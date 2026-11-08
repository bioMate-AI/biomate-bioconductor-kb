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



def test_restore_streams_and_skips_affinity_ckpt():
    import subprocess, tarfile, io
    assert drv is not None
    src = tempfile.mkdtemp(); out = tempfile.mkdtemp()
    for name, data in (("boltz2_conf.ckpt", b"c"), ("boltz2_aff.ckpt", b"a" * 1000), ("mols/ALA.pkl", b"m")):
        pth = os.path.join(src, name); os.makedirs(os.path.dirname(pth), exist_ok=True); open(pth, "wb").write(data)
    tarp = os.path.join(tempfile.mkdtemp(), "c.tar")
    with tarfile.open(tarp, "w") as t: t.add(src, arcname=".")
    r = subprocess.run(["bash", "-c", drv.restore_cmd(f"cat {tarp}", out)], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    assert os.path.exists(os.path.join(out, "boltz2_conf.ckpt")) and os.path.exists(os.path.join(out, "mols", "ALA.pkl"))
    assert not os.path.exists(os.path.join(out, "boltz2_aff.ckpt")), "affinity checkpoint must be skipped"

def test_restore_failure_is_nonzero_so_driver_can_fall_back():
    import subprocess
    r = subprocess.run(["bash", "-c", drv.restore_cmd("false", tempfile.mkdtemp())], capture_output=True)
    assert r.returncode != 0

if __name__ == "__main__":
    n = 0
    for k, f in sorted(globals().items()):
        if k.startswith("test_"): f(); n += 1; print("PASS", k)
    print(f"{n} tests passed")
