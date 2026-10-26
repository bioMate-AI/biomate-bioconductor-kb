#!/usr/bin/env python3
"""Run the channel_routing benchmark for one or more LLMs, in BOTH conditions, and report each:
  * BARE       — query + the 7 channel NAMES only (the raw LLM's own routing judgment).
  * +HARNESS   — query + the 7 channel names WITH BioMate's production definitions (channels.json).
The bare→harness delta is the harness dividend for channel routing — the whole point (per project policy:
always report the LLM itself AND LLM+harness, to see model pros/cons and optimize the harness + local LLM).

Empties-aware (max_tokens budgeted past reasoning tokens, retry-on-empty, low concurrency) so reasoning
models don't produce fake 0s. Writes results/<model>/channel_routing_{bare,harness}.jsonl + a scored summary.

Usage:
  OPENROUTER_API_KEY=... python3 run_channel_routing.py --models qwen/qwen3.5-9b,anthropic/claude-opus-5,...
      [--max-tokens 2000] [--workers 3]
"""
import argparse, json, os, re, time, urllib.request, concurrent.futures as cf, importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))
CH = json.load(open(os.path.join(HERE, "channels.json")))
spec = importlib.util.spec_from_file_location("score", os.path.join(HERE, "score.py"))
S = importlib.util.module_from_spec(spec); spec.loader.exec_module(S)

NAMES = list(CH.keys())
BARE_LIST = "\n".join(f"- {c}" for c in NAMES)
HARNESS_LIST = "\n".join(f"- {c}: {CH[c]['def']}" for c in NAMES)


def prompt(query, harness):
    menu = HARNESS_LIST if harness else BARE_LIST
    return (f"You are a router. Decide which single channel this user request should be sent to. "
            f"Respond with EXACTLY one channel name from the list and nothing else.\n\nChannels:\n{menu}\n\n"
            f"Request: {query}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", required=True)
    ap.add_argument("--max-tokens", type=int, default=2000)
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--retries", type=int, default=4)
    a = ap.parse_args()
    key = os.environ["OPENROUTER_API_KEY"]
    gold = S.load_gold()
    rows = list(gold.values())
    nameset = {c.lower(): c for c in NAMES}

    def parse(raw):
        t = re.sub(r"[\s-]+", "_", (raw or "").strip().lower())
        for c in sorted(nameset, key=len, reverse=True):
            if c.replace("-", "_") in t:
                return nameset[c]
        return (raw or "").strip()[:40]

    def ask(model, q, harness):
        body = json.dumps({"model": model, "temperature": 0, "max_tokens": a.max_tokens,
                           "messages": [{"role": "user", "content": prompt(q, harness)}]}).encode()
        req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", data=body,
                                     headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
        for _ in range(a.retries):
            try:
                c = json.loads(urllib.request.urlopen(req, timeout=120).read())["choices"][0]["message"].get("content")
                if c and c.strip():
                    return c
            except Exception:
                pass
            time.sleep(3)
        return ""

    for model in a.models.split(","):
        outdir = os.path.join(HERE, "results", model.replace("/", "_"))
        os.makedirs(outdir, exist_ok=True)
        summary = {"model": model}
        for cond, harness in [("bare", False), ("harness", True)]:
            preds = {}
            with cf.ThreadPoolExecutor(max_workers=a.workers) as ex:
                for r, raw in zip(rows, ex.map(lambda r: ask(model, r["query"], harness), rows)):
                    preds[r["id"]] = parse(raw)
            with open(os.path.join(outdir, f"channel_routing_{cond}.jsonl"), "w") as f:
                for r in rows:
                    f.write(json.dumps({"id": r["id"], "prediction": preds[r["id"]]}) + "\n")
            sc = S.score(gold, preds)
            summary[cond] = {"accuracy": sc["accuracy"], "drug_discovery_accuracy": sc["drug_discovery_accuracy"],
                             "off_channel_or_empty": sc["off_channel_or_empty"]}
        b, h = summary["bare"]["accuracy"], summary["harness"]["accuracy"]
        summary["harness_dividend"] = round((h or 0) - (b or 0), 4)
        json.dump(summary, open(os.path.join(outdir, "channel_routing_summary.json"), "w"), indent=2)
        print(f"{model:32s} BARE acc={b} (dd={summary['bare']['drug_discovery_accuracy']}) | "
              f"+HARNESS acc={h} (dd={summary['harness']['drug_discovery_accuracy']}) | dividend={summary['harness_dividend']:+}")


if __name__ == "__main__":
    main()
