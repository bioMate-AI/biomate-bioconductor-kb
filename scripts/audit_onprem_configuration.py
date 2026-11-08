#!/usr/bin/env python3
"""Names-only configuration inventory; never reads private .env or secret values.

Scan tracked code plus explicitly supplied public release snapshots. Literal
reads are evidence, not proof a setting is required. Shell expansions are
labelled candidates because they can be local variables. Dynamic accesses
are reported separately rather than silently claiming exhaustive resolution.
"""
import argparse
import bisect
from collections import defaultdict
import datetime
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
NAME = r"[A-Z_][A-Z0-9_]*"
RULES = {
    "python-read": re.compile(r"(?:os\.)?(?:getenv\s*\(|environ\s*(?:\.get\s*\(|\[|\.setdefault\s*\())\s*['\"](" + NAME + r")[ '\"]"),
    "node-read": re.compile(r"(?:process|import\.meta)\.env(?:\.([A-Z_][A-Z0-9_]*)|\[\s*['\"](" + NAME + r")[ '\"]\s*\])"),
    "shell-or-compose-reference": re.compile(r"(?<!\$)\$\{(" + NAME + r")(?=[:?+}\-])"),
    "github-secret-reference": re.compile(r"secrets\.(" + NAME + r")"),
    "github-variable-reference": re.compile(r"vars\.(" + NAME + r")"),
    "nextflow-env-read": re.compile(r"\b(?:System\.getenv|env)\(\s*['\"](" + NAME + r")[ '\"]"),
    "r-env-read": re.compile(r"\bSys\.getenv\(\s*['\"](" + NAME + r")[ '\"]"),
}
SKIP_PARTS = {"node_modules", ".git", ".venv", "venv", "__pycache__", "dist", "build", "test_results", ".worktrees"}
EXTENSIONS = {".py", ".ts", ".tsx", ".js", ".mjs", ".cjs", ".sh", ".bash", ".R", ".r", ".java", ".go", ".yml", ".yaml", ".nf", ".config", ".xml", ".toml", ".json", ".example", ".onprem"}


def scope(path):
    low = path.lower()
    if any(x in low for x in ("/tests/", "/test/", "test_", ".test.", ".spec.", "/fixtures/")):
        return "test"
    if any(x in low for x in ("archive", "/backup", "/reference/")) or low.startswith("reference/"):
        return "historical-or-reference"
    if low.startswith(("backend/nf-core", "backend/biomni/", "biomni/")):
        return "upstream-tooling"
    if low.startswith(("scripts/", ".github/", "infra/", "aws_infrastructure/", "deploy/")) or path.endswith(".sh"):
        return "operations"
    if "workflows/" in low:
        return "scientific-workflows"
    if low.startswith(("frontend/", "backend/", "billing/")):
        return "application"
    return "configuration-or-other"


def extract(text):
    found = []
    # Whole-text matching catches multi-line getenv calls. Mask whole-line
    # comments without changing offsets or line numbers.
    masked = "\n".join(" " * len(line) if line.lstrip().startswith(("#", "//", "<!--", "*")) else line for line in text.split("\n"))
    starts = [0] + [m.end() for m in re.finditer("\n", masked)]
    for kind, rule in RULES.items():
        for match in rule.finditer(masked):
            name = next(g for g in match.groups() if g is not None)
            found.append((name, bisect.bisect_right(starts, match.start()), kind))
    for match in re.finditer(r"\{([^{}]+)\}\s*=\s*process\.env\b", masked):
        for field in match[1].split(","):
            name = re.match(r"\s*(" + NAME + r")\b", field)
            if name:
                found.append((name[1], bisect.bisect_right(starts, match.start()), "node-destructured-read"))
    return found


def read_names(path):
    return {line.split()[0] for line in path.read_text().splitlines() if line.strip() and not line.lstrip().startswith("#")}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--approved-revision", default="79c0421d90ff86f5973513a0360677bd72df390c")
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    files = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).decode().split("\0")
    inputs = []
    skipped = []
    for name in sorted(set(files)):
        path = ROOT / name
        if not name or name.startswith("docs/") or any(p in SKIP_PARTS for p in path.relative_to(ROOT).parts):
            continue
        if path.suffix not in EXTENSIONS and "Dockerfile" not in path.name and path.name not in {"install.sh"}:
            continue
        # Never read real .env files or environment-value exports.
        if path.name.startswith(".env") and not (path.name.endswith(".example") or path.name.endswith(".sample")):
            skipped.append({"path": name, "reason": "private-environment-file"})
            continue
        if not path.is_file() or path.is_symlink():
            continue
        if path.stat().st_size > 5_000_000:
            skipped.append({"path": name, "reason": "over-5MB"})
            continue
        try:
            inputs.append(("worktree", name, path.read_text()))
        except (UnicodeError, OSError):
            skipped.append({"path": name, "reason": "nontext-or-unreadable"})
    # Approved docs describe these newer code paths, absent from this worktree.
    approved_paths = [".env.onprem.example", "docker-compose.onprem.yml", "install.sh",
                      "scripts/diag-onprem.sh", "scripts/remote-access.sh",
                      "frontend/server/vite.ts", "frontend/server/routes.ts",
                      "frontend/server/services/runs-outputs-service.ts",
                      "backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py"]
    for name in approved_paths:
        inputs.append((args.approved_revision, name, subprocess.check_output(["git", "show", args.approved_revision + ":" + name], cwd=ROOT).decode()))
    variables = defaultdict(list)
    dynamic = []
    for revision, name, text in inputs:
        category = scope(name)
        for variable, line, kind in extract(text):
            variables[variable].append({"revision": revision, "path": name, "line": line, "kind": kind, "scope": category})
        # Container environment keys are a separate contract from host inputs:
        # a constant binding still belongs in the inventory, not the Git manager.
        if "compose" in Path(name).name and Path(name).suffix in {".yml", ".yaml"}:
            import yaml
            document = yaml.safe_load(text) or {}
            for service, config in document.get("services", {}).items():
                bindings = config.get("environment", {})
                keys = bindings if isinstance(bindings, dict) else [x.split("=", 1)[0] for x in bindings]
                for key in keys:
                    if re.fullmatch(NAME, key):
                        variables[key].append({"revision": revision, "path": name, "kind": "container-binding", "scope": category, "service": service})
        for number, line in enumerate(text.splitlines(), 1):
            if re.search(r"(?:getenv\(|environ\.get\(|process\.env\[)\s*[a-z_]", line):
                dynamic.append({"revision": revision, "path": name, "line": number})
        # Public template definitions, including commented optional examples.
        if Path(name).name.startswith(".env") and Path(name).name.endswith((".example", ".sample")):
            for number, line in enumerate(text.splitlines(), 1):
                m = re.match(r"\s*(?:#\s*)?(" + NAME + r")=", line)
                if m:
                    variables[m[1]].append({"revision": revision, "path": name, "line": number, "kind": "onprem-template" if name == ".env.onprem.example" else "public-env-template", "scope": "configuration-or-other"})
    # Document-only names must remain visible when no implementation consumes them.
    for path in sorted((out / "approved-documents").glob("*.txt")):
        for number, line in enumerate(path.read_text().splitlines(), 1):
            for match in re.finditer(r"\b([A-Z][A-Z0-9]*_[A-Z0-9_]+)\b", line):
                variables[match[1]].append({"revision": args.approved_revision, "path": str(path.relative_to(ROOT)), "line": number, "kind": "approved-document-example", "scope": "documentation"})
    managed = read_names(ROOT / "deploy/biomate.env.manifest")
    for name in managed:
        variables[name].append({"revision": "worktree", "path": "deploy/biomate.env.manifest", "kind": "managed-manifest", "scope": "operations"})
    records = []
    for name, occurrences in sorted(variables.items()):
        kinds = {x["kind"] for x in occurrences}
        records.append({"name": name, "in_git_manifest": name in managed,
                        "secret_review": "github-secret-reference" in kinds or bool(re.search(r"SECRET|PASSWORD|PASS$|TOKEN|(?:^|_)KEY(?:_|$)|ACCESS_KEY|PRIVATE_KEY|LICENSE_KEY|DATABASE_URL|REDIS_URL|_(?:AK|SK|PWD)$", name)),
                        "literal_runtime_read": bool(kinds & {"python-read", "node-read", "node-destructured-read", "nextflow-env-read", "r-env-read"}),
                        "in_onprem_template": "onprem-template" in kinds,
                        "occurrences": occurrences})
    payload = {"generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
               "worktree_head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT).decode().strip(),
               "approved_revision": args.approved_revision, "scanned_inputs": len(inputs),
               "variables": records, "dynamic_accesses": dynamic, "skipped": skipped,
               "limitations": ["Static literal inventory, not live values or a required-variable schema.",
                               "Shell expansions include local variables; do not blindly upload to GitHub.",
                               "Dynamic variable names require separate review; third-party settings may be discovered only at runtime.",
                               "Approved revision overlay covers deployment-relevant changed files, not a second full repository scan."]}
    (out / "environment-inventory.json").write_text(json.dumps(payload, indent=2) + "\n")
    lines = ["# BioMate environment parameter inventory", "", "Names and source locations only. No environment or secret values are included.", "",
             "Shell references may be script-local variables. Secret review is conservative name-based triage, not permission to store a value as public.", "",
             "| Name | Git manifest | On prem template | Literal runtime read | Secret review | Source example |", "|---|---|---|---|---|---|"]
    for row in records:
        source = next((x for x in row["occurrences"] if x["kind"] not in {"managed-manifest", "shell-or-compose-reference"}), row["occurrences"][0])
        lines.append("| `" + row["name"] + "` | " + " | ".join("yes" if row[k] else "no" for k in ("in_git_manifest", "in_onprem_template", "literal_runtime_read", "secret_review")) + " | " + source["path"] + ":" + str(source.get("line", "")) + " |")
    (out / "ENVIRONMENT_PARAMETERS.md").write_text("\n".join(lines) + "\n")
    # Compact deployer-facing view. Keep host interpolation inputs distinct
    # from constant container bindings and unsupported document-only names.
    onprem_paths = {".env.onprem.example", "docker-compose.onprem.yml", "install.sh", "scripts/diag-onprem.sh", "scripts/remote-access.sh"}
    onprem = []
    for row in records:
        occurrences = [x for x in row["occurrences"] if x["path"] in onprem_paths or x["scope"] == "documentation"]
        if not occurrences:
            continue
        bindings = sorted({x["service"] for x in occurrences if x["kind"] == "container-binding" and x["revision"] == args.approved_revision})
        onprem.append({"name": row["name"], "in_git_manifest": row["in_git_manifest"], "secret_review": row["secret_review"],
                       "literal_runtime_read": row["literal_runtime_read"], "in_onprem_template": row["in_onprem_template"],
                       "approved_container_services": bindings,
                       "host_or_script_reference": any(x["kind"] == "shell-or-compose-reference" for x in occurrences),
                       "document_reference": any(x["scope"] == "documentation" for x in occurrences)})
    (out / "onprem-configuration.json").write_text(json.dumps(onprem, indent=2) + "\n")
    matrix = ["# On premises configuration coverage", "", "This is a coverage matrix, not a template to upload. Script-local names and document-only names require review. A value in .env is ineffective unless Compose passes it to the relevant service.", "",
              "| Name | Git manifest | On prem template | Approved container services | Literal code read | Secret review |", "|---|---|---|---|---|---|"]
    for row in onprem:
        matrix.append("| `" + row["name"] + "` | " + ("yes" if row["in_git_manifest"] else "no") + " | " + ("yes" if row["in_onprem_template"] else "no") + " | " + (", ".join(row["approved_container_services"]) or "—") + " | " + ("yes" if row["literal_runtime_read"] else "no") + " | " + ("review" if row["secret_review"] else "—") + " |")
    (out / "ONPREM_CONFIGURATION_MATRIX.md").write_text("\n".join(matrix) + "\n")
    print(json.dumps({"inputs": len(inputs), "names": len(records), "managed": len(managed), "runtime_names": sum(x["literal_runtime_read"] for x in records), "runtime_missing_from_manifest": sum(x["literal_runtime_read"] and not x["in_git_manifest"] for x in records), "dynamic_accesses": len(dynamic)}))


if __name__ == "__main__":
    main()
