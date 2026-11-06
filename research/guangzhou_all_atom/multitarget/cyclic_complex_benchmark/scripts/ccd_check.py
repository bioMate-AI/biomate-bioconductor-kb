"""Which manifest complexes can Boltz-2 actually run? Boltz resolves `ccd:` codes against its bundled ccd.pkl; codes absent from it make boltz skip the input
(rc 0, no output). Reads codes.json {complex_id: [ccd,...]} from S3, loads ccd.pkl from the cached Boltz tar, writes ccd_check.json {complex_id: [missing codes]}."""
import json, os, pickle, subprocess, sys, tarfile
B = "s3://biomate-nextflow-work/cyclic_peptide/cofold_bench"
def sh(c): return subprocess.run(c, shell=True, check=True)
sh(f"aws s3 cp {B}/ccd_check/codes.json /tmp/codes.json --only-show-errors")
sh(f"aws s3 cp {B}/cache/boltz_cache.tar /tmp/bc.tar --only-show-errors")
# Boltz-2 keeps its component library as one pickle per CCD code under mols/ (not a single ccd.pkl): the library is the set of file stems.
keys = set()
with tarfile.open("/tmp/bc.tar") as t:
    allnames = t.getnames()
for n in allnames:
    parts = n.split("/")
    if "mols" in parts and n.endswith(".pkl"):
        keys.add(os.path.basename(n)[:-4])
print("tar members:", len(allnames), "| sample non-mols:", [n for n in allnames if "mols" not in n][:6], flush=True)
print("n ccd components in boltz library:", len(keys), "| has ALA/DTR/MLE:", all(k in keys for k in ("ALA", "DTR", "MLE")), flush=True)
assert len(keys) > 1000, "library not found in cache tar"
codes = json.load(open("/tmp/codes.json"))
out = {c: [x for x in v if x not in keys] for c, v in codes.items()}
json.dump(dict(n_library=len(keys), missing=out), open("/tmp/ccd_check.json", "w"))
sh(f"aws s3 cp /tmp/ccd_check.json {B}/ccd_check/ccd_check.json --only-show-errors")
print("done; complexes with any missing code:", sum(1 for v in out.values() if v), "of", len(out), flush=True)
