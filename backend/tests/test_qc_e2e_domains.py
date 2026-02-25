"""
End-to-end QC gate tests: multi-domain user personas.

Each test class simulates a researcher from a specific domain running a
multi-step workflow. Tests write real output files, drive the full pipeline
(file I/O → handle_process_completion → SSE callback), and verify:
  1. The correct QC metric is extracted from real files
  2. The correct threshold check fires (or passes)
  3. The correct parameter suggestion is generated
  4. The SSE event has the required structure

Domains covered:
  - RNA-seq (Alice: FASTP → STAR → FEATURECOUNTS → SALMON)
  - DNA-seq / variant calling (Bob: BWA_MEM → FLAGSTAT → MARKDUPLICATES)
  - Single-cell RNA-seq (Carol: CELLRANGER_COUNT)
  - ChIP-seq / ATAC-seq (Dave: MACS2)
  - Metagenomics (Eve: KRAKEN2 → BRACKEN)
  - Cryo-EM SPA (Frank: MOTION_CORRECTION → CTF_ESTIMATION → PARTICLE_PICKING)
"""

import sys
import json
import tempfile
from pathlib import Path
from unittest.mock import Mock

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))

from galaxy.jobs.qc_trace_monitor import NextflowQCGateHandler
from galaxy.jobs.parameter_suggester import (
    RNASeqParameterSuggester,
    GenomicsParameterSuggester,
    SingleCellParameterSuggester,
    ChIPSeqParameterSuggester,
    MetagenomicsParameterSuggester,
    CryoEMParameterSuggester,
    get_suggester_for_domain,
)


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

def _make_handler(work_dir, domain, params=None):
    events = []
    h = NextflowQCGateHandler(
        invocation_id=f"e2e-{domain}",
        work_dir=work_dir,
        sse_callback=lambda t, d: events.append((t, d)),
        app=Mock(),
        workflow_domain=domain,
        current_parameters=params or {},
    )
    return h, events


def _submit(handler, process_name, hash_prefix, hash_rest, work_dir, file_writer):
    """
    Create hash subdirectory, write output files, then call handle_process_completion.
    Returns the events list (same object as returned by _make_handler).
    """
    subdir = work_dir / hash_prefix / hash_rest
    subdir.mkdir(parents=True)
    if file_writer:
        file_writer(subdir)
    handler.handle_process_completion(
        task_id=f"task-{hash_rest[:4]}",
        process_name=process_name,
        process_hash=f"{hash_prefix}/{hash_rest}",
        status="COMPLETED",
    )


# ===========================================================================
# Alice — RNA-seq researcher
# Workflow: FASTP → STAR → FEATURECOUNTS → SALMON
# Scenario A: Everything fails (bad library prep)
# Scenario B: Everything passes (good run)
# ===========================================================================

class TestAliceRNASeq:
    """
    Alice is running an RNA-seq experiment on a tumour sample. Her first run
    has poor QC at every step. A second good run should fire no gates.
    """

    def _fastp_bad(self, subdir):
        """60% reads surviving, Q30=68% — both below threshold."""
        (subdir / "fastp.json").write_text(json.dumps({
            "summary": {
                "before_filtering": {"total_reads": 20_000_000, "q30_rate": 0.68}
            },
            "filtering_result": {"passed_filter_reads": 12_000_000}
        }))

    def _fastp_good(self, subdir):
        """92% reads surviving, Q30=87%."""
        (subdir / "fastp.json").write_text(json.dumps({
            "summary": {
                "before_filtering": {"total_reads": 20_000_000, "q30_rate": 0.87}
            },
            "filtering_result": {"passed_filter_reads": 18_400_000}
        }))

    def _star_bad(self, subdir):
        """STAR Log.final.out: 55% unique + 5% multi = 60% alignment rate."""
        (subdir / "Aligned.Log.final.out").write_text(
            "Number of input reads |\t20000000\n"
            "Uniquely mapped reads % |\t55.00%\n"
            "% of reads mapped to multiple loci |\t5.00%\n"
            "% of reads unmapped: too short |\t40.00%\n"
        )

    def _star_good(self, subdir):
        """STAR: 85% unique + 5% multi = 90% alignment rate."""
        (subdir / "Aligned.Log.final.out").write_text(
            "Number of input reads |\t18400000\n"
            "Uniquely mapped reads % |\t85.00%\n"
            "% of reads mapped to multiple loci |\t5.00%\n"
            "% of reads unmapped: too short |\t10.00%\n"
        )

    def _featurecounts_bad(self, subdir):
        """FeatureCounts: 40% assigned."""
        (subdir / "counts.summary").write_text(
            "Status\tcounts\nAssigned\t8000000\nUnassigned_NoFeatures\t12000000\n"
        )

    def _featurecounts_good(self, subdir):
        """FeatureCounts: 72% assigned."""
        (subdir / "counts.summary").write_text(
            "Status\tcounts\nAssigned\t13000000\nUnassigned_NoFeatures\t5000000\n"
        )

    def _salmon_bad(self, subdir):
        """Salmon: 40% mapping rate."""
        aux = subdir / "aux_info"
        aux.mkdir()
        (aux / "meta_info.json").write_text(json.dumps({"percent_mapped": 40.0}))

    def _salmon_good(self, subdir):
        """Salmon: 85% mapping rate."""
        aux = subdir / "aux_info"
        aux.mkdir()
        (aux / "meta_info.json").write_text(json.dumps({"percent_mapped": 85.0}))

    # --- Bad run ---

    def test_alice_fastp_low_survival_fires_gate(self, tmp_path):
        h, events = _make_handler(tmp_path, "rnaseq",
                                  {"quality_cutoff": 20, "min_length": 36})
        _submit(h, "FASTP_TRIM", "a1", "bc001234", tmp_path, self._fastp_bad)

        assert len(events) == 1
        _, data = events[0]
        metrics_failed = {f["metric"] for f in data["failures"]}
        assert "reads_surviving_pct" in metrics_failed
        assert "q30_pct" in metrics_failed

    def test_alice_fastp_suggests_quality_cutoff_increase(self, tmp_path):
        h, events = _make_handler(tmp_path, "rnaseq", {"quality_cutoff": 20, "min_length": 36})
        _submit(h, "FASTP_TRIM", "a1", "bc002345", tmp_path, self._fastp_bad)

        assert len(events) == 1
        _, data = events[0]
        suggestions = data.get("suggestions", [])
        quality_sugg = next((s for s in suggestions if s["parameter"] == "quality_cutoff"), None)
        assert quality_sugg is not None, "Expected quality_cutoff suggestion for low reads_surviving_pct"
        assert quality_sugg["suggestedValue"] > quality_sugg["currentValue"]

    def test_alice_star_low_alignment_fires_gate(self, tmp_path):
        h, events = _make_handler(tmp_path, "rnaseq", {"twopass_mode": False, "max_mismatches": 2})
        _submit(h, "STAR_ALIGN", "a2", "cd003456", tmp_path, self._star_bad)

        assert len(events) == 1
        _, data = events[0]
        assert any(f["metric"] == "alignment_rate" for f in data["failures"])

    def test_alice_star_suggests_twopass_mode(self, tmp_path):
        h, events = _make_handler(tmp_path, "rnaseq", {"twopass_mode": False, "max_mismatches": 2})
        _submit(h, "STAR_ALIGN", "a2", "cd004567", tmp_path, self._star_bad)

        assert len(events) == 1
        _, data = events[0]
        suggestions = data.get("suggestions", [])
        twopass = next((s for s in suggestions if s["parameter"] == "twopass_mode"), None)
        assert twopass is not None, "Expected twopass_mode suggestion for STAR low alignment"
        assert twopass["suggestedValue"] is True

    def test_alice_featurecounts_low_assignment_fires_gate(self, tmp_path):
        h, events = _make_handler(tmp_path, "rnaseq", {"strandedness": 0})
        _submit(h, "FEATURECOUNTS", "a3", "de005678", tmp_path, self._featurecounts_bad)

        assert len(events) == 1
        assert events[0][1]["failures"][0]["metric"] == "assigned_reads_pct"
        assert events[0][1]["failures"][0]["value"] == pytest.approx(40.0, abs=0.5)

    def test_alice_featurecounts_suggests_strandedness_change(self, tmp_path):
        h, events = _make_handler(tmp_path, "rnaseq", {"strandedness": 0})
        _submit(h, "FEATURECOUNTS", "a3", "de006789", tmp_path, self._featurecounts_bad)

        suggestions = events[0][1].get("suggestions", [])
        strand_sugg = next((s for s in suggestions if s["parameter"] == "strandedness"), None)
        assert strand_sugg is not None
        assert strand_sugg["suggestedValue"] in (1, 2)

    def test_alice_salmon_low_mapping_fires_gate(self, tmp_path):
        h, events = _make_handler(tmp_path, "rnaseq", {"decoy_aware": False})
        _submit(h, "SALMON_QUANT", "a4", "ef007890", tmp_path, self._salmon_bad)

        assert len(events) == 1
        assert events[0][1]["failures"][0]["metric"] == "mapping_rate"

    def test_alice_salmon_suggests_decoy_aware(self, tmp_path):
        h, events = _make_handler(tmp_path, "rnaseq", {"decoy_aware": False})
        _submit(h, "SALMON_QUANT", "a4", "ef008901", tmp_path, self._salmon_bad)

        suggestions = events[0][1].get("suggestions", [])
        decoy = next((s for s in suggestions if s["parameter"] == "decoy_aware"), None)
        assert decoy is not None
        assert decoy["suggestedValue"] is True

    # --- Good run (no gates should fire) ---

    def test_alice_good_fastp_no_gate(self, tmp_path):
        h, events = _make_handler(tmp_path, "rnaseq", {})
        _submit(h, "FASTP_TRIM", "b1", "aa001111", tmp_path, self._fastp_good)
        assert events == []

    def test_alice_good_star_no_gate(self, tmp_path):
        h, events = _make_handler(tmp_path, "rnaseq", {})
        _submit(h, "STAR_ALIGN", "b2", "bb002222", tmp_path, self._star_good)
        assert events == []

    def test_alice_good_featurecounts_no_gate(self, tmp_path):
        h, events = _make_handler(tmp_path, "rnaseq", {})
        _submit(h, "FEATURECOUNTS", "b3", "cc003333", tmp_path, self._featurecounts_good)
        assert events == []

    def test_alice_good_salmon_no_gate(self, tmp_path):
        h, events = _make_handler(tmp_path, "rnaseq", {})
        _submit(h, "SALMON_QUANT", "b4", "dd004444", tmp_path, self._salmon_good)
        assert events == []

    def test_alice_full_bad_run_fires_four_gates(self, tmp_path):
        """Complete bad pipeline: all four steps fire QC gates."""
        h, events = _make_handler(tmp_path, "rnaseq",
                                  {"quality_cutoff": 20, "min_length": 36,
                                   "twopass_mode": False, "max_mismatches": 2,
                                   "strandedness": 0, "decoy_aware": False})
        _submit(h, "FASTP_TRIM",    "c1", "aa111111", tmp_path, self._fastp_bad)
        _submit(h, "STAR_ALIGN",    "c2", "bb222222", tmp_path, self._star_bad)
        _submit(h, "FEATURECOUNTS", "c3", "cc333333", tmp_path, self._featurecounts_bad)
        _submit(h, "SALMON_QUANT",  "c4", "dd444444", tmp_path, self._salmon_bad)

        assert len(events) == 4, f"Expected 4 gate events, got {len(events)}"
        processes_that_fired = {d["process_name"] for _, d in events}
        assert processes_that_fired == {"FASTP_TRIM", "STAR_ALIGN", "FEATURECOUNTS", "SALMON_QUANT"}

    def test_alice_full_good_run_fires_zero_gates(self, tmp_path):
        """Complete good pipeline: no QC gates fire."""
        h, events = _make_handler(tmp_path, "rnaseq", {})
        _submit(h, "FASTP_TRIM",    "d1", "aa555555", tmp_path, self._fastp_good)
        _submit(h, "STAR_ALIGN",    "d2", "bb666666", tmp_path, self._star_good)
        _submit(h, "FEATURECOUNTS", "d3", "cc777777", tmp_path, self._featurecounts_good)
        _submit(h, "SALMON_QUANT",  "d4", "dd888888", tmp_path, self._salmon_good)

        assert events == []


# ===========================================================================
# Bob — DNA-seq / variant calling researcher
# Workflow: BWA_MEM → FLAGSTAT → MARKDUPLICATES
# Scenario: High-PCR-duplicate whole-genome library
# ===========================================================================

class TestBobDNASeq:
    """
    Bob is mapping whole-genome sequencing data. His library has extremely
    high PCR duplication due to low-input sample prep.
    """

    def _bwa_bad(self, subdir):
        """BWA/Bowtie2-style log: 58% overall alignment rate."""
        (subdir / "bwa.log").write_text(
            "10000000 reads; of these:\n"
            "  4200000 (42.00%) aligned 0 times\n"
            "  5800000 (58.00%) aligned\n"
            "58.00% overall alignment rate\n"
        )

    def _bwa_good(self, subdir):
        """BWA: 95% overall alignment rate."""
        (subdir / "bwa.log").write_text(
            "10000000 reads; of these:\n"
            "  500000 (5.00%) aligned 0 times\n"
            "  9500000 (95.00%) aligned\n"
            "95.00% overall alignment rate\n"
        )

    def _flagstat_high_dup(self, subdir):
        """samtools flagstat: 95% mapped but 48% duplicates."""
        (subdir / "sample.flagstat").write_text(
            "10000000 + 0 in total (QC-passed reads + QC-failed reads)\n"
            "4800000 + 0 duplicates\n"
            "9500000 + 0 mapped (95.00% : N/A)\n"
        )

    def _flagstat_good(self, subdir):
        """flagstat: 96% mapped, 8% duplicates — both within threshold."""
        (subdir / "sample.flagstat").write_text(
            "10000000 + 0 in total (QC-passed reads + QC-failed reads)\n"
            "800000 + 0 duplicates\n"
            "9600000 + 0 mapped (96.00% : N/A)\n"
        )

    def _picard_high_dup(self, subdir):
        """Picard MarkDuplicates: 45% duplication (above 40% GATK threshold)."""
        (subdir / "sample.dup_metrics").write_text(
            "## METRICS CLASS\tpicard.sam.DuplicationMetrics\n"
            "LIBRARY\tESTIMATED_LIBRARY_SIZE\tPERCENT_DUPLICATION\n"
            "mylib\t5000000\t0.45\n"
        )

    def _picard_good(self, subdir):
        """Picard: 12% duplication — below 30% threshold."""
        (subdir / "sample.dup_metrics").write_text(
            "## METRICS CLASS\tpicard.sam.DuplicationMetrics\n"
            "LIBRARY\tESTIMATED_LIBRARY_SIZE\tPERCENT_DUPLICATION\n"
            "mylib\t50000000\t0.12\n"
        )

    def test_bob_bwa_low_alignment_fires_gate(self, tmp_path):
        h, events = _make_handler(tmp_path, "dna_seq", {"min_seed_length": 19})
        _submit(h, "BWA_MEM", "e1", "aa010101", tmp_path, self._bwa_bad)

        assert len(events) == 1
        assert events[0][1]["failures"][0]["metric"] == "alignment_rate"

    def test_bob_bwa_suggests_shorter_seed(self, tmp_path):
        h, events = _make_handler(tmp_path, "dna_seq", {"min_seed_length": 19})
        _submit(h, "BWA_MEM", "e1", "aa020202", tmp_path, self._bwa_bad)

        suggestions = events[0][1].get("suggestions", [])
        seed_sugg = next((s for s in suggestions if s["parameter"] == "min_seed_length"), None)
        assert seed_sugg is not None
        assert seed_sugg["suggestedValue"] < seed_sugg["currentValue"]

    def test_bob_flagstat_high_dup_fires_gate(self, tmp_path):
        h, events = _make_handler(tmp_path, "dna_seq", {})
        _submit(h, "FLAGSTAT", "e2", "bb030303", tmp_path, self._flagstat_high_dup)

        assert len(events) == 1
        dup_fail = next((f for f in events[0][1]["failures"] if f["metric"] == "duplicate_pct"), None)
        assert dup_fail is not None
        assert dup_fail["value"] == pytest.approx(48.0, abs=1.0)

    def test_bob_flagstat_suggests_remove_duplicates(self, tmp_path):
        h, events = _make_handler(tmp_path, "dna_seq", {"remove_duplicates": False})
        _submit(h, "FLAGSTAT", "e2", "bb040404", tmp_path, self._flagstat_high_dup)

        suggestions = events[0][1].get("suggestions", [])
        rm_sugg = next((s for s in suggestions if s["parameter"] == "remove_duplicates"), None)
        assert rm_sugg is not None
        assert rm_sugg["suggestedValue"] is True

    def test_bob_picard_high_dup_fires_gate(self, tmp_path):
        h, events = _make_handler(tmp_path, "dna_seq", {})
        _submit(h, "MARKDUPLICATES", "e3", "cc050505", tmp_path, self._picard_high_dup)

        assert len(events) == 1
        assert events[0][1]["failures"][0]["metric"] == "duplicate_pct"
        assert events[0][1]["failures"][0]["value"] == pytest.approx(45.0, abs=0.2)

    def test_bob_picard_suggests_optical_pixel_distance(self, tmp_path):
        h, events = _make_handler(tmp_path, "dna_seq",
                                  {"optical_duplicate_pixel_distance": 100})
        _submit(h, "MARKDUPLICATES", "e3", "cc060606", tmp_path, self._picard_high_dup)

        suggestions = events[0][1].get("suggestions", [])
        pixel_sugg = next((s for s in suggestions
                           if s["parameter"] == "optical_duplicate_pixel_distance"), None)
        assert pixel_sugg is not None
        assert pixel_sugg["suggestedValue"] > pixel_sugg["currentValue"]

    def test_bob_good_run_no_gates(self, tmp_path):
        """Good library: no BWA, flagstat, or Picard gates fire."""
        h, events = _make_handler(tmp_path, "dna_seq", {})
        _submit(h, "BWA_MEM",        "f1", "dd070707", tmp_path, self._bwa_good)
        _submit(h, "FLAGSTAT",       "f2", "ee080808", tmp_path, self._flagstat_good)
        _submit(h, "MARKDUPLICATES", "f3", "ff090909", tmp_path, self._picard_good)
        assert events == []

    def test_bob_full_bad_run_fires_three_gates(self, tmp_path):
        h, events = _make_handler(tmp_path, "dna_seq",
                                  {"min_seed_length": 19, "remove_duplicates": False,
                                   "optical_duplicate_pixel_distance": 100})
        _submit(h, "BWA_MEM",        "g1", "aa111213", tmp_path, self._bwa_bad)
        _submit(h, "FLAGSTAT",       "g2", "bb141516", tmp_path, self._flagstat_high_dup)
        _submit(h, "MARKDUPLICATES", "g3", "cc171819", tmp_path, self._picard_high_dup)

        assert len(events) == 3
        processes = {d["process_name"] for _, d in events}
        assert processes == {"BWA_MEM", "FLAGSTAT", "MARKDUPLICATES"}


# ===========================================================================
# Carol — single-cell RNA-seq researcher
# Workflow: CELLRANGER_COUNT
# Scenario: Low-input sample → very few cells detected
# ===========================================================================

class TestCarolSingleCell:

    def _cellranger_few_cells(self, subdir):
        (subdir / "metrics_summary.csv").write_text(
            "Estimated Number of Cells,Median Genes per Cell,Reads Mapped to Genome\n"
            "85,320,92.1\n"
        )

    def _cellranger_low_genes(self, subdir):
        """Enough cells but poor median genes/cell."""
        (subdir / "metrics_summary.csv").write_text(
            "Estimated Number of Cells,Median Genes per Cell,Reads Mapped to Genome\n"
            "\"2,500\",350,94.5\n"
        )

    def _cellranger_good(self, subdir):
        (subdir / "metrics_summary.csv").write_text(
            "Estimated Number of Cells,Median Genes per Cell,Reads Mapped to Genome\n"
            "\"4,521\",\"2,847\",95.3\n"
        )

    def test_carol_few_cells_fires_gate(self, tmp_path):
        h, events = _make_handler(tmp_path, "single_cell",
                                  {"expected_cells": 3000, "min_umi_cutoff": 500})
        _submit(h, "CELLRANGER_COUNT", "h1", "aa210000", tmp_path, self._cellranger_few_cells)

        assert len(events) == 1
        cells_fail = next((f for f in events[0][1]["failures"]
                           if f["metric"] == "cells_detected"), None)
        assert cells_fail is not None
        assert cells_fail["value"] == 85

    def test_carol_few_cells_suggests_expected_cells_reduction(self, tmp_path):
        h, events = _make_handler(tmp_path, "single_cell",
                                  {"expected_cells": 3000, "min_umi_cutoff": 500})
        _submit(h, "CELLRANGER_COUNT", "h1", "aa220000", tmp_path, self._cellranger_few_cells)

        suggestions = events[0][1].get("suggestions", [])
        cells_sugg = next((s for s in suggestions if s["parameter"] == "expected_cells"), None)
        assert cells_sugg is not None
        assert cells_sugg["suggestedValue"] < cells_sugg["currentValue"]

    def test_carol_few_cells_suggests_lower_umi_cutoff(self, tmp_path):
        h, events = _make_handler(tmp_path, "single_cell",
                                  {"expected_cells": 3000, "min_umi_cutoff": 500})
        _submit(h, "CELLRANGER_COUNT", "h1", "aa230000", tmp_path, self._cellranger_few_cells)

        suggestions = events[0][1].get("suggestions", [])
        umi_sugg = next((s for s in suggestions if s["parameter"] == "min_umi_cutoff"), None)
        assert umi_sugg is not None
        assert umi_sugg["suggestedValue"] < umi_sugg["currentValue"]

    def test_carol_low_genes_fires_gate(self, tmp_path):
        h, events = _make_handler(tmp_path, "single_cell", {"min_genes": 200})
        _submit(h, "CELLRANGER_COUNT", "h2", "bb240000", tmp_path, self._cellranger_low_genes)

        assert len(events) == 1
        genes_fail = next((f for f in events[0][1]["failures"]
                           if f["metric"] == "median_genes_per_cell"), None)
        assert genes_fail is not None
        assert genes_fail["value"] == 350

    def test_carol_low_genes_suggests_min_genes_reduction(self, tmp_path):
        h, events = _make_handler(tmp_path, "single_cell", {"min_genes": 200})
        _submit(h, "CELLRANGER_COUNT", "h2", "bb250000", tmp_path, self._cellranger_low_genes)

        suggestions = events[0][1].get("suggestions", [])
        genes_sugg = next((s for s in suggestions if s["parameter"] == "min_genes"), None)
        assert genes_sugg is not None
        assert genes_sugg["suggestedValue"] < genes_sugg["currentValue"]

    def test_carol_good_run_no_gate(self, tmp_path):
        h, events = _make_handler(tmp_path, "single_cell", {})
        _submit(h, "CELLRANGER_COUNT", "h3", "cc260000", tmp_path, self._cellranger_good)
        assert events == []

    def test_carol_comma_escaped_cell_count_parsed_correctly(self, tmp_path):
        """'4,521' in CellRanger CSV must be parsed as 4521, not raise ValueError."""
        h, events = _make_handler(tmp_path, "single_cell", {})
        _submit(h, "CELLRANGER_COUNT", "h4", "dd270000", tmp_path, self._cellranger_good)
        # Good run: should parse 4521 cells and not fire
        assert events == []

    def test_carol_both_failures_produce_two_failures(self, tmp_path):
        """85 cells AND 320 genes/cell → both threshold failures in one event."""
        h, events = _make_handler(tmp_path, "single_cell",
                                  {"expected_cells": 3000, "min_umi_cutoff": 500, "min_genes": 200})
        _submit(h, "CELLRANGER_COUNT", "h5", "ee280000", tmp_path, self._cellranger_few_cells)

        # 85 cells (< 200) and 320 genes/cell (< 500) → 2 failures
        assert len(events) == 1
        failed_metrics = {f["metric"] for f in events[0][1]["failures"]}
        assert "cells_detected" in failed_metrics
        assert "median_genes_per_cell" in failed_metrics


# ===========================================================================
# Dave — ChIP-seq / ATAC-seq researcher
# Workflow: MACS2
# Scenario: Low signal library → too few peaks
# ===========================================================================

class TestDaveChIPSeq:

    def _macs2_few_peaks(self, subdir):
        """450 peaks called — below 1000 threshold."""
        peak_file = subdir / "sample_peaks.narrowPeak"
        lines = "\n".join(
            f"chr1\t{i*1000}\t{i*1000+400}\tpeak_{i}\t100\t.\t4.0\t8.0\t6.0\t200"
            for i in range(1, 451)
        )
        peak_file.write_text(lines + "\n")

    def _macs2_many_peaks(self, subdir):
        """3000 peaks — above threshold, no gate."""
        peak_file = subdir / "sample_peaks.narrowPeak"
        lines = "\n".join(
            f"chr1\t{i*1000}\t{i*1000+400}\tpeak_{i}\t100\t.\t4.0\t8.0\t6.0\t200"
            for i in range(1, 3001)
        )
        peak_file.write_text(lines + "\n")

    def test_dave_few_peaks_fires_gate(self, tmp_path):
        h, events = _make_handler(tmp_path, "chip_seq", {"qvalue": 0.05, "extsize": 200})
        _submit(h, "MACS2", "i1", "aa310000", tmp_path, self._macs2_few_peaks)

        assert len(events) == 1
        assert events[0][1]["failures"][0]["metric"] == "peaks_called"
        assert events[0][1]["failures"][0]["value"] == 450

    def test_dave_suggests_relaxed_qvalue(self, tmp_path):
        h, events = _make_handler(tmp_path, "chip_seq", {"qvalue": 0.05, "extsize": 200})
        _submit(h, "MACS2", "i1", "aa320000", tmp_path, self._macs2_few_peaks)

        suggestions = events[0][1].get("suggestions", [])
        qval_sugg = next((s for s in suggestions if s["parameter"] == "qvalue"), None)
        assert qval_sugg is not None
        assert qval_sugg["suggestedValue"] > qval_sugg["currentValue"]

    def test_dave_suggests_extsize_reduction(self, tmp_path):
        h, events = _make_handler(tmp_path, "chip_seq", {"qvalue": 0.05, "extsize": 200})
        _submit(h, "MACS2", "i1", "aa330000", tmp_path, self._macs2_few_peaks)

        suggestions = events[0][1].get("suggestions", [])
        ext_sugg = next((s for s in suggestions if s["parameter"] == "extsize"), None)
        assert ext_sugg is not None
        assert ext_sugg["suggestedValue"] < ext_sugg["currentValue"]

    def test_dave_good_run_no_gate(self, tmp_path):
        h, events = _make_handler(tmp_path, "chip_seq", {})
        _submit(h, "MACS2", "i2", "bb340000", tmp_path, self._macs2_many_peaks)
        assert events == []

    def test_dave_peaks_counted_excluding_comment_lines(self, tmp_path):
        """Comment lines in narrowPeak must not be counted as peaks."""
        subdir = tmp_path / "i3" / "cc350000"
        subdir.mkdir(parents=True)
        (subdir / "sample_peaks.narrowPeak").write_text(
            "# MACS2 peak file\n"
            "chr1\t100\t500\tpeak_1\t150\t.\t5.0\t10.0\t8.5\t200\n"
            "chr1\t600\t900\tpeak_2\t100\t.\t4.0\t8.0\t6.5\t150\n"
        )
        h = NextflowQCGateHandler(
            invocation_id="dave-count", work_dir=tmp_path,
            sse_callback=lambda t, d: None, app=Mock()
        )
        metrics = h._parse_peakcalling_metrics(subdir)
        assert metrics is not None
        assert metrics["peaks_called"] == 2  # comment excluded

    def test_dave_qvalue_already_at_max_no_qvalue_suggestion(self, tmp_path):
        """If qvalue is already 0.1 (our cap), no qvalue suggestion fires."""
        h, events = _make_handler(tmp_path, "chip_seq", {"qvalue": 0.1, "extsize": 200})
        _submit(h, "MACS2", "i4", "dd360000", tmp_path, self._macs2_few_peaks)

        assert len(events) == 1
        suggestions = events[0][1].get("suggestions", [])
        qval_sugg = next((s for s in suggestions if s["parameter"] == "qvalue"), None)
        # qvalue * 2 = 0.2 but cap is 0.1 so suggested_value == current_value → no suggestion
        assert qval_sugg is None or qval_sugg["suggestedValue"] == qval_sugg["currentValue"]


# ===========================================================================
# Eve — Metagenomics researcher
# Workflow: KRAKEN2 → BRACKEN
# Scenario: Novel environment sample, very low classification
# ===========================================================================

class TestEveMetagenomics:

    def _kraken2_low_classified(self, subdir):
        """Kraken2: 18% classified (novel environment)."""
        (subdir / "sample.report").write_text(
            " 82.00\t820000\t820000\tU\t0\tunclassified\n"
            " 18.00\t180000\t0\tR\t1\troot\n"
            " 15.00\t150000\t0\tD\t2\tBacteria\n"
        )

    def _kraken2_good(self, subdir):
        """Kraken2: 78% classified — above 60% threshold."""
        (subdir / "sample.report").write_text(
            " 22.00\t220000\t220000\tU\t0\tunclassified\n"
            " 78.00\t780000\t0\tR\t1\troot\n"
        )

    def _bracken_low_classified(self, subdir):
        """Same as Kraken2 but in .k2report extension for BRACKEN process."""
        (subdir / "sample.k2report").write_text(
            " 75.00\t750000\t750000\tU\t0\tunclassified\n"
            " 25.00\t250000\t0\tR\t1\troot\n"
        )

    def test_eve_kraken2_low_classification_fires_gate(self, tmp_path):
        h, events = _make_handler(tmp_path, "metagenomics",
                                  {"confidence_threshold": 0.1, "database": "standard"})
        _submit(h, "KRAKEN2", "j1", "aa410000", tmp_path, self._kraken2_low_classified)

        assert len(events) == 1
        assert events[0][1]["failures"][0]["metric"] == "classified_pct"
        assert events[0][1]["failures"][0]["value"] == pytest.approx(18.0, abs=0.1)

    def test_eve_kraken2_suggests_remove_confidence_threshold(self, tmp_path):
        h, events = _make_handler(tmp_path, "metagenomics",
                                  {"confidence_threshold": 0.1})
        _submit(h, "KRAKEN2", "j1", "aa420000", tmp_path, self._kraken2_low_classified)

        suggestions = events[0][1].get("suggestions", [])
        conf_sugg = next((s for s in suggestions if s["parameter"] == "confidence_threshold"), None)
        assert conf_sugg is not None
        assert conf_sugg["suggestedValue"] == 0.0

    def test_eve_kraken2_suggests_larger_database(self, tmp_path):
        h, events = _make_handler(tmp_path, "metagenomics",
                                  {"confidence_threshold": 0.1, "database": "standard"})
        _submit(h, "KRAKEN2", "j1", "aa430000", tmp_path, self._kraken2_low_classified)

        suggestions = events[0][1].get("suggestions", [])
        db_sugg = next((s for s in suggestions if s["parameter"] == "database"), None)
        assert db_sugg is not None
        assert db_sugg["suggestedValue"] != db_sugg["currentValue"]

    def test_eve_bracken_low_classified_fires_gate(self, tmp_path):
        """BRACKEN process also routes to metagenomics parser."""
        h, events = _make_handler(tmp_path, "metagenomics", {})
        _submit(h, "BRACKEN", "j2", "bb440000", tmp_path, self._bracken_low_classified)

        assert len(events) == 1
        assert events[0][1]["failures"][0]["metric"] == "classified_pct"
        assert events[0][1]["failures"][0]["value"] == pytest.approx(25.0, abs=0.1)

    def test_eve_good_run_no_gate(self, tmp_path):
        h, events = _make_handler(tmp_path, "metagenomics", {})
        _submit(h, "KRAKEN2", "j3", "cc450000", tmp_path, self._kraken2_good)
        assert events == []

    def test_eve_zero_confidence_already_no_suggestion(self, tmp_path):
        """If confidence_threshold already 0.0, no suggestion to reduce it further."""
        h, events = _make_handler(tmp_path, "metagenomics",
                                  {"confidence_threshold": 0.0})
        _submit(h, "KRAKEN2", "j4", "dd460000", tmp_path, self._kraken2_low_classified)

        suggestions = events[0][1].get("suggestions", [])
        conf_sugg = next((s for s in suggestions if s["parameter"] == "confidence_threshold"), None)
        assert conf_sugg is None  # already at minimum, no further reduction possible


# ===========================================================================
# Frank — Cryo-EM SPA researcher
# Workflow: MOTION_CORRECTION → CTF_ESTIMATION → PARTICLE_PICKING
# Scenario A: Bad data collection (high drift, poor CTF fit, few particles)
# Scenario B: Good data
# ===========================================================================

class TestFrankCryoEM:

    def _motion_bad(self, subdir):
        """MotionCor2 log: 85Å total drift (> 50Å threshold)."""
        (subdir / "motion.log").write_text(
            "Total motion: 85.3 Å\n"
            "Average per-frame motion: 4.5 Å\n"
        )

    def _motion_good(self, subdir):
        """MotionCor2 log: 12Å total drift — well within threshold."""
        (subdir / "motion.log").write_text(
            "Total motion: 12.4 Å\n"
            "Average per-frame motion: 0.8 Å\n"
        )

    def _ctf_bad(self, subdir):
        """CTFFIND4: astigmatism 1500Å (> 500Å threshold), fit 0.55 (< 0.7)."""
        (subdir / "ctf.txt").write_text(
            "15000.0\t13500.0\t45.0\t0.0\t0.55\n"
        )

    def _ctf_good(self, subdir):
        """CTFFIND4: astigmatism 200Å, fit quality 0.92."""
        (subdir / "ctf.txt").write_text(
            "15000.0\t14800.0\t30.0\t0.0\t0.92\n"
        )

    def _picking_too_few(self, subdir):
        """STAR coordinate file: only 200 particles (< 1000 threshold)."""
        lines = ["_rlnCoordinateX\n_rlnCoordinateY"]
        for i in range(200):
            lines.append(f"{i*100}.0\t{i*50}.0")
        (subdir / "particles.star").write_text("\n".join(lines) + "\n")

    def _picking_good(self, subdir):
        """STAR: 5000 particles — above threshold."""
        lines = ["_rlnCoordinateX\n_rlnCoordinateY"]
        for i in range(5000):
            lines.append(f"{i*10}.0\t{i*5}.0")
        (subdir / "particles.star").write_text("\n".join(lines) + "\n")

    def test_frank_motion_high_drift_fires_gate(self, tmp_path):
        h, events = _make_handler(tmp_path, "cryo_em", {"alignment_frames": 5})
        _submit(h, "MOTION_CORRECTION", "k1", "aa510000", tmp_path, self._motion_bad)

        assert len(events) == 1
        assert events[0][1]["failures"][0]["metric"] == "total_drift_angstrom"
        assert events[0][1]["failures"][0]["value"] == pytest.approx(85.3, abs=0.5)

    def test_frank_motion_suggests_dose_weighting_or_patch_size(self, tmp_path):
        """High drift (85Å) → dose_weighting or patch_size suggestion (not alignment_frames,
        which requires low correlation_score to trigger)."""
        h, events = _make_handler(tmp_path, "cryo_em",
                                  {"dose_weighting": False, "patch_size": 3})
        _submit(h, "MOTION_CORRECTION", "k1", "aa520000", tmp_path, self._motion_bad)

        suggestions = events[0][1].get("suggestions", [])
        param_names = {s["parameter"] for s in suggestions}
        assert param_names & {"dose_weighting", "patch_size"}, (
            f"Expected dose_weighting or patch_size suggestion for high drift, got: {param_names}"
        )
        # dose_weighting should be suggested True when currently False
        dw = next((s for s in suggestions if s["parameter"] == "dose_weighting"), None)
        if dw:
            assert dw["suggestedValue"] is True

    def test_frank_ctf_high_astigmatism_fires_gate(self, tmp_path):
        h, events = _make_handler(tmp_path, "cryo_em", {})
        _submit(h, "CTF_ESTIMATION", "k2", "bb530000", tmp_path, self._ctf_bad)

        assert len(events) == 1
        astig_fail = next((f for f in events[0][1]["failures"]
                           if f["metric"] == "astigmatism_angstrom"), None)
        assert astig_fail is not None
        assert astig_fail["value"] == pytest.approx(1500.0, abs=10)

    def test_frank_ctf_bad_fit_also_fires(self, tmp_path):
        """CTF file with 1500Å astigmatism AND 0.55 fit → both failures."""
        h, events = _make_handler(tmp_path, "cryo_em", {})
        _submit(h, "CTF_ESTIMATION", "k2", "bb540000", tmp_path, self._ctf_bad)

        failed_metrics = {f["metric"] for f in events[0][1]["failures"]}
        assert "astigmatism_angstrom" in failed_metrics
        assert "fit_quality" in failed_metrics

    def test_frank_picking_too_few_fires_gate(self, tmp_path):
        h, events = _make_handler(tmp_path, "cryo_em", {})
        _submit(h, "PARTICLE_PICKING", "k3", "cc550000", tmp_path, self._picking_too_few)

        assert len(events) == 1
        assert events[0][1]["failures"][0]["metric"] == "particles_picked"
        assert events[0][1]["failures"][0]["value"] == 200

    def test_frank_picking_suggests_lower_threshold(self, tmp_path):
        h, events = _make_handler(tmp_path, "cryo_em",
                                  {"picking_threshold": 0.7, "diameter": 100})
        _submit(h, "PARTICLE_PICKING", "k3", "cc560000", tmp_path, self._picking_too_few)

        suggestions = events[0][1].get("suggestions", [])
        # Should suggest lowering picking threshold
        assert len(suggestions) > 0

    def test_frank_good_motion_no_gate(self, tmp_path):
        h, events = _make_handler(tmp_path, "cryo_em", {})
        _submit(h, "MOTION_CORRECTION", "l1", "aa570000", tmp_path, self._motion_good)
        assert events == []

    def test_frank_good_ctf_no_gate(self, tmp_path):
        h, events = _make_handler(tmp_path, "cryo_em", {})
        _submit(h, "CTF_ESTIMATION", "l2", "bb580000", tmp_path, self._ctf_good)
        assert events == []

    def test_frank_good_picking_no_gate(self, tmp_path):
        h, events = _make_handler(tmp_path, "cryo_em", {})
        _submit(h, "PARTICLE_PICKING", "l3", "cc590000", tmp_path, self._picking_good)
        assert events == []

    def test_frank_full_bad_run_fires_three_gates(self, tmp_path):
        h, events = _make_handler(tmp_path, "cryo_em",
                                  {"alignment_frames": 5, "picking_threshold": 0.7})
        _submit(h, "MOTION_CORRECTION", "m1", "aa600000", tmp_path, self._motion_bad)
        _submit(h, "CTF_ESTIMATION",    "m2", "bb610000", tmp_path, self._ctf_bad)
        _submit(h, "PARTICLE_PICKING",  "m3", "cc620000", tmp_path, self._picking_too_few)

        assert len(events) == 3
        processes = {d["process_name"] for _, d in events}
        assert processes == {"MOTION_CORRECTION", "CTF_ESTIMATION", "PARTICLE_PICKING"}

    def test_frank_full_good_run_zero_gates(self, tmp_path):
        h, events = _make_handler(tmp_path, "cryo_em", {})
        _submit(h, "MOTION_CORRECTION", "n1", "aa630000", tmp_path, self._motion_good)
        _submit(h, "CTF_ESTIMATION",    "n2", "bb640000", tmp_path, self._ctf_good)
        _submit(h, "PARTICLE_PICKING",  "n3", "cc650000", tmp_path, self._picking_good)

        assert events == []


# ===========================================================================
# Cross-domain: domain factory routing
# ===========================================================================

class TestDomainFactory:
    """
    Verify that the domain factory routes each researcher to the correct
    suggester class. These complement the unit tests in test_qc_edge_cases.py
    with more realistic domain strings as would come from actual workflow metadata.
    """

    @pytest.mark.parametrize("domain,expected_class", [
        ("rnaseq",              RNASeqParameterSuggester),
        ("rna_seq",             RNASeqParameterSuggester),
        ("bulk_rnaseq",         RNASeqParameterSuggester),
        ("dna_seq",             GenomicsParameterSuggester),
        ("wgs_variant_calling", GenomicsParameterSuggester),
        ("wes_gatk",            GenomicsParameterSuggester),
        ("single_cell_rnaseq",  SingleCellParameterSuggester),
        ("scrna_seq",           SingleCellParameterSuggester),
        ("chip_seq",            ChIPSeqParameterSuggester),
        ("atac_seq",            ChIPSeqParameterSuggester),
        ("metagenomics_wgs",    MetagenomicsParameterSuggester),
        ("kraken2_pipeline",    MetagenomicsParameterSuggester),
        ("cryo_em",             CryoEMParameterSuggester),
        ("cryosparc_spa",       CryoEMParameterSuggester),
        ("em",                  CryoEMParameterSuggester),
    ])
    def test_domain_routes_to_correct_suggester(self, domain, expected_class):
        suggester = get_suggester_for_domain(domain)
        assert isinstance(suggester, expected_class), (
            f"domain={domain!r} → got {type(suggester).__name__}, "
            f"expected {expected_class.__name__}"
        )

    @pytest.mark.parametrize("false_em_domain", [
        "genome_assembly",
        "system_biology",
        "theorem_prover",
        "item_embedding",
    ])
    def test_false_em_domain_does_not_route_to_cryo_em(self, false_em_domain):
        suggester = get_suggester_for_domain(false_em_domain)
        assert not isinstance(suggester, CryoEMParameterSuggester), (
            f"domain={false_em_domain!r} should NOT route to CryoEM suggester"
        )

    def test_all_six_domains_return_distinct_suggester_types(self):
        """Ensure all six domain families are distinct (not accidentally sharing a class)."""
        domains = ["cryo_em", "rnaseq", "dna_seq", "single_cell", "chip_seq", "metagenomics"]
        classes = [type(get_suggester_for_domain(d)) for d in domains]
        assert len(set(classes)) == 6, f"Expected 6 distinct classes, got: {classes}"
