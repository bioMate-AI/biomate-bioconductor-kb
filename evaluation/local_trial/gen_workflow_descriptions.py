#!/usr/bin/env python3
"""Generate realistic one-sentence TASK descriptions for description-poor workflows with a top LLM,
so the ~7.3k Bioconductor/subworkflow entries (whose DB description is a package name or param dump)
can yield clean routing/DPO training queries. The LLM is grounded ONLY in the workflow's real
metadata (name, domain, tools_used, key param names) — it must not invent accessions/numbers.

Output: {filename, name, domain, generated_description}. Feeds routing-query generation (which then
goes through the committee audit). Reuses the OpenRouter key.

Run:  OPENROUTER_API_KEY=... python3 gen_workflow_descriptions.py --n 30 --out descs_proof.jsonl
      (--n 0 = all description-poor workflows)
"""
from __future__ import annotations
import argparse, json, os, re, sqlite3, urllib.request
from pathlib import Path

KEY = os.environ.get("OPENROUTER_API_KEY") or open(os.path.expanduser("~/.config/biomate/openrouter.key")).read().strip()
MODEL = os.environ.get("DESC_MODEL", "openai/gpt-6.1-sol")
DB = Path(__file__).resolve().parents[1].parent / "backend" / "database" / "galaxy_ai_tools.db"
_PARAM_DUMP = re.compile(r"key_parameters|::|;;|object=|classVar|\w+=[A-Z]|=The |=A |=List of", re.I)


def _lit(x):
    if isinstance(x, (list, dict)):
        return x
    try:
        return json.loads(x)
    except Exception:
        return []


def _is_prose(d):
    return bool(d) and len(d) >= 12 and not _PARAM_DUMP.search(d) and (d.count("=") + d.count(";")) <= 1 and " " in d.strip()


def _param_names(ps):
    ps = _lit(ps)
    if isinstance(ps, dict):
        return [i.get("name") for i in (ps.get("data_inputs") or []) if isinstance(i, dict) and i.get("name")]
    return []


def _call(prompt):
    body = {"model": MODEL, "messages": [{"role": "user", "content": prompt}], "max_tokens": 3000, "temperature": 0.2}
    req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions",
                                 data=json.dumps(body).encode(),
                                 headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
    r = json.load(urllib.request.urlopen(req, timeout=180))
    return r["choices"][0]["message"]["content"] or ""


PROMPT = (
    "For each bioinformatics workflow below, write ONE concise, natural task description a researcher "
    "would actually request (what the workflow DOES), 8-20 words. Ground it ONLY in the given domain, "
    "tools and parameter names — DO NOT invent accession numbers, species, datasets, or specific values. "
    "No package names or code; describe the biological/analytical task. Return ONLY a JSON list "
    "[{\"idx\":int,\"task\":\"...\"}].\n\nWORKFLOWS:\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=30, help="number of description-poor workflows (0 = all)")
    ap.add_argument("--batch", type=int, default=12)
    ap.add_argument("--out", default="generated_descriptions.jsonl")
    a = ap.parse_args()
    conn = sqlite3.connect(str(DB)); conn.row_factory = sqlite3.Row
    poor = []
    for r in conn.execute("SELECT filename,name,domain,description,annotation_v2,tools_used,params_schema FROM workflows"):
        desc = (r["annotation_v2"] or r["description"] or "").strip()
        first = re.split(r"(?<=[.!?])\s", desc)[0] if desc else ""
        if _is_prose(first):
            continue   # already has a usable prose description — skip
        tools = [str(t).split("/")[-1] for t in (_lit(r["tools_used"]) or [])][:6]
        params = _param_names(r["params_schema"])[:6]
        if not (r["domain"] or tools or params):
            continue   # nothing to ground a description in
        poor.append({"filename": r["filename"], "name": r["name"], "domain": r["domain"],
                     "tools": tools, "params": params})
    if a.n:
        poor = poor[:a.n]
    print(f"description-poor workflows to describe: {len(poor)} (model={MODEL})")
    out = []
    for i in range(0, len(poor), a.batch):
        chunk = poor[i:i + a.batch]
        payload = [{"idx": j, "name": w["name"], "domain": w["domain"], "tools": w["tools"], "params": w["params"]}
                   for j, w in enumerate(chunk)]
        try:
            txt = _call(PROMPT + json.dumps(payload, indent=0))
            m = re.search(r"\[.*\]", txt, re.S)
            descs = json.loads(m.group()) if m else []
        except Exception as e:
            print(f"  batch {i} failed: {str(e)[:100]}"); descs = []
        by_idx = {d.get("idx"): d.get("task", "") for d in descs if isinstance(d, dict)}
        for j, w in enumerate(chunk):
            task = (by_idx.get(j) or "").strip()
            if task and _is_prose(task):
                out.append({"filename": w["filename"], "name": w["name"], "domain": w["domain"],
                            "generated_description": task})
        print(f"  {min(i+a.batch,len(poor))}/{len(poor)} done, kept {len(out)}")
    Path(a.out).write_text("\n".join(json.dumps(r) for r in out))
    print(f"GENERATED {len(out)} descriptions -> {a.out}")


if __name__ == "__main__":
    main()
