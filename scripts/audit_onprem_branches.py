#!/usr/bin/env python3
"""Reconcile on-prem remote branch heads without checking out or merging code."""
import datetime
import json
from pathlib import Path
import re
import subprocess

import yaml

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs/qa/20261107-onprem-configuration"


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT).decode()


def source(sha, path):
    result = subprocess.run(["git", "show", sha + ":" + path], cwd=ROOT, capture_output=True)
    return result.stdout.decode() if result.returncode == 0 else None


def main():
    heads = {ref.removeprefix("refs/heads/"): sha for sha, ref in
             (line.split() for line in git("ls-remote", "--heads", "origin").splitlines())}
    base = heads["integration/next-phase"]
    records = []
    for branch, sha in sorted(heads.items()):
        if not re.search(r"on.?prem|aliyun|next-phase|arm64", branch, re.I):
            continue
        row = {"branch": branch, "sha": sha}
        if subprocess.run(["git", "cat-file", "-e", sha + "^{commit}"], cwd=ROOT, stderr=subprocess.DEVNULL).returncode:
            row["status"] = "object-not-local-not-reviewed"
            records.append(row)
            continue
        row["status"] = "selected-source-reviewed"
        row["head_contained_in_next_phase"] = subprocess.run(["git", "merge-base", "--is-ancestor", sha, base], cwd=ROOT).returncode == 0
        counts = git("rev-list", "--left-right", "--count", base + "..." + sha).split()
        row["next_phase_only_commits"], row["branch_only_commits"] = map(int, counts)
        vite = source(sha, "frontend/server/vite.ts") or ""
        executor = source(sha, "backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py") or ""
        compose_text = source(sha, "docker-compose.onprem.yml") or ""
        diag = source(sha, "scripts/diag-onprem.sh") or ""
        compose = yaml.safe_load(compose_text) or {}
        env = {}
        for service, config in compose.get("services", {}).items():
            bindings = config.get("environment", {})
            env[service] = sorted(bindings if isinstance(bindings, dict) else [x.split("=", 1)[0] for x in bindings])
        row["selected_file_sha256"] = {}
        import hashlib
        for path in ("frontend/server/vite.ts", "backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py", "docker-compose.onprem.yml", "scripts/diag-onprem.sh", ".env.onprem.example", "deploy/biomate.env.manifest"):
            text = source(sha, path)
            row["selected_file_sha256"][path] = hashlib.sha256(text.encode()).hexdigest() if text is not None else None
        row["google_flag_code_present"] = "process.env.DISABLE_GOOGLE_FONTS" in vite
        row["google_flag_bound_to_frontend"] = "DISABLE_GOOGLE_FONTS" in env.get("frontend", [])
        row["slurm_executor_branch_present"] = 'executor == "slurm"' in executor
        row["k8s_executor_branch_present"] = 'executor == "k8s"' in executor
        row["cluster_variables_bound_to_backend"] = [x for x in env.get("galaxy-backend", []) if x.startswith(("SLURM_", "NXF_K8S_"))]
        row["local_gpu_option_name_present_in_executor"] = "NEXTFLOW_DOCKER_GPU_OPTIONS" in executor
        row["documented_packager_exists"] = source(sha, "scripts/package-onprem.sh") is not None
        row["diagnostic_raw_inspect_export_present"] = bool(re.search(r'docker inspect "\$cname" >', diag))
        row["s3_path_style_name_present_in_executor"] = "S3_FORCE_PATH_STYLE" in executor
        records.append(row)
    payload = {"checked_at": datetime.datetime.now(datetime.timezone.utc).isoformat(), "next_phase_sha": base,
               "branches": records,
               "limitations": ["Selected-file static checks, not a full branch test or deployment audit.",
                               "Head ancestry is not patch equivalence; a non-ancestor branch may have cherry-picked features already integrated.",
                               "No working-tree checkout, merge, runtime deployment or secret access performed."]}
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "branch-reconciliation.json").write_text(json.dumps(payload, indent=2) + "\n")
    for row in records:
        print(json.dumps({k: row[k] for k in ("branch", "sha", "status", "google_flag_code_present", "documented_packager_exists") if k in row}))


if __name__ == "__main__":
    main()
