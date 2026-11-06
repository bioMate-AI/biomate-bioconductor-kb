"""Fix 2 (committee data audit): purge web-dev / maintenance noise from self-mining. Commit-fixes are
kept only if the commit actually touches EXECUTION-plane code (.nf/.wdl/.smk/.cwl/.sh/.R + pipeline .py);
frontend/API/CI-only commits are dropped (a React button-wiring fix must NOT enter the autofix task).
Docs-QA is filtered to drop DevOps/meta-infrastructure QA and keep bioinformatics/pipeline QA.
Deterministic, no API. Writes *_clean.jsonl + a report.
"""
import json, os, re, subprocess
REPO = "/Users/kky/biomate-review"; POOL = f"{REPO}/docs/20260912_onprem_llm/data_pool_v2"

EXEC = re.compile(r"\.(nf|wdl|smk|cwl|sh|R|r|groovy)$|nextflow\.config$", re.I)
EXEC_PY = re.compile(r"(nextflow|workflow|pipeline|biomni|galaxy/ai|experiments|autoloop|qc_).*\.py$", re.I)
NOISE = re.compile(r"\.(tsx|jsx|ts|js|vue|css|scss|html|md|json|yml|yaml|lock)$", re.I)


def commit_files(sha):
    try:
        return subprocess.check_output(["git", "-C", REPO, "show", "--stat", "--format=", sha], text=True, stderr=subprocess.DEVNULL)
    except Exception: return ""


# --- commit-fixes ---
kept_c, drop_c = [], 0
for l in open(f"{POOL}/self_commit_fixes.jsonl"):
    r = json.loads(l); sha = r.get("source", "").replace("commit:", "").strip()
    files = commit_files(sha)
    is_exec = any(EXEC.search(ln) or EXEC_PY.search(ln) for ln in files.splitlines())
    if is_exec: kept_c.append(r)
    else: drop_c += 1
with open(f"{POOL}/self_commit_fixes_clean.jsonl", "w") as f:
    for r in kept_c: f.write(json.dumps(r) + "\n")

# --- docs-QA ---
META = re.compile(r"\b(frontend|react|tsx|endpoint|button|e2e|CI/CD|\bCI\b|RBAC|billing|stripe|lago|"
                  r"mock_mode|unit test|vitest|playwright|typescript|API route|UI |sidebar|dashboard|"
                  r"deploy|sync_to_dev|docker|gunicorn)\b", re.I)
BIO = re.compile(r"\b(workflow|pipeline|nextflow|bioconductor|rna-?seq|variant|genome|param|tool|"
                 r"align|deseq|edger|qc|cryo|admet|dock|assay|sequenc|annotat|differential)\b", re.I)
kept_d, drop_d = [], 0
for l in open(f"{POOL}/self_docs_qa.jsonl"):
    r = json.loads(l); txt = (r.get("q", "") + " " + r.get("a", ""))
    if META.search(txt) and not BIO.search(txt): drop_d += 1; continue
    kept_d.append(r)
with open(f"{POOL}/self_docs_qa_clean.jsonl", "w") as f:
    for r in kept_d: f.write(json.dumps(r) + "\n")

print(f"commit-fixes: kept {len(kept_c)} / dropped {drop_c} (non-execution web/API/CI noise)")
print(f"docs-QA:      kept {len(kept_d)} / dropped {drop_d} (DevOps/meta-infra QA)")
print(f"-> {POOL}/self_commit_fixes_clean.jsonl , self_docs_qa_clean.jsonl")
