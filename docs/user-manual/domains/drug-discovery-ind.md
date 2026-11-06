# Drug discovery → IND

> One-line promise: take a set of candidate compounds from a computational ADMET/PK safety
> assessment all the way to a signed, downloadable IND §2.6 nonclinical dossier — with every number
> traceable and the auto-loop tightening your screen when a safety gate trips.
> For: **medicinal / computational chemists**, **DMPK / preclinical pharmacologists**, and
> **regulatory / CMC scientists** preparing a Phase-I IND package. No coding required.

<!--
Flagship chapter. Every "supported" claim below is green in coverage-ledger.md § "Drug discovery → IND".
Honesty rule: computational-only capabilities are labelled as such; wet-lab / GLP-dependent sections
are flagged as "partial until you upload measured data"; anything not built is in "What's not covered".
-->

## What this is for

This is the "bench-to-dossier" path. You bring **structures** (SMILES) and, where you have them,
**measured PK values**; BioMate returns a **safety and pharmacokinetics assessment** and then
**assembles the ICH-M4 CTD §2.6 nonclinical summary** you file with an Investigational New Drug (IND)
application.

Four things happen, in order:

1. **ADMET screening** — predict absorption/distribution/metabolism/excretion/toxicity properties for
   each compound and check them against safety gates (hERG, DILI, Ames, Lipinski Ro5).
2. **Auto-loop remediation** — when a gate *halts*, BioMate proposes a concrete parameter change
   (e.g. tighten the library's `logP` / molecular-weight ceiling), shows you the **was → now** diff,
   and re-runs the screen so the flagged chemistry drops out. Nothing runs silently.
3. **PBPK / first-in-human dose** — simulate a human PK profile and project a safe starting dose from
   animal data by allometric scaling.
4. **IND §2.6 assembly** — turn the runs above into a §2.6.1 Pharmacology / §2.6.4 tabulated summary
   **DOCX**, with a 21 CFR Part 11 audit trail, e-signature and immutable versions.

The through-line the whole chapter serves: **interpretation, not a metrics dump.** Every gate and every
flag below is explained as "what it means and what to do next."

> **Tip** — You do **not** need to run all four stages to get value. Screen-only (stage 1) is an
> Instant-lane answer for triaging a hit list. The IND assembly (stage 4) is the moat, but it is only
> as "full" as the data you feed it (see the coverage callouts under each stage).

## Use cases

| Goal (researcher's words) | Workflow(s) / chain | Inputs | Outputs (artifact) | Lane |
|---|---|---|---|---|
| "Screen these hits for ADMET and flag hERG/DILI" | `predict_admet_properties` (ADMET-AI / DeepPurpose) | SMILES list | Per-compound property table (16 endpoints) + gate verdicts | Cloud (AWS Batch) |
| "…and if a gate fails, fix it and re-screen automatically" | ADMET screen + **auto-loop** (`autoloop_bridge` → `admet_autoloop`) | same, + QC profile | Remediation card (was→now params) + re-run + gate table | Cloud |
| "Project a safe human PK profile / starting dose" | `pbpk_simulation` (8-compartment Rodgers–Rowland) | SMILES + CL_int, f_u, MW/logP/pKa, dose | PK profile CSV + NCA table (Cmax/AUC/t½/Vss/F) | Cloud |
| "Give me a first-in-human dose from my animal PK" | `allometric_scaling` | Per-species BW + CL/Vd (+ NOEL) | Human CL/Vd/t½, HED, MRSD, MABEL + R² QC | Cloud |
| "Assemble the IND §2.6 nonclinical dossier and let me sign it" | `ind-assembly` (INDSectionAssembler) | Outputs of the runs above (in the project) | §2.6.1–§2.6.7 Markdown + **DOCX**, audit trail, e-sig | Cloud |

> **Pitfall** — This chapter is a **computational** package. It gives you IND-quality *predicted*
> pharmacology/PK and the assembly scaffold. Toxicology written/tabulated sections that require GLP
> in-vivo data (§2.6.3, and parts of §2.6.6) stay **partial** until you upload measured data — BioMate
> says so on the coverage dots rather than pretending. See "What's not covered."

## How to ask

BioMate routes on intent; the disambiguation that matters here is **screen vs. simulate vs. assemble**.

Screen a hit list (stage 1 + auto-loop):

> "Screen these for ADMET and flag hERG and DILI: `CCO`, `CC(=O)Oc1ccccc1C(=O)O`,
> `CCCCCCCCCCCCCCCCc1ccccc1`."

Project human PK / a starting dose (stage 3):

> "Run a PBPK simulation for this compound (SMILES …, CL_int 12 µL/min/mg, f_u 0.03, MW 421,
> logP 3.2), 50 mg oral, healthy adult — give me Cmax, AUC and t½."

> "I have rat and dog CL and Vd plus a rat NOEL of 10 mg/kg — predict the human dose (MRSD/MABEL)."

Assemble the dossier (stage 4):

> "Assemble the IND §2.6 nonclinical package for this campaign and let me review and sign it."

> **Tip — reaching the IND workspace.** The in-chat **"Generate IND"** handoff (the
> `DrugDiscoveryAction` widget → `/api/drug-discovery/:id/ind-assembly`) is **not currently wired into
> live chat**, so that button does not appear under an ADMET result today. The IND report page itself is
> still reachable by **direct URL** (`/ind-report`) — open it there and set up the project header and
> ADMET step yourself.

**Disambiguation to avoid:**
- "PK" alone is ambiguous. *"predict human PK from structure"* → `pbpk_simulation`; *"scale from
  animal data / first-in-human dose"* → `allometric_scaling`. If you give a SMILES but no clearance
  or `f_u`, BioMate will **ask for them** before running rather than guess (a prerequisite gate).
- "ADMET" defaults to the full 16-endpoint screen. If you only want a single property, say so.

## Tools & workflows behind this

| Tool / workflow | Role | Where (verified) |
|---|---|---|
| `predict_admet_properties` | 16-endpoint ADMET prediction via DeepPurpose models | `backend/biomni_workflows/nextflow/subworkflows/pharmacology/predict_admet_properties.nf` |
| Applicability-domain check | Flags compounds the model hasn't seen (hat-matrix leverage + Tanimoto) | `backend/lib/galaxy/ai/drug_discovery/applicability_domain.py` |
| QC-gate evaluator | Turns predictions into halt/advisory/pass verdicts with cited thresholds | `backend/experiments/admet_autoloop/qc_evaluator.py`; wired via `backend/experiments/autoloop_bridge.py` |
| Auto-loop orchestrator + param tuner | Proposes was→now param changes and re-runs | `backend/experiments/admet_autoloop/orchestrator.py`, `param_tuner.py`; SSE inject at `nextflow_executor.py:3380-3409` |
| `pbpk_simulation` | 8-compartment Rodgers–Rowland ODE PK model + NCA | `backend/.../subworkflows/drug_discovery/pbpk_simulation/main.nf` |
| `allometric_scaling` | Animal→human PK regression + FIH dose (HED/MRSD/MABEL) | `backend/.../subworkflows/pharmacology/allometric_scaling/main.nf` |
| `INDSectionAssembler` | Assembles §2.6.1–§2.6.7, renders DOCX via pandoc | `backend/lib/galaxy/ai/drug_discovery/ind_assembly.py` |
| IND workspace UI (5 steps) | Setup → ADMET → PBPK → Leads → Document | `frontend/client/src/components/ind-report/IndSteps.tsx` |
| Drug-discovery API | campaigns, audit, e-sig, ind-assembly, attachments | proxied at `frontend/server/routes.ts:4649` (`/api/drug-discovery/*`) |

> **License** — ADMET predictions use models trained on public TDC/DeepPurpose datasets. Predicted
> values are *decision-support*, not measured assay results; the dossier labels them as predictions and
> lets measured (wet-lab) values override them where provided.

## QC gates & how to read them

A gate answers one question for a scientist: **"is this compound safe enough to carry forward, and if
not, what do I change?"** BioMate reports each gate in two numbers — **measured (predicted) vs.
threshold** — and one of three verdicts:

- **PASS** (green) — below the liability line; carry forward.
- **ADVISORY** (amber) — near the line; logged and shown, but the run continues. *You* decide.
- **HALT** (red) — over the line; the pipeline stops and the auto-loop offers a fix.

### ADMET / toxicology gates

| Gate | Threshold (HALT) | What a fail means | Citation |
|---|---|---|---|
| **hERG IC₅₀** | `< 10 µM` (advisory band from 11.5 µM) | Cardiac (QT) liability risk — the compound blocks the hERG channel at low concentration | Redfern 2003; ICH S7B |
| **DILI probability** | `> 0.5` (advisory from 0.425) | Predicted drug-induced liver injury risk | model prob; profile-tunable |
| **DILI risk level** | `high` / `very high` | Categorical hepatotoxicity flag | Lammert 2010 zone |
| **Ames mutagenicity** | positive / `> 0.5` | Predicted genotoxicity (structural alert and/or QSAR) | Kazius 2005; ICH M7 |
| **Lipinski logP** | `> 5` | Oral-drug-likeness risk (advisory only — never halts) | Lipinski Ro5 |
| **Lipinski MW** | `> 500 Da` | Oral-drug-likeness risk (advisory only) | Lipinski Ro5 |

Thresholds live in `qc_evaluator.py:106-183` and are selectable by **profile**: `admet_standard`
(default), `admet_cns` (stricter — lower DILI tolerance for CNS penetrants), and `admet_oncology`
(higher hERG/DILI tolerance where therapeutic benefit can outweigh risk). Choosing the right profile is
the single most important "interpretation" decision — an oncology lead that "fails" the standard hERG
gate may legitimately pass the oncology profile.

### PBPK / dose gates

| Gate | Threshold | What it means | Citation |
|---|---|---|---|
| **Allometric R²** | `≥ 0.85` (GOLD ≥ 0.95) | How well animal PK scales to human — below 0.85 the human prediction is untrustworthy | FDA 2005 FIH guidance; `qc_gate_reader.py:247` |
| **PBPK t_max fraction** | `≤ 0.8` of sim window | Simulation ran long enough to capture the peak | model QC |
| **PBPK mass balance** | 0.95–1.05 recovery | The ODE conserved mass (sanity check) | EMA tolerance |
| **PBPK AUC fold-error** | `≤ 2.0` (when observed AUC supplied) | Predicted vs. observed exposure agreement | standard 2-fold |

### What the auto-loop actually does

When an ADMET gate **HALTs**, the loop does **not** invent new molecules. It **re-tunes the screening
filter** so the offending chemistry is excluded, then re-runs — up to 2 retries (3 attempts total),
after which the phase is *escalated* to you. The remediation card shows the exact diff:

- **hERG halt** → lower `logp_max` by a gap-proportional step (Waring & Johnstone 2007: lower logP ↔
  lower hERG affinity). Card reads e.g. `logp_max 5.0 → 4.2`.
- **DILI halt** → set `logp_max = 4.0`, `mw_max_da = 400` (Lammert 2010 "high-DILI zone" boundary).
- **Ames halt** → enable `ames_strict` (Kazius structural-alert filter).
- **Lipinski (advisory)** → no auto-tune; advisory-only, your call.

> **Pitfall — read the remediation for what it is.** The auto-loop tightens the *library filter*, so a
> flagged compound (say a long-chain C16 with logP ≈ 9.9) simply **drops out** on the re-run; BioMate
> is not chemically redesigning it into a shorter analogue. If you want analogue generation, that is a
> separate design task (see "What's not covered"). Source: `param_tuner.py:123-185`.

### The `out_of_domain` flag — the most misread label

`out_of_domain` (OOD) does **NOT** mean "bad compound." It means **the model has not seen chemistry
like this**, so its prediction is low-confidence. It is computed two ways
(`applicability_domain.py`): **hat-matrix leverage** (structural outlier vs. the training set) and a
**Tanimoto nearest-neighbour** check (`< 0.20` similarity → OOD). An OOD compound is still **ranked and
kept**, but flagged — in the dossier it gets an explicit limitation statement in **§2.6.1.5**. Treat
OOD as "verify this one experimentally," not "reject."

> **QC gate — the PBPK gateway.** PBPK qualification (and the allometric R² gate) is the load-bearing
> checkpoint before dose reasoning. If it fails, re-qualify (adjust CL, Vd, absorption) before you
> trust any human-dose number downstream.

## Worked example (gold standard)

**Goal.** Triage a three-compound hit list, watch the auto-loop, then read the gates as a chemist.

**Prompt** (the recorded ADMET moat demo, T09):

> "Screen these for ADMET and flag hERG and DILI: `CCO` (ethanol), `CC(=O)Oc1ccccc1C(=O)O`
> (aspirin), `CCCCCCCCCCCCCCCCc1ccccc1` (hexadecylbenzene)."

**What comes back and how to read it:**

- **Aspirin** — passes all gates (hERG clear, DILI negative, Ames negative, Ro5 satisfied). *Carry
  forward.* This is your sanity anchor: a known clean small molecule reads clean.
- **Hexadecylbenzene** — **HALTs.** Its long C16 chain drives `logP ≈ 9.9` (Ro5 advisory) **and** a
  DILI flag (≈ 0.71). The interpretation: this is a lipophilicity-driven liability, not a subtle one.
- **Auto-loop fires.** The remediation card proposes `logp_max 5.0 → 4.0` and `mw_max_da → 400`
  (Lammert 2010). On the re-pilot, hexadecylbenzene falls outside the tightened filter and drops out;
  the remaining set passes. You see the was→now diff and click to apply — never silent.

**The artifact.** A per-compound table (`predict_admet_properties_results.json` →
`toxicity_report.json`) with the 16 endpoints, colour-coded gate verdicts, and the auto-loop's gate
table (red on the failing run, green on the fixed run). This is the "gold-standard-comparable artifact"
the tutorial-demo plan mandates — you end on a decision, not a process tree.

> **Note (verification tier).** The ADMET screen + auto-loop path is **code-verified (C)** end to end
> and is exercised as tutorial T09; a fresh live Batch run to re-confirm exact numeric outputs is
> **pending (L)** and is not fired speculatively (Batch runs cost real money). The PBPK, allometric and
> IND-assembly stages are **code-verified (C)**; their full live re-runs are ledger tier **L / ⏳**.

## Outputs & visualization

| Output | Where it renders | When to go interactive |
|---|---|---|
| ADMET property table + gate verdicts | Workflow panel → after-run **Findings**; table viewer | Export CSV for your own SAR triage |
| Auto-loop remediation card + gate table | Workflow panel **AutoLoopPanel** (was→now diff, halt/advisory/pass colours) | — |
| PBPK PK profile (`pk_profile.csv`) + NCA (`nca_parameters.json`) | Table/plot viewers in after-run outputs | Open the CSV to overlay dose scenarios |
| Allometric regression + FIH dose (`fih_dose_recommendation.json`) | After-run outputs | — |
| IND §2.6 dossier | **IND workspace** (5-step left panel + live document panel on the right) | Edit paragraphs in place; each edit is captured |
| DOCX / Markdown export | Document panel "Download .docx / .md" | Open in Word for the regulatory affairs handoff |
| Audit-trail PDF | Sign success card | Attach to the submission binder |

The IND workspace shows **coverage dots** per section: **filled = full** (computational + measured,
submission-ready), **half = partial** (computational only — upload wet-lab data to upgrade),
**empty = not yet generated**. §2.6.5 and §2.6.6 need GLP data to reach full; the UI tells you so.

## Pitfalls & tips

> **Tip — pick the QC profile before you screen.** `admet_oncology` vs `admet_cns` vs `admet_standard`
> changes which compounds "fail." An oncology lead flagged by the standard hERG gate may pass the
> oncology profile legitimately. The profile choice is documented in the dossier.

> **Pitfall — OOD is not rejection.** An `out_of_domain` compound is ranked and kept, with a limitation
> statement in §2.6.1.5. It means "low model confidence for this chemistry" — prioritise it for
> experimental confirmation, don't discard it.

> **Pitfall — predicted ≠ measured.** Every value in the assembled dossier that came from a model is
> labelled a prediction. Uploading wet-lab data (PDF/CSV via the ADMET step's attachment upload,
> `POST /api/ind-report/projects/:id/attachments`) lets measured values **override** predictions and
> upgrades partial sections toward full.

> **QC gate — allometry needs ≥ 3 species and R² ≥ 0.85.** A first-in-human dose scaled from one or two
> species, or with a poor regression fit, will fail the gate. Add species or reconsider the scaling
> method (Mahmood Rule of Exponents; brain-weight / MLP correction is chosen automatically from the
> fitted exponent).

> **Tip — the audit trail is the point, not decoration.** Signing records signer credentials, a TOTP
> code, the meaning-of-signature statement, and a SHA-256 of the document body into a tamper-evident
> chain; superseding a version keeps the prior signature record forever. Download the audit-trail PDF
> for your submission binder.

## What's not covered

Honest scope — these are **not** claimed as present in this chapter; they live in **Appendix E
(Coverage & roadmap)**:

- **Analogue / de-novo compound generation as remediation.** The auto-loop tightens the screening
  filter (`logp_max`, `mw_max_da`, `ames_strict`); it does **not** generate redesigned analogues. The
  "C16 → C4" narration describes the flagged compound *dropping out*, not a generated shorter analogue.
  (`param_tuner.py`.)
- **Real MFA/TOTP verification in dev.** The e-signature flow, hash chain, DOCX and audit-trail PDF are
  real, but TOTP verification is **weak in the dev environment** (accepts any 6 digits;
  `ind_actions_router.py` `_verify_totp`). Production-grade enrollment/verification is roadmap. Do not
  present the dev signature as a legally binding Part 11 signature.
- **Toxicology sections requiring GLP in-vivo data** (§2.6.3 single/repeat-dose, genotoxicity in-vivo;
  parts of §2.6.6). These render an **"Awaiting GLP data" placeholder** until you upload measured data
  (`ind_assembly.py` `_section_2631_single_dose` etc.). Computational-only ⇒ **partial** coverage.
- **Non-FDA region content.** Region chips (EMA/NMPA/PMDA) display, but section rendering for non-FDA
  regions returns `not_implemented` (`ind_actions_router.py` `/sections/render`). FDA is the supported
  path today.
- **"Submit to FDA."** The disabled button is honest — there is **no** FDA-submission endpoint.
- **NDA-fetch (FDA NDA → PK params).** Honestly disabled ("coming soon"); no scraper/extractor exists.
- **A manuscript "Stage 6."** There is **no** manuscript-assembly stage after the dossier. The IND flow
  is exactly five steps and terminates at DOCX generation; post-assembly paragraph editing is a user
  edit flow, not a generation stage. (`IndSteps.tsx`, `ind_assembly.py` `assemble()`.)
- **PBPK reference-set size.** The PBPK qualification reference set is **30 marketed drugs**
  (`pk_marketed_drugs.json`) — adequate to demonstrate qualification, but smaller than the 100–300
  compound sets used for a full regulatory PBPK claim. Stated as-is, not oversold.

---
_Verification: this page depends on the coverage-ledger rows under **"## Drug discovery → IND"** —
ADMET screen + 16 endpoints (C), applicability-domain / OOD flag (C), ADMET QC gates + thresholds (C),
auto-loop remediation was→now / threshold-only (C), PBPK 8-compartment + NCA (C), allometric 0.33 HED /
R² gate (C), IND §2.6.1/§2.6.4 DOCX assembly (C), 21 CFR 11 audit trail + e-sig with dev-TOTP caveat
(C), and the roadmap/gap rows (🗺️). Live-Batch re-confirmation of numeric outputs is tier L / ⏳._
