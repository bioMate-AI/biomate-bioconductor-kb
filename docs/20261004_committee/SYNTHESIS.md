# Tutorial-video committee audit — SYNTHESIS & action plan (2026-10-04)

Seven independent reviewers across four LLMs (Opus, Sonnet, Fable, Haiku) audited the
6 produced videos (drug-dev flagship + T0–T4, EN+ZH) and the plan for the rest, grounded
in the priority Excel (`docs/20260715_WORKFLOW_USECASE_PRIORITIZATION.xlsx`), the
data-centric v2 spec (`reference/claude_design/data_centroid_design_v2/spec`, modules
00–14), and the recent Sept/Oct docs. Member reports: `docs/20261004_committee/*.md`.

**Headline:** the earlier self-audit's "clean" verdict was wrong. The set is honest in
*intent* and mechanically clean (scene↔narration 1:1, EN/ZH parity, no broken assets),
but it has **real honesty over-claims**, **one internal contradiction**, **UX composition
defects** (incl. two my own recent fix missed/created), and covers only **~9% of the
mandated scope** — with video budget inverted against the GTM priorities.

---

## P0 — Honesty / accuracy (blockers; most require re-render)

Flagged independently by the honesty (Sonnet) and drug-discovery (Opus) reviewers, several
echoed by marketing and UX.

- **H1 [BLOCKER] Flagship over-claims REINVENT4.** drug-dev Stage 2 headlines "REINVENT4
  Generative Lead Design (4 learned modes)," but the code marks REINVENT4 as an unrun
  SWAP-POINT and **BRICS is what actually runs** — contradicting T1's honest "deterministic
  BRICS, not a trained model." Three incompatible generator stories exist (T1 / T11 /
  Guangzhou deck). Fix: flagship must say the live engine is BRICS; REINVENT4 = built, not
  yet run (gap). → re-render drug-dev EN+ZH.
- **H2 hERG panel over-precise + omits DILI.** The 10 mM values are the estimator's ceiling,
  not measurements, yet narrated "essentially non-cardiotoxic"; "caffeine = worst at 432 µM"
  reads a heuristic artifact as a cardiac signal. The *same run's* `qc_metrics.json` reports
  **DILI "high" (0.875, fails 0.5)** — never mentioned. Fix: lead with the native blocker
  score, demote the heuristic IC50, drop "caffeine worst," add the DILI result. → re-render.
- **H3 [BLOCKER] ADMET completed-state contradiction + T3 framing.** Flagship shows
  *populated* findings (hERG 0.003 / DILI 0.855 / oral 0.873) for aspirin/caffeine/ibuprofen;
  **T3 shows findings WITHHELD for the same three molecules** and frames it as a designed
  honesty feature — but it was a (since-repaired) dev storage fault. Fix: **re-record T3 with
  a completed run that has real populated findings** (resolves both the contradiction and the
  misframing). → re-capture + re-render T3.
- **H4 Stale caveat.** drug-dev says the QC gate firing is "unproven on dev," but
  `docs/20261004_AUTOLOOP_LIVE_PROOF.md` shows it firing live (run d0ff684b; remediation is
  *advisory*, not autonomous). Update wording. → re-render drug-dev.
- **H5 Docking/RBFE/MD + PBPK over-claim "runs on cloud/GPU."** Written T11 manual says
  "demonstration pending"; OpenFE FEP fabricated a ΔΔG until 2026-09-22. Downgrade to "coded,
  not yet demonstrated" (gap). → re-render drug-dev.
- **H6 T2 "hosted, use directly" vs "may be a stub"** internal tension; all 5 registry models
  are unevaluated / 0 uses. Reconcile wording. → re-render T2.
- **H7 (P2) Softening:** "more accurate every round" / "3–4 rounds beat once" unsupported;
  T3 "open in Jupyter" needs the dev-503 + no-auto-load caveat; T2 privacy statement
  unverified; label the T4 demo CSV; T0 "tested/validated" needs a qualifier.
- Note: **no EN/ZH honesty mismatch** — but every over-claim is repeated in ZH, so fix both.

## P1 — UX / composition (re-render affected)

From the UX designer (Opus); U1/U2 include defects in my own recent change.

- **U1 T0 & T3 still use the 0.6 s cross-dissolve** → text-on-text double-exposure at every
  scene change (confirmed: their CSS has `transition:opacity .6s`; T1/flagship have
  `transition:none` + 0.18 s active fade). Trivial fix. → re-render T0, T3.
- **U2 Concept scenes unbalanced** — the recent compaction (`card.big{flex:initial}` +
  `concept{justify-content:center}`) over-corrected: title top, ~200 px dead band, short card
  floating low, empty bottom. Rebalance (restore `flex:1`, or adopt the flagship's
  two-column SVG-diagram concept layout). → re-render T0/T1/T2/T4.
- **U3** T3 live layout (shotcol) differs from the other four (centered focal crop) — normalize.
- **U4** Re-capture T0 cold-start to include the composer it narrates; re-capture T1 form
  un-sliced at the top.
- **U5** Chrome pass: Slide-vs-Stage counter label, type-scale drift, drop T0's
  `object-fit:cover` default.

## P1 — Consistency (coverage-QA, Opus)

- **C1** Honesty-badge scheme inconsistent (only drug-dev uses the 3-way verdict; T0–T4 are
  ad-hoc; T1 adds a 4th "roadmap"). Standardize one badge component across all.
- **C2** Canonical slugs: video `t3-run-and-report`→ catalog `t3-running-a-workflow-…`;
  `drug-dev`→`t11-drug-development-end-to-end`.
- **C3** Reconcile the catalog's **T0 "BLOCKED"** note ("New Chat doesn't mount the cold-start
  dashboard") — our fix made it render live (captured), so the note is stale; re-verify, and
  U4 re-capture addresses the composer gap.

## P1 — Coverage (the strategic gap) — film only what runs today

Bioinformatics, coverage-QA, marketing, and UX all converge: **every live demo is ADMET.**
BioMate's largest domains and 14/15 P1 workflows have **zero** video; the series' own
`catalog.json` plans ~70 episodes (×2 langs). Budget is inverted vs the priority Excel.

Recommended production order (P1 priority; verify each runs live before filming):
1. **Search & Evidence** (v2 module 01) — the "search" pillar; no video. (M1 route currently BLOCKED — reconcile first.)
2. **Large-DB search** — Foldseek / MMseqs2 / FPSim2.
3. **RNA-seq + count-matrix DE** from GEO (e.g. DESeq2 on GSE52778) — the P1 freemium front door.
4. **Cryo-EM SPA** — analysis + instrument paired.
5. **WGS / variant** — hold cohorts until the fetchngs S3 bug is fixed.
6. **Instrument-analysis** videos — qPCR ΔΔCt, flow gating, LC-MS proteomics (film what runs).
7. **Function modules** — full step view (08), report editing (12), output previews by type (14)
   (the T5 "visualization + viewers" video).
Reuse drug-dev clips for the focused drug-discovery episodes (avoid re-shooting).

## Accuracy reconciliations before filming instruments (bioinformatics, Sonnet)
- WGS status conflict: `basespace-sequencing.md` calls WGS "validated" but 0921 says dispatch
  blocked by the fetchngs S3 bug.
- qPCR tutorial §6 stale (0921 shows it now runs end-to-end).
- LC-MS tutorial defaults DIA to **DIA-NN**, which the project's license memory says is NOT
  license-clean (clean = OpenSWATH+PyProphet / Comet / Sage / mokapot).

## Strategic (marketing, Fable)
- **Reclassify:** these are honest *onboarding*, not a GTM asset. For buyer-facing use, scrub
  tool-stack disclosure (REINVENT4/GNN/BRICS/AWS Batch) and "on dev" references, and re-key the
  catalog by **segment/priority**. Show the moat with a **real retrospective closed-loop round**,
  not an empty Rounds view + fictional anecdote.

---

## Recommended sequencing
1. **Honesty P0 (H1–H6)** — correct wording + re-record T3 with a real-findings run; re-render
   the affected videos (drug-dev, T2, T3). Highest priority; they are shipped and wrong.
2. **UX P1 (U1 transition; U2 concept rebalance; U4 re-captures)** — fold into the same re-render pass.
3. **Consistency (C1 badge, C2 slugs, C3 T0 re-verify)**.
4. **Coverage build-out** in the priority order above, filming only verified-live workflows,
   after the instrument-accuracy reconciliations.

Open decision for the requester: scope/sequence of the coverage build-out (the full set is a
~70-episode program), and the onboarding-vs-GTM framing (affects whether tool/dev references
are scrubbed).
