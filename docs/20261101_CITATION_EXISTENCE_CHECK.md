# Citation existence check (gap T8)

## Problem
The research agent dropped or fell back from unverifiable references, but (a) never said so when no reference was grounded, and (b) never checked that a cited PMID/DOI exists.

## Design
`backend/lib/galaxy/ai/agents/citation_check.py` (new module, stdlib only, Python 3.9-safe).

- `verify_citation(c, http_get=None, threshold=0.75, offline=None)` and `verify_citations(list, ...)`. A citation is a dict or object with `pmid`, `doi`, `title`. It never raises.
- PMID: NCBI E-utilities `esummary` (db=pubmed). DOI: Crossref `/works/{doi}` (404 = not found).
- Title match: `max(difflib ratio, token Jaccard)` on normalised titles, threshold `TITLE_MATCH_THRESHOLD = 0.75`. No cited title: existence only.
- Statuses: `verified`, `not_found`, `title_mismatch`, `unverified` ("could not check": network error, HTTP 5xx, timeout; never reported as verified and not cached), `not_checked_offline` (env `TARGET_ID_OFFLINE=1` or `BIOMATE_OFFLINE=1`), `no_identifier`. With both PMID and DOI, any rejection wins.
- Injectable `http_get(url, timeout) -> (status, json)`; in-process cache; 8 s timeout; NCBI throttled to one call per 0.4 s (under 3/s keyless), Crossref one per 0.15 s.
- `evidence_status(rows)`: `grounded` (at least one usable, all verified), `partially_grounded` (some usable but not verified, e.g. offline or unreachable), `insufficient` (no usable citation).
- `check_answer_citations(answer, citations, n_numbered=)`: drops `not_found`/`title_mismatch` citations, renumbers `[N]` markers and adds a removal note; when nothing is usable, `refuse_without_evidence` removes reference sections, DOI/PMID lines and `[N]` markers and prefixes "Insufficient retrievable evidence ... no bibliography is given."

## Hook
`research_agent.py` (clean in git before this change): `ResearchResponse` gains `evidence_status` and `citation_verification`; `_synthesize_response` calls `check_answer_citations` (in an executor, wrapped in try/except so any failure leaves the answer untouched) before the evidence-boundary step. Benchmark DOI citations are checked for existence only (their title is a placeholder). Not hooked: `frontend/server/grounded-research-reply.ts` (read only; another session is editing nearby); the chat layer can read `evidence_status` / `citation_verification` from the agent result.

## Tests
`test_citation_check.py` (8 offline tests with fake HTTP) and the existing `test_research_citation_grounding.py` pass.
Live: `PYTHONPATH=backend/lib python3 scripts/verify_citation_check_live.py` (2026-11-01).

| Set | Case | Result |
|---|---|---|
| real x10 | PMIDs 25516281 (DESeq2), 19451168 (BWA), 20644199 (GATK), 22388286 (Bowtie 2), 19910308 (edgeR), 2231712 (BLAST), 34265844 (AlphaFold, with DOI); DOIs nature14539, s41586-021-03819-2, 171737a0 | all verified, similarity 1.0 |
| fake x10 | PMIDs 99999991, 88888888 | not_found |
| | malformed PMID 2551628100 | not_found |
| | DOIs nature99999999, s13059-014-0550-9999, 10.1234/fake.2020.001 | not_found |
| | real DOI nature14539 / 171737a0 with wrong titles | title_mismatch (0.17 / 0.30) |
| | real PMID 25516281 with wrong title | title_mismatch (0.30) |
| | real PMID 2231712 + fake DOI | not_found |

20/20 as expected.

## Limits
- Existence is not support: a real paper that does not back the claim passes. Claim-to-paper support is a separate gap.
- A title match only shows the cited title is the registry title for that ID; a hallucinated title paired with a wrong-but-real ID of similar title would pass.
- Crossref does not cover every DOI agency (DataCite, mEDRA DOIs return 404 and would be rejected); PubMed does not cover preprints. Citations carrying only such IDs may be falsely dropped.
- Offline or unreachable registries yield `partially_grounded`, not `grounded`.
- The synthesis path now makes up to a few network calls per answer (cached, 8 s timeout each).
