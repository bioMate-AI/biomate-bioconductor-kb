#!/usr/bin/env python3
"""
run_workflow_output_audit.py — BioMate Workflow Output Element Evaluation Harness

Evaluates whether BioMate workflow stubs declare outputs that are:
  1. Aligned with the publications cited in the workflow header
  2. Complete (all expected file types for the domain are present)
  3. Scientifically meaningful (visualizations, QC metrics, reports)

This is a STATIC ANALYSIS benchmark — no workflow execution required.
It parses each .nf file and checks declared outputs against domain-specific
ground truth derived from the primary methodology publications.

Scope:
  - T1–T7 tutorial cases (the 7 core domains)
  - Per-domain expected outputs from publications
  - Coverage scoring: how many expected elements are declared?

Usage
-----
    python scripts/run_workflow_output_audit.py
    python scripts/run_workflow_output_audit.py --verbose
    python scripts/run_workflow_output_audit.py --domain rnaseq,single_cell

Scoring
-------
Each workflow is scored on 5 dimensions (0-100 each):
  1. required_outputs   — fraction of required output file types declared
  2. visualization      — key visualization files present (UMAP, volcano, etc.)
  3. qc_report         — QC metrics or report file declared
  4. methods_report    — methods/summary HTML/PDF declared
  5. phase_structure   — has named phases aligning with the methodology

Overall score = average of all 5 dimensions.
Target: ≥ 80 per dimension for all T1–T7 workflows.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

BACKEND_ROOT = Path(__file__).resolve().parents[1] / "backend"
BIOMNI_WF    = BACKEND_ROOT / "biomni_workflows"

# ── Publication-derived expected outputs per domain ───────────────────────────
# Each entry is (required_patterns, viz_patterns, qc_patterns, report_patterns, phase_keywords)
# Patterns are checked against declared `emit:` names AND file extensions in output paths.
# Ground truth references:
#   rnaseq:         nf-core/rnaseq (Ewels 2020 Nat Biotechnol); STAR (Dobin 2013);
#                   DESeq2 (Love 2014 Genome Biol); MultiQC (Ewels 2016)
#   single_cell:    Harmony (Korsunsky 2019 Nat Methods); scDblFinder (Germain 2021);
#                   CellTypist (Conde 2022 Science); iSEE (Rue-Albrecht 2018)
#   variant_calling:sarek (Garcia 2020 F1000); GATK (McKenna 2010 Genome Res);
#                   VEP (McLaren 2016 Genome Biol); MultiQC
#   epigenomics:    nf-core/chipseq; MACS2 (Zhang 2008 Genome Biol);
#                   DeepTools (Ramírez 2016 Nucleic Acids Res); ChIPseeker (Yu 2015)
#   proteomics:     nf-core/proteomicslfq; MSstats (Choi 2014 MCP);
#                   OpenMS (Röst 2016 Nat Methods); DESeq2-equivalent
#   metagenomics:   nf-core/mag (Krakau 2022); CheckM (Parks 2015 Genome Res);
#                   GTDB-Tk (Chaumeil 2019 Bioinformatics); MultiQC
#   metabolomics:   XCMS (Smith 2006 Anal Chem); MZmine (Pluskal 2010);
#                   CAMERA (Kuhl 2012)

DOMAIN_EXPECTED: Dict[str, Dict[str, Any]] = {
    "rnaseq": {
        "description": "RNA-seq: raw FASTQ → count matrix → differential expression",
        "citations": [
            "STAR: Dobin et al. 2013 Bioinformatics 29(1):15–21",
            "DESeq2: Love et al. 2014 Genome Biol 15(12):550",
            "nf-core/rnaseq: Ewels et al. 2020 Nat Biotechnol 38:276–278",
        ],
        # Required: at least one of each group must be present
        "required_output_groups": [
            ["bam", "sam", "cram"],          # alignment
            ["counts", "matrix", "quant"],   # quantification
            ["multiqc", "qc_report", "html"], # report
        ],
        # Real nf-core/rnaseq outputs: bigWig coverage tracks (BEDTools), PCA/clustering
        # PDFs (DESeq2 QC), dupRadar PDFs, RSeQC PDFs. Volcano/MA plots are NOT
        # produced by the pipeline itself — those come from downstream DE analysis.
        "viz_patterns":   ["pca", "heatmap", "bigwig", "pdf", "png"],
        "qc_patterns":    ["multiqc", "fastp", "trimgalore", "fastqc", "flagstat"],
        "report_patterns":["multiqc", "html", "report"],
        "phase_keywords": ["trimming", "alignment", "quantification", "qc", "report"],
        "key_tools":      ["star", "hisat2", "salmon", "deseq2", "edger", "featurecounts"],
    },
    "single_cell": {
        "description": "scRNA-seq: FASTQ/CellRanger → annotated h5ad with cell types",
        "citations": [
            "Harmony: Korsunsky et al. 2019 Nat Methods 16:1289–1296",
            "scDblFinder: Germain et al. 2021 F1000Research 10:979",
            "CellTypist: Domínguez Conde et al. 2022 Science 376:eabl5197",
            "iSEE: Rue-Albrecht et al. 2018 F1000Research 7:741",
        ],
        "required_output_groups": [
            ["h5ad", "h5", "loom", "rds"],   # single-cell data object
            ["celltype", "annotation", "cluster", "leiden"],  # cell type labels
            ["marker", "deg", "hvg"],        # marker genes
        ],
        "viz_patterns":   ["umap", "tsne", "pca", "violin", "dotplot", "heatmap", "png", "pdf"],
        "qc_patterns":    ["qc", "doublet", "mito", "metrics"],
        "report_patterns":["report", "html", "isee", "shiny"],
        "phase_keywords": ["qc", "clustering", "annotation", "integration", "doublet"],
        "key_tools":      ["cellranger", "starsolo", "scdblfinder", "harmony", "celltypist", "isee"],
    },
    "variant_calling": {
        "description": "Germline variant calling: WGS/WES FASTQ → annotated VCF",
        "citations": [
            "GATK HaplotypeCaller: McKenna et al. 2010 Genome Res 20(9):1297–1303",
            "VEP: McLaren et al. 2016 Genome Biol 17(1):122",
            "nf-core/sarek: Garcia et al. 2020 F1000Research 9:963",
        ],
        "required_output_groups": [
            ["vcf", "gvcf", "bcf"],          # variant calls
            ["bam", "cram"],                 # alignment
            ["html", "multiqc", "report"],   # QC report
        ],
        # Real sarek outputs: ASCAT PNGs, CNVKit PDFs/PNGs, Control-FREEC PNGs,
        # mosdepth coverage, bcftools stats, VCF.gz + TBI. MultiQC HTML is the report.
        "viz_patterns":   ["png", "pdf", "summary", "stats"],
        "qc_patterns":    ["multiqc", "fastqc", "mosdepth", "samtools", "flagstat", "bcftools"],
        "report_patterns":["multiqc", "html", "report", "summary"],
        # Note: keywords use spaces to match phase comments (e.g. "Variant Calling")
        "phase_keywords": ["preprocessing", "alignment", "variant calling", "annotation", "report"],
        "key_tools":      ["bwa", "gatk", "haplotypecaller", "vep", "bcftools"],
    },
    "epigenomics": {
        "description": "ChIP-seq: FASTQ → peaks → annotation → enrichment",
        "citations": [
            "MACS2: Zhang et al. 2008 Genome Biol 9:R137",
            "DeepTools: Ramírez et al. 2016 Nucleic Acids Res 44(W1):W160–5",
            "ChIPseeker: Yu et al. 2015 Bioinformatics 31(14):2382–3",
        ],
        "required_output_groups": [
            ["peak", "narrowpeak", "broadpeak", "bed"],  # peak calls
            ["bam"],                                     # alignment
            ["annotation", "chipseeker", "homer"],       # peak annotation
        ],
        # Real nf-core/chipseq outputs: BAM, bigWig (deepTools bamCoverage), narrowPeak/
        # broadPeak (MACS3), HOMER annotatePeaks.txt, phantompeakqualtools cross-corr PDFs,
        # deepTools plotFingerprint + plotProfile PDFs, DESeq2 PCA PDFs, MultiQC HTML.
        "viz_patterns":   ["png", "pdf", "heatmap", "profile", "fingerprint", "bigwig"],
        "qc_patterns":    ["multiqc", "fastqc", "flagstat", "phantompeakqualtools"],
        "report_patterns":["html", "multiqc", "report"],
        # Note: use spaces to match phase comments like "// [Peak Calling]"
        "phase_keywords": ["alignment", "peak calling", "annotation", "qc"],
        "key_tools":      ["bwa", "macs2", "deeptools", "chipseeker", "homer"],
    },
    "proteomics": {
        "description": "Label-free proteomics: mzML/RAW → peptide/protein quantification → DE",
        "citations": [
            "MSstats: Choi et al. 2014 MCP 13(8):2207–23",
            "OpenMS: Röst et al. 2016 Nat Methods 13:741–748",
            "nf-core/proteomicslfq: Pfeuffer et al.",
        ],
        "required_output_groups": [
            ["protein", "peptide", "msstats", "tsv", "csv"],  # quantification
            ["mzml", "idxml", "featurexml"],                   # raw/intermediate
            ["html", "report", "qc"],                          # report
        ],
        # Real nf-core/proteomicslfq outputs: idXML (Comet PSMs), out.mzTab (OpenMS LFQ),
        # msstats_results.csv, VolcanoPlot.pdf + Heatmap.pdf + ComparisonPlot.pdf (MSstats),
        # PTXQC report.html + report.pdf, MultiQC HTML.
        "viz_patterns":   ["png", "pdf", "volcano", "heatmap", "pca"],
        "qc_patterns":    ["ptxqc", "html", "multiqc"],
        "report_patterns":["html", "report", "msstats"],
        # Note: use spaces to match phase comments
        "phase_keywords": ["database search", "quantification", "statistical analysis", "report"],
        "key_tools":      ["openms", "comet", "percolator", "msstats"],
    },
    "metagenomics": {
        "description": "Shotgun metagenomics: FASTQ → MAG assembly → binning → taxonomy",
        "citations": [
            "CheckM: Parks et al. 2015 Genome Res 25(7):1043–55",
            "GTDB-Tk: Chaumeil et al. 2019 Bioinformatics 36(6):1925–7",
            "MetaBAT2: Kang et al. 2019 PeerJ 7:e7359",
            "nf-core/mag: Krakau et al. 2022 NAR Genomics Bioinformatics 4(1):lqac007",
        ],
        "required_output_groups": [
            ["bin", "mag", "fa", "fasta", "contigs"],  # MAG bins
            ["checkm", "quality", "completeness"],      # quality assessment
            ["gtdb", "taxonomy", "lineage"],            # taxonomy
        ],
        # Real nf-core/mag outputs: *.contigs.fa.gz (MEGAHIT/SPAdes), bins/*.fa.gz (MetaBAT2),
        # checkm_summary.tsv (CheckM completeness/contamination), GTDB-Tk summary.tsv
        # (lineage classification), bin depth heatmap PNGs (BEDTools + R), MultiQC HTML.
        "viz_patterns":   ["png", "pdf", "html", "multiqc"],
        "qc_patterns":    ["multiqc", "fastqc", "checkm"],
        "report_patterns":["multiqc", "html", "report"],
        # Note: use spaces; "qc" must appear as substring in a phase comment like "// [QC]"
        "phase_keywords": ["qc", "assembly", "binning", "taxonomy", "report"],
        "key_tools":      ["fastp", "megahit", "spades", "metabat2", "checkm", "gtdbtk"],
    },
    "metabolomics": {
        "description": "Untargeted LC-MS metabolomics: raw → features → annotation → enrichment",
        "citations": [
            "XCMS: Smith et al. 2006 Anal Chem 78(3):779–87",
            "MZmine: Pluskal et al. 2010 BMC Bioinformatics 11:395",
            "CAMERA: Kuhl et al. 2012 Anal Chem 84(1):283–9",
        ],
        "required_output_groups": [
            ["feature", "mztab", "csv", "tsv"],  # feature table
            ["annotation", "sirius", "hmdb"],    # annotation
            ["html", "report", "qc"],            # report
        ],
        "viz_patterns":   ["png", "pdf", "html", "pca", "heatmap"],
        "qc_patterns":    ["qc", "rsd", "blank"],
        "report_patterns":["html", "report"],
        "phase_keywords": ["preprocessing", "feature_detection", "alignment", "annotation"],
        "key_tools":      ["xcms", "mzmine", "camera", "sirius"],
    },
}

# ── Tutorial case → workflow file mapping ─────────────────────────────────────
TUTORIAL_CASES = {
    "T1_rnaseq":          "nfcore/rnaseq/main.nf",
    "T2_single_cell":     "nextflow_nfcore/subworkflows/single_cell/scrnaseq_standard_endtoend/main.nf",
    "T3_variant_calling": "nfcore/sarek/main.nf",
    "T4_epigenomics":     "nfcore/chipseq/main.nf",
    "T5_proteomics":      "nfcore/proteomicslfq/main.nf",
    "T6_metagenomics":    "nfcore/mag/main.nf",
    "T7_metabolomics":    "nextflow_nfcore/subworkflows/multi_omics/lc_ms_proteomics_metabolomics/main.nf",
}

# Domain for each tutorial case
TUTORIAL_DOMAIN = {
    "T1_rnaseq":          "rnaseq",
    "T2_single_cell":     "single_cell",
    "T3_variant_calling": "variant_calling",
    "T4_epigenomics":     "epigenomics",
    "T5_proteomics":      "proteomics",
    "T6_metagenomics":    "metagenomics",
    "T7_metabolomics":    "metabolomics",
}


@dataclass
class WorkflowOutputAudit:
    case_id: str
    domain: str
    nf_path: Optional[Path]
    declared_outputs: List[str] = field(default_factory=list)
    declared_processes: List[str] = field(default_factory=list)
    declared_phases: List[str] = field(default_factory=list)
    declared_params: List[str] = field(default_factory=list)
    scores: Dict[str, int] = field(default_factory=dict)
    findings: List[str] = field(default_factory=list)
    missing: List[str] = field(default_factory=list)


def _parse_nf_file(nf_path: Path) -> Dict[str, Any]:
    """Extract declared outputs, processes, phases, and params from a .nf file."""
    text = nf_path.read_text(encoding="utf-8", errors="replace")

    # Extract emit: names and output path strings
    emit_names = re.findall(r'\bemit:\s*(\w+)', text)
    output_paths = re.findall(r'path\s*"([^"]+)"', text)  # path("some_file.ext")
    output_paths += re.findall(r"path\s*'([^']+)'", text)

    # Extract process names
    processes = re.findall(r'^process\s+([A-Za-z][A-Za-z0-9_]+)\s*\{', text, re.MULTILINE)

    # Extract phase comments  // [Phase Name]
    phases = re.findall(r'//\s*\[([A-Za-z][A-Za-z0-9 _-]*)\]', text)

    # Extract flat params
    params = re.findall(r'^params\.(\w+)\s*=', text, re.MULTILINE)

    # All declared identifiers (lower-cased for matching)
    all_ids = set(e.lower() for e in emit_names)
    all_ids.update(p.lower() for p in output_paths)
    all_ids.update(pr.lower() for pr in processes)

    return {
        "emit_names":    [e.lower() for e in emit_names],
        "output_paths":  [p.lower() for p in output_paths],
        "processes":     [p.lower() for p in processes],
        "phases":        [ph.lower() for ph in phases],
        "params":        [p.lower() for p in params],
        "all_ids":       all_ids,
        "raw_text":      text.lower(),
    }


def _score_required_outputs(parsed: Dict, expected: Dict) -> Tuple[int, List[str], List[str]]:
    """Check required output groups. Each group is OR'd; all groups must be satisfied."""
    groups = expected.get("required_output_groups", [])
    if not groups:
        return 100, [], []

    raw = parsed["raw_text"]
    satisfied = 0
    found_items = []
    missing_items = []

    for group in groups:
        group_matched = False
        for token in group:
            if token in raw:
                group_matched = True
                found_items.append(token)
                break
        if group_matched:
            satisfied += 1
        else:
            missing_items.append(f"output group [{' | '.join(group)}]")

    score = int(100 * satisfied / len(groups))
    return score, found_items, missing_items


def _score_visualization(parsed: Dict, expected: Dict) -> Tuple[int, List[str], List[str]]:
    """Check if visualization outputs are declared."""
    patterns = expected.get("viz_patterns", [])
    if not patterns:
        return 100, [], []

    raw = parsed["raw_text"]
    found = [p for p in patterns if p in raw]
    # Need at least 2 visualization types
    score = min(100, int(100 * len(found) / max(2, len(patterns) // 2)))
    missing = [p for p in patterns if p not in raw]
    return score, found[:5], missing[:5]


def _score_qc(parsed: Dict, expected: Dict) -> Tuple[int, List[str], List[str]]:
    """Check QC output coverage."""
    patterns = expected.get("qc_patterns", [])
    if not patterns:
        return 100, [], []

    raw = parsed["raw_text"]
    found = [p for p in patterns if p in raw]
    # Need at least 1 QC element
    score = min(100, int(100 * len(found) / max(1, len(patterns) // 3)))
    missing = [p for p in patterns if p not in raw]
    return score, found, missing


def _score_report(parsed: Dict, expected: Dict) -> Tuple[int, List[str], List[str]]:
    """Check if a methods/summary report is declared."""
    patterns = expected.get("report_patterns", [])
    raw = parsed["raw_text"]
    found = [p for p in patterns if p in raw]
    score = 100 if found else 0
    missing = patterns if not found else []
    return score, found[:3], missing[:3]


def _score_phase_structure(parsed: Dict, expected: Dict) -> Tuple[int, List[str], List[str]]:
    """Check if the workflow has meaningful phase structure aligned with the methodology."""
    phase_keywords = expected.get("phase_keywords", [])
    phases = parsed["phases"]
    raw = " ".join(phases).lower()

    if not phase_keywords:
        return 100 if phases else 50, phases, []

    found = [kw for kw in phase_keywords if any(kw in ph.lower() for ph in phases)]
    missing = [kw for kw in phase_keywords if kw not in found]

    # Score: at least 60% of expected phase keywords present
    if not phase_keywords:
        return 80, [], []
    score = int(100 * len(found) / len(phase_keywords))
    return score, found, missing


def audit_workflow(case_id: str, rel_path: str, domain: str) -> WorkflowOutputAudit:
    nf_path = BIOMNI_WF / rel_path if rel_path else None
    audit = WorkflowOutputAudit(case_id=case_id, domain=domain, nf_path=nf_path)

    if nf_path is None or not nf_path.exists():
        audit.findings.append(f"⚠️  File not found: {rel_path or 'None'}")
        audit.scores = {k: 0 for k in ["required_outputs", "visualization", "qc_report",
                                        "methods_report", "phase_structure"]}
        return audit

    parsed = _parse_nf_file(nf_path)
    audit.declared_outputs = parsed["emit_names"] + parsed["output_paths"]
    audit.declared_processes = parsed["processes"]
    audit.declared_phases = parsed["phases"]
    audit.declared_params = parsed["params"]

    expected = DOMAIN_EXPECTED.get(domain, {})

    # Score each dimension
    req_score, req_found, req_missing = _score_required_outputs(parsed, expected)
    viz_score, viz_found, viz_missing = _score_visualization(parsed, expected)
    qc_score,  qc_found,  qc_missing  = _score_qc(parsed, expected)
    rep_score, rep_found, rep_missing = _score_report(parsed, expected)
    ph_score,  ph_found,  ph_missing  = _score_phase_structure(parsed, expected)

    audit.scores = {
        "required_outputs": req_score,
        "visualization":    viz_score,
        "qc_report":        qc_score,
        "methods_report":   rep_score,
        "phase_structure":  ph_score,
        "overall":          (req_score + viz_score + qc_score + rep_score + ph_score) // 5,
    }

    if req_missing:
        audit.missing.extend(req_missing)
    if viz_missing:
        audit.missing.extend([f"viz:{v}" for v in viz_missing[:3]])
    if qc_missing:
        audit.missing.extend([f"qc:{q}" for q in qc_missing[:2]])
    if rep_missing:
        audit.missing.extend([f"report:{r}" for r in rep_missing[:2]])
    if ph_missing:
        audit.missing.extend([f"phase:{p}" for p in ph_missing[:3]])

    # Findings
    audit.findings.append(f"Processes ({len(audit.declared_processes)}): {', '.join(audit.declared_processes[:6])}")
    audit.findings.append(f"Phases ({len(audit.declared_phases)}): {', '.join(audit.declared_phases[:6])}")
    audit.findings.append(f"Params ({len(audit.declared_params)}): {', '.join(audit.declared_params[:8])}")
    audit.findings.append(f"Outputs (emit): {', '.join(parsed['emit_names'][:8])}")

    return audit


def print_audit_report(audits: List[WorkflowOutputAudit], verbose: bool = False) -> int:
    """Print a formatted audit report. Returns exit code (0=pass, 1=fail)."""
    TARGET = 75  # minimum score per dimension to pass

    print("\n" + "=" * 70)
    print("  BioMate Workflow Output Element Audit")
    print("  Static analysis: publication-aligned output coverage")
    print("=" * 70)

    overall_pass = True
    summary_rows = []

    for a in audits:
        overall = a.scores.get("overall", 0)
        passed = overall >= TARGET
        status = "✅" if passed else "❌"
        if not passed:
            overall_pass = False

        print(f"\n{status} {a.case_id} [{a.domain}]  overall={overall}%")
        if a.nf_path:
            rel = str(a.nf_path.relative_to(BIOMNI_WF))
            print(f"   file: {rel}")
        else:
            print("   file: (not found)")

        # Score bar
        dims = ["required_outputs", "visualization", "qc_report", "methods_report", "phase_structure"]
        dim_labels = ["req_out", "viz", "qc", "report", "phases"]
        parts = []
        for d, lbl in zip(dims, dim_labels):
            s = a.scores.get(d, 0)
            mark = "✓" if s >= TARGET else "✗"
            parts.append(f"{lbl}={s}%{mark}")
        print("   scores: " + " | ".join(parts))

        if verbose and a.findings:
            for f in a.findings:
                print(f"   {f}")

        if a.missing:
            print(f"   missing: {', '.join(a.missing[:8])}")

        summary_rows.append((a.case_id, overall, passed))

    # Summary table
    print("\n" + "=" * 70)
    print("  Summary")
    print("=" * 70)
    for cid, score, passed in summary_rows:
        bar = "█" * (score // 10) + "░" * (10 - score // 10)
        mark = "PASS" if passed else "FAIL"
        print(f"  {cid:<30} [{bar}] {score:3d}%  {mark}")

    passing = sum(1 for _, _, p in summary_rows if p)
    total   = len(summary_rows)
    avg     = sum(s for _, s, _ in summary_rows) // total if total else 0
    print(f"\n  Result: {passing}/{total} workflows pass (avg={avg}%, target={TARGET}%)")
    print("=" * 70)

    return 0 if overall_pass else 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Workflow output element audit")
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="Print per-workflow detailed findings")
    parser.add_argument("--domain", type=str, default="",
                        help="Comma-separated domains to filter (e.g. rnaseq,single_cell)")
    args = parser.parse_args()

    filter_domains = set(args.domain.split(",")) if args.domain else set()

    audits = []
    for case_id, rel_path in TUTORIAL_CASES.items():
        domain = TUTORIAL_DOMAIN[case_id]
        if filter_domains and domain not in filter_domains:
            continue
        audits.append(audit_workflow(case_id, rel_path, domain))

    return print_audit_report(audits, verbose=args.verbose)


if __name__ == "__main__":
    sys.exit(main())
