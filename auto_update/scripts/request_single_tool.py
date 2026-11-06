#!/usr/bin/env python3
"""
Targeted SINGLE-TOOL discovery entry point for the auto-update pipeline.

Unlike `run_pipeline.py --mode full` (which crawls ~55 GitHub topics and is
driven by the nightly cron in `daily_update.sh`), this script fetches exactly
ONE named repository (or the single best match for a free-text capability
query) and runs it through the SAME pipeline stages via
`AutoUpdatePipeline._process_tool`:

    enhanced metadata -> version/duplicate gate -> feasibility gate ->
    API-availability gate -> docs fetch -> wrapper generation ->
    XML validation -> integrate (marked auto_discovered, quality-gated)

Design constraints (this file is the "riskiest workstream" targeted wrapper):
  * It NEVER performs an unbounded multi-topic crawl. `--repo` fetches one repo;
    `--query` runs a single bounded GitHub search and processes only the top
    candidate.
  * It does NOT reimplement or weaken any gate. Every gate (feasibility, API
    detection, duplicate/version, XML validation, integration quality checks)
    is the pipeline's own code, reused unchanged.
  * It matches the production cron configuration: execution-test is OFF by
    default (the nightly `daily_update.sh` runs with `ENABLE_TEST=0`), while the
    cheap static XML validation gate stays ON.
  * It backs up the main DB before any write, mirroring `daily_update.sh`, so
    the action is reversible.
  * It is intended to be invoked only by the GATED chat `request_new_tool`
    path (env flag + explicit user confirmation) or manually by an operator.
    Nothing here auto-runs.

Usage:
    python request_single_tool.py --repo owner/name [--json]
    python request_single_tool.py --query "nanopore methylation caller" [--json]

Options:
    --min-stars N   Minimum stars for --query search (default 10, matches cron)
    --test          Enable docker execution test (default OFF, matches cron)
    --test-db       Write to galaxy_ai_tools_test.db instead of the main DB
    --json          Emit a machine-readable result block for the caller

The result block is printed between sentinel lines so a caller can extract it
reliably even when the pipeline logs other lines to stdout:

    ===REQUEST_SINGLE_TOOL_RESULT===
    {"status": "...", ...}
    ===END_RESULT===
"""

import argparse
import json
import logging
import shutil
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, Optional

# Make sibling pipeline modules importable (same dir as this file).
sys.path.insert(0, str(Path(__file__).parent))

# Pipeline deps (PyGithub, pyyaml, colorama, …) are installed in the cron/runtime
# environment. If any are missing we must still emit a clean, parseable result
# instead of a raw traceback, so the gated caller can report "needs review".
_IMPORT_ERROR: Optional[str] = None
try:
    from detect_github_tools import GitHubDetector  # noqa: E402
    from run_pipeline import AutoUpdatePipeline  # noqa: E402
except Exception as _e:  # noqa: BLE001
    _IMPORT_ERROR = str(_e)
    GitHubDetector = None  # type: ignore
    AutoUpdatePipeline = None  # type: ignore

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    stream=sys.stderr,  # keep stdout clean for the result block
)
logger = logging.getLogger(__name__)

RESULT_START = "===REQUEST_SINGLE_TOOL_RESULT==="
RESULT_END = "===END_RESULT==="


def _emit_result(result: Dict, as_json: bool) -> None:
    """Print the machine-readable result block (always), plus a human line."""
    print(RESULT_START)
    print(json.dumps(result))
    print(RESULT_END)
    if not as_json:
        logger.info("Result: %s", json.dumps(result, indent=2))


def _backup_main_db(db_path: Path) -> Optional[str]:
    """Copy the main DB before any write, mirroring daily_update.sh. Best-effort."""
    try:
        if not db_path.exists():
            return None
        backup_dir = Path(__file__).parent.parent / 'backups'
        backup_dir.mkdir(parents=True, exist_ok=True)
        ts = datetime.now().strftime('%Y%m%d_%H%M%S')
        dest = backup_dir / f"galaxy_ai_tools_single_{ts}.db"
        shutil.copy2(db_path, dest)
        # Keep only the most recent 10 single-tool backups to bound disk use.
        backups = sorted(backup_dir.glob('galaxy_ai_tools_single_*.db'))
        for old in backups[:-10]:
            try:
                old.unlink()
            except OSError:
                pass
        logger.info("DB backup created: %s", dest)
        return str(dest)
    except Exception as e:  # noqa: BLE001 - backup must never crash the run
        logger.warning("DB backup failed (continuing): %s", e)
        return None


def _resolve_repo(detector: GitHubDetector, repo: Optional[str], query: Optional[str]) -> Optional[Dict]:
    """
    Resolve a single discovery dict either from an exact repo (owner/name) or
    from the single best match of a bounded capability search. Returns None if
    nothing suitable is found.
    """
    if repo:
        full_name = repo.strip()
        if '/' not in full_name:
            logger.error("--repo must be 'owner/name', got: %s", full_name)
            return None
        logger.info("Fetching single repo: %s", full_name)
        gh_repo = detector.github.get_repo(full_name)
        return detector._extract_repo_data(gh_repo)

    # Bounded capability search: ONE query, top candidate only. Not a crawl.
    q = query.strip()
    logger.info("Searching GitHub for best match of capability: %r", q)
    search_query = f"{q} topic:bioinformatics"
    results = detector.github.search_repositories(
        query=search_query, sort='stars', order='desc'
    )
    # Take only the first result (bounded — no iteration over the full page set).
    for gh_repo in results:
        logger.info("Top candidate: %s", gh_repo.full_name)
        return detector._extract_repo_data(gh_repo)
    return None


def _derive_status(stats: Dict, discovery: Optional[Dict]) -> Dict:
    """Map pipeline stats onto a compact status for the caller."""
    if discovery is None:
        return {"status": "not_found",
                "message": "No matching GitHub repository found for the request."}

    tool_name = discovery.get('name')
    repo = discovery.get('full_name')
    base = {"tool": tool_name, "repo": repo,
            "quality_score": discovery.get('quality_score'),
            "classification": discovery.get('classification')}

    if stats.get('integrated', 0) >= 1:
        base.update(status="registered",
                    message=f"'{tool_name}' was wrapped, validated and registered "
                            f"as an auto_discovered tool.")
    elif stats.get('skipped_duplicate', 0) >= 1 or stats.get('skipped_old_version', 0) >= 1:
        base.update(status="already_exists",
                    message=f"'{tool_name}' already exists in the catalog "
                            f"(duplicate or same/older version).")
    elif stats.get('feasibility_rejected', 0) >= 1:
        base.update(status="not_feasible",
                    message=f"'{tool_name}' did not pass the feasibility gate "
                            f"(not a wrappable command-line/analysis tool).")
    elif stats.get('skipped_has_api', 0) >= 1:
        base.update(status="has_api",
                    message=f"'{tool_name}' exposes a hosted API; prefer the API "
                            f"over local installation.")
    elif stats.get('wrappers_generated', 0) >= 1:
        base.update(status="needs_review",
                    message=f"'{tool_name}' was wrapped but not registered "
                            f"(validation/test gate not satisfied) — needs manual review.")
    else:
        base.update(status="needs_review",
                    message=f"'{tool_name}' could not be processed to registration "
                            f"— needs manual review.")

    if stats.get('errors'):
        base["errors"] = stats["errors"][:5]
    return base


def main() -> int:
    parser = argparse.ArgumentParser(description='Targeted single-tool auto-update entry point')
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--repo', type=str, help="Exact GitHub repo 'owner/name'")
    group.add_argument('--query', type=str, help='Free-text capability to find the single best repo for')
    parser.add_argument('--min-stars', type=int, default=10, help='Min stars for --query (default 10)')
    parser.add_argument('--test', action='store_true', help='Enable docker execution test (default OFF)')
    parser.add_argument('--test-db', action='store_true', help='Use galaxy_ai_tools_test.db')
    parser.add_argument('--json', action='store_true', help='Emit machine-readable result')
    args = parser.parse_args()

    if _IMPORT_ERROR is not None:
        _emit_result({"status": "error",
                      "message": f"Auto-update pipeline dependencies unavailable: {_IMPORT_ERROR}. "
                                 f"Install auto_update/requirements.txt in this environment."},
                     args.json)
        return 1

    script_dir = Path(__file__).parent.parent
    config_dir = script_dir / 'config'
    data_dir = script_dir / 'data'

    try:
        pipeline = AutoUpdatePipeline(config_dir, data_dir, use_test_db=args.test_db)
    except Exception as e:  # noqa: BLE001
        _emit_result({"status": "error", "message": f"Pipeline init failed: {e}"}, args.json)
        return 1

    token = pipeline.config.get('credentials', {}).get('github', {}).get('token')
    if not token:
        _emit_result({"status": "error",
                      "message": "GitHub token not configured (auto_update/config/credentials.yaml)."},
                     args.json)
        return 1

    # Reuse the pipeline's own detector configuration (same gates/scoring).
    detector = GitHubDetector(token, pipeline.config)

    # Resolve the single tool.
    try:
        discovery = _resolve_repo(detector, args.repo, args.query)
    except Exception as e:  # noqa: BLE001
        _emit_result({"status": "error", "message": f"Repo resolution failed: {e}"}, args.json)
        return 1

    if discovery is None:
        _emit_result(_derive_status(pipeline.stats.stats, None), args.json)
        return 0

    # Back up the main DB before any write (reversibility). test-db is disposable.
    if not args.test_db:
        _backup_main_db(pipeline.db_path)

    # Run the single tool through the UNCHANGED pipeline stages.
    #   validate=True  -> keep the static XML quality gate ON
    #   test=args.test -> execution test OFF by default (matches the nightly cron)
    try:
        pipeline._process_tool(discovery, validate=True, test=args.test)
    except Exception as e:  # noqa: BLE001
        logger.error("Processing failed: %s", e)
        pipeline.stats.add_error(str(e))

    result = _derive_status(pipeline.stats.stats, discovery)
    _emit_result(result, args.json)
    return 0


if __name__ == '__main__':
    sys.exit(main())
