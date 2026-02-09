"""
Genomics pilot analysis plugin.

Quick data characterization for genomics workflows: ChIP-seq, RNA-seq, DNA-seq, etc.
"""

from typing import Dict
from ..base import PilotAnalysisPlugin, AnalyzerSpec


class GenomicsPilotPlugin(PilotAnalysisPlugin):
    """Pilot analyzers for genomics domain."""

    @property
    def domain_name(self) -> str:
        return "genomics"

    @property
    def dependencies(self) -> list:
        return [
            "samtools",
            "fastqc",
            "phantompeakqualtools",
            "seqkit",
        ]

    @property
    def analyzers(self) -> Dict[str, AnalyzerSpec]:
        return {
            "estimate_fragment_size": AnalyzerSpec(
                name="estimate_fragment_size",
                category="genomics",
                description="Estimate DNA fragment size from BAM file using insert size distribution",
                input_type="bam",
                tool="samtools_stats",
                command_template="samtools stats {input_file} | grep '^SN' | grep 'insert size average'",
                extract="insert_size_average",
                runtime_estimate="~30s per 10M reads",
                max_runtime_seconds=300,
                sample_strategy="first_10M_reads",
                fallback=200,
                output_type="integer",
                units="bp",
                typical_range=[100, 500],
            ),
            "estimate_fragment_shift": AnalyzerSpec(
                name="estimate_fragment_shift",
                category="genomics",
                description="Estimate fragment shift for ChIP-seq using cross-correlation analysis",
                input_type="bam",
                tool="phantompeakqualtools",
                command_template="Rscript run_spp.R -c={input_file} -savp -out={output_file}",
                extract=["strand_shift", "nsc", "rsc"],
                runtime_estimate="~2min per 100M reads",
                max_runtime_seconds=300,
                sample_strategy="subsample_to_10M",
                fallback=None,
                output_type="dict",
                validation={
                    "nsc": {"min": 1.0, "recommended": 1.05},
                    "rsc": {"min": 0.8, "recommended": 1.0},
                },
            ),
            "detect_sequencing_protocol": AnalyzerSpec(
                name="detect_sequencing_protocol",
                category="genomics",
                description="Detect if data is single-end or paired-end sequencing",
                input_type="bam",
                tool="samtools_view",
                command_template="samtools view -c -f 1 {input_file} | head -1000",
                extract="sequencing_protocol",
                runtime_estimate="<5s",
                max_runtime_seconds=10,
                sample_strategy="first_1000_reads",
                fallback="single_end",
                output_type="string",
                possible_values=["single_end", "paired_end"],
            ),
            "estimate_read_quality": AnalyzerSpec(
                name="estimate_read_quality",
                category="genomics",
                description="Quick quality assessment with FastQC (plots disabled for speed)",
                input_type="fastq",
                tool="fastqc_lite",
                command_template="fastqc --extract --nogroup -o /tmp/ {input_file}",
                extract=["mean_quality_score", "sequence_duplication_level", "gc_content", "total_sequences"],
                runtime_estimate="~1min per 50M reads",
                max_runtime_seconds=120,
                sample_strategy="subsample_to_1M",
                fallback={"mean_quality_score": 30, "gc_content": 50},
                output_type="dict",
            ),
            "count_reads_and_depth": AnalyzerSpec(
                name="count_reads_and_depth",
                category="genomics",
                description="Count total reads and estimate sequencing depth",
                input_type="bam",
                tool="samtools_flagstat",
                command_template="samtools flagstat {input_file}",
                extract=["total_reads", "mapped_reads", "properly_paired"],
                runtime_estimate="<30s",
                max_runtime_seconds=60,
                sample_strategy="full_file",
                fallback=None,
                output_type="dict",
                derived_metrics={
                    "mapping_rate": "mapped_reads / total_reads",
                    "estimated_depth": "mapped_reads * read_length / genome_size",
                },
            ),
            "analyze_template_gc_content": AnalyzerSpec(
                name="analyze_template_gc_content",
                category="genomics",
                description="Analyze GC content of template sequence for primer design",
                input_type="fasta",
                tool="seqkit_fx2tab",
                command_template="seqkit fx2tab --gc {input_file}",
                extract=["gc_percentage", "sequence_length"],
                runtime_estimate="<10s for sequences <10kb",
                max_runtime_seconds=30,
                sample_strategy="full_sequence",
                fallback=50.0,
                output_type="float",
                typical_range=[20, 80],
                thresholds={"at_rich": 35, "balanced": 65, "gc_rich": 65},
            ),
        }
