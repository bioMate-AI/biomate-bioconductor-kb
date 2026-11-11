#!/usr/bin/env python3
"""Explicit mechanical image/path migration, with hashes and reversible ledger.

Does not rename Python dependencies/tool IDs or rewrite historical research.
Use --plan first, then --apply. Never overwrites a different destination file.
"""
import argparse
import datetime
import difflib
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
MAPPING = json.loads((HERE / "image_name_map.json").read_text())
AUDIT = ROOT / "docs/qa/20261107-image-name-migration"
DIR_MOVES = {"backend/docker/" + old: "backend/docker/" + new for old, new in MAPPING.items()}
FILE_MOVES = {
    ".github/workflows/build-biomni-image.yml": ".github/workflows/build-workflow-image.yml",
    ".github/workflows/build-biomni-tools-image.yml": ".github/workflows/build-workflow-tools-image.yml",
    ".github/workflows/build-biomni-tools-onprem-image.yml": ".github/workflows/build-workflow-tools-onprem-image.yml",
    ".github/workflows/build-biomni-pharma-image.yml": ".github/workflows/build-pharmacology-tools-image.yml",
    ".github/workflows/build-biomni-structure-to-drug-image.yml": ".github/workflows/build-structure-to-drug-image.yml",
}
PHRASES = {
    **{Path(a).name: Path(b).name for a, b in FILE_MOVES.items()},
    **{Path(a).stem: Path(b).stem for a, b in FILE_MOVES.items()},
    "BIOMATE_BIOMNI_TOOLS_IMAGE": "BIOMATE_WORKFLOW_TOOLS_IMAGE",
    "_BIOMNI_REMOTE": "_WORKFLOW_REMOTE", "_BIOMNI_LOCAL": "_WORKFLOW_LOCAL",
    "pull_biomni_tools": "pull_workflow_tools", "docker_biomni": "docker_workflow",
}
PATTERN = re.compile(r"(?<![A-Za-z0-9])(?:" + "|".join(re.escape(x) for x in sorted(MAPPING, key=len, reverse=True)) + r")(?![A-Za-z0-9])")


def transform(text):
    for old, new in PHRASES.items():
        text = text.replace(old, new)
    text = PATTERN.sub(lambda match: MAPPING[match.group(0)], text)
    # Purely descriptive image-family wording, not SDK/module names.
    return text.replace("biomni-*", "workflow-task").replace("Build biomni image", "Build workflow image")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def selected(path):
    if nonrelease(path):
        return False
    if path.startswith(("scripts/release/", "scripts/audit_upstream_mentions", "scripts/test_image_name_migration")):
        return False
    if path.startswith(("backend/", "frontend/", "scripts/", ".github/", "deploy/", "infra/", "aws_infrastructure/", "auto_update/arm64_tools/docker/")):
        return not any(x in Path(path).parts for x in ("node_modules", "__pycache__", "builds", "reports", "test-results"))
    return path in ("install.sh", "docker-compose.onprem.yml", ".env.onprem.example", "docker-compose.yml", "docker-compose.dev.yml", "docs/ONPREM_SETUP.md", "docs/ONPREM_IP_PROTECTION.md")


def nonrelease(path):
    return (any(part in Path(path).parts for part in ("_archived", "archived_workflows_broken_api", "test_results"))
            or path in ("backend/20260117_BIOMATE_BIOMNI_WORKFLOW_TEST_RESULTS.md",
                        "backend/20260119_1538_DOCKER_CONTAINER_ROUTING_APPROACH.md",
                        "backend/results/pipeline_info/report.html",
                        "backend/biomni_workflows/results/pharmacophore_filtering/pipeline_info/report.html",
                        "frontend/website-prototypes/variant-c.html"))


def destination(name):
    if name in FILE_MOVES:
        return FILE_MOVES[name]
    for old, new in DIR_MOVES.items():
        if name.startswith(old + "/"):
            return new + name[len(old):]
    return name


def files_plan():
    files = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).split(b"\0")
    result = []
    for raw in files:
        if not raw:
            continue
        name = os.fsdecode(raw)
        path = ROOT / name
        if not selected(name) or not path.is_file() or path.is_symlink():
            continue
        data = path.read_bytes()
        if b"\0" in data[:8192] or data.startswith(b"SQLite format 3"):
            continue
        try:
            before = data.decode("utf8")
        except UnicodeDecodeError:
            continue
        after = transform(before)
        dest = destination(name)
        if after != before or dest != name:
            if dest != name and (ROOT / dest).exists():
                raise RuntimeError("Destination collision: " + dest)
            result.append({"before_path": name, "after_path": dest,
                           "before_sha256": digest(data), "after_sha256": digest(after.encode()),
                           "mode": path.stat().st_mode & 0o777,
                           "replacement_count": len(PATTERN.findall(before)),
                           "before": before, "after": after})
    return result


def quote(name):
    return '"' + name.replace('"', '""') + '"'


def migrate_database(path):
    changes = []
    db = sqlite3.connect(path.resolve().as_uri() + "?mode=rw", uri=True)
    try:
        db.execute("BEGIN IMMEDIATE")
        for table, sql in db.execute("SELECT name,sql FROM sqlite_master WHERE type='table'").fetchall():
            if table.startswith("sqlite_") or "VIRTUAL TABLE" in (sql or "").upper() or "_fts_" in table or "WITHOUT ROWID" in (sql or "").upper():
                continue
            cols = db.execute("PRAGMA table_info(" + quote(table) + ")").fetchall()
            for col in cols:
                name = col[1]
                for rowid, before in db.execute("SELECT rowid," + quote(name) + " FROM " + quote(table) + " WHERE typeof(" + quote(name) + ")='text' AND instr(" + quote(name) + ", 'biomni-')>0").fetchall():
                    after = transform(before)
                    if before == after:
                        continue
                    changes.append({"table": table, "rowid": rowid, "column": name,
                                    "before": before, "after": after})
                    db.execute("UPDATE " + quote(table) + " SET " + quote(name) + "=? WHERE rowid=?", (after, rowid))
        # tools_fts stores its own content; update it from primary tool rows.
        if changes:
            sql = db.execute("SELECT sql FROM sqlite_master WHERE name='tools_fts'").fetchone()
            if sql:
                cols = [x[1] for x in db.execute("PRAGMA table_info(tools_fts)")]
                primary_cols = {x[1] for x in db.execute("PRAGMA table_info(tools)")}
                if not set(cols) <= primary_cols:
                    raise RuntimeError("FTS schema mismatch; refusing partial migration")
                fields = ",".join(quote(c) for c in cols)
                db.execute("DELETE FROM tools_fts")
                db.execute("INSERT INTO tools_fts(rowid," + fields + ") SELECT id," + fields + " FROM tools")
            if db.execute("SELECT 1 FROM sqlite_master WHERE name='workflows_fts'").fetchone():
                db.execute("INSERT INTO workflows_fts(workflows_fts) VALUES ('rebuild')")
            integrity = db.execute("PRAGMA integrity_check").fetchall()
            if integrity != [("ok",)]:
                raise RuntimeError("DB integrity check failed: " + str(integrity))
        # Journal before commit; sufficient exact-cell rollback information.
        (AUDIT / "database_changes.json").write_text(json.dumps(changes, indent=2) + "\n")
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()
    return len(changes)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--database-only", action="store_true", help="resume the catalogue transaction after an audited local-file pass")
    parser.add_argument("--finish-moves", action="store_true", help="preserve and move untracked build-cache remnants from mapped directories")
    parser.add_argument("--trim-nonrelease", action="store_true", help="restore only this task's substitutions in historical/nonrelease files")
    args = parser.parse_args()
    AUDIT.mkdir(parents=True, exist_ok=True)
    if args.trim_nonrelease:
        ledger = json.loads((AUDIT / "applied.json").read_text())
        backups = Path(ledger["backup_dir"])
        restored = []
        for row in ledger["files"]:
            if not nonrelease(row["before_path"]):
                continue
            path = ROOT / row["after_path"]
            before = (backups / row["before_path"]).read_bytes()
            if digest(path.read_bytes()) != row["after_sha256"] or digest(before) != row["before_sha256"]:
                raise RuntimeError("Concurrent edit or backup mismatch; refusing restore: " + str(path))
            path.write_bytes(before)
            restored.append({"path": row["after_path"], "restored_sha256": digest(before),
                             "reason": "outside active image-consumer migration; preserve historical evidence"})
        (AUDIT / "scope_restorations.json").write_text(json.dumps(restored, indent=2) + "\n")
        ledger["scope_restored_files"] = len(restored)
        ledger["retained_file_changes"] = len(ledger["files"]) - len(restored)
        (AUDIT / "applied.json").write_text(json.dumps(ledger, indent=2) + "\n")
        print(json.dumps({"restored": len(restored), "retained": ledger["retained_file_changes"]}))
        return
    if args.finish_moves:
        moved = []
        for old_name, new_name in DIR_MOVES.items():
            old, new = ROOT / old_name, ROOT / new_name
            if not old.is_dir():
                continue
            for child in old.iterdir():
                target = new / child.name
                if target.exists():
                    raise RuntimeError("Untracked destination collision: " + str(target))
                target.parent.mkdir(parents=True, exist_ok=True)
                entry = {"before_path": str(child.relative_to(ROOT)), "after_path": str(target.relative_to(ROOT)),
                         "reason": "preserve untracked build-cache remnant; no deletion"}
                child.rename(target)
                moved.append(entry)
            old.rmdir()
        (AUDIT / "untracked_moves.json").write_text(json.dumps(moved, indent=2) + "\n")
        print(json.dumps({"preserved_untracked_moves": len(moved)}))
        return
    if args.database_only:
        ledger = json.loads((AUDIT / "applied.json").read_text())
        for row in ledger["files"]:
            if digest((ROOT / row["after_path"]).read_bytes()) != row["after_sha256"]:
                raise RuntimeError("File changed since migration; review before DB resume: " + row["after_path"])
        try:
            ledger["database_cells"] = migrate_database(ROOT / "backend/database/galaxy_ai_tools.db")
            ledger["status"] = "local_migration_applied_not_deployed"
            ledger["finished_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        except sqlite3.Error as exc:
            ledger["database_error"] = {"message": str(exc), "code": getattr(exc, "sqlite_errorcode", None), "name": getattr(exc, "sqlite_errorname", None)}
            raise
        finally:
            (AUDIT / "applied.json").write_text(json.dumps(ledger, indent=2) + "\n")
        print(json.dumps({"status": ledger["status"], "database_cells": ledger["database_cells"]}))
        return
    plan = files_plan()
    records = [{k: v for k, v in row.items() if k not in ("before", "after")} for row in plan]
    (AUDIT / "file_plan.json").write_text(json.dumps(records, indent=2) + "\n")
    print(json.dumps({"files": len(plan), "moves": sum(x["before_path"] != x["after_path"] for x in plan), "apply": args.apply}), flush=True)
    if not args.apply:
        return
    if (AUDIT / "applied.json").exists():
        raise RuntimeError("Already applied; audit the existing ledger before attempting another migration")
    before_dir = Path(tempfile.mkdtemp(prefix="biomate-image-name-backup-"))
    ledger = {"started_at": datetime.datetime.now(datetime.timezone.utc).isoformat(), "backup_dir": str(before_dir),
              "files": [], "database_cells": None, "status": "applying"}
    def save():
        (AUDIT / "applied.json").write_text(json.dumps(ledger, indent=2) + "\n")
    save()
    with (AUDIT / "changes.patch").open("w") as patch:
        for row in plan:
            old, new = ROOT / row["before_path"], ROOT / row["after_path"]
            if digest(old.read_bytes()) != row["before_sha256"]:
                raise RuntimeError("Concurrent edit detected: " + str(old))
            backup = before_dir / row["before_path"]
            backup.parent.mkdir(parents=True, exist_ok=True)
            backup.write_bytes(old.read_bytes())
            new.parent.mkdir(parents=True, exist_ok=True)
            if old != new:
                old.rename(new)
            new.write_bytes(row["after"].encode())
            new.chmod(row["mode"])
            patch.writelines(difflib.unified_diff(row["before"].splitlines(True), row["after"].splitlines(True),
                                                fromfile=row["before_path"], tofile=row["after_path"], n=0))
            ledger["files"].append({k: v for k, v in row.items() if k not in ("before", "after")})
            save()
    # Only remove the four now-empty, explicitly mapped Docker build folders.
    # rmdir cannot delete unrelated contents.
    for old in DIR_MOVES:
        path = ROOT / old
        if path.is_dir() and not any(path.iterdir()):
            path.rmdir()
    ledger["database_cells"] = migrate_database(ROOT / "backend/database/galaxy_ai_tools.db")
    ledger["finished_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    ledger["status"] = "local_migration_applied_not_deployed"
    save()
    print(json.dumps({"status": ledger["status"], "files": len(ledger["files"]), "database_cells": ledger["database_cells"]}))


if __name__ == "__main__":
    main()
