"""
Dataset loading for the ML training platform.

Public datasets are fetched via Therapeutics Data Commons (TDC) when available;
a small bundled offline fixture (`HERG_FIXTURE`) lets the config/orchestration
unit tests run with zero network and zero TDC install.

A loaded dataset is a plain list of `(smiles, label)` rows plus a splits dict —
no pandas/numpy required at this layer, so tests stay dependency-free.
"""
from __future__ import annotations

import csv
import logging
import math
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from .config import DatasetSpec, ConfigError

log_stage = logging.getLogger(__name__)


def stage_s3_to_local(s3_uri: str, dest: Optional[str] = None) -> str:
    """Download an ``s3://`` object to a local file and return its path.

    The ml_training loaders were written assuming the executor stages s3 inputs
    into the work dir, but the ml_training ``.nf`` interpolates ``params.dataset``
    as a plain value (no ``path`` input), so Nextflow never stages it. The Batch
    container ships the AWS CLI and runs under an IAM role that can read the
    work bucket, so the loader stages the object itself. Idempotent per-URI: the
    default local name is prefixed with a hash of the FULL URI, so two objects that
    share a basename (``s3://a/train.csv`` vs ``s3://b/train.csv``) do NOT collide and
    reuse each other's data (committee finding — cross-run data leakage).
    """
    if not s3_uri.startswith("s3://"):
        raise ValueError(f"not an s3 uri: {s3_uri}")
    if dest:
        target = dest
    else:
        import hashlib
        _h = hashlib.sha1(s3_uri.encode("utf-8")).hexdigest()[:10]
        target = f"{_h}_{Path(s3_uri).name}"   # URI-unique, keeps the extension for parsers
    if Path(target).exists() and Path(target).stat().st_size > 0:
        return target
    try:
        subprocess.run(
            ["aws", "s3", "cp", s3_uri, target],
            check=True, capture_output=True, text=True,
        )
    except FileNotFoundError as exc:  # aws CLI missing (non-Batch env)
        raise FileNotFoundError(
            f"cannot stage {s3_uri}: the AWS CLI is not available in this "
            f"environment (expected in the ml-training Batch image)"
        ) from exc
    except subprocess.CalledProcessError as exc:
        raise FileNotFoundError(
            f"failed to stage {s3_uri} via 'aws s3 cp' "
            f"(exit {exc.returncode}): {(exc.stderr or '').strip()[:300]}"
        ) from exc
    if not (Path(target).exists() and Path(target).stat().st_size > 0):
        raise FileNotFoundError(f"staged file {target} missing/empty after download of {s3_uri}")
    log_stage.info("[ml_training] staged %s -> %s (%d bytes)", s3_uri, target, Path(target).stat().st_size)
    return target

log = logging.getLogger(__name__)


@dataclass
class LoadedDataset:
    rows: list[tuple[str, float]]           # [(smiles, label), ...]
    smiles_col: str
    target_col: str
    source: str                             # human-readable provenance

    def __len__(self) -> int:
        return len(self.rows)

    @property
    def smiles(self) -> list[str]:
        return [s for s, _ in self.rows]

    @property
    def labels(self) -> list[float]:
        return [y for _, y in self.rows]


# A tiny, real hERG-style fixture (SMILES + binary blocker label) for offline
# tests. NOT a training set — just enough rows to exercise the plumbing.
HERG_FIXTURE: list[tuple[str, float]] = [
    ("CC(=O)Oc1ccccc1C(=O)O", 0.0),                       # aspirin — non-blocker
    ("CN1C=NC2=C1C(=O)N(C(=O)N2C)C", 0.0),                # caffeine — non-blocker
    ("Clc1ccccc1C1=NCC(=O)Nc2ccc(cc21)[N+](=O)[O-]", 1.0),  # clonazepam-like
    ("CCN(CC)CCNC(=O)c1cc(Cl)c(N)cc1OC", 0.0),            # metoclopramide-like
    ("COc1ccc2[nH]cc(CCN)c2c1", 0.0),                     # 5-MeO-tryptamine
    ("CN(C)CCC=C1c2ccccc2CCc2ccccc21", 1.0),              # amitriptyline — blocker
    ("Fc1ccc(cc1)C(=O)CCCN1CCC(CC1)(O)c1ccc(Cl)cc1", 1.0),  # haloperidol — blocker
    ("CC(C)NCC(O)COc1cccc2ccccc12", 1.0),                 # propranolol — blocker
]


def load_dataset(spec: DatasetSpec) -> LoadedDataset:
    """Load a dataset described by a DatasetSpec.

    Dispatches on spec.source_kind(): name -> public loader, path -> CSV,
    s3_uri -> staged download (production path; stubbed here).
    """
    kind = spec.source_kind()
    if kind == "name":
        return _load_named(spec)
    if kind == "path":
        return _load_csv(spec, spec.path)  # type: ignore[arg-type]
    if kind == "s3_uri":
        return _load_s3(spec)
    raise ConfigError(f"unhandled dataset source kind: {kind}")


def _load_named(spec: DatasetSpec) -> LoadedDataset:
    name = (spec.name or "").strip()
    lname = name.lower()
    # Offline fixture shortcut — used by tests and for a no-network smoke run.
    if lname in ("fixture:herg", "herg:fixture"):
        return LoadedDataset(list(HERG_FIXTURE), spec.smiles_col, spec.target_col,
                             source="offline HERG_FIXTURE")
    if lname.startswith("tdc:"):
        return _load_tdc(name.split(":", 1)[1], spec)
    raise ConfigError(
        f"unknown named dataset '{name}'. Use 'tdc:<name>' (e.g. tdc:hERG) "
        f"or 'fixture:herg' for the offline test fixture."
    )


def _load_tdc(tdc_name: str, spec: DatasetSpec) -> LoadedDataset:
    """Load a public dataset via Therapeutics Data Commons.

    Lazy-imported and guarded: a missing `tdc` install raises a clear,
    actionable error rather than an ImportError at module load.
    """
    try:
        from tdc import single_pred  # noqa: F401
    except ImportError as e:
        raise ImportError(
            "PyTDC is required for public dataset loading. "
            "Install with `pip install PyTDC`, or use dataset name "
            "'fixture:herg' for the offline fixture."
        ) from e
    from tdc import single_pred
    # TDC single-pred datasets belong to different problem classes: hERG/AMES →
    # Tox, but Caco2/BBB/CYP/Lipophilicity/Solubility/PPBR → ADME, etc. Try the
    # common classes until one accepts the name (each raises if the name isn't
    # in its catalogue).
    last_err = None
    for cls_name in ("ADME", "Tox", "HTS"):
        cls = getattr(single_pred, cls_name, None)
        if cls is None:
            continue
        try:
            df = cls(name=tdc_name).get_data()
            rows = [(str(r["Drug"]), float(r["Y"])) for _, r in df.iterrows()]
            return LoadedDataset(rows, spec.smiles_col, spec.target_col,
                                 source=f"TDC:{cls_name}:{tdc_name} (n={len(rows)})")
        except Exception as e:  # name not in this class' catalogue — try the next
            last_err = e
    raise ConfigError(
        f"TDC dataset '{tdc_name}' not found in ADME/Tox/HTS catalogues: {last_err}"
    )


def _load_csv(spec: DatasetSpec, path: str) -> LoadedDataset:
    p = Path(path)
    if not p.exists():
        raise ConfigError(f"dataset path not found: {path}")
    rows: list[tuple[str, float]] = []
    with p.open(newline="") as fh:
        reader = csv.DictReader(fh)
        if spec.smiles_col not in (reader.fieldnames or []):
            raise ConfigError(
                f"smiles_col '{spec.smiles_col}' not in CSV columns {reader.fieldnames}"
            )
        if spec.target_col not in (reader.fieldnames or []):
            raise ConfigError(
                f"target_col '{spec.target_col}' not in CSV columns {reader.fieldnames}"
            )
        for row in reader:
            smi = row[spec.smiles_col]
            raw = row[spec.target_col]
            # _is_missing matches the broad token set (NA/nan/./…), not just
            # None/"" — otherwise float("NA") below crashes the whole load.
            if _is_missing(smi) or _is_missing(raw):
                continue
            try:
                val = float(raw)
            except (TypeError, ValueError):
                continue  # non-numeric property label (e.g. "inf"/"high") → skip row
            if not math.isfinite(val):
                continue  # inf/-inf target would poison a regression fit
            rows.append((str(smi), val))
    if not rows:
        raise ConfigError(f"no usable rows parsed from {path}")
    return LoadedDataset(rows, spec.smiles_col, spec.target_col, source=f"csv:{path}")


def _load_s3(spec: DatasetSpec) -> LoadedDataset:
    """Production path: download the staged CSV from S3, then parse as CSV.

    Stubbed for the PoC skeleton — the executor stages inputs to a local
    work dir before the training container runs, so in production this becomes
    a local CSV read. Left explicit so the seam is obvious.
    """
    raise NotImplementedError(
        "s3_uri loading is wired at execution time by the Nextflow executor "
        "(inputs are staged to a local work dir). Use path= for local runs."
    )


# ---------------------------------------------------------------------------
# Generic tabular datasets: numeric feature matrix + a label column
# (e.g. a gene-expression matrix with a subtype/outcome label) — NOT molecules.
# ---------------------------------------------------------------------------

@dataclass
class LoadedTabularDataset:
    X: list[list[float]]          # one row of numeric features per sample
    y: list                       # labels: str for classification, float for regression
    feature_names: list[str]
    target_col: str
    source: str
    task: str                     # 'classification' | 'regression'

    def __len__(self) -> int:
        return len(self.y)


_MISSING_TOKENS = {"", "na", "n/a", "nan", "null", "none", ".", "-"}


def _is_missing(v) -> bool:
    return v is None or (isinstance(v, str) and v.strip().lower() in _MISSING_TOKENS)


def _is_blank(v) -> bool:
    """Truly-absent cell: None or empty/whitespace string. Distinct from
    _is_missing, which also treats semantic tokens (NA/none/./-) as missing.
    A classification LABEL of "None"/"NA"/"-" may be a legitimate class, so the
    label row-skip uses _is_blank (never a real value), and only the regression
    path (where float("NA") would crash) drops the semantic-missing labels."""
    return v is None or (isinstance(v, str) and v.strip() == "")


def _looks_numeric(values) -> bool:
    """A column is numeric if every NON-MISSING value parses as a float. Common
    missing tokens (NA/N/A/NaN/NULL/./-) are treated as missing, NOT as evidence the
    column is non-numeric — otherwise one R-exported `NA` cell would drop a whole
    real gene column as 'id/metadata' (committee finding)."""
    for v in values:
        if _is_missing(v):
            continue
        try:
            float(v)
        except (TypeError, ValueError):
            return False
    return True


def load_tabular_dataset(path: str, target_col: str,
                         id_cols: Optional[list] = None,
                         task: Optional[str] = None) -> LoadedTabularDataset:
    """Load a generic feature-matrix CSV with a label column.

    Every column except ``target_col`` and any ``id_cols`` is treated as a
    numeric feature (e.g. one gene per column in an expression matrix). Rows
    missing the label are skipped; missing feature cells become 0.0. The task is
    inferred when not given: a non-numeric or low-cardinality label column is
    ``classification`` (subtype prediction), otherwise ``regression``.
    """
    p = Path(path)
    if not p.exists():
        raise ConfigError(f"dataset path not found: {path}")
    skip = {target_col, *(id_cols or [])}
    rows_raw: list[dict] = []
    with p.open(newline="") as fh:
        reader = csv.DictReader(fh)
        cols = reader.fieldnames or []
        if target_col not in cols:
            raise ConfigError(f"target_col '{target_col}' not in CSV columns {cols}")
        feature_names = [c for c in cols if c not in skip]
        if not feature_names:
            raise ConfigError("no feature columns found (all columns are target/id)")
        for row in reader:
            # Skip rows whose LABEL is TRULY absent (None/empty/whitespace) only.
            # Semantic missing tokens ("NA"/"none"/"-"/".") are NOT dropped here:
            # for classification they may be a legitimate class (e.g. a "no-subtype"
            # category), and dropping them would silently change class balance
            # (round-4 committee). The regression path below (where float("NA")
            # would crash) drops them explicitly instead.
            if _is_blank(row.get(target_col)):
                continue
            rows_raw.append(row)
    if not rows_raw:
        raise ConfigError(f"no usable rows parsed from {path}")

    # Auto-drop non-numeric feature columns (e.g. a string `sample_id`): a
    # numeric feature matrix cannot use them, and _num() would silently coerce
    # them to a constant 0.0 "feature" (junk that dilutes real signal on live
    # data). Columns the caller named in id_cols were already excluded above.
    _non_numeric = [c for c in feature_names
                    if not _looks_numeric([r.get(c) for r in rows_raw])]
    if _non_numeric:
        log.info("[ml_training] tabular loader dropping %d non-numeric column(s) as "
                 "id/metadata: %s", len(_non_numeric), ", ".join(_non_numeric))
        feature_names = [c for c in feature_names if c not in set(_non_numeric)]
        if not feature_names:
            raise ConfigError(
                "no numeric feature columns found after dropping non-numeric "
                f"id/metadata columns {_non_numeric}; pass a numeric feature matrix")

    raw_labels = [r[target_col] for r in rows_raw]
    if task is None:
        uniq = set(raw_labels)
        task = ("classification"
                if (not _looks_numeric(raw_labels) or len(uniq) <= max(2, len(raw_labels) // 10))
                else "regression")
    if task == "regression":
        # A regression target must be a finite number. Drop rows whose label is a
        # missing token ("NA"/nan/…) or otherwise non-finite/non-numeric, together
        # with their feature rows, so X and y stay aligned (float("NA") would
        # otherwise crash the whole load). Classification keeps such labels as
        # legitimate string classes (round-4 committee).
        def _flabel(v):
            if _is_missing(v):
                return None
            try:
                f = float(v)
            except (TypeError, ValueError):
                return None
            return f if math.isfinite(f) else None
        _kept = [r for r in rows_raw if _flabel(r[target_col]) is not None]
        _dropped = len(rows_raw) - len(_kept)
        if _dropped:
            log.info("[ml_training] tabular loader dropping %d row(s) with a "
                     "missing/non-numeric label under regression", _dropped)
        rows_raw = _kept
        if not rows_raw:
            raise ConfigError("no rows with a finite numeric label for regression")
        raw_labels = [r[target_col] for r in rows_raw]
    y: list = ([str(v) for v in raw_labels] if task == "classification"
               else [float(v) for v in raw_labels])

    # Build X with per-column MEAN IMPUTATION of missing cells (NA/NaN/…): a missing
    # value must not silently become a constant 0 feature, and the column must not be
    # dropped for it (see _looks_numeric). Mirrors the SNF .nf's feature-mean impute.
    def _val(v):
        if _is_missing(v):
            return None
        try:
            f = float(v)
        except (TypeError, ValueError):
            return None
        # A cell like "inf"/"-inf"/"nan" parses as a non-finite float that would
        # survive into _present, poison the column mean (mean of [1, 2, inf] = inf),
        # and then reach sklearn as inf/NaN. Treat non-finite as missing.
        return f if math.isfinite(f) else None
    _col_mean: dict = {}
    _all_missing: list = []
    for c in feature_names:
        _present = [x for x in (_val(r.get(c)) for r in rows_raw) if x is not None]
        if not _present:
            _all_missing.append(c)          # every cell missing → not a feature; drop it
            continue
        _col_mean[c] = sum(_present) / len(_present)
    if _all_missing:
        # A column that is missing in EVERY row would otherwise become a useless
        # constant-0 feature (second-pass review); drop it (partially-missing columns
        # are still kept + mean-imputed above).
        log.info("[ml_training] dropping %d all-missing feature column(s): %s",
                 len(_all_missing), ", ".join(_all_missing))
        feature_names = [c for c in feature_names if c not in set(_all_missing)]
        if not feature_names:
            raise ConfigError("no feature columns with any present (non-missing) value")
    X = []
    for r in rows_raw:
        row = []
        for c in feature_names:
            v = _val(r.get(c))
            row.append(_col_mean[c] if v is None else v)
        X.append(row)
    return LoadedTabularDataset(
        X=X, y=y, feature_names=feature_names, target_col=target_col,
        source=f"tabular-csv:{path}", task=task,
    )


# ---------------------------------------------------------------------------
# LLM fine-tuning: instruction/response datasets (text, not molecules)
# ---------------------------------------------------------------------------

# Tiny built-in instruction fixture — enough rows to exercise the LLM plumbing
# offline (NOT a real training set).
INSTRUCT_FIXTURE: list[dict[str, str]] = [
    {"instruction": "Summarize: hERG is a cardiac potassium channel.",
     "output": "hERG is a heart potassium channel linked to drug cardiotoxicity."},
    {"instruction": "What does ADMET stand for?",
     "output": "Absorption, Distribution, Metabolism, Excretion, and Toxicity."},
    {"instruction": "Define IC50 in one sentence.",
     "output": "IC50 is the concentration of a compound that inhibits a target by 50%."},
    {"instruction": "Is caffeine a stimulant?",
     "output": "Yes, caffeine is a central nervous system stimulant."},
    {"instruction": "What is a SMILES string?",
     "output": "A SMILES string is a text notation encoding a molecule's structure."},
    {"instruction": "Define bioavailability.",
     "output": "Bioavailability is the fraction of a dose that reaches systemic circulation."},
    {"instruction": "What is the blood-brain barrier?",
     "output": "The blood-brain barrier is a selective barrier protecting the brain from the blood."},
    {"instruction": "What does LogP measure?",
     "output": "LogP measures a compound's lipophilicity, the octanol-water partition coefficient."},
    {"instruction": "Define half-life in pharmacology.",
     "output": "Half-life is the time for a drug's plasma concentration to fall by half."},
    {"instruction": "What is a QSAR model?",
     "output": "A QSAR model relates chemical structure to biological activity quantitatively."},
    {"instruction": "What is CYP3A4?",
     "output": "CYP3A4 is a liver enzyme that metabolizes many drugs."},
    {"instruction": "Define Cmax.",
     "output": "Cmax is the maximum plasma concentration a drug reaches after dosing."},
    {"instruction": "What is a hepatotoxicity risk?",
     "output": "Hepatotoxicity risk is the likelihood a compound causes liver injury."},
    {"instruction": "What is molecular weight?",
     "output": "Molecular weight is the mass of a molecule, summed over its atoms."},
    {"instruction": "Define clearance in PK.",
     "output": "Clearance is the volume of plasma cleared of a drug per unit time."},
    {"instruction": "What is the therapeutic index?",
     "output": "The therapeutic index is the ratio of a drug's toxic dose to its effective dose."},
]


def load_instruction_rows(spec: DatasetSpec, instruction_col: str = "instruction",
                          output_col: str = "output") -> list[dict[str, str]]:
    """Load instruction/response rows for LLM fine-tuning.

    Returns a list of {instruction_col: str, output_col: str} dicts (pure Python,
    no pandas at this layer). Sources mirror load_dataset:
      - name 'fixture:instruct' → the offline INSTRUCT_FIXTURE
      - name 'hf:<dataset>'     → a HuggingFace instruction dataset (lazy)
      - path                    → local .jsonl (one obj/line) or .csv
      - s3_uri                  → staged at execution time (NotImplemented here)
    """
    kind = spec.source_kind()
    if kind == "name":
        name = (spec.name or "").strip()
        low = name.lower()
        if low in ("fixture:instruct", "instruct:fixture"):
            return [{instruction_col: r["instruction"], output_col: r["output"]}
                    for r in INSTRUCT_FIXTURE]
        if low.startswith("hf:"):
            return _load_hf_instruct(name.split(":", 1)[1], instruction_col, output_col)
        raise ConfigError(
            f"unknown LLM dataset '{name}'. Use 'hf:<dataset>', a local .jsonl/.csv "
            f"path, or 'fixture:instruct' for the offline fixture."
        )
    if kind == "path":
        return _load_instruct_file(spec.path, instruction_col, output_col)  # type: ignore[arg-type]
    raise NotImplementedError("s3_uri LLM data is staged locally by the executor; use path=.")


def _load_instruct_file(path: str, instruction_col: str, output_col: str) -> list[dict[str, str]]:
    import json
    p = Path(path)
    if not p.exists():
        raise ConfigError(f"LLM dataset path not found: {path}")
    rows: list[dict[str, str]] = []
    if p.suffix.lower() == ".jsonl":
        for line in p.read_text().splitlines():
            line = line.strip()
            if not line:
                continue
            obj = json.loads(line)
            if instruction_col in obj and output_col in obj:
                rows.append({instruction_col: str(obj[instruction_col]),
                             output_col: str(obj[output_col])})
    else:  # csv
        with p.open(newline="") as fh:
            reader = csv.DictReader(fh)
            cols = reader.fieldnames or []
            if instruction_col not in cols or output_col not in cols:
                raise ConfigError(
                    f"CSV must have '{instruction_col}' + '{output_col}' columns; got {cols}"
                )
            for row in reader:
                if row[instruction_col] and row[output_col]:
                    rows.append({instruction_col: row[instruction_col],
                                 output_col: row[output_col]})
    if not rows:
        raise ConfigError(f"no usable instruction rows parsed from {path}")
    return rows


# ---------------------------------------------------------------------------
# Preference data (DPO) + prompts (GRPO) for TRL preference/RL training
# ---------------------------------------------------------------------------

# {prompt, chosen, rejected} — chosen is the preferred response.
PREFERENCE_FIXTURE: list[dict[str, str]] = [
    {"prompt": "What is hERG?", "chosen": "hERG is a cardiac potassium channel; blocking it risks arrhythmia.", "rejected": "hERG is a kind of fish."},
    {"prompt": "Define IC50.", "chosen": "IC50 is the concentration that inhibits a target by 50%.", "rejected": "IC50 is a car model."},
    {"prompt": "Is caffeine a stimulant?", "chosen": "Yes, caffeine stimulates the central nervous system.", "rejected": "No, caffeine is a sedative."},
    {"prompt": "What does ADMET mean?", "chosen": "Absorption, Distribution, Metabolism, Excretion, Toxicity.", "rejected": "It means a type of magnet."},
    {"prompt": "What is LogP?", "chosen": "LogP measures lipophilicity (octanol-water partition).", "rejected": "LogP is a log file format."},
    {"prompt": "Define bioavailability.", "chosen": "The fraction of a dose reaching systemic circulation.", "rejected": "The number of pills in a bottle."},
    {"prompt": "What is CYP3A4?", "chosen": "A liver enzyme metabolizing many drugs.", "rejected": "A programming language."},
    {"prompt": "What is the blood-brain barrier?", "chosen": "A selective barrier protecting the brain from blood-borne substances.", "rejected": "A wall around hospitals."},
]

# {prompt} — GRPO samples completions and scores them with a reward function.
PROMPT_FIXTURE: list[dict[str, str]] = [
    {"prompt": "Explain hERG cardiotoxicity in one sentence."},
    {"prompt": "Summarize what ADMET stands for."},
    {"prompt": "Give a one-line definition of IC50."},
    {"prompt": "Describe the blood-brain barrier briefly."},
    {"prompt": "What does LogP measure? Answer briefly."},
    {"prompt": "Define drug bioavailability in one line."},
    {"prompt": "What is CYP3A4? One sentence."},
    {"prompt": "State the therapeutic index in one sentence."},
]


def load_preference_rows(spec: DatasetSpec) -> list[dict[str, str]]:
    """Load {prompt, chosen, rejected} rows for DPO. Sources mirror the others:
    name 'fixture:preference' | 'hf:<ds>' | local .jsonl/.csv | s3 (exec-staged)."""
    kind = spec.source_kind()
    if kind == "name":
        low = (spec.name or "").strip().lower()
        if low in ("fixture:preference", "preference:fixture"):
            return [dict(r) for r in PREFERENCE_FIXTURE]
        if low.startswith("hf:"):
            return _load_hf_generic(spec.name.split(":", 1)[1], ("prompt", "chosen", "rejected"))
        raise ConfigError("unknown DPO dataset; use 'fixture:preference', hf:<ds>, or a .jsonl/.csv path")
    if kind == "path":
        return _load_cols_file(spec.path, ("prompt", "chosen", "rejected"))  # type: ignore[arg-type]
    raise NotImplementedError("s3_uri DPO data is staged locally by the executor; use path=.")


def load_prompt_rows(spec: DatasetSpec) -> list[dict[str, str]]:
    """Load {prompt} rows for GRPO."""
    kind = spec.source_kind()
    if kind == "name":
        low = (spec.name or "").strip().lower()
        if low in ("fixture:prompts", "prompts:fixture", "fixture:instruct"):
            return [dict(r) for r in PROMPT_FIXTURE]
        if low.startswith("hf:"):
            return _load_hf_generic(spec.name.split(":", 1)[1], ("prompt",))
        raise ConfigError("unknown GRPO dataset; use 'fixture:prompts', hf:<ds>, or a .jsonl/.csv path")
    if kind == "path":
        return _load_cols_file(spec.path, ("prompt",))  # type: ignore[arg-type]
    raise NotImplementedError("s3_uri GRPO data is staged locally by the executor; use path=.")


def _load_cols_file(path: str, cols: tuple) -> list[dict[str, str]]:
    import json
    p = Path(path)
    if not p.exists():
        raise ConfigError(f"dataset path not found: {path}")
    rows: list[dict[str, str]] = []
    if p.suffix.lower() == ".jsonl":
        for line in p.read_text().splitlines():
            line = line.strip()
            if not line:
                continue
            obj = json.loads(line)
            if all(c in obj for c in cols):
                rows.append({c: str(obj[c]) for c in cols})
    else:
        with p.open(newline="") as fh:
            reader = csv.DictReader(fh)
            fns = reader.fieldnames or []
            if not all(c in fns for c in cols):
                raise ConfigError(f"CSV must have columns {cols}; got {fns}")
            for row in reader:
                if all(row.get(c) for c in cols):
                    rows.append({c: row[c] for c in cols})
    if not rows:
        raise ConfigError(f"no usable rows ({cols}) parsed from {path}")
    return rows


def _load_hf_generic(hf_name: str, cols: tuple) -> list[dict[str, str]]:
    try:
        from datasets import load_dataset as _hf_load  # noqa: F401
    except ImportError as e:
        raise ImportError("the `datasets` library is required for hf:<dataset>.") from e
    from datasets import load_dataset as _hf_load
    ds = _hf_load(hf_name, split="train")
    rows = []
    for r in ds:
        if all(c in r and r[c] for c in cols):
            rows.append({c: str(r[c]) for c in cols})
    return rows


def _load_hf_instruct(hf_name: str, instruction_col: str, output_col: str) -> list[dict[str, str]]:
    try:
        from datasets import load_dataset as _hf_load  # noqa: F401
    except ImportError as e:
        raise ImportError(
            "the `datasets` library is required for hf:<dataset> LLM data "
            "(ships with the ml-training image). Use a local .jsonl or "
            "'fixture:instruct' offline."
        ) from e
    from datasets import load_dataset as _hf_load
    ds = _hf_load(hf_name, split="train")
    rows = []
    for r in ds:
        ins = r.get(instruction_col) or r.get("instruction") or r.get("prompt")
        out = r.get(output_col) or r.get("output") or r.get("response") or r.get("completion")
        if ins and out:
            rows.append({instruction_col: str(ins), output_col: str(out)})
    return rows
