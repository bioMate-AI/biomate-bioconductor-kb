# Workflow instability — when the run fails its QC, the agent fixes it

*Fourth in the ChatInvent series. The AstraZeneca Molecular AI team (Jiazhen He, Ola Engkvist, Samuel Genheden et al.) named **workflow instability** as one of the five engineering problems agentic AI hits in pharma R&D, in their *Drug Discovery Today* paper ["Democratising real-world drug discovery through agentic AI"](https://doi.org/10.1016/j.drudis.2026.104605) (doi: 10.1016/j.drudis.2026.104605). This is the one that sets the productivity ceiling: not whether the agent can start a workflow, but what happens when the workflow comes back with results that don't pass QC.*

---

## What the problem actually is

You start a workflow. It completes. You look at the output.

- The ADMET screen returns 47 compounds; 12 of them have a hERG flag.
- The cryo-EM 2D classification finishes; the classes look blobby and resolution is stuck at 4.2 Å.
- The NCA-PK analysis runs; the AUC extrapolation is 38% (FDA accepts ≤20%).
- The RNA-seq job finishes; the RIN scores are 4.1 across half the samples.

In every case, the run "succeeded." The pipeline ran to completion. The output files exist.

The science is still wrong, or at best unusable.

The naive AI agent stops here. It hands the result to the scientist. The scientist (or, more likely, a bioinformatician the scientist has to wait for) reads the QC report, figures out what knob to turn, restarts the run with new parameters. Days pass. The next run has a different problem. More days.

This is **workflow instability**: not crashes, but the inability of the agent to *close the loop* between a result and the next better result.

---

## What we built

> 📊 **Figure 1 — Auto-loop QC remediation cycle.** Source: `figures/post_15_auto_loop.drawio.xml`. Open in [diagrams.net](https://app.diagrams.net), export PNG at 1200×800.

Four pieces, working together as a single closed loop.

### 1. Per-phase QC gates with configured thresholds

Every workflow has a `qc_settings` block in BioMate's registry — a list of metrics with thresholds. The user can edit them per program; defaults come from the relevant FDA / ICH / OpenMS / nf-core guidance.

Examples:

- **ADMET:** hERG (Aronov 2008 threshold), DILI (Lammert 2010), Ames (Kazius 2005), Ro5 violations
- **CYP-DDI:** FDA 2020 DDI gates (R1/R2 investigate / clinical study cutoffs)
- **Docking:** valid_poses + binding_score (Vina kcal/mol + Glide GlideScore)
- **NCA-PK:** FDA-mandated AUC extrap ≤ 20% + terminal slope coverage
- **CryoEM:** CTF estimate, resolution at 0.143 FSC, particle distribution
- **RNA-seq:** RIN, Q30, mapping rate, library complexity

Each gate has three outcomes: **pass**, **advisory**, **halt**.

### 2. Remediation proposals — was → now diff

When a gate halts, the agent doesn't just say "QC failed." It diagnoses and proposes a fix:

- "hERG-flag rate is 25%, gate threshold is 10%. Proposed remediation: tighten the logP filter to <4.5 and the MW filter to <500 Da, per Aronov 2008. **Was:** logP ≤ 5, MW ≤ 550. **Now:** logP ≤ 4.5, MW ≤ 500."
- "CryoEM resolution stalled at 4.2 Å. Three most likely causes given your defocus range: (1) CTF estimation drift in last 200 micrographs, (2) under-defocused subset dragging the class average, (3) ice-thickness variation. Proposed: re-run CTF estimation with tighter defocus bounds, exclude micrographs with CTF fit < 0.7."
- "NCA-PK AUC extrap is 38%, FDA cap is 20%. Last sampling time was 24 h, terminal half-life is 18 h. Proposed: extend last_sampling_time_h to 36 h (1.5× last time × log-linear capture).

Every proposal carries a citation to the rule or paper behind it.

### 3. User approval surface

The user sees the was → now diff, the citations, and approves / rejects with one click. No surprise re-runs.

This is the human-in-the-loop pillar from the ChatInvent paper. The agent proposes; the user disposes; the loop closes with informed consent.

### 4. Same pattern across every domain

The architecture is shared. The remediation rules are domain-specific (different gates, different fixes), but the orchestration code is one orchestrator. Adding a new auto-loop is one PHASES list, one set of QC gates, one set of remediation rules.

This is how we ship four production auto-loops with the same engineering team in the same quarter.

---

## What the benchmarks say

| Auto-loop                                            | Coverage / Tests        | Highlights                                                           |
|------------------------------------------------------|--------------------------|----------------------------------------------------------------------|
| **ADMET** (hERG / DILI / Ames / Ro5)                | 24/24 tests              | 3 remediation profiles; thresholds from Aronov / Lammert / Kazius   |
| **CYP-DDI** (FDA 2020 R1/R2)                         | 24/24 tests              | INVESTIGATE / CLINICAL_STUDY gating + cmax_ss_uM reduction         |
| **Docking** (Vina + Glide)                          | 24/24 tests              | hit_finding / lead_opt / fragment profiles; exhaustiveness + box → SP → XP escalation |
| **NCA-PK** (FDA AUC extrap ≤20%)                    | 24/24 tests              | standard / exploratory / regulatory profiles; last_sampling_time_h × 1.5 remediation |
| **CryoEM** (CTF + resolution + particle dist)       | 95/95 unit + 24/24 E2E   | Was→now param diff in the right panel; data viz panels      |
| **Auto-loop convergence benchmark**                  | 96.4% convergence ≤ 3 iterations | Cross-domain measure of how often the loop reaches pass within 3 remediation rounds |

The headline: **96/96 tests across the four drug-discovery auto-loops, 95/95 + 24/24 for cryo-EM, and 96.4% cross-domain convergence within 3 remediations.**

This is what taking workflow instability seriously looks like as code that ships.

---

## Why this matters more than people think

The standard "AI for drug discovery" pitch is *better prediction*. ADMET model with 91% AUC. Docking pose with 0.3 Å better RMSD.

This frames the productivity gain as a one-shot. Better model → better answer.

The real bottleneck isn't one-shot accuracy. It's the **iteration cycle**: how many days between "the workflow gave me X" and "I have something better than X to act on."

In the typical R&D group today, that cycle is 3–14 days, gated by a human bioinformatician. The auto-loop compresses it to minutes — and crucially, *with a full audit trail* of why each remediation was proposed and approved.

The compounding productivity gain isn't from one model getting better. It's from the cycle getting 100× faster while staying defensible.

---

## The honest limitations

- **96.4% convergence ≤ 3 iters means 3.6% don't converge.** Some genuinely don't have an automatic fix (e.g., dataset is too noisy to salvage). The agent admits the dead-end instead of looping forever.
- **The remediation rules are curated.** When a domain hits a new failure mode, we have to add the rule. Until then the loop halts cleanly with "no auto-remediation available, recommend manual review."
- **Auto-loop ≠ autopilot.** Every remediation requires user approval before execution. This is intentional — for regulatory defensibility, the human stays in the loop.

---

> 🧪 **Try the closed loop.** Open trial — bring an ADMET hit series with known hERG liabilities, or an NCA-PK study with sampling gaps, and watch the auto-loop propose, get approved, and converge: [**biomate.ai/try**](https://biomate.ai/try)

---

*Next post: memory corruption + traceability + governance — what we built for the long-running stability that pharma R&D actually needs.*

— Yaoyun Wang
Founder & CEO, BioMate AI
