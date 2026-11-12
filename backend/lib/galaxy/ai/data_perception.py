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

import csv
import gzip
import io
import json
import logging
import os
from collections import Counter
from dataclasses import dataclass, field
from typing import Any, Dict, Iterator, List, Optional, Sequence, Tuple

log = logging.getLogger(__name__)

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

# Column-name tokens that mark a plausible classification LABEL column.
_LABEL_NAME_TOKENS = (
    "label", "target", "class", "outcome", "response", "responder",
    "y", "diagnosis", "status", "group", "condition", "phenotype",
)

# Column-name tokens that mark a plausible BATCH / grouping / id column.
_BATCH_NAME_TOKENS = (
    "batch", "site", "plate", "run", "lane", "center", "centre",
    "cohort", "study", "donor", "subject", "patient",
    "id", "uuid", "barcode",
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
    quality: str = "good"  # good | watch | blocked
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
        if self.profiled_rows is not None:
            out["profiledRows"] = self.profiled_rows
        if self.format is not None:
            out["format"] = dict(self.format)
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

    For "plan", ``text`` is the observed side and ``params["effect_text"]`` the effect.
    Params must be JSON-serializable (they are interpolated by the UI's i18n strings).
    """
    if section == "note":
        p.notes.append(text)
    elif section == "signal":
        p.signal_summary = (p.signal_summary or []) + [text]
    elif section == "leakage":
        p.leakage_detail = f"{p.leakage_detail} {text}" if p.leakage_detail else text
    elif section == "plan":
        p.plan_impact.append((text, str(params.pop("effect_text", ""))))
    else:  # pragma: no cover — programming error
        raise ValueError(f"unknown finding section {section!r}")
    p.findings.append({"section": section, "code": code, "level": level, "params": params})


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
def profile_dataset(path: str, *, name: Optional[str] = None) -> Dict[str, Any]:
    """Profile a dataset file and return the frontend ``DataProfile`` dict.

    Sniffs by extension + content, dispatches to a type-specific profiler, and
    always returns a valid shape. Never raises for a profilable-but-messy file;
    only truly-unreadable inputs yield a ``blocked`` verdict.
    """
    return profile_to_dataclass(path, name=name).to_dict()


def profile_to_dataclass(path: str, *, name: Optional[str] = None) -> DataProfile:
    """Same as :func:`profile_dataset` but returns the dataclass (for tests)."""
    display = name or (os.path.basename(path) if path else "")
    if not path or not os.path.exists(path):
        if path:
            p = blocked_profile("file_not_found", f"File not found: {path!r}.")
        else:
            p = blocked_profile("no_path", "No dataset path provided.")
        p.format = _biomate_format("unknown", display, None)
        return p

    try:
        size = os.path.getsize(path)
    except OSError:
        size = -1
    if size == 0:
        p = blocked_profile("empty_file", "File is empty (0 bytes).")
        p.format = _biomate_format("unknown", display, None)
        return p

    kind = _sniff_kind(path)
    gext = _galaxy_identify(path, display)
    # When the filename does not decide the format (.txt, no extension, or an extension BioMate has
    # no reader for, e.g. .sam / .pdb that only LOOK delimited), Galaxy's content identification
    # does: a FASTQ saved as .txt is profiled as FASTQ, a SAM or PDB is not read as a CSV.
    if gext and (kind == "unknown" or (kind == "table" and (_generic_name(display) or _kind_from_name(path) is None))):
        mapped = _GALAXY_TO_KIND.get(gext)
        if mapped:
            kind = mapped
        elif gext in _GALAXY_NON_TABLE:
            kind = "unknown"
    layout: Optional[TableLayout] = None
    holder: List[TableLayout] = []
    named = _kind_from_name(path)
    try:
        if kind == "unknown" and named and _is_binary(path) and not (gext and gext not in _galaxy_generic()):
            # Named as a text format (.csv, .bed, .fasta, …) but the content is binary.
            p = DataProfile(quality="watch")
            label = _named_label(path)
            emit(p, "note", "spec_mismatch",
                 f"Named as {label}, but its content does not follow the {label} format, so it was not read as one.",
                 "watch", format=label)
            kind = "mismatch"
        elif kind in ("json", "yaml"):
            p = _profile_structured(path, kind)
        elif kind == "fastq":
            p = _profile_fastq(path)
        elif kind == "fasta":
            p = _profile_fasta(path)
        elif kind == "vcf":
            p = _profile_vcf(path)
        elif kind == "table" and _spec_of(path) is not None and not _spec_layout_or_none(path, holder):
            # Named as a spec format (.bed, .gtf, …) but its lines do not follow it.
            spec = (_spec_of(path) or ("", None))[0]
            label = _BIOMATE_LABELS.get(spec, spec.upper())
            if gext and gext not in _galaxy_generic() and gext not in _KIND_COMPATIBLE_GALAXY["table"]:
                p = _profile_galaxy_format(path, gext, size)
            else:
                p = DataProfile(quality="watch")
            emit(p, "note", "spec_mismatch",
                 f"Named as {label}, but its content does not follow the {label} format, so it was not read as one.",
                 "watch", format=label)
            kind = "mismatch"
        elif kind == "table":
            layout = holder[0] if holder else _table_layout(path)
            p = _profile_table(path, layout=layout)
            if layout.spec:
                _spec_table_findings(p, path, layout, gext)
        elif kind == "jsonl":
            p = _profile_table(path, reader=_read_jsonl)
        elif kind == "mtx":
            p = _profile_mtx(path)
        else:
            p = _profile_unknown(path, display, gext, size)
    except BinaryContent:
        # Binary past the first block (the text sniff could not tell): not a text format at all.
        kind, layout = "unknown", None
        p = _profile_unknown(path, display, gext, size)
    except Exception as e:  # noqa: BLE001 — defensive: profiling must never crash ingest.
        log.warning("[perception] profiling failed for %s: %s", path, e)
        p = blocked_profile("parse_failed", f"Could not parse file: {e}", error=str(e)[:300])
    p.format = _format_for(kind, gext, display, layout)
    return p


def _profile_unknown(path: str, display: str, gext: Optional[str], size: int) -> DataProfile:
    """A file BioMate has no profiler for: Galaxy's metadata when Galaxy identified a specific
    format, else the honest "unprofilable" note."""
    if gext and gext not in _galaxy_generic():
        return _profile_galaxy_format(path, gext, size)
    p = DataProfile(quality="watch")
    emit(
        p, "note", "unprofilable",
        f"File type not profilable ({os.path.basename(display)}); "
        "reported shape only, no leakage/balance derived.",
        "watch", name=os.path.basename(display), ext=gext or "",
    )
    return p


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
    gf = _galaxy_formats()
    if gf is not None:
        try:
            return gf.label_for(ext)
        except Exception:  # noqa: BLE001
            pass
    return (ext or "unknown").upper()


# Galaxy extension → the BioMate profiler that analyses it.
_GALAXY_TO_KIND: Dict[str, str] = {
    "fastqsanger": "fastq", "fastqsanger.gz": "fastq", "fastqsanger.bz2": "fastq",
    "fastq": "fastq", "fastq.gz": "fastq", "fastqillumina": "fastq", "fastqsolexa": "fastq",
    "fastqcssanger": "fastq", "vcf": "vcf", "json": "json", "yaml": "yaml",
    "fasta": "fasta", "fasta.gz": "fasta",
}
# Galaxy formats that are certainly not delimited tables (a .txt holding one is not a table).
_GALAXY_NON_TABLE = frozenset({
    "sdf", "pdb", "cif", "mol2", "genbank", "stockholm", "obo", "owl",
    "sam", "pqr", "gro", "xyz", "phylip", "newick", "nhx", "nexus",
})
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


def _named_label(path: str) -> str:
    spec = _spec_of(path)
    if spec:
        return _BIOMATE_LABELS.get(spec[0], spec[0].upper())
    ext = _ext_of(path).lstrip(".")
    return _BIOMATE_LABELS.get(ext, ext.upper() or "Unknown")


def _generic_name(name: str) -> bool:
    ext = _ext_of(name or "")
    return ext in ("", ".txt", ".tab", ".dat", ".data")


def _biomate_format(kind: str, name: str, layout: Optional["TableLayout"]) -> Dict[str, Any]:
    """BioMate's own format id from its kind + the filename (used when Galaxy has no better)."""
    lower = (name or "").lower()
    gz = lower.endswith(".gz")
    if kind == "table":
        named = _ext_of(name or "")
        if layout is not None and layout.spec:
            ext = layout.spec
        elif named == ".csv":
            ext = "csv"
        elif named in (".tsv", ".tab"):
            ext = "tsv"
        elif layout is not None and len(layout.names) <= 1:
            ext = "txt"  # one value per line (a gene / ID list)
        elif layout is not None and layout.delim == "\t":
            ext = "tabular"
        else:
            ext = "csv"
    elif kind == "mismatch":
        ext = "unknown"
    elif kind == "unknown":
        e = _ext_of(name or "").lstrip(".")
        ext = e or "unknown"
    else:
        ext = kind
    label = _BIOMATE_LABELS.get(ext) or _format_label(ext)
    if gz and kind not in ("unknown", "mismatch"):
        label += " (gzip)"
    return {"ext": ext, "label": label, "source": "biomate"}


_BIOMATE_LABELS: Dict[str, str] = {
    "csv": "CSV", "tsv": "TSV", "jsonl": "JSON Lines", "json": "JSON", "yaml": "YAML",
    "fastq": "FASTQ", "fasta": "FASTA", "vcf": "VCF", "mtx": "Matrix Market", "bed": "BED", "bedgraph": "bedGraph",
    "narrowpeak": "narrowPeak", "broadpeak": "broadPeak", "gtf": "GTF", "gff": "GFF", "gff3": "GFF3",
    "smi": "SMILES", "unknown": "Unknown", "txt": "Text (one value per line)", "tabular": "Tabular",
    "bedpe": "BEDPE",
}


def _format_for(kind: str, gext: Optional[str], name: str, layout: Optional["TableLayout"]) -> Dict[str, Any]:
    """The format chip: Galaxy's identification when it is specific and agrees with how BioMate
    analysed the file; otherwise BioMate's own."""
    generic = _galaxy_generic()
    if gext and gext not in generic:
        compatible = _KIND_COMPATIBLE_GALAXY.get(kind)
        ok = compatible is None or any(gext == c or gext.startswith(c) for c in compatible)
        if kind == "mismatch":  # its lines do not follow the named table format
            ok = gext not in _KIND_COMPATIBLE_GALAXY["table"]
        if ok:
            return {"ext": gext, "label": _format_label(gext), "source": "galaxy"}
    return _biomate_format(kind, name, layout)


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
    """Structural validation, not a claim about scientific dataset quality."""
    p = DataProfile(quality="watch")
    with _open_text(path) as handle:
        text = handle.read(2 * 1024 * 1024 + 1)
    if len(text) > 2 * 1024 * 1024:
        emit(p, "note", "structured_too_large",
             "Structured validation is limited to files under 2 million characters; download for complete validation.",
             "watch")
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
    emit(p, "note", "structured_only",
         f"Valid {kind.upper()} syntax; {root} root. Structural checks only; scientific quality has not been assessed.",
         "watch", format=kind.upper(), root=root)
    return p


# ---------------------------------------------------------------------------
# Sniffing
# ---------------------------------------------------------------------------
def _raw_head(path: str, n: int = 8192) -> bytes:
    """The first ``n`` content bytes (gzip / bzip2 decompressed, by magic number)."""
    with open(path, "rb") as f:
        magic = f.read(3)
    try:
        if magic[:2] == b"\x1f\x8b":
            with gzip.open(path, "rb") as g:
                return g.read(n)
        if magic == b"BZh":
            import bz2

            with bz2.open(path, "rb") as b:
                return b.read(n)
    except (OSError, EOFError, ValueError):
        pass
    with open(path, "rb") as f:
        return f.read(n)


def _utf16_bom(head: bytes) -> bool:
    return head[:2] in (b"\xff\xfe", b"\xfe\xff")


def _is_binary(path: str) -> bool:
    """True for binary content (BAM, CRAM, TIFF, HDF5, xlsx, FITS, …), judged on the first
    (decompressed) block: a NUL byte that is not UTF-16 text, a full block without a single line
    break (no line-oriented text format looks like that), or many control bytes. Binary files must
    never reach the text readers (csv raised "line contains NUL" and the file was called broken)."""
    try:
        head = _raw_head(path)
    except OSError:
        return False
    if _utf16_bom(head):
        return False
    if b"\x00" in head:
        return True
    if len(head) >= 8192 and b"\n" not in head and b"\r" not in head:
        return True
    ctrl = sum(1 for b in head if b < 9 or 13 < b < 32)
    return bool(head) and ctrl / len(head) > 0.1


class BinaryContent(ValueError):
    """Raised by the text readers on a NUL byte found past the first block."""


def _nul_guard(lines: Iterator[str]) -> Iterator[str]:
    for line in lines:
        if "\x00" in line:
            raise BinaryContent("binary content (NUL byte) in a text file")
        yield line


def _open_text(path: str) -> io.TextIOBase:
    """Text view of a file: gzip / bzip2 decompressed by magic number (a BGZF VCF named
    ``.vcf_bgzip``, a ``.prj`` that is gzip), UTF-16 when it carries a BOM, else UTF-8."""
    try:
        with open(path, "rb") as f:
            magic = f.read(3)
    except OSError:
        magic = b""
    if magic[:2] == b"\x1f\x8b":
        return gzip.open(path, "rt", encoding="utf-8", errors="replace")
    if magic == b"BZh":
        import bz2

        return bz2.open(path, "rt", encoding="utf-8", errors="replace")
    # UTF-16 text (Excel "Unicode text" exports) carries a BOM; everything else is read as UTF-8.
    enc = "utf-16" if _utf16_bom(magic) else "utf-8"
    return open(path, "rt", encoding=enc, errors="replace")


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


def _sniff_kind(path: str) -> str:
    """Return one of: 'json', 'yaml', 'jsonl', 'fastq', 'fasta', 'vcf', 'table', 'mtx', 'unknown'."""
    if _is_binary(path):
        return "unknown"  # binary formats are identified by Galaxy's datatypes, never parsed as text
    named = _kind_from_name(path)
    if named:
        return named

    # Content sniff for extension-less or ambiguous files.
    try:
        with _open_text(path) as f:
            head = f.readline()
            second = f.readline()
    except Exception:
        return "unknown"
    if head.startswith("##fileformat=VCF") or head.startswith("#CHROM"):
        return "vcf"
    if head.startswith("%%MatrixMarket"):
        return "mtx"
    if head.startswith("@") and second and set(second.strip()) <= set("ACGTNacgtn"):
        return "fastq"
    if head.startswith(">") and second and second.strip() and second.strip().replace("*", "").replace("-", "").isalpha():
        return "fasta"
    # JSON Lines: a JSON object per line. Must precede the comma check — every JSON object
    # line contains commas, so it was profiled as CSV (columns like '{"source": "epar_table"').
    if head.lstrip().startswith("{"):
        try:
            if isinstance(json.loads(head), dict):
                return "jsonl"
        except ValueError:
            pass
    if ("," in head) or ("\t" in head):
        return "table"
    return "unknown"


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
        emit(p, "note", "format_header_unreadable",
             f"The {label} header could not be read ({meta['error']}); the file may be truncated or malformed.",
             "watch", format=label, error=str(meta["error"])[:200])
        if p.quality == "good":
            p.quality = "watch"
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
            emit(p, "signal", "molecules_count", f"{n:,} molecule(s).", molecules=n)


def _profile_mtx(path: str) -> DataProfile:
    """Matrix Market: dimensions + stored entries from the size line (the data is not read)."""
    p = DataProfile(quality="watch")
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
    obj = parts[1].lower() if len(parts) > 1 else ""
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
    if layout == "coordinate" and len(dims) >= 3:
        nnz = dims[2]
        density = (100.0 * nnz / (rows * cols)) if rows and cols else 0.0
        emit(p, "signal", "mtx_dimensions",
             f"{rows:,} × {cols:,} sparse {field_ or 'matrix'} matrix with {nnz:,} stored entries ({density:.2f}% dense).",
             rows=rows, cols=cols, nnz=nnz, density=round(density, 2), field=field_, symmetry=symmetry)
    else:
        emit(p, "signal", "mtx_dense", f"{rows:,} × {cols:,} dense {field_ or 'matrix'} matrix ({obj or 'matrix'}).",
             rows=rows, cols=cols, field=field_)
    emit(p, "note", "mtx_orientation",
         "Matrix Market files carry no row/column names: pair this matrix with its features/barcodes files "
         "(10x: rows are features, columns are cells).")
    emit(p, "note", "format_metadata_only",
         "Matrix Market header read; the values were not analysed.", "watch", format="Matrix Market")
    return p


def _profile_galaxy_format(path: str, ext: str, size: int) -> DataProfile:
    """A format BioMate has no analysis for, described from Galaxy's metadata (or identified
    only). Never claims anything about content it did not read."""
    p = DataProfile(quality="watch")
    label = _format_label(ext)
    meta = _galaxy_metadata(path, ext)
    described = False
    if not _meta_problem(p, meta, label):
        described = _galaxy_meta_findings(p, ext, meta, label)
    if described:
        emit(p, "note", "format_metadata_only",
             f"{label} metadata read; the data values themselves were not analysed.", "watch", format=label)
    elif not any(f["code"] in ("format_header_unreadable",) for f in p.findings):
        emit(p, "note", "format_identified",
             f"Identified as {label} ({_human_size(size)}); BioMate does not analyse its contents here.",
             "watch", format=label, size=_human_size(size))
    return p


def _galaxy_meta_findings(p: DataProfile, ext: str, meta: Dict[str, Any], label: str) -> bool:
    """Findings from one format's Galaxy metadata; False when nothing useful was in it."""
    if ext == "h5ad":
        shape = meta.get("shape")
        cells = genes = None
        if isinstance(shape, (list, tuple)) and len(shape) >= 2:
            cells, genes = _meta_int({"v": shape[0]}, "v"), _meta_int({"v": shape[1]}, "v")
        cells = cells if cells is not None else _meta_int(meta, "obs_size")
        genes = genes if genes is not None else _meta_int(meta, "var_size")
        if cells is None or genes is None:
            return False
        p.rows, p.cols = cells, genes
        obs = _meta_list(meta, "obs_layers", ("index", "_index"))
        var = _meta_list(meta, "var_layers", ("index", "_index"))
        emit(p, "signal", "anndata_shape", f"{cells:,} cells (obs) × {genes:,} genes/features (var).",
             cells=cells, genes=genes)
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
        groups = _meta_list(meta, "layers_names")
        if groups:
            emit(p, "note", "hdf5_groups", f"Stored groups: {', '.join(_named(groups))}.",
                 count=len(groups), groups=_named(groups))
        return True
    if ext == "loom":
        shape = meta.get("shape")
        if not (isinstance(shape, (list, tuple)) and len(shape) >= 2):
            return False
        genes, cells = _meta_int({"v": shape[0]}, "v"), _meta_int({"v": shape[1]}, "v")
        if genes is None or cells is None:
            return False
        p.rows, p.cols = cells, genes
        emit(p, "signal", "loom_shape", f"{genes:,} genes (rows) × {cells:,} cells (columns).",
             genes=genes, cells=cells)
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
        emit(p, "signal", "alignment_references",
             f"{refs:,} reference sequence(s) in the header ({_meta_int(meta, 'reference_total_length') or 0:,} bp).",
             references=refs, length=_meta_int(meta, "reference_total_length") or 0,
             names=_named(_meta_list(meta, "reference_names")))
        order = str(meta.get("sort_order") or "unknown")
        if order == "coordinate":
            emit(p, "note", "alignment_sorted", "Coordinate-sorted (header SO:coordinate).", order=order)
        else:
            emit(p, "note", "alignment_not_coordinate_sorted",
                 f"Sort order is {order!r}, not coordinate: sort before indexing or variant calling.",
                 "watch", order=order)
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
        emit(p, "signal", "molecules_count", f"{n:,} molecule(s).", molecules=n)
        return True
    if ext in ("pdb", "cif"):
        chains = _meta_list(meta, "chain_ids")
        if not chains:
            return False
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
        emit(p, "signal", "spreadsheet_sheets", f"{len(names)} sheet(s): {', '.join(_named(names))}.",
             count=len(names), sheets=_named(names))
        emit(p, "note", "spreadsheet_convert",
             "Spreadsheets are not profiled cell by cell: export the sheet to CSV to get the table checks.")
        return True
    return False


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


def _open_bytes(path: str):
    with open(path, "rb") as f:
        magic = f.read(3)
    if magic[:2] == b"\x1f\x8b":
        return gzip.open(path, "rb")
    if magic == b"BZh":
        import bz2

        return bz2.open(path, "rb")
    return open(path, "rb")


def _n50(lengths: Sequence[int]) -> int:
    total = sum(lengths)
    acc = 0
    for n in sorted(lengths, reverse=True):
        acc += n
        if acc * 2 >= total:
            return n
    return 0


def _profile_fasta(path: str) -> DataProfile:
    """FASTA (plain / gzip / bzip2): sequence count, total / mean / min / max length, N50, and
    for nucleotides GC% and N share. Streams up to MAX_FASTA_BYTES of content."""
    p = DataProfile()
    lengths: List[int] = []
    cur: Optional[int] = None
    gc = at = n_bases = residues = scanned = 0
    truncated = False
    orphan = 0  # sequence lines before the first '>' header
    with _open_bytes(path) as f:
        for line in f:
            scanned += len(line)
            if line[:1] == b">":
                if cur is not None:
                    lengths.append(cur)
                if scanned > MAX_FASTA_BYTES:
                    cur = None
                    truncated = True
                    break
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
    if cur is not None:
        lengths.append(cur)

    n = len(lengths)
    p.rows = n
    if n == 0:
        p.quality = "blocked"
        emit(p, "note", "fasta_no_sequences", "No '>' sequence headers found.", "blocked")
        return p
    total = sum(lengths)
    mean = total / n
    p.cols = int(round(mean))
    nucleotide = residues > 0 and (gc + at + n_bases) / residues >= _NUCLEOTIDE_FRAC
    unit = "bp" if nucleotide else "aa"
    emit(p, "signal", "fasta_sequences",
         f"{'≥' if truncated else ''}{n:,} sequences, {total:,} {unit}; length mean {mean:,.0f}, "
         f"min {min(lengths):,}, max {max(lengths):,}, N50 {_n50(lengths):,}.",
         sequences=n, at_least=truncated, total=total, unit=unit, mean=int(round(mean)),
         min=min(lengths), max=max(lengths), n50=_n50(lengths))
    if nucleotide:
        gc_pct = round(100.0 * gc / (gc + at), 1) if (gc + at) else 0.0
        emit(p, "signal", "fasta_gc", f"GC content {gc_pct}% (nucleotide sequences).", pct=gc_pct)
        n_frac = n_bases / residues if residues else 0.0
        if n_frac >= _HIGH_N_FRAC:
            p.quality = "watch"
            emit(p, "note", "fasta_high_n",
                 f"{100 * n_frac:.0f}% of bases are N (unknown): gaps or a low-quality assembly.",
                 "watch", pct=int(round(100 * n_frac)))
    else:
        emit(p, "note", "fasta_protein", "Protein sequences (amino-acid alphabet).")
    empty = sum(1 for x in lengths if x == 0)
    if empty:
        p.quality = "watch"
        emit(p, "note", "fasta_empty_records", f"{empty:,} header(s) with no sequence.", "watch", count=empty)
    if orphan:
        p.quality = "watch"
        emit(p, "note", "fasta_orphan_lines", f"{orphan:,} sequence line(s) before the first '>' header were ignored.",
             "watch", count=orphan)
    if truncated:
        emit(p, "note", "fasta_profiled_subset",
             f"Statistics cover the first {MAX_FASTA_BYTES // (1024 * 1024)} MB of the file.",
             mb=MAX_FASTA_BYTES // (1024 * 1024))
    return p


# ---------------------------------------------------------------------------
# FASTQ
# ---------------------------------------------------------------------------
def _profile_fastq(path: str, sample_reads: int = 4000) -> DataProfile:
    """Profile a FASTQ file: reads (sampled), mean length, mean quality.

    Read-counting mirrors DatasetValidator._count_fastq_reads (sampled,
    gzip-aware). We additionally read the length/quality of sampled reads for a
    numeric-first signal summary and a single-end note.
    """
    p = DataProfile()
    n_reads = 0
    total_len = 0
    total_q = 0
    q_chars = 0
    truncated = False
    with _open_text(path) as f:
        while True:
            header = f.readline()
            if not header:
                break
            seq = f.readline()
            _plus = f.readline()
            qual = f.readline()
            if not qual:
                break  # incomplete final record
            n_reads += 1
            s = seq.strip()
            total_len += len(s)
            ql = qual.strip()
            for ch in ql:
                total_q += ord(ch) - 33  # Phred+33
                q_chars += 1
            if n_reads >= sample_reads:
                truncated = True
                break

    # FASTQ "shape": rows = reads observed, cols = mean read length.
    p.rows = n_reads
    mean_len = (total_len / n_reads) if n_reads else 0
    p.cols = int(round(mean_len))
    mean_q = (total_q / q_chars) if q_chars else 0.0

    count_word = "≥" if truncated else ""
    emit(p, "signal", "fastq_reads",
         f"{count_word}{n_reads:,} reads scanned; mean read length {mean_len:.0f} bp.",
         reads=n_reads, at_least=truncated, mean_len=int(round(mean_len)))
    emit(p, "signal", "fastq_mean_quality", f"Mean base quality Phred {mean_q:.1f} (sampled).",
         q=round(mean_q, 1))
    # Single-end vs paired-end can't be known from one file — state honestly.
    emit(p, "note", "fastq_single_file",
         "Single FASTQ file profiled — single-end unless a mate file is present.")
    emit(p, "plan", "fastq_single_end", "single FASTQ observed",
         effect_text="suggested single-end pipeline (override if paired mate exists)")

    if mean_q and mean_q < 20:
        p.quality = "watch"
        emit(p, "note", "fastq_low_quality",
             f"Mean base quality Phred {mean_q:.1f} is below 20 — consider trimming.",
             "watch", q=round(mean_q, 1))
    if n_reads == 0:
        p.quality = "blocked"
        emit(p, "note", "fastq_no_records", "No FASTQ records parsed — file may be malformed.", "blocked")
    return p


# ---------------------------------------------------------------------------
# VCF
# ---------------------------------------------------------------------------
def _profile_vcf(path: str) -> DataProfile:
    """Profile a VCF: variant count (rows) and sample count (cols)."""
    p = DataProfile()
    n_variants = 0
    n_samples = 0
    with _open_text(path) as f:
        for line in f:
            if line.startswith("##"):
                continue
            if line.startswith("#CHROM"):
                cols = line.rstrip("\n").split("\t")
                # Standard VCF: 8 fixed cols, then FORMAT, then samples.
                n_samples = max(0, len(cols) - 9)
                continue
            if line.strip():
                n_variants += 1

    p.rows = n_variants
    p.cols = n_samples
    emit(p, "signal", "vcf_records", f"{n_variants:,} variant records across {n_samples} sample(s).",
         variants=n_variants, samples=n_samples)
    emit(p, "note", "vcf_summary", f"VCF with {n_variants:,} variants, {n_samples} genotyped sample(s).",
         variants=n_variants, samples=n_samples)
    if n_variants == 0:
        p.quality = "watch"
        emit(p, "note", "vcf_no_variants", "No variant records found (header only).", "watch")
    emit(p, "plan", "vcf_sized", f"{n_variants:,} variants / {n_samples} samples",
         effect_text="sized variant-annotation / filtering plan", variants=n_variants, samples=n_samples)
    return p


# ---------------------------------------------------------------------------
# Tables (CSV / TSV) — the leakage / effective-N / class-balance surface.
# ---------------------------------------------------------------------------
def _sniff_delimiter(path: str) -> str:
    lower = _strip_gz(path.lower())
    if lower.endswith((".tsv", ".tab")):
        return "\t"
    if lower.endswith(".csv"):
        return ","
    # sniff first line
    with _open_text(path) as f:
        head = f.readline()
    if head.count("\t") > head.count(","):
        return "\t"
    return ","


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
# A column is numeric when at least this share of its non-empty data values parse as numbers.
_NUMERIC_COL_FRAC = 0.8


@dataclass
class TableLayout:
    delim: str
    # Column names, and where they came from: "header" (line 1), "comment" (the last '#' line of a
    # spec format), "spec" (the format's specification), "generated" (column_1…: no header row).
    names: List[str]
    names_source: str = "header"
    # True when the first record of the file is a header row (not data). The edit route counts
    # data rows after this many header records.
    header_row: bool = True
    # Spec format key (bed, gtf, …) or None for a generic delimited table.
    spec: Optional[str] = None
    # False when a spec-format file's lines do not follow that format (e.g. a binary or a
    # mislabelled file named .bed): it is then not served or profiled as a table.
    valid: bool = True


def _spec_of(path: str) -> Optional[Tuple[str, Optional[str]]]:
    _, ext = os.path.splitext(_strip_gz(path.lower()))
    return _SPEC_TABLE_EXTS.get(ext)


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
        for line in lines:
            yield line.split()
    else:
        for row in csv.reader(_nul_guard(lines), delimiter=delim, quoting=csv.QUOTE_NONE):
            yield row


def _is_number(v: str) -> bool:
    try:
        float(v)
        return True
    except ValueError:
        return False


def _is_missing(v: str) -> bool:
    return v.strip().lower() in _MISSING_TOKENS


def _style(v: str) -> Tuple[str, bool]:
    """Casing class + whitespace presence of a single text value (for one-column lists)."""
    t = v.strip()
    letters = [c for c in t if c.isalpha()]
    if not letters:
        case = "none"
    elif all(c.isupper() for c in letters):
        case = "upper"
    elif all(c.islower() for c in letters):
        case = "lower"
    elif letters[0].isupper() and all(c.islower() for c in letters[1:]):
        case = "title"
    else:
        case = "mixed"
    return case, any(c.isspace() for c in t)


def _line1_is_header(first: List[str], data: List[List[str]]) -> bool:
    """Whether line 1 of a generic delimited table is a header, decided from the content:

    * a column that is numeric in the data (≥80% of its non-empty values) but text in line 1
      ⇒ header;
    * else, if every numeric column's line-1 value is numeric ⇒ no header (line 1 is data);
    * no numeric column: a single text column whose line 1 differs from the data's majority
      casing style / whitespace (``gene`` over ``TP53, EGFR``) ⇒ header, same style ⇒ none;
      several text columns ⇒ header;
    * anything undecidable ⇒ header (the long-standing default).
    """
    if not data:
        return True
    width = len(first)
    saw_numeric_line1 = False
    for j in range(width):
        vals = [r[j].strip() for r in data if j < len(r) and not _is_missing(r[j])]
        if not vals:
            continue
        if sum(1 for v in vals if _is_number(v)) / len(vals) < _NUMERIC_COL_FRAC:
            continue
        cell = first[j].strip()
        if _is_missing(cell):
            continue  # an empty header cell (R's row-name column) is no evidence either way
        if not _is_number(cell):
            return True
        saw_numeric_line1 = True
    if saw_numeric_line1:
        return False
    if width == 1 and all(len(r) <= 1 for r in data):
        vals = [r[0] for r in data if r and not _is_missing(r[0])]
        if not vals or _is_missing(first[0]):
            return True
        majority = Counter(_style(v) for v in vals).most_common(1)[0][0]
        return _style(first[0]) != majority
    return True


def _spec_lines_valid(path: str, key: str, delim: str) -> bool:
    """Whether the sampled data lines follow the spec format's shape (see _SPEC_SHAPE). A file
    with no data lines (only a track line / comments) is a valid, empty table. Binary content
    (a NUL byte, or undecodable bytes) is never valid."""
    min_cols, int_cols = _SPEC_SHAPE.get(key, (1, ()))
    good = total = 0
    with _open_text(path) as f:
        for row in _spec_reader(_spec_lines(f), delim):
            total += 1
            joined = "".join(row)
            if "\x00" in joined or "\ufffd" in joined:
                return False
            if len(row) >= min_cols and all(row[j].strip().lstrip("-").isdigit() for j in int_cols):
                good += 1
            if total >= _HEADER_SAMPLE_ROWS:
                break
    return total == 0 or good / total >= _SPEC_VALID_FRAC


def _spec_layout_or_none(path: str, holder: List["TableLayout"]) -> bool:
    """Layout of a spec-format file (appended to ``holder``) when its lines follow the format;
    False when they do not or the file is unreadable as text."""
    try:
        lay = _table_layout(path)
    except Exception:  # noqa: BLE001 — unreadable as text ⇒ not that table format
        return False
    if not lay.valid:
        return False
    holder.append(lay)
    return True


def _table_layout(path: str) -> TableLayout:
    """Decide the delimiter and the column names of a delimited file (see _line1_is_header for
    generic tables; spec formats such as BED/GTF/SMILES have no header row by specification)."""
    spec = _spec_of(path)
    if spec is not None:
        key, galaxy_ext = spec
        comment: Optional[str] = None
        first: Optional[str] = None
        with _open_text(path) as f:
            for line in f:
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
        width = len(next(_spec_reader(iter([first]), delim), [])) if first else 0
        valid = _spec_lines_valid(path, key, delim)
        if comment is not None and width:
            cnames = [c.strip() for c in next(_spec_reader(iter([comment.lstrip("#")]), delim), [])]
            if len(cnames) == width and all(cnames):
                return TableLayout(delim, cnames, "comment", header_row=True, spec=key, valid=valid)
        names = _spec_names(key, galaxy_ext)[:width] if width else _spec_names(key, galaxy_ext)
        names += [f"column_{i + 1}" for i in range(len(names), width)]
        return TableLayout(delim, names, "spec", header_row=False, spec=key, valid=valid)

    delim = _sniff_delimiter(path)
    sample: List[List[str]] = []
    with _open_text(path) as f:
        for i, row in enumerate(csv.reader(_nul_guard(f), delimiter=delim)):
            if i > 0 and (not row or all(c == "" for c in row)):
                continue
            sample.append(row)
            if len(sample) > _HEADER_SAMPLE_ROWS:
                break
    if not sample:
        return TableLayout(delim, [], "header", header_row=True)
    first = sample[0]
    if _line1_is_header(first, sample[1:]):
        return TableLayout(delim, [c.strip() for c in first], "header", header_row=True)
    width = max(len(r) for r in sample)
    return TableLayout(delim, [f"column_{i + 1}" for i in range(width)], "generated", header_row=False)


def _iter_table(path: str, layout: Optional[TableLayout] = None) -> Iterator[List[str]]:
    """THE delimited-table parse shared by the profiler and the paged rows reader:
    yields the column names first (see :func:`_table_layout`), then every non-blank data row
    as-is. With a header row, line 1 is consumed as the names; without one it is data."""
    lay = layout or _table_layout(path)
    yield list(lay.names)
    with _open_text(path) as f:
        if lay.spec:
            for row in _spec_reader(_spec_lines(f), lay.delim):
                if row and not all(c == "" for c in row):
                    yield row
            return
        for i, row in enumerate(csv.reader(_nul_guard(f), delimiter=lay.delim)):
            if i == 0 and lay.header_row:
                continue
            if not row or all(c == "" for c in row):
                continue
            yield row


def _read_table(
    path: str, max_rows: int = MAX_TABLE_ROWS, layout: Optional[TableLayout] = None
) -> Tuple[List[str], List[List[str]], int]:
    """(header, first ``max_rows`` rows, TRUE total data-row count)."""
    it = _iter_table(path, layout)
    header = next(it, [])
    rows: List[List[str]] = []
    total = 0
    for row in it:
        total += 1
        if len(rows) < max_rows:
            rows.append(row)
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
    counted in ``stats["bad"]``."""
    stats.setdefault("bad", 0)
    with _open_text(path) as f:
        for line in f:
            line = line.strip()
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
    lists/objects as compact JSON."""
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
    if stats.get("bad") and not total:
        raise ValueError(f"no valid JSON lines ({stats['bad']} unparseable)")
    return keys, [[_jsonl_cell(r.get(k)) for k in keys] for r in records], total


# Hard cap on one page of the paged rows reader (the UI asks for ~200 at a time).
MAX_ROWS_PAGE = 1000
# Version of how read_rows turns bytes into columns + rows. Cached page metadata (columns, total)
# written under another version is not reused. Bump when the parse changes what a row is.
READ_ROWS_VERSION = "2026-11-11.header-inference"


def read_rows(
    path: str,
    offset: int = 0,
    limit: int = 200,
    *,
    known: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """One page of a table-like file's FULL rows, parsed exactly as the profiler parses it.

    Returns ``{kind, tabular, columns, rows, offset, limit, totalRows}`` (tables also carry
    ``headerRow`` — whether line 1 is a header record, which the edit route needs to number data
    rows — and ``namesSource``: header | comment | spec | generated). ``known`` is a
    previously returned ``{"columns", "totalRows"}`` for the same bytes: with it the read
    stops once the page is filled (the total and the JSONL key union need a full pass,
    which ``known`` already carries). Non-tabular kinds return ``tabular: False``.
    """
    try:
        return _read_rows(path, offset, limit, known=known)
    except BinaryContent:
        return {"kind": "unknown", "tabular": False, "reason": "binary"}


def _read_rows(
    path: str,
    offset: int = 0,
    limit: int = 200,
    *,
    known: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    kind = _sniff_kind(path)
    if kind not in ("table", "jsonl"):
        return {"kind": kind, "tabular": False}
    layout: Optional[TableLayout] = None
    if kind == "table":
        try:
            layout = _table_layout(path)
        except BinaryContent:
            raise
        except Exception:  # noqa: BLE001
            if _spec_of(path) is None:
                raise
            layout = None
        if layout is None or not layout.valid:
            # A file named as a spec format (.bed, .gtf, …) whose lines do not follow it is not a
            # table: the caller falls back to the text preview instead of showing a parse error.
            return {"kind": kind, "tabular": False, "reason": "spec_mismatch"}
    offset = max(0, int(offset))
    limit = max(1, min(int(limit), MAX_ROWS_PAGE))
    end = offset + limit
    total = 0
    out: Dict[str, Any] = {"kind": kind, "tabular": True, "offset": offset, "limit": limit}
    if kind == "table":
        out["headerRow"] = layout.header_row
        out["namesSource"] = layout.names_source
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


def _find_col(header: Sequence[str], tokens: Sequence[str]) -> Optional[int]:
    """Return the index of the first column whose name matches a token as a
    whole token; falls back to substring. Returns None if none match."""
    low = [h.lower() for h in header]
    # whole-token match first (avoids 'id' matching 'width')
    for i, h in enumerate(low):
        parts = set(h.replace("-", "_").split("_"))
        if any(tok in parts or h == tok for tok in tokens):
            return i
    # substring fallback (e.g. 'sample_id')
    for i, h in enumerate(low):
        if any(tok in h for tok in tokens):
            return i
    return None


def _named(cols: Sequence[str]) -> List[str]:
    return [str(c) for c in cols[:_MAX_NAMED_COLUMNS]]


# A column is a "table column" when at least this share of its values are lists of lists.
NESTED_TABLE_MIN_FRAC = 0.5
# Row-cap signal: most tables sit exactly at the maximum row count (extraction truncation).
NESTED_ROW_CAP_FRAC = 0.5
NESTED_BLANK_NOTE_FRAC = 0.3


def _nested_table_findings(p: "DataProfile", header: Sequence[str], rows: Sequence[Sequence[str]]) -> bool:
    """JSONL columns whose values are tables (lists of lists): size summary, a likely row cap, and the
    blank-cell share. Generic — no field names. Returns True when a Watch-level signal was emitted.
    (epar_study_tables.jsonl, 2026-11-11: 69% of 2,281 tables had exactly 7 rows because the extractor
    kept t[1:8]; nothing reported it.)"""
    watch = False
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
        nrows = sorted(len(m) for m in mats)
        ncols = sorted(max((len(x) for x in m), default=0) for m in mats)
        med = lambda xs: xs[len(xs) // 2]
        emit(p, "note", "nested_tables",
             f"Column {name!r}: {len(mats):,} embedded tables, median {med(nrows)} rows × {med(ncols)} columns "
             f"(largest {nrows[-1]} rows).",
             column=str(name), tables=len(mats), median_rows=med(nrows), median_cols=med(ncols), max_rows=nrows[-1])
        at_max = sum(1 for n in nrows if n == nrows[-1])
        if nrows[-1] >= 3 and nrows[0] < nrows[-1] and at_max / len(nrows) >= NESTED_ROW_CAP_FRAC:
            pct = int(round(100 * at_max / len(nrows)))
            emit(p, "signal", "nested_row_cap",
                 f"{pct}% of the tables in column {name!r} have exactly {nrows[-1]} rows, the maximum: they were "
                 f"probably cut off when extracted. Check the extraction before analysing them.",
                 "watch", column=str(name), pct=pct, max_rows=nrows[-1], tables=len(mats))
            watch = True
        cells = [x for m in mats for row in m for x in row]
        if cells:
            blank = sum(1 for x in cells if x is None or not str(x).strip()) / len(cells)
            if blank >= NESTED_BLANK_NOTE_FRAC:
                emit(p, "note", "nested_blank_cells",
                     f"{int(round(100 * blank))}% of the cells in the tables of column {name!r} are blank — typical of merged "
                     f"or multi-line cells in extracted tables; join continuation rows before analysis.",
                     column=str(name), pct=int(round(100 * blank)))
    return watch


def _profile_table(path: str, reader=None, layout: Optional[TableLayout] = None) -> DataProfile:
    p = DataProfile()
    if reader is not None:
        header, rows, total = reader(path)
    else:
        layout = layout or _table_layout(path)
        header, rows, total = _read_table(path, layout=layout)
    n_rows = len(rows)  # rows held for statistics (≤ MAX_TABLE_ROWS)
    n_cols = len(header)
    p.rows = total
    p.cols = n_cols
    if total > n_rows:
        p.profiled_rows = n_rows

    if n_cols == 0:
        p.quality = "blocked"
        emit(p, "note", "no_columns", "No columns parsed from table.", "blocked")
        return p
    if n_rows == 0:
        # Header present but no data rows: this is a readable (if empty) table,
        # NOT an unprofilable file. Surface the columns so the Preview/Columns
        # views and the stat grid show the real header (cols = n_cols, rows = 0)
        # instead of "analyzer cannot read this dataset".
        p.columns = [str(c) for c in header[:MAX_PREVIEW_COLS]]
        p.sample_rows = []
        if layout is not None and not layout.header_row:
            _column_names_finding(p, layout)
            emit(p, "note", "table_summary", f"{total:,} rows × {n_cols} columns.", rows=total, cols=n_cols)
        else:
            emit(p, "note", "header_only", "Header present; no data rows yet.")
        return p

    # Small tabular sample for the Preview tab (columns + first rows), capped.
    p.columns = [str(c) for c in header[:MAX_PREVIEW_COLS]]
    p.sample_rows = [
        [_preview_cell(c) for c in r[:MAX_PREVIEW_COLS]] for r in rows[:MAX_PREVIEW_ROWS]
    ]
    if layout is not None:
        _column_names_finding(p, layout)
    if layout is not None and layout.spec:
        # A spec format (BED, GTF, SMILES, …): its columns are defined by the format, so the
        # classification checks (label / leakage / balance) and placeholder-column statistics
        # (BED score 0, strand ".") do not apply. Format findings are added by the caller.
        _set_dedup_effective_n(p, rows)
        emit(p, "note", "table_summary", f"{total:,} rows × {n_cols} columns.", rows=total, cols=n_cols)
        if p.profiled_rows is not None:
            emit(p, "note", "profiled_subset",
                 f"Statistics were computed on the first {n_rows:,} of {total:,} rows.",
                 profiled=n_rows, rows=total)
        return p

    watch = False

    # --- constant / high-missingness columns (numeric-first signal) ---
    near_constant: List[str] = []
    high_missing: List[str] = []
    for j in range(n_cols):
        col = _column(rows, j)
        non_missing = [v for v in col if v not in ("", "NA", "NaN", "nan", "null", "None")]
        missing_frac = 1.0 - (len(non_missing) / n_rows) if n_rows else 0.0
        if missing_frac >= HIGH_MISSING_FRAC:
            high_missing.append(header[j])
        if non_missing:
            top = Counter(non_missing).most_common(1)[0][1]
            if top / len(non_missing) >= NEAR_CONSTANT_FRAC:
                near_constant.append(header[j])
    if near_constant:
        emit(
            p, "signal", "near_constant",
            f"{len(near_constant)} column(s) are near-constant (>{int(NEAR_CONSTANT_FRAC*100)}% single value): "
            + ", ".join(_named(near_constant)) + ".",
            "watch", count=len(near_constant), columns=_named(near_constant),
            pct=int(NEAR_CONSTANT_FRAC * 100),
        )
        watch = True
    if high_missing:
        emit(
            p, "signal", "high_missing",
            f"{len(high_missing)} column(s) have ≥{int(HIGH_MISSING_FRAC*100)}% missing values: "
            + ", ".join(_named(high_missing)) + ".",
            "watch", count=len(high_missing), columns=_named(high_missing),
            pct=int(HIGH_MISSING_FRAC * 100),
        )
        watch = True

    # --- locate label column ---
    label_idx = _find_col(header, _LABEL_NAME_TOKENS)
    if label_idx is not None:
        label_col = _column(rows, label_idx)
        distinct_labels = set(v for v in label_col if v != "")
        # Only treat as a classification target if it's low-cardinality.
        if 2 <= len(distinct_labels) <= max(20, int(0.1 * n_rows)):
            counts = Counter(v for v in label_col if v != "")
            total_labelled = sum(counts.values())
            balance = [(lbl, cnt / total_labelled) for lbl, cnt in counts.most_common()]
            p.class_balance = [(lbl, round(frac, 4)) for lbl, frac in balance]

            # normalize near-duplicate label spellings for a note
            norm_map: Dict[str, List[str]] = {}
            for lbl in distinct_labels:
                norm_map.setdefault(lbl.strip().lower(), []).append(lbl)
            dup_spellings = [v for v in norm_map.values() if len(v) > 1]
            if dup_spellings:
                watch = True
                example = sorted(dup_spellings[0])
                emit(p, "note", "label_spellings",
                     f"Two spellings of the same label: {example[0]!r} and {example[1]!r}.",
                     "watch", a=example[0], b=example[1])

            minority_frac = min(frac for _, frac in balance)
            majority_frac = max(frac for _, frac in balance)
            if minority_frac < IMBALANCE_MINORITY_RATIO * majority_frac:
                watch = True
                minority_label = min(balance, key=lambda kv: kv[1])[0]
                emit(p, "note", "minority_class",
                     f"{minority_label!r} class is {minority_frac*100:.0f}% — consider a balanced sampler.",
                     "watch", label=minority_label, pct=int(round(minority_frac * 100)))

            # --- leakage checks (need a label) ---
            _detect_leakage(p, header, rows, label_idx, label_col)
            if p.leakage_detail:
                watch = True

            # --- effective N ---
            eff_n, reason, unique = _effective_n(rows, label_col, balance)
            p.effective_n = eff_n
            p.effective_n_reason = reason
            p.duplicate_rows = n_rows - unique
            if eff_n < 0.75 * n_rows:
                watch = True
                if reason == "imbalance":
                    emit(p, "note", "effective_n_imbalance",
                         f"Effective N ({eff_n}) is far below {n_rows:,} rows — bounded by the "
                         "minority class under strong imbalance.",
                         "watch", n=eff_n, rows=n_rows)
                else:
                    emit(p, "note", "effective_n_dedup",
                         f"Effective N ({eff_n}) is below {n_rows:,} rows — duplicate rows "
                         f"reduce independent samples ({n_rows - unique} duplicate(s)).",
                         "watch", n=eff_n, rows=n_rows, duplicates=n_rows - unique)
        else:
            emit(p, "signal", "label_free_text",
                 f"Column {header[label_idx]!r} looks like a label but has "
                 f"{len(distinct_labels)} distinct values — treated as free-text, not a class target.",
                 column=header[label_idx], distinct=len(distinct_labels))
            _set_dedup_effective_n(p, rows)
    else:
        _set_dedup_effective_n(p, rows)  # no label: effective N is the unique row count

    # --- nested tables in JSON Lines (a column of lists-of-lists, e.g. extracted PDF tables) ---
    if reader is _read_jsonl and _nested_table_findings(p, header, rows):
        watch = True

    if watch and p.quality == "good":
        p.quality = "watch"
    # Where the column names came from is context, not an issue: it does not displace the summary.
    if not any(f["section"] == "note" and not f["code"].startswith("columns_") for f in p.findings):
        # "No issues" only when nothing was flagged — the signal list (near-constant / missing
        # columns) was ignored here, so the card said "no constant-column issues" beside a
        # near-constant-column warning.
        if p.signal_summary:
            emit(p, "note", "table_summary", f"{total:,} rows × {n_cols} columns.", rows=total, cols=n_cols)
        else:
            emit(p, "note", "table_clean",
                 f"{total:,} rows × {n_cols} columns; no leakage, imbalance, or constant-column issues detected.",
                 rows=total, cols=n_cols)
    if p.profiled_rows is not None:
        emit(p, "note", "profiled_subset",
             f"Statistics were computed on the first {n_rows:,} of {total:,} rows.",
             profiled=n_rows, rows=total)
    return p


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


def _set_dedup_effective_n(p: DataProfile, rows: Sequence[Sequence[str]]) -> None:
    unique = _dedup_count(rows)
    p.effective_n = unique
    p.effective_n_reason = "dedup"
    p.duplicate_rows = len(rows) - unique


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
    batch_idx = _find_col(header, _BATCH_NAME_TOKENS)

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
        # Leakage = the column predicts the label for rows it has NOT memorised, well beyond the
        # majority-class baseline. (Scoring each value by its own rows' majority made every
        # unique-per-row measurement — a float column — "perfectly predict" any label.)
        if (acc >= LEAKAGE_ACC_THRESHOLD and (acc - base) >= 0.5 * (1.0 - base) and acc > base
                and total >= max(4, int(0.5 * n_rows))):
            if distinct_vals >= 0.95 * total:
                emit(p, "leakage", "leaked_id",
                     f"column {header[j]!r} is (near-)unique per row and perfectly predicts the label — leaked id.",
                     "watch", column=header[j])
            else:
                emit(p, "leakage", "leaked_feature",
                     f"column {header[j]!r} predicts the label at {acc*100:.0f}% — target leaked into features.",
                     "watch", column=header[j], pct=int(round(acc * 100)))
            emit(p, "plan", "drop_leaky_column", f"{header[j]} leaks the label",
                 effect_text=f"drop {header[j]!r} before modelling", column=header[j])
            leaked_feature = True
            break  # one is enough to flag

    # 3. batch<->label confound
    if batch_idx is not None and batch_idx != label_idx and not leaked_feature:
        batch_col = _column(rows, batch_idx)
        distinct = len(set(v for v in batch_col if v != ""))
        if 2 <= distinct <= max(2, int(BATCH_MAX_DISTINCT_FRAC * n_rows)):
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
            if purity >= BATCH_CONFOUND_PURITY:
                emit(p, "leakage", "batch_confound",
                     f"{header[batch_idx]!r} (batch/id) is (near-)perfectly correlated with the outcome label.",
                     "watch", column=header[batch_idx])
                emit(p, "plan", "batch_covariate", f"{header[batch_idx]}–label leakage",
                     effect_text=f"add {header[batch_idx]!r} as a covariate before modelling",
                     column=header[batch_idx])

    # 1. train/test overlap across a split column
    split_idx = _find_col(header, _SPLIT_NAME_TOKENS)
    if split_idx is not None and split_idx != label_idx:
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
