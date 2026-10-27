"""Local (no-AWS) Boltz-2 driver for the Spark box: same outputs as cofold_boltz_driver.py, plain folders instead of S3, so NO cloud credentials are needed on the machine.
usage: cofold_local.py IN_DIR OUT_DIR IDS_FILE [N_SAMPLES=25] [SEED=0]      IN_DIR/<cid>/{boltz.yaml,meta.json}   ->   OUT_DIR/<cid>/{sample_i.cif,confidence_i.json,pae_if.json,run.json,msa_*}
Resumable: a complex with OUT_DIR/<cid>/run.json is skipped. Exit status 1 if any complex failed (never report success on failure).
"""
import glob, json, os, shutil, subprocess, sys, time, traceback
import numpy as np


def interface_pae(pae_npz, n_rec_tokens):
    z = np.load(pae_npz); pae = z[z.files[0]]; n = pae.shape[0]
    rec, pep = slice(0, n_rec_tokens), slice(n_rec_tokens, n)
    return dict(n_tokens=int(n), n_pep_tokens=int(n - n_rec_tokens), pae_pep_to_rec=float(pae[pep, rec].mean()), pae_rec_to_pep=float(pae[rec, pep].mean()),
                pae_if_mean=float((pae[pep, rec].mean() + pae[rec, pep].mean()) / 2), pae_pep_pep=float(pae[pep, pep].mean()))


def collect(work, dest, n_rec_tokens, n_expected):
    """Boltz output tree under work/out -> dest (same layout/names as the S3 driver). Returns (n_cifs, n_pae, msa_files). FILES ONLY for the MSA copy."""
    cifs = sorted(glob.glob(f"{work}/out/**/*_model_*.cif", recursive=True))
    if len(cifs) != n_expected:
        return len(cifs), 0, []
    os.makedirs(dest, exist_ok=True); paes = {}
    for c in cifs:
        i = int(c.rsplit("_model_", 1)[1].split(".")[0]); shutil.copy(c, f"{dest}/sample_{i}.cif")
        head, tail = c.rsplit("_model_", 1)[0].rsplit("/", 1)
        shutil.copy(f"{head}/confidence_{tail}_model_{i}.json", f"{dest}/confidence_{i}.json")
        pae = f"{head}/pae_{tail}_model_{i}.npz"
        if os.path.exists(pae):
            paes[i] = interface_pae(pae, n_rec_tokens)
    json.dump(paes, open(f"{dest}/pae_if.json", "w"))
    msa = []
    for m in glob.glob(f"{work}/out/**/msa/*", recursive=True):
        if os.path.isfile(m):
            try: shutil.copy(m, f"{dest}/msa_{os.path.basename(m)}"); msa.append(os.path.basename(m))
            except OSError: pass
    return len(cifs), len(paes), msa


def run_one(cid, in_dir, out_dir, n, seed, cache):
    t0 = time.time(); work = f"/tmp/cofold_work/{cid}"; shutil.rmtree(work, ignore_errors=True); os.makedirs(work)
    meta = json.load(open(f"{in_dir}/{cid}/meta.json")); n_rec = sum(len(s) for s in meta["rec_seq"].values())
    rec = dict(complex_id=cid, n_samples=n, seed=seed, status="fail", host="spark-gb10")
    dest = f"{out_dir}/{cid}"
    for attempt, mps in enumerate([n, 5, 1]):          # unified 121 GB memory: try all samples in parallel first, then back off
        cmd = ["boltz", "predict", f"{in_dir}/{cid}/boltz.yaml", "--out_dir", f"{work}/out", "--cache", cache, "--use_msa_server", "--model", "boltz2",
               "--diffusion_samples", str(n), "--max_parallel_samples", str(mps), "--output_format", "mmcif", "--accelerator", "gpu", "--devices", "1",
               "--num_workers", "0", "--seed", str(seed), "--no_kernels", "--write_full_pae", "--override"]
        r = subprocess.run(cmd, capture_output=True, text=True)
        open(f"{work}/boltz_attempt{attempt}.log", "w").write((r.stdout or "") + (r.stderr or ""))
        n_cif, n_pae, msa = collect(work, dest, n_rec, n)
        if r.returncode == 0 and n_cif == n:
            rec.update(status="ok", seconds=round(time.time() - t0, 1), n_cifs=n_cif, max_parallel_samples=mps, n_rec_tokens=n_rec, have_pae=n_pae, msa_files=msa)
            json.dump(rec, open(f"{dest}/run.json", "w")); shutil.rmtree(work, ignore_errors=True); return rec
        rec[f"attempt_{attempt}_rc"] = r.returncode; rec[f"attempt_{attempt}_cifs"] = n_cif
        tail = (r.stderr or "")[-300:].replace("\n", " "); rec[f"attempt_{attempt}_tail"] = tail
        shutil.rmtree(f"{work}/out", ignore_errors=True)
    rec["error"] = "boltz failed on all attempts"; os.makedirs(dest, exist_ok=True); json.dump(rec, open(f"{dest}/run_FAILED.json", "w")); return rec


if __name__ == "__main__":
    in_dir, out_dir, ids_file = sys.argv[1:4]; n = int(sys.argv[4]) if len(sys.argv) > 4 else 25; seed = int(sys.argv[5]) if len(sys.argv) > 5 else 0
    cache = os.path.expanduser(os.environ.get("BOLTZ_CACHE", "~/.boltz")); os.makedirs(out_dir, exist_ok=True)
    ids = [l.strip() for l in open(ids_file) if l.strip()]; bad = []
    for cid in ids:
        if os.path.exists(f"{out_dir}/{cid}/run.json"): print(cid, "cached, skip", flush=True); continue
        try: rec = run_one(cid, in_dir, out_dir, n, seed, cache)
        except Exception as e: traceback.print_exc(); rec = dict(complex_id=cid, status="exception", error=str(e)[:300])
        print("RESULT", json.dumps({k: rec[k] for k in rec if not k.startswith("attempt_") or k.endswith("rc")}), flush=True)
        if rec.get("status") != "ok": bad.append(cid)
    print("ALL_DONE", len(ids), "failed:", bad, flush=True); sys.exit(1 if bad else 0)
