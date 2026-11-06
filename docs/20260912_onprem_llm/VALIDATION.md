# Documentation validation — 12 September 2026

- Static extraction completed over 1,015 tracked source files in the configured scope, with no Python parse errors.
- 356 prompt expressions/builders: exact source expression, source line region, SHA-256 expression hash and source-file hash all checked against the checkout at validation time.
- 165 static callsite candidates recorded. This includes helper definitions and optional/offline paths and is not a count of live production calls.
- 449 local Markdown links checked for file/directory existence and valid line bounds (including the report being created here).
- All generated JSON files parse; extraction Python parses; the TypeScript extractor executed successfully during inventory generation.
- Regulatory split overlap was independently recomputed from canonical full `messages`, without metadata: original train/dev 60, train/test 68, dev/test 4; v6 train/dev 224, train/test 218, dev/test 34 distinct shared sequences. No raw training rows were copied into these documents.
- Manual audit checked the main chat, routing, parameter, research, repair, findings/report and regulatory paths described in the catalog. PaperQA internal templates and deployed runtime skills remain explicitly outside the static prompt extraction.

Final extraction base commit: `7971127cbca05a4d6c3ba53ff83e64ea9ba4a355` plus working-tree content; source hashes are recorded in the manifest/registry. Unrelated concurrent application edits were not changed by this documentation task.

## Work not performed

No application behavior was modified, no inference endpoint or GPU training was run, and no live production/network-isolation benchmark was claimed. Documentation/source integrity checks do not establish model quality, deployment reachability, scientific validation or runtime parity. Those are explicit work packages and release gates in the plan.

## Reproduce

From the repository root, run `python3 docs/20260912_onprem_llm/build_inventory.py` with the repository's existing Node/TypeScript dependencies. This refreshes the machine inventories and prompt appendix from the then-current checkout. It does not import application modules, call models or overwrite the human-written task catalog/plan. Review task-catalog line references and this validation record after any source changes.
