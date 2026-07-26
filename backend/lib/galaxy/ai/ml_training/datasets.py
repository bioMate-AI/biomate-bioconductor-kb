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
        from tdc.single_pred import Tox  # noqa: F401
    except ImportError as e:
        raise ImportError(
            "PyTDC is required for public dataset loading. "
            "Install with `pip install PyTDC`, or use dataset name "
            "'fixture:herg' for the offline fixture."
        ) from e
    from tdc.single_pred import Tox
    data = Tox(name=tdc_name)
    df = data.get_data()
    rows = [(str(r["Drug"]), float(r["Y"])) for _, r in df.iterrows()]
    return LoadedDataset(rows, spec.smiles_col, spec.target_col,
                         source=f"TDC:{tdc_name} (n={len(rows)})")


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
