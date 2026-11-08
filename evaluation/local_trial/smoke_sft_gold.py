#!/usr/bin/env python3
"""Smoke-test the standing sft_gold vLLM endpoint.

Hits base + sft_gold on the same prompts (decomposition + findings) with greedy /
no-think settings that match the eval shim (harness_shim.py: enable_thinking=False,
temperature 0), so served behavior is comparable to the evaluated behavior.

Usage:
  python3 smoke_sft_gold.py http://<gpu-private-ip>:8000/v1
  # from the dev backend container (the only host allowed through the SG):
  #   docker exec biomate-galaxy-dev python3 - <this file> http://<ip>:8000/v1

Exit 0 if both models answer both prompts with non-empty, finish_reason=stop text.
Prints base vs sft_gold side by side so the operator can eyeball the delta
(decomposition should be a terse subtask list; findings a bounded narration).
"""
import json
import sys
import urllib.request

BASE_URL = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000/v1").rstrip("/")
KEY = sys.argv[2] if len(sys.argv) > 2 else None

PROMPTS = [
    (
        "decomposition",
        "Decompose this bioinformatics request into an ordered list of subtasks "
        "(one per line, terse): 'Call somatic variants from matched tumor/normal "
        "WGS FASTQs and annotate functional impact.'",
    ),
    (
        "findings",
        "You are a bioinformatics scientist. In 3-5 sentences, summarize the key "
        "findings from this RNA-seq result: 1,284 genes differentially expressed "
        "(FDR<0.05), 812 up / 472 down; top enriched pathway: oxidative "
        "phosphorylation (padj=3e-7); PCA separates treated vs control on PC1 (61% var).",
    ),
]


def call(model, prompt):
    body = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0,
        "max_tokens": 512,
        "stream": False,
        "chat_template_kwargs": {"enable_thinking": False},
    }
    req = urllib.request.Request(
        BASE_URL + "/chat/completions",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json",
                 **({"Authorization": "Bearer " + KEY} if KEY else {})},
    )
    with urllib.request.urlopen(req, timeout=180) as r:
        result = json.loads(r.read())
    choice = result["choices"][0]
    return choice["message"]["content"], choice.get("finish_reason")


def main():
    # vLLM serves base as "Qwen/Qwen3.5-9B" and the adapter as "sft_gold"
    ok = True
    for task, prompt in PROMPTS:
        print("=" * 78)
        print("TASK:", task)
        print("PROMPT:", prompt[:120], "...")
        for model in ("Qwen/Qwen3.5-9B", "sft_gold"):
            try:
                text, fr = call(model, prompt)
            except Exception as exc:  # noqa: BLE001
                print("  [%s] ERROR: %s" % (model, exc))
                ok = False
                continue
            clean = bool(text and text.strip()) and fr in ("stop", "length")
            ok = ok and clean
            print("  [%s] finish=%s len=%d%s" % (model, fr, len(text or ""),
                                                 "" if clean else "  <-- NOT CLEAN"))
            print("    " + (text or "").strip().replace("\n", "\n    ")[:700])
    print("=" * 78)
    print("SMOKE %s" % ("PASS" if ok else "FAIL"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
