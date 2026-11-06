"""Committee re-review v2 — FULL (untruncated) records, focused on WORKFLOW-relevant data & tasks.
Fixes v1's mistake (samples were sliced to [:400], misleading the models). Each example is complete;
any elision is explicitly marked. Asks gpt-5.6 + gemini-3.8-flash to judge workflow task DESIGN,
grounding, label correctness, coverage/gaps, and alignment with real BioMate usage."""
import os, json, urllib.request, sys, random
random.seed(19)
REPO="/Users/kky/biomate-review"; DV=f"{REPO}/docs/20260912_onprem_llm/routing_data_v1"
rows=[json.loads(l) for l in open(f"{DV}/multitask_sft_paraphrased_clean.jsonl") if l.strip()]

def full(r, cap=2200):
    u=r["messages"][0]["content"]; a=r["messages"][1]["content"]
    u=u if len(u)<=cap else u[:cap]+f"  …[ELIDED {len(u)-cap} chars]"
    return {"USER":u, "GOLD":a}

def pick(pred, n=2):
    xs=[r for r in rows if pred(r["messages"][0]["content"])]; random.shuffle(xs)
    return [full(r) for r in xs[:n]]

TASKS={
 "routing (intent->workflow, tool name NOT in request by design)":
    pick(lambda u:"Retrieved candidates:" not in u and "PHASES" not in u and "WORKFLOWS" not in u
         and "clarify" not in u and "Parameter schema:" not in u and "ERROR LOG" not in u and "\n" not in
         (u.split("Request:")[-1][:0] or ""), 2),
 "rag_routing (pick from retrieved candidates)":
    pick(lambda u:"Retrieved candidates:" in u, 2),
 "decompose (phase->step DAG)": pick(lambda u:"PHASES and STEPS" in u, 1),
 "interwf_decomp (cross-workflow DAG)": pick(lambda u:"ordered plan of WORKFLOWS" in u, 1),
 "param (extract implied params)": pick(lambda u:"Parameter schema:" not in u and "Extract" in u and "param" in u.lower() and "Retrieved" not in u, 2),
 "cond_param (full schema, extract only specified)": pick(lambda u:"Parameter schema:" in u, 1),
 "clarify (ask for missing required)": pick(lambda u:"clarify_needed" in u, 1),
}

BRIEF=f"""Re-audit (v2, FULL records) of a private on-prem domain LLM for BioMate (bioinformatics workflow
assistant). v1 accidentally fed you TRUNCATED samples and you flagged false corruption — these are
COMPLETE records (elision explicitly marked). FOCUS on the WORKFLOW-relevant data and tasks.

## Grounding facts
- 4,200 workflows + 12,312 tools in a DB. Routing/param data is grounded in REAL verified workflow runs
  and real params_schema. By DESIGN the request describes the task WITHOUT naming the target workflow
  (so the gold workflow name is NOT expected to appear in the request).
- Validated SFT = 15,254 examples across 11 tasks. Workflow-relevant counts: rag_routing 4,244,
  routing 2,538, param 1,886, decompose 1,536, wfgen 1,531, cond_param 1,042, interwf_decomp 354.
- A contrastive retriever supplies the rag_routing candidate list (gold is guaranteed present).

## FULL EXAMPLES BY TASK
{json.dumps(TASKS, indent=1)}

## JUDGE — be specific and adversarial, focus on WORKFLOW data & tasks
1. TASK DESIGN: are these the right tasks for how BioMate is actually used (route -> configure -> run ->
   diagnose)? What workflow-relevant task or capability is MISSING (e.g., workflow chaining validity,
   output interpretation, resource/cost, version/compat, input-type checking)?
2. GROUNDING & LABELS: given the FULL request, is each gold workflow/decomposition/param set correct and
   the BEST choice? Any mislabels? Is "request must not name the tool" a good grounding principle here?
3. DECOMPOSITION: is the phase->step / cross-workflow DAG realistic and correctly ordered (deps, parallel)?
4. PARAM extraction: is the restraint (extract only specified, no defaults) correct? Are values schema-valid?
5. COVERAGE: does 15,254 examples across these tasks adequately cover 4,200 workflows / 36 domains? Where
   is it thin? Distribution/imbalance risks?
6. Single highest-priority change to the WORKFLOW data/tasks before GPU training.
Give prioritized, concrete, actionable findings."""

def call_openai(model="gpt-5.6"):
    body=json.dumps({"model":model,"messages":[{"role":"user","content":BRIEF}],
                     "max_completion_tokens":20000,"reasoning_effort":"medium"}).encode()
    req=urllib.request.Request("https://api.openai.com/v1/chat/completions", data=body,
        headers={"Authorization":f"Bearer {os.environ['OPENAI_API_KEY']}","Content-Type":"application/json"})
    return json.load(urllib.request.urlopen(req, timeout=300))["choices"][0]["message"]["content"]

def call_gemini(model="gemini-3.8-flash"):
    url=f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={os.environ['GOOGLE_API_KEY']}"
    body=json.dumps({"contents":[{"parts":[{"text":BRIEF}]}]}).encode()
    d=json.load(urllib.request.urlopen(urllib.request.Request(url, data=body,
        headers={"Content-Type":"application/json"}), timeout=300))
    return d["candidates"][0]["content"]["parts"][0]["text"]

if __name__=="__main__":
    who=sys.argv[1] if len(sys.argv)>1 else "openai"
    os.makedirs(f"{REPO}/docs/20260912_onprem_llm/committee_reviews", exist_ok=True)
    out=call_openai() if who=="openai" else call_gemini()
    open(f"{REPO}/docs/20260912_onprem_llm/committee_reviews/audit_v2_{who}.md","w").write(out)
    print(f"[{who}] {len(out)} chars\n"); print(out)
