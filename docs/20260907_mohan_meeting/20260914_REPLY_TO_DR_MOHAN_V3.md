# Reply to Dr. Mohan — BioMate AI (V3)

**Prepared for Dr. Mohan's review (via Andrew) · September 2026.** Supersedes the Sept-8 reply;
sharpens what BioMate brings (a working, auditable target-selection capability, not a promise) and
states the mutual fit precisely. Proposes no new lab work, cost, or IP terms at this stage; any Lab
data would be existing published or on-request cohort data, under the Lab's terms and any required DUA.

---

## 1 · What has changed since we last wrote

Two things are now concrete rather than aspirational:

- **The system is not a single model — it is a target-discovery *system*.** A mechanistic multi-omic
  model, a **null-calibrated evidence combiner** that ranks targets, modality/druggability gates, and
  a molecule-design front end — turned by a reward-driven loop. We are careful to *not* over-claim: it
  is not "an LLM that predicts outcomes." It predicts **mechanism** and **ranks targets with an
  auditable per-target evidence breakdown**; clinical-outcome prediction is explicitly *not* claimed.
- **The target-ranking combiner is built and behaving honestly.** It scores each evidence channel
  against its own matched negative control, then uses an **OR-gate for nomination** (recall) and an
  **AND-corroboration rule for a high-confidence tier** (precision). In our internal validation this
  corroboration tier is markedly more precise than any single channel, and — importantly — we found
  that naive *averaging* of channels does **not** beat the best single channel, so we don't do it.
  This is the machinery behind your Sept-7 question ("which channels do you use?").

**Proteomic and autoantibody evidence — the Lab's data type — is one of these channels.** Today it is
designed but the least-exercised of the nine, precisely because we lack a rigorous LN proteomic cohort
to build and validate it on. That is the specific gap your data closes (Section 3).

---

## 2 · What BioMate adds to the Lab's program (the "biomarker → target" step)

Your published arc is **biomarker discovery → analytically-validated assay → point-of-care device**,
now advancing ALCAM toward a **therapeutic target** under the LRA Target-Identification grant. BioMate
adds the computational layer between "validated biomarker" and "credible drug target":

1. **Causal target-confidence** — for each Lab marker (ALCAM, VCAM-1, CD163, MCP-1, TWEAK, NGAL…),
   an interpretable score for whether it is a **genetics-anchored causal driver** vs a downstream
   passenger, with the per-channel evidence shown (genetics · perturbation · pathway · network ·
   proteomic/autoantibody · cell-state). This is exactly what a Target-Identification grant must
   defend, and it is auditable, not a black box.
2. **Responder / mechanism stratification** — whether baseline profiles predict which of the ≥4
   approved LN mechanisms (FcRn, BAFF/APRIL, type-I IFN, B-cell depletion) fits a patient — the
   "which therapy for which patient" gap.
3. **Cross-cohort reproducibility** — every claim tested leave-cohort-out against a matched null, so a
   finding is representative rather than single-cohort-biased (strengthens publishability).
4. **Molecule design (later stage)** — for a validated target, our cyclic-peptide design front end
   turns it into candidate molecules optimized for potency/selectivity/permeability (the computational
   complement to the ALCAM–CD6 → itolizumab arc, where the molecule was an external asset).

---

## 3 · What the Lab uniquely enables for BioMate (candid)

We are explicit that this is genuinely mutual — the Lab's data is not interchangeable with public data:

- **It builds our proteomic/autoantibody channel.** Your SOMAscan urine proteomics (1,129 proteins) +
  autoantibody arrays are the ideal substrate to *build and validate* the one evidence channel we
  currently cannot exercise. Public data can't substitute — this is disease-specific, cohort-level.
- **It is the second, cross-ethnic SLE/LN cohort our combiner validation requires.** Our target ranker
  needs a held-out SLE/LN cohort disjoint from the public one we calibrate on; your African-American /
  Caucasian / Asian cohorts are exactly that, and let us test **cross-ethnicity transfer** — a
  discriminating test most groups skip.
- **ALCAM is a real, wet-validated anchor to test us against.** The cleanest first experiment is: does
  our combiner independently recover **ALCAM** as a top-ranked LN target, and what evidence breakdown
  does it give — before we claim anything about targets the Lab hasn't already validated.
- **Patient-level LN data as held-out validation.** Used strictly as validation of our derived
  confidence/stratification scores (the "slow channel" — it validates, it never trains a platform).
- **Wet-lab + clinical validation capability** the dry side cannot self-supply, and the Houston Omics
  Collaborative for generating new paired molecular data where a gap is found.

---

## 4 · A concrete, low-risk first deliverable (4–6 weeks, BioMate compute only)

Pre-registered, on the Lab's **published** cohort first:

1. **Parity** — reproduce the Lab's published primary analysis (the ethnicity-stratified panel).
2. **ALCAM recovery test** — run the combiner blind and report whether ALCAM (and the panel proteins)
   surface as top-ranked LN targets, each with its **per-target evidence breakdown**.
3. **Add the confidence + stratification layer** — causal-driver-vs-passenger confidence, and
   responder/mechanism stratification, on the Lab's cohort.
4. **Cross-cohort transfer** — validate leave-cohort-out across the Lab's cohorts / ethnic groups.

**Success = go / refine / stop, pre-declared:** a signal counts only if it beats a matched null *and*
replicates across cohorts. A null result is a valid, reported outcome. No lab cost; no IP transfer.

---

## 5 · Honest maturity (so expectations are calibrated)

- **Ready now:** the RNA-side representation, the genetics-anchored target ranker with its evidence
  breakdown, and the cross-cohort validation discipline.
- **Build-ahead (not offered in the pilot):** the deeper mechanistic layer — down to *antigen
  presentation*, our longer-horizon differentiator — needs paired proteomic/immunopeptidome data and
  is honestly still in development.
- **Not claimed at all:** direct prediction of clinical outcomes. We add target-confidence and
  stratification, not outcome prediction — and we would rather state that plainly than overreach.

This discipline — null controls, cross-cohort replication, and declaring what we *don't* do — is
itself the point: it is what makes the claims we *do* make trustworthy.

---

## 6 · Data & IP

Only published and reasonable-request cohort data, under the Lab's terms and any required DUA; no
ownership split proposed now. Should the work continue, staged protections (NDA, DUA, MTA if samples
move, and a sponsored-research agreement distinguishing background from project IP) would be in place
**before any nonpublic data or materials move**, consistent with University of Houston policy.

---

## 7 · Proposed next step

A short Zoom between the Mohan Lab and BioMate teams to (a) pick the published cohort for the parity +
ALCAM-recovery test, (b) confirm the data-sharing route (a note to the corresponding author vs. a data
request form / DUA / IRB determination — we'll complete whatever UH requires), and (c) agree the
feasibility question, baseline, success criteria, and deliverable.

We're grateful for the discussion and glad to shape the pilot around what would be most useful to the
Lab's own program.
