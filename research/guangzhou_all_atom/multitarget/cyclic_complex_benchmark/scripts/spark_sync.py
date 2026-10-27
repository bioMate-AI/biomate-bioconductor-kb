"""Pull finished Boltz complexes from the Spark box and publish them to the SAME S3 layout the AWS jobs use, from THIS machine (the Spark box has no cloud credentials).
usage: spark_sync.py [loops=1] [sleep_s=600]. A complex is published only if Spark wrote run.json (status ok) and S3 has no run.json for it yet. Never overwrites S3."""
import json, os, subprocess, sys, tempfile, time
K = os.path.expanduser("~/Downloads/spark-ssh-access-package")
SSH = ["ssh", "-i", f"{K}/keys/spark_train_ed25519", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-o", "HostKeyAlias=spark-d816",
       "-o", f"UserKnownHostsFile={K}/ssh/known_hosts", "yzhang@spark-d816.local"]
B = "s3://biomate-nextflow-work/cyclic_peptide/cofold_bench/samples/boltz"

def sh(cmd, **kw): return subprocess.run(cmd, capture_output=True, text=True, **kw)

def s3_has(cid): return bool(sh(["aws", "s3", "ls", f"{B}/{cid}/run.json", "--region", "us-west-2"]).stdout.strip())

def one_pass():
    r = sh(SSH + ["cd ~/cofold/spark_out && for d in */; do [ -f ${d}run.json ] && echo ${d%/}; done"])
    done = [c for c in r.stdout.split() if c]; pushed, skipped = [], 0
    for cid in done:
        if s3_has(cid): skipped += 1; continue
        tmp = tempfile.mkdtemp(prefix="spk_")
        p1 = subprocess.Popen(SSH + [f"cd ~/cofold/spark_out && tar -cf - {cid}"], stdout=subprocess.PIPE)
        p2 = subprocess.run(["tar", "-xf", "-", "-C", tmp], stdin=p1.stdout, capture_output=True); p1.wait()
        d = f"{tmp}/{cid}"
        if p1.returncode or not os.path.exists(f"{d}/run.json") or len([f for f in os.listdir(d) if f.startswith("sample_")]) < 25: print("incomplete pull, skip", cid); continue
        bad = [f for f in os.listdir(d) if f.startswith("sample_") and (os.path.getsize(f"{d}/{f}") == 0 or "_atom_site." not in open(f"{d}/{f}", errors="replace").read())]
        if bad: print("CORRUPT samples, not publishing", cid, bad); sh(["rm", "-rf", tmp]); continue
        # upload samples first, run.json LAST (run.json is the 'done' marker the AWS driver and the scorer rely on)
        u = sh(["aws", "s3", "cp", d, f"{B}/{cid}/", "--recursive", "--exclude", "run.json", "--only-show-errors", "--region", "us-west-2"])
        if u.returncode == 0: u = sh(["aws", "s3", "cp", f"{d}/run.json", f"{B}/{cid}/run.json", "--only-show-errors", "--region", "us-west-2"])
        sh(["rm", "-rf", tmp])
        if u.returncode == 0: pushed.append(cid)
        else: print("upload failed", cid, u.stderr[:150])
    print(time.strftime("%H:%M:%S"), f"spark finished={len(done)} already-on-S3={skipped} pushed-now={len(pushed)}", flush=True)
    return len(done)

if __name__ == "__main__":
    loops = int(sys.argv[1]) if len(sys.argv) > 1 else 1; gap = int(sys.argv[2]) if len(sys.argv) > 2 else 600
    for i in range(loops):
        one_pass()
        if i < loops - 1: time.sleep(gap)
