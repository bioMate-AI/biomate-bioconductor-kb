"""Named-entity extraction over user queries.

Replaces the hard-coded `_SPECIFICITY_TERMS` vocabulary in composer.py with
LLM-extracted structured entities. The extracted entities serve two purposes:

1. Compute `query_specificity` for the confidence scorer (more entities → more specific).
2. Augment retrieval — entities found in pattern/chain text get a score boost.

The prototype ships:
- A small deterministic regex/dictionary fallback (`extract_entities_offline`)
  that works without an LLM — covers common cases for tests + offline dev.
- An LLM path (`extract_entities`) that returns a richer structured object
  when an `llm` callable is supplied.

Both paths return the same `QueryEntities` dataclass so downstream code is
LLM-agnostic.
"""

from __future__ import annotations

import json
import re
from dataclasses import asdict, dataclass, field
from typing import Any, Callable, Dict, List, Optional


@dataclass
class QueryEntities:
    """Structured entities extracted from a user query."""

    organisms: List[str] = field(default_factory=list)         # human, mouse, Drosophila
    modalities: List[str] = field(default_factory=list)        # RNA-seq, ATAC-seq, scRNA, proteomics
    tools: List[str] = field(default_factory=list)             # DESeq2, Seurat, GATK, MOFA
    data_types: List[str] = field(default_factory=list)        # fastq, bam, vcf, h5ad, counts_matrix, SMILES
    contrasts: List[str] = field(default_factory=list)         # treated vs control, tumor vs normal, KO vs WT
    cohorts: List[str] = field(default_factory=list)           # TCGA, GTEx, UK Biobank, FinnGen
    analyses: List[str] = field(default_factory=list)          # DE, enrichment, variant calling, ADMET, docking
    assemblies: List[str] = field(default_factory=list)        # GRCh38, hg19, mm10
    intent: str = ""                                            # one-line summary of what the user is trying to do

    def all_terms(self) -> List[str]:
        """Flat list of every extracted term, lowercased — used as retrieval boost keys."""
        out: List[str] = []
        for fld in ("organisms", "modalities", "tools", "data_types",
                    "contrasts", "cohorts", "analyses", "assemblies"):
            for v in getattr(self, fld):
                if isinstance(v, str) and v.strip():
                    out.append(v.strip().lower())
        return out

    def specificity_score(self) -> float:
        """Map entity count to a 0..1 score for the confidence signal."""
        n = len(self.all_terms())
        # 0 entities → 0.0; 5+ entities → 1.0; linear in between.
        return min(1.0, n / 5.0)

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


# ─────────────────────────────────────────────────────────────────────────
# Offline / deterministic path — dictionaries are intentionally narrow.
# Real expressiveness comes from the LLM path. This is for tests + the
# zero-API-key prototype demo.
# ─────────────────────────────────────────────────────────────────────────

_DICTS: Dict[str, List[str]] = {
    "organisms": [
        "human", "mouse", "rat", "yeast", "zebrafish", "drosophila", "fly",
        "arabidopsis", "c. elegans", "celegans", "e. coli", "ecoli",
        "macaque", "rhesus", "monkey", "pig", "rabbit", "dog",
    ],
    "modalities": [
        "rna-seq", "rnaseq", "atac-seq", "atacseq", "chip-seq", "chipseq",
        "scrna", "scrnaseq", "single-cell", "snrna", "cite-seq", "citeseq",
        "wgs", "wes", "wgbs", "rrbs", "methyl-seq",
        "cut&tag", "cutandtag", "cut&run", "cutandrun",
        "proteomics", "metabolomics", "lipidomics", "phosphoproteomics",
        "spatial", "spatial-transcriptomics", "visium", "merfish",
    ],
    "tools": [
        "deseq2", "edger", "limma", "voom", "salmon", "kallisto", "star",
        "hisat2", "bwa", "bowtie2", "macs2", "macs3", "seurat", "scanpy",
        "harmony", "mofa", "diablo", "scvi", "signac",
        "gatk", "haplotypecaller", "mutect2", "strelka", "deepvariant",
        "vep", "snpeff", "clinvar",
        "clusterprofiler", "enrichgo", "enrichkegg", "reactomepa", "fgsea",
        "cellranger", "starsolo", "alevin",
    ],
    "data_types": [
        "fastq", "fastq.gz", "bam", "cram", "sam", "vcf", "bcf",
        "h5ad", "h5", "mtx", "rds", "loom",
        "counts_matrix", "count matrix", "tpm", "fpkm",
        "smiles", "sdf", "pdb", "mol2",
        "samplesheet", "metadata", "bed", "bigwig", "gtf", "gff",
    ],
    "contrasts": [
        "tumor vs normal", "tumor-normal", "case vs control", "case-control",
        "treated vs control", "treatment vs control",
        "ko vs wt", "ko-wt", "knockout", "wildtype",
        "before vs after", "pre vs post", "baseline",
    ],
    "cohorts": [
        "tcga", "gtex", "icgc", "uk biobank", "ukbiobank", "ukb",
        "finngen", "bbj", "biobank japan", "1000 genomes", "1kg",
        "encode", "roadmap epigenomics",
    ],
    "analyses": [
        "differential expression", "de analysis", "deg",
        "enrichment", "pathway", "gsea", "go analysis",
        "variant calling", "snv calling", "indel",
        "admet", "docking", "screening", "virtual screening",
        "qc", "alignment", "quantification",
        "clustering", "trajectory", "cell typing", "annotation",
        "peak calling", "binding", "co-expression",
        "meta-analysis", "replication", "validation",
        "biomarker discovery", "biomarker validation",
        # verb forms (queries often use action language)
        "validate", "validate biomarkers", "validating",
        "biomarker", "biomarkers", "biomarker discovery",
        "replicate", "replicating", "pool", "pooling",
        "discovery cohort", "validation cohort", "hold-out",
        # branching-on-QC cues for retrieval (also useful as entities)
        "rrna", "ribosomal rna", "rrna depletion", "rrna contamination",
        "contamination", "depletion",
        # cryoEM
        "single particle analysis", "spa", "particle picking",
        "ctf estimation", "ctf", "motion correction", "motioncor",
        "3d refinement", "3d classification", "3d variability",
        "conformational heterogeneity", "helical reconstruction",
        "focused refinement", "cryosparc", "relion", "cryodrgn",
        # pharmacology / drug development
        "pbpk", "pbpk simulation", "ddi", "cyp450", "cyp inhibition",
        "ic50", "ec50", "hepatic clearance", "dose-response",
        "dose response", "exposure-response", "virtual patient",
        "phase ii", "phase iii", "clinical trial design",
        "phase 2 dose justification", "renal impairment",
        "hepatic impairment", "trial simulation", "pkpd",
        # drug discovery / chemistry
        "antibody developability", "scaffold hopping", "lead optimization",
        "matched molecular pair", "mmp", "codon optimization",
        "mrna therapeutic", "ivt", "alphafold", "target tractability",
        "high-content screening", "hts", "plate qc", "hit calling",
        "fragment", "recap fragmentation", "synthesizability",
        # imaging / spatial / flow
        "merfish", "spatial transcriptomics", "spatial",
        "flow cytometry", "mass cytometry", "cytof", "fcs",
        "tissue segmentation", "cell painting",
        # metagenomics / microbiome
        "metagenomics", "16s", "shotgun metagenomics", "amplicon",
        "concoct", "binning", "contig", "mmseqs", "taxonomy",
        "microbiome", "abundance",
        # single cell flavors
        "cite-seq", "citeseq", "mars-seq", "marsseq", "10x",
        "cellranger", "spatial transcriptomics", "smart-seq",
    ],
    "assemblies": [
        "grch38", "grch37", "hg38", "hg19", "mm10", "mm9", "mm39",
        "dm6", "danrer11", "wbcel235", "saccer3",
    ],
}


def _find_matches(query: str, terms: List[str]) -> List[str]:
    q = query.lower()
    hits: List[str] = []
    for t in terms:
        # Word-ish boundary check to avoid "rna" matching "Lorna".
        if re.search(rf"\b{re.escape(t)}\b", q):
            hits.append(t)
    # Dedupe preserving order.
    seen = set()
    out = []
    for h in hits:
        if h not in seen:
            seen.add(h)
            out.append(h)
    return out


def extract_entities_offline(query: str) -> QueryEntities:
    """Deterministic dictionary-based extraction. No LLM required."""
    return QueryEntities(
        organisms=_find_matches(query, _DICTS["organisms"]),
        modalities=_find_matches(query, _DICTS["modalities"]),
        tools=_find_matches(query, _DICTS["tools"]),
        data_types=_find_matches(query, _DICTS["data_types"]),
        contrasts=_find_matches(query, _DICTS["contrasts"]),
        cohorts=_find_matches(query, _DICTS["cohorts"]),
        analyses=_find_matches(query, _DICTS["analyses"]),
        assemblies=_find_matches(query, _DICTS["assemblies"]),
        intent=query.strip()[:160],
    )


# ─────────────────────────────────────────────────────────────────────────
# LLM path — richer extraction with structured JSON output.
# ─────────────────────────────────────────────────────────────────────────

_NER_PROMPT = """You are a biomedical entity extraction assistant for a workflow planner.

Given the USER QUERY below, extract structured biological entities. Use canonical
forms (e.g. "GRCh38" not "human genome"; "RNA-seq" not "transcriptomics"; "DESeq2"
not "deseq"). Omit entities not present in the query — do not hallucinate.

USER QUERY:
{query}

Return ONLY a JSON object with these keys (use empty arrays for unknown fields):
{{
  "organisms": ["..."],          // e.g. human, mouse
  "modalities": ["..."],         // e.g. RNA-seq, scRNA, ATAC-seq, proteomics
  "tools": ["..."],              // e.g. DESeq2, Seurat, GATK
  "data_types": ["..."],         // e.g. fastq, bam, vcf, counts_matrix, SMILES
  "contrasts": ["..."],          // e.g. tumor vs normal, KO vs WT
  "cohorts": ["..."],            // e.g. TCGA, UK Biobank
  "analyses": ["..."],           // e.g. differential expression, enrichment, docking
  "assemblies": ["..."],         // e.g. GRCh38, mm10
  "intent": "one-sentence summary of what the user wants"
}}
"""


def extract_entities(
    query: str,
    llm: Optional[Callable[[str], str]] = None,
) -> QueryEntities:
    """Extract entities using the LLM if provided; otherwise fall back to offline.

    Always merges LLM output with the offline pass — the offline path catches
    canonical terms the LLM might paraphrase away (e.g. user writes "hg38"
    but LLM normalizes to "GRCh38" only).
    """
    offline = extract_entities_offline(query)
    if llm is None:
        return offline

    try:
        raw = llm(_NER_PROMPT.format(query=query))
        data = _parse_json_loose(raw)
    except Exception:
        return offline
    if not isinstance(data, dict):
        return offline

    merged = QueryEntities(
        organisms=_merge(offline.organisms, data.get("organisms")),
        modalities=_merge(offline.modalities, data.get("modalities")),
        tools=_merge(offline.tools, data.get("tools")),
        data_types=_merge(offline.data_types, data.get("data_types")),
        contrasts=_merge(offline.contrasts, data.get("contrasts")),
        cohorts=_merge(offline.cohorts, data.get("cohorts")),
        analyses=_merge(offline.analyses, data.get("analyses")),
        assemblies=_merge(offline.assemblies, data.get("assemblies")),
        intent=str(data.get("intent") or offline.intent),
    )
    return merged


def _merge(offline: List[str], llm_list: Any) -> List[str]:
    """Combine offline + LLM lists, dedupe case-insensitively, preserve order."""
    seen = set()
    out: List[str] = []
    for src in (offline, llm_list if isinstance(llm_list, list) else []):
        for item in src:
            if not isinstance(item, str):
                continue
            key = item.strip().lower()
            if not key or key in seen:
                continue
            seen.add(key)
            out.append(item.strip())
    return out


def _parse_json_loose(raw: str) -> Any:
    """Pull a JSON object out of LLM output even if wrapped in code fences."""
    raw = (raw or "").strip()
    fence = re.match(r"^```(?:json)?\s*(.*?)\s*```$", raw, re.DOTALL)
    if fence:
        raw = fence.group(1).strip()
    # If there's prose around the JSON, grab the first balanced {...} blob.
    if not raw.startswith("{"):
        m = re.search(r"\{.*\}", raw, re.DOTALL)
        if m:
            raw = m.group(0)
    return json.loads(raw)
