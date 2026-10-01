"""A1 — CoT-distillation data builder. DUAL strong-reasoner teachers (Claude Opus 5.5 + GPT-6 Solar,
alternating for trace diversity; Gemini is NOT a teacher). Per-task contract -> forward step-by-step reasoning
-> REJECT-SAMPLE verify (keep iff the teacher's final answer salient-F1-matches the grounded gold) -> emit
Qwen3 thinking format `<think>{trace}</think>\n{gold}`. Trains reasoning skill; final answer stays the grounded
gold. Usage:
  python build_cot_distill.py --in multitask_sft_v5_norm.jsonl --out cot_distill.jsonl --max-per-task 400
"""
import argparse, json, os, re, time, urllib.request, collections
from concurrent.futures import ThreadPoolExecutor

HARD = {"findings_interpretation", "conclusion_drawing", "task_decomposition", "out_of_catalog_composition",
        "parameter_extraction", "tool_recommendation", "workflow_generation"}
CONTRACT = {
 "findings_interpretation": "Interpret these analysis RESULTS into the KEY FINDINGS (what they MEAN biologically). Interpret, do not restate. Ground every claim ONLY in the given input.",
 "conclusion_drawing": "Reason to a CONCLUSION plus implications/next steps. Do NOT assert causation beyond what the results support. Ground ONLY in the given input.",
 "task_decomposition": "Reason to an ORDERED analysis plan; each step names a candidate (verbatim) from the input or GENERATE. Ground ONLY in the given candidates.",
 "out_of_catalog_composition": "No single workflow fits. Reason to an ordered plan mapping each step to a candidate from the input or GENERATE; ABSTAIN if truly infeasible. Ground ONLY in the given candidates.",
 "parameter_extraction": "Reason to ONLY the context-dependent parameter values the input implies; justify each from the request/data; leave the rest to defaults. Ground ONLY in the given input.",
 "tool_recommendation": "Reason to the best-fitting tool(s) for the task, justified from the given descriptions. Ground ONLY in the given input.",
 "workflow_generation": "Reason the composition of a workflow from existing steps, with correct input/output wiring. Ground ONLY in the given input.",
}
DEFAULT_CONTRACT = "Reason step by step to the correct answer, grounded ONLY in the given input."

_WS = re.compile(r"\s+"); _STOP = set("the a an of to and or for with is are was on in at by from this that these those into as be it its".split())


def salient(s):
    bt = re.findall(r"`([^`]+)`", s or ""); nums = re.findall(r"\d+\.?\d*", s or "")
    w = [x for x in _WS.sub(" ", re.sub(r"[^a-z0-9 ]", " ", (s or "").lower())).split() if len(x) > 3 and x not in _STOP]
    return {t for t in (set(x.lower() for x in bt) | set(nums) | set(w[:40])) if t}


def f1(a, b):
    A, B = salient(a), salient(b)
    if not A or not B:
        return 0.0
    inter = len(A & B)
    p, r = inter / len(B), inter / len(A)
    return 0.0 if p + r == 0 else 2 * p * r / (p + r)


def anthropic_key():
    for f in ("/Users/kky/biomate-review/SETUP_CHECKLIST.md",):
        try:
            m = re.search(r"sk-ant-[A-Za-z0-9_-]{20,}", open(f).read())
            if m:
                return m.group(0)
        except Exception:
            pass
    return os.environ.get("ANTHROPIC_API_KEY")


AK = anthropic_key(); OK = os.environ.get("OPENAI_API_KEY")


def call_teacher(provider, model, prompt, n=900):
    for _ in range(3):
        try:
            if provider == "anthropic":
                b = json.dumps({"model": model, "max_tokens": n, "messages": [{"role": "user", "content": prompt}]}).encode()
                d = json.load(urllib.request.urlopen(urllib.request.Request("https://api.anthropic.com/v1/messages", b,
                    {"x-api-key": AK, "anthropic-version": "2023-06-01", "content-type": "application/json"}), timeout=90))
                return "".join(p.get("text", "") for p in d.get("content", []))
            else:
                b = json.dumps({"model": model, "messages": [{"role": "user", "content": prompt}], "max_completion_tokens": n + 400}).encode()
                d = json.load(urllib.request.urlopen(urllib.request.Request("https://api.openai.com/v1/chat/completions", b,
                    {"Authorization": f"Bearer {OK}", "Content-Type": "application/json"}), timeout=120))
                return d["choices"][0]["message"]["content"]
        except Exception:
            time.sleep(2)
    return ""


TEACHERS = [("anthropic", "claude-opus-5-5"), ("openai", "gpt-6.1-sol")]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", required=True); ap.add_argument("--out", required=True)
    ap.add_argument("--max-per-task", type=int, default=400); ap.add_argument("--workers", type=int, default=12)
    ap.add_argument("--f1-keep", type=float, default=0.4)
    a = ap.parse_args()
    rows = [json.loads(l) for l in open(a.inp) if l.strip()]
    per = collections.Counter(); seeds = []
    for i, r in enumerate(rows):
        t = r.get("task")
        if t not in HARD or per[t] >= a.max_per_task:
            continue
        m = {x["role"]: x["content"] for x in r["messages"]}
        if not (m.get("user") and m.get("assistant")):
            continue
        per[t] += 1
        seeds.append((len(seeds), t, m["user"], m["assistant"]))
    print(f"seeds: {len(seeds)} across {dict(per)}", flush=True)

    def one(seed):
        idx, task, user, gold = seed
        prov, model = TEACHERS[idx % len(TEACHERS)]   # alternate teachers for diversity
        contract = CONTRACT.get(task, DEFAULT_CONTRACT)
        prompt = (f"You are an expert bioinformatician producing a reasoning trace for training.\n{contract}\n\n"
                  f"TASK INPUT:\n{user}\n\nReply ONLY JSON: {{\"reasoning\": \"concise numbered step-by-step "
                  f"reasoning grounded only in the input\", \"final_answer\": \"the answer\"}}.")
        o = call_teacher(prov, model, prompt)
        mm = re.search(r"\{.*\}", o, re.S)
        if not mm:
            return None
        try:
            r = json.loads(mm.group(0))
        except Exception:
            return None
        trace, fa = str(r.get("reasoning", "")).strip(), str(r.get("final_answer", "")).strip()
        if len(trace) < 40 or f1(fa, gold) < a.f1_keep:   # reject if reasoning led away from the grounded gold
            return None
        return {"messages": [{"role": "user", "content": user},
                             {"role": "assistant", "content": f"<think>{trace}</think>\n{gold}"}],
                "task": task, "source": f"cot_distill_{model}"}

    out = []; kept = 0
    with ThreadPoolExecutor(max_workers=a.workers) as ex:
        for i, r in enumerate(ex.map(one, seeds)):
            if r:
                out.append(r); kept += 1
            if i % 200 == 0:
                print(f"  {i}/{len(seeds)} -> kept {kept}", flush=True)
    with open(a.out, "w") as f:
        for r in out:
            f.write(json.dumps(r) + "\n")
    print(f"COT DISTILL: {len(seeds)} seeds -> {kept} verified traces ({kept/max(1,len(seeds))*100:.1f}% keep) "
          f"-> {a.out}  by-task={dict(collections.Counter(r['task'] for r in out))}", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
