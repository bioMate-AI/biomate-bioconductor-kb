"""Benchmark-design fix for the removal eval (documented 2026-09-21).

Problem: ground_truth_steps were copied verbatim from the REMOVED workflow's step_metadata, so
~57% of cases are structurally uncoverable — the gold reads "Execute Documented <RemovedTool>
Pipeline" or names the removed tool's internal functions (RGSEAfix, topGeneQuants). A model composing
valid SUBSTITUTES can never "cover" a step that is literally the deleted tool. Both trained and
untrained models plateau at ~0.27; the metric can't see improvement.

Fix: regenerate ground_truth_steps as TOOL-AGNOSTIC analytical goals derived from the query (what any
correct workflow must accomplish), so a substitute plan can be fairly scored. Keeps query / candidates
/ removed_workflow / domain unchanged. Original preserved as removal_eval_toolsteps.jsonl.
"""
import json, os, re, sys, urllib.request, time
D = os.environ.get("EVAL_DIR", "/Users/kky/biomate-review/docs/20260912_onprem_llm/routing_data_v1")
KEY = os.environ["OPENAI_API_KEY"]
MODEL = os.environ.get("GT_MODEL", "gpt-5-mini")

PROMPT = (
    "You are designing the answer key for a bioinformatics benchmark. Given an analysis REQUEST, list "
    "the 3-6 essential ANALYTICAL steps that ANY correct workflow must perform to satisfy it.\n"
    "Rules:\n"
    "- Tool-agnostic: describe the OPERATION, never a specific package/tool/function name.\n"
    "- Analytical only: exclude trivial I/O ('read input', 'write output').\n"
    "- Each step is a concrete analytical goal (e.g. 'normalize raw counts', 'fit a differential model "
    "adjusting for batch', 'compute log2 fold-changes with adjusted p-values').\n"
    'Reply ONLY a JSON list of {"step": "...", "phase": "..."} (phase in {Preparation, Core Analysis, '
    "Visualization & Output}).\n\nREQUEST:\n"
)


def call(prompt):
    payload = {"model": MODEL, "messages": [{"role": "user", "content": prompt}],
               "max_completion_tokens": 2000}
    if MODEL.startswith("gpt-5"):
        payload["reasoning_effort"] = "low"
    else:
        payload["temperature"] = 0
    body = json.dumps(payload).encode()
    h = {"Content-Type": "application/json", "Authorization": f"Bearer {KEY}"}
    for a in range(4):
        try:
            d = json.load(urllib.request.urlopen(
                urllib.request.Request("https://api.openai.com/v1/chat/completions", data=body, headers=h), timeout=90))
            return d["choices"][0]["message"]["content"]
        except Exception as e:
            if a == 3:
                print("  call failed:", str(e)[:80])
            time.sleep(1.5 * (a + 1))
    return ""


def parse_steps(txt):
    if not txt:
        return None
    m = re.search(r"\[.*\]", txt, re.S)
    if not m:
        return None
    try:
        arr = json.loads(m.group(0))
    except Exception:
        return None
    out = [{"step": str(x["step"]), "phase": str(x.get("phase", "Core Analysis"))}
           for x in arr if isinstance(x, dict) and x.get("step")]
    return out if 2 <= len(out) <= 8 else None


def main():
    src = f"{D}/removal_eval.jsonl"
    rows = [json.loads(l) for l in open(src)]
    # back up original (tool-specific gold) once
    bak = f"{D}/removal_eval_toolsteps.jsonl"
    if not os.path.exists(bak):
        open(bak, "w").write("\n".join(json.dumps(r) for r in rows))
        print("backed up original ->", bak)
    kept = regenerated = 0
    for i, r in enumerate(rows):
        steps = parse_steps(call(PROMPT + r["query"][:1800]))
        if steps:
            r["ground_truth_steps"] = steps
            regenerated += 1
        else:
            kept += 1  # keep original on failure (rare)
        if (i + 1) % 25 == 0:
            print(f"  {i+1}/{len(rows)} (regen={regenerated} kept={kept})")
    open(src, "w").write("\n".join(json.dumps(r) for r in rows))
    print(f"DONE regen={regenerated} kept_original={kept} -> {src}")


if __name__ == "__main__":
    raise SystemExit(main())
