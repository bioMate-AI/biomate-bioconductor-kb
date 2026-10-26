"""Which manifest complexes can Boltz-2 actually run? Boltz resolves `ccd:` codes against its bundled ccd.pkl; codes absent from it make boltz skip the input
(rc 0, no output). Reads codes.json {complex_id: [ccd,...]} from S3, loads ccd.pkl from the cached Boltz tar, writes ccd_check.json {complex_id: [missing codes]}."""
import json, os, pickle, subprocess, sys, tarfile
B = "s3://biomate-nextflow-work/cyclic_peptide/cofold_bench"
def sh(c): return subprocess.run(c, shell=True, check=True)
sh(f"aws s3 cp {B}/ccd_check/codes.json /tmp/codes.json --only-show-errors")
sh(f"aws s3 cp {B}/cache/boltz_cache.tar /tmp/bc.tar --only-show-errors")
with tarfile.open("/tmp/bc.tar") as t:
    names = [m.name for m in t.getmembers() if os.path.basename(m.name) in ("ccd.pkl",)]
    print("ccd members:", names, flush=True)
    t.extract(names[0], "/tmp/ccd_x")
ccd = pickle.load(open(os.path.join("/tmp/ccd_x", names[0]), "rb"))
keys = set(ccd.keys()) if hasattr(ccd, "keys") else set()
print("n ccd components in boltz library:", len(keys), flush=True)
codes = json.load(open("/tmp/codes.json"))
out = {c: [x for x in v if x not in keys] for c, v in codes.items()}
json.dump(dict(n_library=len(keys), missing=out), open("/tmp/ccd_check.json", "w"))
sh(f"aws s3 cp /tmp/ccd_check.json {B}/ccd_check/ccd_check.json --only-show-errors")
print("done; complexes with any missing code:", sum(1 for v in out.values() if v), "of", len(out), flush=True)
