"""Introspect BoltzGen's training-data construction so the --batch converter can build it EXACTLY.

Runs ON an instance with boltzgen installed + a shipped training targets dir (from targets.zip) +
boltzgen_small.yaml. Dumps, to stdout (captured to S3):
  - Record / Manifest / StructureInfo / ChainInfo / InterfaceInfo dataclass fields + types
  - a shipped manifest.json record (first entry) verbatim
  - a shipped records/<id>.json verbatim (so we see exactly what a training Record serializes to)
  - the Structure npz keys of a shipped structure
  - how data.py's training DataModule loads a record (the load path + required files)
  - boltzgen_small.yaml's data/datasets keys (what paths/fields a dataset entry needs, single-seq flag)
This pins the construction; no guessing in --batch.
"""
from __future__ import annotations

import dataclasses
import glob
import importlib
import inspect
import json
import sys
from pathlib import Path


def _fields(cls):
    try:
        return [(f.name, str(f.type)) for f in dataclasses.fields(cls)]
    except Exception as e:  # noqa: BLE001
        return f"<not a dataclass: {e}>"


def dump_api():
    D = importlib.import_module("boltzgen.data.data")
    print("=== dataclass fields ===")
    for name in ("Record", "Manifest", "Structure", "StructureInfo", "ChainInfo",
                 "InterfaceInfo", "TemplateInfo", "ResidueInfo"):
        cls = getattr(D, name, None)
        print(f"{name}: {_fields(cls) if cls is not None else '<absent>'}")
    # constructors / signatures
    for name in ("Record", "Manifest"):
        cls = getattr(D, name, None)
        if cls is not None:
            try:
                print(f"{name}.__init__ sig: {inspect.signature(cls)}")
            except (TypeError, ValueError):
                pass
    # how is a Record built from a parsed structure? look for helpers
    print("\n=== boltzgen.data.data members mentioning 'record'/'manifest'/'info' ===")
    for n in dir(D):
        if any(k in n.lower() for k in ("record", "manifest", "info", "target")):
            print(" ", n, type(getattr(D, n)))


def dump_shipped(targets_dir: str):
    D = importlib.import_module("boltzgen.data.data")
    t = Path(targets_dir)
    print(f"\n=== shipped targets dir: {t} ===")
    for sub in ("", "manifest.json", "records", "structures", "msa", "mols"):
        p = t / sub
        print(f"  {sub or '.'} exists={p.exists()}")
    mf = t / "manifest.json"
    if mf.exists():
        try:
            man = json.loads(mf.read_text())
            recs = man.get("records", man) if isinstance(man, dict) else man
            print("\n=== manifest.json: top-level type / first record ===")
            print("  top type:", type(man).__name__, "| keys:", list(man.keys()) if isinstance(man, dict) else "list")
            first = recs[0] if isinstance(recs, list) and recs else recs
            print("  first record JSON:\n", json.dumps(first, indent=2)[:3000])
        except Exception as e:  # noqa: BLE001
            print("  manifest parse err:", e)
    rjson = sorted(glob.glob(str(t / "records" / "*.json")))
    if rjson:
        print(f"\n=== a shipped records/*.json ({Path(rjson[0]).name}) ===")
        print(Path(rjson[0]).read_text()[:3000])
        # also load via Record.load to see the object
        try:
            rec = D.Record.load(Path(rjson[0]))
            print("  Record.load ok; .id=", getattr(rec, "id", "?"),
                  "chains=", type(getattr(rec, "chains", None)),
                  "structure=", type(getattr(rec, "structure", None)))
        except Exception as e:  # noqa: BLE001
            print("  Record.load err:", e)
    snpz = sorted(glob.glob(str(t / "structures" / "*.npz")))
    if snpz:
        import numpy as np
        print(f"\n=== a shipped structures/*.npz ({Path(snpz[0]).name}) keys ===")
        with np.load(snpz[0], allow_pickle=True) as z:
            for k in z.files:
                a = z[k]
                print(f"  {k}: shape={getattr(a,'shape',None)} dtype={getattr(a,'dtype',None)}")


def dump_datamodule_and_config(config_path: str):
    print("\n=== data.py training DataModule record-load path ===")
    try:
        dm = importlib.import_module("boltzgen.task.train.data")
        src = inspect.getsource(dm)
        for kw in ("def load_record", "def load_structure", "def load_msas", "single_sequence",
                   "class TrainingDataModule", "manifest", "Manifest.load", "Record.load"):
            i = src.find(kw)
            if i >= 0:
                print(f"\n--- near '{kw}' ---\n{src[i:i+500]}")
    except Exception as e:  # noqa: BLE001
        print("  datamodule introspect err:", e)
    print("\n=== boltzgen_small.yaml data/datasets keys ===")
    try:
        import yaml
        cfg = yaml.safe_load(Path(config_path).read_text())
        data = cfg.get("data", {})
        print("  data keys:", list(data.keys()))
        ds = data.get("datasets")
        print("  datasets[0]:", json.dumps(ds[0], indent=2) if isinstance(ds, list) and ds else ds)
        for k in ("max_tokens", "max_atoms", "max_seqs", "single_sequence_prop_training",
                  "single_sequence_prop", "use_msa"):
            if k in data:
                print(f"  data.{k} = {data[k]}")
    except Exception as e:  # noqa: BLE001
        print("  config introspect err:", e)


if __name__ == "__main__":
    targets = sys.argv[1] if len(sys.argv) > 1 else "./training_data/targets"
    config = sys.argv[2] if len(sys.argv) > 2 else "src/boltzgen/resources/config/train/boltzgen_small.yaml"
    dump_api()
    dump_shipped(targets)
    dump_datamodule_and_config(config)
    print("\nINTROSPECT_DONE")
