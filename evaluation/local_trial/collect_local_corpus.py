#!/usr/bin/env python3
"""Collect local, no-PII training-data candidates for the on-prem BioMate model.

Sources (all local; no private conversations, no dev PII):
  1. Nextflow programs (.nf) + their config/schema/README companions  -> nf_program lane
  2. Workflow specs from the AI tool DB                                -> workflow_spec lane
  3. Git fix commits (issue -> fix diff pairs)                         -> repair lane
  4. docs/ incident & reference markdown                               -> knowledge/repair lane

Emits candidate JSONL + a manifest with source hashes and review gates.
Nothing here is approved training data: every record is review_status=needs_review,
eligible_for_training=False. Preserve scientific literals; this collector does not
fabricate completions.
"""
from __future__ import annotations
import argparse, hashlib, json, subprocess, sqlite3
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def sha256_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def sh(args: list[str]) -> str:
    return subprocess.run(args, cwd=REPO, capture_output=True, text=True).stdout


def collect_nf_programs(out_dir: Path, limit: int | None) -> dict:
    """Catalog every .nf program with companion config/schema/README, as
    knowledge + generation candidates (intent/spec -> program)."""
    nf_files = [p for p in REPO.rglob("*.nf") if "node_modules" not in p.parts]
    nf_files.sort()
    if limit:
        nf_files = nf_files[:limit]
    path = out_dir / "nf_program_candidates.jsonl"
    n = 0
    with path.open("w") as f:
        for p in nf_files:
            try:
                body = p.read_bytes()
            except Exception:
                continue
            d = p.parent
            cfg = d / "nextflow.config"
            schema = d / "nextflow_schema.json"
            readme = next((d / n for n in ("README.md", "meta.yml") if (d / n).exists()), None)
            rel = str(p.relative_to(REPO))

            def read_cap(path, n=8000):
                try:
                    t = path.read_text(errors="ignore")
                    return t[:n], len(t) > n
                except Exception:
                    return None, False
            code_txt, code_trunc = read_cap(p, 12000)
            cfg_txt, _ = read_cap(cfg) if cfg.exists() else (None, False)
            schema_txt, _ = read_cap(schema) if schema.exists() else (None, False)
            readme_txt, _ = read_cap(readme) if readme else (None, False)
            rec = {
                "candidate_id": "nf_" + sha256_bytes(rel.encode())[:12],
                "source_path": rel,
                "source_sha256": sha256_bytes(body),
                "bytes": len(body),
                "code": code_txt,                 # actual .nf workflow code
                "code_truncated": code_trunc,
                "config": cfg_txt,                # nextflow.config
                "schema": schema_txt,             # nextflow_schema.json
                "readme": readme_txt,             # workflow document
                "has_config": cfg.exists(),
                "has_schema": schema.exists(),
                "has_readme": bool(readme),
                "readme_path": str(readme.relative_to(REPO)) if readme else None,
                "domain_hint": rel.split("/")[1] if "/" in rel else "",
                "source_groups": ["nf_dir:" + str(d.relative_to(REPO))],
                "intended_task": "nextflow_generate_understand",
                "review_status": "needs_review",
                "eligible_for_training": False,
            }
            f.write(json.dumps(rec) + "\n")
            n += 1
    return {"file": path.name, "count": n, "sha256": sha256_bytes(path.read_bytes())}


OK_STATUS = {"ok", "ok_warnings"}
FAIL_STATUS = {"exec_error", "fixture_failed", "timeout", "ran_empty_output"}
GOOD_VERDICT = {"pass", "correct", "executable"}


def _cap(v, n=4000):
    s = "" if v is None else str(v)
    return s[:n], len(s) > n


def collect_workflow_specs(out_dir: Path, limit: int | None) -> dict:
    """Split the workflow DB into training lanes using REAL execution outcome as the
    verification signal:
      - verified_generation : real_exec ok/ok_warnings + good correctness verdict
      - nextflow_debug      : real_exec failure + real_exec_err (workflow + real error)
      - repair              : correctness minor_issues/major_issues
      - unverified          : everything else (retrieval material only)
    """
    db = REPO / "backend" / "database" / "galaxy_ai_tools.db"
    path = out_dir / "workflow_spec_candidates.jsonl"
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    con.row_factory = sqlite3.Row
    q = ("SELECT name, domain, description, annotation, params_schema, input_types, "
         "output_types, tools_used, step_count, workflow_json, workflow_hash, "
         "real_exec_status, real_exec_err, real_exec_produced, "
         "workflow_correctness_score, workflow_correctness_verdict FROM workflows")
    if limit:
        q += f" LIMIT {limit}"
    from collections import Counter
    lanes = Counter()
    n = 0
    with path.open("w") as f:
        for row in con.execute(q):
            d = dict(row)
            status = d.get("real_exec_status") or ""
            verdict = d.get("workflow_correctness_verdict") or ""
            err = d.get("real_exec_err")
            has_err = err not in (None, "", "null")
            if status in OK_STATUS and verdict in GOOD_VERDICT:
                lane, task, verified = "verified_generation", "nextflow_generate_verified", True
            elif status in FAIL_STATUS and has_err:
                lane, task, verified = "nextflow_debug", "nextflow_diagnose_fix", True
            elif verdict in ("minor_issues", "major_issues"):
                lane, task, verified = "repair", "workflow_repair", False
            else:
                lane, task, verified = "unverified", "retrieval_material", False
            lanes[lane] += 1
            wf_json, wf_trunc = _cap(d.get("workflow_json"), 8000)
            err_txt, err_trunc = _cap(err, 4000)
            payload = json.dumps({k: str(v) for k, v in d.items()}, sort_keys=True).encode()
            rec = {
                "candidate_id": "wf_" + sha256_bytes(str(d.get("name", n)).encode())[:12],
                "workflow_name": d.get("name"),
                "domain": d.get("domain"),
                "lane": lane,
                "intended_task": task,
                "execution_verified": verified,
                "real_exec_status": status or None,
                "real_exec_err_excerpt": err_txt or None,
                "real_exec_err_truncated": err_trunc,
                "correctness_verdict": verdict or None,
                "correctness_score": d.get("workflow_correctness_score"),
                "description": d.get("description"),
                "annotation": d.get("annotation"),
                "params_schema": d.get("params_schema"),
                "input_types": d.get("input_types"),
                "output_types": d.get("output_types"),
                "tools_used": d.get("tools_used"),
                "step_count": d.get("step_count"),
                "workflow_json_excerpt": wf_json,
                "workflow_json_truncated": wf_trunc,
                "workflow_hash": d.get("workflow_hash"),
                "source_sha256": sha256_bytes(payload),
                "source_groups": ["workflow:" + str(d.get("name"))],
                "review_status": "needs_review",
                "eligible_for_training": False,
                "note": "execution_verified reflects recorded real_exec outcome; still requires human review.",
            }
            f.write(json.dumps(rec, default=str) + "\n")
            n += 1
    con.close()
    return {"file": path.name, "count": n, "lanes": dict(lanes),
            "sha256": sha256_bytes(path.read_bytes())}


def collect_git_fix_pairs(out_dir: Path, limit: int) -> dict:
    """Issue -> fix pairs from fix-type commits. Message = issue statement,
    diff = fix. Capped diff; large commits flagged truncated."""
    shas = sh(["git", "log", "--pretty=format:%H",
               "--grep", "fix", "--grep", "bug", "--grep", "error", "--grep", "crash",
               "--grep", "repair", "--grep", "regression", "--grep", "resolve",
               "-i", "--all-match" if False else "-E", f"-n{limit}"]).split()
    # fall back to simple grep if the above returns nothing
    if not shas:
        shas = sh(["git", "log", "--pretty=format:%H", "-iE", "--grep=fix|bug|error|crash|repair|regression",
                   f"-n{limit}"]).split()
    path = out_dir / "git_fix_pair_candidates.jsonl"
    n = 0
    with path.open("w") as f:
        for sha in shas:
            subject = sh(["git", "show", "-s", "--pretty=format:%s", sha]).strip()
            body = sh(["git", "show", "-s", "--pretty=format:%b", sha]).strip()
            files = [x for x in sh(["git", "diff-tree", "--no-commit-id",
                                    "--name-only", "-r", sha]).splitlines() if x]
            diff = sh(["git", "show", "--pretty=format:", "--unified=3", sha])
            rec = {
                "candidate_id": "fixpair_" + sha[:12],
                "commit": sha,
                "issue_statement": (subject + ("\n\n" + body if body else ""))[:1500],
                "files_changed": files[:25],
                "touches_nf": any(x.endswith(".nf") for x in files),
                "fix_diff_excerpt": diff[:6000],
                "diff_truncated": len(diff) > 6000,
                "source_groups": ["commit:" + sha],
                "intended_task": "issue_diagnosis_and_fix",
                "review_status": "needs_review",
                "eligible_for_training": False,
            }
            f.write(json.dumps(rec) + "\n")
            n += 1
    return {"file": path.name, "count": n, "sha256": sha256_bytes(path.read_bytes())}


def collect_docs(out_dir: Path, limit: int | None) -> dict:
    kws = ("incident", "root cause", "postmortem", "regression", "what was changed",
           "known issue", "bug", "failure", "fix")
    docs = [p for p in (REPO / "docs").rglob("*.md")]
    docs.sort()
    path = out_dir / "docs_candidates.jsonl"
    n = 0
    with path.open("w") as f:
        for p in docs:
            try:
                text = p.read_text(errors="ignore")
            except Exception:
                continue
            low = text.lower()
            is_incident = any(k in low for k in kws)
            rel = str(p.relative_to(REPO))
            rec = {
                "candidate_id": "doc_" + sha256_bytes(rel.encode())[:12],
                "source_path": rel,
                "source_sha256": sha256_bytes(text.encode()),
                "bytes": len(text),
                "is_incident_or_fix": is_incident,
                "source_groups": ["doc:" + rel],
                "intended_task": "knowledge_or_repair_narrative",
                "review_status": "needs_review",
                "eligible_for_training": False,
            }
            f.write(json.dumps(rec) + "\n")
            n += 1
            if limit and n >= limit:
                break
    return {"file": path.name, "count": n, "sha256": sha256_bytes(path.read_bytes())}


def collect_official_docs(out_dir: Path) -> dict:
    """Official upstream Nextflow documentation + patterns (authoritative language
    reference and idiomatic examples) staged under official_nextflow_docs/."""
    base = REPO / "docs/20260912_onprem_llm/official_nextflow_docs"
    path = out_dir / "official_nextflow_doc_candidates.jsonl"
    n = 0
    if not base.exists():
        return {"count": 0, "note": "official docs not staged"}
    with path.open("w") as f:
        for p in base.rglob("*"):
            if not p.is_file() or p.suffix.lower() not in (".mdx", ".md", ".rst", ".nf", ".config"):
                continue
            try:
                text = p.read_text(errors="ignore")
            except Exception:
                continue
            rel = str(p.relative_to(REPO))
            kind = "nextflow_pattern" if ".nf" in p.suffix else "nextflow_doc"
            rec = {
                "candidate_id": "offdoc_" + sha256_bytes(rel.encode())[:12],
                "source_path": rel,
                "source": "nextflow-io (official upstream)",
                "kind": kind,
                "content": text[:16000],
                "content_truncated": len(text) > 16000,
                "source_sha256": sha256_bytes(text.encode()),
                "intended_task": "nextflow_language_knowledge",
                "source_groups": ["official_nextflow:" + rel],
                "license_note": "upstream nextflow-io docs/patterns; verify license before external redistribution",
                "review_status": "needs_review",
                "eligible_for_training": False,
            }
            f.write(json.dumps(rec) + "\n")
            n += 1
    return {"file": path.name, "count": n, "sha256": sha256_bytes(path.read_bytes()) if n else None}


def collect_all_benchmark_datasets(out_dir: Path) -> dict:
    """Catalog ALL local benchmark dataset dirs (beyond RealBio public_export):
    evaluation/datasets/* data files, as input(+gold where present) candidates."""
    base = REPO / "evaluation" / "datasets"
    path = out_dir / "all_benchmark_candidates.jsonl"
    from collections import Counter
    per = Counter()
    n = 0
    if not base.exists():
        return {"count": 0}
    with path.open("w") as f:
        for d in sorted(base.iterdir()):
            if not d.is_dir() or d.name == "public_export":
                continue
            for data in list(d.rglob("*.jsonl")) + list(d.rglob("*.yaml")) + list(d.rglob("*.json")):
                if data.name in ("MANIFEST.json",):
                    continue
                try:
                    if data.suffix == ".jsonl":
                        items = [json.loads(x) for x in data.read_text().splitlines() if x.strip()]
                    elif data.suffix in (".yaml", ".yml"):
                        try:
                            import yaml
                            y = yaml.safe_load(data.read_text())
                        except Exception:
                            continue
                        items = y if isinstance(y, list) else (y.get("cases") or y.get("items") or y.get("tasks") or [])
                    else:
                        j = json.loads(data.read_text())
                        items = j if isinstance(j, list) else (j.get("cases") or j.get("items") or j.get("tasks") or [])
                except Exception:
                    continue
                if not isinstance(items, list):
                    continue
                for it in items:
                    if not isinstance(it, dict):
                        continue
                    rec = {
                        "candidate_id": f"bench_{d.name}_{it.get('id', n)}",
                        "benchmark": d.name,
                        "intended_task": f"benchmark:{d.name}",
                        "input_item": it,
                        "source_path": str(data.relative_to(REPO)),
                        "source_groups": [f"benchmark:{d.name}:{it.get('id', n)}"],
                        "review_status": "needs_review",
                        "eligible_for_training": False,
                    }
                    f.write(json.dumps(rec, default=str) + "\n")
                    per[d.name] += 1
                    n += 1
    return {"file": path.name, "count": n, "per_benchmark": dict(per),
            "sha256": sha256_bytes(path.read_bytes()) if n else None}


def collect_db_knowledge(out_dir: Path, limit: int | None) -> dict:
    """Tool knowledge base + composition/rationale from the 304MB AI tool DB.
    Retrieval/grounding + tool-understanding + param material (not conversations)."""
    db = REPO / "backend" / "database" / "galaxy_ai_tools.db"
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    con.row_factory = sqlite3.Row

    # --- tools (12k) ---
    tools_path = out_dir / "tool_knowledge_candidates.jsonl"
    q = ("SELECT tool_id, name, category, description, help_text, parameters, inputs, "
         "outputs, requirements, examples, usage_guide, scientific_context, "
         "scientific_context_v2, scientific_context_v2_verify_rate, edam_operations, "
         "edam_topics, tags, citations FROM tools")
    if limit:
        q += f" LIMIT {limit}"
    nt = 0
    with tools_path.open("w") as f:
        for row in con.execute(q):
            d = {k: row[k] for k in row.keys()}
            sci = d.get("scientific_context_v2") or d.get("scientific_context")
            payload = json.dumps({k: str(v) for k, v in d.items()}, sort_keys=True).encode()
            rec = {
                "candidate_id": "tool_" + sha256_bytes(str(d.get("tool_id", nt)).encode())[:12],
                "tool_id": d.get("tool_id"),
                "name": d.get("name"),
                "category": d.get("category"),
                "intended_task": "tool_knowledge_grounding",
                "description": d.get("description"),
                "help_text": d.get("help_text"),
                "parameters": d.get("parameters"),
                "inputs": d.get("inputs"),
                "outputs": d.get("outputs"),
                "requirements": d.get("requirements"),
                "examples": d.get("examples"),
                "scientific_context": sci,
                "sci_context_verify_rate": d.get("scientific_context_v2_verify_rate"),
                "edam_operations": d.get("edam_operations"),
                "edam_topics": d.get("edam_topics"),
                "citations": d.get("citations"),
                "source_sha256": sha256_bytes(payload),
                "source_groups": ["tool:" + str(d.get("tool_id"))],
                "review_status": "needs_review",
                "eligible_for_training": False,
                "note": "retrieval/knowledge material; scientific_context_v2_verify_rate is a quality signal.",
            }
            f.write(json.dumps(rec, default=str) + "\n")
            nt += 1

    # --- composition + rationale (compact) ---
    comp_path = out_dir / "composition_rationale_candidates.jsonl"
    nc = 0
    with comp_path.open("w") as f:
        def dump(table, task):
            nonlocal nc
            try:
                cols = [r[1] for r in con.execute(f"PRAGMA table_info({table})")]
            except Exception:
                return
            if not cols:
                return
            for row in con.execute(f"SELECT * FROM {table}"):
                d = {k: row[k] for k in row.keys()}
                f.write(json.dumps({
                    "candidate_id": f"{table}_{nc}",
                    "source_table": table,
                    "intended_task": task,
                    "record": d,
                    "source_groups": [f"{table}:{nc}"],
                    "review_status": "needs_review",
                    "eligible_for_training": False,
                }, default=str) + "\n")
                nc += 1
        dump("tool_compatibility", "tool_composition")
        dump("workflow_chains", "workflow_composition_reasoning")
        dump("rationale_registry", "workflow_rationale")
        dump("workflow_phase_rationale", "workflow_phase_reasoning")
    con.close()
    return {"tools_file": tools_path.name, "tools_count": nt,
            "tools_sha256": sha256_bytes(tools_path.read_bytes()),
            "composition_file": comp_path.name, "composition_count": nc,
            "composition_sha256": sha256_bytes(comp_path.read_bytes())}


def collect_biomate_run_outputs(out_dir: Path) -> dict:
    """Per-case BioMate/model outputs from evaluation/results/**.jsonl — records that
    carry BOTH a produced output and an expected/gold answer (+score). These are
    (input -> output -> gold -> score) triples: distillation / preference material."""
    base = REPO / "evaluation" / "results"
    path = out_dir / "biomate_run_output_candidates.jsonl"
    OUT_KEYS = ("generated", "output", "prediction", "response", "answer", "biomate_output")
    GOLD_KEYS = ("expected", "gold", "ground_truth", "reference", "correct_answer")
    from collections import Counter
    per = Counter()
    n = 0
    if not base.exists():
        return {"count": 0}
    with path.open("w") as f:
        for jf in base.rglob("*.jsonl"):
            try:
                lines = [json.loads(x) for x in jf.read_text().splitlines() if x.strip()]
            except Exception:
                continue
            for it in lines:
                if not isinstance(it, dict):
                    continue
                out_k = next((k for k in OUT_KEYS if k in it and it[k]), None)
                gold_k = next((k for k in GOLD_KEYS if k in it and it[k]), None)
                if not out_k:
                    continue
                model = jf.stem
                rec = {
                    "candidate_id": f"run_{jf.parent.name}_{model}_{it.get('example_id', it.get('task', n))}",
                    "result_set": jf.parent.name,
                    "model": model,
                    "intended_task": "biomate_run_distillation_or_preference",
                    "produced_output": it.get(out_k),
                    "expected": it.get(gold_k) if gold_k else None,
                    "score": it.get("macro") or it.get("checker_result") or it.get("score"),
                    "raw_keys": list(it.keys()),
                    "source_path": str(jf.relative_to(REPO)),
                    "source_groups": [f"result:{jf.parent.name}:{it.get('example_id', n)}"],
                    "has_gold": bool(gold_k),
                    "review_status": "needs_review",
                    "eligible_for_training": False,
                    "note": "teacher/BioMate output is a candidate until independently verified; "
                            "exclude release-test result sets from training.",
                }
                f.write(json.dumps(rec, default=str) + "\n")
                per[jf.parent.name] += 1
                n += 1
    return {"file": path.name, "count": n, "per_result_set": dict(per),
            "sha256": sha256_bytes(path.read_bytes()) if n else None}


def collect_public_benchmarks(out_dir: Path) -> dict:
    """RealBio public benchmark suite: input + explicit ground truth per item.
    Highest-confidence SFT source (gold-labeled, no PII, publicly releasable)."""
    base = REPO / "evaluation" / "datasets" / "public_export"
    man = base / "MANIFEST.json"
    if not man.exists():
        return {"count": 0, "note": "no public_export MANIFEST"}
    m = json.loads(man.read_text())
    gt_by = {b["name"]: b.get("gt") for b in m.get("benchmarks", [])}
    task_by = {b["name"]: b.get("task", "") for b in m.get("benchmarks", [])}
    path = out_dir / "public_benchmark_candidates.jsonl"
    from collections import Counter
    per = Counter()
    n = 0
    with path.open("w") as f:
        for b in m.get("benchmarks", []):
            name = b["name"]
            data = base / name / "data.jsonl"
            if not data.exists():
                continue
            for line in data.open():
                line = line.strip()
                if not line:
                    continue
                item = json.loads(line)
                gt = gt_by.get(name)
                gt_fields = gt if isinstance(gt, list) else ([gt] if isinstance(gt, str) else
                            list(gt.get("any", [])) if isinstance(gt, dict) else [])
                ground_truth = {k: item.get(k) for k in gt_fields if k in item}
                rec = {
                    "candidate_id": f"pb_{name}_{item.get('id', n)}",
                    "benchmark": name,
                    "intended_task": f"public_benchmark:{name}",
                    "input_item": item,
                    "ground_truth": ground_truth,
                    "task_description": task_by.get(name, ""),
                    "gold_labeled": bool(ground_truth),
                    "source_groups": [f"public_benchmark:{name}:{item.get('id', n)}"],
                    "review_status": "needs_review",
                    "eligible_for_training": False,
                    "note": "Gold-labeled public benchmark item; exclude any release-test split from training before use.",
                }
                f.write(json.dumps(rec, default=str) + "\n")
                per[name] += 1
                n += 1
    return {"file": path.name, "count": n, "per_benchmark": dict(per),
            "sha256": sha256_bytes(path.read_bytes()) if n else None}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(REPO / "docs/20260912_onprem_llm/data_candidates_v2"))
    ap.add_argument("--nf-limit", type=int, default=None)
    ap.add_argument("--wf-limit", type=int, default=None)
    ap.add_argument("--fix-limit", type=int, default=500)
    ap.add_argument("--docs-limit", type=int, default=None)
    ap.add_argument("--tools-limit", type=int, default=None)
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    manifest = {
        "scope": "Local no-PII training-data candidates; BioMate core; IND excluded. "
                 "Candidates only — none approved for training.",
        "application_commit": sh(["git", "rev-parse", "HEAD"]).strip(),
        "sources": {},
        "limitations": [
            "Recorded workflow status is not verified execution.",
            "Fix-commit selection is keyword-based; requires human triage of true issue->fix pairs.",
            "nf programs are raw material; a spec->program pair is not a verified correct completion.",
            "No private conversations or dev PII included.",
        ],
    }
    manifest["sources"]["nf_programs"] = collect_nf_programs(out, args.nf_limit)
    manifest["sources"]["workflow_specs"] = collect_workflow_specs(out, args.wf_limit)
    manifest["sources"]["git_fix_pairs"] = collect_git_fix_pairs(out, args.fix_limit)
    manifest["sources"]["docs"] = collect_docs(out, args.docs_limit)
    manifest["sources"]["public_benchmarks"] = collect_public_benchmarks(out)
    manifest["sources"]["db_knowledge"] = collect_db_knowledge(out, args.tools_limit)
    manifest["sources"]["official_nextflow_docs"] = collect_official_docs(out)
    manifest["sources"]["all_benchmark_datasets"] = collect_all_benchmark_datasets(out)
    manifest["sources"]["biomate_run_outputs"] = collect_biomate_run_outputs(out)
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2))
    print(json.dumps({k: v for k, v in manifest["sources"].items()}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
