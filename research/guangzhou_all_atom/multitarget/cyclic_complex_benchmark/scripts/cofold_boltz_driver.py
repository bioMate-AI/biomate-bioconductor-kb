"""Runs INSIDE the Boltz image (python3.10, /opt/boltz-env) on an AWS Batch SPOT GPU job.

For each complex id: pull <IN_S3>/<cid>/boltz.yaml, run `boltz predict` (Boltz-2, ColabFold MSA server for the receptor,
peptide MSA empty), 25 diffusion samples from one trunk pass (Boltz trunk is deterministic given the input; seeds only change the
diffusion noise, so 5 seeds x 5 samples == 25 samples of one seed in distribution; documented in README), then push to
<OUT_S3>/<cid>/: sample_<i>.cif, confidence_<i>.json, pae_if.json (interface PAE, computed here to avoid shipping NxN arrays), run.json.
Resumable: skips a complex whose run.json already exists on S3. Weights are cached on S3 (<OUT_S3 root>/cache/boltz_cache.tar).

env: IN_S3 OUT_S3 IDS (comma separated) [N_SAMPLES=25] [SEED=0] [CACHE_S3]
"""
import glob, json, os, shutil, subprocess, sys, time, traceback
import numpy as np

IN_S3, OUT_S3 = os.environ["IN_S3"].rstrip("/"), os.environ["OUT_S3"].rstrip("/")
IDS = [x for x in os.environ["IDS"].split(",") if x]
N = int(os.environ.get("N_SAMPLES", "25"))
SEED = int(os.environ.get("SEED", "0"))
CACHE_S3 = os.environ.get("CACHE_S3", "s3://biomate-nextflow-work/cyclic_peptide/cofold_bench/cache/boltz_cache.tar")
CACHE = "/tmp/bcache"
W = "/tmp/work"
os.makedirs(W, exist_ok=True)


def sh(cmd, check=True, **kw):
    print("+", cmd if isinstance(cmd, str) else " ".join(cmd), flush=True)
    return subprocess.run(cmd, shell=isinstance(cmd, str), check=check, **kw)


def s3_exists(uri):
    return subprocess.run(["aws", "s3", "ls", uri], capture_output=True).returncode == 0 and \
        bool(subprocess.run(["aws", "s3", "ls", uri], capture_output=True, text=True).stdout.strip())


def restore_cache():
    os.makedirs(CACHE, exist_ok=True)
    if s3_exists(CACHE_S3):
        sh(f"aws s3 cp {CACHE_S3} /tmp/bc.tar --only-show-errors && tar -xf /tmp/bc.tar -C {CACHE} && rm /tmp/bc.tar")
        return True
    return False


def save_cache():
    if not s3_exists(CACHE_S3) and glob.glob(f"{CACHE}/*"):
        sh(f"tar -cf /tmp/bc.tar -C {CACHE} . && aws s3 cp /tmp/bc.tar {CACHE_S3} --only-show-errors && rm /tmp/bc.tar", check=False)


def interface_pae(pae_npz, n_rec_tokens):
    z = np.load(pae_npz)
    pae = z[z.files[0]]
    n = pae.shape[0]
    rec, pep = slice(0, n_rec_tokens), slice(n_rec_tokens, n)
    return dict(n_tokens=int(n), n_pep_tokens=int(n - n_rec_tokens),
                pae_pep_to_rec=float(pae[pep, rec].mean()), pae_rec_to_pep=float(pae[rec, pep].mean()),
                pae_if_mean=float((pae[pep, rec].mean() + pae[rec, pep].mean()) / 2), pae_pep_pep=float(pae[pep, pep].mean()))


def run_one(cid, have_cache):
    t0 = time.time()
    d = f"{W}/{cid}"
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    sh(f"aws s3 cp {IN_S3}/{cid}/boltz.yaml {d}/in.yaml --only-show-errors")
    meta = json.loads(subprocess.run(["aws", "s3", "cp", f"{IN_S3}/{cid}/meta.json", "-"], capture_output=True, text=True, check=True).stdout)
    n_rec_tokens = sum(len(s) for s in meta["rec_seq"].values())
    rec = dict(complex_id=cid, n_samples=N, seed=SEED, status="fail")
    for attempt, mps in enumerate([5, 1]):
        cmd = ["boltz", "predict", f"{d}/in.yaml", "--out_dir", f"{d}/out", "--cache", CACHE, "--use_msa_server", "--model", "boltz2",
               "--diffusion_samples", str(N), "--max_parallel_samples", str(mps), "--output_format", "mmcif", "--accelerator", "gpu",
               "--devices", "1", "--num_workers", "0", "--seed", str(SEED), "--no_kernels", "--write_full_pae", "--override"]
        r = sh(cmd, check=False)
        cifs = sorted(glob.glob(f"{d}/out/**/*_model_*.cif", recursive=True))
        if r.returncode == 0 and len(cifs) == N:
            break
        rec["attempt_%d_rc" % attempt] = r.returncode
        shutil.rmtree(f"{d}/out", ignore_errors=True)
    else:
        rec["error"] = "boltz failed (both max_parallel_samples=5 and 1)"
        json.dump(rec, open(f"{d}/run.json", "w"))
        sh(f"aws s3 cp {d}/run.json {OUT_S3}/{cid}/run_FAILED.json --only-show-errors", check=False)
        return rec
    paes = {}
    for c in cifs:
        i = int(c.rsplit("_model_", 1)[1].split(".")[0])
        shutil.copy(c, f"{d}/sample_{i}.cif")
        base = c.rsplit("_model_", 1)[0].rsplit("/", 1)
        conf = f"{base[0]}/confidence_{base[1]}_model_{i}.json"
        shutil.copy(conf, f"{d}/confidence_{i}.json")
        pae = f"{base[0]}/pae_{base[1]}_model_{i}.npz"
        if os.path.exists(pae):
            paes[i] = interface_pae(pae, n_rec_tokens)
    json.dump(paes, open(f"{d}/pae_if.json", "w"))
    msa = glob.glob(f"{d}/out/**/msa/*", recursive=True)
    rec.update(status="ok", seconds=round(time.time() - t0, 1), n_cifs=len(cifs), max_parallel_samples=mps, n_rec_tokens=n_rec_tokens,
               have_pae=len(paes), msa_files=[os.path.basename(m) for m in msa])
    json.dump(rec, open(f"{d}/run.json", "w"))
    # upload everything small; the MSA csv/a3m is kept for reproducibility
    for m in msa:
        shutil.copy(m, f"{d}/msa_{os.path.basename(m)}")
    sh(f"aws s3 cp {d} {OUT_S3}/{cid}/ --recursive --exclude 'out/*' --only-show-errors")
    save_cache()
    return rec


if __name__ == "__main__":
    have = restore_cache()
    print("weights cache restored from S3:", have, flush=True)
    summary = []
    for cid in IDS:
        if s3_exists(f"{OUT_S3}/{cid}/run.json"):
            print(cid, "cached, skip", flush=True)
            continue
        try:
            summary.append(run_one(cid, have))
        except Exception as e:
            traceback.print_exc()
            summary.append(dict(complex_id=cid, status="exception", error=str(e)[:300]))
        print("RESULT", json.dumps(summary[-1]), flush=True)
    print("ALL_DONE", json.dumps([(s["complex_id"], s["status"]) for s in summary]))
