"""Per-checkpoint evaluation -> learning curve + best-checkpoint selection.
For SFT checkpoints: gold routing accuracy (accept-set, 279 cases) per checkpoint.
For MIDTRAIN checkpoints: knowledge probe = mean NLL (perplexity proxy) on a held-out text sample
  (agent-task metrics are meaningless pre-instruction). Pick metric with --mode sft|midtrain.
Usage: python eval_checkpoints.py --base <p> --ckpt-root <dir-with-checkpoint-*> --mode sft \
         --evalfile gold_routing_eval.jsonl --out curve.json
"""
import argparse, glob, json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def norm(s): return re.sub(r"[^a-z0-9]+", " ", str(s).lower()).strip()
def answer_of(o): return o.rsplit("</think>", 1)[1].strip() if "</think>" in o else o.strip()


def gold_routing(rows):
    from eval_removal import call_direct_batch
    prompts = ["You are BioMate. Choose the single best workflow for this request from the candidates. "
               f"Reply ONLY the exact workflow name.\n\nRequest: {r['query']}\n\nCandidates:\n" +
               "\n".join(f"- {c}" for c in r["candidates"]) for r in rows]
    outs = []
    BS = int(os.environ.get("GEN_BATCH", "24"))
    for i in range(0, len(prompts), BS):
        outs.extend(call_direct_batch(prompts[i:i + BS], 256))
    hit = 0
    for r, o in zip(rows, outs):
        ans = norm(answer_of(o))
        if any(norm(x) in ans for x in r["accept"]): hit += 1
    return round(hit / max(len(rows), 1), 4)


def knowledge_nll(texts):
    import torch
    from eval_removal import _DIRECT
    m, tok = _DIRECT["model"], _DIRECT["tok"]
    tot, n = 0.0, 0
    for t in texts:
        enc = tok(t[:1500], return_tensors="pt", truncation=True, max_length=512).to(m.device)
        with torch.no_grad():
            loss = m(**enc, labels=enc["input_ids"]).loss
        tot += float(loss); n += 1
    return round(tot / max(n, 1), 4)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True); ap.add_argument("--ckpt-root", required=True)
    ap.add_argument("--mode", choices=["sft", "midtrain"], default="sft")
    ap.add_argument("--evalfile", default=""); ap.add_argument("--out", required=True)
    ap.add_argument("--probe", default="")  # jsonl of held-out texts for midtrain NLL
    a = ap.parse_args()
    from eval_removal import direct_load
    os.environ["EVAL_DTYPE"] = "bf16"
    cks = sorted(glob.glob(os.path.join(a.ckpt_root, "checkpoint-*")),
                 key=lambda p: int(re.search(r"checkpoint-(\d+)", p).group(1)))
    cks.append(a.ckpt_root)  # also the final merged adapter dir
    rows = [json.loads(l) for l in open(a.evalfile)] if a.evalfile else []
    probe = [json.loads(l).get("text", "") for l in open(a.probe)][:200] if a.probe else []
    curve = []
    for ck in cks:
        if not os.path.exists(os.path.join(ck, "adapter_config.json")) and not os.path.exists(os.path.join(ck, "adapter_model.safetensors")):
            continue
        step = int(re.search(r"checkpoint-(\d+)", ck).group(1)) if "checkpoint-" in ck else "final"
        direct_load(a.base, ck)
        if a.mode == "sft" and rows:
            metric = {"gold_routing_accept": gold_routing(rows)}
        else:
            metric = {"knowledge_nll": knowledge_nll(probe)}
        curve.append({"step": step, **metric})
        print(f"[ckpt] step={step} {metric}", flush=True)
    best = (min(curve, key=lambda c: c["knowledge_nll"]) if a.mode == "midtrain"
            else max(curve, key=lambda c: c.get("gold_routing_accept", 0))) if curve else None
    json.dump({"mode": a.mode, "curve": curve, "best": best}, open(a.out, "w"), indent=2)
    print("CKPT CURVE:", json.dumps({"curve": curve, "best": best}))


if __name__ == "__main__":
    raise SystemExit(main())
