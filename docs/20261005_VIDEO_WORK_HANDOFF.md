# Tutorial / Video Workstream — Handoff to the Tutorial-Series Session

**Date:** 2026-10-05 · **From:** session on branch `cursor/tutorial-live-recording-and-report-editing-4ea7`
(worktree `/Users/kky/biomate-review`) · **To:** the session already doing tutorials/video —
branch `cursor/tutorial-series-on-dev-lineage-4ea7` (worktree `/Users/kky/biomate-tutorial-combined-4ea7`).

**Why:** this session is concentrating on the on-prem LLM + marketing + papers. The tutorial/video work
below (authored partly in THIS worktree) should be owned and finished by the tutorial-series session so it
isn't split across two branches. **Nothing here is deleted** — it's committed on this branch; the
tutorial-series session should bring it over (cherry-pick / rebuild) and own it going forward.

> **Heads-up (important):** the richer tutorial set currently lives in THIS worktree
> (`biomate-review`), not in the tutorial-combined worktree. At time of writing, tutorial-combined has only
> `drug-dev-walkthrough.html` + `series/ narration/ review-pilot/`, while this worktree additionally has
> `t0–t4`, `m1`, `m2`, `qpcr`, and the three new DL/ML episodes `d1`, `d2`, `s2`. The owning session must
> reconcile the two (bring the newer episodes onto the tutorial-series lineage).

---

## 1. The authoring contract (do not change — the recorder depends on it)

Each tutorial is an **auto-play HTML page** under `reference/claude_design/tutorials/`:
- `window.__timeline` — the scene schedule the recorder reads.
- `window.__done` — set true when playback completes (recorder stops on it).
- `window.__sceneDurations` — per-scene durations; **scene count MUST equal the narration beat count.**
- Narration lives beside it as `*-narration.md` (and per-language `narration/<name>.en.md` / `.zh.md`).

Pipeline (per memory `project_educational_video_pipeline`): auto-play HTML → **edge-tts** (EN voice Aria,
CN Xiaoxiao, +40% rate) → `scripts/recording/record-walkthrough*.py` (Playwright capture) →
`scripts/recording/mux-walkthrough*.py` (libopenh264 mux audio+video) → EN/CN `.mp4` →
`rclone` to `biomate_drive:…/marketing/…`. **Not the Artifact tool** (publishes publicly — forbidden).

Recording scripts already exist per episode in `scripts/recording/` (e.g. `record-walkthrough-t0.py`,
`mux-walkthrough-t3.py`, generic `record-walkthrough.py` / `mux-walkthrough.py`, `record-tutorial.sh`).

---

## 2. State — what's DONE vs OPEN

### DONE (HTML + narration committed in this worktree; contract verified: timeline/done present, scenes==beats)
| Episode | Files | Note |
|---|---|---|
| T0–T4 getting-started series | `t0..t4-*-walkthrough.html` + `narration/t0..t4.{en,zh}.md` | pre-existing; internal lane names ("Instant"/"Cloud") already scrubbed (commit 44a37a5e7) |
| M1 search & evidence | `m1-*-walkthrough.html` | interactive-launch claim corrected (commit 9527ff13a) |
| M2 RNA-seq DE | `m2-rnaseq-differential-expression-walkthrough.html` | |
| drug-dev, qPCR ddCq | `drug-dev-walkthrough.html`, `qpcr-ddcq-walkthrough.html` | |
| **D1 QSAR classical-ML** | `d1-qsar-classical-ml-{walkthrough.html,narration.md}` | DL/ML track (new) |
| **D2 ADMET deep-learning** | `d2-admet-deep-learning-{walkthrough.html,narration.md}` | hero beat grounded in run `d0ff684b` hERG GOLD halt; reuses live panel assets |
| **S2 PBPK simulation** | `s2-pbpk-simulation-{walkthrough.html,narration.md}` | grounded in `pbpk_simulation` 8-compartment ODE; RealBio within-2-fold honesty anchor |

### OPEN — remaining DL/ML episodes (plan: `docs/20261004_DL_ML_MODULE_TUTORIAL_PLAN.md`)
| Episode | Workflow | Model class |
|---|---|---|
| **D3** Generative lead design | `REINVENT4 Generative Lead Design` | reinforcement learning (de-novo) |
| **D4** Binding free energy | `openfe_rbfe` | physics-based FEP |
| **S1** Non-compartmental PK | `Nca Pknca`, `Dose Response` | statistical PK |
| **S4** Survival analysis | `survival_analysis_km`, `rlassocox` (Cox) | survival statistics |
| **B1** Train a custom model | `run_code` (sklearn/XGBoost/PyTorch) | classification/regression on user CSV |

Each needs HTML + EN+CN narration, same contract. Ground model context with external DBs
(ChEMBL/PubChem for D1–D4). Honesty: predictions are estimates — experimental validation required.

### OPEN — production (render) and capture
- **Render step for every episode:** EN+CN audio (edge-tts) + video (record → mux) → `.mp4` → rclone.
  The HTML/narration are authored; the actual `.mp4` renders are the production backlog.
- **Hero A live-panel capture** (the one unfilmed visual for the flagship demo): run
  `frontend/e2e/autoloop-live-proof.e2e.ts`, screenshot the live SSE remediation panel
  (`[data-testid=autoloop-gate-table]`, `autoloop-remediation-card`), produce EN+CN.
  Spec: `docs/20261004_HERO_A_CASE_STUDY.md` + `docs/20261004_HERO_CASE_STUDY_DEMO_SPEC.md`.

---

## 3. Constraints to honor (standing user rules)
- **No Artifact tool** — render to `.mp4` + rclone to Drive; never publish via Artifact.
- **Natural Chinese** — CN narration must be idiomatic, not literal calques; review subagent output.
- **No internal lane names** in narration/slides (scrub "Instant"/"Cloud" etc. — see commit 44a37a5e7).
- **Formal register**, no salesy taglines.
- **Date-prefixed docs in `docs/`**; commit each episode as it's finished.
- **Report editing** (the other half of this branch's name) is a separate concern tracked in the
  `cursor/report-editing-integration-fixes-153f` worktree (`/Users/kky/biomate-report-editing`) — not
  part of this video handoff.

---

## 4. Suggested pickup order (owning session)
1. Reconcile: bring `t0–t4/m1/m2/qpcr/d1/d2/s2` onto the tutorial-series lineage (they're newer here).
2. Render the 3 DL/ML episodes already authored (D1/D2/S2) → EN+CN `.mp4` → rclone.
3. Author + render the remaining D3/D4/S1/S4/B1.
4. Capture Hero A live panel → EN+CN.

## Resolution (2026-10-05)
Peer session `biomate-review-14` confirmed it is the active video/tutorial session working **in this
worktree** under direct user direction (concept-card alignment fix; internal lane-name scrub on m1/t0
EN+ZH; m1/t0 re-renders; flagship/t3/t4 re-rendered + uploaded to Drive; background job generating real
m2 (DESeq2/GSE52778) + qpcr (ΔΔCq) assets). So the video workstream is **NOT** moved to the
`cursor/tutorial-series-on-dev-lineage-4ea7` lineage — it stays owned by session 14 here. This session
(LLM + marketing + papers) does not touch video artifacts or `scripts/recording/`. Transfer closed.

## Change log
- 2026-10-05 — created to transfer the tutorial/video workstream off the LLM/marketing session.
  Inventory only; no video content changed.
- 2026-10-05 — resolution recorded: session 14 owns video in-worktree (no lineage move). Peers 49
  (immune-FM) and 76 (backend workflows) declined; the handoff is closed.
- 2026-10-05 (session 14) — **M2 (RNA-seq DE) and qPCR ΔΔCq rendered EN+ZH and uploaded.** Real
  BioMate Batch-run outputs (DESeq2 on airway/GSE52778; NormqPCR ΔΔCq) wired into the walkthrough
  HTML and rendered via the edge-tts → record → mux pipeline; 4 mp4s on
  `biomate_drive:…/marketing/data_centroid_tutorial/videos/`. Details + root-cause of the prior
  asset-blocking saga: `docs/20261005_REALBIO_CAPABILITY_DEMO_SERIES.md`.
- 2026-10-05 (session 14) — **D1 (QSAR classical-ML), D2 (ADMET deep-learning), S2 (PBPK) rendered
  EN+ZH and uploaded** (6 mp4s on Drive). EN narration normalized to `## Step` format, ZH narration
  translated (idiomatic, reviewed), per-scene slots fitted to the narration (the d1/d2/s2 narrations
  badly overran their authored `data-seconds` — `scripts/recording/fit-scene-slots.py` sizes each
  scene to max(EN,ZH)+pad before recording). Ports 7790/7791/7792.
- 2026-10-05 (session 14) — **M3 (accession → dataset → workflow) rendered EN+ZH and uploaded.** NEW episode
  demonstrating BioMate's accession intelligence on real GEO/SRA IDs (resolve_accession ID→fetcher;
  context-aware routing of the same GEO ID → microarray-DE / DESeq2-chain / GSEA with auto-filled
  params). Grounded capability list + honest gaps: `docs/20261005_ACCESSION_TO_WORKFLOW_CAPABILITY.md`.
  Remaining render backlog: D3/D4/S1/S4/B1 (not authored).
