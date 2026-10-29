"""Control-plane launcher (laptop runs only `aws` CLI calls): merge shard outputs, aggregate, build cards, run tests, on EC2 spot.
usage (from allatom_paper/): python3 structure_knowledge/launch_final.py RID shardPrefix1 shardPrefix2 ...
Shard prefixes are S3 run ids under s3://biomate-nextflow-work/cyclic_peptide/allatom/k3/. Features/meta are read from <shard>/out/lib/ when the shard
finished, else from <shard>/out_live/ (the live copy)."""
import os
import subprocess
import sys
import time

sys.path.insert(0, ".")
from orchestrator import ec2  # noqa: E402

B = "s3://biomate-nextflow-work/cyclic_peptide/allatom/k3"


def main() -> None:
    shards = sys.argv[1:]
    rid = "final-" + time.strftime("%H%M%S", time.gmtime())
    P = f"{B}/{rid}"
    here = os.path.dirname(os.path.abspath(__file__))
    repo_data = os.path.abspath(os.path.join(here, "..", "..", "..", "data", "bound_cyclic", "v2", "bound_cyclic_manifest.jsonl"))
    tkb = os.path.abspath(os.path.join(here, "..", "..", "target_kb"))
    subprocess.run(["aws", "s3", "cp", repo_data, f"{P}/in/manifest.jsonl", "--only-show-errors"], check=True)
    subprocess.run(["aws", "s3", "cp", tkb, f"{P}/in/target_kb", "--recursive", "--exclude", "*.jsonl", "--only-show-errors"], check=True)
    subprocess.run(["aws", "s3", "cp", f"{B}/full1-171811/out_live/import/", f"{P}/in/import/", "--recursive", "--only-show-errors"], check=True)
    get = []
    for i, s in enumerate(shards):
        get.append(f"(aws s3 cp {B}/{s}/out/lib/features.jsonl /w/in/f{i}.jsonl --only-show-errors || aws s3 cp {B}/{s}/out_live/features.jsonl /w/in/f{i}.jsonl --only-show-errors)")
        get.append(f"(aws s3 cp {B}/{s}/out/lib/meta.jsonl /w/in/m{i}.jsonl --only-show-errors || aws s3 cp {B}/{s}/out_live/meta.jsonl /w/in/m{i}.jsonl --only-show-errors)")
    merge = ("python3.11 - <<'PY'\nimport glob, json\n"
             "seen=set(); out=open('/w/out/lib/features.jsonl','w')\n"
             "for f in sorted(glob.glob('/w/in/f*.jsonl')):\n"
             "    for l in open(f):\n"
             "        try: d=json.loads(l)\n"
             "        except Exception: continue\n"
             "        k=(d.get('pdb_id'),d.get('pep_chain'))\n"
             "        if k in seen: continue\n"
             "        seen.add(k); out.write(l if l.endswith('\\n') else l+'\\n')\n"
             "out.close(); seen=set(); out=open('/w/out/lib/meta.jsonl','w')\n"
             "for f in sorted(glob.glob('/w/in/m*.jsonl')):\n"
             "    for l in open(f):\n"
             "        try: d=json.loads(l)\n"
             "        except Exception: continue\n"
             "        k=d.get('rcsb_id')\n"
             "        if k in seen: continue\n"
             "        seen.add(k); out.write(l if l.endswith('\\n') else l+'\\n')\n"
             "out.close()\nPY")
    cmd = " ; ".join([
        "python3.11 -m pip install -q gemmi",
        "mkdir -p /w/in /w/out/lib /w/out/agg /w/out/agg_excl_armG",
        f"aws s3 cp $P/in/manifest.jsonl /w/manifest.jsonl --only-show-errors",
        f"aws s3 cp $P/in/target_kb /w/target_kb --recursive --only-show-errors",
        f"aws s3 cp $P/in/import /w/out/import --recursive --only-show-errors",
        *get, merge,
        "wc -l /w/out/lib/features.jsonl /w/out/lib/meta.jsonl",
        "python3.11 structure_knowledge/aggregate.py --features /w/out/lib/features.jsonl --meta /w/out/lib/meta.jsonl --out /w/out/agg",
        "printf 'P06756\\nP18564\\nQ9NZQ7\\n' > /w/out/exclude_armG_example.txt",
        "python3.11 structure_knowledge/aggregate.py --features /w/out/lib/features.jsonl --meta /w/out/lib/meta.jsonl --out /w/out/agg_excl_armG --exclude-targets /w/out/exclude_armG_example.txt",
        "python3.11 structure_knowledge/cards.py --library /w/out/agg/library_v1.jsonl --targets-dir /w/target_kb --out /w/out/cards_v1.json --extra 'grpr=gastrin-releasing peptide receptor'",
        "K3_MANIFEST=/w/manifest.jsonl python3.11 -m pytest structure_knowledge/test_structure_knowledge.py -q --tb=short > /w/out/pytest.log 2>&1 ; tail -5 /w/out/pytest.log",
    ])
    ec2.upload_code(P)
    ud = f"/tmp/ud_k3_{rid}.sh"
    open(ud, "w").write(ec2.make_userdata(P, cmd, 60, pip="numpy scipy pytest pandas"))
    for t in ("c6i.2xlarge", "c6a.2xlarge", "m6i.2xlarge", "c5.2xlarge", "c6i.xlarge"):
        try:
            print(P, t, ec2.launch(ud, "allatom-k3", itype=t, root_gb=60), flush=True)
            return
        except Exception as e:  # noqa: BLE001
            last = str(e)[:100]
    raise SystemExit("launch failed: " + last)


if __name__ == "__main__":
    main()
