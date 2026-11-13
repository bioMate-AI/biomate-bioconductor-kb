"""LLM classification of each workflow's INPUT KINDS into a closed vocabulary.

`workflows.input_types` holds free-form names (real file descriptions for Bioconductor rows, Nextflow
channel names or placeholders such as ["input"] for many nf-core rows), so the router's input-type term
could not tell a raw-spectra pipeline from a processed-table method. This pass writes a normalized
`workflows.input_kinds` JSON list drawn from INPUT_KINDS (unified_workflow_search), read only by that
scoring term; `input_types` is left untouched (chain wiring and the composer use the real names).

Usage:
    PYTHONPATH=lib python3 -m galaxy.ai.chain_composer.input_kinds_classifier \\
        --openrouter-model google/gemini-3.8-flash --workers 16 --output kinds.jsonl
Output rows: {"name", "input_kinds", "reason", "method"}; apply with --apply <db> (guarded by name).
"""
from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Callable, Dict, List, Optional

from .domain_reclassifier import _DEFAULT_DB, assert_fts_consistent, openrouter_llm

# Kept in sync with UnifiedWorkflowSearch._RAW_KINDS / _PROCESSED_KINDS (asserted in tests).
INPUT_KINDS: Dict[str, str] = {
    # raw instrument / sequencer output
    "fastq": "sequencing reads (FASTQ)",
    "bam": "aligned reads (BAM/CRAM/SAM)",
    "raw_spectra": "raw mass-spectrometry data (.raw, .mzML, .mzXML, .d, .wiff)",
    "idat": "Illumina methylation/genotyping array IDAT files",
    "bcl": "Illumina BCL run folders",
    "nanopore_signal": "nanopore signal files (FAST5/POD5)",
    "raw_images": "raw microscopy / micrographs / movies (TIFF, MRC, CZI, ND2)",
    # processed tables / objects produced by an upstream pipeline
    "counts_matrix": "gene/feature count or expression matrix",
    "h5ad": "single-cell object (h5ad, Seurat/SingleCellExperiment RDS, loom)",
    "cellranger_output": "Cell Ranger / 10x output directory or matrix.mtx",
    "protein_table": "protein-level quantification table (MaxQuant proteinGroups, DIA-NN pg_matrix, protein intensities)",
    "peptide_table": "peptide/precursor/PSM-level table (peptides.txt, evidence.txt, DIA-NN report, PSM sheet)",
    "metabolite_table": "metabolite / LC-MS feature intensity table",
    "beta_values": "methylation beta / M-value matrix",
    "vcf": "variant calls (VCF/BCF)",
    "peaks": "peak / interval files (BED, narrowPeak)",
    "gene_list": "gene list or ranked gene statistics",
    # other common inputs
    "fasta": "sequences or reference genome (FASTA)",
    "annotation": "annotation (GTF/GFF)",
    "structure": "molecular structure (PDB/mmCIF)",
    "molecules": "small molecules (SMILES/SDF)",
    "tabular": "other tabular data (clinical, phenotype, generic CSV)",
}

_PROMPT = """You label the INPUT data a bioinformatics workflow consumes, using a closed vocabulary.

WORKFLOW: {name}
SOURCE: {source}
DESCRIPTION: {description}
DECLARED INPUTS: {input_types}
ANNOTATION: {annotation}

Vocabulary (key: meaning):
{vocab}

List the keys for the PRIMARY data the user must supply (not reference files the workflow downloads
itself, not intermediate outputs). Distinguish raw instrument data from processed tables: a pipeline
that starts from mass spectra is raw_spectra; a method that starts from a MaxQuant protein table is
protein_table. Use [] if the inputs cannot be determined.
Reply with ONLY one JSON object: {{"input_kinds": ["<key>", ...], "reason": "<short phrase>"}}"""


# ---------------------------------------------------------------------------
# Deterministic rule-based labeler (hybrid rule-first; the LLM classify() below is the
# refinement layer for rows this leaves unlabelled). Precision over recall: an uncertain row
# returns None (column stays NULL) rather than a guess. Called at INSERT time by the indexers
# so re-indexing a source PRESERVES the data-shape gate instead of reverting input_kinds to NULL.
# ---------------------------------------------------------------------------
import re as _re

# Matrix/count/expression-TABLE input evidence. A downstream analysis tool that consumes a matrix
# must NOT be labelled fastq just because it mentions "RNA-seq" (regression 2026-11-13: linnorm,
# degseq, rcsl were mislabelled {fastq} via a bare rna-seq cue in their tags/description, then the
# step-8a -25 penalty demoted them for a {counts_matrix} user).
_MATRIX_INPUT_CUE = _re.compile(
    r"count matrix|counts matrix|count table|gene counts|raw counts?|expression matrix|"
    r"expression matrices|expression data|pre-?calculated|normali[sz]ed (?:counts|expression)|"
    r"abundance (?:matrix|table)|expression values|expression profile",
    _re.I)
# Genuine RAW-READ evidence (what actually justifies a fastq label).
_RAW_READ_CUE = _re.compile(
    r"\bfastq\b|\.fq\b|raw reads|raw sequencing reads|sequencing reads|paired-?end reads|"
    r"single-?end reads|adapter trimming|read trimming|\bdemultiplex",
    _re.I)
# IVIVE / intrinsic-clearance PK calculators consume a measured-CLint TABLE, not molecules
# (regression 2026-11-13: id 12825 'Ivive Hepatic Clearance' mislabelled {molecules}).
_IVIVE_CUE = _re.compile(
    r"\bivive\b|in vitro[- ]to[- ]in vivo|intrinsic clearance|\bclint\b|hepatic clearance",
    _re.I)

# (keyword pattern, kind). All patterns are scanned; a row may collect several kinds.
_RULE_CUES: List = [
    # fastq requires RAW-READ evidence only — NOT a bare 'rna-seq'/'chip-seq'/'atac-seq' domain word.
    (r"\bfastq\b|\.fq\b|raw reads|raw sequencing reads|sequencing reads|paired-?end reads|"
     r"single-?end reads|adapter trimming|read trimming|\bdemultiplex", "fastq"),
    (r"bam file|cram file|aligned reads|alignment file|sorted bam", "bam"),
    (r"mass spectrom|mzml|mzxml|\.wiff|thermo \.?raw|lc-?ms/?ms spectra|\bdda\b|raw spectra", "raw_spectra"),
    (r"\bidat\b|methylation array|450k array|epic array", "idat"),
    (r"bcl2fastq|illumina run folder|\bbcl\b", "bcl"),
    (r"fast5|pod5|nanopore signal", "nanopore_signal"),
    (r"micrograph|cryo-?em|cryoem|tomogram|\.mrc\b|movie frames|electron microscopy|particle picking", "raw_images"),
    (r"count matrix|counts matrix|gene counts|count table|featurecounts|expression matrix|\bdeseq2?\b|\bedger\b|\blimma\b", "counts_matrix"),
    (r"cell ?ranger|matrix\.mtx|\b10x\b|filtered_feature_bc_matrix", "cellranger_output"),
    (r"h5ad|anndata|\bseurat\b|single-?cell object|\bscanpy\b|singlecellexperiment", "h5ad"),
    (r"proteingroups|protein table|protein quantification|protein abundance|pg_matrix|dia-?nn report", "protein_table"),
    (r"peptide table|peptides\.txt|evidence\.txt|\bpsm\b|precursor table", "peptide_table"),
    (r"metabolite|metabolomics feature|feature intensity table", "metabolite_table"),
    (r"methylation beta|beta-?value|m-?value matrix", "beta_values"),
    (r"vcf file|annotate variants|variant annotation|\.vcf\b|variant calls? table", "vcf"),
    (r"narrowpeak|broadpeak|peak file|called peaks", "peaks"),
    (r"gene list|ranked gene|gene set enrichment|enrichment analysis|over-?representation|\bgsea\b", "gene_list"),
    (r"reference genome|\.fasta\b|protein sequence|amino acid sequence|nucleotide sequence", "fasta"),
    (r"\bgtf\b|\bgff3?\b|gene annotation file", "annotation"),
    (r"\bpdb\b|mmcif|receptor structure|protein structure|crystal structure|apo structure|holo structure|3d structure|molecular dynamics|\bmd simulation|docking|binding pocket", "structure"),
    (r"smiles|\.sdf\b|ligand|small molecule|compound library|chemical library|\badmet\b|virtual screen|scaffold|building blocks|molecular docking|developability", "molecules"),
    (r"assay data|\bic50\b|composite score|assay csv|dose-?response|clinical table|phenotype table", "tabular"),
]
_RULE_PATTERNS = [(_re.compile(p, _re.I), k) for p, k in _RULE_CUES]


def rule_classify_kinds(row: Dict[str, str]) -> Optional[List[str]]:
    """Deterministic, high-precision input-kind labels from a workflow's own metadata
    (name/description/annotation/input_types/tags). Returns a sorted list of INPUT_KINDS keys,
    or None when nothing matches confidently (the LLM pass refines those). NEVER raises."""
    try:
        def _g(k: str) -> str:
            v = row.get(k) if isinstance(row, dict) else getattr(row, k, None)
            return str(v) if v else ""
        blob = " ".join(_g(k) for k in ("name", "description", "annotation", "input_types", "tags")).lower()
        if not blob.strip():
            return None
        found = {kind for pat, kind in _RULE_PATTERNS if pat.search(blob) and kind in INPUT_KINDS}
        # Guard 1: a downstream matrix/count analysis tool that only *mentions* RNA-seq must not keep
        # a fastq label when there is matrix-input evidence and NO genuine raw-read evidence.
        if "fastq" in found and _MATRIX_INPUT_CUE.search(blob) and not _RAW_READ_CUE.search(blob):
            found.discard("fastq")
        # Guard 2: IVIVE / intrinsic-clearance PK calculators consume a measured-parameter TABLE.
        if _IVIVE_CUE.search(blob):
            found.discard("molecules")
            found.discard("structure")
            found.add("tabular")
        return sorted(found) or None
    except Exception:  # noqa: BLE001 — labelling must never break indexing
        return None


def _row_prompt(r: Dict[str, str]) -> str:
    return _PROMPT.format(name=r["name"], source=r["source"] or "unknown", description=(r["description"] or "")[:600],
                          input_types=(r["input_types"] or "[]")[:400], annotation=(r["annotation"] or "")[:400],
                          vocab="\n".join(f"  {k}: {v}" for k, v in INPUT_KINDS.items()))


def parse_kinds(raw: str) -> Optional[Dict]:
    raw = (raw or "").strip()
    i, j = raw.find("{"), raw.rfind("}")
    if i == -1 or j <= i:
        return None
    try:
        d = json.loads(raw[i:j + 1])
    except Exception:  # noqa: BLE001
        return None
    kinds = d.get("input_kinds")
    if not isinstance(kinds, list) or any(k not in INPUT_KINDS for k in kinds):
        return None  # out-of-vocabulary answers are rejected, not coerced
    return {"input_kinds": sorted(set(kinds)), "reason": str(d.get("reason", ""))[:200]}


def classify(db_path: Path, llm: Callable[[str], str], workers: int = 8, limit: Optional[int] = None,
             null_only: bool = False) -> List[Dict]:
    conn = sqlite3.connect(str(db_path))
    where = "WHERE executable=1"
    if null_only:
        # Refinement pass: classify ONLY rows the rule labeler left NULL (preserve rule labels).
        has_col = "input_kinds" in {r[1] for r in conn.execute("PRAGMA table_info(workflows)")}
        if has_col:
            where += " AND input_kinds IS NULL"
    rows = conn.execute("SELECT name, COALESCE(source,''), COALESCE(description,''), COALESCE(input_types,'[]'), "
                        f"COALESCE(annotation,''), id FROM workflows {where} ORDER BY name").fetchall()
    conn.close()
    rows = rows[:limit] if limit else rows

    def one(r):
        d = dict(zip(("name", "source", "description", "input_types", "annotation", "id"), r))
        try:
            p = parse_kinds(llm(_row_prompt(d)))
        except Exception:  # noqa: BLE001
            p = None
        return ({"id": d["id"], "name": d["name"], **p, "method": "llm"} if p
                else {"id": d["id"], "name": d["name"], "input_kinds": None, "reason": "llm_failed", "method": "llm_failed"})

    with ThreadPoolExecutor(max(1, workers)) as ex:
        return list(ex.map(one, rows))


def apply(db_path: Path, results: List[Dict], null_only: bool = False) -> int:
    """Write input_kinds (failed rows untouched). Adds the column if absent. Rows are addressed by id
    (names are not unique); results recorded before ids fall back to the name. With null_only, only
    rows still NULL are written — so an LLM refinement run never clobbers an existing rule label."""
    assert_fts_consistent(db_path)
    conn = sqlite3.connect(str(db_path))
    cols = {r[1] for r in conn.execute("PRAGMA table_info(workflows)")}
    if "input_kinds" not in cols:
        conn.execute("ALTER TABLE workflows ADD COLUMN input_kinds TEXT")
    if "input_kinds_method" not in cols:
        conn.execute("ALTER TABLE workflows ADD COLUMN input_kinds_method TEXT")  # provenance marker
    guard = " AND input_kinds IS NULL" if null_only else ""
    n = 0
    for r in results:
        if r.get("input_kinds") is not None:
            # Stamp provenance 'llm' so a later rule-version self-heal NEVER clobbers this value.
            if r.get("id") is not None:
                n += conn.execute(f"UPDATE workflows SET input_kinds = ?, input_kinds_method = 'llm' "
                                  f"WHERE id = ? AND executable = 1{guard}",
                                  (json.dumps(r["input_kinds"]), r["id"])).rowcount
            else:
                n += conn.execute(f"UPDATE workflows SET input_kinds = ?, input_kinds_method = 'llm' "
                                  f"WHERE name = ? AND executable = 1{guard}",
                                  (json.dumps(r["input_kinds"]), r["name"])).rowcount
    conn.commit()
    conn.close()
    return n


def _cli(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--openrouter-model", default="google/gemini-3.8-flash")
    p.add_argument("--workers", type=int, default=8)
    p.add_argument("--limit", type=int, default=None)
    p.add_argument("--db", default=None, help="DB to classify (defaults to the bundled catalog DB)")
    p.add_argument("--null-only", action="store_true",
                   help="refinement pass: classify/apply ONLY rows with input_kinds IS NULL (preserve rule labels)")
    p.add_argument("--output", required=True, help="JSONL of results (read back with --apply)")
    p.add_argument("--apply", default=None, help="DB path to write input_kinds into, from --output")
    a = p.parse_args(argv)
    if a.apply:
        res = [json.loads(l) for l in open(a.output) if l.strip()]
        sys.stderr.write(f"updated {apply(Path(a.apply), res, null_only=a.null_only)} rows\n")
        return 0
    res = classify(Path(a.db) if a.db else _DEFAULT_DB,
                   openrouter_llm(a.openrouter_model), a.workers, a.limit, null_only=a.null_only)
    with open(a.output, "w") as f:
        for r in res:
            f.write(json.dumps(r) + "\n")
    sys.stderr.write(f"classified {len(res)}; failed {sum(r['method'] != 'llm' for r in res)}\n")
    return 0


if __name__ == "__main__":  # pragma: no cover
    sys.exit(_cli(sys.argv[1:]))
