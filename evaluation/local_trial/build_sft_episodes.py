#!/usr/bin/env python3
"""Turn the collected candidate lanes into SFT episodes (input -> target), with a
frozen train/dev split and the public benchmarks held out as the release test set.

Discipline:
  * The RealBio public benchmarks (routing/param/autofix/...) are the EVAL set and are
    NEVER emitted as training episodes (no train/test leakage).
  * Training episodes are drawn from non-benchmark, verified/authoritative lanes.
  * Assistant-token-only supervision: each episode is {system, input, target}; the
    collator supervises `target` only.
  * Nothing is auto-approved as scientifically correct; episodes carry provenance +
    a verification basis and remain review-gated.
"""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CAND = REPO / "docs/20260912_onprem_llm/data_candidates_v2"


def h(s: str) -> str:
    return hashlib.sha256(s.encode()).hexdigest()


def load(name):
    p = CAND / name
    if not p.exists():
        return []
    return [json.loads(l) for l in p.open() if l.strip()]


def split_of(key: str, dev_every: int = 10) -> str:
    """Deterministic connected-family split by hash; ~10% dev, rest train.
    (Public-benchmark families are excluded entirely -> they are the test set.)"""
    return "dev" if (int(h(key)[:8], 16) % dev_every == 0) else "train"


SYS_GEN = ("You are BioMate, a bioinformatics workflow assistant. Given an analysis "
           "intent, produce the correct workflow.")
SYS_FIX = ("You are BioMate. Given a software issue, diagnose the root cause and give the "
           "fix.")
SYS_NF = ("You are BioMate, an expert in Nextflow. Given a task, write or explain the "
          "Nextflow workflow.")


def episode(task_id, source_group, system, inp, target, basis, extra=None):
    rec = {
        "record_id": task_id,
        "task_id": task_id.split("::")[0],
        "source_groups": [source_group],
        "split": split_of(source_group),
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": inp},
            {"role": "assistant", "content": target},
        ],
        "prompt_sha256": h(system + "\n" + inp),
        "verification_basis": basis,
        "review_status": "needs_review",
        "eligible_for_training": False,
    }
    if extra:
        rec.update(extra)
    return rec


def build(out_dir: Path, caps: dict) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    counts = {}
    train_dev = out_dir / "sft_episodes.jsonl"
    n = 0
    from collections import Counter
    by = Counter()
    with train_dev.open("w") as f:
        # 1) verified_generation: intent/description -> verified workflow (real_exec ok)
        wf = [r for r in load("workflow_spec_candidates.jsonl") if r.get("lane") == "verified_generation"]
        for r in wf[: caps.get("verified_generation", 10_000)]:
            desc = (r.get("description") or "").strip()
            name = r.get("name") or r.get("workflow_name")
            target_wf = r.get("workflow_json_excerpt") or name
            if not desc or not target_wf:
                continue
            inp = f"Analysis request (domain: {r.get('domain')}): {desc}\nWhich workflow should run this, and what are its key params?"
            tgt = f"Workflow: {name}\nParams schema: {r.get('params_schema')}\n"
            e = episode(f"gen::{name}", f"workflow:{name}", SYS_GEN, inp, tgt,
                        basis=f"real_exec_status={r.get('real_exec_status')}, verdict={r.get('correctness_verdict')}")
            f.write(json.dumps(e, default=str) + "\n"); n += 1; by[e["split"] + "/gen"] += 1

        # 2) git issue -> fix (CODE fixes only; drop docs-only / non-code commits)
        CODE_EXT = (".ts", ".tsx", ".js", ".py", ".nf", ".groovy", ".sql", ".sh",
                    ".yml", ".yaml", ".json", ".xml", ".r", ".java")
        DOC_HINT = ("docs:", "doc:", "chore(docs", "readme")
        for r in load("git_fix_pair_candidates.jsonl")[: caps.get("git_fix", 500)]:
            issue = (r.get("issue_statement") or "").strip()
            diff = (r.get("fix_diff_excerpt") or "").strip()
            files = r.get("files_changed", [])
            has_code = any(str(x).lower().endswith(CODE_EXT) and not str(x).startswith("docs/")
                           for x in files)
            is_doc_commit = issue[:40].lower().startswith(DOC_HINT)
            if not issue or not diff or not has_code or is_doc_commit:
                continue
            inp = f"Issue:\n{issue}\n\nFiles: {', '.join(r.get('files_changed', [])[:8])}\nWhat is the fix?"
            e = episode(f"fix::{r['commit'][:12]}", f"commit:{r['commit']}", SYS_FIX, inp,
                        f"Fix (diff):\n{diff}", basis="merged fix commit")
            f.write(json.dumps(e, default=str) + "\n"); n += 1; by[e["split"] + "/fix"] += 1

        # 3) Nextflow program understanding: README/spec -> code (only where a README exists)
        nf = [r for r in load("nf_program_candidates.jsonl") if r.get("readme") and r.get("code")]
        for r in nf[: caps.get("nf_program", 2000)]:
            inp = f"Write the Nextflow workflow described here:\n{(r['readme'] or '')[:1500]}"
            e = episode(f"nf::{r['candidate_id']}", r["source_groups"][0], SYS_NF, inp,
                        (r["code"] or "")[:8000], basis="repo .nf paired with its README")
            f.write(json.dumps(e, default=str) + "\n"); n += 1; by[e["split"] + "/nf"] += 1

    counts["train_dev_episodes"] = n
    counts["by_split_lane"] = dict(by)

    # 4) frozen release TEST set = public benchmarks (held out; never trained)
    test_path = out_dir / "release_test_holdout.jsonl"
    nt = 0
    with test_path.open("w") as f:
        for r in load("public_benchmark_candidates.jsonl"):
            r["split"] = "test"; r["holdout_reason"] = "release benchmark — excluded from training"
            f.write(json.dumps(r, default=str) + "\n"); nt += 1
    counts["release_test_holdout"] = nt

    manifest = {
        "scope": "First-batch SFT episodes (input->target) + frozen release test holdout.",
        "application_commit": __import__("subprocess").run(
            ["git", "rev-parse", "HEAD"], cwd=REPO, capture_output=True, text=True).stdout.strip(),
        "assistant_token_only": True,
        "counts": counts,
        "leakage_guard": "public benchmarks emitted ONLY to release_test_holdout.jsonl, never to sft_episodes.jsonl",
        "review_gate": "episodes are eligible_for_training=False until human review of provenance/verification",
        "files": {p.name: h(p.read_text()) for p in (train_dev, test_path)},
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2))
    return counts


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(REPO / "docs/20260912_onprem_llm/sft_episodes_v1"))
    args = ap.parse_args()
    counts = build(Path(args.out), caps={})
    print(json.dumps(counts, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
