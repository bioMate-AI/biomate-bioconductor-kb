#!/bin/bash
# On-prem dose e2e eval: serve Qwen/Qwen3.5-9B via vLLM, run both dose tiers (hand + generated),
# score outcome/safety/fidelity with empties tracking, upload result to S3. Self-terminating via the launcher.
set -uo pipefail
SCRATCH=${SCRATCH:-/opt/dlami/nvme}
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
cd "$SCRATCH"
echo "[dose] fetching dose data"
aws s3 cp "$S3/dose_eval/hand.jsonl" hand.jsonl --quiet
aws s3 cp "$S3/dose_eval/generated.jsonl" generated.jsonl --quiet
echo "[dose] starting vLLM (Qwen/Qwen3.5-9B)"
python3 -m vllm.entrypoints.openai.api_server --model Qwen/Qwen3.5-9B --served-model-name qwen \
  --max-model-len 12288 --gpu-memory-utilization 0.92 --port 8000 --enforce-eager > vllm.log 2>&1 &
for i in $(seq 1 120); do curl -s -m3 http://localhost:8000/health >/dev/null 2>&1 && break; sleep 10; done
if ! curl -s -m5 http://localhost:8000/health >/dev/null 2>&1; then
  echo "[dose] VLLM_FAILED"; tail -40 vllm.log; aws s3 cp vllm.log "$S3/eval/dose_onprem_vllm.log" --quiet; exit 1
fi
echo "[dose] vLLM ready; running eval"
python3 - <<'PY'
import json, re, urllib.request
INSTR = ("You are selecting the maximum tolerated dose (MTD) for a Phase-I trial. You are given PK and "
 "exposure-response (Emax) inputs and a dose grid. Model the probability of dose-limiting toxicity (DLT) at "
 "EACH dose level from the inputs, then select the MTD as the dose whose modeled DLT probability is closest to "
 "the target without exceeding it by more than 0.10; declare no MTD if even the lowest dose exceeds the target "
 "by more than 0.10. Return ONLY JSON: "
 '{"per_dose_dlt":[...one probability per dose level...],"mtd_mg":<number or null>,"no_mtd":<true|false>}')
ELIM = 0.10
def prompt(r):
    i = r["inputs"]
    return (f'{INSTR}\n\nTarget DLT rate: {i["DLT_rate_target"]}\nDose levels (mg): {i["dose_levels_json"]}\n'
            f'PK/ER inputs: {json.dumps({k: v for k, v in i.items() if k != "dose_levels_json"})}')
def score_item(r, pred):
    inp, ref = r["inputs"], r["reference"]; doses = json.loads(inp["dose_levels_json"]); tc = ref["true_dlt_rate_per_level"]
    gold = ref.get("true_MTD_mg"); tgt = inp["DLT_rate_target"]; pm = pred.get("mtd_mg"); pno = bool(pred.get("no_mtd"))
    if gold is None: outcome = 1.0 if (pno or pm is None) else 0.0
    else: outcome = 1.0 if (not pno and pm is not None and pm == gold) else 0.0
    if gold is None: safety = 1.0 if (pno or pm is None) else 0.0
    elif pno or pm is None: safety = 0.0
    else:
        pi = doses.index(pm) if pm in doses else None
        safety = 1.0 if (pi is not None and tc[pi] <= tgt + ELIM + 1e-9) else 0.0
    pc = pred.get("per_dose_dlt") or []; hit = 0; n = len(tc)
    for k, t in enumerate(tc):
        if k < len(pc):
            try:
                p = float(pc[k])
                if (t > 0 and 0.5 <= max(p, 1e-6) / t <= 2.0) or (t == 0 and p <= 0.03): hit += 1
            except Exception: pass
    return outcome, safety, (hit / n if n else 0.0)
def ask(text):
    body = json.dumps({"model": "qwen", "messages": [{"role": "user", "content": text}],
                       "max_tokens": 10000, "temperature": 0}).encode()
    req = urllib.request.Request("http://localhost:8000/v1/chat/completions", body, {"Content-Type": "application/json"})
    for _ in range(3):
        try:
            c = json.loads(urllib.request.urlopen(req, timeout=300).read())["choices"][0]["message"].get("content") or ""
            m = re.search(r"\{.*\}", c, re.S)
            if m:
                try: return json.loads(m.group())
                except Exception: pass
        except Exception: pass
    return {}
out = {}
for tier, fn in [("hand", "hand.jsonl"), ("generated", "generated.jsonl")]:
    rows = [json.loads(l) for l in open(fn)]; O = S = F = 0; n = 0; emp = 0; rec = []
    for r in rows:
        p = ask(prompt(r)); o, s, f = score_item(r, p); O += o; S += s; F += f; n += 1
        if not p.get("per_dose_dlt"): emp += 1
        rec.append({"id": r["id"], "outcome": o, "fidelity": round(f, 2), "empty": not bool(p.get("per_dose_dlt"))})
    out[tier] = {"model": "Qwen/Qwen3.5-9B (local vLLM)", "n": n, "outcome": round(O/n, 3),
                 "safety": round(S/n, 3), "fidelity": round(F/n, 3), "empties": emp, "per_item": rec}
    print(tier, "outcome", out[tier]["outcome"], "fidelity", out[tier]["fidelity"], "empties", emp, flush=True)
json.dump(out, open("dose_onprem_result.json", "w"), indent=2)
PY
aws s3 cp dose_onprem_result.json "$S3/eval/dose_onprem_result.json" --quiet && echo "DOSE_ONPREM_DONE"
aws s3 cp vllm.log "$S3/eval/dose_onprem_vllm.log" --quiet
