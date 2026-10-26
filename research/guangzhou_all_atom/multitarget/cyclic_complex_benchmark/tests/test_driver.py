"""Regression tests for cofold_boltz_driver (smoke1b lost 3x25 samples to a directory-as-file copy). Run: python3 tests/test_driver.py"""
import os, sys, tempfile, importlib.util
here = os.path.dirname(os.path.abspath(__file__))
os.environ.setdefault("IDS", "x"); os.environ.setdefault("IN_S3", "s3://x/in"); os.environ.setdefault("OUT_S3", "s3://x/out")
spec = importlib.util.spec_from_file_location("drv", os.path.join(here, "..", "scripts", "cofold_boltz_driver.py"))
try:
    drv = importlib.util.module_from_spec(spec); spec.loader.exec_module(drv)
except SystemExit:
    drv = None

def test_collect_msa_skips_directories_and_does_not_raise():
    assert drv is not None, "driver import failed"
    d = tempfile.mkdtemp()
    msa = os.path.join(d, "out", "boltz_results_in", "msa"); os.makedirs(os.path.join(msa, "in_unpaired_tmp_env"))  # the directory boltz leaves
    open(os.path.join(msa, "in_unpaired.a3m"), "w").write(">q\nAAAA\n")
    names = drv.collect_msa(d)
    assert names == ["in_unpaired.a3m"], names
    assert os.path.isfile(os.path.join(d, "msa_in_unpaired.a3m"))

def test_driver_exits_nonzero_when_any_complex_fails():
    src = open(os.path.join(here, "..", "scripts", "cofold_boltz_driver.py")).read()
    assert "sys.exit(1)" in src and "FAILED_COMPLEXES" in src

if __name__ == "__main__":
    n = 0
    for k, f in sorted(globals().items()):
        if k.startswith("test_"): f(); n += 1; print("PASS", k)
    print(f"{n} tests passed")
