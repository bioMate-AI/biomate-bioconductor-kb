#!/usr/bin/env python3.9
"""Live smoke test for the externally-served federated fetchers.

Why this exists
---------------
`backend/lib/galaxy/ai/federated_query.py` grew four fetchers that reach LIVE
external APIs with NO coverage beyond the offline `data_sources.registry_drift()`
check (which only asserts the registry ids and `_FETCHERS` keys agree — it never
calls out, so a silent schema break or endpoint move reads as "0 results"):

    pdbe         https://www.ebi.ac.uk/pdbe/api/mappings/best_structures/<acc>
    chembl       https://www.ebi.ac.uk/chembl/api/data/{molecule,target,activity}
    gnomad       https://gnomad.broadinstitute.org/api              (GraphQL)
    opentargets  https://api.platform.opentargets.org/api/v4/graphql (GraphQL)

Each needs an identifier-resolution hop first (symbol -> UniProt / ENSG via
mygene.info), so this also exercises `resolve_gene`.

This is a LIVE test: it must run where outbound HTTPS to those hosts is allowed
(the dev Galaxy container), NOT in an offline CI sandbox. It is intentionally
skipped when `BIOMATE_OFFLINE_MODE` is set.

Verdict rules (per source)
--------------------------
- transport/GraphQL error  -> FAIL (surfaced by `_run_fetcher` as status=error)
- zero results             -> FAIL (these queries are known-populated targets)
- non-empty + key field    -> PASS

Exit code 0 only if every source passes. Prints one line per source and a JSON
summary on the last line.

Run on dev:
    docker exec -i -u galaxy biomate-galaxy-dev python3.9 - < scripts/smoke_federated_fetchers.py
Run locally against a backend that has network:
    PYTHONPATH=backend/lib python3.9 scripts/smoke_federated_fetchers.py
"""
import json
import os
import sys

try:
    from galaxy.ai.federated_query import _FETCHERS, _run_fetcher
except Exception as e:  # pragma: no cover - import wiring
    print(json.dumps({"ok": False, "error": "cannot import federated_query: %s" % e}))
    sys.exit(2)

if os.environ.get("BIOMATE_OFFLINE_MODE", "").lower() in ("1", "true", "yes"):
    print("SKIP: BIOMATE_OFFLINE_MODE set — live fetcher smoke needs real network egress")
    sys.exit(0)

# (source id, query, key that every result row must carry non-null)
CASES = [
    ("pdbe", "ABL1", "pdb_id"),          # ABL1 -> P00519 -> ranked experimental structures
    ("chembl", "aspirin", "chembl_id"),  # name search -> molecule rows
    ("gnomad", "BRAF", "gene_id"),       # BRAF -> ENSG -> gnomAD constraint
    ("opentargets", "BRAF", "disease"),  # BRAF -> ENSG -> target-disease associations
]

results = []
all_ok = True
for source, query, key in CASES:
    fn = _FETCHERS.get(source)
    if fn is None:
        results.append({"source": source, "ok": False, "reason": "no fetcher registered"})
        all_ok = False
        print("FAIL %-12s no fetcher registered in _FETCHERS" % source)
        continue
    try:
        out = _run_fetcher(fn, query)
    except Exception as e:  # pragma: no cover - defensive
        results.append({"source": source, "ok": False, "reason": "exception: %s" % e})
        all_ok = False
        print("FAIL %-12s exception: %s" % (source, e))
        continue

    rows = out.get("results") or []
    err = out.get("error")
    if err:
        ok = False
        reason = "transport/graphql error: %s" % err
    elif not rows:
        ok = False
        reason = "0 results for %r (endpoint moved / schema break / resolver miss?)" % query
    elif not any(r.get(key) is not None for r in rows):
        ok = False
        reason = "results present but none carry %r" % key
    else:
        ok = True
        sample = next((r.get(key) for r in rows if r.get(key) is not None), None)
        reason = "%d rows, e.g. %s=%s" % (len(rows), key, sample)

    all_ok = all_ok and ok
    results.append({"source": source, "query": query, "ok": ok, "rows": len(rows), "reason": reason})
    print("%-4s %-12s %s" % ("PASS" if ok else "FAIL", source, reason))

print(json.dumps({"ok": all_ok, "sources": results}))
sys.exit(0 if all_ok else 1)
