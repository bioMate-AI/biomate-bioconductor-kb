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
from typing import Any, Dict, List, Optional, Sequence, Tuple

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
MAX_PREVIEW_ROWS = 8

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
        p = DataProfile(quality="blocked")
        p.notes.append(f"File not found: {path!r}." if path else "No dataset path provided.")
        return p

    try:
        size = os.path.getsize(path)
    except OSError:
        size = -1
    if size == 0:
        p = DataProfile(quality="blocked")
        p.notes.append("File is empty (0 bytes).")
        return p

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
        # Unknown / non-profilable — degrade honestly.
        p = DataProfile(quality="watch")
        p.notes.append(
            f"File type not profilable ({os.path.basename(path)}); "
            "reported shape only, no leakage/balance derived."
        )
        return p
    except Exception as e:  # noqa: BLE001 — defensive: profiling must never crash ingest.
        log.warning("[perception] profiling failed for %s: %s", path, e)
        p = DataProfile(quality="blocked")
        p.notes.append(f"Could not parse file: {e}")
        return p


def _profile_structured(path: str, kind: str) -> DataProfile:
    """Structural validation, not a claim about scientific dataset quality."""
    p = DataProfile(quality="watch")
    with _open_text(path) as handle:
        text = handle.read(2 * 1024 * 1024 + 1)
    if len(text) > 2 * 1024 * 1024:
        p.notes.append("Structured validation is limited to files under 2 million characters; download for complete validation.")
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
    p.notes.append(f"Valid {kind.upper()} syntax; {root} root. Structural checks only; scientific quality has not been assessed.")
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
    """Return one of: 'fastq', 'vcf', 'table', 'unknown'."""
    lower = _strip_gz(path.lower())
    _, ext = os.path.splitext(lower)
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
    p.signal_summary = [
        f"{count_word}{n_reads:,} reads scanned; mean read length {mean_len:.0f} bp.",
        f"Mean base quality Phred {mean_q:.1f} (sampled).",
    ]
    # Single-end vs paired-end can't be known from one file — state honestly.
    p.notes.append("Single FASTQ file profiled — single-end unless a mate file is present.")
    p.plan_impact.append(
        ("single FASTQ observed", "suggested single-end pipeline (override if paired mate exists)")
    )

    if mean_q and mean_q < 20:
        p.quality = "watch"
        p.notes.append(f"Mean base quality Phred {mean_q:.1f} is below 20 — consider trimming.")
    if n_reads == 0:
        p.quality = "blocked"
        p.notes.append("No FASTQ records parsed — file may be malformed.")
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
    p.signal_summary = [
        f"{n_variants:,} variant records across {n_samples} sample(s).",
    ]
    p.notes.append(f"VCF with {n_variants:,} variants, {n_samples} genotyped sample(s).")
    if n_variants == 0:
        p.quality = "watch"
        p.notes.append("No variant records found (header only).")
    p.plan_impact.append(
        (f"{n_variants:,} variants / {n_samples} samples", "sized variant-annotation / filtering plan")
    )
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


def _read_table(path: str) -> Tuple[List[str], List[List[str]]]:
    delim = _sniff_delimiter(path)
    header: List[str] = []
    rows: List[List[str]] = []
    with _open_text(path) as f:
        reader = csv.reader(f, delimiter=delim)
        for i, row in enumerate(reader):
            if i == 0:
                header = [c.strip() for c in row]
                continue
            if not row or all(c == "" for c in row):
                continue
            rows.append(row)
            if len(rows) >= MAX_TABLE_ROWS:
                break
    return header, rows


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


def _profile_table(path: str) -> DataProfile:
    p = DataProfile()
    header, rows = _read_table(path)
    n_rows = len(rows)
    n_cols = len(header)
    p.rows = n_rows
    p.cols = n_cols

    if n_cols == 0:
        p.quality = "blocked"
        p.notes.append("No columns parsed from table.")
        return p
    if n_rows == 0:
        p.quality = "blocked"
        p.notes.append("File parsed to 0 rows — header present but no data records.")
        return p

    # Small tabular sample for the Preview tab (columns + first rows), capped.
    p.columns = [str(c) for c in header[:MAX_PREVIEW_COLS]]
    p.sample_rows = [
        [str(c) for c in r[:MAX_PREVIEW_COLS]] for r in rows[:MAX_PREVIEW_ROWS]
    ]

    signal: List[str] = []
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
        signal.append(
            f"{len(near_constant)} column(s) are near-constant (>{int(NEAR_CONSTANT_FRAC*100)}% single value)."
        )
        watch = True
    if high_missing:
        signal.append(
            f"{len(high_missing)} column(s) have ≥{int(HIGH_MISSING_FRAC*100)}% missing values."
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
            total = sum(counts.values())
            balance = [(lbl, cnt / total) for lbl, cnt in counts.most_common()]
            p.class_balance = [(lbl, round(frac, 4)) for lbl, frac in balance]

            # normalize near-duplicate label spellings for a note
            norm_map: Dict[str, List[str]] = {}
            for lbl in distinct_labels:
                norm_map.setdefault(lbl.strip().lower(), []).append(lbl)
            dup_spellings = [v for v in norm_map.values() if len(v) > 1]
            if dup_spellings:
                watch = True
                example = dup_spellings[0]
                p.notes.append(
                    f"Two spellings of the same label: {example[0]!r} and {example[1]!r}."
                )

            minority_frac = min(frac for _, frac in balance)
            if minority_frac < IMBALANCE_MINORITY_FRAC:
                watch = True
                minority_label = min(balance, key=lambda kv: kv[1])[0]
                p.notes.append(
                    f"{minority_label!r} class is {minority_frac*100:.0f}% — consider a balanced sampler."
                )

            # --- leakage checks (need a label) ---
            _detect_leakage(p, header, rows, label_idx, label_col)
            if p.leakage_detail:
                watch = True

            # --- effective N ---
            eff_n, eff_note = _effective_n(rows, label_col, balance)
            p.effective_n = eff_n
            if eff_note:
                p.notes.append(eff_note)
                watch = True
        else:
            signal.append(
                f"Column {header[label_idx]!r} looks like a label but has "
                f"{len(distinct_labels)} distinct values — treated as free-text, not a class target."
            )
            p.effective_n = _dedup_count(rows)
    else:
        p.effective_n = _dedup_count(rows)  # no label: effective N is the unique row count

    if signal:
        p.signal_summary = signal
    if watch and p.quality == "good":
        p.quality = "watch"
    if not p.notes:
        p.notes.append(
            f"{n_rows:,} rows × {n_cols} columns; no leakage, imbalance, or constant-column issues detected."
        )
    return p


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
    """Populate p.leakage_detail / plan_impact from three leakage heuristics.

    1. train/test overlap — duplicate feature-rows appearing in >1 split value.
    2. target leaked into a feature — a single column predicts the label at
       >= LEAKAGE_ACC_THRESHOLD accuracy.
    3. batch<->label confound — a batch/id column whose values map (near-)purely
       onto the label.
    """
    n_rows = len(rows)
    findings: List[str] = []

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
                findings.append(
                    f"column {header[j]!r} is (near-)unique per row and perfectly predicts the label — leaked id."
                )
            else:
                findings.append(
                    f"column {header[j]!r} predicts the label at {acc*100:.0f}% — target leaked into features."
                )
            p.plan_impact.append(
                (f"{header[j]} leaks the label", f"drop {header[j]!r} before modelling")
            )
            break  # one is enough to flag

    # 3. batch<->label confound
    if batch_idx is not None and batch_idx != label_idx and not findings:
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
                findings.append(
                    f"{header[batch_idx]!r} (batch/id) is (near-)perfectly correlated with the outcome label."
                )
                p.plan_impact.append(
                    (
                        f"{header[batch_idx]}–label leakage",
                        f"add {header[batch_idx]!r} as a covariate before modelling",
                    )
                )

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
                findings.append(
                    f"{overlap} feature-row(s) appear in more than one split — train/test overlap."
                )
                p.plan_impact.append(
                    ("train/test overlap", "de-duplicated rows across splits before evaluation")
                )

    if findings:
        # frontend leakage is a single detail string — join concisely.
        p.leakage_detail = " ".join(findings)


def _effective_n(
    rows: Sequence[Sequence[str]],
    label_col: Sequence[str],
    balance: Sequence[Tuple[str, float]],
) -> Tuple[int, Optional[str]]:
    """Estimate effective sample size and an optional explanatory note.

    Combines two deterministic reductions and reports the binding (smallest):
      * dedup — exact duplicate rows count once.
      * imbalance — for classification, usable N is bounded by the minority
        class (a 7/93 split of 300 rows carries ~ the information of the ~2*21
        balanced examples, generalized to k*min for k classes).
    We note it when the effective N is well below the raw row count.
    """
    n_rows = len(rows)

    unique = _dedup_count(rows)
    candidates: List[Tuple[int, str]] = [(unique, "dedup")]

    if balance:
        counts = Counter(v for v in label_col if v != "")
        minority = min(counts.values()) if counts else n_rows
        k = len(counts)
        candidates.append((k * minority, "imbalance"))

    eff = min(c for c, _ in candidates)
    eff = max(1, min(eff, n_rows))

    note: Optional[str] = None
    if eff < 0.75 * n_rows:
        reason = min(candidates, key=lambda c: c[0])[1]
        if reason == "imbalance":
            note = (
                f"Effective N ({eff}) is far below {n_rows:,} rows — bounded by the "
                "minority class under strong imbalance."
            )
        else:
            note = (
                f"Effective N ({eff}) is below {n_rows:,} rows — duplicate rows "
                f"reduce independent samples ({n_rows - unique} duplicate(s))."
            )
    return eff, note
