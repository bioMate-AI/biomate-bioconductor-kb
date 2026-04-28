# Verified Starter Queries

This folder contains starter queries intended for the BioMate onboarding welcome screen.
**Each query must be verified to trigger the correct workflow before being added to the UI.**

## Verification process

1. Add a candidate query to `candidates.yaml`
2. Run `python verify_queries.py` against the live backend
3. Check that:
   - The routing API returns the correct `workflow_id`
   - The workflow exists in the DB (`workflow_type != 'disambiguation'`)
   - The routing confidence score ≥ 6.0
4. Passing queries are written to `verified.yaml`
5. Only import from `verified.yaml` into the frontend

## Files

- `candidates.yaml` — queries to test (one per domain, with expected workflow)
- `verified.yaml` — auto-generated; queries that passed verification
- `verify_queries.py` — test runner that hits `/api/ai_assistant` and checks routing
- `report.json` — last verification run results

## Merging into BioMate

Once `verified.yaml` has ≥ 2 passing queries per domain, run:
```bash
python export_to_frontend.py
```
This generates `frontend/client/src/lib/onboarding-queries.ts` which the welcome screen imports.
