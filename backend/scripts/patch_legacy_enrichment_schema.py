#!/usr/bin/env python3
"""
patch_legacy_enrichment_schema.py

Patches the 1,749 Bioconductor tools that have scientific_context_v2 in the
OLD schema (when_to_use/data_requirements/key_parameters/… but NO scientific_domain
or keywords). Adds the missing v2 fields using keyword inference — no API calls.

Usage:
    python3 scripts/patch_legacy_enrichment_schema.py [--db /path/to/db] [--dry-run]
"""
import argparse
import json
import re
import sqlite3
from pathlib import Path

DB_DEFAULT = Path(__file__).parent.parent / "database" / "galaxy_ai_tools.db"


def _rebuild_fts(conn: sqlite3.Connection) -> None:
    """Rebuild tools_fts merging scientific_context_v2 keywords into FTS tags slot."""
    tools = conn.execute("""
        SELECT tool_id, name, description, category, parameters, help_text,
               availability_status, tags, edam_operations, edam_topics, scientific_context_v2
        FROM tools
    """).fetchall()
    conn.execute("DELETE FROM tools_fts")

    def _v2_text(raw):
        if not raw:
            return ""
        try:
            ctx = json.loads(raw)
        except Exception:
            return ""
        parts = []
        domain = ctx.get("scientific_domain") or ctx.get("domain")
        if isinstance(domain, str):
            parts.append(domain.replace("_", " "))
        for kw in (ctx.get("keywords") or [])[:10]:
            if isinstance(kw, str) and kw.strip():
                parts.append(kw.strip())
        wtu = ctx.get("when_to_use", "")
        if isinstance(wtu, list):
            parts.extend(str(w)[:80] for w in wtu[:2])
        return " ".join(parts)

    def _tags(raw, extra):
        parts = []
        if raw:
            r = raw.strip()
            if r.startswith("["):
                try:
                    parts.extend(str(i) for i in json.loads(r) if i)
                except Exception:
                    parts.append(r)
            else:
                parts.append(r)
        if extra:
            parts.append(extra)
        return " ".join(parts)[:600]

    conn.executemany("""
        INSERT INTO tools_fts(
            tool_id, name, description, category, parameters, help_text,
            availability_status, tags, edam_operations, edam_topics
        ) VALUES (?,?,?,?,?,?,?,?,?,?)
    """, [
        (r[0], r[1] or "", (r[2] or "")[:800], r[3] or "",
         (r[4] or "")[:400], (r[5] or "")[:400], r[6] or "",
         _tags(r[7], _v2_text(r[10])), r[8] or "", r[9] or "")
        for r in tools
    ])
    conn.commit()


# ── Domain keyword patterns ────────────────────────────────────────────────────
# Applied in order; first match wins.
DOMAIN_RULES = [
    ("single_cell",          r"single.cell|scrna|scatac|seurat|scanpy|anndata|monocle|slingshot|celltypist"),
    ("spatial_transcriptomics", r"spatial.transcriptom|spatialexperiment|visium|merfish|seqfish|xenium"),
    ("epigenomics",          r"chip.?seq|atac.?seq|methylat|bisulfite|dnase|histonem|histone|cpg|chromatin.access|dname|methylGSA|methylKit|ChIP"),
    ("transcriptomics",      r"rna.?seq|rnaseq|mrna|deseq|edger|limma|voom|htseq|featurecounts|tximport|salmon|kallisto|differential.express|transcript|count.matrix|bulk.rna"),
    ("metagenomics",         r"metagenom|microbiome|16s|amplicon|dada2|qiime|phyloseq|metaphlan|kraken|shotgun"),
    ("genomics",             r"\bwgs\b|\bwes\b|\bexome\b|\bsnp\b|\bsnv\b|\bindel\b|\bvcf\b|\bvariant.call|gatk|freebayes|mutect|annovar|vep|cnv|sv.call|genome.assembl|genome.annot"),
    ("population_genetics",  r"gwas|population.genetic|linkage.disequilib|admixture|structure|fst|pca.geno|kinship|grm|relatedness|haplotype|phasing|imputation"),
    ("proteomics",           r"proteom|mass.spec|ms.?ms|peptide|protein.quant|phospho|ubiquitin|mzml|mzxml|maxquant|perseus|dia.nn"),
    ("metabolomics",         r"metabolom|metabolite|lipidome|lipidomic|nmr|lcms|gcms|mzmine|xcms|hmdb|compound.id"),
    ("structural_biology",   r"protein.struct|alphafold|rosetta|molecular.dynamic|md.sim|gromacs|amber|namd|docking|pdb|pymol|fold.predict"),
    ("immunology",           r"immuno|antibod|tcr|bcr|hla|mhc|neoantigen|immunorepert|vdj|clonotype|imgt"),
    ("clinical_genomics",    r"clinical|pathogen|disease.variant|phenotype|omim|clinvar|rare.disease|mendelian|diagnostic|germline.variant|somatic.variant"),
    ("drug_discovery",       r"drug.discov|drug.target|ligand|docking|admet|toxicit|pkpk|pharmacok|ic50|smiles|compound.screen|lead.optim"),
    ("cell_biology",         r"cell.line|flow.cytom|facs|imaging|microscop|organoid|crispr.screen|proliferat|apoptosis"),
    ("neuroscience",         r"neuroscien|neuron|brain|neural|eeg|fmri|synap|axon|dopamin|serotonin"),
    ("other",                r"."),   # catch-all
]

# ── Keyword extraction ─────────────────────────────────────────────────────────
STOPWORDS = {
    # Articles / prepositions / conjunctions
    "the", "a", "an", "and", "or", "for", "with", "of", "in", "on", "to",
    "is", "are", "be", "by", "from", "at", "as", "its",
    # Common verbs
    "use", "used", "using", "can", "will", "may", "should", "must",
    "provides", "provide", "allows", "allow", "enables", "enable",
    "perform", "performs", "support", "supports", "include", "includes",
    "including", "require", "requires", "run", "runs",
    # Pronouns / demonstratives
    "this", "that", "which", "when", "where", "these", "those",
    # Generic domain words (too broad to be useful keywords)
    "data", "analysis", "test", "tests", "statistical", "statistics",
    "package", "function", "method", "approach", "tool", "tools",
    "results", "result", "output", "outputs", "input", "inputs",
    "file", "files", "sample", "samples", "dataset", "datasets",
    "based", "between", "within", "across", "two", "more", "all",
    "each", "also", "such", "well", "set", "sets", "user", "users",
    # Template artifacts from the legacy schema prompt
    "name", "default", "guidance", "note", "notes", "general",
    "specific", "given", "example", "examples", "type", "types",
    "value", "values", "parameter", "parameters", "information",
    "available", "provided", "common", "multiple", "single", "one",
    "new", "different", "various", "other", "same", "high", "low",
    "large", "small", "number", "count", "list", "object", "objects",
    # JSON/template literal artifacts
    "none", "null", "true", "false", "via", "nan", "yes", "no",
}


def infer_domain(text: str) -> str:
    t = text.lower()
    for domain, pattern in DOMAIN_RULES:
        if re.search(pattern, t):
            return domain
    return "other"


def extract_keywords(data: dict, name: str) -> list[str]:
    """Pull meaningful terms from the legacy enrichment blob."""
    parts = [name]
    for key in ("when_to_use", "data_requirements", "key_parameters", "when_not_to_use"):
        val = data.get(key, "")
        if isinstance(val, list):
            parts.extend(val)
        elif isinstance(val, str):
            parts.append(val)

    raw_text = " ".join(str(p) for p in parts)
    # Tokenise: keep alpha tokens of length 3+
    tokens = re.findall(r"[a-zA-Z][a-zA-Z0-9\-]{2,}", raw_text)
    seen: dict[str, int] = {}
    for tok in tokens:
        t = tok.lower()
        if t not in STOPWORDS:
            seen[t] = seen.get(t, 0) + 1

    # Sort by frequency, take top 12 unique terms; include package name first
    sorted_terms = sorted(seen.items(), key=lambda x: -x[1])
    kw = [name.lower()]
    for term, _ in sorted_terms:
        if term not in kw:
            kw.append(term)
        if len(kw) >= 12:
            break
    return kw


def infer_inputs(data: dict) -> list[str]:
    req = data.get("data_requirements", "")
    text = " ".join(req) if isinstance(req, list) else str(req)
    inputs = []
    for fmt, pat in [
        ("count matrix", r"count.matrix|expression.matrix|raw.count"),
        ("BAM/SAM", r"\bbam\b|\bsam\b|\balignment"),
        ("FASTQ", r"\bfastq\b"),
        ("VCF", r"\bvcf\b"),
        ("FASTA", r"\bfasta\b"),
        ("BED", r"\bbed\b"),
        ("CSV/TSV", r"\bcsv\b|\btsv\b|\bspreadsheet"),
        ("AnnData/h5ad", r"anndata|\bh5ad\b|\bseurat.object"),
        ("SummarizedExperiment", r"summarizedexperiment|rangedse|se.object"),
        ("MSA", r"\bmsa\b|multiple.sequence"),
        ("PDB", r"\bpdb\b|structure.file"),
    ]:
        if re.search(pat, text, re.I):
            inputs.append(fmt)
    return inputs or ["tabular data"]


def patch(db_path: Path, dry_run: bool) -> None:
    conn = sqlite3.connect(db_path)
    rows = conn.execute("""
        SELECT tool_id, name, scientific_context_v2
        FROM tools
        WHERE scientific_context_v2 IS NOT NULL AND scientific_context_v2 != ''
          AND JSON_EXTRACT(scientific_context_v2, '$.scientific_domain') IS NULL
    """).fetchall()

    print(f"Found {len(rows)} tools with legacy schema to patch")
    updated = 0
    errors = 0

    for tool_id, name, raw in rows:
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            errors += 1
            continue

        # Gather signal text for inference
        all_text = " ".join([
            name,
            str(data.get("when_to_use", "")),
            str(data.get("data_requirements", "")),
            str(data.get("key_parameters", "")),
        ])

        domain = infer_domain(all_text)
        keywords = extract_keywords(data, name)
        primary_inputs = infer_inputs(data)

        # Patch: add missing v2 fields without touching existing keys
        data["scientific_domain"] = domain
        data["keywords"] = keywords
        if "primary_inputs" not in data:
            data["primary_inputs"] = primary_inputs
        if "primary_outputs" not in data:
            data["primary_outputs"] = ["R object", "plots", "tables"]
        if "package" not in data:
            data["package"] = name

        if dry_run:
            print(f"  DRY  {name} → domain={domain}  kw={keywords[:4]}")
            updated += 1
            continue

        conn.execute(
            "UPDATE tools SET scientific_context_v2 = ? WHERE tool_id = ?",
            (json.dumps(data), tool_id),
        )
        updated += 1
        if updated % 100 == 0:
            conn.commit()
            print(f"  {updated}/{len(rows)} patched…")

    conn.commit()
    print(f"\nPatched: {updated}, Errors: {errors}")

    if not dry_run and updated > 0:
        print("Rebuilding tools_fts…")
        _rebuild_fts(conn)
        print("FTS rebuilt.")

    conn.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default=str(DB_DEFAULT))
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    db_path = Path(args.db)
    if not db_path.exists():
        raise SystemExit(f"DB not found: {db_path}")
    patch(db_path, args.dry_run)
