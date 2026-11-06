"""One place that puts the earlier assets on sys.path (module names are top-level in this repo) and records canonical locations."""
import os, sys, hashlib, importlib.util
HERE = os.path.dirname(os.path.abspath(__file__)); CYC = os.path.abspath(os.path.join(HERE, "..")); ROOT = os.path.abspath(os.path.join(CYC, ".."))
for p in (os.path.join(CYC, "ihlm"), os.path.join(CYC, "v4_eval"), CYC, ROOT):
    if p not in sys.path: sys.path.insert(0, p)
CKPT_V4 = os.path.join(ROOT, "runs_helm", "unified_cyclic_llm_v4.pt")
CYCPEPT_CSV = os.path.join(ROOT, "data", "raw", "CycPeptMPDB_Peptide_All.csv")


def sha256_file(path, n=1 << 20):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(n), b""): h.update(b)
    return h.hexdigest()


def load_ihlm():
    """workstream 1's IHLM class, loaded by path under a unique module name (the top-level name `model` is generic). Read-only."""
    spec = importlib.util.spec_from_file_location("ihlm_core_model", os.path.join(CYC, "ihlm", "model.py")); m = importlib.util.module_from_spec(spec)
    sys.modules["ihlm_core_model"] = m; spec.loader.exec_module(m); return m
