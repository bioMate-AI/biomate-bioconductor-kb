"""cofold_local.collect on a FAKE boltz output tree (names as boltz writes them). Run: python3 tests/test_cofold_local.py"""
import json, os, sys, tempfile
import numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts"))
import cofold_local as L

def fake(work, n=3, with_msa_dir=True):
    d = f"{work}/out/boltz_results_in/predictions/in"; os.makedirs(d)
    for i in range(n):
        open(f"{d}/in_model_{i}.cif", "w").write("data_x\nloop_\n_atom_site.id\n1\n"); json.dump({"iptm": 0.5 + i / 10}, open(f"{d}/confidence_in_model_{i}.json", "w"))
        np.savez(f"{d}/pae_in_model_{i}.npz", pae=np.ones((10, 10)) * (i + 1))
    m = f"{work}/out/boltz_results_in/msa"; os.makedirs(m)
    open(f"{m}/in_0.csv", "w").write("a\n")
    if with_msa_dir: os.makedirs(f"{m}/in_unpaired_tmp_env")           # the directory that broke the S3 driver
    return work

def test_collect_complete_set_and_msa_directory_safe():
    w = fake(tempfile.mkdtemp()); dest = tempfile.mkdtemp() + "/c"
    n, npae, msa = L.collect(w, dest, n_rec_tokens=6, n_expected=3)
    assert (n, npae) == (3, 3) and msa == ["in_0.csv"], (n, npae, msa)
    assert sorted(os.listdir(dest)) == sorted(["sample_0.cif", "sample_1.cif", "sample_2.cif", "confidence_0.json", "confidence_1.json", "confidence_2.json", "pae_if.json", "msa_in_0.csv"])
    pf = json.load(open(f"{dest}/pae_if.json")); assert abs(pf["1"]["pae_pep_to_rec"] - 2.0) < 1e-9 and pf["1"]["n_pep_tokens"] == 4

def test_wrong_count_is_reported_not_silently_accepted():
    w = fake(tempfile.mkdtemp(), n=2); dest = tempfile.mkdtemp() + "/c"
    n, npae, msa = L.collect(w, dest, 6, n_expected=3)
    assert n == 2 and npae == 0 and not os.path.exists(dest)

def test_zero_byte_or_atomless_cif_is_a_failed_sample_not_a_success():
    for bad in ("", "data_x\n"):
        w = fake(tempfile.mkdtemp(), n=3); dest = tempfile.mkdtemp() + "/c"
        open(f"{w}/out/boltz_results_in/predictions/in/in_model_1.cif", "w").write(bad)
        n, npae, msa = L.collect(w, dest, 6, n_expected=3)
        assert n == 2 and not os.path.exists(dest), (bad, n)

if __name__ == "__main__":
    k = 0
    for name, f in sorted(globals().items()):
        if name.startswith("test_"): f(); k += 1; print("PASS", name)
    print(f"{k} tests passed")
