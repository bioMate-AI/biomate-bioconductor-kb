# Marketing Workstream — Handoff to a Dedicated Session

**Date:** 2026-10-05 · **Purpose:** transfer all BioMate marketing / positioning / publication
work out of the on-prem-LLM engineering session into a dedicated marketing session. This doc is the
single entry point: read it first, then the artifacts it points at. Everything below is already
written and committed — the new session **continues** it, it does not start from scratch.

> **Scope boundary.** This workstream is *marketing, positioning, and publication strategy* — and the
> evidence/claim discipline behind them. It does NOT include the engineering tasks that produced the
> evidence (routing fix, bioc benchmark runners, on-prem LLM training, tutorial recording pipeline).
> Those stay in the engineering session. When the marketing session needs a new number, it **requests**
> it from engineering; it does not fabricate or re-run.

---

## 1. Constraints the marketing session MUST honor (non-negotiable)

These are standing user rules; violating them is a regression, not a style choice.

- **Honesty / claim discipline.** Only claim what is evidenced. Every "best / first / only / no
  competitor" claim must survive a competitive pass + a prior-survey check, and lead with the honest
  gap. The claim matrix (strategy §9) is the source of truth for CLAIMABLE vs CANNOT-CLAIM.
- **Citation integrity.** Every external-facing number traces to a real, verifiable source. Never
  fabricate a DOI. Flag reconstructed or paywalled numbers.
- **No method disclosure externally.** Outward docs state WHAT BioMate delivers + a light credibility
  tag, NOT the tool stack / recipe / prompts. The "how" stays internal.
- **Formal academic register.** No salesy taglines or punchlines — they undercut senior-scientist
  credibility. This applies to decks, emails, and the website copy.
- **Proposals are forward-looking.** A proposal describes work being built; present it confidently but
  do not claim it is already finished or validated.
- **No Artifact tool, ever.** It publishes publicly without consent. Write to `docs/` (or
  `docs/marketing/`, `internal/marketing-research/`). Website lives in `webpage_design_v2/` static
  HTML (NOT the React app).
- **Continuous documentation.** One living master doc per workstream, updated each step, with an
  honesty contract + change log.
- **Date-prefixed docs in `docs/`** only — never in repo/frontend/backend root.
- **Commit attribution:** end commit messages with
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

---

## 2. Artifact inventory (what exists, where)

### Strategy & plan (the two master docs)
| File | What it holds | State |
|---|---|---|
| `docs/marketing/biomate-marketing-strategy.md` (380 ln) | Full strategy: exec summary, market survey (incumbents/AI-agents/competitor table/sizing/China), evidence-graded uniqueness, positioning/ICP/messaging/funnel/metrics, phased GTM (A–D, each milestone-gated), risks & honesty guardrails, **§8 headline selling points + competitor contrast**, **§9 claim matrix (CLAIMABLE / CANNOT-CLAIM / open-LLM status / convert partial→proven)** | Living master — continue here |
| `docs/marketing/manuscript-plan.md` (209 ln) | Publication plan: inventory of current drafts; recommended Papers A–D + M1–M5 with venue + single core claim each; per-paper gaps & next work; cross-cutting gaps before submission | Living master — continue here |

### Supporting research (internal only — "how"/competitive, not for external use)
- `internal/marketing-research/competitors_ai_agents.md` — FutureHouse, Virtual Pharma, Biomni, etc.
- `internal/marketing-research/competitors_bioinformatics_platforms.md` — Seqera/Latch/DNAnexus/data-clouds.
- `internal/marketing-research/china_market_sizing_regulatory.md` — China enterprise + data-residency.
- `internal/marketing-research/internal_evidence_and_manuscripts.md` — evidence crosswalk.
- `internal/marketing-research/marketing_skills_inventory.md` — the skill set catalogue.
- `docs/marketing/skills/` — vendored marketing skill packs (Apache-2.0 + MIT licensed; README).

### Evidence docs the claims rest on (produced by the engineering session; cite these, don't re-run)
- `docs/20261004_PAPER_B_HARNESS_VS_LLM_DRAFT.md` — the task-split / "harness, not the model" paper draft.
- `docs/20261004_EFFICIENCY_AND_COST_FOR_MANUSCRIPTS.md` — **measured vs projected** speed/cost table
  (§A measured, §C projected-label-only, §F RealBio-usage×real-price, §G invoice-grade anchor). This is
  the canonical source for every efficiency/cost number in marketing copy.
- `docs/20261004_KB_DIVIDEND_UNIFIED.md` — KB-dividend-scales-inversely-with-model-strength result.
- `docs/20261004_BIOC_SELECTION_MATRIX_RESULTS.md` + `..._DESIGN_GATE.md` — bioc method-selection matrix.
- `docs/20261004_CLOSE_THE_GAP_ROUTING.md` / `docs/20261004_REALBIO_LLM_VS_HARNESS.md` — routing result.
- `docs/20261004_AUTOLOOP_LIVE_PROOF.md` (+ `docs/autoloop_live_proof_20261004/*.json`) — live QC-gate proof.
- `docs/20261004_CATALOG_COUNT_RECONCILIATION.md` — the authoritative catalog counts for copy.
- `docs/20261004_HERO_A_CASE_STUDY.md` + `docs/20261004_HERO_CASE_STUDY_DEMO_SPEC.md` — the flagship
  hero demo ("BioMate caught a cardiotoxic candidate and remediated the screen").
- `docs/20261004_DL_ML_MODULE_TUTORIAL_PLAN.md` — the DL/ML tutorial track plan (marketing pillar).

---

## 3. State of the claims (short form — authoritative version is strategy §9)

**CLAIMABLE now (evidenced + defensible):**
- Chat-driven **QC auto-loop that halts a scientifically-unsafe candidate with a cited threshold +
  grounded remediation over an executed pipeline** — no surveyed competitor demonstrates this (hero A).
- **The knowledge/harness layer, not model scale, carries biomedical workflow automation** — a
  small on-prem 9B + KB matches frontier on routing and bioc method-selection; KB dividend scales
  inversely with model strength (Paper B).
- **On-prem economics:** match frontier capability at ~$0 marginal API vs cents/task (efficiency §F/§G).
- **Measured** CryoEM 3.4× GPU speedup at 1.7× lower effective cost; findings cache 10 s→236 ms;
  Docker 50–75% image reduction (efficiency §A/§B).

**CANNOT claim without a head-to-head (do NOT use):**
- "Largest tool set / best on every benchmark / longest workflows" — not validated vs competitors.
- Any **projected** efficiency number (spot %, ADMET-array 20–50×, tiered-model latency) as an
  *achieved* saving — label as modeled design target only (efficiency §C/§E).

**Open-LLM comparison status:** matrix covers Opus-5/GPT-5.6/Gemini-3.1/DeepSeek-V4/Kimi-K3/GLM-5.2;
refresh against newest open models is an open task (strategy §9 "open-LLM comparison status").

---

## 4. Pending marketing tasks (what the new session picks up)

Ordered; none are started unless noted.

1. **Convert partial→proven** (strategy §9 final subsection): the specific head-to-heads needed to
   upgrade CANNOT-CLAIM items — scope each, request the run from engineering, fold the result in.
2. **Refresh the open-LLM comparison** against the newest open models, then update §9 status.
3. **Website copy** (`webpage_design_v2/` static HTML; positioning = "AI drug discovery for
   immune-mediated disorders" per the marketing-scope memory; formal register; no method disclosure).
4. **Manuscript plan execution** — drive Papers A–D per-paper gaps (manuscript-plan §3); fix the two
   C4 internal inconsistencies flagged in efficiency §D ($6.29 vs $2.38; "5.7× approaches 3× limit").
5. **Hero demo production** — the one unfilmed visual is the live SSE remediation panel (hero-A recipe
   §recipe; `frontend/e2e/autoloop-live-proof.e2e.ts`). This needs engineering/E2E, so request it.
6. **Outreach collateral** — collab emails in the required style (CEO intro → clinical white-space →
   their program → simple ask; ~4 short paras; name the disease).

---

## 5. How the marketing session should request evidence from engineering

When a claim needs a number that doesn't yet exist: **do not fabricate, do not re-run heavy jobs from
the marketing session.** Write the precise ask (metric, models, n, acceptance) into
`manuscript-plan.md` §3 or strategy §9 "convert partial→proven", and hand it to the engineering
session. The marketing session's job is to decide *what must be true to claim X* and to phrase the
claim honestly once the number lands — not to produce the number.

---

## Change log
- 2026-10-05 — created at user request ("the marketing should be transferred to another session").
  Inventories all marketing artifacts as of commit on branch
  `cursor/tutorial-live-recording-and-report-editing-4ea7`; no marketing content changed, only indexed.
