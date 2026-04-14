"""
OutputAnalyzer — type-aware biological interpretation of Nextflow run outputs.

Dispatches to per-format handlers (VCF, CSV rankings, FastQC, RNA DEG, MRC, generic)
and returns a structured AnalysisResult with plain-English summary, key metrics,
suggested PubMed queries, quality caveats, and next-step suggestions.
"""

from dataclasses import dataclass, field
from typing import Optional
import os
import csv
import json
import re
import logging

log = logging.getLogger(__name__)


@dataclass
class AnalysisResult:
    run_id: str
    workflow_id: str
    output_type: str  # 'vcf' | 'csv_rankings' | 'fastq_qc' | 'rna_deg' | 'mrc_map' | 'generic'
    summary: str       # 2-3 sentences plain English
    key_results: list  # list[dict] with keys: metric, value, interpretation
    search_queries: list  # list[str] PubMed queries
    caveats: list      # list[str] quality issues
    next_steps: list   # list[str] suggested follow-up workflows


class OutputAnalyzer:
    """Analyze Nextflow output files and produce structured biological interpretation."""

    # ── Public API ──────────────────────────────────────────────────────────────

    def analyze(self, run_id: str, workflow_id: str, output_files: list) -> AnalysisResult:
        """
        Analyze output files from a completed Nextflow run.

        Args:
            run_id: UUID of the execution run
            workflow_id: Workflow identifier
            output_files: list of {"name": str, "path": str, "type": str}

        Returns:
            AnalysisResult with summary, key_results, search_queries, caveats, next_steps
        """
        if not output_files:
            return AnalysisResult(
                run_id=run_id,
                workflow_id=workflow_id,
                output_type="generic",
                summary="No output files were provided for analysis.",
                key_results=[],
                search_queries=[],
                caveats=["No output files found in the specified output directory."],
                next_steps=["Verify the workflow completed successfully and check the output directory."],
            )

        # Detect primary output type from file names
        output_type, primary_file = self._detect_output_type(output_files)

        try:
            if output_type == "vcf":
                return self._analyze_vcf(primary_file["path"], run_id, workflow_id)
            elif output_type == "csv_rankings":
                return self._analyze_csv_rankings(primary_file["path"], run_id, workflow_id)
            elif output_type == "fastq_qc":
                return self._analyze_fastq_qc(primary_file["path"], run_id, workflow_id)
            elif output_type == "rna_deg":
                return self._analyze_rna_deg(primary_file["path"], run_id, workflow_id)
            elif output_type == "mrc_map":
                return self._analyze_mrc(primary_file["path"], run_id, workflow_id)
            else:
                return self._analyze_generic(output_files, run_id, workflow_id)
        except Exception as exc:
            log.error("[OutputAnalyzer] top-level error for run %s: %s", run_id, exc)
            return self._analyze_generic(output_files, run_id, workflow_id,
                                         extra_caveat=f"Primary file analysis failed: {exc}")

    # ── Type Detection ───────────────────────────────────────────────────────────

    def _detect_output_type(self, output_files: list) -> tuple:
        """Return (output_type, primary_file_dict) from the file list."""
        # Priority order — most specific first
        priorities = [
            ("vcf", lambda n: re.search(r'\.vcf(\.gz)?$', n, re.I)),
            ("fastq_qc", lambda n: re.search(r'(multiqc_data\.json|fastqc.*\.txt|multiqc.*\.json|summary\.txt)$', n, re.I)),
            ("rna_deg", lambda n: re.search(r'(deg|deseq2|edger|limma|differential.*expression|DE_results).*\.(csv|tsv)$', n, re.I)),
            ("csv_rankings", lambda n: re.search(r'\.(csv|tsv)$', n, re.I)),
            ("mrc_map", lambda n: re.search(r'\.(mrc|map|ccp4|spi|mrcs)$', n, re.I)),
        ]
        for out_type, matcher in priorities:
            for f in output_files:
                name = f.get("name", "") or os.path.basename(f.get("path", ""))
                if matcher(name):
                    return out_type, f
        # Fallback: return first file
        return "generic", output_files[0]

    # ── Per-type Analyzers ───────────────────────────────────────────────────────

    def _analyze_vcf(self, path: str, run_id: str, workflow_id: str) -> AnalysisResult:
        """Parse VCF/VCF.gz and summarize variant counts, impact, and gene names."""
        total = 0
        pass_count = 0
        high_impact = 0
        moderate_impact = 0
        genes: list = []
        caveats: list = []

        try:
            import gzip
            open_fn = gzip.open if path.endswith(".gz") else open
            mode = "rt"
            with open_fn(path, mode) as fh:
                for line in fh:
                    if line.startswith("#"):
                        continue
                    total += 1
                    cols = line.strip().split("\t")
                    if len(cols) < 8:
                        continue
                    filter_col = cols[6] if len(cols) > 6 else "."
                    if filter_col == "PASS":
                        pass_count += 1
                    info = cols[7] if len(cols) > 7 else ""
                    # SnpEff ANN field
                    ann_match = re.search(r'ANN=([^;]+)', info)
                    if ann_match:
                        ann_parts = ann_match.group(1).split(",")
                        for ann in ann_parts:
                            fields = ann.split("|")
                            if len(fields) > 3:
                                impact = fields[2].upper()
                                gene = fields[3]
                                if impact == "HIGH":
                                    high_impact += 1
                                    if gene and gene not in genes:
                                        genes.append(gene)
                                elif impact == "MODERATE":
                                    moderate_impact += 1
                                    if gene and len(genes) < 10 and gene not in genes:
                                        genes.append(gene)
                    # Simpler GENE= field
                    gene_match = re.search(r'GENE=([^;,\s]+)', info)
                    if gene_match:
                        g = gene_match.group(1)
                        if g and g not in genes:
                            genes.append(g)
                    # Stop after 50k lines to avoid memory issues with huge VCFs
                    if total > 50000:
                        caveats.append("VCF truncated at 50,000 variants for summary — file may be larger.")
                        break
        except Exception as exc:
            caveats.append(f"Could not fully parse {os.path.basename(path)}: {exc}")

        top_genes = genes[:5]
        gene_str = ", ".join(top_genes) if top_genes else "unknown"

        if total == 0:
            summary = "VCF file appears to contain no variant records."
        elif high_impact > 0:
            summary = (
                f"Found {total:,} variants ({pass_count:,} PASS filter). "
                f"{high_impact} HIGH impact variant{'s' if high_impact != 1 else ''} detected"
                f"{f' in genes {gene_str}' if top_genes else ''}. "
                f"Also {moderate_impact} MODERATE impact variants identified."
            )
        else:
            summary = (
                f"Found {total:,} variants ({pass_count:,} PASS filter). "
                f"No HIGH impact variants detected; {moderate_impact} MODERATE impact variants found."
            )

        key_results = [
            {"metric": "Total variants", "value": f"{total:,}", "interpretation": "All called variants before filtering"},
            {"metric": "PASS variants", "value": f"{pass_count:,}", "interpretation": "Variants passing all quality filters"},
            {"metric": "HIGH impact", "value": str(high_impact), "interpretation": "Variants predicted to severely disrupt protein function"},
            {"metric": "MODERATE impact", "value": str(moderate_impact), "interpretation": "Variants with moderate functional consequence"},
        ]
        if top_genes:
            key_results.append({"metric": "Affected genes (HIGH)", "value": gene_str, "interpretation": "Genes harboring HIGH impact variants"})

        search_queries = []
        for gene in top_genes[:3]:
            search_queries.append(f"{gene} variant pathogenicity")
        if not search_queries:
            search_queries = ["whole genome sequencing variant calling GATK", "somatic variant functional impact annotation"]

        next_steps = [
            "Prioritize HIGH and MODERATE impact variants for functional validation",
            "Cross-reference variants against ClinVar and gnomAD population databases",
            "Consider running CADD or REVEL pathogenicity scoring on filtered variants",
        ]

        return AnalysisResult(
            run_id=run_id,
            workflow_id=workflow_id,
            output_type="vcf",
            summary=summary,
            key_results=key_results,
            search_queries=search_queries,
            caveats=caveats,
            next_steps=next_steps,
        )

    def _analyze_csv_rankings(self, path: str, run_id: str, workflow_id: str) -> AnalysisResult:
        """Parse compound ranking CSVs and summarize top hits."""
        caveats: list = []
        rows: list = []
        headers: list = []

        try:
            sep = "\t" if path.endswith(".tsv") else ","
            with open(path, newline="", encoding="utf-8", errors="replace") as fh:
                reader = csv.DictReader(fh, delimiter=sep)
                headers = list(reader.fieldnames or [])
                for i, row in enumerate(reader):
                    rows.append(row)
                    if i >= 1000:
                        caveats.append("CSV truncated at 1,000 rows for summary.")
                        break
        except Exception as exc:
            caveats.append(f"Could not parse {os.path.basename(path)}: {exc}")
            return AnalysisResult(
                run_id=run_id, workflow_id=workflow_id, output_type="csv_rankings",
                summary="Could not read ranking CSV file.",
                key_results=[], search_queries=[], caveats=caveats, next_steps=[],
            )

        if not rows:
            return AnalysisResult(
                run_id=run_id, workflow_id=workflow_id, output_type="csv_rankings",
                summary="Ranking CSV is empty.",
                key_results=[], search_queries=[], caveats=["CSV file has no data rows."], next_steps=[],
            )

        # Identify primary score column
        score_col = self._detect_score_column(headers)
        name_col = self._detect_name_column(headers)

        top_rows = rows[:3]
        top_names = [r.get(name_col, f"row {i+1}") for i, r in enumerate(top_rows)] if name_col else []
        top_scores = [r.get(score_col, "N/A") for r in top_rows] if score_col else []

        summary = (
            f"Ranking table contains {len(rows):,} compound{'s' if len(rows) != 1 else ''}. "
        )
        if score_col and top_names:
            summary += f"Top hit by {score_col}: {top_names[0]} (score: {top_scores[0] if top_scores else 'N/A'}). "
        summary += "Key metrics are shown in the table below."

        key_results = [{"metric": "Total compounds", "value": str(len(rows)), "interpretation": "Compounds in ranking table"}]
        for i, (name, score) in enumerate(zip(top_names[:3], top_scores[:3])):
            key_results.append({
                "metric": f"Rank {i+1}",
                "value": f"{name} ({score_col}: {score})" if score_col else name,
                "interpretation": "Top-ranked compound by primary score",
            })

        search_queries = []
        for name in top_names[:2]:
            if name and len(name) > 3:
                search_queries.append(f"{name} drug discovery binding affinity")
        if not search_queries:
            search_queries = ["virtual screening drug docking score", "compound ranking ADMET drug like properties"]

        next_steps = [
            f"Validate top hits ({', '.join(top_names[:2])}) with wet-lab binding assay",
            "Run ADMET profiling on shortlisted compounds",
            "Submit top 10 compounds for CRO synthesis and testing",
        ]

        return AnalysisResult(
            run_id=run_id, workflow_id=workflow_id, output_type="csv_rankings",
            summary=summary, key_results=key_results,
            search_queries=search_queries, caveats=caveats, next_steps=next_steps,
        )

    def _analyze_fastq_qc(self, path: str, run_id: str, workflow_id: str) -> AnalysisResult:
        """Parse MultiQC JSON or FastQC summary and flag quality issues."""
        caveats: list = []
        key_results: list = []
        summary_parts: list = []

        try:
            if path.endswith(".json"):
                with open(path, encoding="utf-8", errors="replace") as fh:
                    data = json.load(fh)
                # MultiQC general stats
                general_stats = data.get("report_general_stats_data", [])
                samples_parsed = 0
                total_reads = 0
                dup_pct_sum = 0.0
                dup_count = 0
                for block in general_stats:
                    for sample, stats in block.items():
                        samples_parsed += 1
                        reads = stats.get("total_sequences") or stats.get("Total Sequences") or 0
                        total_reads += int(reads) if reads else 0
                        dup = stats.get("percent_duplicates") or stats.get("% Duplicate Reads") or 0
                        if dup:
                            dup_pct_sum += float(dup)
                            dup_count += 1
                avg_dup = dup_pct_sum / dup_count if dup_count else None
                if avg_dup and avg_dup > 40:
                    caveats.append(f"High duplication rate: {avg_dup:.1f}% average across samples (threshold: 40%).")
                summary_parts.append(f"{samples_parsed} sample(s) QC'd by MultiQC.")
                if total_reads:
                    summary_parts.append(f"Total reads: {total_reads:,}.")
                if avg_dup is not None:
                    summary_parts.append(f"Average duplication: {avg_dup:.1f}%.")
                key_results.append({"metric": "Samples", "value": str(samples_parsed), "interpretation": "Samples passing QC pipeline"})
                if total_reads:
                    key_results.append({"metric": "Total reads", "value": f"{total_reads:,}", "interpretation": "Sequencing reads across all samples"})
                if avg_dup is not None:
                    key_results.append({"metric": "Avg duplication", "value": f"{avg_dup:.1f}%",
                                        "interpretation": "Above 40% may indicate library issues"})
            else:
                # FastQC summary.txt: tab-separated PASS/WARN/FAIL rows
                fail_modules: list = []
                warn_modules: list = []
                with open(path, encoding="utf-8", errors="replace") as fh:
                    for line in fh:
                        parts = line.strip().split("\t")
                        if len(parts) >= 2:
                            status, module = parts[0], parts[1]
                            if status == "FAIL":
                                fail_modules.append(module)
                            elif status == "WARN":
                                warn_modules.append(module)
                if fail_modules:
                    caveats.append(f"FastQC FAIL modules: {', '.join(fail_modules)}.")
                    summary_parts.append(f"{len(fail_modules)} FastQC module(s) failed: {', '.join(fail_modules[:3])}.")
                else:
                    summary_parts.append("All FastQC modules passed.")
                if warn_modules:
                    summary_parts.append(f"{len(warn_modules)} warning(s): {', '.join(warn_modules[:3])}.")
                key_results.append({"metric": "FAIL modules", "value": str(len(fail_modules)), "interpretation": "FastQC quality modules failing"})
                key_results.append({"metric": "WARN modules", "value": str(len(warn_modules)), "interpretation": "FastQC quality modules with warnings"})
        except Exception as exc:
            caveats.append(f"Could not parse {os.path.basename(path)}: {exc}")
            summary_parts.append("QC file could not be fully parsed.")

        summary = " ".join(summary_parts) if summary_parts else "QC analysis completed."

        return AnalysisResult(
            run_id=run_id, workflow_id=workflow_id, output_type="fastq_qc",
            summary=summary, key_results=key_results,
            search_queries=["sequencing quality control best practices", "FastQC MultiQC RNA-seq QC metrics"],
            caveats=caveats,
            next_steps=[
                "Trim adapter sequences if adapter content > 10%",
                "Consider removing PCR duplicates if duplication > 40%",
                "Re-sequence samples with mapping rate < 70%",
            ],
        )

    def _analyze_rna_deg(self, path: str, run_id: str, workflow_id: str) -> AnalysisResult:
        """Parse DEG result table and summarize up/downregulated genes."""
        caveats: list = []
        rows: list = []

        try:
            sep = "\t" if path.endswith(".tsv") else ","
            with open(path, newline="", encoding="utf-8", errors="replace") as fh:
                reader = csv.DictReader(fh, delimiter=sep)
                headers = list(reader.fieldnames or [])
                for row in reader:
                    rows.append(row)
        except Exception as exc:
            caveats.append(f"Could not parse {os.path.basename(path)}: {exc}")
            return AnalysisResult(
                run_id=run_id, workflow_id=workflow_id, output_type="rna_deg",
                summary="Could not read DEG result file.",
                key_results=[], search_queries=[], caveats=caveats, next_steps=[],
            )

        if not rows:
            return AnalysisResult(
                run_id=run_id, workflow_id=workflow_id, output_type="rna_deg",
                summary="DEG result table is empty.",
                key_results=[], search_queries=[], caveats=["No DEG results found."], next_steps=[],
            )

        headers = list(rows[0].keys()) if rows else []
        log2fc_col = self._find_column(headers, ["log2FoldChange", "log2fc", "logFC", "log2_fold_change", "lfc"])
        padj_col = self._find_column(headers, ["padj", "FDR", "adj.P.Val", "q_value", "qvalue", "adjusted_pvalue"])
        gene_col = self._find_column(headers, ["gene", "gene_name", "symbol", "Gene", "gene_id", "SYMBOL"])

        up = 0
        down = 0
        top_genes: list = []  # list of (|log2fc|, gene_name)

        for row in rows:
            try:
                lfc = float(row.get(log2fc_col or "", "") or 0) if log2fc_col else 0
                padj_val = float(row.get(padj_col or "", "") or 1) if padj_col else 1
                gene = row.get(gene_col or "", "") if gene_col else ""
                if padj_val < 0.05:
                    if lfc > 1:
                        up += 1
                    elif lfc < -1:
                        down += 1
                if padj_val < 0.05 and abs(lfc) > 1:
                    top_genes.append((abs(lfc), gene))
            except (ValueError, TypeError):
                pass

        top_genes.sort(key=lambda x: x[0], reverse=True)
        top_gene_names = [g for _, g in top_genes[:5] if g]

        total_sig = up + down
        summary = (
            f"Differential expression analysis identified {total_sig} significant genes "
            f"(|log2FC| > 1, padj < 0.05): {up} upregulated, {down} downregulated. "
        )
        if top_gene_names:
            summary += f"Top genes by fold change: {', '.join(top_gene_names[:5])}."

        key_results = [
            {"metric": "Total genes tested", "value": str(len(rows)), "interpretation": "Genes in DE analysis"},
            {"metric": "Significant DEGs", "value": str(total_sig), "interpretation": "padj < 0.05 and |log2FC| > 1"},
            {"metric": "Upregulated", "value": str(up), "interpretation": "log2FC > 1, padj < 0.05"},
            {"metric": "Downregulated", "value": str(down), "interpretation": "log2FC < -1, padj < 0.05"},
        ]
        if top_gene_names:
            key_results.append({"metric": "Top DEGs", "value": ", ".join(top_gene_names[:5]),
                                 "interpretation": "Highest absolute fold change, padj < 0.05"})

        search_queries = [f"{g} differential expression" for g in top_gene_names[:2]]
        if not search_queries:
            search_queries = ["RNA-seq differential expression DESeq2", "transcriptome analysis gene regulation"]

        return AnalysisResult(
            run_id=run_id, workflow_id=workflow_id, output_type="rna_deg",
            summary=summary, key_results=key_results,
            search_queries=search_queries, caveats=caveats,
            next_steps=[
                "Run pathway enrichment analysis (GSEA or ORA) on significant DEGs",
                "Validate top hits by RT-qPCR",
                "Build protein-protein interaction network for top DEGs",
            ],
        )

    def _analyze_mrc(self, path: str, run_id: str, workflow_id: str) -> AnalysisResult:
        """MRC/CCP4 map file — report size and point to log for resolution."""
        size_mb = 0.0
        try:
            size_mb = os.path.getsize(path) / 1e6
        except OSError:
            pass

        summary = (
            f"Cryo-EM density map file ({os.path.basename(path)}, {size_mb:.1f} MB). "
            "Resolution and quality metrics are reported in the CryoSPARC or RELION log file. "
            "Use ChimeraX or UCSF Chimera to visualize the reconstructed density."
        )

        return AnalysisResult(
            run_id=run_id, workflow_id=workflow_id, output_type="mrc_map",
            summary=summary,
            key_results=[
                {"metric": "Map file size", "value": f"{size_mb:.1f} MB", "interpretation": "Uncompressed MRC density map"},
            ],
            search_queries=["cryo-EM single particle analysis resolution FSC", "CryoSPARC RELION structure determination"],
            caveats=["Binary MRC format cannot be parsed directly; see run log for FSC resolution estimate."],
            next_steps=[
                "Check the CryoSPARC/RELION log for FSC 0.143 resolution estimate",
                "Visualize map in ChimeraX and fit atomic model",
                "Run model validation with MolProbity or EMRinger",
            ],
        )

    def _analyze_generic(self, output_files: list, run_id: str, workflow_id: str,
                          extra_caveat: Optional[str] = None) -> AnalysisResult:
        """Fallback: list all output files with sizes."""
        file_summaries: list = []
        total_size = 0.0
        for f in output_files:
            path = f.get("path", "")
            name = f.get("name") or os.path.basename(path)
            try:
                size = os.path.getsize(path) / 1e6 if path and os.path.exists(path) else 0
            except OSError:
                size = 0
            total_size += size
            file_summaries.append({"metric": name, "value": f"{size:.2f} MB",
                                    "interpretation": f.get("type", "output file")})

        summary = (
            f"Workflow produced {len(output_files)} output file(s) "
            f"(total {total_size:.1f} MB). "
            "Detailed biological interpretation requires type-specific analysis."
        )

        caveats: list = []
        if extra_caveat:
            caveats.append(extra_caveat)

        return AnalysisResult(
            run_id=run_id, workflow_id=workflow_id, output_type="generic",
            summary=summary, key_results=file_summaries[:10],
            search_queries=[], caveats=caveats,
            next_steps=["Review individual output files for biological insights."],
        )

    # ── Column Detection Helpers ─────────────────────────────────────────────────

    def _detect_score_column(self, headers: list) -> Optional[str]:
        """Identify primary numeric score column from header names."""
        score_candidates = [
            "docking_score", "binding_affinity", "affinity", "score", "ic50", "ki", "kd",
            "qed", "sa_score", "tanimoto", "cnnscore", "vina_score", "glide_score",
            "rank_score", "total_score", "fitness",
        ]
        headers_lower = {h.lower(): h for h in headers}
        for cand in score_candidates:
            if cand in headers_lower:
                return headers_lower[cand]
        # Fallback: any header with "score" or "affinity"
        for h in headers:
            if re.search(r'score|affinity|ic50|ki\b|kd\b', h, re.I):
                return h
        return None

    def _detect_name_column(self, headers: list) -> Optional[str]:
        """Identify compound/sample name column."""
        name_candidates = ["compound", "molecule", "smiles", "name", "id", "compound_id",
                           "mol_id", "ligand", "drug", "sample"]
        headers_lower = {h.lower(): h for h in headers}
        for cand in name_candidates:
            if cand in headers_lower:
                return headers_lower[cand]
        # Return first column if nothing else found
        return headers[0] if headers else None

    def _find_column(self, headers: list, candidates: list) -> Optional[str]:
        """Find first matching column name from candidates (case-insensitive)."""
        headers_lower = {h.lower(): h for h in headers}
        for cand in candidates:
            if cand.lower() in headers_lower:
                return headers_lower[cand.lower()]
        return None
