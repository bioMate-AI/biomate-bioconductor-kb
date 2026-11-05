#!/usr/bin/env python3
"""Independent review of a work packet by a committee of LLMs from different vendors (OpenRouter).

Each reviewer gets the same packet + code diffs and returns structured findings. Raw responses are saved verbatim;
findings are NOT applied automatically — each one is verified against the code and data by the engineer, and the
triage (adopted / rejected / deferred, with evidence) is recorded separately.

Usage: scripts/review/llm_committee_review.py <packet.md> <diffs.txt> <out_dir> [model,model,...]
"""
import json, os, sys, time, urllib.request
from concurrent.futures import ThreadPoolExecutor

KEY = open(os.path.expanduser("~/.config/biomate/openrouter.key")).read().strip()
DEFAULT = ["anthropic/claude-opus-5.5", "openai/gpt-5.6-terra", "google/gemini-4-argon",
           "moonshotai/kimi-k3", "deepseek/deepseek-v4-pro"]
FALLBACK = {"anthropic/claude-opus-5.5": "anthropic/claude-sonnet-5.5"}

SYSTEM = """You are a senior reviewer (bioinformatics platform engineering, information retrieval, ML evaluation).
Review the work packet and the code diffs that follow. Be rigorous and specific. Find real problems; do not pad.
A wrong finding stated confidently is worse than a missing one — say "uncertain" when you are."""

ASK = """Return your review as ONE JSON object, no prose outside it:
{
  "summary": "<5-8 sentences: overall assessment>",
  "findings": [
    {"id": "F1", "severity": "critical|major|minor", "area": "<short>", "location": "<file:function or packet section>",
     "claim": "<what is wrong>", "evidence": "<quote code/number from the packet or diffs>",
     "suggested_fix": "<concrete>", "confidence": "high|medium|low",
     "depends_on_unseen": true|false}
  ],
  "keep": ["<things that are right and should not be changed, with reason>"],
  "answers": {"q1": "...", "q2": "...", "q3": "...", "q4": "...", "q5": "...", "q6": "..."}
}"""


def call(model, packet, diffs):
    body = json.dumps({"model": model, "temperature": 0.2, "max_tokens": 16000,
                       "messages": [{"role": "system", "content": SYSTEM},
                                    {"role": "user", "content": f"{packet}\n\n=== CODE DIFFS ===\n{diffs}\n\n{ASK}"}]}).encode()
    req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", data=body, method="POST",
                                 headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
    last = ""
    for attempt in range(3):
        try:
            t0 = time.time()
            with urllib.request.urlopen(req, timeout=900) as r:
                j = json.loads(r.read())
            text = j["choices"][0]["message"].get("content") or ""
            if text.strip():
                return {"model": model, "secs": round(time.time() - t0), "usage": j.get("usage"), "text": text}
            last = "empty response"
        except Exception as e:  # noqa: BLE001
            last = str(e)[:300]
        time.sleep(10 * (attempt + 1))
    return {"model": model, "error": last}


def review(model, packet, diffs):
    r = call(model, packet, diffs)
    if (r.get("error") or not r.get("text")) and model in FALLBACK:
        r2 = call(FALLBACK[model], packet, diffs)
        r2["fallback_for"] = model
        return r2
    return r


def main():
    packet, diffs, out = open(sys.argv[1]).read(), open(sys.argv[2]).read(), sys.argv[3]
    models = sys.argv[4].split(",") if len(sys.argv) > 4 else DEFAULT
    os.makedirs(out, exist_ok=True)
    with ThreadPoolExecutor(len(models)) as ex:
        for r in ex.map(lambda m: review(m, packet, diffs), models):
            name = (r.get("fallback_for") or r["model"]).replace("/", "_")
            json.dump(r, open(os.path.join(out, f"{name}.json"), "w"), indent=1)
            print(r["model"], "ERROR " + r["error"] if r.get("error") else f"{r['secs']}s usage={r.get('usage')}", flush=True)


if __name__ == "__main__":
    main()
