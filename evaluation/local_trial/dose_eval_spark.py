#!/usr/bin/env python3
"""On-prem dose eval against a local vLLM OpenAI endpoint (Spark GB10).

Scores one tier (hand | generated) of the BOIN dose-selection benchmark for one
served model. Metrics match the DrugDev manuscript:
  outcome  = exact MTD match (mtd_mg == true_MTD_mg; or correct no-MTD call)
  safety   = chosen dose's true DLT rate within target+0.10 band (1.0 if correct no-MTD)
  fidelity = fraction of per-dose DLT probabilities within 2x of truth (<=0.03 when truth 0)
Thinking is disabled (chat_template_kwargs.enable_thinking=False) for speed; empties tracked.
Writes per-item receipts so the aggregate is auditable.
"""
import argparse, json, re, urllib.request, os

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


def _num(x):
    try:
        return float(str(x).strip())
    except Exception:
        return None


def score_item(r, pred):
    inp, ref = r["inputs"], r["reference"]
    doses = json.loads(inp["dose_levels_json"]); tc = ref["true_dlt_rate_per_level"]
    gold = ref.get("true_MTD_mg"); tgt = inp["DLT_rate_target"]
    pm = _num(pred.get("mtd_mg")); pno = bool(pred.get("no_mtd"))
    if gold is None:
        outcome = 1.0 if (pno or pm is None) else 0.0
    else:
        outcome = 1.0 if (not pno and pm is not None and pm == float(gold)) else 0.0
    if gold is None:
        safety = 1.0 if (pno or pm is None) else 0.0
    elif pno or pm is None:
        safety = 0.0
    else:
        dnum = [float(d) for d in doses]
        pi = dnum.index(pm) if pm in dnum else None
        safety = 1.0 if (pi is not None and tc[pi] <= tgt + ELIM + 1e-9) else 0.0
    pc = pred.get("per_dose_dlt") or []; hit = 0; n = len(tc)
    for k, t in enumerate(tc):
        if k < len(pc):
            p = _num(pc[k])
            if p is None:
                continue
            if (t > 0 and 0.5 <= max(p, 1e-6) / t <= 2.0) or (t == 0 and p <= 0.03):
                hit += 1
    return outcome, safety, (hit / n if n else 0.0)


THINK = os.environ.get("THINK", "0") == "1"   # enable reasoning (for arithmetic-heavy items)
MAXTOK = int(os.environ.get("MAXTOK") or ("4000" if THINK else "800"))


def ask(url, model, text):
    def call(with_nothink):
        payload = {"model": model, "messages": [{"role": "user", "content": text}],
                   "max_tokens": MAXTOK, "temperature": 0}
        # with_nothink=True means we explicitly DISABLE thinking; when THINK is on we skip that.
        if with_nothink and not THINK:
            payload["chat_template_kwargs"] = {"enable_thinking": False}
        req = urllib.request.Request(url, json.dumps(payload).encode(), {"Content-Type": "application/json"})
        c = json.loads(urllib.request.urlopen(req, timeout=300).read())["choices"][0]["message"].get("content") or ""
        c = re.sub(r"<think>.*?</think>", "", c, flags=re.S)   # strip reasoning block if present
        ms = re.findall(r"\{[^{}]*\}", c, re.S)                # take the LAST flat JSON object
        return json.loads(ms[-1]) if ms else {}
    for with_nothink in (True, False):   # fall back if the chat template rejects enable_thinking
        for _ in range(2):
            try:
                return call(with_nothink)
            except urllib.error.HTTPError as e:
                if with_nothink and e.code == 400:
                    break      # template likely rejects the kwarg -> retry without it
            except Exception:
                pass
    return {}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8000/v1/chat/completions")
    ap.add_argument("--model", required=True)
    ap.add_argument("--data", required=True)
    ap.add_argument("--tier", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    rows = [json.loads(l) for l in open(a.data)]
    O = S = F = 0.0; n = 0; emp = 0; rec = []
    for r in rows:
        p = ask(a.url, a.model, prompt(r))
        o, s, f = score_item(r, p); O += o; S += s; F += f; n += 1
        empty = not bool(p.get("per_dose_dlt"))
        if empty:
            emp += 1
        rec.append({"id": r["id"], "pred_mtd": p.get("mtd_mg"), "gold_mtd": r["reference"].get("true_MTD_mg"),
                    "outcome": o, "safety": s, "fidelity": round(f, 3), "empty": empty})
    res = {"model": a.model, "tier": a.tier, "n": n, "outcome": round(O / n, 3),
           "safety": round(S / n, 3), "fidelity": round(F / n, 3), "empties": emp, "per_item": rec}
    json.dump(res, open(a.out, "w"), indent=2)
    print(f"{a.model} {a.tier}: outcome={res['outcome']} safety={res['safety']} "
          f"fidelity={res['fidelity']} empties={emp}/{n}", flush=True)


if __name__ == "__main__":
    main()
