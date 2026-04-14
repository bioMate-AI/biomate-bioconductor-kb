"""
FindingReporter — builds a structured FindingsReport from an AnalysisResult,
optionally enriched with PubMed citations via the existing literature client.

Usage:
    reporter = FindingReporter()
    citations = reporter.search_citations(analysis_result.search_queries)
    report = reporter.generate(analysis_result, citations)
    reporter.save_report(report, output_dir="/tmp/nextflow_runs/run-uuid/output")
"""

from dataclasses import dataclass, field
from typing import Optional
import subprocess
import os
import logging

log = logging.getLogger(__name__)


@dataclass
class Citation:
    pmid: str
    title: str
    year: str
    relevance: str  # one-line explanation of relevance


@dataclass
class FindingsReport:
    run_id: str
    summary: str
    key_results: list  # list[dict] metric/value/interpretation
    citations: list    # list[Citation]
    caveats: list      # list[str]
    next_steps: list   # list[str]
    report_md: str     # full Markdown text
    report_path: Optional[str] = None  # path to saved .md file


class FindingReporter:
    """Build and persist findings reports from OutputAnalyzer results."""

    # ── Public API ───────────────────────────────────────────────────────────────

    def generate(self, analysis_result, citations: list) -> FindingsReport:
        """
        Build a FindingsReport from an AnalysisResult and citation list.

        Args:
            analysis_result: AnalysisResult dataclass instance
            citations: list of Citation instances

        Returns:
            FindingsReport with full markdown text
        """
        md = self._build_markdown(analysis_result, citations)
        return FindingsReport(
            run_id=analysis_result.run_id,
            summary=analysis_result.summary,
            key_results=analysis_result.key_results,
            citations=citations,
            caveats=analysis_result.caveats,
            next_steps=analysis_result.next_steps,
            report_md=md,
        )

    def search_citations(self, queries: list, max_per_query: int = 3) -> list:
        """
        Search PubMed for each query string and return Citation instances.

        Uses the existing UnifiedLiteratureClient (PubMed + Semantic Scholar).
        Citation search is best-effort; failures are silently logged.

        Args:
            queries: list of search query strings
            max_per_query: max results per query (default 3)

        Returns:
            list of Citation objects (may be empty if search unavailable)
        """
        citations: list = []
        seen_pmids: set = set()

        try:
            import asyncio
            from galaxy.ai.agents.literature_clients import create_literature_client

            lit_client = create_literature_client()

            async def _search_all():
                results: list = []
                for q in queries[:3]:  # max 3 queries to avoid rate limiting
                    try:
                        hits = await lit_client.pubmed.search(q, max_per_query)
                        results.extend(hits)
                    except Exception as exc:
                        log.warning("[FindingReporter] PubMed query failed for '%s': %s", q, exc)
                return results

            # Run async search
            try:
                loop = asyncio.get_running_loop()
                import concurrent.futures
                with concurrent.futures.ThreadPoolExecutor() as executor:
                    future = executor.submit(asyncio.run, _search_all())
                    lit_results = future.result(timeout=20)
            except RuntimeError:
                lit_results = asyncio.run(_search_all())

            for r in lit_results:
                pmid = str(r.pmid or "")
                if pmid and pmid in seen_pmids:
                    continue
                if pmid:
                    seen_pmids.add(pmid)
                abstract = r.abstract or ""
                relevance = (abstract[:150] + "…") if abstract else "Related publication"
                citations.append(Citation(
                    pmid=pmid,
                    title=r.title or "Untitled",
                    year=str(r.year or ""),
                    relevance=relevance,
                ))

        except Exception as exc:
            log.warning("[FindingReporter] Citation search unavailable: %s", exc)

        return citations

    def save_report(self, report: FindingsReport, output_dir: str) -> str:
        """
        Save findings_report.md to output_dir.

        Args:
            report: FindingsReport instance
            output_dir: directory path (will be created if absent)

        Returns:
            Absolute path to the saved file
        """
        os.makedirs(output_dir, exist_ok=True)
        path = os.path.join(output_dir, "findings_report.md")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(report.report_md)
        report.report_path = path
        log.info("[FindingReporter] Saved findings report to %s", path)
        return path

    def export_pdf(self, report: FindingsReport) -> Optional[str]:
        """
        Convert findings_report.md to PDF using pandoc.

        Returns:
            PDF path on success, None if pandoc is unavailable or conversion fails.
        """
        if not report.report_path:
            return None
        try:
            pdf_path = report.report_path.replace(".md", ".pdf")
            result = subprocess.run(
                ["pandoc", report.report_path, "-o", pdf_path],
                capture_output=True,
                timeout=30,
            )
            if result.returncode == 0:
                log.info("[FindingReporter] Exported PDF to %s", pdf_path)
                return pdf_path
            else:
                log.warning("[FindingReporter] pandoc failed: %s", result.stderr.decode(errors="replace"))
                return None
        except FileNotFoundError:
            log.debug("[FindingReporter] pandoc not available on PATH")
            return None
        except subprocess.TimeoutExpired:
            log.warning("[FindingReporter] pandoc timed out")
            return None

    # ── Markdown Builder ─────────────────────────────────────────────────────────

    def _build_markdown(self, analysis_result, citations: list) -> str:
        """Render FindingsReport as formatted Markdown."""
        lines: list = []

        lines.append("# Findings Report")
        lines.append("")
        lines.append(f"**Run ID:** {analysis_result.run_id}  ")
        lines.append(f"**Output type:** {analysis_result.output_type}")
        lines.append("")

        # Summary
        lines.append("## Findings Summary")
        lines.append("")
        lines.append(analysis_result.summary)
        lines.append("")

        # Key Results table
        if analysis_result.key_results:
            lines.append("## Key Results")
            lines.append("")
            lines.append("| Metric | Value | Interpretation |")
            lines.append("|--------|-------|----------------|")
            for r in analysis_result.key_results:
                metric = str(r.get("metric", "")).replace("|", "\\|")
                value = str(r.get("value", "")).replace("|", "\\|")
                interp = str(r.get("interpretation", "")).replace("|", "\\|")
                lines.append(f"| {metric} | {value} | {interp} |")
            lines.append("")

        # Supporting Literature
        if citations:
            lines.append("## Supporting Literature")
            lines.append("")
            for i, c in enumerate(citations, start=1):
                pmid_link = (
                    f"[PMID:{c.pmid}](https://pubmed.ncbi.nlm.nih.gov/{c.pmid}/)"
                    if c.pmid
                    else "no PMID"
                )
                year_str = f" ({c.year})" if c.year else ""
                lines.append(f"{i}. **{c.title}**{year_str} — {pmid_link}  ")
                lines.append(f"   *{c.relevance}*")
                lines.append("")

        # Caveats
        if analysis_result.caveats:
            lines.append("## Caveats")
            lines.append("")
            for caveat in analysis_result.caveats:
                lines.append(f"- {caveat}")
            lines.append("")

        # Next Steps
        if analysis_result.next_steps:
            lines.append("## Recommended Next Steps")
            lines.append("")
            for i, step in enumerate(analysis_result.next_steps, start=1):
                lines.append(f"{i}. {step}")
            lines.append("")

        return "\n".join(lines)
