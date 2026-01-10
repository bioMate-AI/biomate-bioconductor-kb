"""
Results Analyzer

Analyzes benchmark results and generates comparison reports.
"""

import logging
import json
from typing import Dict, List, Any, Optional, Tuple
from dataclasses import dataclass, field, asdict
from pathlib import Path
from collections import defaultdict
import statistics

log = logging.getLogger(__name__)


@dataclass
class StatisticalResult:
    """Result of statistical comparison."""
    metric: str
    test_name: str
    statistic: float
    p_value: float
    significant: bool
    effect_size: Optional[float] = None
    confidence_interval: Optional[Tuple[float, float]] = None

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class ToolComparison:
    """Comparison results for a single tool."""
    tool_id: str
    tool_name: str
    run_count: int

    # Aggregated metrics
    mean_runtime: float
    std_runtime: float
    mean_memory: float
    std_memory: float

    # Quality metrics
    quality_metrics: Dict[str, float] = field(default_factory=dict)

    # Ranking
    rank: int = 0
    rank_reason: str = ""

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class ComparisonReport:
    """Complete comparison report."""
    scenario_name: str
    generated_at: str
    summary: str

    # Tool comparisons
    tool_comparisons: List[ToolComparison] = field(default_factory=list)

    # Statistical tests
    statistical_results: List[StatisticalResult] = field(default_factory=list)

    # Best tool by metric
    best_by_metric: Dict[str, str] = field(default_factory=dict)

    # Recommendations
    recommendations: List[str] = field(default_factory=list)

    # Visualization data
    chart_data: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "scenario_name": self.scenario_name,
            "generated_at": self.generated_at,
            "summary": self.summary,
            "tool_comparisons": [t.to_dict() for t in self.tool_comparisons],
            "statistical_results": [s.to_dict() for s in self.statistical_results],
            "best_by_metric": self.best_by_metric,
            "recommendations": self.recommendations,
            "chart_data": self.chart_data
        }


class ResultsAnalyzer:
    """
    Analyzes benchmark results and generates comparison reports.

    Features:
    - Statistical comparison (t-test, Wilcoxon)
    - Visualization data generation
    - Report generation (HTML, Markdown, JSON)
    - Regression detection
    """

    def __init__(self):
        pass

    def compare_tools(
        self,
        results: "BenchmarkResults",
        primary_metric: str = "runtime_seconds"
    ) -> ComparisonReport:
        """
        Compare tools in benchmark results.

        Args:
            results: Benchmark results to analyze
            primary_metric: Primary metric for ranking

        Returns:
            ComparisonReport with analysis
        """
        from datetime import datetime

        report = ComparisonReport(
            scenario_name=results.scenario_name,
            generated_at=datetime.now().isoformat(),
            summary=""
        )

        # Group runs by tool
        tool_runs = defaultdict(list)
        for run in results.runs:
            if run.success:
                tool_runs[run.tool_id].append(run)

        if not tool_runs:
            report.summary = "No successful runs to analyze."
            return report

        # Calculate statistics for each tool
        tool_stats = {}
        for tool_id, runs in tool_runs.items():
            runtimes = [r.runtime_seconds for r in runs if r.runtime_seconds]
            memories = [r.peak_memory_gb for r in runs if r.peak_memory_gb]

            if not runtimes:
                continue

            stats = {
                "mean_runtime": statistics.mean(runtimes),
                "std_runtime": statistics.stdev(runtimes) if len(runtimes) > 1 else 0,
                "mean_memory": statistics.mean(memories) if memories else 0,
                "std_memory": statistics.stdev(memories) if len(memories) > 1 else 0,
                "run_count": len(runs),
                "quality_metrics": self._aggregate_quality_metrics(runs)
            }
            tool_stats[tool_id] = stats

        # Create tool comparisons
        tool_comparisons = []
        for tool_id, stats in tool_stats.items():
            comparison = ToolComparison(
                tool_id=tool_id,
                tool_name=tool_id.split("/")[-1] if "/" in tool_id else tool_id,
                run_count=stats["run_count"],
                mean_runtime=stats["mean_runtime"],
                std_runtime=stats["std_runtime"],
                mean_memory=stats["mean_memory"],
                std_memory=stats["std_memory"],
                quality_metrics=stats["quality_metrics"]
            )
            tool_comparisons.append(comparison)

        # Rank tools by primary metric
        if primary_metric == "runtime_seconds":
            tool_comparisons.sort(key=lambda t: t.mean_runtime)
            metric_label = "runtime"
        elif primary_metric == "peak_memory_gb":
            tool_comparisons.sort(key=lambda t: t.mean_memory)
            metric_label = "memory usage"
        else:
            tool_comparisons.sort(key=lambda t: t.mean_runtime)
            metric_label = "runtime"

        for i, comp in enumerate(tool_comparisons):
            comp.rank = i + 1
            if i == 0:
                comp.rank_reason = f"Fastest {metric_label}"
            elif i == len(tool_comparisons) - 1:
                comp.rank_reason = f"Slowest {metric_label}"

        report.tool_comparisons = tool_comparisons

        # Statistical comparisons
        if len(tool_runs) >= 2:
            report.statistical_results = self._run_statistical_tests(tool_runs, primary_metric)

        # Find best tool by each metric
        report.best_by_metric = self._find_best_by_metric(tool_stats)

        # Generate recommendations
        report.recommendations = self._generate_recommendations(tool_comparisons, tool_stats)

        # Generate chart data
        report.chart_data = self._generate_chart_data(tool_comparisons, tool_runs)

        # Generate summary
        if tool_comparisons:
            best = tool_comparisons[0]
            worst = tool_comparisons[-1]
            speedup = worst.mean_runtime / best.mean_runtime if best.mean_runtime > 0 else 1

            report.summary = (
                f"Compared {len(tool_comparisons)} tools across {sum(c.run_count for c in tool_comparisons)} runs. "
                f"Best performer: {best.tool_name} ({best.mean_runtime:.1f}s avg runtime). "
                f"Speedup vs slowest: {speedup:.1f}x."
            )

        return report

    def _aggregate_quality_metrics(self, runs: List) -> Dict[str, float]:
        """Aggregate quality metrics across runs."""
        all_metrics = defaultdict(list)

        for run in runs:
            for metric, value in run.quality_metrics.items():
                if value is not None:
                    all_metrics[metric].append(value)

        aggregated = {}
        for metric, values in all_metrics.items():
            if values:
                aggregated[metric] = statistics.mean(values)

        return aggregated

    def _run_statistical_tests(
        self,
        tool_runs: Dict[str, List],
        metric: str
    ) -> List[StatisticalResult]:
        """Run statistical tests between tools."""
        results = []
        tools = list(tool_runs.keys())

        if len(tools) < 2:
            return results

        # Pairwise comparisons
        for i in range(len(tools)):
            for j in range(i + 1, len(tools)):
                tool_a = tools[i]
                tool_b = tools[j]

                values_a = [getattr(r, metric.replace("_seconds", "_seconds")) or r.runtime_seconds
                           for r in tool_runs[tool_a]]
                values_b = [getattr(r, metric.replace("_seconds", "_seconds")) or r.runtime_seconds
                           for r in tool_runs[tool_b]]

                if len(values_a) >= 2 and len(values_b) >= 2:
                    stat_result = self._paired_ttest(values_a, values_b, metric)
                    stat_result.metric = f"{tool_a} vs {tool_b}"
                    results.append(stat_result)

        return results

    def _paired_ttest(
        self,
        values_a: List[float],
        values_b: List[float],
        metric: str
    ) -> StatisticalResult:
        """Perform paired t-test."""
        try:
            from scipy import stats
            statistic, p_value = stats.ttest_ind(values_a, values_b)

            # Calculate effect size (Cohen's d)
            pooled_std = ((len(values_a) - 1) * statistics.stdev(values_a) ** 2 +
                         (len(values_b) - 1) * statistics.stdev(values_b) ** 2)
            pooled_std = (pooled_std / (len(values_a) + len(values_b) - 2)) ** 0.5
            effect_size = (statistics.mean(values_a) - statistics.mean(values_b)) / pooled_std if pooled_std > 0 else 0

            return StatisticalResult(
                metric=metric,
                test_name="Independent t-test",
                statistic=statistic,
                p_value=p_value,
                significant=p_value < 0.05,
                effect_size=effect_size
            )
        except ImportError:
            # Fallback without scipy
            mean_a = statistics.mean(values_a)
            mean_b = statistics.mean(values_b)

            return StatisticalResult(
                metric=metric,
                test_name="Mean comparison",
                statistic=mean_a - mean_b,
                p_value=1.0,
                significant=False,
                effect_size=None
            )

    def _find_best_by_metric(self, tool_stats: Dict[str, Dict]) -> Dict[str, str]:
        """Find best tool for each metric."""
        best = {}

        # Best runtime (lowest)
        if tool_stats:
            best["runtime"] = min(tool_stats.keys(), key=lambda t: tool_stats[t]["mean_runtime"])
            best["memory"] = min(tool_stats.keys(), key=lambda t: tool_stats[t]["mean_memory"])

            # Best quality metrics (highest)
            all_quality_metrics = set()
            for stats in tool_stats.values():
                all_quality_metrics.update(stats["quality_metrics"].keys())

            for metric in all_quality_metrics:
                tools_with_metric = {
                    t: s["quality_metrics"].get(metric, 0)
                    for t, s in tool_stats.items()
                    if metric in s["quality_metrics"]
                }
                if tools_with_metric:
                    best[metric] = max(tools_with_metric.keys(), key=lambda t: tools_with_metric[t])

        return best

    def _generate_recommendations(
        self,
        comparisons: List[ToolComparison],
        stats: Dict[str, Dict]
    ) -> List[str]:
        """Generate recommendations based on analysis."""
        recommendations = []

        if not comparisons:
            return recommendations

        best = comparisons[0]
        worst = comparisons[-1]

        # Speed recommendation
        speedup = worst.mean_runtime / best.mean_runtime if best.mean_runtime > 0 else 1
        if speedup > 1.5:
            recommendations.append(
                f"Consider using {best.tool_name} for {speedup:.1f}x faster execution compared to {worst.tool_name}."
            )

        # Memory recommendation
        if comparisons:
            lowest_memory = min(comparisons, key=lambda c: c.mean_memory)
            highest_memory = max(comparisons, key=lambda c: c.mean_memory)
            if highest_memory.mean_memory > lowest_memory.mean_memory * 2:
                recommendations.append(
                    f"For memory-constrained environments, prefer {lowest_memory.tool_name} "
                    f"(uses {lowest_memory.mean_memory:.1f}GB vs {highest_memory.mean_memory:.1f}GB)."
                )

        # Consistency recommendation
        for comp in comparisons:
            cv = comp.std_runtime / comp.mean_runtime if comp.mean_runtime > 0 else 0
            if cv > 0.3:
                recommendations.append(
                    f"{comp.tool_name} shows high runtime variability (CV={cv:.2f}). "
                    "Consider investigating system resource contention."
                )

        return recommendations

    def _generate_chart_data(
        self,
        comparisons: List[ToolComparison],
        tool_runs: Dict[str, List]
    ) -> Dict[str, Any]:
        """Generate data for visualization charts."""
        chart_data = {}

        # Bar chart data (mean runtime by tool)
        chart_data["runtime_bar"] = {
            "labels": [c.tool_name for c in comparisons],
            "values": [c.mean_runtime for c in comparisons],
            "errors": [c.std_runtime for c in comparisons]
        }

        # Memory bar chart
        chart_data["memory_bar"] = {
            "labels": [c.tool_name for c in comparisons],
            "values": [c.mean_memory for c in comparisons],
            "errors": [c.std_memory for c in comparisons]
        }

        # Box plot data (runtime distribution)
        chart_data["runtime_box"] = {}
        for tool_id, runs in tool_runs.items():
            tool_name = tool_id.split("/")[-1] if "/" in tool_id else tool_id
            runtimes = [r.runtime_seconds for r in runs if r.runtime_seconds]
            if runtimes:
                chart_data["runtime_box"][tool_name] = runtimes

        return chart_data

    def generate_report(
        self,
        comparison: ComparisonReport,
        format: str = "markdown"
    ) -> str:
        """
        Generate formatted report.

        Args:
            comparison: Comparison report to format
            format: Output format ('markdown', 'html', 'json')

        Returns:
            Formatted report string
        """
        if format == "json":
            return json.dumps(comparison.to_dict(), indent=2)
        elif format == "html":
            return self._generate_html_report(comparison)
        else:
            return self._generate_markdown_report(comparison)

    def _generate_markdown_report(self, report: ComparisonReport) -> str:
        """Generate Markdown report."""
        lines = [
            f"# Benchmark Report: {report.scenario_name}",
            f"",
            f"Generated: {report.generated_at}",
            f"",
            f"## Summary",
            f"",
            report.summary,
            f"",
            f"## Tool Comparison",
            f"",
            "| Rank | Tool | Avg Runtime | Std Dev | Avg Memory | Runs |",
            "|------|------|-------------|---------|------------|------|"
        ]

        for comp in report.tool_comparisons:
            lines.append(
                f"| {comp.rank} | {comp.tool_name} | {comp.mean_runtime:.2f}s | "
                f"{comp.std_runtime:.2f}s | {comp.mean_memory:.2f}GB | {comp.run_count} |"
            )

        lines.extend([
            f"",
            f"## Best by Metric",
            f""
        ])

        for metric, tool in report.best_by_metric.items():
            lines.append(f"- **{metric}**: {tool}")

        if report.statistical_results:
            lines.extend([
                f"",
                f"## Statistical Analysis",
                f""
            ])
            for stat in report.statistical_results:
                sig = "significant" if stat.significant else "not significant"
                lines.append(f"- {stat.metric}: p={stat.p_value:.4f} ({sig})")

        if report.recommendations:
            lines.extend([
                f"",
                f"## Recommendations",
                f""
            ])
            for rec in report.recommendations:
                lines.append(f"- {rec}")

        return "\n".join(lines)

    def _generate_html_report(self, report: ComparisonReport) -> str:
        """Generate HTML report."""
        html = f"""<!DOCTYPE html>
<html>
<head>
    <title>Benchmark Report: {report.scenario_name}</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 40px; }}
        h1 {{ color: #333; }}
        table {{ border-collapse: collapse; width: 100%; margin: 20px 0; }}
        th, td {{ border: 1px solid #ddd; padding: 12px; text-align: left; }}
        th {{ background-color: #4CAF50; color: white; }}
        tr:nth-child(even) {{ background-color: #f2f2f2; }}
        .summary {{ background: #e7f3fe; padding: 15px; border-left: 4px solid #2196F3; margin: 20px 0; }}
        .recommendations {{ background: #fff3cd; padding: 15px; border-left: 4px solid #ffc107; }}
        .best {{ font-weight: bold; color: #4CAF50; }}
    </style>
</head>
<body>
    <h1>Benchmark Report: {report.scenario_name}</h1>
    <p>Generated: {report.generated_at}</p>

    <div class="summary">
        <h2>Summary</h2>
        <p>{report.summary}</p>
    </div>

    <h2>Tool Comparison</h2>
    <table>
        <tr>
            <th>Rank</th>
            <th>Tool</th>
            <th>Avg Runtime</th>
            <th>Std Dev</th>
            <th>Avg Memory</th>
            <th>Runs</th>
        </tr>"""

        for comp in report.tool_comparisons:
            row_class = "best" if comp.rank == 1 else ""
            html += f"""
        <tr class="{row_class}">
            <td>{comp.rank}</td>
            <td>{comp.tool_name}</td>
            <td>{comp.mean_runtime:.2f}s</td>
            <td>{comp.std_runtime:.2f}s</td>
            <td>{comp.mean_memory:.2f}GB</td>
            <td>{comp.run_count}</td>
        </tr>"""

        html += """
    </table>

    <h2>Best by Metric</h2>
    <ul>"""

        for metric, tool in report.best_by_metric.items():
            html += f"\n        <li><strong>{metric}</strong>: {tool}</li>"

        html += """
    </ul>"""

        if report.recommendations:
            html += """
    <div class="recommendations">
        <h2>Recommendations</h2>
        <ul>"""
            for rec in report.recommendations:
                html += f"\n            <li>{rec}</li>"
            html += """
        </ul>
    </div>"""

        html += """
</body>
</html>"""

        return html

    def detect_regression(
        self,
        current: "BenchmarkResults",
        baseline: "BenchmarkResults",
        threshold_percent: float = 10.0
    ) -> Dict[str, Any]:
        """
        Detect performance regressions between two benchmark runs.

        Args:
            current: Current benchmark results
            baseline: Baseline to compare against
            threshold_percent: Percentage change threshold for regression

        Returns:
            Regression report
        """
        regressions = []
        improvements = []

        # Group runs by tool for both results
        current_by_tool = defaultdict(list)
        baseline_by_tool = defaultdict(list)

        for run in current.runs:
            if run.success:
                current_by_tool[run.tool_id].append(run)

        for run in baseline.runs:
            if run.success:
                baseline_by_tool[run.tool_id].append(run)

        # Compare each tool
        for tool_id in set(current_by_tool.keys()) & set(baseline_by_tool.keys()):
            current_runs = current_by_tool[tool_id]
            baseline_runs = baseline_by_tool[tool_id]

            current_runtime = statistics.mean([r.runtime_seconds for r in current_runs if r.runtime_seconds])
            baseline_runtime = statistics.mean([r.runtime_seconds for r in baseline_runs if r.runtime_seconds])

            if baseline_runtime > 0:
                change_percent = ((current_runtime - baseline_runtime) / baseline_runtime) * 100

                if change_percent > threshold_percent:
                    regressions.append({
                        "tool": tool_id,
                        "metric": "runtime",
                        "baseline": baseline_runtime,
                        "current": current_runtime,
                        "change_percent": change_percent
                    })
                elif change_percent < -threshold_percent:
                    improvements.append({
                        "tool": tool_id,
                        "metric": "runtime",
                        "baseline": baseline_runtime,
                        "current": current_runtime,
                        "change_percent": change_percent
                    })

        return {
            "has_regressions": len(regressions) > 0,
            "regressions": regressions,
            "improvements": improvements,
            "threshold_percent": threshold_percent,
            "tools_compared": len(set(current_by_tool.keys()) & set(baseline_by_tool.keys()))
        }

    def generate_plots(
        self,
        report: ComparisonReport,
        output_dir: str
    ) -> List[str]:
        """
        Generate visualization plots.

        Args:
            report: Comparison report with chart data
            output_dir: Directory to save plots

        Returns:
            List of generated plot file paths
        """
        try:
            import matplotlib.pyplot as plt
            import numpy as np
        except ImportError:
            log.warning("matplotlib not available for plot generation")
            return []

        output_path = Path(output_dir)
        output_path.mkdir(parents=True, exist_ok=True)
        generated = []

        # Runtime bar chart
        if "runtime_bar" in report.chart_data:
            data = report.chart_data["runtime_bar"]
            fig, ax = plt.subplots(figsize=(10, 6))
            x = np.arange(len(data["labels"]))
            bars = ax.bar(x, data["values"], yerr=data["errors"], capsize=5)
            ax.set_xlabel("Tool")
            ax.set_ylabel("Runtime (seconds)")
            ax.set_title(f"Runtime Comparison - {report.scenario_name}")
            ax.set_xticks(x)
            ax.set_xticklabels(data["labels"], rotation=45, ha="right")
            plt.tight_layout()
            path = output_path / "runtime_comparison.png"
            plt.savefig(path, dpi=150)
            plt.close()
            generated.append(str(path))

        # Memory bar chart
        if "memory_bar" in report.chart_data:
            data = report.chart_data["memory_bar"]
            fig, ax = plt.subplots(figsize=(10, 6))
            x = np.arange(len(data["labels"]))
            bars = ax.bar(x, data["values"], yerr=data["errors"], capsize=5, color="orange")
            ax.set_xlabel("Tool")
            ax.set_ylabel("Peak Memory (GB)")
            ax.set_title(f"Memory Comparison - {report.scenario_name}")
            ax.set_xticks(x)
            ax.set_xticklabels(data["labels"], rotation=45, ha="right")
            plt.tight_layout()
            path = output_path / "memory_comparison.png"
            plt.savefig(path, dpi=150)
            plt.close()
            generated.append(str(path))

        # Box plot for runtime distribution
        if "runtime_box" in report.chart_data:
            data = report.chart_data["runtime_box"]
            if data:
                fig, ax = plt.subplots(figsize=(10, 6))
                ax.boxplot(list(data.values()), labels=list(data.keys()))
                ax.set_xlabel("Tool")
                ax.set_ylabel("Runtime (seconds)")
                ax.set_title(f"Runtime Distribution - {report.scenario_name}")
                plt.xticks(rotation=45, ha="right")
                plt.tight_layout()
                path = output_path / "runtime_distribution.png"
                plt.savefig(path, dpi=150)
                plt.close()
                generated.append(str(path))

        return generated
