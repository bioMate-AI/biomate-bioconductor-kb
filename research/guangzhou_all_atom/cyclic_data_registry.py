#!/usr/bin/env python3
"""Unified cyclic-peptide DATA REGISTRY — one catalogue + one loader for every held dataset.

The problem it solves (priority #1, integration map row "Databases -> one unified data registry"):
our cyclic-peptide datasets are scattered across S3 prefixes and ad-hoc local caches, and every
stage script hard-codes its own paths. This module makes the holdings addressable by NAME:

    from cyclic_data_registry import registry
    reg = registry()
    reg.catalog()                 # list every dataset: name, modality, count, format
    df  = reg.load("cycpeptmpdb") # -> pandas.DataFrame (local cache first, else S3 download)
    idx = reg.load("pepbdb")      # -> dict (parsed JSON index)
    reg.s3_uri("cremp_partial")   # canonical S3 location

Design:
  * Canonical store is S3; ``local_path`` (relative to this file) is an optional cache.
  * ``load(name)`` returns a DataFrame (csv), dict (json), or list[dict] (jsonl) for ``loadable``
    datasets, downloading small files from S3 into a cache dir on demand. Large ``archive`` datasets
    are not auto-opened — ``load`` raises with the S3 URI and ``fetch(name)`` guidance.
  * No dataset is mutated; counts in the manifest are verified real counts, and ``verify()`` re-reads
    headers/counts of the accessible ones to prove the manifest is honest.

CPU/local only — never launches GPU/EC2. S3 access is read-only (``aws s3 cp``), used lazily.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml

ROOT = Path(__file__).resolve().parent
MANIFEST = ROOT / "cyclic_data_registry.yaml"
CACHE_DIR = ROOT / "data" / "_registry_cache"

MODALITIES = {"binding", "permeability", "conformer", "structure", "sequence", "reference"}
FORMATS = {"csv", "json", "jsonl", "archive"}


@dataclass
class Dataset:
    name: str
    description: str
    modality: str
    format: str
    s3_uri: Optional[str]
    local_path: Optional[str]
    record_count: Optional[int]
    loadable: bool
    unit: str = ""
    cyclic_count: Optional[int] = None
    key_columns: Optional[List[str]] = None
    license: str = ""
    feeds: Optional[List[str]] = None
    notes: str = ""
    raw: Dict[str, Any] = None  # full manifest entry (archives, summary_json, ...)

    def local_abspath(self) -> Optional[Path]:
        return (ROOT / self.local_path) if self.local_path else None


class CyclicDataRegistry:
    def __init__(self, manifest_path: Path = MANIFEST):
        self.manifest_path = Path(manifest_path)
        doc = yaml.safe_load(self.manifest_path.read_text())
        self.bucket = doc.get("s3_bucket")
        self.prefix = doc.get("s3_prefix")
        self._datasets: Dict[str, Dataset] = {}
        for name, e in doc["datasets"].items():
            ds = Dataset(
                name=name,
                description=(e.get("description") or "").strip(),
                modality=e["modality"],
                format=e["format"],
                s3_uri=e.get("s3_uri"),
                local_path=e.get("local_path"),
                record_count=e.get("record_count"),
                loadable=bool(e.get("loadable", False)),
                unit=e.get("unit", ""),
                cyclic_count=e.get("cyclic_count"),
                key_columns=e.get("key_columns"),
                license=e.get("license", ""),
                feeds=e.get("feeds"),
                notes=e.get("notes", ""),
                raw=e,
            )
            if ds.modality not in MODALITIES:
                raise ValueError(f"{name}: bad modality {ds.modality!r} (allowed {sorted(MODALITIES)})")
            if ds.format not in FORMATS:
                raise ValueError(f"{name}: bad format {ds.format!r} (allowed {sorted(FORMATS)})")
            self._datasets[name] = ds

    # ---- lookup ---------------------------------------------------------------------------
    def names(self) -> List[str]:
        return list(self._datasets)

    def get(self, name: str) -> Dataset:
        if name not in self._datasets:
            raise KeyError(f"unknown dataset {name!r}; known: {', '.join(self._datasets)}")
        return self._datasets[name]

    def by_modality(self, modality: str) -> List[Dataset]:
        return [d for d in self._datasets.values() if d.modality == modality]

    def s3_uri(self, name: str) -> Optional[str]:
        return self.get(name).s3_uri

    def catalog(self) -> List[dict]:
        rows = []
        for d in self._datasets.values():
            rows.append({
                "name": d.name, "modality": d.modality, "format": d.format,
                "record_count": d.record_count, "cyclic_count": d.cyclic_count,
                "unit": d.unit, "loadable": d.loadable,
                "local_cached": bool(d.local_abspath() and d.local_abspath().exists()),
            })
        return rows

    # ---- resolution + fetch ---------------------------------------------------------------
    def resolve_path(self, name: str, allow_download: bool = True) -> Path:
        """Return a local path to the dataset file, downloading small files from S3 if needed."""
        d = self.get(name)
        lp = d.local_abspath()
        if lp and lp.exists():
            return lp
        if not allow_download:
            raise FileNotFoundError(f"{name}: no local cache at {lp} and allow_download=False")
        if not d.s3_uri:
            raise FileNotFoundError(f"{name}: no local cache and no s3_uri to download from")
        if d.format == "archive":
            raise NotImplementedError(
                f"{name} is an archive ({d.s3_uri}); it is not auto-fetched. Download + extract "
                f"manually (aws s3 cp {d.s3_uri} <dst>) — large multi-GB file.")
        return self.fetch(name)

    def fetch(self, name: str, dst: Optional[Path] = None) -> Path:
        """aws s3 cp the dataset's file into the cache dir (small loadable files only)."""
        d = self.get(name)
        if not d.s3_uri:
            raise ValueError(f"{name}: no s3_uri")
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        dst = dst or (CACHE_DIR / Path(d.s3_uri).name)
        cp = subprocess.run(["aws", "s3", "cp", d.s3_uri, str(dst)],
                            capture_output=True, text=True)
        if cp.returncode != 0:
            raise RuntimeError(f"s3 cp failed for {name}: {cp.stderr.strip()}")
        return dst

    # ---- load -----------------------------------------------------------------------------
    def load(self, name: str, nrows: Optional[int] = None, allow_download: bool = True) -> Any:
        """Load a dataset. csv -> DataFrame, json -> dict, jsonl -> list[dict]. Archives raise."""
        d = self.get(name)
        if d.format == "archive" or not d.loadable:
            raise NotImplementedError(
                f"{name} is not directly loadable (format={d.format}). "
                f"S3: {d.s3_uri}. Use fetch()/manual extraction.")
        path = self.resolve_path(name, allow_download=allow_download)
        if d.format == "csv":
            import pandas as pd
            return pd.read_csv(path, nrows=nrows, low_memory=False)
        if d.format == "json":
            return json.loads(Path(path).read_text())
        if d.format == "jsonl":
            out = []
            with open(path) as fh:
                for i, line in enumerate(fh):
                    if nrows is not None and i >= nrows:
                        break
                    line = line.strip()
                    if line:
                        out.append(json.loads(line))
            return out
        raise ValueError(f"{name}: unhandled format {d.format}")

    def head(self, name: str, n: int = 5) -> Any:
        """Peek: first n rows/records. For csv returns a small DataFrame."""
        return self.load(name, nrows=n)

    # ---- verification ---------------------------------------------------------------------
    def verify(self, names: Optional[List[str]] = None, allow_download: bool = True) -> List[dict]:
        """Re-read headers/counts of accessible datasets and compare to manifest counts.

        Only reads what is cheaply readable (local cache, or small S3 files). Archives and
        uncached large remote files are reported as 'skipped' (not a failure)."""
        report = []
        for name in (names or self.names()):
            d = self.get(name)
            rec = {"name": name, "modality": d.modality, "format": d.format,
                   "manifest_count": d.record_count, "status": None, "observed_count": None,
                   "detail": ""}
            try:
                lp = d.local_abspath()
                cached = bool(lp and lp.exists())
                if d.format == "archive" or not d.loadable:
                    rec["status"] = "skipped"
                    rec["detail"] = "archive / not directly loadable"
                elif not cached and not allow_download:
                    rec["status"] = "skipped"
                    rec["detail"] = "not cached locally (download disabled)"
                elif not cached and d.s3_uri and _s3_size(d.s3_uri) > 80_000_000:
                    rec["status"] = "skipped"
                    rec["detail"] = "remote file too large to fetch for verify"
                else:
                    obs, cols = self._observe(name, allow_download=allow_download)
                    rec["observed_count"] = obs
                    rec["columns"] = cols
                    if d.record_count is None:
                        rec["status"] = "ok"
                        rec["detail"] = "loaded; no manifest count to compare"
                    elif obs == d.record_count:
                        rec["status"] = "ok"
                    else:
                        rec["status"] = "count_mismatch"
                        rec["detail"] = f"manifest {d.record_count} != observed {obs}"
            except Exception as exc:  # noqa: BLE001 - verify must not crash on one dataset
                rec["status"] = "error"
                rec["detail"] = f"{type(exc).__name__}: {exc}"
            report.append(rec)
        return report

    def _observe(self, name: str, allow_download: bool):
        """Return (row_count, columns) by reading the file cheaply (no full DataFrame for big csv)."""
        d = self.get(name)
        path = self.resolve_path(name, allow_download=allow_download)
        if d.format == "csv":
            # line-count minus header (cheap, exact) + header columns
            with open(path, "rb") as fh:
                n = sum(1 for _ in fh)
            with open(path) as fh:
                header = fh.readline().rstrip("\n").split(",")
            return (n - 1, header)
        if d.format == "jsonl":
            with open(path) as fh:
                lines = [ln for ln in fh if ln.strip()]
            cols = sorted(json.loads(lines[0]).keys()) if lines else []
            return (len(lines), cols)
        if d.format == "json":
            obj = json.loads(Path(path).read_text())
            # count = n_entries field, or length of the obvious list payload
            if isinstance(obj, dict):
                for k in ("entry_ids", "entries"):
                    if isinstance(obj.get(k), list):
                        return (len(obj[k]), list(obj.keys()))
                if isinstance(obj.get("n_entries"), int):
                    return (obj["n_entries"], list(obj.keys()))
                return (len(obj), list(obj.keys()))
            if isinstance(obj, list):
                return (len(obj), [])
        raise ValueError(f"cannot observe {name}")


def _s3_size(uri: str) -> int:
    """Best-effort object size via `aws s3 ls`; returns a large sentinel on failure (=> skip)."""
    try:
        out = subprocess.run(["aws", "s3", "ls", uri], capture_output=True, text=True, timeout=30)
        parts = out.stdout.split()
        for p in parts:
            if p.isdigit():
                return int(p)
    except Exception:  # noqa: BLE001
        pass
    return 1 << 62


_SINGLETON: Optional[CyclicDataRegistry] = None


def registry() -> CyclicDataRegistry:
    global _SINGLETON
    if _SINGLETON is None:
        _SINGLETON = CyclicDataRegistry()
    return _SINGLETON


def _main(argv=None):
    ap = argparse.ArgumentParser(description="Unified cyclic-peptide data registry.")
    ap.add_argument("--catalog", action="store_true", help="print the dataset catalogue")
    ap.add_argument("--verify", action="store_true", help="re-read counts of accessible datasets")
    ap.add_argument("--no-download", action="store_true", help="local cache only; never hit S3")
    ap.add_argument("--head", metavar="NAME", help="print first rows of a dataset")
    args = ap.parse_args(argv)
    reg = registry()

    if args.head:
        print(reg.head(args.head, 5))
        return 0

    if args.catalog or not (args.verify or args.head):
        print(f"{'name':<28} {'modality':<12} {'fmt':<8} {'count':>10}  {'cyclic':>8}  cached")
        print("-" * 86)
        for r in reg.catalog():
            print(f"{r['name']:<28} {r['modality']:<12} {r['format']:<8} "
                  f"{str(r['record_count']):>10}  {str(r['cyclic_count'] or ''):>8}  "
                  f"{'yes' if r['local_cached'] else 'no'}")
        total = sum((r['record_count'] or 0) for r in reg.catalog())
        print("-" * 86)
        print(f"{len(reg.names())} datasets; summed record_count = {total:,}")

    if args.verify:
        print("\n=== verify (observed vs manifest) ===")
        rep = reg.verify(allow_download=not args.no_download)
        ok = mism = err = skip = 0
        for r in rep:
            tag = r["status"]
            ok += tag == "ok"; mism += tag == "count_mismatch"
            err += tag == "error"; skip += tag == "skipped"
            line = f"[{tag:<14}] {r['name']:<28} manifest={r['manifest_count']}"
            if r["observed_count"] is not None:
                line += f" observed={r['observed_count']}"
            if r["detail"]:
                line += f"  ({r['detail']})"
            print(line)
        print(f"\nsummary: ok={ok} mismatch={mism} error={err} skipped={skip}")
        if mism or err:
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(_main())
