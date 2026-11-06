# Session handoff — AI-search claim reconciliation (2026-10-11)

Takeover of the website-search workstream from the prior (Codex) session. Scope this session: verify the pending benchmark claims against source evidence, correct the supportable ones on the live marketing site, and prepare the blocked measurement step for the account holder. Objective is AI-search credibility: an engine that retrieves an over-stated, un-traceable number hurts us more than a modest honest one.

## What was done

### 1. Evidence verification (read-only, three parallel audits)
Each pending claim traced to artifacts under `evaluation/` + `docs/` before any edit:

| Claim (was live) | Verdict | Source reality |
|---|---|---|
| BixBench **92.7%** beating Biomni 88.7% "same methodology" | Unsupported | No result file; produced via 9–18 capsule-specific hand-coded handlers that bypass the LLM; internal audit (`docs/20260516…`) estimates true product score ~60–70% (unmeasured); durable mean 87.7%. `compare.html` also misattributes authorship to "the BioMate team (Xu et al.)" — it is **FutureHouse, arXiv:2503.00096**. |
| PBPK **100% on 18 compounds**, "regulatory-ready" | Unsupported | Dataset is **15** compounds, not 18; no file validates predicted-vs-observed PK; only executed run is workflow-handling and **fails** its prereq target (33.3%); 2-fold validation code never run. |
| Routing **94.6% "first-pick" across "36 domains"** | Partly true, mislabeled | 94.6% is a partial-credit aggregate (109 exact + 9 half + 2 wrong / 120, April 2026 v11); strict exact first-choice = **90.8%**. "36 domains" false (dataset ~13). A later n=155 run scored 61.9% (not directly comparable). |
| "**4,000+ validated workflows**" | Conflation | Catalog ~4,210 but validated-by-real-execution subset ~1,092 (CLAUDE.md registry). "4,000+" fine as catalog; "validated" was the false word. |

### 2. Corrections (owner decision: hold BixBench + PBPK for clean re-runs; fix routing + count)
- **Routing** → every surface leads with 90.8% exact first-choice; 94.6% disclosed as "including closely-related equivalent pipelines (partial credit)"; false "36 domains" test-coverage removed (kept only for the catalog); dated April 2026; stability card corrected to the real 24-query 20% subsample.
- **Workflow count** → "4,000+ validated workflows" → "a catalog of 4,000+ workflows"; validated subset (1,092) cited explicitly in `llms.txt`/`llms-full.txt`.
- **Held, untouched (still live):** BixBench 92.7%, PBPK 100%/18 — pending owner-commissioned clean product-path runs.

### 3. Tests + deploy
- Added two regression guards in `tests/seo.test.cjs` (routing exact-first-choice disclosure; catalog-vs-validated non-conflation). Suite **57/57**; `prepare_marketing_shell.cjs --check` passes.
- **Deployed live** to biomate.ai via `scripts/deploy_marketing.sh` (backup saved, nginx reloaded, verification passed).

### 4. Baseline step prepared for the account holder
`docs/20261011_AI_SEARCH_BASELINE_CAPTURE_RUNBOOK.md` — operator runbook for the 24-prompt × 5-provider consumer measurement (blocked on sign-ins/terms). Model scores the archived answers afterward.

## Version control
- Local commits on `cursor/tutorial-live-recording-and-report-editing-4ea7`: `c6992544e` (reconciliation), `88f6f462c` (runbook), plus this doc.
- **PR #282** (https://github.com/bioMate-AI/biomate/pull/282) — focused branch `marketing/claim-reconciliation-20261011` (base = the cursor branch). Carries the claim-instance fixes still unreconciled on that base. The `cursor/…` branch itself cannot be pushed with the current token (its history edits a GitHub Actions workflow file; token lacks `workflow` scope) — hence the "copied-out" focused branch.
- Note: trunk (`integration/next-phase`) hosts a **different** marketing-site version that does not contain these claim strings; this reconciliation applies to the branch deployed to biomate.ai.

## Open items / next steps
1. **Owner: commission clean product-path re-runs** of BixBench (no handlers) and PBPK (L5–L6 predictive 2-fold against observed PK), then publish real numbers and fix: the FutureHouse attribution, the PBPK prereq 100%→33.3% contradiction, and the "regulatory-ready" framing.
2. **Owner: run the AI-search baseline** per the runbook; hand the round file back for scoring.
3. **Still blocked:** Google/Bing webmaster indexing verification (needs property access); real contact-form delivery test.
4. Consider a routing re-measurement on an expanded set (the April n=120 is the live number; a later n=155 run was far lower).

Primary evidence doc: `docs/20261009_AI_SEARCH_BASELINE_AND_CLAIM_RECONCILIATION.md` (reconciliation pass 2).
