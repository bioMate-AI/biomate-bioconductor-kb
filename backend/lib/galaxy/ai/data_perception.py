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
    if not path or not os.path.exists(path):
        if path:
            return blocked_profile("file_not_found", f"File not found: {path!r}.")
        return blocked_profile("no_path", "No dataset path provided.")

    try:
        size = os.path.getsize(path)
    except OSError:
        size = -1
    if size == 0:
        return blocked_profile("empty_file", "File is empty (0 bytes).")

    kind = _sniff_kind(path)
    try:
        if kind in ("json", "yaml"):
            return _profile_structured(path, kind)
        if kind == "fastq":
            return _profile_fastq(path)
        if kind == "vcf":
            return _profile_vcf(path)
        if kind == "table":
            return _profile_table(path)
        if kind == "jsonl":
            return _profile_table(path, reader=_read_jsonl)
        # Unknown / non-profilable — degrade honestly.
        p = DataProfile(quality="watch")
        emit(
            p, "note", "unprofilable",
            f"File type not profilable ({os.path.basename(path)}); "
            "reported shape only, no leakage/balance derived.",
            "watch", name=os.path.basename(path),
        )
        return p
    except Exception as e:  # noqa: BLE001 — defensive: profiling must never crash ingest.
        log.warning("[perception] profiling failed for %s: %s", path, e)
        return blocked_profile("parse_failed", f"Could not parse file: {e}", error=str(e)[:300])


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
def _open_text(path: str) -> io.TextIOBase:
    if path.endswith(".gz"):
        return gzip.open(path, "rt", encoding="utf-8", errors="replace")
    return open(path, "rt", encoding="utf-8", errors="replace")


def _strip_gz(name: str) -> str:
    return name[:-3] if name.endswith(".gz") else name


def _sniff_kind(path: str) -> str:
    """Return one of: 'json', 'yaml', 'jsonl', 'fastq', 'vcf', 'table', 'unknown'."""
    lower = _strip_gz(path.lower())
    _, ext = os.path.splitext(lower)
    if ext in (".jsonl", ".ndjson"):
        return "jsonl"
    if ext in (".json", ".yaml", ".yml"):
        return "json" if ext == ".json" else "yaml"
    if ext in (".fastq", ".fq"):
        return "fastq"
    if ext == ".vcf":
        return "vcf"
    if ext in (".csv", ".tsv", ".txt", ".tab"):
        return "table"

    # Content sniff for extension-less or ambiguous files.
    try:
        with _open_text(path) as f:
            head = f.readline()
            second = f.readline()
    except Exception:
        return "unknown"
    if head.startswith("##fileformat=VCF") or head.startswith("#CHROM"):
        return "vcf"
    if head.startswith("@") and second and set(second.strip()) <= set("ACGTNacgtn"):
        return "fastq"
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


def _iter_table(path: str) -> Iterator[List[str]]:
    """THE delimited-table parse shared by the profiler and the paged rows reader:
    yields the header (cells stripped) first, then every non-blank data row as-is."""
    delim = _sniff_delimiter(path)
    with _open_text(path) as f:
        for i, row in enumerate(csv.reader(f, delimiter=delim)):
            if i == 0:
                yield [c.strip() for c in row]
                continue
            if not row or all(c == "" for c in row):
                continue
            yield row


def _read_table(path: str, max_rows: int = MAX_TABLE_ROWS) -> Tuple[List[str], List[List[str]], int]:
    """(header, first ``max_rows`` rows, TRUE total data-row count)."""
    it = _iter_table(path)
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


def read_rows(
    path: str,
    offset: int = 0,
    limit: int = 200,
    *,
    known: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """One page of a table-like file's FULL rows, parsed exactly as the profiler parses it.

    Returns ``{kind, tabular, columns, rows, offset, limit, totalRows}``. ``known`` is a
    previously returned ``{"columns", "totalRows"}`` for the same bytes: with it the read
    stops once the page is filled (the total and the JSONL key union need a full pass,
    which ``known`` already carries). Non-tabular kinds return ``tabular: False``.
    """
    kind = _sniff_kind(path)
    if kind not in ("table", "jsonl"):
        return {"kind": kind, "tabular": False}
    offset = max(0, int(offset))
    limit = max(1, min(int(limit), MAX_ROWS_PAGE))
    end = offset + limit
    total = 0
    out: Dict[str, Any] = {"kind": kind, "tabular": True, "offset": offset, "limit": limit}
    if kind == "table":
        it = _iter_table(path)
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


def _profile_table(path: str, reader=None) -> DataProfile:
    p = DataProfile()
    header, rows, total = (reader or _read_table)(path)
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
        emit(p, "note", "header_only", "Header present; no data rows yet.")
        return p

    # Small tabular sample for the Preview tab (columns + first rows), capped.
    p.columns = [str(c) for c in header[:MAX_PREVIEW_COLS]]
    p.sample_rows = [
        [_preview_cell(c) for c in r[:MAX_PREVIEW_COLS]] for r in rows[:MAX_PREVIEW_ROWS]
    ]

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
            if minority_frac < IMBALANCE_MINORITY_FRAC:
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

    if watch and p.quality == "good":
        p.quality = "watch"
    if not p.notes:
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
        correct = 0
        total = 0
        for _v, lblcounts in per_value.items():
            total += sum(lblcounts.values())
            correct += lblcounts.most_common(1)[0][1]
        acc = correct / total if total else 0.0
        distinct_vals = len(per_value)
        if acc >= LEAKAGE_ACC_THRESHOLD and total >= max(4, int(0.5 * n_rows)):
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
