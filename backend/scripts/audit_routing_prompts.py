"""Routing regression audit for the 2026-11-12/13 scoring changes (chemistry-regime data gate,
developability vocab, gated rank boost, self-healing input_kinds). Scores representative prompts
against the real catalog DB WITH and WITHOUT the user's perceived input kinds, printing top-5, so a
human can confirm the GLOBAL scoring changes did not mis-route unrelated domains.

Usage: PYTHONPATH=lib python3 scripts/audit_routing_prompts.py [db_path]
"""
import sys
from pathlib import Path

from galaxy.ai.unified_workflow_search import UnifiedWorkflowSearch

DB = sys.argv[1] if len(sys.argv) > 1 else "/Users/kky/biomate/backend/database/galaxy_ai_tools.db"

CASES = [
    ("RNA-seq (fastq)",        "Run differential expression on my RNA-seq FASTQ files, KO vs WT", ["fastq"]),
    ("proteomics (raw)",       "Quantify proteins from my Thermo .raw mass-spectrometry files, KO vs WT", ["raw_spectra"]),
    ("proteomics (table)",     "Find differentially abundant proteins from my MaxQuant proteinGroups.txt", ["protein_table"]),
    ("variant (vcf)",          "Annotate and prioritise the variants in my VCF file", ["vcf"]),
    ("scRNA (h5ad)",           "Cluster my single-cell RNA-seq h5ad object and annotate cell types", ["h5ad"]),
    ("docking (mol+struct)",   "Dock this ligand library against my receptor structure", ["molecules", "structure"]),
    ("ADMET (molecules)",      "Predict ADMET properties for these SMILES compounds", ["molecules"]),
    ("REAL assay-rank (table)","Rank these compounds by composite potency and hERG safety from my assay IC50 table", ["tabular"]),
    ("incident developability","Rank these 500 candidates for developability and show me the top 20.", ["molecules", "structure"]),
]


def main():
    s = UnifiedWorkflowSearch(db_path=Path(DB))
    for label, q, uik in CASES:
        print("=" * 100)
        print(f"{label}: {q!r}")
        for tag, kinds in ((f"uik={uik}", uik), ("uik=None", None)):
            res = s.search(q, limit=5, user_input_kinds=kinds)
            print(f"  [{tag}]")
            for i, m in enumerate(res):
                print(f"    {i+1}. id={getattr(m,'id',None):<6} {m.score:6.1f}  {m.name[:52]}  [{m.domain}]")


if __name__ == "__main__":
    main()
