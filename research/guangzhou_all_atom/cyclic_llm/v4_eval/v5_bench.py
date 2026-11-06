"""Step-time / memory benchmark of the v5 trainer on synthetic data at the registered production shape (d=256, 6 layers, 8 heads, max_len 512, target memory 1280-d).
Run on the spot GPU queue before any real run; prints JSON with GPU/instance type, sec/step per config, peak memory. usage: python v5_bench.py"""
import os, sys, json, time, subprocess, urllib.request
import numpy as np, torch
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v5_train as T
def imds(path):
    try:
        tok = urllib.request.urlopen(urllib.request.Request("http://169.254.169.254/latest/api/token", method="PUT", headers={"X-aws-ec2-metadata-token-ttl-seconds": "60"}), timeout=2).read().decode()
        return urllib.request.urlopen(urllib.request.Request("http://169.254.169.254/latest/meta-data/" + path, headers={"X-aws-ec2-metadata-token": tok}), timeout=2).read().decode()
    except Exception as e: return f"unavailable:{type(e).__name__}"
dev = "cuda" if torch.cuda.is_available() else "cpu"; V = 280; TD = 1280
out = {"instance_type": imds("instance-type"), "az": imds("placement/availability-zone"), "gpu": torch.cuda.get_device_name(0) if dev == "cuda" else "cpu", "torch": torch.__version__,
       "bf16": bool(dev == "cuda" and torch.cuda.is_bf16_supported())}
rng = np.random.default_rng(0)
def rows(n, L, with_target, tkeys):
    return [dict(ids=[1] + rng.integers(4, V, L - 2).tolist() + [2], target=(tkeys[i % len(tkeys)] if with_target else None), y=(float(rng.normal(7, 1)) if with_target else None), rel=0) for i in range(n)]
def bench(name, mk, steps, **kw):
    torch.manual_seed(0); m = T.V5Model(V, d=256, layers=6, heads=8, max_len=512, target_dim=TD); data = mk()
    if dev == "cuda": torch.cuda.reset_peak_memory_stats()
    T.train(m, data, 5, seed=0, device=dev, amp=True, **kw)       # warm-up (not timed)
    if dev == "cuda": torch.cuda.synchronize()
    t0 = time.time(); T.train(m, data, steps, seed=1, device=dev, amp=True, **kw)
    if dev == "cuda": torch.cuda.synchronize()
    dt = (time.time() - t0) / steps
    out[name] = {"sec_per_step": round(dt, 4), "steps": steps, "peak_gb": round(torch.cuda.max_memory_allocated() / 1e9, 2) if dev == "cuda" else None, **{k: v for k, v in kw.items()}}
    print(name, out[name], flush=True)
tg = {f"t{i}": rng.normal(size=(int(rng.integers(300, 1000)), TD)).astype("float32") for i in range(8)}; tk = sorted(tg)
S = 500 if dev == "cuda" else 3
# (1) pretraining proxy: LM-only, batch 128, length 128 (macrocycle-upsampled corpus mean ~50 tokens, macrocycles 100-300): 500 steps as specified
bench("pretrain_lm_b128_len128", lambda: T.V5Data(rows(2000, 128, False, tk), tg, TD), S, lm_w=1.0, aff_w=0.0, rank_w=0.0, lm_bs=128)
# (2) worst-case length: LM batch 32 at the 512 limit
bench("pretrain_lm_b32_len512", lambda: T.V5Data(rows(500, 512, False, tk), tg, TD), max(S // 5, 3), lm_w=1.0, aff_w=0.0, rank_w=0.0, lm_bs=32)
# (3) affinity fine-tuning step: within-target batch 32 at len 300 with a real-size target memory (<=1000 residues), tobit + hard-negative ranking
bench("affinity_b32_len300_target", lambda: T.V5Data(rows(800, 300, True, tk), tg, TD), max(S // 5, 3), lm_w=0.0, aff_w=1.0, rank_w=1.0, bs=32)
json.dump(out, open("/tmp/v5_bench.json", "w"), indent=1); print("V5_BENCH", json.dumps(out))
