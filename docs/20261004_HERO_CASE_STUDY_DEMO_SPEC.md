# BioMate hero end-to-end case-study demos (spec)

**Date:** 2026-10-04
**Purpose:** the single demonstrable asset that lands in a keynote/paper the way FutureHouse's
"found + validated a treatment" does — but on BioMate's honest axis: **a plain-English request becomes a
correct, QC-governed, reproducible, *executed* result with an auditable report.** Seeds the flagship paper's
Tier-3 case study (the load-bearing gap). Two heroes: a *trust* demo (immediately buildable — the live QC
gate already works) and a *reproduction* demo (the closest analog to competitors' "found a finding").

## Hero A — "BioMate caught a cardiotoxic candidate and auto-remediated the screen" (TRUST; buildable now)
**Seed already exists:** live run `d0ff684b` — ADMET on a compound panel; the GOLD hERG gate fired at
0.012 µM on a real AWS Batch run and emitted a remediation (`docs/20261004_AUTOLOOP_LIVE_PROOF.md`).
**The demo (one chat session, recorded):**
1. Scientist: "Screen these N candidates for ADMET / developability." (real marketed drugs + a known
   hERG-liable compound, e.g. terfenadine, mixed in.)
2. BioMate routes → `predict_admet_properties`, runs on Batch, returns per-compound ADMET.
3. **The hero beat:** the QC auto-loop *halts* on the hERG-liable compound (GOLD, Torsade-de-Pointes risk,
   cited) and shows a was→now remediation (tighten logP/MW envelope) — a *scientifically-grounded* catch a
   naive pipeline would have shipped silently.
4. Scientist confirms remediation → re-run → clean panel → **downloadable audit report** (gate table, cited
   thresholds, params, provenance).
**Why it's a hero:** no competitor demonstrates chat-driven QC-gate detection + remediation over an executed
pipeline. It is the "you can trust the result" story, with a real run behind it.
**To finish:** capture the live SSE remediation panel (the one piece not yet captured — run
`autoloop-live-proof.e2e.ts`), and package the recorded walkthrough + the committed JSON artifacts.

## Hero B — "Reproduce a published finding from the accession, in one chat" (REPRODUCTION; the FutureHouse analog)
**The demo:** scientist pastes a paper/GEO accession → BioMate resolves accession → modality → the correct
*validated* workflow (RNA-seq → differentialabundance; the method-selection result makes this defensible) →
runs on Batch → reproduces the paper's headline DE/enrichment result → **flags any QC issue** (e.g. the
over-correction / batch gate) → audit report with the reproduced figure + provenance.
**Why it's a hero:** matches the competitors' "found/validated a finding" register but on *reproducibility +
correctness* — and it exercises the whole stack (accession→route→run→QC→findings→report) end to end.
**Honest grounding:** accession→modality→method is RealBio task #9 and a GEO reproduction has run on Batch
before (memory `project_accession_benchmark`: GSE22055 validated after exec-path fixes). Pick a dataset with
a crisp, checkable published result and confirm the reproduction numerically before filming.
**Risk/guardrail:** only claim "reproduced" if the numbers match the paper within tolerance; otherwise frame
as "ran the published pipeline and reported concordance/discordance honestly."

## Success criteria (both)
- One unbroken chat→report session, recorded (EN + CN per the tutorial pipeline).
- Every claim in the report traces to a committed artifact (run id, S3 outputs, gate JSON) — honesty contract.
- A reader/viewer can re-run it (fixed inputs, pinned workflow) → reproducibility.
- Hero A ships first (seed exists); Hero B is the flagship Tier-3 case study.

## Where it plugs in
Flagship Paper A Tier-3 case study; marketing hero video; the "trust/execution" positioning (below).
Depends on: capture the live remediation SSE (Hero A), one numerically-confirmed reproduction (Hero B).
