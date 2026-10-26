"""Score + featurize all samples of one or more complexes (streams from S3, keeps only small outputs).

usage: score_complex.py MODEL OUT.jsonl CID [CID...]     env: BENCH_INP (dir with <cid>/{meta.json,native.pdb}), BENCH_S3 (s3 prefix, default below)
One JSON line per (complex, sample): GT-dependent metrics (DockQ default + capri_peptide variant) and GT-free features.
Resumable: complexes already present in OUT.jsonl are skipped.
"""
import json, os, shutil, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scoring as S

S3 = os.environ.get("BENCH_S3", "s3://biomate-nextflow-work/cyclic_peptide/cofold_bench")


def score_complex(cid, inp_dir, samp_dir, work, n_expected=None):
    meta = json.load(open(f"{inp_dir}/{cid}/meta.json"))
    native = f"{inp_dir}/{cid}/native.pdb"
    ids = sorted(int(f.split("_")[1].split(".")[0]) for f in os.listdir(samp_dir) if f.startswith("sample_") and f.endswith(".cif"))
    if n_expected and len(ids) != n_expected:
        raise RuntimeError(f"{cid}: {len(ids)} samples, expected {n_expected}")
    pae = json.load(open(f"{samp_dir}/pae_if.json")) if os.path.exists(f"{samp_dir}/pae_if.json") else {}
    chains = meta["receptor_chains"] + ["Z"]
    rows, coords = [], []
    for i in ids:
        pdb = S.normalize_to_pdb(f"{samp_dir}/sample_{i}.cif", f"{work}/s{i}.pdb")
        r = dict(complex_id=cid, sample=i)
        r.update(S.sample_features(pdb, f"{samp_dir}/confidence_{i}.json", meta, pae.get(str(i))))
        for tag, capri in (("", False), ("capri_", True)):
            m = S.dockq_metrics(pdb, native, chains, capri_peptide=capri)
            if "error" in m:
                r[tag + "dockq_error"] = m["error"]
            else:
                p = m["primary"]
                r.update({f"{tag}dockq": p["DockQ"], f"{tag}irmsd": p["iRMSD"], f"{tag}lrmsd": p["LRMSD"], f"{tag}fnat": p["fnat"]})
                if not capri:
                    r["primary_iface"] = p["iface"]
        coords.append(S.pep_rec_coords(pdb))
        rows.append(r)
    cons, M, biggest = S.consensus_features(coords)
    for r, c in zip(rows, cons):
        r.update(c)
        r["cons_largest_cluster"] = biggest
    return rows


if __name__ == "__main__":
    model, out, cids = sys.argv[1], sys.argv[2], sys.argv[3:]
    inp = os.environ["BENCH_INP"]
    done = set()
    if os.path.exists(out):
        done = {json.loads(l)["complex_id"] for l in open(out)}
    for cid in cids:
        if cid in done:
            continue
        with tempfile.TemporaryDirectory(prefix="cc_") as w:
            sd = f"{w}/samples"
            os.makedirs(sd)
            r = subprocess.run(["aws", "s3", "cp", f"{S3}/samples/{model}/{cid}/", sd, "--recursive", "--only-show-errors"], capture_output=True, text=True)
            if r.returncode or not os.path.exists(f"{sd}/pae_if.json"):
                print(cid, "NO SAMPLES", r.stderr[:200], flush=True)
                continue
            try:
                rows = score_complex(cid, inp, sd, w)
            except Exception as e:
                print(cid, "SCORE FAIL", repr(e)[:300], flush=True)
                continue
        with open(out, "a") as fh:
            for r in rows:
                fh.write(json.dumps(r) + "\n")
        print(cid, "scored", len(rows), flush=True)
