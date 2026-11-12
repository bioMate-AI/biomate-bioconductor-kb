"""
Data-perception profiler — OmniScientist "look at the raw data first".

Given a dataset file, this module emits a ``DataProfile`` matching the shape the
frontend ``DataPerception`` panel consumes (frontend
``data-perception.tsx`` on ``feat/dl-upgrade-wave3``):

    {
      shape: { rows, cols },
      leakage?: { detail },
      effectiveN?: number,
      classBalance?: [{ label, frac }],
      signalSummary?: string[],
      quality: 'good' | 'watch' | 'blocked',
      notes: string[]
    }

plus a ``planImpact: [{ observed, effect }]`` list.

DESIGN — RULES-FIRST, DETERMINISTIC (per CLAUDE.md "rules first, LLM as
fallback"): all numeric profiling here is pure arithmetic on the data. There is
NO LLM call and NO network access. When a file type can't be profiled we return
the shape (or an honest zero shape) plus a note — we NEVER fabricate a leakage /
balance / effective-N number for a file we didn't actually parse.

Reuse: FASTQ read counting mirrors
``galaxy.ai.workflow_ops.autofix.dataset_validator.DatasetValidator._count_fastq_reads``
(sampled, gzip-aware). Table parsing uses the stdlib ``csv`` module so this
module has ZERO third-party dependencies (no pandas/numpy) and imports cleanly
in the Galaxy backend on Python 3.9.
"""
from __future__ import annotations

import codecs
import csv
import io
import json
import logging
import os
import re
import threading
import zlib
from collections import Counter
from dataclasses import dataclass, field
from typing import Any, Dict, Iterator, List, Optional, Sequence, Tuple

log = logging.getLogger(__name__)

# A delimited cell may be far larger than the csv module's 128 KiB default (a sequence, a JSON
# blob, an embedded table): such a file is valid, not "malformed". Raised, never lowered.
_CSV_FIELD_LIMIT = 256 * 1024 * 1024
if csv.field_size_limit() < _CSV_FIELD_LIMIT:
    csv.field_size_limit(_CSV_FIELD_LIMIT)

# ---------------------------------------------------------------------------
# Tunables (all deterministic thresholds — documented so notes can cite them).
# ---------------------------------------------------------------------------

# A single feature column that predicts the label at or above this accuracy is
# flagged as suspected target leakage (a column that "trivially predicts").
LEAKAGE_ACC_THRESHOLD = 0.98

# A batch/id column whose value→label mapping is this pure (each batch value
# maps to one dominant label at or above this rate) is a batch↔label confound.
BATCH_CONFOUND_PURITY = 0.98

# A batch/id-like column has few distinct values relative to rows. This is the
# max ratio distinct/rows for a column to be treated as a grouping key.
BATCH_MAX_DISTINCT_FRAC = 0.5

# Column is "near-constant" if its single most common value covers this frac.
NEAR_CONSTANT_FRAC = 0.99
# The near-constant rule (_near_constant_expected) raises Watch only when BOTH hold:
#   1. the table has at least NEAR_CONSTANT_MIN_ROWS data rows — on a handful of rows "over 99%
#      a single value" just means "every row agrees", which says nothing about the data (the same
#      floor as MODEL_MIN_ROWS for the label statistics);
#   2. the column is not per-record PROVENANCE of a record file: in JSON Lines every record is
#      stamped by its extractor with where it came from (source, document, drug, file …), so one
#      scalar value in EVERY record is expected, not a defect.
# A near-constant column failing either is stated once at info level (``expected`` says why:
# "few_rows" | "record_metadata"); it never makes the verdict Watch.
NEAR_CONSTANT_MIN_ROWS = 20

# Column is "high-missingness" at or above this missing frac.
HIGH_MISSING_FRAC = 0.5

# Minority class below this fraction → imbalance note + watch.
IMBALANCE_MINORITY_FRAC = 0.2
# The same rule for any number of classes: imbalanced when the smallest class is below this
# share of the largest (binary: minority < 20% ⇔ minority/majority < 0.25). Comparing the
# minority to a fixed 20% called a perfectly balanced 7-class label (14% each) "imbalanced".
IMBALANCE_MINORITY_RATIO = IMBALANCE_MINORITY_FRAC / (1 - IMBALANCE_MINORITY_FRAC)

# Cap on rows scanned for table profiling (keeps ingest cheap on huge files).
MAX_TABLE_ROWS = 200_000
# Small caps for the Preview-tab sample (columns + first rows) — kept tiny so the
# profile response stays light; the full table lives behind the table viewer.
MAX_PREVIEW_COLS = 12
MAX_PREVIEW_ROWS = 100  # was 8: the preview showed 8 rows with no way to see more
# Long cells (e.g. a JSONL record's nested arrays) are trimmed in the preview sample only.
MAX_PREVIEW_CELL_CHARS = 300

# Column-name tokens that mark a plausible classification LABEL column, most label-like first
# (matched as WHOLE tokens of the column name: "gene_symbol" is not "y", "assay" is not "y").
_LABEL_NAME_TOKENS = (
    "label", "target", "class", "y", "outcome", "diagnosis", "response", "responder",
    "phenotype", "condition", "genotype", "treatment", "group", "status",
)

# Column-name tokens that mark a plausible BATCH / grouping / id column, most batch-like first.
_BATCH_NAME_TOKENS = (
    "batch", "plate", "run", "lane", "site", "center", "centre", "cohort", "study",
    "donor", "subject", "patient", "id", "uuid", "barcode",
)

# Column-name tokens that mark a train/test SPLIT column.
_SPLIT_NAME_TOKENS = ("split", "fold", "partition", "subset")


# ---------------------------------------------------------------------------
# Result container
# ---------------------------------------------------------------------------
@dataclass
class DataProfile:
    """Mirror of the frontend ``DataProfile`` TS interface."""

    structured: Optional[Dict[str, Any]] = None
    rows: int = 0
    cols: int = 0
    # good | watch | blocked | unassessed. "unassessed": the file was identified (and, where the
    # format has it, its metadata read) but its content was not analysed (images, PDF, archives,
    # BAM/CRAM headers, h5ad/loom/xlsx/mtx/sdf/pod5 metadata, JSON structure). "watch": something
    # worth checking was found.
    quality: str = "good"
    notes: List[str] = field(default_factory=list)
    leakage_detail: Optional[str] = None
    effective_n: Optional[int] = None
    class_balance: Optional[List[Tuple[str, float]]] = None
    signal_summary: Optional[List[str]] = None
    plan_impact: List[Tuple[str, str]] = field(default_factory=list)
    # A small tabular sample so the dataset object's Preview tab can show the
    # actual data (columns + first rows), not just identity metadata. Populated
    # only for table-like inputs; capped small (see MAX_PREVIEW_*).
    columns: Optional[List[str]] = None
    sample_rows: Optional[List[List[str]]] = None
    # Structured, localizable mirror of every free-text note / signal / leakage /
    # plan-impact line: {section, code, level, params}. The UI renders these through
    # i18n (perception.msg.<code>) so the card is never a mix of languages; the
    # free-text lists stay for non-UI consumers (chat context, logs). ``level`` is
    # "info" | "watch" | "blocked" — the findings at the verdict's level ARE the
    # reason for that verdict ("why Watch?").
    findings: List[Dict[str, Any]] = field(default_factory=list)
    # Which reduction bound effective N: "dedup" (exact duplicate rows) or
    # "imbalance" (k × minority-class size). The profiler does not estimate a
    # correlation-based effective N, so it never emits "correlation".
    effective_n_reason: Optional[str] = None
    duplicate_rows: Optional[int] = None
    # Rows actually held for statistics when the file exceeds MAX_TABLE_ROWS
    # (``rows`` is always the true total). None when every row was profiled.
    profiled_rows: Optional[int] = None
    # The file's format for the UI's format chip: {"ext", "label", "source"} where source is
    # "galaxy" (identified by Galaxy's datatype sniffers) or "biomate" (this module's own sniff).
    format: Optional[Dict[str, Any]] = None
    # How the panel shows the content (see VIEW_KINDS), decided content-first.
    view_kind: str = "unknown"
    # The measures that make sense for the view kind: [{"code", "value", "atLeast"?}].
    stats: List[Dict[str, Any]] = field(default_factory=list)
    # Measures set by the type profilers (code → value) and which of them are lower bounds.
    stats_map: Dict[str, int] = field(default_factory=dict)
    at_least: set = field(default_factory=set)
    # "," when the table's numbers use a decimal comma (serialized only then, as ``decimal``).
    decimal: Optional[str] = None
    # A 3D structure's provenance (see _structure_provenance) — serialized as ``structure``.
    structure: Optional[Dict[str, Any]] = None
    # The class-label column, when one was found: {"column", "confident"}. ``confident`` is True
    # only for a MODELLING table (see _modelling_label) — class balance, effective N and the
    # leakage checks are computed only then. Serialized as ``label``.
    label: Optional[Dict[str, Any]] = None
    # Per-column type + statistics over the profiled rows, parsed with the table's decimal mark
    # (see _column_stats). Serialized as ``columnStats``.
    column_stats: Optional[List[Dict[str, Any]]] = None
    # The spreadsheet sheet the columns / sample_rows preview comes from (xlsx).
    preview_sheet: Optional[str] = None
    # AnnData layers (the keys of the h5ad's ``layers`` group; [] when it has none) — separate
    # from its stored HDF5 groups. Serialized as ``layers`` (h5ad only).
    layers: Optional[List[str]] = None

    def to_dict(self) -> Dict[str, Any]:
        """Serialize to the exact JSON shape the frontend consumes."""
        out: Dict[str, Any] = {
            "shape": {"rows": self.rows, "cols": self.cols},
            "quality": self.quality,
            "notes": list(self.notes),
        }
        if self.structured is not None:
            out["structured"] = self.structured
        if self.leakage_detail:
            out["leakage"] = {"detail": self.leakage_detail}
        if self.effective_n is not None:
            out["effectiveN"] = self.effective_n
            if self.effective_n_reason:
                out["effectiveNReason"] = self.effective_n_reason
        if self.duplicate_rows is not None:
            out["duplicateRows"] = self.duplicate_rows
        if self.label is not None:
            out["label"] = dict(self.label)
            if self.label.get("confident"):
                # The client reads THIS: present only for a confident label (W7), and classBalance
                # / effectiveN / leakage are computed only then.
                out["labelColumn"] = self.label["column"]
        if self.layers is not None:
            out["layers"] = list(self.layers)
        if self.column_stats is not None:
            out["columnStats"] = [dict(c) for c in self.column_stats]
        if self.preview_sheet is not None:
            out["previewSheet"] = self.preview_sheet
        if self.profiled_rows is not None:
            out["profiledRows"] = self.profiled_rows
        if self.format is not None:
            out["format"] = dict(self.format)
        if self.decimal:
            out["decimal"] = self.decimal
        if self.structure is not None:
            out["structure"] = dict(self.structure)
        out["viewKind"] = self.view_kind
        out["stats"] = [dict(s) for s in self.stats]
        out["findings"] = [dict(f) for f in self.findings]
        if self.class_balance:
            out["classBalance"] = [
                {"label": lbl, "frac": frac} for lbl, frac in self.class_balance
            ]
        if self.signal_summary:
            out["signalSummary"] = list(self.signal_summary)
        # planImpact lives alongside the profile in the frontend props.
        out["planImpact"] = [
            {"observed": obs, "effect": eff} for obs, eff in self.plan_impact
        ]
        if self.columns:
            out["columns"] = list(self.columns)
        if self.sample_rows is not None:
            out["sampleRows"] = [list(r) for r in self.sample_rows]
        return out


# English text of every finding — the same wording as the UI's en locale
# (frontend locales/en/common.json ``perception.msg.<code>``), so chat context, logs and the card
# say the same thing. ``{{name}}`` placeholders are the finding's params; counts are written so
# they read correctly for 1 and for many ("Columns with …: a, b", never "column(s)").
_EN_TEXT: Dict[str, str] = {
    'file_not_found': "The file could not be found.",
    'no_path': "No dataset path was provided.",
    'empty_file': "The file is empty (0 bytes).",
    'unprofilable': "This file type cannot be read here ({{name}}); only its size is reported.",
    'parse_failed': "The file could not be parsed; it may be malformed or in a different format than its name suggests.",
    'no_ref': "No dataset reference was provided.",
    'unresolvable_ref': "The dataset reference could not be resolved to a readable file.",
    'structured_too_large': "Structural validation is limited to files under 2 million characters; download the file for a complete check.",
    'structured_only': "Valid {{format}} syntax ({{root}} root). Only the structure was checked; scientific quality has not been assessed.",
    'fastq_reads': "Reads scanned: {{reads}}; mean read length {{mean_len}} bp.",
    'fastq_mean_quality': "Mean base quality: Phred {{q}} (sampled; Phred 20 = 1 error in 100 bases, 30 = 1 in 1,000).",
    'fastq_single_file': "Profiled on its own: whether it has a read-2 mate was not checked.",
    'fastq_single_end': "Single FASTQ file",
    'fastq_single_end_effect': "single-end pipeline suggested (override if a paired mate exists)",
    'fastq_low_quality': "Mean base quality Phred {{q}} is below 20 (more than 1 error in 100 bases) — consider trimming.",
    'fastq_no_records': "No FASTQ records could be parsed — the file may be malformed.",
    'vcf_records': "Variant records: {{variants}}; samples: {{samples}}.",
    'vcf_no_variants': "No variant records were found (header only).",
    'no_columns': "No columns could be parsed from the table.",
    'header_only': "A header is present but there are no data rows.",
    'near_constant': "Near-constant columns (over {{pct}}% a single value): {{columns}}.",
    'high_missing': "Columns with at least {{pct}}% missing values: {{columns}}.",
    'label_spellings': "Two spellings of the same label: “{{a}}” and “{{b}}”.",
    'minority_class': "Class “{{label}}” is only {{pct}}% of rows — consider a balanced sampler.",
    'effective_n_imbalance': "Effective N ({{n}}) is far below the row count ({{rows}}) — bounded by the minority class under strong imbalance.",
    'effective_n_dedup': "Effective N ({{n}}) is below the row count ({{rows}}) — duplicate rows ({{duplicates}}) reduce the independent samples.",
    'label_free_text': "Column “{{column}}” looks like a label, but its distinct values ({{distinct}}) make it free text, not a class target.",
    'table_summary': "Rows: {{rows}} · columns: {{cols}}.",
    'table_clean': "Rows: {{rows}} · columns: {{cols}}; groups are balanced, no column gives the group away, and no column is constant.",
    'profiled_subset': "Statistics were computed on the first {{profiled}} of {{rows}} rows.",
    'leaked_id': "Column “{{column}}” differs in almost every row yet matches the groups exactly — it probably encodes the group (e.g. a sample ID containing the condition); do not use it as a predictor.",
    'leaked_feature': "Column “{{column}}” matches the groups in {{pct}}% of rows — it may encode the group itself; check it before using it in a model.",
    'drop_leaky_column': "“{{column}}” reveals the group",
    'drop_leaky_column_effect': "leave “{{column}}” out of any model that predicts the group",
    'batch_confound': "“{{column}}” (batch) lines up almost exactly with the groups, so batch and condition effects cannot be separated — a design problem for differential analysis.",
    'group_nested': "Each value of “{{column}}” occurs in only one group of “{{label}}”, so {{column}} and {{label}} effects cannot be separated — a confounded design; dropping the column does not fix it.",
    'batch_covariate': "“{{column}}” overlaps with the groups",
    'batch_covariate_effect': "include “{{column}}” in the design (e.g. as a covariate) for differential analysis",
    'split_overlap': "Feature rows that appear in more than one split: {{count}} — train/test overlap.",
    'dedup_splits': "Train/test overlap",
    'dedup_splits_effect': "de-duplicate rows across splits before evaluation",
    'nested_tables': "Column “{{column}}” holds embedded tables: {{tables}}; rows per table: median {{median_rows}}, largest {{max_rows}}; columns per table: median {{median_cols}}.",
    'nested_row_cap': "{{pct}}% of the tables in column “{{column}}” have the maximum row count ({{max_rows}}), far more than any other size: they were probably cut off when extracted. Check the extraction before analysing them.",
    'nested_blank_cells': "{{pct}}% of the cells in the tables of column “{{column}}” are blank — typical of merged or multi-line cells in extracted tables; join continuation rows before analysis.",
    'columns_generated': "No header row detected (line 1 holds data values); columns are named column_1, column_2, …",
    'columns_spec': "{{format}} files have no header row; column names follow the {{format}} specification: {{columns}}.",
    'columns_comment': "Column names taken from the file's last “#” comment line: {{columns}}.",
    'intervals_summary': "Genomic intervals: {{regions}}; columns: {{columns}}.",
    'intervals_stranded': "Strand is given (column “{{column}}”).",
    'intervals_unstranded': "No strand column: the intervals are treated as unstranded.",
    'annotation_features': "Feature lines: {{features}}; comment lines: {{comments}}; attribute keys ({{count}}): {{attributes}}.",
    'molecules_count': "Molecules: {{molecules}}.",
    'mtx_bad_header': "Not a readable Matrix Market file: the %%MatrixMarket banner or the size line is missing.",
    'mtx_dimensions': "Sparse matrix of {{field}} values; {{density}}% of its cells hold a stored entry.",
    'mtx_dense': "Dense matrix of {{field}} values.",
    'mtx_orientation': "Matrix Market files carry no row or column names: pair this matrix with its features and barcodes files (10x: rows are features, columns are cells).",
    'format_metadata_only': "{{format}} metadata was read; the data values themselves have not been analysed.",
    'format_identified': "Identified as {{format}} ({{size}}); its contents are not analysed here.",
    'format_metadata_skipped': "{{format}} metadata was not read: the file ({{size}}) is above the {{cap}} limit for reading during upload.",
    'format_header_unreadable': "The {{format}} header could not be read; the file may be truncated or malformed.",
    'fasta_sequences': "Sequences: {{sequences}}; {{total}} {{unit}} in total; length mean {{mean}}, min {{min}}, max {{max}}, N50 {{n50}} (half of all bases lie in sequences at least this long).",
    'fasta_no_sequences': "No “>” sequence headers found.",
    'anndata_shape': "Rows of the matrix X are cells (obs); its columns are genes or features (var).",
    'anndata_obs': "Cell annotation columns ({{count}}): {{columns}}.",
    'anndata_var': "Gene annotation columns ({{count}}): {{columns}}.",
    'anndata_embeddings': "Stored embeddings: {{embeddings}}.",
    'loom_shape': "Rows of the matrix are genes; its columns are cells (the loom layout, transposed relative to AnnData).",
    'loom_row_attrs': "Gene attributes: {{columns}}.",
    'loom_col_attrs': "Cell attributes: {{columns}}.",
    'loom_layers': "Layers: {{layers}}.",
    'alignment_references': "Total length of the reference sequences in the header: {{length}} bp.",
    'alignment_sorted': "Coordinate-sorted (header SO:coordinate).",
    'alignment_not_coordinate_sorted': "Sort order is {{order_words}}, not by coordinate: sort the file before indexing or variant calling.",
    'alignment_read_groups': "Read groups: {{count}}; samples: {{samples}}.",
    'alignment_no_read_groups': "No read groups (@RG) in the header: GATK and most variant callers require them.",
    'structure_chains': "Chains ({{count}}): {{chains}}.",
    'spreadsheet_sheets': "Sheets ({{count}}): {{sheets}}.",
    'spreadsheet_convert': "Spreadsheets are not checked cell by cell: export the sheet to CSV to get the table checks.",
    'fasta_gc': "GC content {{pct}}%.",
    'fasta_high_n': "{{pct}}% of bases are N (unknown): gaps or a low-quality assembly.",
    'fasta_protein': "Protein sequences (amino-acid alphabet).",
    'fasta_empty_records': "Headers with no sequence: {{count}}.",
    'fasta_orphan_lines': "Sequence lines before the first “>” header, which were ignored: {{count}}.",
    'fasta_profiled_subset': "Statistics cover the first {{mb}} MB of the file.",
    'fastq_paired_mate': "Read {{read}} of sample {{sample}}; its mate {{mate}} is in the same folder.",
    'fastq_paired_end': "Both reads of the pair present",
    'fastq_paired_end_effect': "paired-end pipeline (sample {{sample}})",
    'fastq_mate_missing': "Read {{read}} of sample {{sample}}; no read-{{missing}} mate is in this folder.",
    'fastq_orphan_single_end': "Read pair incomplete",
    'fastq_orphan_single_end_effect': "single-end for sample {{sample}} until the mate is added",
    'fastq_single_end_named': "No read-1/read-2 naming and no mate in this folder.",
    'tenx_member_headerless': "Part of the 10x matrix {{matrix}} in this folder: header-less by the 10x specification, so line 1 is data.",
    'mtx_tenx_set': "10x matrix: rows are the features in {{features}}, columns are the cells in {{barcodes}} (same folder).",
    'name_content_mismatch': "Named as {{named}}, but the content is {{detected}} — it is shown and checked as {{detected}}.",
    'compressed_unreadable': "The compressed file could not be decompressed: it is corrupt or not actually compressed.",
    'compressed_corrupt': "The compressed data is corrupt partway through, so the file cannot be read reliably.",
    'compressed_truncated': "The compressed file ends early (truncated): only the readable part was checked.",
    'nul_bytes': "Lines with NUL bytes, which were ignored: {{lines}}.",
    'jsonl_skipped_lines': "Lines that are not valid JSON were skipped: {{count}}.",
    'ragged_rows': "Rows whose number of fields differs from the header's ({{expected}}): {{count}}.",
    'table_clean_unlabelled': "Rows: {{rows}} · columns: {{cols}}; no constant columns or missing-value problems. No group column (e.g. condition) was found, so group sizes were not checked.",
    'few_data_rows': "Too few data rows for the column and label checks (rows: {{rows}}).",
    'blank_content': "The file holds only blank lines.",
    'comment_lines_skipped': "Comment lines before the table were skipped: {{count}}.",
    'fastq_malformed_records': "Records that do not follow the four-line FASTQ layout (or whose quality line differs in length from the sequence): {{count}} of {{checked}} checked.",
    'fastq_index_read': "Index read ({{read}}) of sample {{sample}}: it holds the sample barcodes, not biological reads, and is used only for demultiplexing.",
    'vcf_malformed_lines': "Data lines with fewer than 8 tab-separated columns: {{count}}.",
    'text_encoding_legacy': "The file is not UTF-8 text; it was read as {{encoding}}. Check that accented or non-Latin characters display correctly — tools that expect UTF-8 may misread them.",
    'text_encoding_replaced': "Byte sequences that are not valid UTF-8 were replaced with “�”: {{count}}.",
    'duplicate_column_names': "Column names used more than once: {{columns}}. Tools that look columns up by name keep only one of them or rename them.",
    'structure_experimental': "Experimental structure ({{method}}): the B-factor column holds atomic displacement, not prediction confidence.",
    'structure_predicted': "Predicted model ({{predictor}}), not an experimental structure: the B-factor column holds the predictor's per-residue confidence (pLDDT for AlphaFold-type models).",
    'anndata_layers': "Layers stored beside X ({{count}}): {{layers}}.",
    'anndata_no_layers': "No layers: the expression values are in X only.",
    'anndata_components': "Stored components ({{count}}): {{components}}.",
    'label_few_rows': "Column “{{column}}” looks like a group column (e.g. condition), but with {{rows}} rows (at least {{min_rows}} needed) group sizes and columns that reveal the group were not checked.",
    'label_no_features': "Column “{{column}}” looks like a group column, but the other columns are identifiers or annotation, so there is nothing to compare between the groups.",
    'table_clean_label_unchecked': "Rows: {{rows}} · columns: {{cols}}; no constant columns or missing-value problems.",
    'duplicate_rows': "Exact duplicate rows: {{count}}.",
    'spreadsheet_preview': "Preview of sheet “{{sheet}}”: its first rows (rows shown: {{rows}}).",
    'spreadsheet_preview_sheets': "Sheets ({{count}}): {{sheets}}; the preview shows the first rows of “{{sheet}}” (rows shown: {{rows}}).",
    'sample_groups_from_names': "Sample columns form groups by name: {{groups}}.",
}

_PLACEHOLDER = re.compile(r"{{\s*(\w+)\s*}}")
# Counts written as "at least N" when the finding says they are lower bounds.
_AT_LEAST_PARAMS = {"fastq_reads": "reads", "fasta_sequences": "sequences"}


def _fmt_param(v: Any) -> str:
    if isinstance(v, bool):
        return "yes" if v else "no"
    if isinstance(v, int):
        return f"{v:,}"
    if isinstance(v, float):
        return f"{v:,.2f}".rstrip("0").rstrip(".") if not v.is_integer() else f"{int(v):,}"
    if isinstance(v, (list, tuple)):
        if v and all(isinstance(x, dict) and "name" in x and "n" in x for x in v):
            # Named counts ({name, n} — sample_groups_from_names): "ctrl (2) · treat (2)".
            return " · ".join(f"{x['name']} ({_fmt_param(x['n'])})" for x in v)
        return ", ".join(str(x) for x in v)
    return str(v)


def finding_text(code: str, params: Dict[str, Any]) -> Optional[str]:
    """The English sentence for a finding (None when the code has no template)."""
    tpl = _EN_TEXT.get(code)
    if tpl is None:
        return None
    vals = {k: _fmt_param(v) for k, v in params.items()}
    if code in _AT_LEAST_PARAMS and params.get("at_least"):
        key = _AT_LEAST_PARAMS[code]
        vals[key] = "at least " + vals.get(key, "")
    return _PLACEHOLDER.sub(lambda m: vals.get(m.group(1), ""), tpl)


def emit(
    p: DataProfile,
    section: str,
    code: str,
    text: str,
    level: str = "info",
    **params: Any,
) -> None:
    """Record one profiler finding as BOTH its legacy free-text line and a structured,
    localizable finding (``section`` is "note" | "signal" | "leakage" | "plan").

    The free text is the finding's English template (``_EN_TEXT``, the UI's en wording) filled
    with ``params``; ``text`` is used only for a code without a template. For "plan", the text
    is the observed side and the effect comes from ``<code>_effect`` (or ``params["effect_text"]``).
    Params must be JSON-serializable (they are interpolated by the UI's i18n strings).
    """
    effect_fallback = str(params.pop("effect_text", ""))
    line = finding_text(code, params) or text
    if section == "note":
        p.notes.append(line)
    elif section == "signal":
        p.signal_summary = (p.signal_summary or []) + [line]
    elif section == "leakage":
        p.leakage_detail = f"{p.leakage_detail} {line}" if p.leakage_detail else line
    elif section == "plan":
        p.plan_impact.append((line, finding_text(code + "_effect", params) or effect_fallback))
    else:  # pragma: no cover — programming error
        raise ValueError(f"unknown finding section {section!r}")
    finding: Dict[str, Any] = {"section": section, "code": code, "level": level, "params": params}
    cols = params.get("columns")
    if isinstance(cols, (list, tuple)):
        finding["columns"] = [str(c) for c in cols]
    elif isinstance(params.get("column"), str):
        finding["columns"] = [params["column"]]
    p.findings.append(finding)


def blocked_profile(code: str, text: str, **params: Any) -> DataProfile:
    """A ``blocked`` profile carrying one blocked finding (used by the API layer too)."""
    p = DataProfile(quality="blocked")
    emit(p, "note", code, text, "blocked", **params)
    return p


# Columns named in a finding's params are capped so the payload stays small.
_MAX_NAMED_COLUMNS = 8


# ---------------------------------------------------------------------------
# Public entrypoints
# ---------------------------------------------------------------------------
def profile_dataset(
    path: str, *, name: Optional[str] = None, context: Optional[Dict[str, Any]] = None
) -> Dict[str, Any]:
    """Profile a dataset file and return the frontend ``DataProfile`` dict.

    Decides what the file IS from its content (Galaxy's datatype identification + BioMate's own
    validation; the name only states a claim, and a contradiction is a finding), dispatches to a
    type-specific profiler, and always returns a valid shape. Never raises: unreadable inputs
    (a corrupt gzip, an unparseable file) yield a ``blocked`` profile.

    ``context`` = ``{"name": <project path>, "siblings": [<other paths in its folder>]}`` (the
    server that owns the project's file list supplies it). Facts that live at FOLDER level —
    a FASTQ's mate, a 10x features/barcodes file's role — come from it through the same
    folder_profile functions the folder view uses; without it they are stated as unknown.
    """
    return profile_to_dataclass(path, name=name, context=context).to_dict()


_UNKNOWN_DECISION = ("binary", "unknown", "unknown", "Unknown", "biomate")


def profile_to_dataclass(
    path: str, *, name: Optional[str] = None, context: Optional[Dict[str, Any]] = None
) -> DataProfile:
    """Same as :func:`profile_dataset` but returns the dataclass (for tests)."""
    display = name or (os.path.basename(path) if path else "")
    unknown = Decision(*_UNKNOWN_DECISION)
    if not path or not os.path.exists(path):
        p = blocked_profile("file_not_found" if path else "no_path", "")
        return _finish(p, unknown)
    try:
        size = os.path.getsize(path)
    except OSError:
        size = -1
    _reset_damage()
    try:
        empty = _empty_content(path, size)
        if empty:
            return _finish(blocked_profile(empty, ""), unknown)
        d = decide(path, display)
    except UnreadableContent:
        return _finish(blocked_profile("compressed_unreadable", ""), unknown)
    except Exception as e:  # noqa: BLE001 — profiling must never crash ingest
        log.warning("[perception] format decision failed for %s: %s", path, e)
        return _finish(blocked_profile("parse_failed", "", error=_reason(e)), unknown)
    try:
        p = _run_profiler(path, d, display, size, context)
    except Exception as e:  # noqa: BLE001 — defensive: profiling must never crash ingest.
        log.warning("[perception] profiling failed for %s: %s", path, e)
        p = blocked_profile("parse_failed", "", error=_reason(e))
    dmg = _damage()
    if dmg["corrupt"]:
        # Data decoded from a stream that failed its integrity check is not trustworthy.
        p = blocked_profile("compressed_corrupt", "")
    elif dmg["truncated"]:
        emit(p, "note", "compressed_truncated", "", "watch")
    if dmg["nul_lines"]:
        emit(p, "note", "nul_bytes", "", "watch", lines=dmg["nul_lines"])
    if not dmg["corrupt"]:
        if d.encoding in _LEGACY_ENCODINGS:
            emit(p, "note", "text_encoding_legacy", "", "watch", encoding=ENCODING_NAMES[d.encoding])
        if dmg["replaced"]:
            emit(p, "note", "text_encoding_replaced", "", "watch", count=dmg["replaced"])
    if d.mismatch:
        emit(p, "note", "name_content_mismatch", "", "watch", named=d.mismatch[0], detected=d.mismatch[1])
        p.findings.insert(0, p.findings.pop())
    return _finish(p, d)


def _empty_content(path: str, size: int) -> Optional[str]:
    """The blocking finding for a file with no content — "empty_file" (0 bytes) or "blank_content"
    (only whitespace, after decompression) — or None. ONE gate for the profile and read_rows, so
    an empty file is never "blocked" in the card and a pageable table in the grid."""
    if size == 0:
        return "empty_file"
    head = _raw_head(path, HEAD_BYTES)
    if len(head) < HEAD_BYTES:
        if _utf16_bom(head) or _utf16_encoding(head):
            enc = "utf-16" if _utf16_bom(head) else _utf16_encoding(head)
            blank = not head.decode(enc or "utf-16", errors="replace").strip()
        else:
            blank = not head.lstrip(b"\xef\xbb\xbf").strip(b" \t\r\n\x0b\x0c")
        if blank:
            return "blank_content"
    return None


def _run_profiler(path: str, d: "Decision", display: str, size: int,
                  context: Optional[Dict[str, Any]]) -> DataProfile:
    if d.kind == "table":
        member = _context_tenx(context)
        if member and member["role"] in _tenx_columns():
            layout = _tenx_layout(path, member["role"])
            d.layout = layout
            p = _profile_table(path, layout=layout)
            emit(p, "note", "tenx_member_headerless", "", role=member["role"], matrix=member["matrix"])
            return p
        layout = d.layout or _table_layout(path)
        if not layout.valid:
            raise ValueError("table layout invalid")
        p = _profile_table(path, layout=layout)
        if layout.spec:
            _spec_table_findings(p, path, layout, d.gext)
        return p
    if d.kind == "jsonl":
        return _profile_table(path, reader=_read_jsonl)
    if d.kind in ("json", "yaml"):
        return _profile_structured(path, d.kind)
    if d.kind == "fastq":
        return _profile_fastq(path, layout=_context_fastq(context))
    if d.kind == "fasta":
        return _profile_fasta(path)
    if d.kind == "vcf":
        return _profile_vcf(path)
    if d.kind == "mtx":
        return _profile_mtx(path, member=_context_tenx(context))
    if d.kind in ("galaxy", "binary") and d.ext not in ("binary", "unknown"):
        p = _profile_galaxy_format(path, d.ext, size, d.label)
        if d.ext in _STRUCTURE_FORMATS and d.kind == "galaxy":
            _structure_findings(p, path, d.ext)
        return p
    if d.kind == "text":
        if _blank_only(path):
            return blocked_profile("blank_content", "")
        p = DataProfile()
        if not d.mismatch:
            # Under a name that claims another format the name/content note (added by the caller)
            # already says what the file is and that it is shown as that text: one note, never a
            # second "identified as …; not analysed" line beside it.
            emit(p, "note", "format_identified", "", format=d.label, size=_human_size(size))
        return p
    p = DataProfile()
    emit(p, "note", "unprofilable", "", name=os.path.basename(display), ext=d.ext)
    return p


# The measures that make sense for each view kind (``stats`` in the profile, in this order).
_VIEW_STATS: Dict[str, Tuple[str, ...]] = {
    "table": ("rows", "columns", "molecules"), "records": ("records", "columns", "tables"),
    "intervals": ("regions", "columns"), "annotation": ("features", "columns"),
    "reads": ("reads", "read_length"), "sequences": ("sequences", "bases"),
    "variants": ("variants", "samples"), "alignment": ("references",),
    "anndata": ("cells", "genes"), "loom": ("cells", "genes"), "matrix": ("rows", "columns", "entries"),
    "molecules": ("molecules",), "structure": ("chains",), "document": ("sheets",), "json": ("entries",),
}
# Views whose content BioMate analyses (others are identified or described from metadata only).
_ASSESSED_VIEWS = frozenset({"table", "records", "intervals", "annotation", "reads", "sequences", "variants"})


def _finish(p: DataProfile, d: "Decision") -> DataProfile:
    """Format, view kind, stats and the verdict — one place, for every path."""
    p.format = d.format()
    p.view_kind = "unknown" if p.quality == "blocked" else d.view
    v = p.view_kind
    base: Dict[str, int] = {}
    if v in ("table", "records", "intervals", "annotation"):
        first = {"table": "rows", "records": "records", "intervals": "regions", "annotation": "features"}[v]
        base = {first: p.rows, "columns": p.cols}
    vals = dict(base, **p.stats_map)
    stats: List[Dict[str, Any]] = []
    for code in _VIEW_STATS.get(v, ()):
        val = vals.get(code)
        if isinstance(val, int) and not isinstance(val, bool) and val >= 0:
            item: Dict[str, Any] = {"code": code, "value": val}
            if code in p.at_least:
                item["atLeast"] = True
            stats.append(item)
    p.stats = stats
    levels = {f["level"] for f in p.findings}
    if p.quality == "blocked" or "blocked" in levels:
        p.quality = "blocked"
    elif "watch" in levels:
        p.quality = "watch"
    else:
        p.quality = "good" if p.view_kind in _ASSESSED_VIEWS else "unassessed"
    return p


def _reason(exc: BaseException) -> str:
    """A short, human reason for a parse failure — never the raw exception text (it can carry
    temp paths and library internals); the full error goes to the log."""
    if isinstance(exc, UnicodeError):
        return "the text encoding could not be read"
    if isinstance(exc, (json.JSONDecodeError,)):
        return "the JSON is not valid"
    if isinstance(exc, csv.Error):
        return "the table's quoting or delimiters are malformed"
    if isinstance(exc, (EOFError, zlib.error)):
        return "the file is truncated"
    if isinstance(exc, MemoryError):
        return "the file is too large to read here"
    if type(exc).__name__ in ("YAMLError", "ScannerError", "ParserError", "ComposerError"):
        return "the YAML is not valid"
    return "its content is malformed"



# ---------------------------------------------------------------------------
# Galaxy datatypes (format identification + metadata) — see galaxy_formats.py
# ---------------------------------------------------------------------------
_GF_MODULE: List[Any] = []


def _galaxy_formats() -> Any:
    """The galaxy_formats module. Inside Galaxy it is imported as a package module; when this
    file is loaded on its own (unit tests, scripts) the sibling file is loaded by path so the
    heavy ``galaxy.ai`` package __init__ is never triggered. Returns None if it cannot load."""
    if _GF_MODULE:
        return _GF_MODULE[0]
    mod = None
    try:
        import sys

        if "galaxy.ai" in sys.modules:
            import importlib

            mod = importlib.import_module("galaxy.ai.galaxy_formats")
        else:
            import importlib.util

            sib = os.path.join(os.path.dirname(os.path.abspath(__file__)), "galaxy_formats.py")
            spec = importlib.util.spec_from_file_location("_biomate_galaxy_formats", sib)
            if spec and spec.loader:
                mod = importlib.util.module_from_spec(spec)
                sys.modules["_biomate_galaxy_formats"] = mod
                spec.loader.exec_module(mod)
    except Exception as exc:  # noqa: BLE001 — Galaxy formats are an enhancement, never required
        log.info("[perception] galaxy_formats unavailable: %s", exc)
        mod = None
    _GF_MODULE.append(mod)
    return mod


_FP_MODULE: List[Any] = []


def _folder_profile() -> Any:
    """The folder_profile module (same loading rule as :func:`_galaxy_formats`)."""
    if _FP_MODULE:
        return _FP_MODULE[0]
    mod = None
    try:
        import sys

        if "galaxy.ai" in sys.modules:
            import importlib

            mod = importlib.import_module("galaxy.ai.folder_profile")
        else:
            import importlib.util

            sib = os.path.join(os.path.dirname(os.path.abspath(__file__)), "folder_profile.py")
            spec = importlib.util.spec_from_file_location("_biomate_folder_profile", sib)
            if spec and spec.loader:
                mod = importlib.util.module_from_spec(spec)
                sys.modules["_biomate_folder_profile"] = mod
                spec.loader.exec_module(mod)
    except Exception as exc:  # noqa: BLE001 — folder context is an enhancement, never required
        log.warning("[perception] folder_profile unavailable: %s", exc)
        mod = None
    _FP_MODULE.append(mod)
    return mod


def _context_parts(context: Optional[Dict[str, Any]]) -> Optional[Tuple[str, List[str]]]:
    if not isinstance(context, dict) or not isinstance(context.get("name"), str):
        return None
    sib = context.get("siblings")
    if not isinstance(sib, list):
        return None
    return context["name"], [s for s in sib if isinstance(s, str)]


def _context_fastq(context: Optional[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    parts = _context_parts(context)
    fpm = _folder_profile() if parts else None
    return fpm.fastq_layout(*parts) if fpm else None


def _context_tenx(context: Optional[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    parts = _context_parts(context)
    fpm = _folder_profile() if parts else None
    return fpm.tenx_member(*parts) if fpm else None


def rows_layout_key(context: Optional[Dict[str, Any]]) -> str:
    """What in ``context`` changes how rows are read ("tenx:features" / "tenx:barcodes" / ""):
    the rows cache keys its column/total metadata on it."""
    member = _context_tenx(context)
    return f"tenx:{member['role']}" if member and member["role"] in _tenx_columns() else ""


def _tenx_columns() -> Dict[str, List[str]]:
    fpm = _folder_profile()
    return getattr(fpm, "TENX_COLUMNS", {}) if fpm else {}


def _tenx_layout(path: str, role: str) -> "TableLayout":
    """A 10x features/barcodes TSV: tab-delimited, NO header row (10x spec), spec column names."""
    width = 0
    with _open_text(path) as f:
        for line in f:
            if line.strip():
                width = len(line.rstrip("\r\n").split("\t"))
                break
    names = list(_tenx_columns().get(role, []))[:width]
    names += [f"column_{i + 1}" for i in range(len(names), width)]
    # A spec-defined table: its columns are the 10x specification's, so the classification and
    # placeholder-column checks (every feature_type "Gene Expression") do not apply.
    return TableLayout("\t", names, "spec", header_row=False, spec="tenx", header_width=width)


def _galaxy_identify(path: str, name: str) -> Optional[str]:
    gf = _galaxy_formats()
    if gf is None:
        return None
    try:
        return gf.identify(path, name)
    except Exception as exc:  # noqa: BLE001
        log.info("[perception] Galaxy identify failed for %s: %s", path, exc)
        return None


def _galaxy_metadata(path: str, ext: str) -> Dict[str, Any]:
    gf = _galaxy_formats()
    if gf is None:
        return {}
    try:
        return gf.metadata(path, ext) or {}
    except Exception as exc:  # noqa: BLE001
        return {"error": str(exc)[:300]}


def _galaxy_generic() -> frozenset:
    gf = _galaxy_formats()
    return getattr(gf, "GENERIC_EXTS", None) or frozenset({"data", "binary", "txt", "text", "tabular", "tsv"})


def _format_label(ext: Optional[str]) -> str:
    if ext in _BIOMATE_LABELS:
        return _BIOMATE_LABELS[ext]
    gf = _galaxy_formats()
    if gf is not None:
        try:
            return gf.label_for(ext)
        except Exception:  # noqa: BLE001
            pass
    return (ext or "Unknown").upper()


# Which Galaxy extensions agree with each BioMate kind (else the chip shows BioMate's own).
_KIND_COMPATIBLE_GALAXY: Dict[str, Tuple[str, ...]] = {
    "table": ("csv", "tsv", "tabular", "bed", "bed6", "bed12", "bedgraph", "interval", "encodepeak",
              "gff", "gff3", "gtf", "gff3.gz", "gtf.gz", "smi"),
    "fastq": ("fastq",),
    "fasta": ("fasta",),
    "vcf": ("vcf", "vcf_bgzip"),
    "json": ("json",),
    "yaml": ("yaml",),
    "jsonl": (),
    "mtx": ("mtx",),
}


# The generic label of a plain-text DOCUMENT — the same as Galaxy's "txt" format label
# (galaxy_formats). BioMate's own "txt" label below is the one-value-per-line LIST table.
_TEXT_LABEL = "Text"
_BIOMATE_LABELS: Dict[str, str] = {
    "csv": "CSV", "tsv": "TSV", "jsonl": "JSON Lines", "json": "JSON", "yaml": "YAML",
    "fastq": "FASTQ", "fasta": "FASTA", "vcf": "VCF", "mtx": "Matrix Market", "bed": "BED", "bedgraph": "bedGraph",
    "narrowpeak": "narrowPeak", "broadpeak": "broadPeak", "gtf": "GTF", "gff": "GFF", "gff3": "GFF3",
    "smi": "SMILES", "unknown": "Unknown", "txt": "Text (one value per line)", "tabular": "Tabular",
    "bedpe": "BEDPE", "tenx": "10x Genomics",
    # Text documents (shown as documents, not analysed).
    "log": "Log (text)", "md": "Markdown", "markdown": "Markdown", "rst": "reStructuredText", "html": "HTML",
    "htm": "HTML", "xml": "XML", "py": "Python script", "r": "R script", "sh": "Shell script",
    "nf": "Nextflow script", "config": "Configuration", "ini": "Configuration", "toml": "TOML",
    "readme": _TEXT_LABEL,
}


# ---------------------------------------------------------------------------
# Attached-data → input_kinds mapping
# ---------------------------------------------------------------------------
# Maps the SHAPE of the data the user actually attached to the closed input-kind
# vocabulary used by workflow routing (galaxy.ai.chain_composer.input_kinds_classifier.INPUT_KINDS,
# mirrored in UnifiedWorkflowSearch._RAW_KINDS/_PROCESSED_KINDS). Grounding the routing check in the
# real data shape — not the intent classifier's guess from prose — is the principled fix for the
# processed-vs-raw mismatch (a processed abundance TABLE must not route to a raw LC-MS pipeline).
#
# Only valid INPUT_KINDS keys are emitted; UnifiedWorkflowSearch._valid_kinds re-validates anyway.
# An extension that unambiguously identifies the data wins outright. A table is classified from
# filename cues (and, when a local file is actually readable, its column shape); a cue-less /
# unreadable table yields NO kind rather than a guess — routing then falls back to the prose path.

# Unambiguous file-extension → input_kind (raw instrument output + a few reference/object types).
_EXT_TO_KIND: Dict[str, str] = {
    ".fastq": "fastq", ".fq": "fastq",
    ".bam": "bam", ".cram": "bam", ".sam": "bam",
    ".vcf": "vcf", ".bcf": "vcf",
    ".raw": "raw_spectra", ".mzml": "raw_spectra", ".mzxml": "raw_spectra",
    ".wiff": "raw_spectra", ".mgf": "raw_spectra", ".d": "raw_spectra",
    ".h5ad": "h5ad", ".loom": "h5ad",
    ".idat": "idat",
    ".bcl": "bcl",
    ".fast5": "nanopore_signal", ".pod5": "nanopore_signal",
    ".mrc": "raw_images", ".mrcs": "raw_images", ".tif": "raw_images", ".tiff": "raw_images",
    ".eer": "raw_images", ".dm4": "raw_images", ".czi": "raw_images", ".nd2": "raw_images",
    ".pdb": "structure", ".cif": "structure", ".mmcif": "structure", ".ent": "structure",
    ".sdf": "molecules", ".smi": "molecules", ".smiles": "molecules", ".mol2": "molecules",
    ".fasta": "fasta", ".fa": "fasta", ".faa": "fasta", ".fna": "fasta",
    ".gtf": "annotation", ".gff": "annotation", ".gff3": "annotation",
    ".narrowpeak": "peaks", ".broadpeak": "peaks",
    ".mtx": "cellranger_output",
}

_TABLE_EXTS = (".csv", ".tsv", ".txt", ".tab")

# Filename/column cues → processed-table kind(s). A processed abundance/quant/DE matrix is the
# canonical ``counts_matrix`` kind (omics-agnostic numeric matrix that generic integration
# workflows consume); modality-specific cues add the precise proteomics/metabolomics/methylation
# kind on top. Ordered most-specific first. A design/sample sheet is NOT a processed matrix.
_TABLE_CUE_RULES: List[Tuple[Tuple[str, ...], Tuple[str, ...]]] = [
    # (substring cues, kinds to emit) — a design matrix is intentionally mapped to NOTHING below.
    (("proteingroups", "pg_matrix", "pg.matrix", "protein group", "protein-group",
      "protein_group", "protein intensit", "protein_intensit", "protein abundance",
      "protein-abundance", "protein_abundance", "protein level", "protein-level",
      "protein_level", "lfq"), ("protein_table", "counts_matrix")),
    (("peptides.txt", "evidence.txt", "psm", "precursor report", "diann", "dia-nn",
      "peptide intensit", "peptide table", "peptide-level", "peptide level"),
     ("peptide_table", "counts_matrix")),
    (("metabolite", "feature table", "feature_table", "lc-ms feature", "peak table",
      "peak_table", "peak intensit"), ("metabolite_table", "counts_matrix")),
    (("beta value", "beta-value", "beta_value", "m-value", "methylation matrix",
      "methylation_matrix", "ewas"), ("beta_values",)),
    (("featurecount", "feature_count", "htseq", "gene count", "gene_count",
      "count matrix", "count_matrix", "counts matrix", "counts_matrix", "countmatrix",
      "expression matrix", "expression_matrix", "salmon", "rsem", "tpm", "fpkm",
      "abundance", "deseq", "edger", "differential", "de_result", "de result",
      "de_table", "de table", "log2fc", "logfc", "quant.sf", "quantification"),
     ("counts_matrix",)),
]

# Cues that mark a table as sample/design metadata, NOT a processed data matrix. These must never
# demote a raw pipeline (a sample sheet legitimately accompanies raw FASTQ / spectra).
_DESIGN_CUES: Tuple[str, ...] = (
    "samplesheet", "sample_sheet", "sample sheet", "coldata", "col_data",
    "metadata", "phenotype", "design matrix", "design_matrix", "manifest",
)

# ---------------------------------------------------------------------------
# PRIMARY vs AUXILIARY input kinds (committee review 2026-11-09, finding 3)
# ---------------------------------------------------------------------------
# A workflow's PRIMARY input is the data it actually analyses: raw instrument output (FASTQ,
# spectra, images, …) or a processed matrix/object/result (counts table, protein table, VCF, …).
# These are the kinds that drive the raw-vs-processed routing decision (step 8a), so an attached
# PRIMARY file is authoritative and may OVERRIDE a prose-guessed shape.
#
# AUXILIARY/reference inputs accompany a primary input but are not themselves the thing being
# analysed: a reference genome (.fa→fasta), a gene model (.gtf→annotation), a ligand library
# (.sdf→molecules), a receptor structure (.pdb→structure). A user whose real reads are remote or
# prose-described, who also attaches a reference genome, still "has" {fastq} — so an auxiliary-only
# attachment must NOT, on its own, discard the correct prose classification.
AUXILIARY_INPUT_KINDS: frozenset = frozenset({"fasta", "annotation", "molecules", "structure"})
PRIMARY_INPUT_KINDS: frozenset = frozenset({
    # raw instrument output
    "fastq", "bam", "raw_spectra", "idat", "bcl", "nanopore_signal", "raw_images",
    # processed matrices / objects
    "counts_matrix", "h5ad", "cellranger_output", "protein_table", "peptide_table",
    "metabolite_table", "beta_values",
    # per-sample result data that is itself a primary analysis input
    "vcf", "peaks",
})


def has_primary_input_kind(kinds: Optional[Sequence[str]]) -> bool:
    """True when ``kinds`` contains at least one PRIMARY input kind (raw file or processed
    matrix/object/result). A set of only AUXILIARY/reference kinds (fasta/annotation/molecules/
    structure) must not, on its own, override a prose-described primary shape — see finding 3."""
    return any(str(k).strip().lower() in PRIMARY_INPUT_KINDS for k in (kinds or []))


def _dataset_name_candidates(dataset: Any) -> List[str]:
    """All filename/URI-bearing strings for a session dataset (dict) or a raw path string."""
    if isinstance(dataset, str):
        return [dataset] if dataset.strip() else []
    if not isinstance(dataset, dict):
        return []
    out: List[str] = []
    for key in ("file_path", "path", "s3_uri", "uri", "source_url", "name", "filename"):
        v = dataset.get(key)
        if isinstance(v, str) and v.strip():
            out.append(v.strip())
    return out


def _ext_of(name: str) -> str:
    """Lowercased extension with any trailing .gz stripped (e.g. 'x.fastq.gz' → '.fastq')."""
    base = _strip_gz(name.lower())
    _, ext = os.path.splitext(base)
    return ext


def _local_path(dataset: Any) -> Optional[str]:
    """A readable LOCAL filesystem path for the dataset, if one exists (never an s3:// URI)."""
    candidates = [dataset] if isinstance(dataset, str) else (
        [dataset.get(k) for k in ("file_path", "path", "uri", "source_url")]
        if isinstance(dataset, dict) else []
    )
    for c in candidates:
        if isinstance(c, str) and c and "://" not in c and os.path.exists(c):
            return c
    return None


def _looks_like_numeric_matrix(path: str) -> bool:
    """True when a local table reads as a wide numeric matrix (≥3 cols, ≥2 rows, majority of the
    sampled value cells numeric) — the shape of a counts/abundance/expression matrix."""
    try:
        prof = profile_to_dataclass(path)
    except Exception:  # noqa: BLE001 — perception must never raise into routing.
        return False
    if prof.quality == "blocked" or prof.cols < 3 or prof.rows < 2 or not prof.sample_rows:
        return False
    numeric = total = 0
    for row in prof.sample_rows:
        # Skip the first (identifier) column; count the rest.
        for cell in row[1:]:
            total += 1
            try:
                float(str(cell).replace(",", ""))
                numeric += 1
            except ValueError:
                pass
    return total > 0 and (numeric / total) >= 0.6


def _kinds_for_table(names: Sequence[str], dataset: Any) -> List[str]:
    """Classify a tabular dataset into processed input kinds from filename cues, falling back to a
    local column-shape check. Returns [] for a design/sample sheet or an uncertain cue-less table."""
    hay = " ".join(names).lower()
    if any(cue in hay for cue in _DESIGN_CUES):
        return []  # a sample/design sheet is not a processed data matrix — never demote raw pipelines
    for cues, kinds in _TABLE_CUE_RULES:
        if any(cue in hay for cue in cues):
            return list(kinds)
    # No filename cue: only commit to a processed kind when a local file actually reads as a matrix.
    local = _local_path(dataset)
    if local and _looks_like_numeric_matrix(local):
        return ["counts_matrix"]
    return []


def infer_input_kinds(datasets: Optional[Sequence[Any]]) -> List[str]:
    """Derive the closed-vocabulary input kinds the user HAS from the datasets actually attached.

    ``datasets`` is the session-dataset list (dicts with name/path/s3_uri/… fields) or a list of
    path strings. Returns a sorted, de-duplicated list of INPUT_KINDS keys, or [] when nothing can
    be grounded (routing then falls back to the prose/intent path). This NEVER raises.

    Symmetry is automatic: raw files (.fastq/.mzML/…) map to raw kinds, so the raw pipeline stays
    compatible; processed tables map to processed kinds, so raw pipelines become incompatible (step
    8a) and downstream/integration methods are preferred — for every modality, with no per-case list.
    """
    kinds: set = set()
    for ds in (datasets or []):
        try:
            names = _dataset_name_candidates(ds)
            if not names:
                continue
            # First name with a recognised extension decides; else try the table path.
            ext = ""
            for nm in names:
                e = _ext_of(nm)
                if e in _EXT_TO_KIND or e in _TABLE_EXTS:
                    ext = e
                    break
            if ext in _EXT_TO_KIND:
                kinds.add(_EXT_TO_KIND[ext])
            elif ext in _TABLE_EXTS or _local_path(ds):
                kinds.update(_kinds_for_table(names, ds))
        except Exception:  # noqa: BLE001 — one bad dataset must not drop the rest.
            continue
    return sorted(kinds)


def resolve_effective_input_kinds(
    prose_kinds: Optional[Sequence[str]],
    datasets: Optional[Sequence[Any]],
) -> Optional[List[str]]:
    """Combine the prose/intent-classifier input kinds with the kinds inferred from the user's
    ACTUALLY-attached datasets, so workflow routing is grounded in the real data shape (finding 3).

    Policy:
      * Attached PRIMARY data (a raw file or a processed matrix/object/result) is authoritative and
        OVERRIDES the prose classification — step 8a then owns the raw-vs-processed decision
        (McGill: a processed abundance TABLE demotes raw nf-core/diaproteomics).
      * An attachment that infers ONLY AUXILIARY/reference kinds (reference genome .fa→fasta,
        gene model .gtf→annotation, ligand library .sdf→molecules, receptor .pdb→structure) is
        MERGED with the prose kinds, NEVER replacing them — a user with prose-described FASTQ who
        also attaches a reference .fa still "has" {fastq}, so the raw pipeline keeps its boost.
      * Nothing profilable (or a design/sample sheet → no kind) → the prose value is returned
        unchanged (None / [] / list preserved exactly, so the ``[]`` "states no input data" and the
        "unknown shape" semantics in step 8 are untouched).

    NEVER raises — perception must not block generation.
    """
    try:
        data_kinds = infer_input_kinds(datasets)
    except Exception:  # noqa: BLE001 — never block generation on perception
        return prose_kinds
    if not data_kinds:
        return prose_kinds
    if has_primary_input_kind(data_kinds):
        return data_kinds  # attached primary data is authoritative — override the prose guess
    # Auxiliary-only attachment: augment, do not discard, the prose primary shape.
    return sorted(set(prose_kinds or []) | set(data_kinds))


def _profile_structured(path: str, kind: str) -> DataProfile:
    """Structural validation, not a claim about scientific dataset quality (the verdict is
    "unassessed" unless something worth checking is found)."""
    p = DataProfile()
    with _open_text(path) as handle:
        text = handle.read(2 * 1024 * 1024 + 1)
    if len(text) > 2 * 1024 * 1024:
        emit(p, "note", "structured_too_large", "")
        return p
    if kind == "json":
        data = json.loads(text)
    else:
        import yaml
        data = yaml.safe_load(text)
    nodes = keys = nulls = depth = 0
    stack = [(data, 0)]
    visited = set()
    while stack:
        value, level = stack.pop()
        nodes += 1
        depth = max(depth, level)
        if value is None:
            nulls += 1
        if isinstance(value, (dict, list)):
            identity = id(value)
            if identity in visited:
                continue  # YAML aliases may be shared or recursive.
            visited.add(identity)
            children = value.values() if isinstance(value, dict) else value
            if isinstance(value, dict):
                keys += len(value)
            stack.extend((child, level + 1) for child in children)
    root = "object" if isinstance(data, dict) else "array" if isinstance(data, list) else "scalar"
    p.structured = {"format": kind.upper(), "root": root, "nodes": nodes,
                    "keys": keys, "nulls": nulls, "depth": depth}
    if isinstance(data, (dict, list)):
        p.stats_map["entries"] = len(data)
    emit(p, "note", "structured_only", "", format=kind.upper(), root=root)
    return p


# ---------------------------------------------------------------------------
# Reading: compression by magic number, damage tracking, text decoding
# ---------------------------------------------------------------------------
# Content bytes looked at to identify a file (decompressed).
HEAD_BYTES = 64 * 1024


class UnreadableContent(ValueError):
    """The compressed stream cannot be decoded at all (corrupt from the start)."""


_DAMAGE = threading.local()


def _damage() -> Dict[str, Any]:
    """Per-thread record of what the readers hit while profiling ONE file: a compressed stream
    that ended early ("truncated") or failed to decode ("corrupt"), and NUL bytes dropped."""
    d = getattr(_DAMAGE, "d", None)
    if d is None:
        d = _DAMAGE.d = _fresh_damage()
    return d


def _fresh_damage() -> Dict[str, Any]:
    # replaced: undecodable byte sequences replaced by U+FFFD in the fullest read of the file;
    # replaced_total: the running count all streams of this thread add to (see _CountingText).
    return {"truncated": False, "corrupt": False, "nul_lines": 0, "replaced": 0, "replaced_total": 0}


def _reset_damage() -> None:
    _DAMAGE.d = _fresh_damage()


class _DecompressingStream(io.RawIOBase):
    """Incremental gzip / bzip2 decoding (multi-member: BGZF, concatenated streams) that ENDS —
    instead of raising — where the compressed data is truncated or corrupt, keeps every byte it
    could decode, and records which of the two happened in :func:`_damage`. (Library readers
    raise on the read that crosses the damage and drop the partial block with it.)"""

    _IN_CHUNK = 64 * 1024
    _OUT_CHUNK = 1024 * 1024

    def __init__(self, path: str, kind: str) -> None:
        super().__init__()
        self._f = open(path, "rb")
        self._kind = kind
        self._d = self._new()
        self._buf = b""
        self._pending = b""  # compressed input not yet consumed
        self._member_started = False
        self._done = False

    def _new(self) -> Any:
        if self._kind == "gzip":
            return zlib.decompressobj(31)
        import bz2

        return bz2.BZ2Decompressor()

    def readable(self) -> bool:
        return True

    def _fail(self, what: str) -> None:
        _damage()[what] = True
        self._done = True

    def _fill(self) -> None:
        while not self._buf and not self._done:
            needs = self._kind == "gzip" or self._d.needs_input
            if needs and not self._pending:
                self._pending = self._f.read(self._IN_CHUNK)
                if not self._member_started:
                    self._pending = self._pending.lstrip(b"\x00")  # zero padding between members
                    if not self._pending:
                        if not self._f.peek(1):  # nothing but padding left
                            self._done = True
                            return
                        continue
                if not self._pending:
                    self._fail("truncated")  # the file ends inside a member
                    return
            data = self._pending if needs else b""
            self._pending = b""
            try:
                out = self._d.decompress(data, self._OUT_CHUNK)
            except (zlib.error, OSError, EOFError, ValueError):
                self._fail("corrupt")
                return
            if self._kind == "gzip":
                self._pending = self._d.unconsumed_tail
            self._member_started = True
            self._buf = out
            if self._d.eof:
                rest = self._d.unused_data + self._pending
                self._d = self._new()  # the next member (BGZF block / concatenated stream)
                self._member_started = False
                self._pending = rest.lstrip(b"\x00")

    def readinto(self, b: Any) -> int:
        self._fill()
        n = min(len(b), len(self._buf))
        b[:n] = self._buf[:n]
        self._buf = self._buf[n:]
        return n

    def close(self) -> None:
        try:
            self._f.close()
        finally:
            super().close()


def _magic(path: str) -> bytes:
    try:
        with open(path, "rb") as f:
            return f.read(8)
    except OSError:
        return b""


def _compression(path: str) -> Optional[str]:
    m = _magic(path)
    if m[:2] == b"\x1f\x8b":
        return "gzip"
    if m[:3] == b"BZh":
        return "bzip2"
    return None


def _open_bytes(path: str) -> io.BufferedReader:
    """Binary view of the CONTENT (gzip / bzip2 decompressed by magic number); a damaged
    compressed stream ends where it breaks (see :class:`_GuardedStream`)."""
    comp = _compression(path)
    if comp:
        return io.BufferedReader(_DecompressingStream(path, comp))
    return open(path, "rb")


def _open_text(path: str) -> io.TextIOBase:
    """Text view of the content: decompressed by magic number, in the encoding
    :func:`_text_encoding` decides from the head (UTF-16 with or without a BOM; UTF-8 with any
    BOM removed — ``utf-8-sig``: a BOM must never become part of the first column name or hide a
    ``##fileformat`` line; or the legacy encoding of a file that is clearly not UTF-8). Bytes the
    encoding cannot decode become U+FFFD and are counted (:class:`_CountingText`)."""
    try:
        head = _raw_head(path, HEAD_BYTES)
    except UnreadableContent:
        head = b""
    enc = _text_encoding(head, complete=len(head) < HEAD_BYTES)
    return _CountingText(_open_bytes(path), encoding=enc, errors=_COUNT_REPLACE)


# Decoding errors are replaced by U+FFFD and counted per thread (see _damage()["replaced"]).
# The codec error-handler registry is process-global: under one fixed name, a second copy of this
# module (a re-import, another loader) took over the handler and counted into ITS _DAMAGE, so the
# copy that read the file reported nothing replaced. The name is unique to this module object.
_COUNT_REPLACE = f"biomate.count_replace.{id(_DAMAGE):x}"


def _count_replace(exc: UnicodeError) -> Tuple[str, int]:
    if isinstance(exc, UnicodeDecodeError):
        _damage()["replaced_total"] += 1
        return "\ufffd", exc.end
    raise exc


codecs.register_error(_COUNT_REPLACE, _count_replace)


class _CountingText(io.TextIOWrapper):
    """A text stream that records, when closed, how many undecodable byte sequences it replaced.
    The profiler reads one file several times (layout, rows, …): the count kept is the largest
    of any one pass (the same bad bytes are not counted twice)."""

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, **kwargs)
        self._replaced_start = _damage()["replaced_total"]

    def close(self) -> None:
        if not self.closed:
            d = _damage()
            d["replaced"] = max(d["replaced"], d["replaced_total"] - self._replaced_start)
        super().close()


# Encodings a non-UTF-8 text file is read in, and their names in findings / read_rows.
ENCODING_NAMES = {"utf-8-sig": "utf-8", "utf-16": "utf-16", "utf-16-le": "utf-16-le", "utf-16-be": "utf-16-be",
                  "gb18030": "gb18030", "cp1252": "windows-1252", "latin-1": "latin-1"}
_LEGACY_ENCODINGS = frozenset({"gb18030", "cp1252", "latin-1"})


def _non_ascii(text: str) -> int:
    return len(text) - len(text.encode("ascii", "ignore"))


def _text_encoding(head: bytes, complete: bool = False) -> str:
    """The codec a text file's content is read with, decided from its head:

    * UTF-16 (BOM, or the every-other-byte-NUL shape of a BOM-less Excel export);
    * UTF-8 (``utf-8-sig``) when the head is valid UTF-8 — or mostly valid: a few damaged bytes
      among valid multi-byte characters are replaced and counted, the file is still UTF-8;
    * otherwise the file is clearly in a legacy 8-bit encoding: GB18030 when the head decodes as
      it into mostly CJK characters (Chinese Excel exports), else Windows-1252 (a superset of the
      printable Latin-1 range), else Latin-1, which decodes any byte.
    """
    if _utf16_bom(head):
        return "utf-16"
    u16 = _utf16_encoding(head)
    if u16:
        return u16
    text = codecs.getincrementaldecoder("utf-8")("replace").decode(head, final=complete)
    bad = text.count("\ufffd") - head.count(b"\xef\xbf\xbd")
    if bad <= 0:
        return "utf-8-sig"
    good = _non_ascii(text) - text.count("\ufffd")
    if good > bad:
        return "utf-8-sig"
    try:
        gb = codecs.getincrementaldecoder("gb18030")("strict").decode(head, final=complete)
        cjk = sum(1 for ch in gb if "\u4e00" <= ch <= "\u9fff" or "\u3000" <= ch <= "\u303f"
                  or "\uff00" <= ch <= "\uffef")
        if cjk and cjk >= 0.5 * _non_ascii(gb):
            return "gb18030"
    except UnicodeDecodeError:
        pass
    try:
        head.decode("cp1252")
        return "cp1252"
    except UnicodeDecodeError:
        return "latin-1"


def _raw_head(path: str, n: int = 8192) -> bytes:
    """The first ``n`` content bytes (decompressed). Raises UnreadableContent when a compressed
    file yields nothing decodable (corrupt from its first block)."""
    if _compression(path) is None:
        with open(path, "rb") as f:
            return f.read(n)
    before = dict(_damage())
    with _open_bytes(path) as f:
        data = f.read(n)
    d = _damage()
    if not data and (d["corrupt"] or d["truncated"]):
        raise UnreadableContent("compressed stream could not be decoded")
    # A probe must not leave its own damage behind for a short head of a healthy file.
    if data and len(data) == n:
        d["corrupt"], d["truncated"] = before["corrupt"], before["truncated"]
    return data


def _utf16_bom(head: bytes) -> bool:
    return head[:2] in (b"\xff\xfe", b"\xfe\xff")


def _utf16_encoding(head: bytes) -> Optional[str]:
    """The UTF-16 codec of text WITHOUT a BOM (Excel / Windows exports): every other byte NUL
    and the rest printable. None for anything else."""
    block = head[:4096]
    if len(block) < 8:
        return None
    even, odd = block[0::2], block[1::2]
    for zeros, chars, enc in ((odd, even, "utf-16-le"), (even, odd, "utf-16-be")):
        if zeros.count(0) >= 0.95 * len(zeros) and chars.count(0) == 0 \
                and sum(1 for b in chars if b >= 32 or b in (9, 10, 13)) >= 0.95 * len(chars):
            return enc
    return None


# Control bytes that do not occur in text (everything below 0x20 except TAB, LF, VT, FF, CR, and
# ESC of ANSI-coloured logs). NUL is counted on its own.
_CONTROL_BYTES = bytes(b for b in range(1, 32) if b not in (9, 10, 11, 12, 13, 27))
_HIGH_BYTES = bytes(range(128, 256))
# The first block judged for binary content; it is extended to the end of the first line.
BINARY_PROBE_BYTES = 8192
# Share of control bytes above which content is binary.
_BINARY_CONTROL_FRAC = 0.1
# Share of non-ASCII bytes above which content that decodes in no text encoding, and carries some
# control bytes (more than _BINARY_SOME_CONTROL_FRAC), is binary. Without control bytes it is read
# as legacy 8-bit text (Cyrillic, Greek, … code pages) and its encoding is reported.
_BINARY_HIGH_FRAC = 0.3
_BINARY_SOME_CONTROL_FRAC = 0.01


def _count_of(block: bytes, which: bytes) -> int:
    return len(block) - len(block.translate(None, which))


def _head_is_binary(head: bytes, complete: bool = False) -> bool:
    """Binary content (BAM, CRAM, TIFF, HDF5, xlsx, …), judged on what the bytes ARE — never on
    line length (a 5,000-column matrix or a minified JSON has a first line far longer than any
    block): a NUL byte that is not UTF-16 text, many control bytes, or bytes that decode in no
    text encoding. The block judged is the first BINARY_PROBE_BYTES, extended to the end of the
    first line when that line is longer (so the judgement covers at least one whole line). Only
    that block decides: a stray NUL deep in a CSV does not make it binary."""
    if not head or _utf16_bom(head) or _utf16_encoding(head):
        return False
    nl = min((i for i in (head.find(b"\n"), head.find(b"\r")) if i >= 0), default=-1)
    end = max(BINARY_PROBE_BYTES, nl + 1 if nl >= 0 else len(head))
    block = head[:end]
    whole = complete and len(block) == len(head)
    if b"\x00" in block:
        return True
    ctrl = _count_of(block, _CONTROL_BYTES)
    if ctrl > _BINARY_CONTROL_FRAC * len(block):
        return True
    if ctrl <= _BINARY_SOME_CONTROL_FRAC * len(block) or _count_of(block, _HIGH_BYTES) <= _BINARY_HIGH_FRAC * len(block):
        return False  # text in some encoding (damaged bytes are counted, a legacy encoding reported)
    # Mostly non-ASCII bytes beside control bytes: text only when they decode (UTF-8, or GB18030).
    for enc in ("utf-8", "gb18030"):
        try:
            codecs.getincrementaldecoder(enc)("strict").decode(block, final=whole)
            return False
        except UnicodeDecodeError:
            continue
    return True


def _nul_guard(lines: Iterator[str]) -> Iterator[str]:
    """Drop NUL characters from text lines (counted in :func:`_damage` and reported)."""
    for line in lines:
        if "\x00" in line:
            _damage()["nul_lines"] += 1
            line = line.replace("\x00", "")
        yield line


def _strip_gz(name: str) -> str:
    """The name without a compression suffix (.gz / .bgz / .bz2)."""
    for suf in (".gz", ".bgz", ".bz2"):
        if name.endswith(suf):
            return name[: -len(suf)]
    return name


def _kind_from_name(path: str) -> Optional[str]:
    """The text kind a filename extension claims (None when the name claims none)."""
    lower = _strip_gz(path.lower())
    _, ext = os.path.splitext(lower)
    if ext in _FASTA_EXTS:
        return "fasta"
    if ext in (".jsonl", ".ndjson"):
        return "jsonl"
    if ext in (".json", ".yaml", ".yml"):
        return "json" if ext == ".json" else "yaml"
    if ext in (".fastq", ".fq"):
        return "fastq"
    if ext == ".vcf":
        return "vcf"
    if ext in (".csv", ".tsv", ".txt", ".tab") or ext in _SPEC_TABLE_EXTS:
        return "table"
    if ext == ".mtx":
        return "mtx"
    return None



# ---------------------------------------------------------------------------
# What a file IS — decided from its content (Galaxy's identification + BioMate's validation);
# the name only says what it CLAIMS to be, and a contradiction is reported.
# ---------------------------------------------------------------------------
# viewKind vocabulary shared with the panel (it picks the views from this, never from the name).
VIEW_KINDS = (
    "table", "records", "json", "sequences", "reads", "variants", "intervals", "annotation",
    "alignment", "anndata", "loom", "matrix", "molecules", "structure", "image", "document",
    "archive", "binary", "unknown",
)
# View kinds served as rows by read_rows (the profile and the rows reader decide identically).
TABULAR_VIEWS = frozenset({"table", "records", "intervals", "annotation"})

# Extensions whose content is binary by definition → (view kind, label).
_BINARY_NAME_FORMATS: Dict[str, Tuple[str, str]] = {
    "png": ("image", "PNG"), "jpg": ("image", "JPEG"), "jpeg": ("image", "JPEG"), "gif": ("image", "GIF"),
    "tif": ("image", "TIFF"), "tiff": ("image", "TIFF"), "bmp": ("image", "BMP"), "webp": ("image", "WebP"),
    "pdf": ("document", "PDF"), "docx": ("document", "Word document"), "pptx": ("document", "PowerPoint"),
    "xlsx": ("document", "Excel (xlsx)"), "xls": ("document", "Excel (xls)"),
    "zip": ("archive", "ZIP archive"), "tar": ("archive", "Tar archive"), "tgz": ("archive", "Tar archive (gzip)"),
    "7z": ("archive", "7-Zip archive"),
    "bam": ("alignment", "BAM"), "cram": ("alignment", "CRAM"), "bcf": ("variants", "BCF"),
    "h5ad": ("anndata", "AnnData (h5ad)"), "loom": ("loom", "Loom"), "h5": ("binary", "HDF5"),
    "hdf5": ("binary", "HDF5"), "fast5": ("binary", "FAST5"), "pod5": ("binary", "POD5"),
    "bigwig": ("binary", "bigWig"), "bw": ("binary", "bigWig"), "bigbed": ("binary", "bigBed"),
    "bb": ("binary", "bigBed"), "rds": ("binary", "R data (RDS)"), "npy": ("binary", "NumPy array"),
    "parquet": ("binary", "Parquet"), "sqlite": ("binary", "SQLite database"), "db": ("binary", "SQLite database"),
    "mrc": ("image", "MRC"), "mrcs": ("image", "MRC stack"),
}
# Same-content families: a name in one of these and content in the same family agree.
_FORMAT_FAMILY: Dict[str, str] = {
    "jpg": "jpeg", "jpeg": "jpeg", "tif": "tiff", "tiff": "tiff", "ome.tiff": "tiff",
    "bam": "bam", "qname_sorted.bam": "bam", "unsorted.bam": "bam", "qname_input_sorted.bam": "bam",
    "h5": "hdf5", "hdf5": "hdf5", "h5ad": "hdf5", "loom": "hdf5", "fast5": "hdf5",
    "bw": "bigwig", "bigwig": "bigwig", "bb": "bigbed", "bigbed": "bigbed",
    "xlsx": "xlsx", "excel.xls": "xls", "xls": "xls", "tgz": "tar", "tar": "tar",
    "sqlite": "sqlite", "db": "sqlite", "mrc": "mrc", "mrcs": "mrc",
}
# Galaxy extension → view kind (Galaxy formats BioMate describes from metadata).
_GALAXY_VIEW: Dict[str, str] = {
    "bam": "alignment", "cram": "alignment", "sam": "alignment", "qname_sorted.bam": "alignment",
    "unsorted.bam": "alignment", "qname_input_sorted.bam": "alignment",
    "h5ad": "anndata", "loom": "loom", "mtx": "matrix",
    "xlsx": "document", "excel.xls": "document", "pdf": "document", "html": "document",
    "markdown": "document", "docx": "document",
    "sdf": "molecules", "mol2": "molecules", "mol": "molecules", "inchi": "molecules", "smi": "table",
    "pdb": "structure", "cif": "structure", "pqr": "structure", "gro": "structure", "mmcif": "structure",
    "vcf": "variants", "vcf_bgzip": "variants", "bcf": "variants", "bcf_uncompressed": "variants",
    "fasta": "sequences", "fasta.gz": "sequences", "genbank": "sequences", "stockholm": "sequences",
    "zip": "archive", "tar": "archive", "fast5.tar": "archive", "fast5.tar.gz": "archive",
    "fast5.tar.bz2": "archive",
}
_GALAXY_IMAGE_EXTS = frozenset({
    "png", "jpg", "jpeg", "gif", "tiff", "ome.tiff", "bmp", "im", "pcd", "pcx", "ppm", "psd", "xbm",
    "xpm", "rgb", "pbm", "pgm", "eps", "rast", "webp", "svg", "mrc", "zarr",
})
def _name_ext(name: str) -> str:
    """The claimed extension (lowercase, compression removed, ``.ome.tiff`` kept whole)."""
    base = _strip_gz(os.path.basename(name or "").lower())
    if base.endswith(".ome.tiff") or base.endswith(".ome.tif"):
        return "ome.tiff"
    if base.endswith((".tar.gz", ".tar.bz2")):
        return "tar"
    _, ext = os.path.splitext(base)
    return ext.lstrip(".")


_GENERIC_NAME_EXTS = frozenset({"", "txt", "tab", "dat", "data", "out", "text", "bin"})
_PROSE_NAME_EXTS = frozenset({"log", "md", "markdown", "rst", "readme", "html", "htm", "xml",
                              "py", "r", "sh", "nf", "config", "ini", "toml"})


def _name_claim(name: str) -> Optional[Tuple[str, str, str]]:
    """What the file NAME claims: (BioMate kind, extension, label), or None for a generic name
    (.txt, .dat, no extension) that claims no particular format."""
    ext = _name_ext(name)
    if ext in _GENERIC_NAME_EXTS:
        return None
    k = _kind_from_name(name)
    if k == "table":
        spec = _spec_of(name)
        if spec:
            return "table", spec[0], _BIOMATE_LABELS.get(spec[0], spec[0].upper())
        e = "tsv" if ext in ("tsv", "tab") else "csv"
        return "table", e, _BIOMATE_LABELS[e]
    if k:
        return k, k, _BIOMATE_LABELS.get(k, k.upper())
    if ext in _BINARY_NAME_FORMATS:
        return "binary", ext, _BINARY_NAME_FORMATS[ext][1]
    if ext in _PROSE_NAME_EXTS:
        return "text", ext, _format_label(ext)
    return "other", ext, _format_label(ext)


def _sniff_magic(head: bytes, path: str) -> Optional[str]:
    """Binary format from its signature bytes (content-first, independent of the name)."""
    if head.startswith(b"\x89PNG\r\n\x1a\n"):
        return "png"
    if head[:3] == b"\xff\xd8\xff":
        return "jpg"
    if head[:6] in (b"GIF87a", b"GIF89a"):
        return "gif"
    if head[:4] in (b"II*\x00", b"MM\x00*", b"II+\x00", b"MM\x00+"):
        return "tiff"
    if head[:5] == b"%PDF-":
        return "pdf"
    if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
        return "webp"
    if head[:4] == b"PK\x03\x04":
        try:
            import zipfile

            with zipfile.ZipFile(path) as z:
                names = z.namelist()[:2000]
            if any(n.startswith("xl/") for n in names):
                return "xlsx"
            if any(n.startswith("word/") for n in names):
                return "docx"
        except Exception:  # noqa: BLE001 — a damaged zip is still a zip
            pass
        return "zip"
    if head[:8] == b"\x89HDF\r\n\x1a\n":
        return "h5"
    if head[:8] == b"\x8bPOD\r\n\x1a\n":
        return "pod5"
    if head[:4] == b"CRAM":
        return "cram"
    if head[:4] == b"BAM\x01":
        return "bam"
    if head[:4] in (b"BCF\x02", b"BCF\x04"):
        return "bcf"
    if head[:4] == b"\x26\xfc\x8f\x88":
        return "bigwig"
    if head[:4] == b"\xeb\xf2\x89\x87":
        return "bigbed"
    if head[:16] == b"SQLite format 3\x00":
        return "sqlite"
    if head[:6] == b"7z\xbc\xaf\x27\x1c":
        return "7z"
    if head[:6] == b"\x93NUMPY":
        return "npy"
    if head[:4] == b"PAR1":
        return "parquet"
    if head[:2] in (b"X\n", b"A\n") or head[:4] in (b"RDX2", b"RDX3", b"RDA2", b"RDA3"):
        return "rds" if _compression(path) else None
    if len(head) > 262 and head[257:262] == b"ustar":
        return "tar"
    return None


def _binary_label(ext: str) -> str:
    if ext in _BINARY_NAME_FORMATS:
        return _BINARY_NAME_FORMATS[ext][1]
    return _format_label(ext)


def _binary_view(ext: Optional[str]) -> str:
    if not ext:
        return "binary"
    if ext in _GALAXY_VIEW:
        return _GALAXY_VIEW[ext]
    if ext in _GALAXY_IMAGE_EXTS:
        return "image"
    if ext in _BINARY_NAME_FORMATS:
        return _BINARY_NAME_FORMATS[ext][0]
    gf = _galaxy_formats()
    if gf is not None:
        try:
            v = gf.view_for_ext(ext)
            if v:
                return v
        except Exception:  # noqa: BLE001
            pass
    return "binary"


def _same_family(a: Optional[str], b: Optional[str]) -> bool:
    if not a or not b:
        return False
    if a == b:
        return True
    return _family(a) == _family(b)


def _family(ext: str) -> str:
    if ext in _FORMAT_FAMILY:
        return _FORMAT_FAMILY[ext]
    parts = ext.split(".")
    if "tar" in parts or ext == "tgz":
        return "tar"  # fast5.tar.gz, tar.bz2, …: a tar archive
    if parts[-1] == "zip":
        return "zip"
    return ext


@dataclass
class Decision:
    """What the content of a file is, and how it is profiled and shown."""

    kind: str  # profiler: table|jsonl|json|yaml|fastq|fasta|vcf|mtx|galaxy|text|binary
    view: str
    ext: str  # content format extension ("unknown" when nothing is known)
    label: str
    source: str  # "galaxy" | "biomate"
    gext: Optional[str] = None
    layout: Optional["TableLayout"] = None
    # The name's claim when the content contradicts it: (named label, detected label).
    mismatch: Optional[Tuple[str, str]] = None
    # The codec text content is read with (see _text_encoding); None for binary content.
    encoding: Optional[str] = None

    def format(self) -> Dict[str, Any]:
        out: Dict[str, Any] = {"ext": self.ext, "label": self.label, "source": self.source}
        if self.layout is not None and self.layout.recognised:
            out["layout"] = self.layout.recognised  # a recognised tool output (KNOWN_TABLE_LAYOUTS)
        return out


def _lines_of(text: str, n: int = 400) -> List[str]:
    out = text.splitlines()
    # The last line of a head can be cut mid-way.
    return out[: n]


def _fastq_records_valid(lines: Sequence[str], need: int = 1) -> Tuple[int, int]:
    """(valid, invalid) 4-line FASTQ records among complete records of ``lines``: '@' header,
    sequence, '+' separator, quality of the sequence's length. Trailing blank lines are allowed."""
    ls = list(lines)
    while ls and not ls[-1].strip():
        ls.pop()
    good = bad = 0
    for i in range(0, len(ls) - 3, 4):
        h, s, plus, q = ls[i], ls[i + 1].strip(), ls[i + 2], ls[i + 3].strip()
        if h.startswith("@") and plus.startswith("+") and s and len(s) == len(q) and _SEQ_CHARS.issuperset(s.upper()):
            good += 1
        else:
            bad += 1
    return good, bad


_SEQ_CHARS = frozenset("ACGTUNRYKMSWBDHV.-")


def _vcf_valid(lines: Sequence[str]) -> bool:
    """A VCF: a ``##fileformat=VCF`` or ``#CHROM`` header, and data lines with at least 8
    tab-separated columns whose POS is an integer."""
    header = False
    data = good = 0
    for line in lines:
        if line.startswith("##fileformat=VCF") or line.startswith("#CHROM"):
            header = True
            continue
        if line.startswith("#") or not line.strip():
            continue
        data += 1
        f = line.rstrip("\r\n").split("\t")
        if len(f) >= 8 and f[1].isdigit():
            good += 1
    return header and (data == 0 or good / data >= 0.9)


def _sam_valid(lines: Sequence[str]) -> bool:
    data = good = 0
    hdr = False
    for line in lines:
        if line.startswith(("@HD\t", "@SQ\t", "@RG\t", "@PG\t", "@CO\t")):
            hdr = True
            continue
        if not line.strip():
            continue
        data += 1
        f = line.rstrip("\r\n").split("\t")
        if len(f) >= 11 and f[1].isdigit() and f[3].isdigit() and f[4].isdigit():
            good += 1
    return (hdr and (data == 0 or good / data >= 0.9)) or (data >= 1 and good / data >= 0.9)


# Every record name of the wwPDB coordinate file format (v3.3, columns 1–6), plus the obsolete
# records older files still carry. A PDB file's lines all start with one of them.
_PDB_RECORD_NAMES = frozenset({
    # Title section
    "HEADER", "OBSLTE", "TITLE", "SPLIT", "CAVEAT", "COMPND", "SOURCE", "KEYWDS", "EXPDTA", "NUMMDL",
    "MDLTYP", "AUTHOR", "REVDAT", "SPRSDE", "JRNL", "REMARK",
    # Primary structure, heterogen, secondary structure, connectivity annotation, misc.
    "DBREF", "DBREF1", "DBREF2", "SEQADV", "SEQRES", "MODRES", "HET", "HETNAM", "HETSYN", "FORMUL",
    "HELIX", "SHEET", "SSBOND", "LINK", "CISPEP", "SITE",
    # Crystallographic and coordinate transformation
    "CRYST1", "ORIGX1", "ORIGX2", "ORIGX3", "SCALE1", "SCALE2", "SCALE3", "MTRIX1", "MTRIX2", "MTRIX3",
    # Coordinates, connectivity, bookkeeping
    "MODEL", "ATOM", "ANISOU", "TER", "HETATM", "ENDMDL", "CONECT", "MASTER", "END",
    # Obsolete (pre-v3) records still found in older and program-written files
    "FTNOTE", "HYDBND", "SLTBRG", "TURN", "SIGATM", "SIGUIJ", "TVECT", "LINKR", "USER",
})
_PDB_COORD_RECORDS = ("ATOM", "HETATM")


def _pdb_record(line: str) -> str:
    """The record name of a PDB line (columns 1–6). ATOM/HETATM serials past 99,999 run into the
    name field (``ATOM100000``), so those two are recognised by prefix."""
    if line.startswith(_PDB_COORD_RECORDS):
        return "HETATM" if line.startswith("HETATM") else "ATOM"
    return line[:6].rstrip()


def _pdb_valid(lines: Sequence[str]) -> bool:
    """PDB coordinates: at least 90% of the non-blank lines are wwPDB records and at least one is
    an ATOM / HETATM record (a header-only fragment is not a structure)."""
    recs = [ln for ln in lines if ln.strip()]
    if not recs:
        return False
    hits = sum(1 for ln in recs if _pdb_record(ln) in _PDB_RECORD_NAMES)
    return hits / len(recs) >= 0.9 and any(ln.startswith(_PDB_COORD_RECORDS) for ln in recs)


# Structure provenance: experimental method vs predicted model.
_STRUCTURE_FORMATS = frozenset({"pdb", "cif", "mmcif", "pqr"})
# EXPDTA / _exptl.method values → a method key the UI translates.
_EXPERIMENTAL_METHODS = (
    ("X-RAY", "xray"), ("ELECTRON MICROSCOPY", "em"), ("ELECTRON CRYSTALLOGRAPHY", "electron_crystallography"),
    ("CRYO", "em"), ("NMR", "nmr"), ("NEUTRON", "neutron"), ("FIBER", "fiber"), ("FIBRE", "fiber"),
    ("POWDER", "xray"), ("SOLUTION SCATTERING", "other"), ("INFRARED", "other"), ("EPR", "other"),
    ("FLUORESCENCE", "other"),
)
# Structure predictors and modelling servers named in headers/titles/remarks, and the words a
# header uses for a computed model. Their B-factor column holds a confidence score (pLDDT for the
# AlphaFold family, ESMFold, OmegaFold, Boltz, Chai; QMEAN for SWISS-MODEL), not displacement.
_PREDICTOR_RE = re.compile(
    r"\b(ALPHA\s?FOLD\s?\d?|COLAB\s?FOLD|ESM\s?-?\s?FOLD|ROSETTA\s?FOLD|OMEGA\s?FOLD|OPEN\s?FOLD|"
    r"BOLTZ-?\d?|CHAI-?\d?|PROTENIX|HELIX\s?FOLD\d?|UNI-?FOLD|SWISS-?MODEL|MODELLER|I-?TASSER|TRROSETTA|"
    r"RF\s?DIFFUSION)\b", re.I)
# Words that call the whole entry a computed model — trusted only in the records that describe the
# entry (HEADER, TITLE, KEYWDS, EXPDTA, COMPND), not in free-text remarks ("secondary structure
# prediction").
_PREDICTED_WORDS_RE = re.compile(r"\b(THEORETICAL MODEL|COMPUTED MODEL|IN SILICO MODEL|PREDICTED|PREDICTION)\b",
                                 re.I)
_ENTRY_RECORDS = frozenset({"HEADER", "TITLE", "KEYWDS", "EXPDTA", "COMPND"})
_STRUCTURE_HEADER_LINES = 3000


def _structure_provenance(path: str, ext: str) -> Dict[str, Any]:
    """Whether a 3D structure file is EXPERIMENTAL (and by which method) or a PREDICTED model,
    from its own header: PDB ``EXPDTA`` (``THEORETICAL MODEL`` = predicted) and the header /
    title / remark records; mmCIF ``_exptl.method`` and ModelCIF ``_ma_`` categories. A predictor
    named anywhere in the header (AlphaFold, ESMFold, …) makes it predicted. Unknown → None.

    Returns {"method": raw method or None, "method_key": xray|em|nmr|neutron|fiber|
    electron_crystallography|other|None, "predicted": True|False|None, "predictor": the name or
    phrase that said so, or None, "bfactor": "confidence"|"displacement"|None} — the backend's
    signal for whether the B-factor column is a confidence score (pLDDT) or atomic displacement."""
    method: Optional[str] = None
    predictor: Optional[str] = None
    modelcif = False
    is_cif = ext in ("cif", "mmcif")
    with _open_text(path) as f:
        for i, line in enumerate(f):
            if i >= _STRUCTURE_HEADER_LINES:
                break
            if not is_cif:
                rec = _pdb_record(line)
                if rec in ("ATOM", "HETATM", "MODEL"):
                    break  # the header ends where the coordinates begin
                if rec == "EXPDTA" and method is None:
                    method = line[6:].strip().rstrip(";").strip() or None
                if rec in ("HEADER", "TITLE", "COMPND", "SOURCE", "KEYWDS", "EXPDTA", "REMARK", "AUTHOR",
                           "CAVEAT", "JRNL") and predictor is None:
                    m = _PREDICTOR_RE.search(line[6:]) or (
                        _PREDICTED_WORDS_RE.search(line[6:]) if rec in _ENTRY_RECORDS else None)
                    if m:
                        predictor = " ".join(m.group(1).split())
            else:
                st = line.strip()
                if st.startswith("_atom_site."):
                    break
                if st.startswith("_exptl.method") and method is None:
                    val = st[len("_exptl.method"):].strip().strip("'\"")
                    method = val or None
                if st.startswith("_ma_"):
                    modelcif = True
                if predictor is None and (st.startswith(("_software.name", "_struct.title", "_ma_", "_exptl."))
                                          or st[:1] in ("'", '"')):
                    m = _PREDICTOR_RE.search(st) or (
                        _PREDICTED_WORDS_RE.search(st) if st.startswith(("_struct.title", "_exptl.")) else None)
                    if m:
                        predictor = " ".join(m.group(1).split())
    method_key: Optional[str] = None
    predicted: Optional[bool] = None
    if method:
        up = method.upper()
        if "THEORETICAL" in up or "PREDICT" in up or "COMPUTED" in up:
            predicted = True
            predictor = predictor or method
        else:
            method_key = next((k for word, k in _EXPERIMENTAL_METHODS if word in up), "other")
            predicted = False
    if predicted is None and (predictor or modelcif):
        predicted = True
        predictor = predictor or "ModelCIF"
    if predicted is False:
        predictor = None  # an experimental method decides; a word in a remark does not
    bfactor = "confidence" if predicted else ("displacement" if predicted is False else None)
    return {"method": method, "method_key": method_key, "predicted": predicted, "predictor": predictor,
            "bfactor": bfactor}


def _structure_findings(p: DataProfile, path: str, ext: str) -> None:
    try:
        info = _structure_provenance(path, ext)
    except Exception as exc:  # noqa: BLE001 — provenance is a description, never a failure
        log.info("[perception] structure provenance failed for %s: %s", path, exc)
        return
    p.structure = info
    if info["predicted"] is True:
        emit(p, "note", "structure_predicted", "", predictor=info["predictor"])
    elif info["predicted"] is False:
        emit(p, "note", "structure_experimental", "", method=info["method"], method_key=info["method_key"])


def _sdf_valid(text: str) -> bool:
    return "$$$$" in text or "V2000" in text or "V3000" in text or "M  END" in text


# Lines sampled to decide JSON Lines.
_JSONL_SAMPLE_LINES = 50


def _jsonl_objects(text: str, complete: bool) -> Tuple[int, int]:
    """(lines that are JSON objects, non-blank lines sampled) over the first _JSONL_SAMPLE_LINES
    lines of ``text`` (the last line of a partial head is left out: it can be cut)."""
    lines = [ln for ln in text.splitlines() if ln.strip()]
    if not complete and len(lines) > 1:
        lines = lines[:-1]
    sample = lines[:_JSONL_SAMPLE_LINES]
    objects = 0
    for ln in sample:
        if ln.lstrip().lstrip("\ufeff")[:1] != "{":
            continue
        try:
            if isinstance(json.loads(ln.strip().lstrip("\ufeff")), dict):
                objects += 1
        except ValueError:
            pass
    return objects, len(sample)


def _json_kind(text: str, complete: bool) -> Optional[str]:
    """'json' / 'jsonl' when the head parses as JSON (Lines), else None. JSON Lines: of the
    sampled lines (any of them, the first included), MORE THAN HALF are JSON objects; the others
    are reported as skipped lines, never a reason to call the file something else."""
    objects, sampled = _jsonl_objects(text, complete)
    if sampled >= 2 and objects * 2 > sampled:
        return "jsonl"
    s = text.lstrip().lstrip("\ufeff")
    if not s or s[0] not in "{[":
        return None
    if complete:
        try:
            json.loads(s)
            return "json"
        except ValueError:
            return None
    return "json"  # a large document: validated by the structured profiler


def _detect_text(path: str, text: str, complete: bool) -> Tuple[str, Optional[str]]:
    """(BioMate kind, content extension) of a TEXT file from its content alone."""
    lines = _lines_of(text)
    if not complete and lines:
        lines = lines[:-1] or lines
    first = next((ln for ln in lines if ln.strip()), "")
    if _vcf_valid(lines):
        return "vcf", "vcf"
    if first.startswith("%%MatrixMarket"):
        return "mtx", "mtx"
    good, bad = _fastq_records_valid(lines)
    if first.startswith("@") and good and good >= 4 * bad:
        return "fastq", "fastq"
    if first.startswith(">"):
        return "fasta", "fasta"
    if first.startswith("@") and _sam_valid(lines):
        return "galaxy", "sam"
    jk = _json_kind(text, complete)
    if jk:
        return jk, jk
    if first.lstrip()[:1] in ("{", "["):
        return "text", "txt"  # braces that do not parse: broken JSON is text, not a table
    if first.startswith("data_") and any(ln.startswith(("_atom_site.", "_cell.", "_exptl.", "_entry.id"))
                                         for ln in lines[:2000]):
        return "galaxy", "cif"  # mmCIF / PDBx
    if first.startswith("##gff-version"):
        return "table", "gff3"
    if _pdb_valid(lines):
        return "galaxy", "pdb"
    if _sdf_valid(text) and not first.count("\t") and not first.count(","):
        return "galaxy", "sdf"
    if "\t" in first and _sam_valid(lines):
        return "galaxy", "sam"
    sniff = _sniff_table(lines)
    if sniff is None:
        return "text", "txt"
    return "table", None


def _validate_claim(path: str, claim_kind: str, claim_ext: str, text: str, complete: bool) -> bool:
    """Whether the content follows the format the name claims (text formats BioMate reads)."""
    lines = _lines_of(text)
    if not complete and lines:
        lines = lines[:-1] or lines
    first = next((ln for ln in lines if ln.strip() and not ln.startswith(";")), "")
    if claim_kind == "fastq":
        # Named FASTQ: mostly valid records are FASTQ (the malformed ones are counted as a finding).
        good, bad = _fastq_records_valid(lines)
        return first.startswith("@") and good > 0 and good >= bad
    if claim_kind == "vcf":
        return _vcf_valid(lines)
    if claim_kind == "fasta":
        return first.startswith(">")
    if claim_kind == "mtx":
        return first.startswith("%%MatrixMarket")
    if claim_kind == "jsonl":
        # Named JSON Lines: at least half of the sampled lines are JSON objects (one record is a
        # JSON Lines file of one line); the rest are reported as skipped lines.
        objects, sampled = _jsonl_objects(text, complete)
        return objects > 0 and objects * 2 >= sampled
    if claim_kind == "json":
        return _json_kind(text, complete) in ("json", "jsonl") and (
            _json_kind(text, complete) == "json" or not complete)
    if claim_kind == "yaml":
        return True  # nearly any text is valid YAML; the structured profiler parses it
    if claim_kind == "table":
        spec = _SPEC_TABLE_EXTS.get("." + claim_ext) if claim_ext not in ("csv", "tsv") else None
        if claim_ext in ("csv", "tsv"):
            return _sniff_table(lines) is not None or _single_column_list(lines)
        if spec is not None or claim_ext in _SPEC_SHAPE:
            try:
                lay = _table_layout(path, spec_key=claim_ext)
            except Exception:  # noqa: BLE001
                return False
            return lay.valid
        return True
    return True


_KIND_VIEW = {"table": "table", "jsonl": "records", "json": "json", "yaml": "json", "fastq": "reads",
              "fasta": "sequences", "vcf": "variants", "mtx": "matrix", "text": "document"}


def decide(path: str, display: str) -> Decision:
    """Decide what ``path`` (shown as ``display``) is, CONTENT FIRST. Raises UnreadableContent
    for a compressed file that cannot be decoded at all."""
    d = _decide(path, display)
    comp = _compression(path)
    if comp and d.source == "biomate" and d.kind not in ("binary", "galaxy") and "(" not in d.label:
        d.label += " (gzip)" if comp == "gzip" else " (bzip2)"
    return d


# A head with fewer line breaks than this is read further (a wide matrix's first line can be
# longer than HEAD_BYTES), up to MAX_DECISION_HEAD_BYTES.
_MIN_DECISION_LINES = 5
MAX_DECISION_HEAD_BYTES = 16 * 1024 * 1024


def _line_breaks(head: bytes) -> int:
    return max(head.count(b"\n"), head.count(b"\r"))


def _decision_head(path: str) -> Tuple[bytes, bool]:
    """(content head, whether it is the whole content) for the format decision: HEAD_BYTES, read
    further while it holds fewer than _MIN_DECISION_LINES lines of text — a 5,000-column CSV
    header or a long JSON Lines record is decided from whole lines, not from a cut first line."""
    n = HEAD_BYTES
    head = _raw_head(path, n)
    while len(head) == n and n < MAX_DECISION_HEAD_BYTES and _line_breaks(head) < _MIN_DECISION_LINES \
            and not _head_is_binary(head):
        n = min(n * 4, MAX_DECISION_HEAD_BYTES)
        head = _raw_head(path, n)
    return head, len(head) < n


def _galaxy_says_text(graw: Optional[str]) -> bool:
    """Galaxy identified the content as a TEXT datatype (csv, tabular, txt, json, …): its sniffers
    read the bytes as text, which the binary judgement honours."""
    if not graw:
        return False
    gf = _galaxy_formats()
    fn = getattr(gf, "is_text_ext", None) if gf is not None else None
    if fn is None:
        return False
    try:
        return bool(fn(graw))
    except Exception:  # noqa: BLE001
        return False


def _decide(path: str, display: str) -> Decision:
    head, complete = _decision_head(path)
    claim = _name_claim(display)
    graw = _galaxy_identify(path, display)
    gext = graw if graw and graw not in _galaxy_generic() else None
    magic = _sniff_magic(head, path)
    binary = _head_is_binary(head, complete)
    if binary and _galaxy_says_text(graw) and magic is None:
        binary = False  # Galaxy's sniffers read these bytes as text
    elif not binary and (magic is not None or _galaxy_says_binary(gext, path)):
        # A binary SIGNATURE (%PDF-, PK.., \x89PNG, …) or Galaxy's identification as a non-text
        # datatype decides, whatever share of the head happens to be ASCII: a PDF 1.x with
        # uncompressed streams is mostly ASCII, yet it is a PDF — never "text in gb18030".
        binary = True
    if binary:
        content = gext or magic
        if content == "h5" and claim and _same_family(claim[1], "h5"):
            content = claim[1]  # an HDF5 container named as one of its specialisations
        if content is None and claim and claim[0] == "other":
            # Unrecognised binary under a name BioMate has no reader for: nothing contradicts the
            # name, so it labels the file.
            d = Decision("binary", "binary", claim[1], claim[2], "biomate", gext)
        elif content is None:
            d = Decision("binary", "binary", "binary", "Binary", "biomate", gext)
        else:
            src = "galaxy" if gext else "biomate"
            label = _format_label(content) if gext else _binary_label(content)
            d = Decision("galaxy" if gext else "binary", _binary_view(content), content, label, src, gext)
        if claim and _binary_contradicts(claim, d, magic):
            d.mismatch = _mismatch(claim, d)
        return d

    # The same codec every text reader uses (_open_text decides from the first HEAD_BYTES).
    enc = _text_encoding(head[:HEAD_BYTES], complete and len(head) <= HEAD_BYTES)
    text = codecs.getincrementaldecoder(enc)("replace").decode(head, final=complete)
    d = _decide_text(path, display, text, complete, claim, gext)
    d.encoding = enc
    return d


def _decide_text(path: str, display: str, text: str, complete: bool, claim: Optional[Tuple[str, str, str]],
                 gext: Optional[str]) -> Decision:
    # The name's claim is honoured when the content follows it.
    if claim and claim[0] in ("fastq", "vcf", "fasta", "mtx", "json", "jsonl", "yaml", "table"):
        if _validate_claim(path, claim[0], claim[1], text, complete):
            d = _text_decision(path, claim[0], claim[1] if claim[0] == "table" else None, gext, display)
            if d.kind == "table" and claim[1] in ("csv", "tsv") and d.source == "biomate" \
                    and not (d.layout and (d.layout.spec or d.layout.recognised)):
                d.ext, d.label = claim[1], _BIOMATE_LABELS[claim[1]]
                if d.layout and d.layout.delim == ";":
                    d.label = "CSV (semicolon-separated)"
            return d
    kind, ext = _detect_text(path, text, complete)
    if gext and gext in _GALAXY_NON_TABLE_TEXT and kind in ("table", "text"):
        kind, ext = "galaxy", gext
    elif gext and kind == "table" and ext is None and gext in _GALAXY_SPEC_KEYS:
        ext = _GALAXY_SPEC_KEYS[gext]  # Galaxy recognised BED / GFF content in a generic name
    if claim and claim[0] == "text" and kind == "table":
        # A log / Markdown / script that happens to split on a delimiter is still a document.
        kind, ext = "text", None
    d = _text_decision(path, kind, ext, gext, display)
    if claim and claim[0] in ("fastq", "vcf", "fasta", "mtx", "json", "jsonl", "yaml", "table", "binary"):
        d.mismatch = _mismatch(claim, d)
    return d


def _mismatch(claim: Tuple[str, str, str], d: "Decision") -> Optional[Tuple[str, str]]:
    """(named label, detected label) — or None when the name and the content AGREE (same format
    family, or the same label): "Named as PDF, but the content is PDF" is never a finding."""
    if _same_family(claim[1], d.ext) or claim[2] == d.label:
        return None
    return claim[2], d.label


def _galaxy_says_binary(gext: Optional[str], path: str) -> bool:
    """Galaxy identified an UNCOMPRESSED file as a binary datatype: not a Text subclass AND one of
    its image / PDF / archive / binary classes (galaxy_formats.view_for_ext). A non-Text class
    outside those (Triples, ISA, NRRD header — text formats Galaxy models on Data) does not count.
    Compressed text (fastqsanger.gz, vcf_bgzip) is decompressed and read as text here, so the rule
    never applies to a compressed file."""
    if not gext or _compression(path) is not None:
        return False
    gf = _galaxy_formats()
    is_text = getattr(gf, "is_text_ext", None) if gf is not None else None
    view = getattr(gf, "view_for_ext", None) if gf is not None else None
    if is_text is None or view is None:
        return False
    try:
        return is_text(gext) is False and view(gext) in ("image", "document", "archive", "binary")
    except Exception:  # noqa: BLE001
        return False


# Galaxy interval / annotation extensions → BioMate spec key.
_GALAXY_SPEC_KEYS = {"bed": "bed", "bed6": "bed", "bed12": "bed", "bedgraph": "bedgraph",
                     "encodepeak": "narrowpeak", "gff": "gff", "gff3": "gff3", "gtf": "gtf"}


def _binary_contradicts(claim: Tuple[str, str, str], d: "Decision", magic: Optional[str]) -> bool:
    """Whether binary content contradicts the name: a text format named (.csv, .fastq), another
    binary format named (.png holding a JPEG or nothing recognisable), or a name BioMate does not
    know whose content is positively identified as a well-known different format."""
    if claim[0] == "binary":
        return not _same_family(claim[1], d.ext)
    if claim[0] in ("other", "text"):
        return magic is not None and not _same_family(claim[1], d.ext) and claim[1] not in d.ext
    return True


# Galaxy text formats that are not delimited tables (a .txt holding one is not a table).
_GALAXY_NON_TABLE_TEXT = frozenset({
    "sdf", "pdb", "cif", "mol2", "genbank", "stockholm", "obo", "owl",
    "sam", "pqr", "gro", "xyz", "phylip", "newick", "nhx", "nexus", "html", "markdown",
})


def _text_decision(path: str, kind: str, ext: Optional[str], gext: Optional[str], display: str) -> Decision:
    if kind == "galaxy":
        e = ext or gext or "txt"
        return Decision("galaxy", _binary_view(e) if e not in ("html", "markdown") else "document",
                        e, _format_label(e), "galaxy" if gext == e else "biomate", gext)
    if kind == "table":
        lay = _table_layout(path, spec_key=ext if ext in _SPEC_SHAPE else None)
        fmt = _table_format(lay, ext, gext)
        view = "table"
        if lay.spec in _INTERVAL_SPECS:
            view = "intervals"
        elif lay.spec in _ANNOTATION_SPECS:
            view = "annotation"
        return Decision("table", view, fmt["ext"], fmt["label"], fmt["source"], gext, layout=lay)
    if kind == "text":
        claim = _name_claim(display)
        if claim and claim[0] in ("text", "other"):
            return Decision("text", "document", claim[1], claim[2], "biomate", gext)
        if gext and gext not in _galaxy_generic():
            return Decision("text", "document", gext, _format_label(gext), "galaxy", gext)
        return Decision("text", "document", "txt", _TEXT_LABEL, "biomate", gext)
    e = ext or kind
    if gext and any(gext == c or gext.startswith(c) for c in _KIND_COMPATIBLE_GALAXY.get(kind, ())):
        fmt = {"ext": gext, "label": _format_label(gext), "source": "galaxy"}
    else:
        fmt = {"ext": e, "label": _BIOMATE_LABELS.get(e, e.upper()), "source": "biomate"}
    return Decision(kind, _KIND_VIEW.get(kind, "unknown"), fmt["ext"], fmt["label"], fmt["source"], gext)


def _table_format(lay: "TableLayout", ext: Optional[str], gext: Optional[str]) -> Dict[str, Any]:
    if lay.recognised and not lay.spec:
        e = "csv" if lay.delim in (",", ";") else "tsv"
        return {"ext": e, "label": KNOWN_TABLE_LAYOUTS[lay.recognised]["label"], "source": "biomate"}
    if gext and lay.spec and any(gext == c or gext.startswith(c) for c in _KIND_COMPATIBLE_GALAXY["table"]):
        return {"ext": gext, "label": _format_label(gext), "source": "galaxy"}
    if lay.spec:
        e = lay.spec
    elif lay.delim == "," and len(lay.names) > 1:
        e = "csv"
    elif lay.delim == "\t" and len(lay.names) > 1:
        e = "tsv"
    elif lay.delim == ";" and len(lay.names) > 1:
        e = "csv"
    elif len(lay.names) <= 1:
        e = "txt"
    else:
        e = "tabular"
    if gext in ("csv", "tsv") and e == gext:
        return {"ext": e, "label": _format_label(e), "source": "galaxy"}
    label = _BIOMATE_LABELS.get(e, e.upper())
    if lay.delim == ";" and e == "csv":
        label = "CSV (semicolon-separated)"
    return {"ext": e, "label": label, "source": "biomate"}


# ---------------------------------------------------------------------------
# Formats read through Galaxy's datatypes (metadata), and Matrix Market.
# ---------------------------------------------------------------------------
_INTERVAL_SPECS = frozenset({"bed", "narrowpeak", "broadpeak", "bedgraph", "bedpe"})
_ANNOTATION_SPECS = frozenset({"gtf", "gff", "gff3"})
# Galaxy extensions whose metadata describes a spec table.
_GALAXY_INTERVAL_EXTS = frozenset({"bed", "bed6", "bed12", "bedgraph", "interval", "encodepeak"})
_GALAXY_ANNOTATION_EXTS = frozenset({"gtf", "gff", "gff3", "gtf.gz", "gff3.gz"})


def _human_size(n: int) -> str:
    size = float(max(0, n))
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if size < 1024 or unit == "TB":
            return f"{size:.0f} {unit}" if unit == "B" else f"{size:.1f} {unit}"
        size /= 1024
    return f"{n} B"  # pragma: no cover


def _meta_int(meta: Dict[str, Any], key: str) -> Optional[int]:
    v = meta.get(key)
    if isinstance(v, bool):
        return None
    if isinstance(v, int):
        return v
    if isinstance(v, float) and v.is_integer():
        return int(v)
    return None


def _meta_list(meta: Dict[str, Any], key: str, drop: Sequence[str] = ()) -> List[str]:
    v = meta.get(key)
    if not isinstance(v, (list, tuple)):
        return []
    return [str(x) for x in v if str(x) and str(x) not in drop]


def _meta_problem(p: DataProfile, meta: Dict[str, Any], label: str) -> bool:
    """Emit the note for a skipped/failed metadata read; True when there is no usable metadata."""
    if meta.get("skipped") == "too_large":
        emit(p, "note", "format_metadata_skipped",
             f"{label} metadata was not read: the file ({_human_size(int(meta.get('bytes') or 0))}) is above the "
             f"{_human_size(int(meta.get('cap') or 0))} limit for in-request reading.",
             format=label, size=_human_size(int(meta.get("bytes") or 0)),
             cap=_human_size(int(meta.get("cap") or 0)))
        return True
    if meta.get("skipped"):
        return True
    if meta.get("error"):
        # The reason in words — never the library's message (it carries temp paths / internals).
        err = str(meta["error"]).lower()
        reason = "it ends early" if ("truncat" in err or "eof" in err or "end of file" in err) else "it is malformed"
        emit(p, "note", "format_header_unreadable", "", "watch", format=label, error=reason)
        return True
    return not meta


def _spec_table_findings(p: DataProfile, path: str, layout: TableLayout, gext: Optional[str]) -> None:
    """Format findings for a spec table (BED-like intervals, GTF/GFF annotation, SMILES) from
    Galaxy's metadata. Without Galaxy the table profile + the columns_spec note stand alone."""
    spec = layout.spec or ""
    label = _BIOMATE_LABELS.get(spec, spec.upper())
    if spec in _INTERVAL_SPECS and gext in _GALAXY_INTERVAL_EXTS:
        meta = _galaxy_metadata(path, gext)
        if _meta_problem(p, meta, label):
            return
        emit(p, "signal", "intervals_summary",
             f"{p.rows:,} genomic intervals in {_meta_int(meta, 'columns') or p.cols} columns.",
             regions=p.rows, columns=_meta_int(meta, "columns") or p.cols)
        strand = _meta_int(meta, "strandCol")
        if strand is not None:
            if strand > 0:
                name = layout.names[strand - 1] if strand - 1 < len(layout.names) else f"column_{strand}"
                emit(p, "note", "intervals_stranded", f"Strand is given (column {name!r}).",
                     column=name, index=strand)
            else:
                emit(p, "note", "intervals_unstranded",
                     "No strand column: intervals are treated as unstranded.")
    elif spec in _ANNOTATION_SPECS and gext in _GALAXY_ANNOTATION_EXTS:
        meta = _galaxy_metadata(path, gext)
        if _meta_problem(p, meta, label):
            return
        attrs = meta.get("attribute_types") if isinstance(meta.get("attribute_types"), dict) else {}
        comments = _meta_int(meta, "comment_lines") or 0
        emit(p, "signal", "annotation_features",
             f"{p.rows:,} feature lines, {comments:,} comment line(s); {len(attrs)} attribute key(s): "
             + ", ".join(_named(list(attrs))) + ".",
             features=p.rows, comments=comments, count=len(attrs), attributes=_named(list(attrs)))
    elif spec == "smi" and gext == "smi":
        meta = _galaxy_metadata(path, gext)
        if _meta_problem(p, meta, label):
            return
        n = _meta_int(meta, "number_of_molecules")
        if n is not None:
            p.stats_map["molecules"] = n
            emit(p, "signal", "molecules_count", "", molecules=n)


def _profile_mtx(path: str, member: Optional[Dict[str, Any]] = None) -> DataProfile:
    """Matrix Market: dimensions + stored entries from the size line (the data is not read)."""
    p = DataProfile()
    banner = ""
    size_line = None
    with _open_text(path) as f:
        for i, line in enumerate(f):
            if i == 0:
                banner = line.strip()
            if line.startswith("%") or not line.strip():
                if i > 10_000:
                    break
                continue
            size_line = line.split()
            break
    parts = banner.split()
    layout = parts[2].lower() if len(parts) > 2 else ""
    field_ = parts[3].lower() if len(parts) > 3 else ""
    symmetry = parts[4].lower() if len(parts) > 4 else ""
    try:
        dims = [int(x) for x in (size_line or [])]
    except ValueError:
        dims = []
    if not banner.lower().startswith("%%matrixmarket") or len(dims) < 2:
        p.quality = "blocked"
        emit(p, "note", "mtx_bad_header",
             "Not a readable Matrix Market file: the %%MatrixMarket banner or the size line is missing.", "blocked")
        return p
    rows, cols = dims[0], dims[1]
    p.rows, p.cols = rows, cols
    p.stats_map.update(rows=rows, columns=cols)
    if layout == "coordinate" and len(dims) >= 3:
        p.stats_map["entries"] = dims[2]
    if layout == "coordinate" and len(dims) >= 3:
        nnz = dims[2]
        density = (100.0 * nnz / (rows * cols)) if rows and cols else 0.0
        # Rows / columns / entries are the profile's stats: the signal states only what they do
        # not — the value type and the density (params keep the numbers for the UI).
        emit(p, "signal", "mtx_dimensions", "",
             rows=rows, cols=cols, nnz=nnz, density=round(density, 2), field=field_, symmetry=symmetry)
    else:
        emit(p, "signal", "mtx_dense", "", rows=rows, cols=cols, field=field_)
    if member and member.get("role") == "matrix" and member.get("features") and member.get("barcodes"):
        emit(p, "note", "mtx_tenx_set",
             f"10x matrix: rows are the features in {member['features']}, columns the cells in "
             f"{member['barcodes']} (same folder).",
             features=member["features"], barcodes=member["barcodes"])
    else:
        emit(p, "note", "mtx_orientation",
             "Matrix Market files carry no row/column names: pair this matrix with its features/barcodes files "
             "(10x: rows are features, columns are cells).")
    emit(p, "note", "format_metadata_only", "", format="Matrix Market")
    return p


def _profile_galaxy_format(path: str, ext: str, size: int, label: Optional[str] = None) -> DataProfile:
    """A format BioMate has no analysis for, described from Galaxy's metadata (or identified
    only). Never claims anything about content it did not read: the verdict is "unassessed"
    unless the metadata shows something worth checking."""
    p = DataProfile()
    label = label or _format_label(ext)
    meta = _galaxy_metadata(path, ext)
    described = False
    if not _meta_problem(p, meta, label):
        described = _galaxy_meta_findings(p, ext, meta, label)
    if described:
        # Only when no data values were read: a spreadsheet whose first rows are previewed has
        # had values read (its own notes say the sheet is previewed, not checked cell by cell).
        if not p.sample_rows:
            emit(p, "note", "format_metadata_only", "", format=label)
    elif not any(f["code"] in ("format_header_unreadable",) for f in p.findings):
        emit(p, "note", "format_identified", "", format=label, size=_human_size(size))
    return p


_SORT_ORDER_WORDS = {"queryname": "by read name", "unsorted": "unsorted", "unknown": "not stated in the header"}
# The SAM specification's @HD SO values.
_SORT_ORDER_KEYS = frozenset({"unknown", "unsorted", "queryname", "coordinate"})


def _galaxy_meta_findings(p: DataProfile, ext: str, meta: Dict[str, Any], label: str) -> bool:
    """Findings from one format's Galaxy metadata; False when nothing useful was in it."""
    if ext == "h5ad":
        shape = meta.get("shape")
        cells = genes = None
        if isinstance(shape, (list, tuple)) and len(shape) >= 2:
            cells, genes = _meta_int({"v": shape[0]}, "v"), _meta_int({"v": shape[1]}, "v")
        # Galaxy reports -1 when X is stored sparse / unreadable: obs/var sizes are the truth then.
        if cells is None or cells < 0:
            cells = _meta_int(meta, "obs_size")
        if genes is None or genes < 0:
            genes = _meta_int(meta, "var_size")
        if cells is None or genes is None or cells < 0 or genes < 0:
            return False
        p.rows, p.cols = cells, genes
        p.stats_map.update(cells=cells, genes=genes)
        obs = _meta_list(meta, "obs_layers", ("index", "_index"))
        var = _meta_list(meta, "var_layers", ("index", "_index"))
        # The counts are the cells / genes stats; the finding states the orientation only.
        emit(p, "signal", "anndata_shape", "", cells=cells, genes=genes)
        if obs:
            emit(p, "note", "anndata_obs", f"{len(obs)} cell annotation column(s): {', '.join(_named(obs))}.",
                 count=len(obs), columns=_named(obs))
        if var:
            emit(p, "note", "anndata_var", f"{len(var)} gene annotation column(s): {', '.join(_named(var))}.",
                 count=len(var), columns=_named(var))
        obsm = _meta_list(meta, "obsm_layers")
        if obsm:
            emit(p, "note", "anndata_embeddings", f"Embeddings stored: {', '.join(_named(obsm))}.",
                 count=len(obsm), embeddings=_named(obsm))
        # AnnData layers (alternative matrices beside X: counts, spliced, …) are the keys of the
        # ``layers`` group — NOT Galaxy's "layers_names", which lists the file's top-level groups
        # (X, obs, var, obsm, varm, uns, obsp, varp, layers): those are its stored components.
        layers = meta.get("anndata_layers")
        if isinstance(layers, list):
            names = [str(x) for x in layers]
            p.layers = names
            if names:
                emit(p, "note", "anndata_layers", "", count=len(names), layers=_named(names))
            else:
                emit(p, "note", "anndata_no_layers", "")
        groups = _meta_list(meta, "layers_names")
        if groups:
            emit(p, "note", "anndata_components", "", count=len(groups), components=_named(groups))
        return True
    if ext == "loom":
        shape = meta.get("shape")
        if not (isinstance(shape, (list, tuple)) and len(shape) >= 2):
            return False
        genes, cells = _meta_int({"v": shape[0]}, "v"), _meta_int({"v": shape[1]}, "v")
        if genes is None or cells is None or genes < 0 or cells < 0:
            return False
        p.rows, p.cols = cells, genes
        p.stats_map.update(cells=cells, genes=genes)
        emit(p, "signal", "loom_shape", "", genes=genes, cells=cells)
        rattrs = _meta_list(meta, "row_attrs_names")
        cattrs = _meta_list(meta, "col_attrs_names")
        if rattrs:
            emit(p, "note", "loom_row_attrs", f"Gene attributes: {', '.join(_named(rattrs))}.",
                 count=len(rattrs), columns=_named(rattrs))
        if cattrs:
            emit(p, "note", "loom_col_attrs", f"Cell attributes: {', '.join(_named(cattrs))}.",
                 count=len(cattrs), columns=_named(cattrs))
        layers = _meta_list(meta, "layers_names")
        if layers:
            emit(p, "note", "loom_layers", f"Layers: {', '.join(_named(layers))}.",
                 count=len(layers), layers=_named(layers))
        return True
    if ext in ("bam", "cram", "qname_sorted.bam", "unsorted.bam"):
        refs = _meta_int(meta, "reference_count")
        if refs is None:
            return False
        p.stats_map["references"] = refs
        # The count is the profile's "references" stat; the signal adds the total length, and
        # only when the header states one (a header without LN values has no length to report).
        total_len = _meta_int(meta, "reference_total_length") or 0
        if total_len > 0:
            emit(p, "signal", "alignment_references", "", references=refs, length=total_len,
                 names=_named(_meta_list(meta, "reference_names")))
        order = str(meta.get("sort_order") or "unknown")
        if order == "coordinate":
            emit(p, "note", "alignment_sorted", "", order=order)
        else:
            # ``order`` is the header's SO value as written; ``order_key`` is it mapped onto the SAM
            # specification's vocabulary (anything else → "unknown") for the UI to translate;
            # ``order_words`` is the English.
            key = order if order in _SORT_ORDER_KEYS else "unknown"
            emit(p, "note", "alignment_not_coordinate_sorted", "", "watch", order=order, order_key=key,
                 order_words=_SORT_ORDER_WORDS.get(order, f"“{order}”"))
        rgs = _meta_int(meta, "read_group_count") or 0
        if rgs:
            samples = _meta_list(meta, "samples")
            emit(p, "signal", "alignment_read_groups",
                 f"{rgs} read group(s); sample(s): {', '.join(_named(samples)) or '—'}.",
                 count=rgs, samples=_named(samples))
        else:
            emit(p, "note", "alignment_no_read_groups",
                 "No read groups (@RG) in the header: GATK and most variant callers require them.", "watch")
        return True
    if ext == "sdf":
        n = _meta_int(meta, "number_of_molecules")
        if n is None:
            return False
        p.rows = n
        p.stats_map["molecules"] = n
        emit(p, "signal", "molecules_count", "", molecules=n)
        return True
    if ext in ("pdb", "cif"):
        chains = _meta_list(meta, "chain_ids")
        if not chains:
            return False
        p.stats_map["chains"] = len(chains)
        emit(p, "signal", "structure_chains", f"{len(chains)} chain(s): {', '.join(_named(chains))}.",
             count=len(chains), chains=_named(chains))
        return True
    if ext == "xlsx":
        sheets = meta.get("sheets")
        if not isinstance(sheets, list) or not sheets:
            return False
        names = [str(sh.get("name")) for sh in sheets if isinstance(sh, dict)]
        first = sheets[0] if isinstance(sheets[0], dict) else {}
        p.rows, p.cols = int(first.get("rows") or 0), int(first.get("cols") or 0)
        p.stats_map["sheets"] = len(names)
        # The sheet names are stated by ONE finding: the preview's (one sheet), the combined
        # sheets-and-preview finding (several sheets), or the sheet list (no preview).
        previewed = _spreadsheet_preview(p, meta.get("preview"))
        if not previewed:
            emit(p, "signal", "spreadsheet_sheets", "", count=len(names), sheets=_named(names))
        elif len(names) > 1:
            emit(p, "signal", "spreadsheet_preview_sheets", "", count=len(names), sheets=_named(names),
                 sheet=p.preview_sheet, rows=len(p.sample_rows or []))
        else:
            emit(p, "note", "spreadsheet_preview", "", sheet=p.preview_sheet, rows=len(p.sample_rows or []))
        emit(p, "note", "spreadsheet_convert", "")
        return True
    return False


def _spreadsheet_preview(p: DataProfile, preview: Any) -> bool:
    """The first sheet's first rows as the profile's preview table (``columns`` + ``sampleRows``,
    the same caps as a delimited table): line 1 is the header when the table rule says so
    (_line1_is_header), else the columns are named column_1, column_2, … True when a preview was
    set (the caller states it in the sheets finding)."""
    if not isinstance(preview, dict) or not isinstance(preview.get("rows"), list) or not preview["rows"]:
        return False
    rows = [[str(c) for c in r] for r in preview["rows"] if isinstance(r, list)]
    if not rows:
        return False
    width = max(len(r) for r in rows)
    rows = [r + [""] * (width - len(r)) for r in rows]
    if len(rows) > 1 and _line1_is_header(rows[0], rows[1:]):
        names, data = [c.strip() or f"column_{i + 1}" for i, c in enumerate(rows[0])], rows[1:]
    else:
        names, data = [f"column_{i + 1}" for i in range(width)], rows
    p.columns = names[:MAX_PREVIEW_COLS]
    p.sample_rows = [[_preview_cell(c) for c in r[:MAX_PREVIEW_COLS]] for r in data[:MAX_PREVIEW_ROWS]]
    p.preview_sheet = str(preview.get("sheet") or "")
    # An unsized sheet (no stored dimension) keeps shape 0 × 0: its size is unknown without a
    # full parse, and the preview's row count is not the sheet's.
    return True


# ---------------------------------------------------------------------------
# FASTA
# ---------------------------------------------------------------------------
_FASTA_EXTS = (".fa", ".fasta", ".fna", ".faa", ".fas", ".ffn", ".fsa", ".frn", ".mfa")
# Content bytes scanned per FASTA (decompressed); beyond it the statistics are over a prefix.
MAX_FASTA_BYTES = 256 * 1024 * 1024
# Share of residues that must be A/C/G/T/U/N for a nucleotide FASTA (else protein).
_NUCLEOTIDE_FRAC = 0.9
# N (unknown base) share that is worth a note.
_HIGH_N_FRAC = 0.1


def _n50(lengths: Sequence[int]) -> int:
    total = sum(lengths)
    acc = 0
    for n in sorted(lengths, reverse=True):
        acc += n
        if acc * 2 >= total:
            return n
    return 0


# Residue letters that occur in nucleotide sequences (IUPAC codes, gaps); anything else (E, F,
# I, L, P, Q, X, *, …) only in protein.
_NUCLEOTIDE_IUPAC = b"ACGTUNRYKMSWBDHV-."


def _profile_fasta(path: str) -> DataProfile:
    """FASTA (plain / gzip / bzip2): sequence count, total / mean / min / max length, N50, and
    for nucleotides GC% and N share. Streams at most MAX_FASTA_BYTES of content — the cap holds
    inside one record too (a single 3 GB chromosome stops at the cap, its length a lower bound)."""
    p = DataProfile()
    lengths: List[int] = []
    cur: Optional[int] = None
    gc = at = n_bases = residues = scanned = other = 0
    truncated = False
    orphan = 0  # sequence lines before the first '>' header
    with _open_bytes(path) as f:
        for line in f:
            scanned += len(line)
            if scanned > MAX_FASTA_BYTES:
                truncated = True
                break
            if line[:1] == b">":
                if cur is not None:
                    lengths.append(cur)
                cur = 0
                continue
            if line[:1] == b";":
                continue  # old-style comment line
            seq = line.strip()
            if not seq:
                continue
            if cur is None:
                orphan += 1
                continue
            cur += len(seq)
            residues += len(seq)
            u = seq.upper()
            gc += u.count(b"G") + u.count(b"C")
            at += u.count(b"A") + u.count(b"T") + u.count(b"U")
            n_bases += u.count(b"N")
            other += len(u.translate(None, _NUCLEOTIDE_IUPAC))
    if cur is not None:
        lengths.append(cur)

    n = len(lengths)
    p.rows = n
    if n == 0:
        p.quality = "blocked"
        emit(p, "note", "fasta_no_sequences", "", "blocked")
        return p
    total = sum(lengths)
    mean = total / n
    p.cols = int(round(mean))
    p.stats_map.update(sequences=n, bases=total)
    if truncated:
        p.at_least.update({"sequences", "bases"})
    # Nucleotide: no protein-only letters, and mostly A/C/G/T/U/N (IUPAC ambiguity codes such as
    # R/Y/K/M/S/W stay nucleotide — they are not evidence of protein).
    nucleotide = residues > 0 and other / residues < 0.01 and (gc + at + n_bases) / residues >= 0.5
    unit = "bp" if nucleotide else "aa"
    emit(p, "signal", "fasta_sequences", "", sequences=n, at_least=truncated, total=total, unit=unit,
         mean=int(round(mean)), min=min(lengths), max=max(lengths), n50=_n50(lengths))
    if nucleotide:
        gc_pct = round(100.0 * gc / (gc + at), 1) if (gc + at) else 0.0
        emit(p, "signal", "fasta_gc", "", pct=gc_pct)
        n_frac = n_bases / residues if residues else 0.0
        if n_frac >= _HIGH_N_FRAC:
            emit(p, "note", "fasta_high_n", "", "watch", pct=int(round(100 * n_frac)))
    elif residues:
        emit(p, "note", "fasta_protein", "")
    empty = sum(1 for x in lengths if x == 0)
    if empty:
        emit(p, "note", "fasta_empty_records", "", "watch", count=empty)
    if orphan:
        emit(p, "note", "fasta_orphan_lines", "", "watch", count=orphan)
    if truncated:
        emit(p, "note", "fasta_profiled_subset", "", mb=MAX_FASTA_BYTES // (1024 * 1024))
    return p


# ---------------------------------------------------------------------------
# FASTQ
# ---------------------------------------------------------------------------
def _profile_fastq(path: str, sample_reads: int = 4000, layout: Optional[Dict[str, Any]] = None) -> DataProfile:
    """Profile a FASTQ file: reads (sampled), mean length, mean quality.

    Read-counting mirrors DatasetValidator._count_fastq_reads (sampled,
    gzip-aware). We additionally read the length/quality of sampled reads for a
    numeric-first signal summary and a single-end note.
    """
    p = DataProfile()
    n_reads = 0
    bad = 0
    total_len = 0
    total_q = 0
    q_chars = 0
    truncated = False
    with _open_text(path) as f:
        lines = _nul_guard(f)
        while True:
            header = next(lines, "")
            if not header:
                break
            if not header.strip():
                continue  # blank lines between / after records
            seq = next(lines, "").strip()
            plus = next(lines, "")
            qual_line = next(lines, "")
            if not qual_line:
                break  # incomplete final record (end of file / truncated stream)
            qual = qual_line.strip()
            if not header.startswith("@") or not plus.startswith("+") or not seq or len(seq) != len(qual):
                bad += 1  # not a 4-line record with a quality string per base
                if bad + n_reads >= sample_reads:
                    truncated = True
                    break
                continue
            n_reads += 1
            total_len += len(seq)
            for ch in qual:
                total_q += ord(ch) - 33  # Phred+33
                q_chars += 1
            if n_reads + bad >= sample_reads:
                truncated = True
                break

    # FASTQ "shape": rows = reads observed, cols = mean read length.
    p.rows = n_reads
    mean_len = (total_len / n_reads) if n_reads else 0
    p.cols = int(round(mean_len))
    mean_q = (total_q / q_chars) if q_chars else 0.0
    p.stats_map.update(reads=n_reads, read_length=int(round(mean_len)))
    if truncated:
        p.at_least.add("reads")

    emit(p, "signal", "fastq_reads", "", reads=n_reads, at_least=truncated, mean_len=int(round(mean_len)))
    emit(p, "signal", "fastq_mean_quality", "", q=round(mean_q, 1))
    if bad:
        emit(p, "note", "fastq_malformed_records", "", "watch", count=bad, checked=bad + n_reads)
    # Single- vs paired-end is a fact about the FOLDER (is the mate there?), not about this
    # file's bytes: decided from the folder context with Galaxy's pairing when the caller has
    # it, else stated as unknown.
    _fastq_layout_findings(p, layout)

    if mean_q and mean_q < 20:
        emit(p, "note", "fastq_low_quality", "", "watch", q=round(mean_q, 1))
    if n_reads == 0:
        p.quality = "blocked"
        emit(p, "note", "fastq_no_records", "No FASTQ records parsed — file may be malformed.", "blocked")
    return p


# ---------------------------------------------------------------------------
# VCF
# ---------------------------------------------------------------------------
def _fastq_layout_findings(p: DataProfile, layout: Optional[Dict[str, Any]]) -> None:
    """The note states what was observed (the mate, its absence); the plan states what follows
    (single- / paired-end). Each fact is said once: the note never restates the decision."""
    if not layout:
        emit(p, "note", "fastq_single_file",
             "Profiled on its own: whether it has a read-2 mate was not checked.")
        emit(p, "plan", "fastq_single_end", "single FASTQ observed",
             effect_text="suggested single-end pipeline (override if paired mate exists)")
        return
    read = "2" if layout.get("role") == "reverse" else "1"
    sample = layout.get("sample") or ""
    if layout["status"] == "index":
        emit(p, "note", "fastq_index_read", "", read=layout.get("read") or "I1", sample=sample)
        return
    if layout["status"] == "paired":
        emit(p, "note", "fastq_paired_mate",
             f"Read {read} of sample {sample}; its mate {layout['mate']} is in the same folder.",
             read=read, sample=sample, mate=layout["mate"])
        emit(p, "plan", "fastq_paired_end", "both reads of the pair present",
             effect_text=f"paired-end pipeline (sample {sample})", sample=sample)
    elif layout["status"] == "orphan":
        missing = "1" if read == "2" else "2"
        emit(p, "note", "fastq_mate_missing",
             f"Read {read} of sample {sample}; no read-{missing} mate is in this folder.",
             "watch", read=read, missing=missing, sample=sample)
        emit(p, "plan", "fastq_orphan_single_end", "read pair incomplete",
             effect_text="single-end for this sample until the mate is added", sample=sample)
    else:
        emit(p, "note", "fastq_single_end_named",
             "No read-1/read-2 naming and no mate in this folder.")
        emit(p, "plan", "fastq_single_end", "single FASTQ observed",
             effect_text="suggested single-end pipeline (override if paired mate exists)")


def _profile_vcf(path: str) -> DataProfile:
    """Profile a VCF: variant count (rows) and sample count (cols); data lines without the 8
    fixed tab-separated columns are counted, not taken as variants."""
    p = DataProfile()
    n_variants = 0
    n_samples = 0
    malformed = 0
    with _open_text(path) as f:
        for line in _nul_guard(f):
            if line.startswith("##"):
                continue
            if line.startswith("#CHROM"):
                cols = line.rstrip("\r\n").split("\t")
                # Standard VCF: 8 fixed cols, then FORMAT, then samples.
                n_samples = max(0, len(cols) - 9)
                continue
            if not line.strip():
                continue
            fields = line.rstrip("\r\n").split("\t")
            if len(fields) < 8 or not fields[1].isdigit():
                malformed += 1
                continue
            n_variants += 1

    p.rows = n_variants
    p.cols = n_samples
    p.stats_map.update(variants=n_variants, samples=n_samples)
    # One finding states the counts (the stats carry the same numbers); a second note and a plan
    # line repeating them were dropped in round 5.
    emit(p, "signal", "vcf_records", "", variants=n_variants, samples=n_samples)
    if malformed:
        emit(p, "note", "vcf_malformed_lines", "", "watch", count=malformed)
    if n_variants == 0:
        emit(p, "note", "vcf_no_variants", "", "watch")
    return p


# ---------------------------------------------------------------------------
# Tables (CSV / TSV) — the leakage / effective-N / class-balance surface.
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Table layout: delimiter + where the column names come from.
# ---------------------------------------------------------------------------
# Header-less spec formats → (spec key, Galaxy extension for its column_names). Their files have
# no header row by specification; comment/track/browser lines are skipped.
_SPEC_TABLE_EXTS: Dict[str, Tuple[str, Optional[str]]] = {
    ".bed": ("bed", "bed"), ".bedgraph": ("bedgraph", None), ".bdg": ("bedgraph", None),
    ".narrowpeak": ("narrowpeak", "encodepeak"), ".broadpeak": ("broadpeak", None),
    ".gtf": ("gtf", "gtf"), ".gff": ("gff", "gff"), ".gff3": ("gff3", "gff3"),
    ".bedpe": ("bedpe", None),
    ".smi": ("smi", "smi"), ".smiles": ("smi", "smi"),
}
# Spec column names. Identical to Galaxy's class ``column_names`` (galaxy.datatypes.interval
# Bed / ENCODEPeak / Gff / Gff3 / Gtf, galaxy.datatypes.molecules SMILES) — Galaxy's are used
# when importable; these keep the same names on hosts without Galaxy. bedGraph / broadPeak have
# no Galaxy class: UCSC bedGraph (chrom start end value) and ENCODE broadPeak (BED6+3).
_SPEC_FALLBACK_NAMES: Dict[str, List[str]] = {
    "bed": ["Chrom", "Start", "End", "Name", "Score", "Strand", "ThickStart", "ThickEnd",
            "ItemRGB", "BlockCount", "BlockSizes", "BlockStarts"],
    "narrowpeak": ["Chrom", "Start", "End", "Name", "Score", "Strand", "SignalValue", "pValue",
                   "qValue", "Peak"],
    "broadpeak": ["Chrom", "Start", "End", "Name", "Score", "Strand", "SignalValue", "pValue", "qValue"],
    "bedgraph": ["Chrom", "Start", "End", "Value"],
    "bedpe": ["Chrom1", "Start1", "End1", "Chrom2", "Start2", "End2", "Name", "Score", "Strand1", "Strand2"],
    "gff": ["Seqname", "Source", "Feature", "Start", "End", "Score", "Strand", "Frame", "Group"],
    "gff3": ["Seqid", "Source", "Type", "Start", "End", "Score", "Strand", "Phase", "Attributes"],
    "gtf": ["Seqname", "Source", "Feature", "Start", "End", "Score", "Strand", "Frame", "Attributes"],
    "smi": ["SMILES", "TITLE"],
}
# What a data line of each spec format must look like: (minimum columns, 0-based columns that
# must be integers). A file whose sampled lines mostly fail this is not that format.
_SPEC_SHAPE: Dict[str, Tuple[int, Tuple[int, ...]]] = {
    "bed": (3, (1, 2)), "narrowpeak": (10, (1, 2)), "broadpeak": (9, (1, 2)),
    "bedgraph": (4, (1, 2)), "bedpe": (6, (1, 2, 4, 5)),
    "gtf": (9, (3, 4)), "gff": (9, (3, 4)), "gff3": (9, (3, 4)), "smi": (1, ()),
}
# Share of sampled spec-format lines that must match _SPEC_SHAPE.
_SPEC_VALID_FRAC = 0.8
# Values treated as missing when inferring whether line 1 is a header.
_MISSING_TOKENS = frozenset({"", "na", "nan", "null", "none", "n/a", "."})
# Rows sampled to decide header vs data.
_HEADER_SAMPLE_ROWS = 200
# ... and at most this many cells (a 30,000-column matrix samples a few rows, not 200).
_HEADER_SAMPLE_CELLS = 400_000
# A column is numeric when at least this share of its non-empty data values parse as numbers.
_NUMERIC_COL_FRAC = 0.8


@dataclass
class TableLayout:
    delim: str
    # Column names, and where they came from: "header" (the header line), "comment" (the last '#'
    # line before the data), "spec" (the format's specification), "generated" (column_1…: no
    # header row).
    names: List[str]
    names_source: str = "header"
    # True when the first record after ``skip_lines`` is a header row (not data). The edit route
    # counts data rows after this many header records.
    header_row: bool = True
    # Spec format key (bed, gtf, …) or None for a generic delimited table.
    spec: Optional[str] = None
    # False when a spec-format file's lines do not follow that format (e.g. a binary or a
    # mislabelled file named .bed): it is then not served or profiled as a table.
    valid: bool = True
    # Physical lines before the header/data (leading '#' comment lines and blank lines of a
    # generic table, e.g. featureCounts' "# Program:…" line). Spec formats skip their own.
    skip_lines: int = 0
    # Width of the header line; ``names`` is extended with column_N when data rows are wider.
    header_width: int = 0
    # Decimal mark of the numbers: "," when they are written with a decimal comma (1,5 — only in a
    # file whose delimiter is not the comma, e.g. a European semicolon CSV), else ".".
    decimal: str = "."
    # A recognised tool-output layout (see KNOWN_TABLE_LAYOUTS), e.g. "featurecounts".
    recognised: Optional[str] = None

    def annotation_columns(self) -> Tuple[str, ...]:
        """The recognised layout's annotation columns (constant or sparse by design)."""
        spec = KNOWN_TABLE_LAYOUTS.get(self.recognised or "")
        return spec["annotation"] if spec else ()


# Tool outputs recognised from their header row: key → label (the format chip), the leading
# columns that identify the layout (exactly, in order), how many value columns must follow, and
# the annotation columns — identifiers and coordinates that are constant or sparse BY DESIGN on
# many inputs (featureCounts on one chromosome has one Chr and one Strand), so the near-constant /
# high-missing checks do not apply to them.
KNOWN_TABLE_LAYOUTS: Dict[str, Dict[str, Any]] = {
    "featurecounts": {"label": "featureCounts counts", "lead": ("Geneid", "Chr", "Start", "End", "Strand", "Length"),
                      "min_values": 1, "annotation": ("Geneid", "Chr", "Start", "End", "Strand", "Length")},
    "mageck_count": {"label": "MAGeCK counts", "lead": ("sgRNA", "Gene"), "min_values": 1,
                     "annotation": ("sgRNA", "Gene")},
    # Salmon / RSEM: one sample per file (no sample columns); featureCounts / MAGeCK: the
    # columns after the lead are the samples (see _matrix_sample_columns).
    "salmon_quant": {"label": "Salmon quantification", "lead": ("Name", "Length", "EffectiveLength", "TPM", "NumReads"),
                     "min_values": 0, "annotation": ("Name", "Length", "EffectiveLength")},
    "rsem_results": {"label": "RSEM quantification",
                     "lead": ("gene_id", "transcript_id(s)", "length", "effective_length", "expected_count", "TPM", "FPKM"),
                     "min_values": 0, "annotation": ("gene_id", "transcript_id(s)", "length", "effective_length")},
}


def _recognise_layout(names: Sequence[str]) -> Optional[str]:
    """The KNOWN_TABLE_LAYOUTS key whose leading columns head ``names`` exactly, else None."""
    names = [str(n).strip() for n in names]
    for key, spec in KNOWN_TABLE_LAYOUTS.items():
        lead = spec["lead"]
        if tuple(names[:len(lead)]) == lead and len(names) >= len(lead) + spec["min_values"]:
            return key
    return None


_FROM_NAME = object()


def _spec_of(path: str) -> Optional[Tuple[str, Optional[str]]]:
    _, ext = os.path.splitext(_strip_gz(path.lower()))
    return _SPEC_TABLE_EXTS.get(ext)


def _spec_by_key(key: Optional[str]) -> Optional[Tuple[str, Optional[str]]]:
    if not key:
        return None
    for spec in _SPEC_TABLE_EXTS.values():
        if spec[0] == key:
            return spec
    return None


def _spec_names(spec: str, galaxy_ext: Optional[str]) -> List[str]:
    if galaxy_ext:
        gf = _galaxy_formats()
        if gf is not None:
            try:
                names = gf.spec_column_names(galaxy_ext)
                if names:
                    return list(names)
            except Exception:  # noqa: BLE001
                pass
    return list(_SPEC_FALLBACK_NAMES.get(spec, []))


def _is_spec_skip(line: str) -> bool:
    return line.startswith("#") or line.startswith("track") or line.startswith("browser")


def _spec_lines(f: Iterator[str]) -> Iterator[str]:
    """Data lines of a spec format: comment/track/browser and blank lines dropped; a GFF3
    ``##FASTA`` section ends the feature table."""
    for line in f:
        if line.startswith("##FASTA"):
            return
        if not line.strip() or _is_spec_skip(line):
            continue
        yield line


def _spec_reader(lines: Iterator[str], delim: str) -> Iterator[List[str]]:
    if delim == " ":
        for line in _nul_guard(lines):
            yield line.split()
    else:
        for row in csv.reader(_nul_guard(lines), delimiter=delim, quoting=csv.QUOTE_NONE):
            yield row


def _to_float(v: str, decimal: str = ".") -> float:
    """``v`` as a number; with a decimal-comma layout "1,5" is 1.5 (a value holding both marks,
    such as "1.234,5", is not read as a number)."""
    if decimal == "," and "," in v:
        if "." in v:
            raise ValueError(v)
        v = v.replace(",", ".")
    return float(v)


def _is_number(v: str, decimal: str = ".") -> bool:
    try:
        _to_float(v, decimal)
        return True
    except ValueError:
        return False


_DECIMAL_COMMA_RE = re.compile(r"^[+-]?\d+,\d+(?:[eE][+-]?\d+)?$")
_DECIMAL_POINT_RE = re.compile(r"^[+-]?(?:\d+\.\d*|\.\d+)(?:[eE][+-]?\d+)?$")


def _decimal_mark(rows: Sequence[Sequence[str]], delim: str) -> str:
    """"," when the table's numbers use a decimal comma: the delimiter is not a comma and values
    like 1,5 make up at least 90% of the fractional numbers sampled; else ".". A comma-delimited
    file cannot hold an unquoted decimal comma, so its marks are always "."."""
    if delim == ",":
        return "."
    comma = point = 0
    for r in rows:
        for c in r:
            c = c.strip()
            if _DECIMAL_COMMA_RE.match(c):
                comma += 1
            elif _DECIMAL_POINT_RE.match(c):
                point += 1
    return "," if comma and comma >= 0.9 * (comma + point) else "."


def _is_missing(v: str) -> bool:
    return v.strip().lower() in _MISSING_TOKENS


def _shape(v: str) -> str:
    """Token pattern of a value: runs of upper letters → 'A', lower → 'a', digits → '9', other
    characters kept ('TP53' → 'A9', 'Trp53' → 'Aa9', 'gene_id' → 'a_a', '1990' → '9')."""
    out: List[str] = []
    for c in v.strip():
        k = "A" if c.isupper() else "a" if c.islower() else "9" if c.isdigit() else " " if c.isspace() else c
        if not out or out[-1] != k:
            out.append(k)
    return "".join(out)


# Words that commonly NAME a column of identifiers / values. Used only to break a tie that the
# value distribution cannot decide (a 3-line gene list under "Gene" / "SYMBOL").
_HEADER_VOCAB = frozenset({
    "gene", "genes", "symbol", "symbols", "gene_symbol", "genesymbol", "gene_id", "geneid", "gene_name",
    "genename", "id", "ids", "name", "names", "ensembl", "ensembl_id", "ensembl_gene_id", "entrez",
    "entrez_id", "entrezid", "accession", "accessions", "sample", "samples", "sample_id", "barcode",
    "barcodes", "cell", "cells", "cell_id", "feature", "features", "protein", "proteins", "uniprot",
    "transcript", "transcripts", "transcript_id", "probe", "probe_id", "probeset", "value", "values",
    "smiles", "compound", "compounds", "target", "targets", "label", "labels", "sequence", "peptide",
    "peptides", "metabolite", "metabolites", "chromosome", "chrom", "position", "variant", "rsid",
})

# Consecutive integer column names (1, 2, 3 or years 1990, 2000, 2010) — an index-like header.
def _progression(vals: Sequence[str]) -> bool:
    try:
        nums = [float(v) for v in vals]
    except ValueError:
        return False
    if len(nums) < 2 or any(not n.is_integer() for n in nums):
        return False
    steps = {nums[i + 1] - nums[i] for i in range(len(nums) - 1)}
    return len(steps) == 1 and next(iter(steps)) > 0


def _line1_is_header(first: List[str], data: List[List[str]], decimal: str = ".") -> bool:
    """Whether line 1 of a generic delimited table is a header, decided from each column's value
    distribution:

    * a column that is numeric in the data (≥80% of its non-empty values) but text in line 1
      ⇒ header (decisive);
    * a text column: line 1's token pattern (:func:`_shape`) never seen in the data ⇒ a vote for
      a header; line 1 sharing the clearly dominant pattern (≥80% of ≥5 values) ⇒ a vote for data;
      sharing a pattern of a few values ⇒ weak evidence for data;
    * a numeric column whose line-1 value is numeric ⇒ a vote for data — unless the line-1 numbers
      form an increasing integer progression (1, 2, 3 / 1990, 2000, 2010) beside a text column
      that already votes header (sample numbers or years as column names);
    * a tie is broken by line 1 holding a common column name (gene, symbol, sample, …), then by
      the weak evidence, else the long-standing default (header).
    """
    if not data:
        # One line: numbers alone are data, anything with text is a header.
        return not all(_is_number(c, decimal) for c in first if not _is_missing(c)) or all(_is_missing(c) for c in first)
    width = len(first)
    votes = 0
    weak_data = 0
    numeric_line1: List[str] = []
    for j in range(width):
        vals = [r[j].strip() for r in data if j < len(r) and not _is_missing(r[j])]
        cell = first[j].strip()
        if not vals or _is_missing(cell):
            continue  # an empty header cell (R's row-name column) is no evidence either way
        numeric = sum(1 for v in vals if _is_number(v, decimal)) / len(vals) >= _NUMERIC_COL_FRAC
        if numeric:
            if not _is_number(cell, decimal):
                return True
            numeric_line1.append(cell)
            continue
        shapes = Counter(_shape(v) for v in vals)
        s1 = _shape(cell)
        if s1 not in shapes:
            votes += 1  # line 1 is unlike every data value of its column
        elif shapes.most_common(1)[0][0] == s1 and shapes[s1] / len(vals) >= 0.8 and len(vals) >= 5:
            votes -= 1  # line 1 has the column's clearly dominant pattern
        else:
            weak_data += 1  # line 1 looks like some data values; too few values to be sure
    if numeric_line1 and not (votes > 0 and _progression(numeric_line1)):
        votes -= len(numeric_line1)
    if votes:
        return votes > 0
    if any(c.strip().lower() in _HEADER_VOCAB for c in first):
        return True
    return not (weak_data or numeric_line1)


def _spec_lines_valid(path: str, key: str, delim: str) -> bool:
    """Whether the sampled data lines follow the spec format's shape (see _SPEC_SHAPE). A file
    with no data lines (only a track line / comments) is a valid, empty table. Binary content
    (a NUL byte, or undecodable bytes) is never valid. A first line that is a plain column-name
    line (``chrom start end``) is not counted against the format."""
    min_cols, int_cols = _SPEC_SHAPE.get(key, (1, ()))
    good = total = 0
    with _open_text(path) as f:
        for i, row in enumerate(_spec_reader(_spec_lines(f), delim)):
            joined = "".join(row)
            if "�" in joined:
                return False
            ok = len(row) >= min_cols and all(row[j].strip().lstrip("-").isdigit() for j in int_cols)
            if i == 0 and not ok and _is_column_name_line(row, int_cols):
                continue
            total += 1
            good += ok
            if total >= _HEADER_SAMPLE_ROWS:
                break
    return total == 0 or good / total >= _SPEC_VALID_FRAC


def _is_column_name_line(row: Sequence[str], int_cols: Sequence[int]) -> bool:
    """A spec-format line of column names (``chrom start end``): text where integers belong."""
    return bool(int_cols) and all(j < len(row) and row[j].strip() and not _is_number(row[j]) for j in int_cols)


_SNIFF_DELIMS = ("\t", ",", ";", "|")


def _leading_skip(lines: Sequence[str]) -> Tuple[int, Optional[str]]:
    """(number of leading blank / '#' comment lines, the last comment line) of a generic table."""
    skip = 0
    last_comment = None
    for line in lines:
        if not line.strip():
            skip += 1
            continue
        if line.startswith("#"):
            skip += 1
            last_comment = line
            continue
        break
    return skip, last_comment


def _fields(line: str, delim: str) -> List[str]:
    try:
        return next(csv.reader([line], delimiter=delim))
    except (csv.Error, StopIteration):
        return [line]


def _sniff_table(lines: Sequence[str]) -> Optional[str]:
    """The delimiter of a delimited table judged over several lines (tab, comma, semicolon,
    pipe: the one that splits most lines into a consistent number of fields; the header line
    counts, so ``gene;S1;S2`` over ``A;1,5;2,0`` is semicolon-separated). "\\n" for a
    one-value-per-line list, None when the text is prose rather than a table."""
    skip, _c = _leading_skip(lines)
    rest = [ln for ln in lines[skip:] if ln.strip()][:200]
    if not rest:
        return None
    best: Optional[Tuple[float, int, str]] = None
    scores: Dict[str, float] = {}
    for order, d in enumerate(_SNIFF_DELIMS):
        if d not in rest[0] and not any(d in ln for ln in rest[1:6]):
            continue
        counts = [len(_fields(ln, d)) for ln in rest]
        multi = sum(1 for c in counts if c > 1) / len(counts)
        if multi < 0.8:
            continue
        mode, mc = Counter(counts).most_common(1)[0]
        if mode < 2:
            continue
        consistency = mc / len(counts)
        if consistency < 0.5:
            continue
        key = (consistency, -order, d)
        scores[d] = consistency
        if best is None or key[:2] > best[:2]:
            best = key
    if best is not None:
        if best[2] == "," and scores.get(";", 0) >= best[0] and _commas_are_decimal(rest):
            return ";"  # 1,5;2,25 — the commas are decimal marks inside semicolon-separated fields
        return best[2]
    return "\n" if _single_column_list(rest) else None


_NON_DECIMAL_COMMA = re.compile(r"(?<!\d),|,(?!\d)")


def _commas_are_decimal(lines: Sequence[str]) -> bool:
    """Every comma of the sampled lines sits between two digits (a decimal mark, as in 1,5)."""
    return not any(_NON_DECIMAL_COMMA.search(ln.rstrip("\r\n")) for ln in lines)


# Longest value of a one-value-per-line list (gene symbols, accessions, SMILES, barcodes).
_MAX_LIST_ITEM_CHARS = 4096


def _single_column_list(lines: Sequence[str]) -> bool:
    """One value per line (a gene / ID list), not prose: no line of four or more words and most
    lines a single token."""
    vals = [ln.strip() for ln in lines if ln.strip() and not ln.startswith("#")]
    if not vals:
        return True
    if any(len(v) > _MAX_LIST_ITEM_CHARS for v in vals):
        return False  # a list holds names / IDs, not lines of hundreds of kilobytes
    words = [len(v.split()) for v in vals]
    if any(w >= 4 for w in words) and sum(1 for w in words if w >= 2) / len(words) >= 0.2:
        return False
    return sum(1 for w in words if w >= 3) / len(words) < 0.3


def _head_lines(path: str, limit_lines: int = 400, limit_chars: int = 2 * 1024 * 1024) -> List[str]:
    out: List[str] = []
    size = 0
    with _open_text(path) as f:
        for line in _nul_guard(f):
            out.append(line)
            size += len(line)
            if len(out) >= limit_lines or size >= limit_chars:
                break
    return out


def _table_layout(path: str, spec_key: Any = _FROM_NAME) -> TableLayout:
    """Decide the delimiter and the column names of a delimited file (see _line1_is_header for
    generic tables; spec formats such as BED/GTF/SMILES have no header row by specification).
    ``spec_key`` is the spec format decided from the content (default: the one the name claims)."""
    spec = _spec_of(path) if spec_key is _FROM_NAME else _spec_by_key(spec_key)
    if spec is not None:
        return _spec_layout(path, spec)

    head = _head_lines(path)
    skip, comment = _leading_skip(head)
    delim = _sniff_table(head) or ","
    if delim == "\n":
        delim = "\t" if any("\t" in ln for ln in head[skip:skip + 20]) else ","
    sample: List[List[str]] = []
    cells = 0
    with _open_text(path) as f:
        for _ in range(skip):
            f.readline()
        for row in csv.reader(_nul_guard(f), delimiter=delim):
            if sample and (not row or all(c == "" for c in row)):
                continue
            if not sample and (not row or all(c == "" for c in row)):
                continue
            sample.append(row)
            cells += len(row)
            if len(sample) > _HEADER_SAMPLE_ROWS or cells > _HEADER_SAMPLE_CELLS:
                break
    if not sample:
        return TableLayout(delim, [], "header", header_row=True, skip_lines=skip)
    first = sample[0]
    dec = _decimal_mark(sample, delim)
    data_width = max((len(r) for r in sample[1:]), default=len(first))
    if comment is not None and len(sample) and len(_fields(comment.lstrip("#").strip(), delim)) == len(first) > 1 \
            and not _line1_is_header(first, sample[1:], dec):
        names = [c.strip() for c in _fields(comment.lstrip("#").strip(), delim)]
        names += [f"column_{i + 1}" for i in range(len(names), data_width)]
        return TableLayout(delim, names, "comment", header_row=False, skip_lines=skip, header_width=len(first),
                           decimal=dec)
    if _line1_is_header(first, sample[1:], dec):
        names = [c.strip() for c in first]
        names += [f"column_{i + 1}" for i in range(len(names), data_width)]
        return TableLayout(delim, names, "header", header_row=True, skip_lines=skip, header_width=len(first),
                           decimal=dec, recognised=_recognise_layout(names))
    width = max(len(r) for r in sample)
    return TableLayout(delim, [f"column_{i + 1}" for i in range(width)], "generated", header_row=False,
                       skip_lines=skip, header_width=width, decimal=dec)


def _spec_layout(path: str, spec: Tuple[str, Optional[str]]) -> TableLayout:
    key, galaxy_ext = spec
    comment: Optional[str] = None
    first: Optional[str] = None
    with _open_text(path) as f:
        for line in _nul_guard(f):
            if line.startswith("##FASTA"):
                break
            if not line.strip():
                continue
            if line.startswith("#"):
                comment = line
                continue
            if _is_spec_skip(line):
                continue
            first = line
            break
    if key == "smi":
        delim = "\t" if (first is None or "\t" in first) else " "
    else:
        delim = "\t"
    row1 = next(_spec_reader(iter([first]), delim), []) if first else []
    width = len(row1)
    valid = _spec_lines_valid(path, key, delim)
    int_cols = _SPEC_SHAPE.get(key, (1, ()))[1]
    if row1 and _is_column_name_line(row1, int_cols):
        # A plain column-name line (``chrom start end``) heads the data: it is the header, not a row.
        return TableLayout(delim, [c.strip() for c in row1], "header", header_row=True, spec=key, valid=valid,
                           header_width=width)
    if comment is not None and width:
        cnames = [c.strip() for c in next(_spec_reader(iter([comment.lstrip("#")]), delim), [])]
        if len(cnames) == width and all(cnames):
            return TableLayout(delim, cnames, "comment", header_row=False, spec=key, valid=valid,
                               header_width=width)
    names = _spec_names(key, galaxy_ext)[:width] if width else _spec_names(key, galaxy_ext)
    names += [f"column_{i + 1}" for i in range(len(names), width)]
    return TableLayout(delim, names, "spec", header_row=False, spec=key, valid=valid, header_width=width)


def _iter_table(path: str, layout: Optional[TableLayout] = None) -> Iterator[List[str]]:
    """THE delimited-table parse shared by the profiler and the paged rows reader:
    yields the column names first (see :func:`_table_layout`), then every non-blank data row
    as-is. Leading comment/blank lines are skipped; with a header row it is consumed as names."""
    lay = layout or _table_layout(path)
    yield list(lay.names)
    with _open_text(path) as f:
        if lay.spec:
            first = True
            for row in _spec_reader(_spec_lines(f), lay.delim):
                if first and lay.header_row and lay.names_source == "header":
                    first = False
                    continue
                first = False
                if row and not all(c == "" for c in row):
                    yield row
            return
        for _ in range(lay.skip_lines):
            f.readline()
        seen_first = False
        for row in csv.reader(_nul_guard(f), delimiter=lay.delim):
            if not row or all(c == "" for c in row):
                continue
            if not seen_first:
                seen_first = True
                if lay.header_row:
                    continue
            yield row


# Cells held in memory for the table statistics. A wide matrix (20,000 genes × 1,000 samples)
# is profiled on its first rows that fit, never loaded whole (rows held ≈ cap / width).
MAX_PROFILE_CELLS = 2_000_000


def _read_table(
    path: str, max_rows: int = MAX_TABLE_ROWS, layout: Optional[TableLayout] = None
) -> Tuple[List[str], List[List[str]], int]:
    """(header, first rows held for statistics, TRUE total data-row count). At most ``max_rows``
    rows and MAX_PROFILE_CELLS cells are held; the rest are only counted."""
    it = _iter_table(path, layout)
    header = next(it, [])
    rows: List[List[str]] = []
    total = 0
    cells = 0
    full = False
    for row in it:
        total += 1
        if not full:
            if len(rows) < max_rows and (cells + len(row) <= MAX_PROFILE_CELLS or not rows):
                rows.append(row)
                cells += len(row)
            else:
                full = True
    return header, rows, total


def _preview_cell(c: Any) -> str:
    t = str(c)
    return t if len(t) <= MAX_PREVIEW_CELL_CHARS else t[:MAX_PREVIEW_CELL_CHARS - 1] + "…"


def _jsonl_cell(v: Any) -> str:
    if v is None:
        return ""
    if isinstance(v, str):
        return v
    if isinstance(v, (list, dict)):
        return json.dumps(v, ensure_ascii=False, separators=(",", ":"))
    return str(v)


def _iter_jsonl(path: str, stats: Dict[str, int]) -> Iterator[Dict[str, Any]]:
    """THE JSON Lines parse shared by the profiler and the paged rows reader: one dict per
    record (a non-object line becomes {"value": …}); unparseable lines are skipped and
    counted in ``stats["bad"]`` (the profile reports them). Text is read as UTF-8 with any
    BOM removed, so a BOM never costs the first record."""
    stats.setdefault("bad", 0)
    with _open_text(path) as f:
        for line in _nul_guard(f):
            line = line.strip().lstrip("\ufeff")
            if not line:
                continue
            try:
                obj = json.loads(line)
            except ValueError:
                stats["bad"] += 1
                continue
            if not isinstance(obj, dict):
                obj = {"value": obj}
            yield obj


def _read_jsonl(path: str, max_rows: int = MAX_TABLE_ROWS) -> Tuple[List[str], List[List[str]], int]:
    """JSON Lines → (header, first ``max_rows`` rows, TRUE record count): one row per
    record, columns = top-level keys (first-seen order, over ALL records), nested
    lists/objects as compact JSON. The count of skipped lines is in ``_read_jsonl.last_bad``."""
    keys: List[str] = []
    seen = set()
    records: List[Dict[str, Any]] = []
    stats: Dict[str, int] = {}
    total = 0
    for obj in _iter_jsonl(path, stats):
        for k in obj:
            if k not in seen:
                seen.add(k)
                keys.append(str(k))
        total += 1
        if len(records) < max_rows:
            records.append(obj)
    _JSONL_BAD.n = stats.get("bad", 0)
    if stats.get("bad") and not total:
        raise ValueError(f"no valid JSON lines ({stats['bad']} unparseable)")
    return keys, [[_jsonl_cell(r.get(k)) for k in keys] for r in records], total


_JSONL_BAD = threading.local()


# Hard cap on one page of the paged rows reader (the UI asks for ~200 at a time).
MAX_ROWS_PAGE = 1000
# Version of how read_rows turns bytes into columns + rows. Cached page metadata (columns, total)
# written under another version is not reused. Bump when the parse changes what a row is.
READ_ROWS_VERSION = "2026-11-12.r2-encoding-jsonl"


def read_rows(
    path: str,
    offset: int = 0,
    limit: int = 200,
    *,
    known: Optional[Dict[str, Any]] = None,
    context: Optional[Dict[str, Any]] = None,
    name: Optional[str] = None,
) -> Dict[str, Any]:
    """One page of a table-like file's FULL rows, parsed exactly as the profiler parses it.

    Returns ``{kind, viewKind, tabular, columns, rows, offset, limit, totalRows}`` (tables also
    carry ``headerRow`` — whether the first record after ``skipLines`` leading comment/blank
    lines is a header, which the edit route needs to number data rows — and ``namesSource``:
    header | comment | spec | generated; ``delimiter`` — the exact field separator, "\\t" "," ";"
    "|" or " " (None for JSON Lines); ``decimal`` — "," for decimal-comma numbers, else "."; and
    ``encoding`` — the codec the bytes were read with, which an edit must write back in). An
    empty or blank file is ``{viewKind: "unknown", tabular: False, reason: "empty"}``, as its
    profile is blocked. ``tabular`` is True exactly when the profile's
    ``viewKind`` is table / records / intervals / annotation: the SAME content-first decision
    (:func:`decide`), so the panel never pages rows of a SAM, PDB or FASTQ. ``known`` is a
    previously returned ``{"columns", "totalRows"}`` for the same bytes: with it the read stops
    once the page is filled. Never raises for unreadable content (``reason`` says why).
    """
    _reset_damage()
    display = name or os.path.basename(path or "")
    try:
        empty = _empty_content(path, os.path.getsize(path))
        if empty:
            # The profile blocks an empty / blank file with view "unknown": no rows to page either.
            return {"kind": "unknown", "viewKind": "unknown", "tabular": False, "reason": "empty", "code": empty}
        d = decide(path, display)
    except UnreadableContent:
        return {"kind": "unknown", "viewKind": "unknown", "tabular": False, "reason": "unreadable"}
    except Exception as exc:  # noqa: BLE001 — a rows request must never 500 on bad content
        log.warning("[perception] rows decision failed for %s: %s", path, exc)
        return {"kind": "unknown", "viewKind": "unknown", "tabular": False, "reason": "unreadable"}
    if d.view not in TABULAR_VIEWS:
        return {"kind": d.kind, "viewKind": d.view, "tabular": False}
    try:
        out = _read_rows(path, d, offset, limit, known=known, context=context)
    except Exception as exc:  # noqa: BLE001
        log.warning("[perception] rows read failed for %s: %s", path, exc)
        return {"kind": d.kind, "viewKind": d.view, "tabular": False, "reason": "unreadable"}
    if _damage()["corrupt"]:
        return {"kind": d.kind, "viewKind": "unknown", "tabular": False, "reason": "unreadable"}
    return out


def _read_rows(
    path: str,
    d: "Decision",
    offset: int = 0,
    limit: int = 200,
    *,
    known: Optional[Dict[str, Any]] = None,
    context: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    kind = d.kind
    layout: Optional[TableLayout] = None
    if kind == "table":
        member = _context_tenx(context)
        layout = _tenx_layout(path, member["role"]) if member and member["role"] in _tenx_columns() else d.layout
        if layout is None or not layout.valid:
            return {"kind": kind, "viewKind": d.view, "tabular": False, "reason": "spec_mismatch"}
    offset = max(0, int(offset))
    limit = max(1, min(int(limit), MAX_ROWS_PAGE))
    end = offset + limit
    total = 0
    out: Dict[str, Any] = {"kind": kind, "viewKind": d.view, "tabular": True, "offset": offset, "limit": limit,
                           # The codec the bytes were read with (utf-8 | utf-16[-le|-be] | gb18030 |
                           # windows-1252 | latin-1): an edit must write the file back in it.
                           "encoding": ENCODING_NAMES.get(d.encoding or "utf-8-sig", d.encoding),
                           # The exact field separator ("\t", ",", ";", "|", " "); None for JSON Lines.
                           "delimiter": None}
    if kind == "table":
        assert layout is not None
        out["delimiter"] = layout.delim
        # "," when numbers are written with a decimal comma ("1,5" in a semicolon file), else ".".
        out["decimal"] = layout.decimal
        out["headerRow"] = layout.header_row
        out["namesSource"] = layout.names_source
        out["skipLines"] = layout.skip_lines
        it = _iter_table(path, layout)
        columns = next(it, [])
        page: List[List[str]] = []
        for row in it:
            if offset <= total < end:
                page.append(list(row))
            total += 1
            if known and total >= end:
                break
        out["columns"] = columns
        out["rows"] = page
    else:
        columns = list(known["columns"]) if known else []
        seen = set(columns)
        stats: Dict[str, int] = {}
        recs: List[Dict[str, Any]] = []
        for obj in _iter_jsonl(path, stats):
            if not known:
                for k in obj:
                    if k not in seen:
                        seen.add(k)
                        columns.append(str(k))
            if offset <= total < end:
                recs.append(obj)
            total += 1
            if known and total >= end:
                break
        out["columns"] = columns
        out["rows"] = [[_jsonl_cell(r.get(k)) for k in columns] for r in recs]
        if not known:
            out["skippedLines"] = stats.get("bad", 0)
    out["totalRows"] = int(known["totalRows"]) if known else total
    return out


def _column(rows: Sequence[Sequence[str]], idx: int) -> List[str]:
    out = []
    for r in rows:
        out.append(r[idx].strip() if idx < len(r) else "")
    return out


def _name_tokens(name: str) -> List[str]:
    """Whole tokens of a column name: split on non-alphanumerics and camelCase
    ("patientID" → patient, id; "gene_symbol" → gene, symbol; "weight_kg" → weight, kg)."""
    return [t.lower() for t in re.findall(r"[A-Z]+(?![a-z])|[A-Z]?[a-z]+|\d+", str(name))]


def _ranked_cols(header: Sequence[str], tokens: Sequence[str], exclude: Sequence[int] = ()) -> List[int]:
    """Columns whose name has one of ``tokens`` as a WHOLE token, most token-like first (token
    rank, then column order). Never substring matches ('id' is not in 'width')."""
    ranked: List[Tuple[int, int]] = []
    for i, h in enumerate(header):
        if i in exclude:
            continue
        toks = set(_name_tokens(h))
        ranks = [r for r, tok in enumerate(tokens) if tok in toks]
        if ranks:
            ranked.append((min(ranks), i))
    return [i for _r, i in sorted(ranked)]


def _find_col(header: Sequence[str], tokens: Sequence[str]) -> Optional[int]:
    """The most token-like column (see :func:`_ranked_cols`), or None."""
    cols = _ranked_cols(header, tokens)
    return cols[0] if cols else None


# A numeric column is a class label only with at most this many distinct integer values
# (0/1, grades 1–5); a measurement (age, weight, a coordinate) is not a class target.
MAX_NUMERIC_LABEL_CLASSES = 10


def _label_like(values: Sequence[str], n_rows: int, decimal: str = ".") -> bool:
    """Whether a column's values are class labels: 2…max(20, 10% of rows) distinct values, and
    — when numeric — few distinct integers rather than a continuous measurement."""
    present = [v for v in values if v != ""]
    distinct = set(present)
    if not (2 <= len(distinct) <= max(20, int(0.1 * n_rows))):
        return False
    numeric = [v for v in distinct if _is_number(v, decimal)]
    if numeric and len(numeric) / len(distinct) >= _NUMERIC_COL_FRAC:
        if any(not _to_float(v, decimal).is_integer() for v in numeric):
            return False
        return len(distinct) <= MAX_NUMERIC_LABEL_CLASSES
    return True


def _named(cols: Sequence[str]) -> List[str]:
    return [str(c) for c in cols[:_MAX_NAMED_COLUMNS]]


# A column is a "table column" when at least this share of its values are lists of lists.
NESTED_TABLE_MIN_FRAC = 0.5
# Row-cap signature (extraction truncation, e.g. an extractor that kept t[1:8]): at least this
# share of the tables sit exactly at the maximum row count, the maximum is at least
# NESTED_ROW_CAP_DOMINANCE times as common as any other size (so a 4/7/4/7 mix of two real
# table sizes is not "cut off"), and at least NESTED_ROW_CAP_MIN_TABLES tables were seen.
NESTED_ROW_CAP_FRAC = 0.6
NESTED_ROW_CAP_DOMINANCE = 2.0
NESTED_ROW_CAP_MIN_TABLES = 5
NESTED_BLANK_NOTE_FRAC = 0.3


def _median(xs: Sequence[int]) -> Any:
    """The median of sorted ``xs``: the middle value, or the mean of the two middle values for an
    even count ([4, 4, 4, 7, 7, 7] → 5.5) — an int when it is whole."""
    n = len(xs)
    if not n:
        return 0
    if n % 2:
        return xs[n // 2]
    m = (xs[n // 2 - 1] + xs[n // 2]) / 2
    return int(m) if float(m).is_integer() else m


def _row_cap_signature(nrows: Sequence[int]) -> bool:
    """Whether sorted table sizes ``nrows`` show a row CAP: enough tables, a maximum of at least 3
    rows that not every table shares, ≥ NESTED_ROW_CAP_FRAC of them at the maximum, and the
    maximum ≥ NESTED_ROW_CAP_DOMINANCE × as common as the next most common size (not bimodal)."""
    if len(nrows) < NESTED_ROW_CAP_MIN_TABLES or nrows[-1] < 3 or nrows[0] == nrows[-1]:
        return False
    counts = Counter(nrows)
    at_max = counts[nrows[-1]]
    other = max((c for size, c in counts.items() if size != nrows[-1]), default=0)
    return at_max / len(nrows) >= NESTED_ROW_CAP_FRAC and at_max >= NESTED_ROW_CAP_DOMINANCE * other


def _nested_table_findings(p: "DataProfile", header: Sequence[str], rows: Sequence[Sequence[str]]) -> int:
    """JSONL columns whose values are tables (lists of lists): size summary, a likely row cap, and the
    blank-cell share. Generic — no field names. Returns the number of embedded tables found.
    (epar_study_tables.jsonl, 2026-11-11: 69% of 2,281 tables had exactly 7 rows because the extractor
    kept t[1:8]; nothing reported it.)"""
    found = 0
    for j, name in enumerate(header):
        mats: List[List[Any]] = []
        present = 0
        for r in rows:
            c = r[j] if j < len(r) else ""
            if not c:
                continue
            present += 1
            if c[0] != "[":
                continue
            try:
                v = json.loads(c)
            except ValueError:
                continue
            if isinstance(v, list) and v and all(isinstance(x, list) for x in v):
                mats.append(v)
        if not present or len(mats) / present < NESTED_TABLE_MIN_FRAC:
            continue
        found += len(mats)
        nrows = sorted(len(m) for m in mats)
        ncols = sorted(max((len(x) for x in m), default=0) for m in mats)
        med = _median
        emit(p, "note", "nested_tables",
             f"Column {name!r}: {len(mats):,} embedded tables, median {med(nrows)} rows × {med(ncols)} columns "
             f"(largest {nrows[-1]} rows).",
             column=str(name), tables=len(mats), median_rows=med(nrows), median_cols=med(ncols), max_rows=nrows[-1])
        if _row_cap_signature(nrows):
            at_max = sum(1 for n in nrows if n == nrows[-1])
            pct = int(round(100 * at_max / len(nrows)))
            emit(p, "signal", "nested_row_cap",
                 f"{pct}% of the tables in column {name!r} have exactly {nrows[-1]} rows, the maximum: they were "
                 f"probably cut off when extracted. Check the extraction before analysing them.",
                 "watch", column=str(name), pct=pct, max_rows=nrows[-1], tables=len(mats))
        cells = [x for m in mats for row in m for x in row]
        if cells:
            blank = sum(1 for x in cells if x is None or not str(x).strip()) / len(cells)
            if blank >= NESTED_BLANK_NOTE_FRAC:
                emit(p, "note", "nested_blank_cells",
                     f"{int(round(100 * blank))}% of the cells in the tables of column {name!r} are blank — typical of merged "
                     f"or multi-line cells in extracted tables; join continuation rows before analysis.",
                     column=str(name), pct=int(round(100 * blank)))
    return found


def _profile_table(path: str, reader=None, layout: Optional[TableLayout] = None) -> DataProfile:
    p = DataProfile()
    if reader is not None:
        _JSONL_BAD.n = 0
        header, rows, total = reader(path)
        skipped = int(getattr(_JSONL_BAD, "n", 0) or 0)
        if skipped:
            emit(p, "note", "jsonl_skipped_lines", "", "watch", count=skipped)
    else:
        layout = layout or _table_layout(path)
        header, rows, total = _read_table(path, layout=layout)
    n_rows = len(rows)  # rows held for statistics (≤ MAX_TABLE_ROWS / MAX_PROFILE_CELLS)
    dec = layout.decimal if layout is not None else "."
    if dec == ",":
        p.decimal = ","
    n_cols = len(header)
    p.rows = total
    p.cols = n_cols
    if total > n_rows:
        p.profiled_rows = n_rows
    if layout is not None and layout.skip_lines and not layout.spec:
        comments = _leading_comment_count(path, layout.skip_lines)
        if comments:
            emit(p, "note", "comment_lines_skipped", "", count=comments)

    if n_cols == 0:
        if total == 0 and _blank_only(path):
            return blocked_profile("blank_content", "")
        p.quality = "blocked"
        emit(p, "note", "no_columns", "", "blocked")
        return p
    if layout is not None and layout.names_source in ("header", "comment"):
        _duplicate_columns_finding(p, header)
    if n_rows == 0:
        # A readable but EMPTY table: the columns are shown (so the Preview/Columns views show the
        # real header), and the missing data is something to check, not "Good".
        p.columns = [str(c) for c in header[:MAX_PREVIEW_COLS]]
        p.sample_rows = []
        if layout is not None and not layout.header_row:
            _column_names_finding(p, layout)
            emit(p, "note", "table_summary", "", rows=total, cols=n_cols)
        else:
            emit(p, "note", "header_only", "", "watch")
        return p

    # Small tabular sample for the Preview tab (columns + first rows), capped.
    p.columns = [str(c) for c in header[:MAX_PREVIEW_COLS]]
    p.sample_rows = [
        [_preview_cell(c) for c in r[:MAX_PREVIEW_COLS]] for r in rows[:MAX_PREVIEW_ROWS]
    ]
    if layout is not None:
        _column_names_finding(p, layout)
        _ragged_finding(p, rows, layout)
    if layout is not None and layout.spec:
        # A spec format (BED, GTF, SMILES, …): its columns are defined by the format, so the
        # classification checks (label / leakage / balance) and placeholder-column statistics
        # (BED score 0, strand ".") do not apply. Format findings are added by the caller. The
        # per-column statistics are kept, with the format's coordinate / descriptor columns as
        # ``annotation`` so they are never a plot default or a feature.
        p.column_stats = _column_stats(header, rows, dec, _spec_annotation_columns(layout.spec, header))
        _set_duplicate_rows(p, rows)
        emit(p, "note", "table_summary", "", rows=total, cols=n_cols)
        if p.profiled_rows is not None:
            emit(p, "note", "profiled_subset", "", profiled=n_rows, rows=total)
        return p

    annotation = set(layout.annotation_columns()) if layout is not None else set()
    annotation |= _genomic_coordinate_columns(header)
    if n_rows < MIN_ROWS_FOR_CHECKS:
        # One data row: "near-constant" / "high missingness" / class balance say nothing. The
        # column types and roles still describe it (a one-record JSON Lines extract's "page").
        p.column_stats = _column_stats(header, rows, dec, annotation)
        emit(p, "note", "few_data_rows", "", "watch", rows=n_rows)
        _set_duplicate_rows(p, rows)
        emit(p, "note", "table_summary", "", rows=total, cols=n_cols)
        return p

    # --- per-column types + statistics (decimal-mark aware), and the columns' roles ---
    p.column_stats = _column_stats(header, rows, dec, annotation)
    roles = {c["name"]: c.get("role") for c in p.column_stats}

    # --- constant / high-missingness columns (numeric-first signal) ---
    # Annotation columns of a recognised layout (featureCounts' Chr / Strand / Length …) are
    # constant or sparse BY DESIGN on many inputs (one chromosome, one strand): not a finding.
    near_constant: List[str] = []
    expected_constant: List[str] = []
    high_missing: List[str] = []
    for j in range(n_cols):
        if header[j] in annotation:
            continue
        col = _column(rows, j)
        non_missing = [v for v in col if v not in ("", "NA", "NaN", "nan", "null", "None")]
        missing_frac = 1.0 - (len(non_missing) / n_rows) if n_rows else 0.0
        if missing_frac >= HIGH_MISSING_FRAC:
            high_missing.append(header[j])
        if non_missing:
            top = Counter(non_missing).most_common(1)[0][1]
            if top / len(non_missing) >= NEAR_CONSTANT_FRAC:
                if _near_constant_expected(col, n_rows, records=reader is not None):
                    expected_constant.append(header[j])
                else:
                    near_constant.append(header[j])
    if near_constant:
        emit(p, "signal", "near_constant", "", "watch", count=len(near_constant), columns=_named(near_constant),
             pct=int(NEAR_CONSTANT_FRAC * 100))
    elif expected_constant:
        # Stated once, as information: below the row floor, or per-record provenance.
        emit(p, "signal", "near_constant", "", count=len(expected_constant), columns=_named(expected_constant),
             pct=int(NEAR_CONSTANT_FRAC * 100),
             expected="few_rows" if n_rows < NEAR_CONSTANT_MIN_ROWS else "record_metadata")
    if high_missing:
        emit(p, "signal", "high_missing", "", "watch", count=len(high_missing), columns=_named(high_missing),
             pct=int(HIGH_MISSING_FRAC * 100))

    # --- locate the label column: the most label-like name whose values ARE class labels ---
    candidates = [c for c in _ranked_cols(header, _LABEL_NAME_TOKENS) if header[c] not in annotation]
    label_idx: Optional[int] = None
    for c in candidates:
        if _label_like(_column(rows, c), n_rows, dec):
            label_idx = c
            break
    confident = False
    if label_idx is not None:
        confident, why = _modelling_label(header, label_idx, n_rows, roles)
        p.label = {"column": str(header[label_idx]), "confident": confident}
        if confident:
            for cs in p.column_stats:
                if cs["name"] == header[label_idx]:
                    cs["role"] = "label"
        elif why == "few_rows":
            emit(p, "note", "label_few_rows", "", column=str(header[label_idx]), rows=n_rows,
                 min_rows=MODEL_MIN_ROWS)
        else:
            emit(p, "note", "label_no_features", "", column=str(header[label_idx]))
        if not confident:
            _batch_confound(p, header, rows, label_idx, _column(rows, label_idx))
    if confident:
        assert label_idx is not None
        label_col = _column(rows, label_idx)
        counts = Counter(v for v in label_col if v != "")
        total_labelled = sum(counts.values())
        balance = [(lbl, cnt / total_labelled) for lbl, cnt in counts.most_common()]
        p.class_balance = [(lbl, round(frac, 4)) for lbl, frac in balance]

        # normalize near-duplicate label spellings for a note
        norm_map: Dict[str, List[str]] = {}
        for lbl in counts:
            norm_map.setdefault(lbl.strip().lower(), []).append(lbl)
        dup_spellings = [v for v in norm_map.values() if len(v) > 1]
        if dup_spellings:
            example = sorted(dup_spellings[0])
            emit(p, "note", "label_spellings", "", "watch", a=example[0], b=example[1])

        minority_frac = min(frac for _, frac in balance)
        majority_frac = max(frac for _, frac in balance)
        imbalanced = minority_frac < IMBALANCE_MINORITY_RATIO * majority_frac
        if imbalanced:
            minority_label = min(balance, key=lambda kv: kv[1])[0]
            emit(p, "note", "minority_class", "", "watch", label=minority_label,
                 pct=int(round(minority_frac * 100)))

        # --- leakage checks (need a label) ---
        _detect_leakage(p, header, rows, label_idx, label_col)

        # --- effective N --- (the minority-class bound applies only under the imbalance rule
        # above, so "strong imbalance" is never said of a 65/35 label)
        eff_n, reason, unique = _effective_n(rows, label_col, balance if imbalanced else [])
        p.effective_n = eff_n
        p.effective_n_reason = reason
        p.duplicate_rows = n_rows - unique
        if eff_n < 0.75 * n_rows:
            if reason == "imbalance":
                emit(p, "note", "effective_n_imbalance", "", "watch", n=eff_n, rows=n_rows)
            else:
                emit(p, "note", "effective_n_dedup", "", "watch", n=eff_n, rows=n_rows,
                     duplicates=n_rows - unique)
    else:
        if label_idx is None:
            text_candidates = [c for c in candidates if not _mostly_numeric(_column(rows, c), dec)]
            if text_candidates:
                c = text_candidates[0]
                emit(p, "signal", "label_free_text", "", column=header[c],
                     distinct=len(set(v for v in _column(rows, c) if v != "")))
        _set_duplicate_rows(p, rows)

    # --- nested tables in JSON Lines (a column of lists-of-lists, e.g. extracted PDF tables) ---
    if reader is _read_jsonl:
        n_tables = _nested_table_findings(p, header, rows)
        if n_tables:
            p.stats_map["tables"] = n_tables

    # "No issues" only when nothing at watch level was found in ANY section, and it names only
    # the checks that actually ran. The clean summaries say no column is constant, so a table
    # with an (expected, info-level) near-constant column closes with the plain summary.
    # A wide count / expression matrix (features × samples: the samples are COLUMNS) has no group
    # column by construction, so "no group column was found" is not said of it; sample columns
    # whose names form groups (ctrl_1, ctrl_2, treat_1 …) are stated instead.
    sample_cols = _matrix_sample_columns(header, p.column_stats, layout) if label_idx is None else None
    if sample_cols is not None:
        groups = _sample_name_groups(sample_cols)
        if groups:
            emit(p, "note", "sample_groups_from_names", "", groups=groups)
    if any(f["level"] in ("watch", "blocked") or f["code"] == "near_constant" for f in p.findings):
        emit(p, "note", "table_summary", "", rows=total, cols=n_cols)
    elif confident:
        emit(p, "note", "table_clean", "", rows=total, cols=n_cols)
    elif label_idx is not None or sample_cols is not None:
        emit(p, "note", "table_clean_label_unchecked", "", rows=total, cols=n_cols)
    else:
        emit(p, "note", "table_clean_unlabelled", "", rows=total, cols=n_cols)
    if p.profiled_rows is not None:
        emit(p, "note", "profiled_subset", "", profiled=n_rows, rows=total)
    return p


# Whole name tokens of a FEATURE-identifier first column of a wide matrix (rows are genes,
# transcripts, guides, peaks, … and the samples are columns).
_FEATURE_ID_NAME_TOKENS = frozenset({
    "gene", "genes", "geneid", "symbol", "ensembl", "transcript", "transcripts", "tx", "feature",
    "features", "probe", "probes", "probeset", "sgrna", "guide", "protein", "proteins", "peptide",
    "metabolite", "otu", "asv", "taxon", "taxa", "cpg", "peak", "peaks", "region", "locus",
})
# File suffixes a tool leaves on sample column names (featureCounts: S1.bam).
_SAMPLE_NAME_SUFFIX = re.compile(r"\.(?:sorted\.)?(?:bam|sam|cram|bw|bigwig|bed|fastq|fq|txt|tsv|csv|counts?)$", re.I)
# A sample name = group prefix (with a letter) + replicate number; a separated replicate word
# before the number ("ctrl_rep1", "WT-r2", "KO_Rep_3") is not part of the group's name.
_SAMPLE_NAME_GROUP = re.compile(r"^(.*?)(\d+)$")
# A plate well position at the end of a name: one row letter A–P (96/384-well) standing alone
# (start or after a non-letter, so "KO1" is not well O1) + column 1–24.
_PLATE_WELL = re.compile(r"(?:^|[^A-Za-z])[A-Pa-p](?:0?[1-9]|1[0-9]|2[0-4])$")
_SAMPLE_REPLICATE_WORD = re.compile(r"(?:[ _.\-]+(?:rep(?:licate)?|r)|(?<=[a-z0-9])Rep)[ _.\-]*$", re.I)


def _matrix_sample_columns(header: Sequence[str], column_stats: Optional[Sequence[Dict[str, Any]]],
                           layout: Optional["TableLayout"]) -> Optional[List[str]]:
    """The sample columns when the table is a WIDE count / expression matrix, else None.

    A matrix is (a) a recognised count / quantification layout (featureCounts, MAGeCK — the
    columns after the lead are the samples; Salmon / RSEM — one sample per file, no sample
    columns), or (b) a table whose first column is a non-numeric feature identifier and every
    other column is numeric (at least two), where either the first column's name is a feature
    word (gene_id, Geneid, transcript, sgRNA, … or blank, as R writes row names) or the numeric
    columns' names form sample groups (ctrl_1, ctrl_2, treat_1). A samples × measurements table
    (sample, weight_g, conc_mg_ml) is neither, and keeps its group-column note."""
    if layout is not None and layout.recognised in KNOWN_TABLE_LAYOUTS:
        lead = KNOWN_TABLE_LAYOUTS[layout.recognised]["lead"]
        return [str(h) for h in header[len(lead):]] if KNOWN_TABLE_LAYOUTS[layout.recognised]["min_values"] else []
    # (columnStats cover the first MAX_COLUMN_STATS columns: a wider matrix is judged on those.)
    if layout is None or not column_stats or len(column_stats) < 3:
        return None
    first, rest = column_stats[0], column_stats[1:]
    if first["type"] not in ("text", "categorical") or first["distinct"] != first["present"]:
        return None
    if not all(c["type"] == "numeric" for c in rest):
        return None
    names = [str(h) for h in header[1:]]
    first_name = str(header[0]).strip()
    if not first_name or set(_name_tokens(first_name)) & _FEATURE_ID_NAME_TOKENS or _sample_name_groups(names):
        return names
    return None


def _sample_name_groups(names: Sequence[str]) -> Optional[List[Dict[str, Any]]]:
    """Groups formed by sample column names — ``[{name, n}]`` in first-seen order — when EVERY
    name is a group prefix + replicate number (ctrl_1, ctrl_2, treat_1; WT_1, KO_2; S1.bam's file
    suffix is ignored) and there are at least two groups; else None (S1, S2 … is one group)."""
    if len(names) < 2:
        return None
    order: List[str] = []
    counts: Dict[str, int] = {}
    for raw in names:
        m = _SAMPLE_NAME_GROUP.match(_SAMPLE_NAME_SUFFIX.sub("", str(raw).strip()))
        g = _SAMPLE_REPLICATE_WORD.sub("", m.group(1)).rstrip(" _.-") if m else ""
        if not re.search(r"[A-Za-z]", g):
            return None
        if g not in counts:
            order.append(g)
            counts[g] = 0
        counts[g] += 1
    if len(order) < 2:
        return None
    if all(_PLATE_WELL.search(_SAMPLE_NAME_SUFFIX.sub("", str(raw).strip())) for raw in names):
        return None  # A01, B12, sample_C3 …: plate positions, not groups
    return [{"name": g, "n": counts[g]} for g in order]


def _near_constant_expected(col: Sequence[str], n_rows: int, *, records: bool) -> bool:
    """Whether a near-constant column is EXPECTED (info, not Watch) — the rule documented at
    NEAR_CONSTANT_MIN_ROWS: fewer than that many rows, or, in a record file (JSON Lines), the
    same scalar in every record (per-record provenance; a nested list/object is data, not a stamp)."""
    if n_rows < NEAR_CONSTANT_MIN_ROWS:
        return True
    if not records:
        return False
    values = set(col)
    if len(values) != 1:
        return False
    v = next(iter(values)).strip()
    return bool(v) and v.lower() not in _MISSING_TOKENS and not v.startswith(("[", "{"))


# A label column makes the table a MODELLING table — class balance, effective N and leakage are
# computed — only with at least this many rows: below it one row moves a class share by more
# than 5 points and a leave-one-out accuracy of 0.98 cannot be told from "no error at all", so
# the numbers describe the handful of rows, not a population (a 4-sample sheet's "condition" is
# a design factor, not a target to balance). The rule is documented in _modelling_label.
MODEL_MIN_ROWS = 20

# Whole name tokens that mark an IDENTIFIER column (when its values are integers or all distinct):
# a record / page / row number or an accession is never a feature, a class or a plot axis.
_IDENTIFIER_NAME_TOKENS = frozenset({
    "id", "ids", "uuid", "barcode", "accession", "index", "idx", "page", "row", "line", "record",
    "sample", "name", "serial",
})
MAX_COLUMN_STATS = 2000
# Name tokens of a POSITION column (where a record sits in its source), and the words that may
# accompany them ("page_no", "row_index", "line_number"). A name made only of these words, with
# at least one position word, is an identifier for any integer values (see _is_identifier).
_POSITION_ONLY_TOKENS = frozenset({"page", "row", "line", "record", "index", "idx", "serial"})
_POSITION_NAME_TOKENS = _POSITION_ONLY_TOKENS | frozenset({"no", "num", "number", "nr", "n", "pos"})


def _modelling_label(header: Sequence[str], label_idx: int, n_rows: int,
                     roles: Dict[str, Optional[str]]) -> Tuple[bool, str]:
    """Whether the label column at ``label_idx`` is a CONFIDENT modelling target → (confident,
    reason when not: "few_rows" | "no_features").

    The rule: (1) the column's NAME is a label word and its VALUES are class labels (the caller
    found it so: _LABEL_NAME_TOKENS + _label_like); (2) the table has at least MODEL_MIN_ROWS rows;
    (3) at least one FEATURE column besides it — a column that is not an identifier (see
    _column_stats), not an annotation column of a recognised layout, not a batch / grouping /
    split column (_BATCH_NAME_TOKENS / _SPLIT_NAME_TOKENS) and not constant. Without (2) the
    statistics describe a handful of rows; without (3) there is nothing to model or to leak.
    """
    if n_rows < MODEL_MIN_ROWS:
        return False, "few_rows"
    grouping = set(_ranked_cols(header, _BATCH_NAME_TOKENS)) | set(_ranked_cols(header, _SPLIT_NAME_TOKENS))
    for j, name in enumerate(header):
        if j == label_idx or j in grouping:
            continue
        if roles.get(name) in ("identifier", "annotation", "constant"):
            continue
        return True, ""
    return False, "no_features"


def _column_stats(header: Sequence[str], rows: Sequence[Sequence[str]], decimal: str,
                  annotation: Optional[set] = None) -> List[Dict[str, Any]]:
    """Per column over the profiled rows: ``type`` (numeric | categorical | text | empty — numeric
    when every present value parses as a number in the table's decimal mark, so "12,5" in a
    semicolon file is numeric), ``present`` / ``missing`` / ``distinct`` counts, ``min`` / ``max`` /
    ``mean`` for numeric columns, and ``role`` when the column is not an ordinary value column:

    * "annotation" — a declared annotation column of a recognised layout (featureCounts Chr …);
    * "identifier" — its name has an identifier word as a whole token (id, page, row, sample, …)
      AND its values are all distinct ("sample_id" S1, S2, …) or a non-decreasing run of integers
      in file order ("page" 30, 30, 31, … — two tables on one page). The name is required: an
      all-distinct column without one (SMILES, a sequence) is a feature, and a count column whose
      name happens to hold "sample" (sample_count 7, 3, 9) is not ordered, so it stays a value;
    * "constant" — a single distinct value;
    * "measurement" — any other numeric column: a measured / counted value (featureCounts' sample
      count columns, an expression or assay value) — the columns a plot defaults to. A confident
      class label is re-marked "label" by the caller.

    Every numeric column therefore carries a role; a categorical / text column without one is an
    ordinary descriptive column.
    """
    annotation = annotation or set()
    out: List[Dict[str, Any]] = []
    for j, name in enumerate(list(header)[:MAX_COLUMN_STATS]):
        cells = [r[j].strip() if j < len(r) else "" for r in rows]
        present = [v for v in cells if v and v.lower() not in _MISSING_TOKENS]
        distinct = len(set(present))
        nums: List[float] = []
        numeric = bool(present)
        try:
            nums = [float(v) for v in present] if decimal == "." else [_to_float(v, decimal) for v in present]
        except ValueError:
            numeric, nums = False, []
        if not present:
            typ = "empty"
        elif numeric:
            typ = "numeric"
        elif distinct <= max(2, -(-len(present) // 2)):
            typ = "categorical"
        else:
            typ = "text"
        cs: Dict[str, Any] = {"name": str(name), "type": typ, "present": len(present),
                              "missing": len(rows) - len(present), "distinct": distinct}
        if typ == "numeric":
            finite = [x for x in nums if x == x and x not in (float("inf"), float("-inf"))]
            if finite:
                cs.update(min=_num(min(finite)), max=_num(max(finite)), mean=_num(round(sum(finite) / len(finite), 6)))
        role: Optional[str] = None
        if str(name) in annotation:
            role = "annotation"
        elif present and distinct == 1 and len(present) > 1:
            role = "constant"
        elif present and _is_identifier(str(name), present, distinct, typ, nums):
            role = "identifier"
        elif typ == "numeric":
            role = "measurement"
        if role:
            cs["role"] = role
        out.append(cs)
    return out


# Genomic coordinate columns of a BED-like / featureCounts-like table that is not a recognised
# layout (a CSV of chrom,start,end,score,gene; a featureCounts table without its exact header):
# matched on the WHOLE column name, case-insensitively. They are coordinates, not measurements —
# never a plot default, a feature or a class — and constant by design on many inputs (one
# chromosome, one strand). The rule applies only when the table has BOTH a chromosome column
# and a position column, so a "length" or "end" column of an unrelated table stays a value.
_COORD_CHROM_NAMES = frozenset({"chr", "chrom", "chromosome", "seqname", "seqnames", "seqid", "contig",
                                "#chr", "#chrom", "chrom_name"})
_COORD_POS_NAMES = frozenset({"start", "end", "stop", "pos", "position", "begin", "chromstart", "chromend",
                              "start_position", "end_position", "txstart", "txend", "thickstart", "thickend"})
_COORD_EXTRA_NAMES = frozenset({"strand", "length", "width"})


def _genomic_coordinate_columns(header: Sequence[str]) -> set:
    """The names in ``header`` that are genomic coordinates by the rule above (else empty)."""
    low = {str(h): str(h).strip().lower() for h in header}
    if not any(v in _COORD_CHROM_NAMES for v in low.values()):
        return set()
    if not any(v in _COORD_POS_NAMES for v in low.values()):
        return set()
    keep = _COORD_CHROM_NAMES | _COORD_POS_NAMES | _COORD_EXTRA_NAMES
    return {h for h, v in low.items() if v in keep}


# Columns of a spec format that are VALUES (a plot or a model may use them); every other column
# of an interval / annotation format (Chrom, Start, End, Strand, Frame, Source, Feature, Phase,
# Attributes, the BED block columns …) is annotation. Name stays out of both: it is an
# identifier when its values are distinct (see _column_stats), else a descriptive column.
_SPEC_VALUE_COLUMNS = frozenset({"score", "value", "signalvalue", "pvalue", "qvalue"})
_SPEC_PLAIN_COLUMNS = frozenset({"name", "title", "smiles"})


def _spec_annotation_columns(spec: str, header: Sequence[str]) -> set:
    if spec == "smi":
        return set()
    return {str(h) for h in header
            if str(h).strip().lower() not in _SPEC_VALUE_COLUMNS | _SPEC_PLAIN_COLUMNS}


def _num(x: float) -> Any:
    """An integral float as an int (30.0 → 30), else the float."""
    return int(x) if float(x).is_integer() and abs(x) < 2 ** 53 else x


def _is_identifier(name: str, present: Sequence[str], distinct: int, typ: str, nums: Sequence[float]) -> bool:
    toks = set(_name_tokens(name))
    if not toks & _IDENTIFIER_NAME_TOKENS:
        return False
    if typ == "numeric":  # integers only: a measurement (sample_weight 1.25) is never an ID
        if not all(float(x).is_integer() for x in nums):
            return False
        if toks <= _POSITION_NAME_TOKENS and toks & _POSITION_ONLY_TOKENS:
            # A position in the source (page, page_no, row_index, line_number): an identifier
            # whatever its order — an extract of several documents restarts its page numbers.
            return True
        return distinct == len(present) or all(a <= b for a, b in zip(nums, nums[1:]))
    return distinct == len(present)


# Fewer data rows than this: the column / label statistics are not computed.
MIN_ROWS_FOR_CHECKS = 2


def _mostly_numeric(values: Sequence[str], decimal: str = ".") -> bool:
    present = [v for v in values if v != ""]
    return bool(present) and sum(1 for v in present if _is_number(v, decimal)) / len(present) >= _NUMERIC_COL_FRAC


def _blank_only(path: str) -> bool:
    with _open_text(path) as f:
        for i, line in enumerate(f):
            if line.strip():
                return False
            if i > 10_000:
                return False
    return True


def _leading_comment_count(path: str, skip: int) -> int:
    n = 0
    with _open_text(path) as f:
        for _ in range(skip):
            if f.readline().startswith("#"):
                n += 1
    return n


def _ragged_finding(p: DataProfile, rows: Sequence[Sequence[str]], layout: TableLayout) -> None:
    """Rows whose field count differs from the header line (extra fields are shown under
    generated column names; missing fields read as empty) — never truncated silently."""
    expected = layout.header_width or len(layout.names)
    if not expected or (layout.spec and layout.names_source == "spec"):
        return
    ragged = sum(1 for r in rows if len(r) != expected)
    if ragged:
        emit(p, "note", "ragged_rows", "", "watch", count=ragged, expected=expected)


def _column_names_finding(p: DataProfile, layout: TableLayout) -> None:
    """Say where the column names came from when they are not the file's own header row."""
    names = _named(layout.names)
    label = _BIOMATE_LABELS.get(layout.spec or "", (layout.spec or "").upper())
    if layout.names_source == "generated":
        emit(p, "note", "columns_generated",
             f"No header row detected (line 1 holds data values); columns are named column_1 … column_{len(layout.names)}.",
             count=len(layout.names))
    elif layout.names_source == "spec":
        emit(p, "note", "columns_spec",
             f"{label} files have no header row; column names follow the {label} specification: {', '.join(names)}.",
             format=label, columns=names)
    elif layout.names_source == "comment":
        emit(p, "note", "columns_comment",
             f"Column names taken from the file's last '#' comment line: {', '.join(names)}.",
             format=label, columns=names)


def _duplicate_columns_finding(p: DataProfile, header: Sequence[str]) -> None:
    """Column names used more than once: a reader keyed by name (pandas, R, a samplesheet) keeps
    only one of them or renames them silently."""
    counts = Counter(str(c).strip() for c in header if str(c).strip())
    dups = [c for c, n in counts.items() if n > 1]
    if dups:
        emit(p, "note", "duplicate_column_names", "", "watch", count=len(dups), columns=_named(dups))


def _set_duplicate_rows(p: DataProfile, rows: Sequence[Sequence[str]]) -> None:
    """Exact duplicate rows of a table that is not a modelling table: counted and noted, but no
    effective N — that is a modelling notion and is computed only with a confident label."""
    dups = len(rows) - _dedup_count(rows)
    p.duplicate_rows = dups
    if dups:
        emit(p, "note", "duplicate_rows", "", count=dups)


def _dedup_count(rows: Sequence[Sequence[str]]) -> int:
    seen = set()
    for r in rows:
        seen.add(tuple(c.strip() for c in r))
    return len(seen)


def _detect_leakage(
    p: DataProfile,
    header: Sequence[str],
    rows: Sequence[Sequence[str]],
    label_idx: int,
    label_col: Sequence[str],
) -> None:
    """Emit leakage findings (+ plan impact) from three heuristics.

    1. train/test overlap — duplicate feature-rows appearing in >1 split value.
    2. target leaked into a feature — a single column predicts the label at
       >= LEAKAGE_ACC_THRESHOLD accuracy.
    3. batch<->label confound — a batch/id column whose values map (near-)purely
       onto the label.
    """
    n_rows = len(rows)
    leaked_feature = False

    # A batch/id column is handled by the batch↔label branch below (it gets
    # "add as covariate" advice, not "drop"). Exclude it from the generic
    # leaky-feature scan so we don't mislabel a confound as a leaked feature.
    # The most batch-like column that IS a grouping (2…50% of rows distinct): a unique-per-row
    # patient_id is not a batch, the plate column beside it is.
    batch_idx = _batch_column(header, rows, label_idx)

    # 2. single-feature trivially predicts the label
    for j in range(len(header)):
        if j == label_idx or j == batch_idx:
            continue
        col = _column(rows, j)
        if all(v == "" for v in col):
            continue
        per_value: Dict[str, Counter] = {}
        for v, lbl in zip(col, label_col):
            if v == "" or lbl == "":
                continue
            per_value.setdefault(v, Counter())[lbl] += 1
        if not per_value:
            continue
        acc, base, total = _loo_value_accuracy(per_value)
        distinct_vals = len(per_value)
        near_unique = distinct_vals >= 0.95 * total
        if near_unique:
            # A value seen once carries no leave-one-out evidence, so a unique-per-row column is
            # scored by its NAME part instead: "ctrl_017" / "KO-3" give the group away through
            # "ctrl" / "ko"; a running ID (S0001 …), a hex code or a number has no telling stem.
            per_value = _per_stem(col, label_col)
            acc, base, total = _loo_value_accuracy(per_value) if len(per_value) >= 2 else (0.0, 0.0, 0)
        # Leakage = the column predicts the label for rows it has NOT memorised, well beyond the
        # majority-class baseline. (Scoring each value by its own rows' majority made every
        # unique-per-row measurement — a float column — "perfectly predict" any label.)
        if (acc >= LEAKAGE_ACC_THRESHOLD and (acc - base) >= 0.5 * (1.0 - base) and acc > base
                and total >= max(4, int(0.5 * n_rows))):
            if near_unique:
                emit(p, "leakage", "leaked_id",
                     f"column {header[j]!r} is (near-)unique per row and perfectly predicts the label — leaked id.",
                     "watch", column=header[j])
            elif _nested_in_groups(per_value) and _grouping_values(header[j], col):
                # A grouping column (donor, subject …) nested within the groups: a confounded
                # DESIGN, not a leaked feature — dropping the column does not separate the two
                # effects, so there is no "drop" plan. Other columns are still scanned.
                emit(p, "leakage", "group_nested", "", "watch", column=header[j], label=str(header[label_idx]))
                continue
            else:
                emit(p, "leakage", "leaked_feature",
                     f"column {header[j]!r} predicts the label at {acc*100:.0f}% — target leaked into features.",
                     "watch", column=header[j], pct=int(round(acc * 100)))
            emit(p, "plan", "drop_leaky_column", f"{header[j]} leaks the label",
                 effect_text=f"drop {header[j]!r} before modelling", column=header[j])
            leaked_feature = True
            break  # one is enough to flag

    # 3. batch<->label confound
    if not leaked_feature:
        _batch_confound(p, header, rows, label_idx, label_col)

    # 1. train/test overlap across a split column
    split_cols = _ranked_cols(header, _SPLIT_NAME_TOKENS, exclude=(label_idx,))
    split_idx = split_cols[0] if split_cols else None
    if split_idx is not None:
        split_col = _column(rows, split_idx)
        splits = set(v for v in split_col if v != "")
        if len(splits) >= 2:
            skip = {split_idx, label_idx}
            sig_to_splits: Dict[Tuple[str, ...], set] = {}
            for r, sp in zip(rows, split_col):
                if sp == "":
                    continue
                sig = tuple(
                    (r[k].strip() if k < len(r) else "")
                    for k in range(len(header))
                    if k not in skip
                )
                sig_to_splits.setdefault(sig, set()).add(sp)
            overlap = sum(1 for s in sig_to_splits.values() if len(s) >= 2)
            if overlap:
                emit(p, "leakage", "split_overlap",
                     f"{overlap} feature-row(s) appear in more than one split — train/test overlap.",
                     "watch", count=overlap)
                emit(p, "plan", "dedup_splits", "train/test overlap",
                     effect_text="de-duplicated rows across splits before evaluation")


def _batch_column(header: Sequence[str], rows: Sequence[Sequence[str]], label_idx: int) -> Optional[int]:
    """The most batch-like column that IS a grouping (2…50% of rows distinct): a unique-per-row
    patient_id is not a batch, the plate column beside it is."""
    for c in _ranked_cols(header, _BATCH_NAME_TOKENS, exclude=(label_idx,)):
        distinct = len(set(v for v in _column(rows, c) if v != ""))
        if 2 <= distinct <= max(2, int(BATCH_MAX_DISTINCT_FRAC * len(rows))):
            return c
    return None


def _batch_confound(p: DataProfile, header: Sequence[str], rows: Sequence[Sequence[str]], label_idx: int,
                    label_col: Sequence[str]) -> None:
    """batch↔label confound: a batch column whose values map (near-)purely onto the label. This
    is an EXPERIMENTAL-DESIGN check as much as a modelling one — a 6-sample sheet whose condition
    is batch b1 vs b2 cannot separate the two in a DE model — so it also runs for a label that is
    not a confident modelling target (a design sheet's "condition")."""
    batch_idx = _batch_column(header, rows, label_idx)
    if batch_idx is None:
        return
    batch_col = _column(rows, batch_idx)
    per_batch: Dict[str, Counter] = {}
    for v, lbl in zip(batch_col, label_col):
        if v == "" or lbl == "":
            continue
        per_batch.setdefault(v, Counter())[lbl] += 1
    pure = 0
    total = 0
    for _v, lblcounts in per_batch.items():
        total += sum(lblcounts.values())
        pure += lblcounts.most_common(1)[0][1]
    purity = pure / total if total else 0.0
    if _nested_in_groups(per_batch):
        # Every batch lies inside one group and each group spans several batches: the batch is
        # NESTED in the groups. A covariate cannot be added (it is collinear with the group), so
        # this is the confounded-design finding, without the covariate plan.
        emit(p, "leakage", "group_nested", "", "watch", column=header[batch_idx], label=str(header[label_idx]))
    elif purity >= BATCH_CONFOUND_PURITY:
        emit(p, "leakage", "batch_confound",
             f"{header[batch_idx]!r} (batch/id) is (near-)perfectly correlated with the outcome label.",
             "watch", column=header[batch_idx])
        emit(p, "plan", "batch_covariate", f"{header[batch_idx]}–label leakage",
             effect_text=f"add {header[batch_idx]!r} as a covariate before modelling",
             column=header[batch_idx])


def _grouping_values(name: str, values: Sequence[str]) -> bool:
    """Whether a column's values can be a GROUPING (donor, subject, plate …): non-numeric
    labels, or integers in a column whose name is a grouping word (donor 1…30, patient_id). A
    measured value that separates the groups (expression, a score) is a leaked feature instead."""
    if not _mostly_numeric(values):
        return True
    if not set(_name_tokens(name)) & set(_BATCH_NAME_TOKENS):
        return False
    present = [v for v in values if v != ""]
    return all(_is_number(v) and float(v).is_integer() for v in present)


def _nested_in_groups(per_value: Dict[str, Counter]) -> bool:
    """Whether a column is a GROUPING column nested within the label's groups: every value's
    rows carry one label only, there are more values than groups (so it is not a one-to-one
    recoding of the label — that IS a leaked feature, or a batch that lines up with the groups),
    and the values repeat — on average at least two rows per value (a near-unique identifier is a
    leaked id, not a grouping). E.g. donor D01…D30 with 20 samples each, every donor in one
    condition: donor and condition effects cannot be separated."""
    if not per_value:
        return False
    groups = set()
    for lblcounts in per_value.values():
        present = [k for k, c in lblcounts.items() if c > 0]
        if len(present) != 1:
            return False
        groups.add(present[0])
    total = sum(sum(c.values()) for c in per_value.values())
    return len(groups) >= 2 and len(per_value) > len(groups) and total >= 2 * len(per_value)


def _per_stem(col: Sequence[str], label_col: Sequence[str]) -> Dict[str, Counter]:
    """Label counts per NAME stem of an ID column — its letter runs, lower-cased, with digits and
    separators dropped ("ctrl_017" → "ctrl", "WT-r2" → "wt r"). Values without a letter have no
    stem and are left out."""
    out: Dict[str, Counter] = {}
    for v, lbl in zip(col, label_col):
        if v == "" or lbl == "":
            continue
        stem = " ".join(t.lower() for t in re.findall(r"[A-Za-z]+", v))
        if stem:
            out.setdefault(stem, Counter())[lbl] += 1
    return out


def _loo_value_accuracy(per_value: Dict[str, Counter]) -> Tuple[float, float, int]:
    """(leave-one-out accuracy, majority-class baseline, labelled rows) of predicting the label
    from one column's value: each row is predicted by the majority label of the OTHER rows with
    the same value; a value seen once carries no evidence and is predicted by the overall
    majority label."""
    overall: Counter = Counter()
    for lblcounts in per_value.values():
        overall.update(lblcounts)
    total = sum(overall.values())
    if not total:
        return 0.0, 0.0, 0
    majority_label, majority_n = overall.most_common(1)[0]
    correct = 0
    for lblcounts in per_value.values():
        n_v = sum(lblcounts.values())
        for lbl, cnt in lblcounts.items():
            if n_v == 1:
                correct += cnt if lbl == majority_label else 0
                continue
            others = Counter(lblcounts)
            others[lbl] -= 1
            top = max(others.values())
            # A tie among the other rows is not a prediction of this row's label.
            winners = [k for k, c in others.items() if c == top]
            if winners == [lbl]:
                correct += cnt
    return correct / total, majority_n / total, total


def _effective_n(
    rows: Sequence[Sequence[str]],
    label_col: Sequence[str],
    balance: Sequence[Tuple[str, float]],
) -> Tuple[int, str, int]:
    """Estimate effective sample size → (effective N, binding reason, unique rows).

    Combines two deterministic reductions and reports the binding (smallest):
      * "dedup" — exact duplicate rows count once.
      * "imbalance" — for classification, usable N is bounded by the minority
        class (a 7/93 split of 300 rows carries ~ the information of the ~2*21
        balanced examples, generalized to k*min for k classes).
    The caller notes it when the effective N is well below the raw row count.
    """
    n_rows = len(rows)

    unique = _dedup_count(rows)
    candidates: List[Tuple[int, str]] = [(unique, "dedup")]

    if balance:
        counts = Counter(v for v in label_col if v != "")
        minority = min(counts.values()) if counts else n_rows
        k = len(counts)
        candidates.append((k * minority, "imbalance"))

    eff, reason = min(candidates, key=lambda c: c[0])
    eff = max(1, min(eff, n_rows))
    return eff, reason, unique
