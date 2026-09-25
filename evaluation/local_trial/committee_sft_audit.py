"""Committee audit of the SFT task DEFINITIONS + training data + eval data.
Grounds 3 frontier models (Claude/GPT/Gemini, latest) in the REAL artifacts (per-task train/eval counts,
actual samples, the metric caveat) and collects independent expert critiques. Synthesis is done by the caller.
Usage: python committee_sft_audit.py --context /tmp/committee_context.json --out committee_sft_audit_raw.json
"""
import argparse, json, os, urllib.request, time
from concurrent.futures import ThreadPoolExecutor

MEMBERS = {"claude": ("anthropic", "claude-opus-5-5"),
           "gpt": ("openai", "gpt-6-luna"),
           "gemini": ("google", "gemini-3.8-flash")}

TAXONOMY = """BioMate is moving to a DATA-CENTRIC, de-Galaxy architecture with 4 user modules and a
2-lane (Instant/Cloud) model. New execution backends (pre-trained NIM inference, REINVENT design/generate,
ML-training) are ROUTED-TO by the intent LLM, they are NOT new LLM tasks. The genuinely new LLM tasks are:
N1 out-of-catalog compositional generation (phases->steps->blocks from a workflow knowledge graph, with
abstention) = FLAGSHIP; N2 lane-arbitration verdict (Instant-cited / Instant-compute / Cloud-workflow /
Cloud-design / Cloud-models + why); N3 design-intent/constraint extraction (goal->stage+target/scaffold/
property-envelope/count); N4 pre-trained-model/NIM selection + confidence narration. Core live tasks kept:
routing, parameter_extraction, task_decomposition, autofix_repair, workflow_generation, clarification,
log_diagnosis, knowledge_recall, scientific_qa, tool_recommendation, dataset_prerequisite_check,
findings_interpretation, multi_workflow_chaining."""

METRIC_CAVEAT = """The current SFT eval metric is an LLM-judge COVERAGE of the teacher's distilled answer
(distillation fidelity), NOT ground-truth correctness — EXCEPT routing (accept-set membership vs the real
workflow DB) and param (schema-key recall) which have true gold. Training data is teacher-distilled
(gemini/committee) grounded on the workflow DB + docs. Split is tool-Jaccard family-disjoint."""

PROMPT = """You are on an expert review committee auditing the SFT (supervised fine-tuning) phase of an
on-prem 4B model for BioMate (an agentic bioinformatics assistant). Be rigorous, specific, and critical —
your job is to find what is WRONG or MISSING, not to praise.

# BioMate current-version task context
{tax}

# Eval-metric & data provenance caveat
{caveat}

# The 17 SFT tasks — training vs eval row counts
{counts}

# Two real training samples per task (user -> assistant)
{samples}

# Your task
Critique the SFT phase across THREE axes. For each, give concrete, actionable findings tied to the data above.

1. TASK DEFINITIONS: Are these the right tasks for the current data-centric BioMate? Which are
   redundant/overlapping (e.g. knowledge_recall vs scientific_qa vs tool_recommendation)? Which are
   mis-scoped or ill-defined? What high-value tasks are MISSING (esp. N1-N4)? Should any be split/merged?

2. TRAINING DATA: Judge coverage, balance, diversity, and quality from the counts + samples. Flag
   imbalance (4 tasks = ~62% of rows; tail tasks <400), circularity/leakage risk from teacher distillation,
   and whether training VOLUME matches task VALUE. Is the data too templated/easy?

3. EVAL DATA: Is the eval valid? Flag the teacher-fidelity-vs-gold problem, coverage GAPS (e.g.
   out_of_catalog_composition has 599 train but 0 eval), family-disjoint adequacy, and whether the eval
   measures REAL capability. What gold-standard evals should be added per task?

End with a prioritized list of the top 5 CONCRETE changes to task definitions / training data / eval data.
Return well-structured prose with clear headers. Be specific to BioMate and the numbers shown."""


def call(provider, model, prompt, mx=8000):
    for attempt in range(4):
        try:
            if provider == "anthropic":
                url = "https://api.anthropic.com/v1/messages"
                h = {"x-api-key": os.environ["ANTHROPIC_API_KEY"], "anthropic-version": "2023-06-01", "content-type": "application/json"}
                b = {"model": model, "max_tokens": mx, "messages": [{"role": "user", "content": prompt}]}
                d = json.load(urllib.request.urlopen(urllib.request.Request(url, json.dumps(b).encode(), h), timeout=300))
                return "".join(p.get("text", "") for p in d.get("content", []))
            if provider == "openai":
                url = "https://api.openai.com/v1/chat/completions"
                h = {"Authorization": f"Bearer {os.environ['OPENAI_API_KEY']}", "Content-Type": "application/json"}
                b = {"model": model, "messages": [{"role": "user", "content": prompt}], "max_completion_tokens": mx, "reasoning_effort": "high"}
                d = json.load(urllib.request.urlopen(urllib.request.Request(url, json.dumps(b).encode(), h), timeout=300))
                return d["choices"][0]["message"]["content"]
            if provider == "google":
                url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={os.environ['GOOGLE_API_KEY']}"
                b = {"contents": [{"parts": [{"text": prompt}]}], "generationConfig": {"maxOutputTokens": mx}}
                d = json.load(urllib.request.urlopen(urllib.request.Request(url, json.dumps(b).encode(), {"Content-Type": "application/json"}), timeout=300))
                return "".join(p.get("text", "") for p in d["candidates"][0].get("content", {}).get("parts", []))
        except Exception as e:
            if attempt == 3: return f"[ERROR {provider}/{model}: {str(e)[:200]}]"
            time.sleep(min(3 * (attempt + 1), 20))
    return ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--context", required=True); ap.add_argument("--out", required=True)
    a = ap.parse_args()
    ctx = json.load(open(a.context))
    counts = f"{'task':28s} {'train':>7s} {'eval':>6s}\n" + "\n".join(
        f"{t:28s} {ctx['train_counts'].get(t,0):7d} {ctx['eval_counts'].get(t,0):6d}"
        for t in sorted(set(ctx['train_counts']) | set(ctx['eval_counts']), key=lambda x: -ctx['train_counts'].get(x, 0)))
    samples = ""
    for t, exs in ctx["samples"].items():
        samples += f"\n## {t}\n"
        for e in exs:
            samples += f"  U: {e.get('user','')}\n  A: {e.get('assistant','')}\n"
    prompt = PROMPT.format(tax=TAXONOMY, caveat=METRIC_CAVEAT, counts=counts, samples=samples[:9000])
    out = {}
    with ThreadPoolExecutor(max_workers=3) as ex:
        futs = {label: ex.submit(call, prov, model, prompt) for label, (prov, model) in MEMBERS.items()}
        for label, f in futs.items():
            out[label] = {"model": MEMBERS[label][1], "critique": f.result()}
            print(f"=== {label} ({MEMBERS[label][1]}): {len(out[label]['critique'])} chars ===", flush=True)
    json.dump(out, open(a.out, "w"), indent=2)
    print("COMMITTEE DONE ->", a.out)


if __name__ == "__main__":
    raise SystemExit(main())
