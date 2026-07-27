# Lead-Tailored Demo Runbooks — UCB & VorBio

**Date:** 2026-07-27
**Purpose:** Exact, reproducible demo scripts + talking points for the two highest-priority summit leads. Both run on **real, live data** (no synthetic fixtures) and are fully citable.

Local run note: `nextflow -profile standard` executes the embedded Python on the host (stdlib only) — no Docker needed for these. On dev/prod they run in the `biomate/biotools` + `biomni-tools` containers.

---

## DEMO 1 — UCB / Jessica VanBaaren (target discovery)

**Who:** Senior Scientist, Neuromuscular Translational Biology. She presented UCB's own multi-omics/AI target-discovery methodology at the summit.

**The hook (one line):** *"You described this on stage — closed-system, human-in-the-loop, provenance-backed multi-omic target ranking. Here it is running, on live Open Targets data, and it rediscovered your own MG franchise."*

**Why it lands:** the pipeline independently ranks **C5 #1** and **FCGRT #2** — complement C5 and FcRn, i.e. UCB's *zilucoplan* (Zilbrysq) and *rozanolixizumab* (Rystiggo) MG target classes — from public evidence, using the exact method (Open Targets two-layer) her team already trusts.

### Run it
```bash
CFG=backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/target_scorecard_ranker/nextflow.config

# Step 1 — live Open Targets evidence + prioritisation panel
cd backend/biomni_workflows/nextflow/subworkflows/database
nextflow run query_opentarget.nf -c "$CFG" -profile standard \
  --disease "myasthenia gravis" --n_targets 20 --outdir out
#   -> out/target_evidence.csv          (genetic / mechanism / tractability / safety)
#   -> out/target_prioritisation.csv    (OT traffic-light panel)

# BioMate suggests the next step; the user decides. Step 2 — rank:
cd .../drug_discovery/target_scorecard_ranker
nextflow run main.nf -profile standard \
  --evidence_file .../database/out/target_evidence.csv \
  --disease "Myasthenia Gravis" --outdir scored
#   -> scored/scorecard_run/target_scorecard.csv   (ranked)
#   -> scored/scorecard_run/target_ranking_report.md
```

### Expected result (talking points as you show the table)
| Rank | Gene | Tier | Point to make |
|---|---|---|---|
| 1 | **C5** | Tier 1 | Complement — your zilucoplan target. Rediscovered from public evidence. |
| 2 | **FCGRT** | Tier 2 | FcRn — your rozanolixizumab target. Tier 2 *because* its mechanism evidence (ex known-drug) is literature-only — the system is honest, not inflating. |
| … | K-channels | Tier 3/4/UNSCORED | Symptomatic 3,4-DAP channels correctly deprioritised — not disease-mechanism targets. |

### The three things to emphasise (mirror her own language)
1. **Closed & citable** — every score traces to Open Targets (Ochoa 2021/2023, Buniello 2025), genetic-support-of-success (Nelson 2015; Minikel 2024, 2.6× success), LOEUF (Karczewski 2020). No black box, no hallucination.
2. **Two layers, never conflated** — a harmonic-sum association *ranking* + a separate traffic-light *prioritisation panel* (`target_prioritisation.csv`). Exactly her "AI ranks, human decides" governance.
3. **Step-by-step, human-gated** — after each step BioMate *suggests* the next ("rank these?", "send C5/FCGRT to lead-finding?"); the scientist decides. No auto-run.

**Positioning caveat:** this doubles as validation of her methodology — frame as partnership/co-development, aware it may accelerate her internal build.

---

## DEMO 2 — VorBio / Jeremy Sokolove (autoantibody-isotype stratification)

**Who:** CMO (rheumatologist; ex-GSK/AbbVie/Odyssey/Roivant). Lead asset **telitacicept** (dual BAFF/APRIL, Phase 3 gMG).

**The hook (one line):** *"You said the open question is which MG patients carry non-IgG autoantibodies that FcRn inhibitors can't touch. Here's a workflow that stratifies exactly that population — your telitacicept candidates — from a serology panel."*

**Why it lands:** it's not a platform pitch, it's *their specific pilot*. FcRn inhibitors clear IgG only; patients with an IgA/IgM contribution are the ~30% non-responders — and the rational BAFF/APRIL (telitacicept) population.

### Run it (needs a real serology panel: patient_id, igg_total, igg1-4, iga, igm, baff, april, …)
```bash
cd backend/biomni_workflows/nextflow_nfcore/subworkflows/immunology/autoantibody_isotype_stratification
nextflow run main.nf -profile standard \
  --serology_file <your_mg_cohort_serology.csv> \
  --cohort "MG FcRn-refractory screen" --outdir out
#   -> out/isotype_run/patient_stratification.csv   (per-patient prediction)
#   -> out/isotype_run/cohort_summary.json          (the headline number)
#   -> out/isotype_run/stratification_report.md
```

### Expected result (talking points)
- **Cohort readout:** "X% of your screen-fail / non-responder cohort is IgA/IgM-driven and telitacicept-addressable." (On the test cohort: 50%.)
- **Per patient:** IgG-dominant → predicted FcRn-responsive; meaningful IgA/IgM (+elevated BAFF/APRIL) → **FcRn-refractory → telitacicept candidate**; IgG4-predominant (MuSK-like) → flagged mechanistically distinct.

### Emphasise
1. **Tailored to their mechanism**, not generic analytics — isotype composition → FcRn response prediction → BAFF/APRIL rationale.
2. **Citable** — FcRn IgG-selectivity (Howard 2021 ADAPT), AChR isotype heterogeneity, telitacicept BAFF/APRIL Ph3.
3. **A scoped pilot**, not a seat: run it on their gMG Phase 3 screen-fails to quantify the telitacicept-addressable fraction.

---

## Both demos — the shared story
- Real data, closed system, every choice citable → credible to a pharma/translational audience.
- Human-in-the-loop, step-by-step: BioMate suggests, the scientist decides.
- One is discovery (UCB), one is stratification (VorBio) — same engine philosophy, tailored to each account's stated need.
