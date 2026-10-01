"""A1 — CoT-distillation data builder. DUAL strong-reasoner teachers (Claude Opus 5.5 + GPT-6 Solar).
FREE-FORM prompt + 'FINAL_ANSWER:' delimiter (Opus returns EMPTY for strict-JSON asks — it extended-thinks
and leaves no text; free-form works). Primary keep = CONSENSUS: both teachers independently reach the same
answer (salient-F1 >= thr) -> distill their consensus answer + reasoning, BYPASSING our weak generative-task
gold (the cause of the old 6.6% keep). Secondary keep = a single teacher reaching OUR gold. Emits Qwen3
thinking `<think>{trace}</think>\n{answer}`. Usage:
  python build_cot_distill.py --in multitask_sft_v5_norm.jsonl --out cot_distill.jsonl --max-per-task 250
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
    try:
        m = re.search(r"sk-ant-[A-Za-z0-9_-]{20,}", open("/Users/kky/biomate-review/SETUP_CHECKLIST.md").read())
        if m:
            return m.group(0)
    except Exception:
        pass
    return os.environ.get("ANTHROPIC_API_KEY")


AK = anthropic_key(); OK = os.environ.get("OPENAI_API_KEY")


def call_teacher(provider, model, prompt, n=1600):
    for _ in range(3):
        try:
            if provider == "anthropic":
                b = json.dumps({"model": model, "max_tokens": n, "messages": [{"role": "user", "content": prompt}]}).encode()
                d = json.load(urllib.request.urlopen(urllib.request.Request("https://api.anthropic.com/v1/messages", b,
                    {"x-api-key": AK, "anthropic-version": "2023-06-01", "content-type": "application/json"}), timeout=120))
                return "".join(p.get("text", "") for p in d.get("content", []) if p.get("type") == "text")
            else:
                b = json.dumps({"model": model, "messages": [{"role": "user", "content": prompt}], "max_completion_tokens": n + 600}).encode()
                d = json.load(urllib.request.urlopen(urllib.request.Request("https://api.openai.com/v1/chat/completions", b,
                    {"Authorization": f"Bearer {OK}", "Content-Type": "application/json"}), timeout=150))
                return d["choices"][0]["message"]["content"]
        except Exception:
            time.sleep(2)
    return ""


def parse(txt):
    """free-form -> (reasoning_trace, final_answer); None if no/short answer."""
    if "FINAL_ANSWER:" not in (txt or ""):
        return None, None
    i = txt.rfind("FINAL_ANSWER:")
    trace = re.sub(r"^\s*(reasoning\s*:)", "", txt[:i].strip(), flags=re.I).strip()
    ans = txt[i + len("FINAL_ANSWER:"):].strip()
    return (trace, ans) if (len(trace) >= 40 and len(ans) >= 2) else (None, None)


OPUS = ("anthropic", "claude-opus-5-5"); SOLAR = ("openai", "gpt-6.1-sol")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", required=True); ap.add_argument("--out", required=True)
    ap.add_argument("--max-per-task", type=int, default=250); ap.add_argument("--workers", type=int, default=10)
    ap.add_argument("--consensus-f1", type=float, default=0.4); ap.add_argument("--gold-f1", type=float, default=0.5)
    a = ap.parse_args()
    rows = [json.loads(l) for l in open(a.inp) if l.strip()]
    per = collections.Counter(); seeds = []
    for r in rows:
        t = r.get("task")
        if t not in HARD or per[t] >= a.max_per_task:
            continue
        m = {x["role"]: x["content"] for x in r["messages"]}
        if not (m.get("user") and m.get("assistant")):
            continue
        per[t] += 1
        seeds.append((len(seeds), t, m["user"], m["assistant"]))
    print(f"seeds: {len(seeds)} across {dict(per)}", flush=True)

    def ask(prov_model, task, user):
        contract = CONTRACT.get(task, DEFAULT_CONTRACT)
        prompt = (f"You are an expert bioinformatician. {contract}\n\nTASK INPUT:\n{user}\n\n"
                  f"Reason step by step (numbered), then on a FINAL new line write exactly:\nFINAL_ANSWER: <the answer>")
        return parse(call_teacher(prov_model[0], prov_model[1], prompt))

    def grounded(ans, user):
        return len(salient(ans) & salient(user)) >= 1

    def one(seed):
        idx, task, user, gold = seed
        (ta, aa) = ask(OPUS, task, user)
        (tb, ab) = ask(SOLAR, task, user)
        # PRIMARY: consensus — both teachers independently agree (bypasses weak gold)
        if aa and ab and f1(aa, ab) >= a.consensus_f1 and grounded(aa, user):
            return {"messages": [{"role": "user", "content": user},
                                 {"role": "assistant", "content": f"<think>{ta}</think>\n{aa}"}],
                    "task": task, "source": "cot_consensus"}
        # SECONDARY: a single strong teacher that reaches OUR gold (validated)
        if aa and f1(aa, gold) >= a.gold_f1:
            return {"messages": [{"role": "user", "content": user},
                                 {"role": "assistant", "content": f"<think>{ta}</think>\n{gold}"}],
                    "task": task, "source": "cot_opus_gold"}
        if ab and f1(ab, gold) >= a.gold_f1:
            return {"messages": [{"role": "user", "content": user},
                                 {"role": "assistant", "content": f"<think>{tb}</think>\n{gold}"}],
                    "task": task, "source": "cot_solar_gold"}
        return None

    out = []; kept = 0
    with ThreadPoolExecutor(max_workers=a.workers) as ex:
        for i, r in enumerate(ex.map(one, seeds)):
            if r:
                out.append(r); kept += 1
            if i % 100 == 0:
                print(f"  {i}/{len(seeds)} -> kept {kept}", flush=True)
    with open(a.out, "w") as f:
        for r in out:
            f.write(json.dumps(r) + "\n")
    print(f"COT DISTILL: {len(seeds)} seeds -> {kept} traces ({kept/max(1,len(seeds))*100:.1f}% keep) -> {a.out}\n"
          f"  by-task={dict(collections.Counter(r['task'] for r in out))}\n"
          f"  by-source={dict(collections.Counter(r['source'] for r in out))}", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
