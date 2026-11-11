#!/usr/bin/env python3
"""Read-only path/text/SQLite and AWS ECR name inventory; no renames or pulls.

Inventories contain locations and matching identifier tokens, not whole source
lines or DB values, to avoid copying unrelated secrets into audit artifacts.
"""
import argparse
import collections
import concurrent.futures
import datetime
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import sys
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "docs/qa/20261107-upstream-name-audit"
NEEDLE = "biomni"
TOKEN = re.compile(r"[A-Za-z0-9_./:@+\-]*biomni[A-Za-z0-9_./:@+\-]*", re.I)
SELF = "scripts/audit_upstream_mentions.py"
EXCLUDED = ["!**/.git/**", "!.git", "!" + SELF,
            "!docs/qa/20261107-upstream-name-audit/**", "!docs/20261107_UPSTREAM_NAME_RELEASE_AUDIT.md"]


def stamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def dump(name, data):
    OUTPUT.mkdir(parents=True, exist_ok=True)
    (OUTPUT / name).write_text(json.dumps(data, indent=2, default=str) + "\n")


def tokens(value):
    return sorted(set(m.group(0)[:240] for m in TOKEN.finditer(value)))


def group(path):
    if path.startswith((".claude/worktrees/", ".codex/worktrees/")):
        return "nested_worktrees"
    if any(x in Path(path).parts for x in ("node_modules", ".venv", "venv", "site-packages", "__pycache__")):
        return "dependencies_and_caches"
    if path.startswith(("Biomni/", "backend/biomni/")):
        return "upstream_source"
    if path.startswith(("docs/", "reference/")):
        return "documentation_and_reference"
    if path.startswith(("evaluation/", "research/")):
        return "research_and_evaluation"
    if path.startswith("backend/biomni_workflows/"):
        return "workflow_tree"
    return "application_and_operations"


def rgargs():
    return [part for pattern in EXCLUDED for part in ("-g", pattern)]


def qident(identifier):
    return '"' + identifier.replace('"', '""') + '"'


def local_inventory():
    started = stamp()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run(["rg", "--files", "--hidden", "--no-ignore", "-0", *rgargs()], cwd=ROOT, capture_output=True)
    files = [os.fsdecode(p) for p in proc.stdout.split(b"\0") if p]
    errors = []
    if proc.returncode not in (0, 1):
        errors.append({"stage": "file_inventory", "error": proc.stderr.decode(errors="replace")})
    tracked = set(os.fsdecode(p) for p in subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).split(b"\0") if p)
    dirs = set()
    paths = []
    dbs = []
    binary_candidates = []
    binary_suffixes = {".pyc", ".so", ".dylib", ".bin", ".pt", ".pth", ".pkl", ".pickle", ".zip", ".gz", ".tar", ".pdf", ".docx", ".pptx", ".xlsx"}
    for name in files:
        path = Path(name)
        for parent in path.parents:
            if str(parent) != "." and NEEDLE in str(parent).lower():
                dirs.add(str(parent))
        if NEEDLE in name.lower():
            paths.append({"path": name, "kind": "symlink" if (ROOT / name).is_symlink() else "file",
                          "category": group(name), "tracked": name in tracked,
                          "basename_matches": NEEDLE in path.name.lower()})
        if path.suffix.lower() in (".db", ".sqlite", ".sqlite3", ".db3"):
            dbs.append(name)
        elif path.suffix.lower() in binary_suffixes:
            binary_candidates.append(name)
    paths.extend({"path": p, "kind": "directory", "category": group(p), "basename_matches": NEEDLE in Path(p).name.lower()} for p in sorted(dirs))
    with (OUTPUT / "paths.jsonl").open("w") as out:
        for item in sorted(paths, key=lambda x: x["path"]):
            out.write(json.dumps(item) + "\n")

    counts = collections.Counter()
    file_stats = {}
    # Standard rg text semantics: detects binary files rather than forcing model
    # tensors/archives through text decoding. SQLite contents are queried below.
    command = ["rg", "--json", "--hidden", "--no-ignore", "-i", *rgargs(), NEEDLE, "."]
    with (OUTPUT / "text_occurrences.jsonl").open("w") as out, (OUTPUT / "rg-errors.txt").open("w") as err:
        child = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=err)
        for raw in child.stdout:
            event = json.loads(raw)
            data = event.get("data", {})
            if event["type"] == "match":
                name = data["path"].get("text", "").removeprefix("./")
                line = data["lines"].get("text", "")
                matches = data.get("submatches", [])
                item = {"path": name, "line": data["line_number"], "byte_offset": data["absolute_offset"],
                        "columns_bytes_1based": [m["start"] + 1 for m in matches],
                        "occurrences": len(matches), "identifiers": tokens(line),
                        "category": group(name), "tracked": name in tracked}
                out.write(json.dumps(item) + "\n")
                counts["matching_lines"] += 1
                counts["occurrences"] += len(matches)
                counts["category:" + group(name)] += len(matches)
                stats = file_stats.setdefault(name, {"path": name, "category": group(name), "tracked": name in tracked,
                                                    "matching_lines": 0, "occurrences": 0, "identifiers": set()})
                stats["matching_lines"] += 1
                stats["occurrences"] += len(matches)
                stats["identifiers"].update(item["identifiers"])
            elif event["type"] == "end" and data.get("binary_offset") is not None:
                counts["binary_files_detected"] += 1
        rc = child.wait()
    if rc not in (0, 1):
        errors.append({"stage": "text_scan", "exit_code": rc, "error_file": "rg-errors.txt"})
    with (OUTPUT / "files.jsonl").open("w") as out:
        for item in sorted(file_stats.values(), key=lambda x: x["path"]):
            item["identifiers"] = sorted(item["identifiers"])
            out.write(json.dumps(item) + "\n")

    db_summary = []
    with (OUTPUT / "database_cells.jsonl").open("w") as out:
        for name in sorted(dbs):
            db_path = ROOT / name
            info = {"path": name, "category": group(name), "matching_cells": 0, "matching_rows": 0,
                    "tables": [], "status": "pending"}
            db_summary.append(info)
            if db_path.is_symlink():
                info.update(status="not_scanned", reason="symlink not followed to avoid out-of-scope writes/reads")
                continue
            try:
                with db_path.open("rb") as src:
                    header = src.read(16)
                if header != b"SQLite format 3\0":
                    info.update(status="not_sqlite", reason="suffix-only database candidate; header not SQLite")
                    continue
                # mode=ro and query_only; no VACUUM, migrations or SQL execution
                # from stored values. Identifier quoting handles unusual schemas.
                conn = sqlite3.connect(db_path.resolve().as_uri() + "?mode=ro", uri=True, timeout=2)
                conn.execute("PRAGMA query_only=ON")
                conn.execute("PRAGMA busy_timeout=2000")
                schemas = conn.execute("SELECT type,name,sql FROM sqlite_master WHERE type IN ('table','view','index','trigger')").fetchall()
                seen_rows = set()
                for kind, table, sql in schemas:
                    if NEEDLE in (table + (sql or "")).lower():
                        out.write(json.dumps({"path": name, "kind": "schema", "object_type": kind,
                                              "object_name": table, "identifiers": tokens(table + " " + (sql or ""))}) + "\n")
                    # Exclude views (could invoke external functions), virtual/FTS
                    # tables and SQLite internal rows from content scanning.
                    if kind != "table" or table.startswith("sqlite_") or "VIRTUAL TABLE" in (sql or "").upper():
                        continue
                    cols = conn.execute("PRAGMA table_info(" + qident(table) + ")").fetchall()
                    if any(table.endswith(s) for s in ("_fts_data", "_fts_idx", "_fts_docsize", "_fts_config")):
                        continue
                    table_info = {"table": table, "matching_cells": 0}
                    info["tables"].append(table_info)
                    without = "WITHOUT ROWID" in (sql or "").upper()
                    identity = ",".join(qident(c[1]) for c in sorted(cols, key=lambda c: c[5]) if c[5]) if without else "rowid"
                    if not identity:
                        table_info["error"] = "no usable row identity"
                        continue
                    for col in cols:
                        column = col[1]
                        try:
                            query = ("SELECT " + identity + "," + qident(column) + " FROM " + qident(table)
                                     + " WHERE instr(lower(CAST(" + qident(column) + " AS TEXT)),?)>0")
                            for row in conn.execute(query, (NEEDLE,)):
                                val = row[-1]
                                if isinstance(val, bytes):
                                    val = val.decode("utf8", errors="replace")
                                value = str(val)
                                key = tuple(str(v) for v in row[:-1])
                                seen_rows.add((table, key))
                                out.write(json.dumps({"path": name, "kind": "cell", "table": table,
                                                      "row_identity": key, "column": column,
                                                      "identifiers": tokens(value),
                                                      "occurrences": value.lower().count(NEEDLE)}) + "\n")
                                info["matching_cells"] += 1
                                table_info["matching_cells"] += 1
                        except Exception as exc:
                            table_info.setdefault("errors", []).append({"column": column, "error": str(exc)})
                conn.close()
                info["matching_rows"] = len(seen_rows)
                info["status"] = "partial" if any(t.get("error") or t.get("errors") for t in info["tables"]) else "scanned"
            except Exception as exc:
                info.update(status="error", error=str(exc))
    dump("databases.json", db_summary)
    # Archives and binary containers require separate extraction/OCR to assert
    # content completeness. Keep a full candidate list, not a silent exclusion.
    dump("binary_and_archive_candidates.json", binary_candidates)
    summary = {"started_at": started, "finished_at": stamp(), "root": str(ROOT),
               "files_in_inventory": len(files), "matching_path_entries": len(paths),
               "matching_files": len(file_stats), "text": dict(counts),
               "path_categories": dict(collections.Counter(p["category"] for p in paths)),
               "database_files": len(db_summary), "database_matching_cells": sum(d["matching_cells"] for d in db_summary),
               "database_matching_rows": sum(d["matching_rows"] for d in db_summary),
               "databases_with_matches": sum(bool(d["matching_cells"]) for d in db_summary),
               "binary_archive_candidates": len(binary_candidates), "errors": errors,
               "exclusions": EXCLUDED, "limitations": ["Git object history not scanned", "No symlink targets followed",
               "Archive/PDF/Office/model-binary internals not exhaustively decoded", "Remote databases not queried",
               "SQLite views, virtual tables and FTS binary shadow tables not queried; primary tables scanned"]}
    dump("local_summary.json", summary)
    print(json.dumps(summary))


def ecr_inventory(profile):
    import boto3
    from botocore.config import Config
    session = boto3.Session(profile_name=profile)
    config = Config(connect_timeout=6, read_timeout=25, retries={"max_attempts": 3, "mode": "standard"})
    identity = session.client("sts", region_name="us-west-2", config=config).get_caller_identity()
    account = identity["Account"]
    if account != "399683337364":
        raise RuntimeError("Refusing to inventory a registry outside the verified BioMate account")
    regions = session.client("ec2", region_name="us-west-2", config=config).describe_regions(AllRegions=True)["Regions"]
    enabled = sorted(r["RegionName"] for r in regions if r["OptInStatus"] in ("opt-in-not-required", "opted-in"))
    report = {"started_at": stamp(), "account": account, "profile": profile,
              "region_opt_in_status": regions, "regions": [], "matching_repositories": [], "matching_images": [],
              "scope": "BioMate commercial-partition account; all enabled private-ECR regions plus ECR Public; names/tags, no layer pulls"}

    def region_scan(region, public=False):
        result = {"region": region, "registry_type": "public" if public else "private", "repositories_scanned": 0,
                  "images_scanned": 0, "matching_repositories": [], "matching_images": [], "errors": []}
        try:
            client = session.client("ecr-public" if public else "ecr", region_name=region, config=config)
            for page in client.get_paginator("describe_repositories").paginate():
                for repository in page.get("repositories", []):
                    result["repositories_scanned"] += 1
                    name = repository["repositoryName"]
                    matched_repo = NEEDLE in name.lower()
                    if matched_repo:
                        result["matching_repositories"].append({**repository, "region": region, "registry_type": result["registry_type"]})
                    try:
                        for images in client.get_paginator("describe_images").paginate(repositoryName=name):
                            for image in images.get("imageDetails", []):
                                result["images_scanned"] += 1
                                tags = image.get("imageTags", [])
                                if matched_repo or any(NEEDLE in t.lower() for t in tags):
                                    result["matching_images"].append({**image, "repositoryName": name,
                                       "repositoryUri": repository.get("repositoryUri"), "region": region,
                                       "registry_type": result["registry_type"],
                                       "match_reason": "repository_name" if matched_repo else "image_tag"})
                    except Exception as exc:
                        result["errors"].append({"repository": name, "error": str(exc)})
        except Exception as exc:
            result["errors"].append({"region": region, "error": str(exc)})
        return result

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        futures = [pool.submit(region_scan, region) for region in enabled]
        futures.append(pool.submit(region_scan, "us-east-1", True))
        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            report["matching_repositories"].extend(result.pop("matching_repositories"))
            report["matching_images"].extend(result.pop("matching_images"))
            report["regions"].append(result)
            dump("ecr.json", report)
            print(json.dumps(result), flush=True)
    report["finished_at"] = stamp()
    report["summary"] = {"private_regions_attempted": len(enabled),
                         "repositories_scanned": sum(r["repositories_scanned"] for r in report["regions"]),
                         "images_scanned": sum(r["images_scanned"] for r in report["regions"]),
                         "matching_repositories": len(report["matching_repositories"]),
                         "matching_image_digests": len(report["matching_images"]),
                         "region_errors": sum(bool(r["errors"]) for r in report["regions"])}
    dump("ecr.json", report)
    print(json.dumps(report["summary"]))


def backup_databases():
    """Scan SQLite backups too; they often lack a .db final suffix."""
    files = subprocess.check_output(["rg", "--files", "--hidden", "--no-ignore", "-0", *rgargs()], cwd=ROOT)
    candidates = [os.fsdecode(p) for p in files.split(b"\0") if p
                  and any(s in os.fsdecode(p).lower() for s in (".db", ".sqlite"))
                  and not os.fsdecode(p).endswith(("-wal", "-shm"))
                  and Path(os.fsdecode(p)).suffix.lower() not in (".db", ".sqlite", ".sqlite3", ".db3")]
    results = []
    with (OUTPUT / "database_backup_cells.jsonl").open("w") as out:
        for name in sorted(candidates):
            path = ROOT / name
            if path.is_symlink():
                continue
            with path.open("rb") as src:
                if src.read(16) != b"SQLite format 3\0":
                    continue
            info = {"path": name, "matching_cells": 0, "matching_rows": 0, "tables": [], "errors": []}
            results.append(info)
            try:
                db = sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True, timeout=2)
                db.execute("PRAGMA query_only=ON")
                rows_seen = set()
                for table, sql in db.execute("SELECT name,sql FROM sqlite_master WHERE type='table'").fetchall():
                    if table.startswith("sqlite_") or "VIRTUAL TABLE" in (sql or "").upper() or any(table.endswith(s) for s in ("_fts_data", "_fts_idx", "_fts_docsize", "_fts_config")):
                        continue
                    cols = db.execute("PRAGMA table_info(" + qident(table) + ")").fetchall()
                    if "WITHOUT ROWID" in (sql or "").upper():
                        identity = ",".join(qident(c[1]) for c in sorted(cols, key=lambda c: c[5]) if c[5])
                    else:
                        identity = "rowid"
                    detail = {"table": table, "matching_cells": 0}
                    info["tables"].append(detail)
                    for col in cols:
                        try:
                            for row in db.execute("SELECT " + identity + "," + qident(col[1]) + " FROM " + qident(table) + " WHERE instr(lower(CAST(" + qident(col[1]) + " AS TEXT)),?)>0", (NEEDLE,)):
                                value = row[-1].decode(errors="replace") if isinstance(row[-1], bytes) else str(row[-1])
                                key = tuple(str(v) for v in row[:-1])
                                rows_seen.add((table, key))
                                out.write(json.dumps({"path": name, "kind": "cell", "table": table, "column": col[1],
                                                      "row_identity": key, "identifiers": tokens(value),
                                                      "occurrences": value.lower().count(NEEDLE)}) + "\n")
                                info["matching_cells"] += 1
                                detail["matching_cells"] += 1
                        except Exception as exc:
                            info["errors"].append({"table": table, "column": col[1], "error": str(exc)})
                db.close()
                info["matching_rows"] = len(rows_seen)
            except Exception as exc:
                info["errors"].append({"error": str(exc)})
    dump("database_backups.json", results)
    print(json.dumps({"backup_databases": len(results), "matching_cells": sum(r["matching_cells"] for r in results),
                      "matching_rows": sum(r["matching_rows"] for r in results), "files_with_errors": sum(bool(r["errors"]) for r in results)}))


def binary_inventory():
    """Literal-byte and ZIP-member search without executing/unpickling files."""
    files = json.loads((OUTPUT / "binary_and_archive_candidates.json").read_text())
    pattern = re.compile(b"biomni", re.I)
    results = []
    skipped = []
    errors = []
    total = 0
    for name in files:
        path = ROOT / name
        if path.is_symlink():
            skipped.append({"path": name, "reason": "symlink target not followed"})
            continue
        try:
            offset = 0
            tail = b""
            positions = []
            with path.open("rb") as stream:
                while block := stream.read(4 * 1024 * 1024):
                    data = tail + block
                    positions.extend(offset - len(tail) + m.start() for m in pattern.finditer(data))
                    offset += len(block)
                    tail = data[-5:]
            total += offset
            if positions:
                results.append({"path": name, "kind": "literal_binary_bytes", "byte_offsets": positions,
                                "occurrences": len(positions)})
            if path.suffix.lower() in (".zip", ".pt", ".pth", ".docx", ".pptx", ".xlsx") and zipfile.is_zipfile(path):
                with zipfile.ZipFile(path) as archive:
                    for member in archive.infolist():
                        if member.is_dir():
                            continue
                        if NEEDLE in member.filename.lower():
                            results.append({"path": name, "kind": "archive_member_name", "member": member.filename})
                        if member.file_size > 128 * 1024 * 1024:
                            skipped.append({"path": name, "member": member.filename, "reason": "member exceeds 128 MiB inspection limit"})
                            continue
                        with archive.open(member) as stream:
                            data = stream.read()
                        matches = [m.start() for m in pattern.finditer(data)]
                        if matches:
                            results.append({"path": name, "kind": "archive_member_bytes", "member": member.filename,
                                            "byte_offsets": matches, "occurrences": len(matches)})
        except Exception as exc:
            errors.append({"path": name, "error": str(exc)})
    with (OUTPUT / "binary_occurrences.jsonl").open("w") as out:
        for row in results:
            out.write(json.dumps(row) + "\n")
    summary = {"files_considered": len(files), "raw_bytes_scanned": total, "matching_records": len(results),
               "matching_files": len(set(r["path"] for r in results)), "skipped": skipped, "errors": errors,
               "limitations": ["No pickle/model code execution", "No PDF content-stream decompression or OCR",
                               "No gzip/tar recursive decompression", "No extraction of nested archives"]}
    dump("binary_summary.json", summary)
    print(json.dumps(summary))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["local", "ecr", "backups", "binary"])
    parser.add_argument("--profile", default="default")
    args = parser.parse_args()
    if args.mode == "local":
        local_inventory()
    elif args.mode == "ecr":
        ecr_inventory(args.profile)
    elif args.mode == "backups":
        backup_databases()
    else:
        binary_inventory()
