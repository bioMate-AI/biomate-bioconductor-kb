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
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from .config import DatasetSpec, ConfigError

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
            if smi is None or raw in (None, ""):
                continue
            rows.append((str(smi), float(raw)))
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


def _looks_numeric(values) -> bool:
    for v in values:
        if v in (None, ""):
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
            if row.get(target_col) in (None, ""):
                continue
            rows_raw.append(row)
    if not rows_raw:
        raise ConfigError(f"no usable rows parsed from {path}")

    raw_labels = [r[target_col] for r in rows_raw]
    if task is None:
        uniq = set(raw_labels)
        task = ("classification"
                if (not _looks_numeric(raw_labels) or len(uniq) <= max(2, len(raw_labels) // 10))
                else "regression")
    y: list = ([str(v) for v in raw_labels] if task == "classification"
               else [float(v) for v in raw_labels])

    def _num(v):
        try:
            return float(v)
        except (TypeError, ValueError):
            return 0.0
    X = [[_num(r.get(c)) for c in feature_names] for r in rows_raw]
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
