"""
Verify candidate starter queries against the live BioMate routing API.

Usage:
    python verify_queries.py [--base-url http://localhost:5000] [--token <jwt>]

Writes:
    verified.yaml  — queries that passed
    report.json    — full per-query results
"""

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Any

import requests
import yaml

HERE = Path(__file__).parent
CANDIDATES_FILE = HERE / "candidates.yaml"
VERIFIED_FILE = HERE / "verified.yaml"
REPORT_FILE = HERE / "report.json"

MIN_CONFIDENCE = 6.0
ROUTING_ENDPOINT = "/api/ai_assistant"
SEARCH_ENDPOINT = "/api/ai_assistant/search_ranked"


def call_routing(base_url: str, query: str, token: str | None) -> dict[str, Any]:
    """Hit the AI assistant endpoint and return the parsed response."""
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"

    resp = requests.post(
        f"{base_url}{ROUTING_ENDPOINT}",
        json={"message": query, "session_id": f"verify_{int(time.time())}"},
        headers=headers,
        timeout=30,
    )
    resp.raise_for_status()
    return resp.json()


def call_search_ranked(base_url: str, query: str, token: str | None) -> dict[str, Any]:
    """Hit the search_ranked endpoint for raw routing score."""
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"

    resp = requests.post(
        f"{base_url}{SEARCH_ENDPOINT}",
        json={"user_intent": query, "limit": 5},
        headers=headers,
        timeout=30,
    )
    if not resp.ok:
        return {}
    return resp.json()


def verify_query(base_url: str, candidate: dict, token: str | None) -> dict[str, Any]:
    """Run a single candidate through routing and return a result record."""
    query = candidate["query"]
    expected = candidate.get("expected_workflow", "")
    keywords = [k.lower() for k in candidate.get("expected_keywords", [])]

    result: dict[str, Any] = {
        "domain": candidate["domain"],
        "query": query,
        "expected_workflow": expected,
        "pass": False,
        "reason": "",
        "routing_response": {},
        "search_response": {},
    }

    try:
        # Try search_ranked first (faster, no LLM)
        search_resp = call_search_ranked(base_url, query, token)
        result["search_response"] = search_resp

        ranked = search_resp.get("results", [])
        if ranked:
            top = ranked[0]
            top_name = (top.get("name") or top.get("workflow_name") or "").lower()
            top_score = float(top.get("score", 0))

            keyword_hit = any(kw in top_name for kw in keywords) or (
                expected.lower() in top_name
            )

            if keyword_hit and top_score >= MIN_CONFIDENCE:
                result["pass"] = True
                result["reason"] = f"search_ranked top={top_name!r} score={top_score:.2f}"
                return result
            else:
                result["reason"] = f"search_ranked top={top_name!r} score={top_score:.2f} (expected {expected!r})"

        # Fall through to full routing API
        routing_resp = call_routing(base_url, query, token)
        result["routing_response"] = routing_resp

        workflow_type = routing_resp.get("workflow_type", "")
        workflow_name = (routing_resp.get("workflow_name") or routing_resp.get("name") or "").lower()
        score = float(routing_resp.get("confidence", routing_resp.get("score", 0)))

        if workflow_type == "disambiguation":
            # Check if expected is in candidates list
            candidates_list = routing_resp.get("candidates", [])
            names = [c.get("name", "").lower() for c in candidates_list]
            if any(expected.lower() in n or any(kw in n for kw in keywords) for n in names):
                result["pass"] = True
                result["reason"] = f"disambiguation — expected workflow in candidates: {names}"
            else:
                result["reason"] = f"disambiguation — expected not found in {names}"
        elif keyword_hit := any(kw in workflow_name for kw in keywords) or (expected.lower() in workflow_name):
            if score >= MIN_CONFIDENCE or score == 0:  # score=0 means field absent, treat as ok
                result["pass"] = True
                result["reason"] = f"routing matched {workflow_name!r} score={score:.2f}"
            else:
                result["reason"] = f"routing matched {workflow_name!r} but score {score:.2f} < {MIN_CONFIDENCE}"
        else:
            result["reason"] = f"routing returned {workflow_name!r}, expected {expected!r}"

    except Exception as exc:
        result["reason"] = f"error: {exc}"

    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://localhost:5000")
    parser.add_argument("--token", default=None)
    args = parser.parse_args()

    data = yaml.safe_load(CANDIDATES_FILE.read_text())
    candidates = data.get("queries", [])

    print(f"Verifying {len(candidates)} candidate queries against {args.base_url}...")
    results = []
    verified = []

    for i, candidate in enumerate(candidates, 1):
        print(f"  [{i}/{len(candidates)}] {candidate['domain']}: {candidate['query'][:60]}...", end=" ")
        result = verify_query(args.base_url, candidate, args.token)
        results.append(result)
        status = "PASS" if result["pass"] else "FAIL"
        print(f"→ {status} ({result['reason']})")

        if result["pass"]:
            verified.append({
                "domain": candidate["domain"],
                "query": candidate["query"],
                "expected_workflow": candidate.get("expected_workflow", ""),
            })

    # Write report
    report = {
        "total": len(candidates),
        "passed": sum(1 for r in results if r["pass"]),
        "failed": sum(1 for r in results if not r["pass"]),
        "results": results,
    }
    REPORT_FILE.write_text(json.dumps(report, indent=2))
    print(f"\nReport written to {REPORT_FILE}")

    # Write verified
    verified_data = {"queries": verified}
    VERIFIED_FILE.write_text(yaml.dump(verified_data, allow_unicode=True, default_flow_style=False))
    print(f"Verified queries written to {VERIFIED_FILE}")

    # Summary
    pct = report["passed"] / report["total"] * 100 if report["total"] else 0
    print(f"\n{report['passed']}/{report['total']} passed ({pct:.0f}%)")
    if report["passed"] < report["total"]:
        print("\nFailed queries:")
        for r in results:
            if not r["pass"]:
                print(f"  [{r['domain']}] {r['query'][:60]} — {r['reason']}")

    sys.exit(0 if report["passed"] == report["total"] else 1)


if __name__ == "__main__":
    main()
