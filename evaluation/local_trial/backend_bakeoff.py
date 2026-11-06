"""Backend bake-off (decision-proxy): same BioMate harness retrieval, different LLM backend deciding
{workflow, params}; the artifact is then run on Batch and graded by execution (execution_grader).

This measures what the backend actually changes about a RUNNABLE, CORRECT artifact — not similarity.
Shared across backends: the retrieved candidate workflows + their param schemas (the harness half).
Varies: which backend produces the decision (frontier via Anthropic API; our model via an OpenAI-
compatible vLLM endpoint serving base+sft_v5).

Modes:
  --backend frontier --facts today_resolved_compounds.json  # calls Anthropic (ANTHROPIC_API_KEY / SETUP_CHECKLIST.md)
  --backend ourmodel --endpoint http://localhost:8000/v1 --model sft_v5 --facts today_resolved_compounds.json  # vLLM on the GPU box
Writes decisions_<backend>.jsonl: one {task_id, nextflow_path, params, raw} per task. run_workflow +
grade happen OUTSIDE this script (MCP + execution_grader), so the same decision file drives both.
"""
import argparse, json, os, re, urllib.request

# Tasks: each gives a natural request + the harness-retrieved candidates (name + nextflow_path + the
# param schema). The backend must (a) pick the right workflow, (b) fill params using the supplied
# resolver evidence. Compound identity is a harness lookup, never a model-memory test. All map to the cheap, known-
# good ADMET image so Batch stays cheap and the image won't flake.
ADMET_PATH = "nextflow_nfcore/subworkflows/drug_discovery/predict_admet_properties/main.nf"
CANDIDATES = [
    {"name": "Predict Admet Properties", "nextflow_path": ADMET_PATH,
     "params_schema": {"smiles_list": "JSON array string of SMILES", "ADMET_model_type": "MPNN|CNN|Morgan",
                       "admet_shard_size": "integer"}},
    {"name": "Oral Absorption Bcs Model",
     "nextflow_path": "nextflow_nfcore/subworkflows/drug_discovery/oral_absorption_bcs_model/main.nf",
     "params_schema": {"smiles_list": "JSON array string of SMILES"}},
]
TASKS = [
    {"id": "admet_named3",
     "compound_names": ["aspirin", "caffeine", "ibuprofen"],
     "request": "Predict ADMET / toxicity properties for three marketed drugs: aspirin, caffeine, and ibuprofen.",
     "expect_compounds": 3},
    {"id": "admet_imatinib_mpnn",
     "compound_names": ["imatinib"],
     "request": "Run ADMET toxicity prediction for the kinase inhibitor imatinib using the MPNN model.",
     "expect_compounds": 1},
]
SYS = ("You are BioMate's workflow planner. Given a user request and candidate workflows (with param "
       "schemas), choose ONE workflow and fill its params so it will RUN and produce a correct result. "
       "For ADMET provide smiles_list as a JSON-array STRING using ONLY the supplied resolved-compound "
       "SMILES verbatim. Compound identity comes from retrieval, not memory. Output ONLY a JSON object: "
       '{"nextflow_path": "...", "params": {...}}. No prose.')


def resolved_for(task, facts):
    rows = []
    for name in task["compound_names"]:
        row = facts.get(name)
        if not isinstance(row, dict) or not all(isinstance(row.get(k), str) and row[k].strip()
                                              for k in ("smiles", "source_url")):
            raise ValueError(f"Missing resolved compound evidence for {name}")
        rows.append({"name": name, "smiles": row["smiles"], "source_url": row["source_url"]})
    return rows


def prompt_for(task, facts):
    cands = "\n".join(f"- {c['name']} (nextflow_path={c['nextflow_path']}) params={json.dumps(c['params_schema'])}"
                      for c in CANDIDATES)
    evidence = json.dumps(resolved_for(task, facts), sort_keys=True)
    return f"{SYS}\n\nRequest: {task['request']}\n\nCandidate workflows:\n{cands}\n\nResolved compounds (harness evidence):\n{evidence}\n\nJSON decision:"


def anthropic_key():
    try:
        m = re.search(r"sk-ant-[A-Za-z0-9_-]{20,}", open("/Users/kky/biomate-review/SETUP_CHECKLIST.md").read())
        if m:
            return m.group(0)
    except Exception:
        pass
    return os.environ.get("ANTHROPIC_API_KEY")


def call_frontier(prompt, model="claude-opus-4-8"):
    b = json.dumps({"model": model, "max_tokens": 3000,   # room for Opus thinking + the JSON (700 truncated)
                    "messages": [{"role": "user", "content": prompt}]}).encode()
    d = json.load(urllib.request.urlopen(urllib.request.Request(
        "https://api.anthropic.com/v1/messages", b,
        {"x-api-key": anthropic_key(), "anthropic-version": "2023-06-01", "content-type": "application/json"}), timeout=120))
    return "".join(p.get("text", "") for p in d.get("content", []) if p.get("type") == "text")


def call_openai_compat(prompt, endpoint, model):
    b = json.dumps({"model": model, "messages": [{"role": "user", "content": prompt}],
                    "max_tokens": 700, "temperature": 0}).encode()
    d = json.load(urllib.request.urlopen(urllib.request.Request(
        endpoint.rstrip("/") + "/chat/completions", b, {"Content-Type": "application/json"}), timeout=180))
    return d["choices"][0]["message"]["content"]


def parse_decision(txt):
    m = re.search(r"\{.*\}", (txt or "").replace("\n", " "), re.S)
    if not m:
        return None
    try:
        return json.loads(m.group(0))
    except Exception:
        # tolerate trailing junk: trim to last brace
        s = m.group(0)
        for i in range(len(s), 0, -1):
            try:
                return json.loads(s[:i])
            except Exception:
                continue
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--backend", required=True, choices=["frontier", "ourmodel"])
    ap.add_argument("--endpoint", default="http://localhost:8000/v1")
    ap.add_argument("--model", default="sft_v5")
    ap.add_argument("--frontier-model", default="claude-opus-4-8")
    ap.add_argument("--out", default="")
    ap.add_argument("--facts", required=True, help="Frozen resolver JSON: compound name -> {smiles, source_url}; identical for both backends")
    a = ap.parse_args()
    with open(a.facts) as stream:
        facts = json.load(stream)
    # Validate all evidence before making any billable model calls.
    for task in TASKS:
        resolved_for(task, facts)
    out = a.out or f"decisions_{a.backend}.jsonl"
    with open(out, "w") as f:
        for t in TASKS:
            p = prompt_for(t, facts)
            raw = call_frontier(p, a.frontier_model) if a.backend == "frontier" else call_openai_compat(p, a.endpoint, a.model)
            dec = parse_decision(raw) or {}
            rec = {"task_id": t["id"], "expect_compounds": t.get("expect_compounds"),
                   "resolved_compounds": resolved_for(t, facts),
                   "nextflow_path": dec.get("nextflow_path"), "params": dec.get("params"), "raw": raw[:800]}
            f.write(json.dumps(rec) + "\n")
            print(f"[{a.backend}] {t['id']}: path={rec['nextflow_path']} params={json.dumps(rec['params'])[:200]}", flush=True)
    print(f"-> {out}", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
