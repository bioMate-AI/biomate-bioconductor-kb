# QC + Auto-Loop Coverage — Team Brief

**Date:** 2026-06-10
**Audience:** product, regulatory, QA, platform engineering
**Companion technical doc:** `docs/20260609_QC_COVERAGE_EXPANSION.md`

## TL;DR

Ten BioMate drug-development workflows now emit gate-anchored QC
metrics that the platform consumes live during every run. Each gate
is tagged with the literature citation it is anchored to, and the
*honesty* of that anchoring is graded GOLD / SILVER / BRONZE so
downstream consumers (CRO partners, regulatory readers, internal QA)
know what they can rely on.

Two more workflows are code-complete and waiting on external unblocks
(an aizynthfinder container ship and a GPU budget for Boltz).

This brief is for anyone who needs to know what's covered, what
graded evidence "means," and how to add a workflow without re-doing
the audit work.

## What's covered

10 workflows verified end-to-end on dev. Each one's gate fires a
real `[QC-S3] Reading report …` + `[QC Gate] PASSED/FAILED …` event
during a Batch run, observable in `gunicorn.log`.

| Workflow | Question the gate answers | Provenance |
|---|---|---|
| HTS plate QC | Did the assay pass Zhang's "excellent" plate quality bar? | **GOLD** Zhang 1999 |
| Allometric scaling | Is the inter-species PK fit good enough for FIH dose selection? | SILVER (cutoff is convention, not in FDA guidance verbatim) |
| ICH S5 reproductive tox | Is the safety margin against WOCBP exposure ≥ 10× Cmax? | **GOLD** ICH S5R3 §3.1 |
| ICH S7A safety pharm | Is the hERG cardiac liability margin ≥ 10× free Cmax? | **GOLD** ICH S7B / Redfern 2003 |
| Pocket detection | Is the predicted binding pocket actually druggable? | **GOLD** Le Guilloux 2009 (fpocket) |
| p0 PKPD semaglutide | Does the predicted Δweight at week 30 match SUSTAIN-1? | **GOLD** Overgaard 2019 |
| BOIN clinical trial | Does the recommended MTD respect the toxicity target φ? | **GOLD** Liu & Yuan 2015 |
| LNP formulation | Is the predicted particle size in the CLT range? | SILVER (in vitro proxy, not measured DLS) |
| Antibody developability | Does the total CDR length sit in the clinical-stage band? | **GOLD** Raybould 2019 Table 1 |
| siRNA off-target | Does the duplex have the thermodynamic asymmetry that loads the guide strand? | **GOLD** Khvorova 2003 |

Two more (aizynthfinder retrosynthesis + Boltz-2 structure prediction)
are wired identically and will go live as soon as their external
blockers are cleared.

## How a regulatory reviewer should read these grades

- **GOLD**: the paper cited states the numeric cutoff verbatim, or
  trivially derives it. Pointing the reviewer at the paper answers
  "where does that number come from?" with no further explanation.
- **SILVER**: the *metric* is GOLD-anchored (the paper recommends
  using it) but the specific cutoff is a community convention or a
  BioMate operational choice. The label always names which side is
  which.
- **BRONZE**: explicitly labelled "no peer-reviewed anchor for the
  cutoff." Used very sparingly; today there are only 5 such entries
  in the whole evidence file and each `paper_supports` field says
  outright what the paper *does* and *does not* establish.

GOLD/SILVER/BRONZE counts after the 06-07 audit pass:
**22 GOLD / 30 SILVER / 5 BRONZE** out of 57 graded entries.

We deliberately **demoted four** previously-GOLD entries in this work
(Kazius 2005 Ames cutoff, FDA 2005 allometric R², Rosenthal & Henderson
cryo-EM resolution tiers ×2) because spot-reading the papers showed the
specific cutoff wasn't actually in the cited text. The split-grade
template now in use ("metric is GOLD-anchored to paper Y; the cutoff
value is operational/SILVER") is the model for any new entry.

## What lives where

- **Gate definitions:** `backend/lib/galaxy/ai/retrievers/qc_gate_reader.py`
  Each gate is a small function: `(metrics dict) → (name, value, threshold, passed, grade, message)`.
- **Evidence + citations:** `backend/config/qc_evidence.yaml`
  Per-domain, per-gate. Each entry has `paper_ref` + `paper_doi` + a
  `provenance:` GOLD/SILVER/BRONZE tag + a `paper_supports:` field that
  states *exactly* what the cited paper does and does not say.
- **Process-to-domain wiring:** `backend/lib/galaxy/ai/retrievers/qc_gate_emit.py`
  `_PROCESS_KEYWORDS` maps Nextflow process-name substrings to gate
  domain. If the workflow's process name doesn't contain one of the
  keywords for its domain, no gate fires.
- **S3 fallback table:** `backend/lib/galaxy/jobs/qc_trace_monitor.py`
  `_S3_REPORT_PATHS` tells the monitor which processes publish
  `qc_metrics.json` to S3 and where to look. Required because Batch
  runs don't keep a local work dir for the Galaxy backend to read.
- **Live evidence:** `[QC-S3] Reading report for <PROCESS>` lines in
  `gunicorn.log` on each Galaxy worker.

## Recipe for adding a new workflow (5 steps, end-to-end)

1. **Pick the workflow + identify the process** that computes the
   gate metric. (Not the workflow root — the specific *process*.)
2. **In the workflow's `main.nf`,** emit `qc_metrics.json` from that
   process with the canonical keys the gate reader expects (e.g.
   `z_prime`, `safety_margin_x`, `herg_safety_margin_x`,
   `druggability_score`, `r_squared`, `num_solved_routes`,
   `week30_weight_change_kg`). Names are case-sensitive — the most
   common bug in this work was emitting `hERG_safety_margin_x`
   where the reader expects `herg_safety_margin_x`.
3. **Declare the new output** in the process's `output:` block. If
   you're adding a 2nd path to a process whose downstream caller
   uses `.out[0]` / `.out[1]` positionally, switch the caller to
   `.out.<name>` named-access to avoid the ich_s5 footgun (a 2 → 3
   output shift broke its AGGREGATE step until pinned).
4. **Register in `_S3_REPORT_PATHS`** (`qc_trace_monitor.py`), with
   the same wildcard step prefix the others use:
   ```python
   "PROCESS_NAME": ("*", "qc_metrics.json"),  # gate (provenance, citation)
   ```
5. **Verify** with a Playwright test that POSTs to
   `/api/workflows/execute`. The 10 existing tests
   (`frontend/e2e/*-qc-coverage.e2e.ts`) all share the same shape;
   copy one and swap the names. The canonical user fixture is set
   in CLAUDE.md — do NOT invent a new test email.

## Infrastructure fixes in this stretch (already merged)

Two QC-monitor bugs surfaced + got fixed during the coverage push.
Both benefit every workflow, not just the new ones:

- **`0e69e9577` — header-aware trace column lookup.** The monitor's
  poll loop used to assume Nextflow's default trace columns; any
  workflow that customizes `trace.fields` (omitting the `hash`
  column, for instance) silently broke. Now the loop reads the
  header line and maps column-names → indices.
- **`43603bf6c` — S3-first when `s3_outdir` is set.** The monitor
  used to gate the S3 fallback on `not work_dir.is_dir()`, which
  silently skipped reading the published report whenever the local
  work dir happened to exist (which it always does on Batch runs).
  Symptom was `[QC Gate] No QC metrics calculated` right after a
  clean COMPLETED event. Fix: read S3 first whenever `s3_outdir`
  is set; fall through to local parsers only if S3 returned nothing.

Two Groovy/Python heredoc-escape bugs in the siRNA workflow itself
(`9be578fe5b`, `546166a93d`) were also pre-existing and only surfaced
because this work caused that workflow to execute live on dev for the
first time. Worth flagging because **any** Nextflow process that uses
backslash-escaped Python (e.g. `'2\'-OMe'`, `'\n'.join(...)`) will
hit the same bug, and there are likely more lurking in less-exercised
workflows.

## Known limitations

- The QC monitor's poll cadence (5s) can miss process completion
  events on workflows that finish in <2 min. Symptom: trace file
  shows COMPLETED tasks but `[QC Gate]` events never fire. Workaround
  is to ensure the workflow runs at least one Batch step long enough
  for a poll cycle to land; long-term fix needs a workflow-completion
  hook.
- `tap_psh_score`, `camsol_intrinsic_score`, IVIVE fold-error
  (predicted-vs-observed), OpenFE cycle closure, and the cancer-biology
  VAF/depth gates are all *defined* in the evidence + gate-reader
  files, but the corresponding workflows don't compute those exact
  metrics yet. Skipping them deliberately — emitting an approximation
  under a GOLD-anchored key would be misleading.
- LNP `pdi` is not computed by the current workflow; gate skips when
  metric is `None`, which is correct behaviour, but means we lose half
  the LNP gate evaluation until somebody adds the DLS measurement.

## Open follow-ups (intentionally not in this scope)

1. Aizynthfinder container `biomate/biomni-drug-discovery-nf:x86` needs
   an expansion policy configured. QC code is ready and will fire on
   the first successful run.
2. Boltz / ChAI1 / AlphaFold GPU runs are expensive enough that we
   deferred live verification. Process-name match + emit code are in
   place; one GPU sprint will close all three.
3. Galaxy's `chat_narrator` mis-reports `outcome: failed` for many
   workflows that Nextflow shows as Succeeded (e.g. pocket, ich_s7a,
   LNP). Not in QC scope; tracked separately. Doesn't affect the gate.
4. Provenance audit pass 3: spot-check the remaining 22 GOLD entries
   the same way pass 2 did the original 26. Pass 2 demoted 4 of 26
   (~15%) so further work is warranted.

## For product + regulatory: what you can say externally

- "BioMate's drug-development workflows now run live QC gates anchored
  to ten distinct peer-reviewed publications and regulatory guidances,
  with honest provenance grading on every gate."
- "Every cutoff in the system is labelled either GOLD (paper states
  it verbatim), SILVER (community convention), or BRONZE (operational
  with no peer-reviewed anchor); BRONZE entries are explicitly
  labelled as such — we do not present operational heuristics as
  literature-derived."
- "When a gate fires during a run, the platform records the citation
  alongside the value — the same record is what a CRO QA pack
  exports."

## How this fits into the wider system

This work touches three subsystems that other teams will recognise:

- **Auto-loop:** the same `qc_metrics.json` consumed by the monitor
  flows into the auto-loop event stream. Workflows can use the
  evaluated gate state to trigger re-runs with adjusted parameters
  (already wired for HTS / pocket / ICH-S5; the other 7 will plug in
  through the same SSE event path).
- **CRO compliance exports:** the `qc_evidence.yaml` rows are the
  source of the tooltip text rendered next to each gate result in
  CRO compliance packs. The 4 GOLD demotions performed here flow
  straight through.
- **Memory + retrieval (LongMemEval):** the platform's memory layer
  already stores per-invocation gate outcomes; nothing here changes
  that contract, but it does mean memory queries against historical
  runs will now resolve more provenance-tagged metrics.

---

For the full commit-by-commit detail + the precise audit demotion
rationale, see `docs/20260609_QC_COVERAGE_EXPANSION.md` and
`docs/20260607_QC_EVIDENCE_AUDIT_PASS_2.md`.
