# BioMate Test Harness & QC Gate — User Stories
**Date**: 2026-02-23
**Audience**: Product, engineering, and UX teams

---

## Background: What the System Does

When a researcher asks BioMate to run a bioinformatics workflow, the system can:

1. **Run a pilot first** — execute a small representative subset of the data (e.g. 5 micrographs out of 500, or 10% of FASTQ reads) to validate that parameters are sane before committing to the full run.
2. **Monitor every step** — watch the actual output files each tool writes (STAR logs, CTFFIND4 files, FASTP JSONs, etc.) and compute quality metrics in real time.
3. **Gate on failures** — when a process produces output that falls below quality thresholds, pause and surface an interactive decision point to the researcher.
4. **Suggest better parameters** — use domain-specific heuristics to propose concrete parameter changes with confidence scores and explanations.
5. **Apply and retry** — let the researcher accept (all or some) suggestions, then restart the affected portion of the run with the new parameters.

This is the difference between a workflow runner and an intelligent research assistant: the system knows when something is wrong before the researcher wastes 8 hours on a bad run.

---

## User Personas

| Persona | Background | Goal | Risk if confused |
|---|---|---|---|
| **Nina (Novice)** | Wet-lab biologist, new to NGS | Get results without worrying about parameters | Ignores QC banner; runs full job on bad parameters; gets garbage output |
| **Alex (Analyst)** | Bioinformatician, knows tools | Get good results efficiently; trust but verify | Dismisses pilot without understanding cost; or over-trusts suggestions |
| **Priya (Power user)** | Methods developer | Full control, no hand-holding | Pilot auto-trigger feels patronising; wants to set own thresholds |
| **Frank (Core facility)** | Runs 20 jobs a week | Throughput; wants automation for routine jobs | Needs to understand which jobs need human review vs. auto-proceed |
| **Kenji (Cryo-EM specialist)** | Knows CryoSPARC deeply | Interpret CTF and motion metrics correctly; trust QC | Confuses BioMate's motion QC with CryoSPARC's internal quality scores |

---

## Epic 1: Understanding the Pilot Run

### US-1.1 — First-time encounter with pilot banner
**As Nina (novice),** I see a yellow banner saying "Running 5-micrograph pilot first" appear before my workflow starts, and I don't know what it means or whether to wait.

**I want**: a clear, jargon-free explanation of why the pilot is happening and what I should do next.

**So that**: I don't click "Skip" out of confusion and waste compute on a bad full run.

**Acceptance Criteria:**

```
GIVEN I submitted a cryo-EM SPA workflow with 450 micrographs
AND the AI determined a pilot is beneficial (large dataset, first use of this workflow)
WHEN the workflow artifact renders
THEN I see a banner that reads:
     "Running a 5-micrograph pilot test first (~2 min).
      This checks whether your parameters will work before committing
      to the full 450-micrograph run. You'll see quality results
      before anything processes at scale."
AND the banner shows the reason(s) the pilot was suggested:
     e.g. "• Large dataset (450 micrographs) — catching issues early saves ~6 hours"
AND there is a clearly-labelled "Skip pilot, run full dataset now" link
     (small, not a primary button — so the default action is to wait)
AND clicking anywhere else does NOT accidentally dismiss the pilot
```

**Anti-pattern to avoid:**
- Don't show just "Pilot run suggested" with no explanation. Nina doesn't know what a pilot run is.
- Don't make "Skip" look equally prominent as "Wait" — the default should be obvious.

---

### US-1.2 — Understanding what "Phase 0" means in the step list
**As Alex (analyst),** I see my workflow listed as "Phase 0 (Pilot)" followed by "Phase 1 (Full Run)" in the step list, and I'm not sure if Phase 1 is already running or waiting.

**I want**: a clear visual state for each phase so I know what's active, pending, and complete.

**So that**: I don't interrupt a running phase or wait unnecessarily.

**Acceptance Criteria:**

```
GIVEN the pilot is currently executing
WHEN I look at the workflow step list
THEN Phase 0 steps show a spinning progress indicator with "Running"
AND Phase 1 steps show a grey "Waiting" state with a lock icon
     and the tooltip "Full run starts after pilot QC passes"
AND the progress bar at the top shows pilot progress (e.g. "Phase 0: 3/5 micrographs")
WHEN Phase 0 completes without QC failures
THEN Phase 0 steps show green checkmarks
AND Phase 1 transitions from "Waiting" to "Running" automatically
AND a brief toast notification appears: "Pilot passed — starting full run"
```

---

### US-1.3 — Pilot completes with no issues
**As Nina,** the pilot finished and nothing went wrong. I don't want to have to click anything — I just want the full run to start.

**I want**: the full run to start automatically when pilot QC passes.

**So that**: I don't need to babysit the workflow.

**Acceptance Criteria:**

```
GIVEN all pilot QC metrics are within thresholds
WHEN the last pilot process completes
THEN the full run begins automatically within 5 seconds
AND a subtle status message appears:
     "Pilot QC passed (motion drift: 12 Å, CTF fit: 0.85, 342 particles/mic).
      Starting full run with original parameters."
AND no modal or confirmation dialog interrupts the user
AND the pilot banner changes to a collapsed success state, not dismissed entirely
     (so the user can still see that a pilot was run and what it found)
```

**Key insight:** Silent success is the right UX. The researcher should only be interrupted when something needs their decision.

---

## Epic 2: The QC Gate Modal

### US-2.1 — QC gate fires mid-run: basic case
**As Nina,** I'm waiting for my RNA-seq workflow to finish. Suddenly a modal pops up saying "Quality Control Gate Triggered". I don't know if I should be alarmed or if this is normal.

**I want**: to understand at a glance what went wrong, how bad it is, and what my options are.

**So that**: I can make a decision without needing to understand the technical details of STAR alignment parameters.

**Acceptance Criteria:**

```
GIVEN STAR_ALIGN completed with alignment_rate = 45%
AND the threshold is 60%
WHEN the QC gate modal opens
THEN the title is human-readable:
     "Quality issue detected in Read Alignment (STAR)"
     NOT "qc_gate_triggered for STAR_ALIGN"
AND the failed metric is shown as:
     [RED BADGE] Alignment Rate: 45%   Threshold: ≥ 60%
     "Only 45% of your reads mapped to the genome. This is unusually low
      and may indicate a species mismatch, incorrect strandedness setting,
      or heavily contaminated input."
AND the severity is communicated:
     "Proceeding with 45% alignment may produce unreliable expression counts."
AND there are exactly 3 action buttons:
     [RETRY WITH SUGGESTIONS]  — primary, green
     [PROCEED ANYWAY]          — secondary, grey
     [CANCEL WORKFLOW]         — tertiary, outline/red
AND each button has a one-line consequence description below it:
     Retry: "Applies 2 parameter adjustments and re-runs alignment (~8 min)"
     Proceed: "Continues with current low-quality alignment — results may be inaccurate"
     Cancel: "Stops the workflow — you can adjust parameters and restart"
```

---

### US-2.2 — Reading the parameter suggestion card
**As Alex (analyst),** I see a suggestion to change `max_mismatches` from `2` to `4`. I want to understand whether this is safe to accept before I click Retry.

**I want**: enough context in the suggestion card to make an informed decision in under 30 seconds.

**So that**: I don't blindly apply all suggestions or blindly reject them.

**Acceptance Criteria:**

```
GIVEN a suggestion:
  parameter: max_mismatches
  currentValue: 2
  suggestedValue: 4
  reason: "Low alignment rate (45%) often indicates reads with more SNPs or
           splice variants than the default 2-mismatch tolerance allows.
           Increasing to 4 typically recovers 10–20% additional reads."
  confidence: 0.82
WHEN the suggestion card renders
THEN I see:
  - Parameter name in human-readable form: "Maximum Mismatches Allowed"
    (NOT the raw parameter key "max_mismatches")
  - Confidence badge: "82% confidence" with green color for > 80%
  - Current → Suggested: 2 → 4  (shown as code blocks, not plain text)
  - Full reason text, not truncated
  - A checkbox that is PRE-CHECKED (opt-out, not opt-in)
    because high-confidence suggestions should be accepted by default
AND if I hover over the confidence badge I see a tooltip:
     "Confidence is based on how often this adjustment resolves
      this specific failure pattern in similar workflows."
AND if confidence < 0.7, the checkbox is unchecked by default
     and there is a yellow note: "Lower confidence — review before applying"
```

---

### US-2.3 — Multiple failures in one gate event
**As Alex,** the QC modal shows 3 failures at once after FASTP trimming: low reads surviving, low Q30 rate, AND low adapter removal rate. I'm not sure if these are related or independent problems.

**I want**: the modal to help me understand whether the failures have a common root cause.

**So that**: I don't apply conflicting suggestions that make things worse.

**Acceptance Criteria:**

```
GIVEN 3 simultaneous failures from FASTP:
  - reads_surviving_pct = 52%   (threshold 70%)
  - q30_rate = 60%              (threshold 75%)
  - adapter_content_pct = 35%  (threshold < 20%)
WHEN the modal renders
THEN failures are grouped under a single process name "Read Trimming (FASTP)"
     NOT shown as 3 separate modals
AND there is an "Overall assessment" line before the individual failures:
     "3 quality issues detected — likely caused by poor-quality input or
      incorrect adapter specification. Addressing adapter trimming may
      resolve the other two issues."
AND the suggestions are ordered by expected impact (highest first)
AND if two suggestions would conflict, a warning note appears:
     "Note: applying both 'adapter sequence' and 'quality cutoff' changes
      at once may over-correct — consider applying one at a time."
```

---

### US-2.4 — Partial suggestion acceptance
**As Priya (power user),** the QC gate suggests 3 parameter changes but I already know one of them is wrong for my experiment. I want to accept only 2 of the 3.

**I want**: to individually select/deselect suggestions and see exactly what will be applied before I click Retry.

**So that**: I maintain control while still benefiting from the automated suggestions.

**Acceptance Criteria:**

```
GIVEN 3 suggestions: quality_cutoff, twopass_mode, max_mismatches
WHEN I uncheck "max_mismatches"
THEN the Retry button text updates to:
     "Retry with 2 adjustments"  (was "Retry with 3 adjustments")
AND a summary line appears below the suggestion list:
     "Will apply: quality_cutoff (20→25), twopass_mode (false→true)"
WHEN I click Retry
THEN ONLY quality_cutoff and twopass_mode are changed
AND max_mismatches remains at its original value
AND the workflow re-runs STAR_ALIGN only (not the steps that already passed)
```

---

### US-2.5 — "Proceed Anyway" with understanding of consequences
**As Priya,** I have domain knowledge that my sample has known SNP-rich regions and a 45% alignment rate is expected. I want to proceed without changing anything.

**I want**: to proceed despite QC failures without feeling blocked, but with a clear record that I made this choice.

**So that**: I can move forward with my science while BioMate keeps an audit trail.

**Acceptance Criteria:**

```
GIVEN alignment_rate = 45%  (threshold 60%)
WHEN I click "Proceed Anyway"
THEN a brief confirmation appears:
     "You're proceeding with alignment_rate = 45% (below threshold 60%).
      This is recorded in the workflow audit log."
     with a single "Confirm Proceed" button
AND after confirming, the workflow continues from the next step
AND in the workflow output summary, a yellow warning badge appears:
     "QC overridden at STAR_ALIGN — alignment_rate 45%"
AND the override is included in the downloadable Methods report
```

---

### US-2.6 — Cancelling the workflow at a QC gate
**As Nina,** the QC modal shows a metric I don't understand and I don't want to guess. I want to cancel the workflow, look up what "CTF fit quality" means, and come back.

**I want**: to cancel cleanly and return to a state where I can adjust parameters and restart.

**So that**: I don't waste compute on a run I know will fail.

**Acceptance Criteria:**

```
GIVEN I click "Cancel Workflow" in the QC modal
THEN a confirmation asks:
     "Cancel the workflow?
      Completed steps will be saved. You can adjust parameters and re-run."
WHEN I confirm
THEN all running processes are stopped
AND the workflow card returns to "Ready to run" state with parameters editable
AND the step list shows which steps completed (checkmarks) and which were cancelled (grey)
AND the previous QC failure is shown as a collapsed note on the relevant step:
     "Last run: CTF fit quality = 0.04 (threshold 0.1) — cancelled"
     so I know what to investigate
```

---

## Epic 3: Domain-Specific QC Guidance

### US-3.1 — Cryo-EM motion correction: what does "drift" mean?
**As Kenji (cryo-EM specialist),** I see a QC gate for MOTION_CORRECTION with `total_drift_angstrom = 78 Å`. I know this can be caused by either beam-induced motion or stage drift, and the fix is different for each.

**I want**: the QC message to reflect cryo-EM domain knowledge, not generic bioinformatics advice.

**So that**: I trust the suggestion and apply it with confidence.

**Acceptance Criteria:**

```
GIVEN total_drift_angstrom = 78 Å  (threshold > 50 Å)
AND current parameters: dose_weighting=false, patch_size=3
WHEN the QC gate fires
THEN the failure description reads:
     "Total drift of 78 Å exceeds the recommended 50 Å limit.
      High beam-induced motion reduces contrast transfer and blurs high-
      resolution features. Enabling dose weighting will down-weight
      heavily-exposed frames that contribute most to motion artifacts."
NOT: "total_drift_angstrom is too high"
AND the suggestions include:
  1. dose_weighting: false → true   (confidence: 85%)
     Reason: "Dose weighting compensates for radiation damage accumulation.
              Effective for drift values between 50–150 Å."
  2. patch_size: 3 → 5              (confidence: 72%)
     Reason: "Larger patch size improves local motion correction for
              stage drift patterns, at the cost of slightly longer compute."
AND there is a "Learn more" link that opens the MotionCor2 parameter docs
```

---

### US-3.2 — Cryo-EM CTF estimation: defocus out of range
**As Kenji,** the CTF QC gate fires with a confusing message about defocus being "outside valid range". I have no idea whether this means my defocus is too far from focus or too close.

**I want**: to see the actual defocus value and understand which direction it's out of range.

**So that**: I can adjust the defocus search range in the right direction.

**Acceptance Criteria:**

```
GIVEN defocus_u = 950 Å  (valid range: 1000–100000 Å)
WHEN the QC gate fires
THEN the failure message reads:
     "Estimated defocus of 950 Å is below the minimum valid range (1,000 Å).
      This suggests your micrographs may be nearly in-focus.
      Consider collecting at a target defocus of 1.0–3.0 μm for optimal
      phase contrast, or widen the CTF search range if your collection
      target is intentionally close to focus."
AND the suggestion reads:
     defocus_search_min: 1000 → 500 Å
     "Widens the search range downward to catch near-focus micrographs."
AND if the defocus is above the valid range (> 100,000 Å), the message
     instead reads: "Estimated defocus of 125,000 Å is unusually far from focus —
                     possible stage error or wrong microscope calibration."
```

---

### US-3.3 — RNA-seq alignment: species mismatch hint
**As Alex,** my RNA-seq alignment rate is 12% — much lower than the usual case. Something is badly wrong. I need to know if this is a parameter issue or a data quality issue.

**I want**: the QC gate to distinguish between "probably fixable by adjusting parameters" vs. "check your data first".

**So that**: I don't waste a retry on a parameter change when the real problem is that I uploaded mouse reads to be aligned to the human genome.

**Acceptance Criteria:**

```
GIVEN alignment_rate = 12%  (threshold 60%)
WHEN the QC gate fires
THEN the severity indicator shows "Critical" (not just "Warning")
AND the description reads:
     "12% alignment is critically low. Typical failed-but-fixable runs
      align at 30–55%. Values below 20% often indicate:
        • Genome/species mismatch (aligned wrong organism's genome)
        • Heavily contaminated sample (rRNA, adapter dimer, etc.)
        • Wrong file format or corrupt FASTQ
      We suggest verifying your input data before applying parameter changes."
AND the "Retry with Suggestions" button is replaced by:
     [CHECK INPUT DATA FIRST]  — primary
     [Retry with suggestions anyway]  — secondary, less prominent
AND the suggestion block includes a note at the top:
     "These suggestions assume correct input data. If alignment is still
      < 30% after retry, the issue is likely in the input, not parameters."
```

---

### US-3.4 — Single-cell: comma-escaped numbers in CellRanger output
**As Alex,** my single-cell run reports "Estimated cells: 1,247" in the QC summary. BioMate shows this correctly as 1,247 cells (not 1 cell), and the QC threshold check uses the right value.

**I want**: large cell counts with comma formatting to be parsed correctly, not interpreted as strings or truncated.

**So that**: I don't get a false QC failure saying I only recovered 1 cell when I actually have 1,247.

**Acceptance Criteria:**

```
GIVEN CellRanger metrics_summary.csv contains:
     "Estimated Number of Cells","1,247"
WHEN BioMate reads this file
THEN estimated_cells = 1247  (NOT 1 from truncation, NOT "1,247" as string)
AND the QC check correctly evaluates: 1247 >= 500 threshold → PASS
AND the displayed metric reads: "Estimated Cells: 1,247" (with comma formatting for readability)
AND the QC gate does NOT fire
```

---

### US-3.5 — Metagenomics: database size suggestion
**As Eve (metagenomics researcher),** my Kraken2 classification rate is 28% (threshold 50%). The QC gate suggests I should "use a larger database" — but I don't know which database to use or where to get it.

**I want**: the suggestion to be actionable, not just descriptive.

**So that**: I know exactly what to do next, not just that something is wrong.

**Acceptance Criteria:**

```
GIVEN classified_pct = 28%  (threshold 50%)
AND current_database = "minikraken2_v2_8GB"
WHEN the QC gate fires
THEN the suggestion reads:
     database: "minikraken2_v2_8GB" → "standard_16"
     Reason: "The 8 GB database covers ~25% of known microbial sequences.
              The standard 16 GB database covers ~60% and typically increases
              classification rates by 15–30% for environmental samples."
AND a note explains the trade-off:
     "Larger database requires ~16 GB RAM and takes 3–5x longer to run.
      Your current compute environment appears to support this."
AND there is a secondary suggestion:
     confidence_threshold: 0.1 → 0.0
     Reason: "Removing the confidence filter catches more reads at the cost
              of slightly higher false positive classification."
AND if the database file is not available on the execution environment,
     a warning badge shows: "Database not found on this compute node —
                              you may need to download it first."
```

---

## Epic 4: The Skip / Override Path

### US-4.1 — Power user skips pilot entirely
**As Priya,** I've run this exact workflow on this exact sample type 20 times. I know my parameters are correct. I don't want to wait 3 minutes for a pilot I don't need.

**I want**: a clear, easy way to skip the pilot and run the full dataset immediately.

**So that**: I don't feel patronised or slowed down.

**Acceptance Criteria:**

```
GIVEN pilotRunSuggested = true
AND I click "Skip pilot, run full dataset now"
THEN no confirmation dialog appears (the skip link itself is deliberate enough)
AND the workflow immediately begins Phase 1 (full run)
AND a subtle collapsed note remains visible:
     "Pilot was suggested but skipped by user"
     (so the audit log shows this was a deliberate choice)
AND subsequent identical workflow submissions for the same user
     do NOT auto-trigger the pilot banner for 7 days
     (the system learns from the skip)
```

---

### US-4.2 — Proceeding despite QC failures on every step
**As Priya,** I'm running a benchmark where I deliberately use poor parameters to measure the effect. Every step fires QC gates. I want to click "Proceed Anyway" on every one without the system adding friction.

**I want**: a "Do not stop at QC gates for this run" toggle that I can set at the start.

**So that**: I can run a full pipeline with intentionally bad parameters for experimental purposes.

**Acceptance Criteria:**

```
GIVEN I am viewing the workflow before running
WHEN I open the execution options (gear icon or "Advanced" expander)
THEN I see a toggle:
     [ ] "Pause at QC failures and ask for confirmation"  (default: on)
AND if I turn it off:
     A yellow banner shows:
     "QC monitoring is active but will not pause execution.
      Failures will be logged and shown in the final report."
AND the run proceeds without any modal interruptions
AND the final run summary shows a consolidated QC report:
     "3 QC gates would have fired: FASTP (reads_surviving 52%),
      STAR_ALIGN (alignment 45%), FEATURECOUNTS (assigned 30%)"
```

---

### US-4.3 — Custom QC thresholds
**As Priya,** I'm working with a low-complexity soil microbiome where 35% Kraken2 classification is actually good. The default 50% threshold will keep firing false QC gates.

**I want**: to set custom thresholds for specific metrics in my workflow.

**So that**: the QC system is calibrated for my biology, not generic defaults.

**Acceptance Criteria:**

```
GIVEN I am viewing a metagenomics workflow
WHEN I open the QC configuration panel (accessible from the workflow header "Settings" icon)
THEN I see a table of active QC thresholds for this workflow:
     Metric                    | Default | My Threshold
     Kraken2 classified_pct    |   50%   |  [    35    ]
     MACS2 peak_count          |  1000   |  [   1000   ]
     STAR alignment_rate       |   60%   |  [    60    ]
AND I can edit any threshold
AND I can reset individual rows to default
AND changes apply to the current run only (not saved globally by default)
AND there is a "Save as default for this workflow type" checkbox
AND thresholds that are changed from default are highlighted in yellow
```

---

## Epic 5: Core Facility / Automation Use Cases

### US-5.1 — Core facility running 20 samples: which ones need attention?
**As Frank (core facility),** I submitted 20 RNA-seq jobs simultaneously. Some have QC gates firing and some don't. I need to triage which ones need my attention.

**I want**: a consolidated view across all running jobs showing QC status at a glance.

**So that**: I can prioritise my time without opening each job individually.

**Acceptance Criteria:**

```
GIVEN 20 workflows are running
AND 4 have QC gates that fired and are waiting for decisions
AND 3 completed successfully
AND 13 are still running without issues
WHEN I view my jobs dashboard
THEN the 4 waiting-for-QC jobs are sorted to the top with an orange "Action required" badge
AND each shows a one-line QC summary:
     Sample_12: STAR alignment 41% (threshold 60%) — 2 suggestions available
     Sample_07: FASTP Q30 62% (threshold 75%) — 1 suggestion available
AND I can click "Apply all suggestions" for each without opening the full modal
AND I can click "Bulk apply" to apply all high-confidence (> 80%) suggestions
     across all 4 waiting jobs in a single action
AND I can set a global preference: "Auto-apply suggestions with confidence > 85%
     and proceed — do not ask me to confirm"
```

---

### US-5.2 — Automated nightly batch run
**As Frank,** I have a CRON job that submits 50 samples every night. I don't want QC gates waking me up at 3 AM with modals.

**I want**: a fully automated mode where high-confidence suggestions are applied automatically and only critical failures (< 20% alignment, etc.) are escalated to email.

**So that**: routine jobs run without any human intervention while genuine problems still surface.

**Acceptance Criteria:**

```
GIVEN I configure a workflow with:
     auto_apply_confidence_threshold: 0.85
     escalate_to_email: frank@institute.org
     escalation_condition: alignment_rate < 20% OR classified_pct < 20%
WHEN a QC gate fires with confidence 0.90
THEN the suggestion is applied automatically
AND the workflow continues without pausing
AND a non-urgent email is sent:
     "QC gate at STAR_ALIGN (sample 14) — auto-applied twopass_mode=true (90% confidence)"
WHEN a QC gate fires with alignment_rate = 8% (escalation threshold)
THEN the workflow pauses
AND an urgent email is sent immediately:
     "ESCALATION: Sample 14 alignment rate critically low (8%).
      Manual review required. Workflow is paused."
AND the job remains paused until I log in and make a decision
```

---

## Epic 6: Transparency and Trust

### US-6.1 — Knowing where the suggestion came from
**As Alex,** I see a suggestion to change `twopass_mode` from `false` to `true`. I want to understand whether this is coming from a rules engine, a model, or observed results from my own run.

**I want**: the suggestion source to be visible so I can calibrate my trust appropriately.

**So that**: I apply evidence-based suggestions with high confidence and be more cautious with heuristic ones.

**Acceptance Criteria:**

```
GIVEN a suggestion for twopass_mode
THEN the suggestion card shows a "Source" line:
     For rules-based: "Based on: low alignment rate + novel splice junctions heuristic"
     For ML-based: "Based on: similar workflows in BioMate with 89% success rate"
     For literature: "Based on: ENCODE RNA-seq pipeline best practices (Dobin 2013)"
AND there is a small "i" info icon that expands to show:
     "This suggestion was generated by BioMate's rule engine.
      Rule: if alignment_rate < 60% and organism is human and protocol is polyA-RNA,
      then twopass_mode significantly improves novel splice junction recovery.
      This rule has been validated on 847 similar workflows."
```

---

### US-6.2 — The QC log after completion
**As Alex,** my workflow completed. I want to see a complete record of what QC gates fired, what decisions were made, and what the final quality metrics were — all in one place.

**I want**: a post-completion QC report that I can include in my methods section.

**So that**: I can document exactly how parameters were determined for publication.

**Acceptance Criteria:**

```
GIVEN my RNA-seq workflow completed after 1 QC gate intervention
WHEN I click "View QC Report" in the workflow output panel
THEN I see a structured report:
     QC Gate Events:
     ─────────────────────────────────────────────────────────────
     Step: STAR_ALIGN  |  Time: 14:23:07
     Metric: alignment_rate = 45%  (threshold ≥ 60%)
     Decision: Retry with suggestions
     Applied: twopass_mode false→true, max_mismatches 2→4
     Result: alignment_rate = 78%  ✓
     ─────────────────────────────────────────────────────────────
     Final QC Summary:
       FASTP:         reads_surviving = 87%  ✓
       STAR_ALIGN:    alignment_rate = 78%   ✓  (after 1 retry)
       FEATURECOUNTS: assigned_pct = 71%     ✓
       SALMON:        mapping_rate = 82%     ✓
AND there is a "Copy for Methods section" button that generates:
     "STAR (v2.7.11) was run with twopass_mode enabled and max_mismatches=4.
      Initial alignment rate was 45%; parameters were automatically adjusted
      by BioMate's QC gate system based on low alignment rate detection,
      achieving a final alignment rate of 78%. All QC thresholds passed."
```

---

### US-6.3 — Understanding the difference between QC warnings and QC failures
**As Nina,** I see both orange warnings and red errors in the QC panel and don't know which ones I need to act on.

**I want**: clear visual distinction between "this will probably cause problems" (failure, gates the run) and "this is a heads-up" (warning, run continues).

**So that**: I know which alerts require my action and which are just informational.

**Acceptance Criteria:**

```
Failures (red, gate the run — user must decide):
  - Metric crossed a hard threshold (e.g. alignment_rate < 60%)
  - Run is paused; QC gate modal opens
  - Example badge: [QUALITY GATE TRIGGERED — ACTION REQUIRED]

Warnings (yellow, do not gate — run continues):
  - Metric is approaching a threshold (e.g. alignment_rate = 63%)
  - Run continues normally; warning added to step card
  - Example badge: [WARNING: Near quality threshold — monitor]

Informational (blue, always shown, no action required):
  - Normal quality metrics summary
  - Example: "STAR alignment: 82% ✓ (typical range 70–95%)"

GIVEN alignment_rate = 63% (threshold 60%)
THEN a yellow warning badge appears on the STAR step:
     "Alignment rate 63% — above threshold but lower than typical (70–95%)"
AND the workflow does NOT pause
AND the warning is collapsed by default, expandable with one click
```

---

## Epic 7: Error and Recovery States

### US-7.1 — QC gate fires on a process that has no suggestions
**As Nina,** the QC gate fired for CTF estimation but BioMate has no parameter suggestions. The modal shows a grey box saying "No automatic suggestions available." I don't know what to do.

**I want**: the no-suggestion state to tell me what to do manually, not just tell me there's nothing it can do.

**So that**: I have a next step even when automation can't help.

**Acceptance Criteria:**

```
GIVEN CTF estimation has fit_quality = 0.03 (threshold 0.1)
AND no suggestions are available
WHEN the no-suggestion alert renders
THEN it reads:
     "No automatic suggestions available for this failure pattern.

      Possible causes and manual interventions:
      • Check micrograph quality: open a few micrographs in CTFFIND4 viewer
        to see if they are visibly blurry or have ice contamination
      • Verify microscope settings: ensure accelerating voltage and
        spherical aberration (Cs) match your microscope's actual values
      • Check pixel size calibration: incorrect pixel size shifts all
        defocus estimates

      [Open Documentation] [Contact Support]"
AND the action buttons are:
     [Proceed Anyway]   [Cancel Workflow]
     (Retry is hidden since there's nothing to retry with)
```

---

### US-7.2 — SSE connection lost during a run
**As Nina,** I'm watching my workflow run and the progress indicators suddenly stop updating. I'm not sure if the workflow crashed or if I just lost the live connection.

**I want**: a clear indicator that distinguishes "workflow is still running but I lost the live feed" from "the workflow actually stopped."

**So that**: I don't panic and cancel a healthy run.

**Acceptance Criteria:**

```
GIVEN the SSE connection drops while the workflow is running on the backend
WHEN 10 seconds pass with no events
THEN a subtle banner appears at the top of the workflow card:
     "Live updates paused — reconnecting..."  (spinner)
AND the step progress indicators show their last known state (not blank)
WHEN the connection restores
THEN the banner disappears
AND any QC gate events that fired while disconnected are replayed immediately
     (the modal opens as if in real time)
WHEN reconnection fails after 30 seconds
THEN the banner changes to:
     "Live updates unavailable. Workflow may still be running on the server.
      [Refresh status manually]"
AND clicking refresh polls the backend for current invocation state
     and updates all step statuses
```

---

### US-7.3 — Same QC gate fires again after retry
**As Alex,** I applied BioMate's suggestions and retried. The alignment rate improved from 45% to 58% — still below the 60% threshold. The same QC gate is triggering again.

**I want**: the second QC gate to acknowledge that we already tried once and show me what changed.

**So that**: I don't feel like the system is stuck in a loop.

**Acceptance Criteria:**

```
GIVEN this is the second time the same QC gate has fired for the same step
WHEN the modal opens
THEN the title reads:
     "Quality gate triggered again — retry #2"
AND a diff panel shows what changed from the first retry:
     Previous: alignment_rate = 45% → After retry: alignment_rate = 58%
     "Improvement of +13 percentage points — still below threshold"
AND the suggestion panel notes:
     "Previous suggestions partially helped. Additional options:"
     (shows new suggestions if available, or different suggestions from last time)
AND if the same suggestions are offered again:
     "This suggestion was already applied. Applying it again is unlikely to help."
AND after 3 retries on the same step, an escalation message appears:
     "After 3 retries this step is still failing. Consider cancelling and
      reviewing the raw input data or contacting BioMate support."
```

---

## Summary: Key Design Principles

These user stories define the following design contract for the QC gate system:

| Principle | Implementation |
|---|---|
| **Silent success** | Auto-advance when everything passes. Only interrupt when action is required. |
| **Default to automated** | High-confidence suggestions pre-selected. Users opt out, not opt in. |
| **Domain language** | Metric names and descriptions use the tool's native terminology (Å, not "units"; "CTF fit quality", not "fit_quality"). |
| **Root cause first** | Distinguish "data problem" from "parameter problem" before suggesting parameter fixes. |
| **Audit trail always** | Every QC gate, decision, and retry is logged — for publication methods sections and debugging. |
| **Escape hatch always** | Skip pilot, proceed anyway, cancel — always available. BioMate assists, never blocks. |
| **Context-preserving retry** | Retry re-runs only the failed step and downstream steps, never already-passed steps. |
| **Progressive disclosure** | Simple case = 3 buttons and one red badge. Advanced case = expandable details, confidence scores, suggestion sources. |

---

## Open Questions for Product / Engineering

1. **When should BioMate auto-apply suggestions without asking?** Current plan: only when user explicitly enables it in settings. Should there be a per-session "trust mode"?

2. **How do we communicate when a suggestion comes from rules vs. ML vs. literature?** The rule-based system is currently implemented; ML suggestions are future work.

3. **Should QC gates fire during the pilot run, or only during the full run?** Current architecture fires gates for both. During pilot, failing gates could short-circuit before the full run starts (good). But this means pilot can take longer than expected if a retry is needed.

4. **What is the retention policy for QC event logs?** They should persist in the run history for at least the lifetime of the output data. The Methods section generation depends on this.

5. **Who sees QC gates on shared workflows?** If Alice submits a job and it's waiting at a QC gate, can Frank (same team) approve the suggestion? What are the multi-user collaboration semantics?
