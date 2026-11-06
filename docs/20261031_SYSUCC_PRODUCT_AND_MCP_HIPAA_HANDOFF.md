# 2026-10-31 handoff — SYSUCC product PRs and HIPAA MCP isolation

Canonical copy for this workstream also lives in the parent review tree:

`/Users/kky/biomate-review/docs/20261031_SYSUCC_PRODUCT_AND_MCP_HIPAA_HANDOFF.md`

That file has the full BD pointers, PR table, HIPAA rationale, and leftover list. Summary:

- **#308 merged** — first SYSUCC product batch (sandbox, assay coverage, model versions).
- **#310 open** — censored ranking, salt/parent identity, Tanimoto GP, Benchling LIMS poll (`fix/sysucc-assay-bo-benchling`).
- **biomate-connector #22 open** — hide instrument tools on the HIPAA cloud unless on-prem; `instruments:control` is not a default scope; `POST /oauth/revoke`.
- **HIPAA lock** (`BIOMATE_MCP_HIPAA=1` / known cloud hostnames) is in the connector working tree and in uncommitted `scripts/sync_to_dev.sh`; healthz, Dockerfile default, and tests were not finished.

Do not send this, or any English research file, to BD. BD gets only `docs/20261030_SYSUCC_BD_CAPABILITY_AND_USE_CASES_ZH.docx`.
