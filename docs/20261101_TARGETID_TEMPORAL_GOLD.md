# Target-ID time-split gold set (T9) — build and first smoke result

Date: 2026-11-01. Code: `backend/lib/galaxy/ai/target_id/{temporal_gold,temporal_eval,temporal_gold_test}.py`. Data: `temporal_gold_data/` (queried 2026-11-01). The build and the smoke evaluation ran on the dev EC2 host in `/tmp` (no deployment, no container touched).

## Purpose
Test whether a ranking made only from pre-cut-off evidence recovers targets or (disease, target) pairs that gained their first approval after the cut-off. Until now the repository had no such gold set, so "finds novel targets" was untested.

## Rules (conservative)
A target is **novel** only if no approved drug, in any indication, was dated before the cut-off or left undated or ambiguous. An exact (disease, target) pair already approved before the cut-off is excluded. Non-human and complex targets are never gold. Drugs with more than three targets are dropped. Cut-off-year approvals count only when openFDA gives an exact date. Sources: ChEMBL (approvals, mechanisms, phase-4 indications), openFDA (dates), Open Targets (disease-id resolution and cross-check).

## Counts (from each file's `meta`)
| Cut-off | Novel pairs | Novel targets | Diseases with ≥2 pairs | New-indication pairs |
|---|---|---|---|---|
| 2023-06-30 | 11 | 7 | 1 | 26 |
| 2024-06-30 | 1 | 1 | 0 | 7 |
| 2025-01-01 | 0 | 0 | 0 | 0 |

## Smoke result (2023-06-30, first 10 diseases, 200 permutations, Open Targets leakage-safe datatypes)
Scored novel targets: 0 of 5 (n=1 disease). New-indication pairs: macro AUROC 0.548 (null 95th percentile 0.698, p=0.31) against a literature-popularity baseline of 0.691 (p=0.12). Every p-value is above 0.05.

## Reading
- **This is not evidence for or against novel-target discovery.** With one disease holding more than one novel pair, the novel subset cannot support a test. The numbers above are a working-pipeline check, not a finding.
- No claim of novel-target discovery is supported by this data, and none should be made. The earlier recall-only framing stands.
- The popularity baseline uses current literature scores, so it is itself not leakage-free.
- Cut-off year ambiguity, regional approval dates and supplements (not mapped to diseases) understate the new-indication subset.
- A usable test needs more cut-offs, a pooled design across many diseases, or prospective tracking of new approvals.

## Run
`cd backend && PYTHONPATH=lib python -m galaxy.ai.target_id.temporal_gold build` (cached, about 10–20 min), then `temporal_eval --gold <file> --live-ot --max-diseases N --n-perm 200`. Run on dev or EC2, not the laptop.
