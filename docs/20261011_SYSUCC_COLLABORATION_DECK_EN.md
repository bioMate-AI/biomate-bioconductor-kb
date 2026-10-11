---
marp: true
theme: default
paginate: true
title: BioMate × SYSUCC — Multi-Site Cyclic-Peptide Immuno-Oncology Collaboration
---

<!--
Audience: SYSUCC leadership + international-collaboration office + GI/IO PIs.
Purpose: introduce BioMate's AI cyclic-peptide IO platform, what we are working on, and the potential SYSUCC
         multi-site connection.
FRAMING (corrected 2026-10-11): the cyclic peptide IS the therapeutic (direct-acting macrocycle) —
  αvβ6 ANTAGONIST (blocks integrin → latent-TGF-β activation → immunosuppressive PDAC TME) + PD-L1 checkpoint
  inhibitor. It is NOT a radioligand/theranostic — NO Ga-68 / Lu-177 / nuclear medicine / radiochemistry.
EXTERNAL MESSAGING RULES (founder directive 2026-10-11):
  - DO NOT mention ACT / accelerator / CPRIT / RADIATE.
  - DO NOT reveal our status with MD Anderson. MD Anderson appears ONLY as (a) SYSUCC's own public sister-
    institution partner and (b) one of the Texas Medical Center institutions — never as "our site/partner."
  - US site = generic "our planned US clinical/translational site within the Texas Medical Center."
  - Capability framing: WHAT we deliver, not internal tools/methods/model/infra.
  - Honesty: lead candidates are DESIGNED + in synthesis/characterization — NOT confirmed binders.
Source of truth for facts: docs/20260930_HOSPITAL_SURVEY_SYSUCC_CYCLICPEPTIDE_COLLAB.md (UPDATE 2026-10-11).
Render: scratchpad/build_sysucc_deck.py (python-pptx) → docs/20261011_SYSUCC_COLLABORATION_DECK_EN.pptx
-->

# BioMate AI
### AI-designed cyclic-peptide therapeutics for immuno-oncology

**Our platform · what we are working on · a potential multi-site collaboration**
BioMate AI (Houston) · Sun Yat-sen University Cancer Center

*Discussion deck · October 2026*

---

## Who we are

**BioMate AI** — a Houston-based therapeutics company developing **AI-designed cyclic-peptide (macrocycle) drugs for immuno-oncology**.

- We **design and computationally prioritize** candidate peptide drugs, assemble the supporting translational evidence, and work with **clinical and experimental partners for validation and development**.
- Our focus is **tumor-selective immuno-oncology** — targets that antibodies and small molecules serve poorly.
- We operate a **closed design → validate → learn loop**: each experimental result sharpens the next design cycle.

> We bring the **design and computational engine**; our partners bring **target biology, patient data, wet-lab validation, and the clinical path**.

---

## The clinical white-space we address

- **Tumor-selective targeting is hard.** Many validated oncology targets are cell-surface receptors or protein–protein interfaces; off-tumor activity drives toxicity, and the most important interfaces are often poorly served by existing modalities.
- **Antibodies and small molecules each fall short here.** Antibodies are large and reach some compartments poorly; small molecules struggle to cover large, flat interaction surfaces.

> Cyclic peptides occupy the gap between them — large enough to grip a flat interface with high selectivity, small enough to be developable. The bottleneck is **designing the right one**.

---

## What we deliver — the platform (capability view)

1. **Target assessment** — structural and biological suitability for a cyclic-peptide approach.
2. **Generative design** — novel cyclic/macrocyclic binders proposed against the target interface.
3. **Multi-objective prioritization** — ranked for **affinity, selectivity, stability/developability, and safety** *in silico*.
4. **A filtered candidate shortlist** — ready for synthesis and experimental testing.
5. **Closed-loop learning** — experimental results feed back to improve the next design round.

*We describe what the platform delivers, not how it is built internally.*

---

## What we are working on — our lead program

**Two direct-acting cyclic-peptide therapeutics — the peptide itself is the drug (not a delivery vehicle).**

- **αvβ6 integrin (lead, PDAC)** — a cyclic-peptide **antagonist** that blocks αvβ6. αvβ6 activates latent **TGF-β** and shapes the immunosuppressive pancreatic-cancer microenvironment; **blocking it is the therapeutic mechanism**. αvβ6 is highly and selectively expressed in PDAC and many epithelial carcinomas, sparing normal tissue.
- **PD-L1 (checkpoint)** — a cyclic-peptide **checkpoint inhibitor** that blocks PD-L1 directly: a tumor-selective approach to the most validated IO axis.

> **Honest status:** our lead candidates are **designed and now entering synthesis and binding characterization**. We do **not** yet have confirmed binders, and we present them as such.

---

## The US site — clinical & wet-lab validation

Our program is designed to run across **two sites**. The **US site** sits within the **Texas Medical Center** (Houston) — the largest medical complex in the world.

- **Clinical & translational validation** — patient-derived organoid and in-vivo models.
- **Experimental binder validation** — biophysical/display confirmation that designed peptides bind and block their target.
- **Functional & IO readouts** — target-blockade and immune-microenvironment assays.
- **A Phase-I clinical on-ramp** within a leading US cancer-center network.

> The US site provides the clinical and wet-lab foundation — and a second site makes the program multi-national from the start.

---

## Why a second site — and why SYSUCC

- **Independent, multi-ethnic validation** of targets and candidates across two patient populations.
- **A dual regulatory path** — FDA (US) and NMPA (China) — opening both markets from the start.
- **Greater patient access and cohort depth** for selection and biomarker work.
- **Complementary wet-lab and clinical capacity** across two world-class centers.

> **SYSUCC** — the **#2 oncology center in China**, ~1,600 beds, the State Key Laboratory of Oncology in South China, and an NMPA-certified clinical-trial center — can anchor the program's second site.

---

## SYSUCC already partners with leading US cancer centers

- **SYSUCC and MD Anderson have been sister institutions since 2003**, with an active **Sister Institution Network Fund (SINF)** channel for collaborative oncology research.
- In 2015, MD Anderson received a top Chinese science & technology award — **nominated by its sister institution, SYSUCC**.
- SYSUCC also holds Western research ties with **Karolinska Institutet** (joint lab, 2004) and **Fred Hutchinson Cancer Center** (MoU, 2017).

> A US–China translational program fits a model SYSUCC has run for two decades — building on, not starting, its international collaborations.

---

## SYSUCC strengths we would build on (verified)

- **GI / pancreatic oncology** — Pancreaticobiliary/Gastric/Colorectal/Liver Surgery + Medical Oncology; **≥7 PDAC trials** (incl. a KRAS-G12V TCR-T Phase I); **Prof. Feng Wang**, Asst. President & Director of Medical Oncology — directly matched to the αvβ6 / PDAC lead.
- **Checkpoint immuno-oncology** — pivotal anti-PD-1 (camrelizumab) trial leadership, with receptor-occupancy biomarker work — matched to the PD-L1 program.
- **Patient-derived organoids** — a co-led **NPC organoid living biobank** (Ann Transl Med 2022) plus a broad multi-tumor organoid publication record (NPC/colorectal/gastric/lung/breast/liver) — the wet-lab engine that validates designed peptides.
- **Data & biobank** — biobank (est. 2001) scaled to **~6 million samples**; large single-cell/spatial & multi-omics datasets.
- **Clinical path** — NMPA national anticancer-drug clinical-trial center + GCP early-phase capability.

<small>Honest note: SYSUCC's organoid use is verified in print; a **named catalog-scale organoid/PDX core** and **PDX-specific capacity** are to be confirmed directly.</small>

---

## The αvβ6 program extends naturally to SYSUCC's tumors

- αvβ6 is expressed across **epithelial carcinomas** — pancreatic, head & neck, and others — so the same αvβ6 antagonist applies well beyond PDAC, into tumor types central to SYSUCC.
- SYSUCC's **GI/pancreatic and head-&-neck patient volume and organoid platforms** make it an ideal site to validate the αvβ6 program across multiple indications.
- One drug therefore creates value at **both sites' priority tumor types** — PDAC/GI in the US, and SYSUCC's high-volume epithelial tumors in China.

> The lead target is chosen so the **same molecule creates value at both sites**, not two disconnected programs.

---

## The multi-site design — US site × SYSUCC

| Capability | US site (Texas Medical Center) | China site (SYSUCC) |
|---|---|---|
| **Design & prioritization** | BioMate (shared) | BioMate (shared) |
| **Patient cohorts** | TMC PDAC & IO cohorts | GI/PDAC (≥7 trials) + checkpoint |
| **Wet-lab validation** | Organoid / in-vivo models | Organoids (NPC biobank + multi-tumor) |
| **IO / biomarker data** | TMC IO cohorts | anti-PD-1 + receptor-occupancy biomarker |
| **Clinical path** | US Phase-I on-ramp | NMPA anticancer-drug Phase-I center |
| **International context** | — | MD Anderson sister institution since 2003 |

> One candidate set, designed once, validated and advanced independently at two world-class sites.

---

## Proposed first joint project (Phase-0)

1. **Target lock** — confirm αvβ6 (and/or PD-L1) suitability on a SYSUCC-relevant tumor type.
2. **Prioritize** — use one cohort/stratification question from SYSUCC to focus the design.
3. **Design** — BioMate generates and ranks a candidate panel.
4. **Synthesize** — a third-party peptide CRO makes the panel (kept IP-clean).
5. **Validate** — SYSUCC runs binding + functional (target-blockade / IO) readout on its organoid/PDX and primary samples.
6. **Learn & co-author** — results refine the next design round; both sides publish.

> One scoped round per site keeps a "no" cheap and a "yes" decisive.

---

## Data & IP governance (built in from the start)

- **China Human Genetic Resources (HGRAC):** the collaboration is structured **domestically via our Chinese entity** — patient samples and raw data **stay in China**. Under the **2023 implementing rules, clinical/imaging/protein/metabolic data are outside the scope of "HGR data,"** easing AI/model collaboration; sample/raw-sequence work proceeds under a Sino-foreign cooperative-research approval.
- **In-country validation** — wet-lab runs in SYSUCC's own laboratories; only **de-identified results** inform the design engine.
- **Composition-of-matter IP** — the designed peptides are our composition; **co-generated data and publications are shared** on agreed terms.
- **Governance & ethics** — deployment and data terms are decided **with** SYSUCC's IT, ethics, and international-collaboration offices.

> We treat cross-border data governance as a **design requirement**, not an afterthought.

---

## What we would ask of SYSUCC

- **One tumor type and one cohort question** to focus the first design cycle.
- **One validation assay** on a designed candidate panel (organoid/PDX + binding/blockade).
- **A scientific advisor / co-PI** on the joint program.
- **Interest in a future Phase-I path** on the China side, once candidates are validated.

In return, SYSUCC gains **early access to a first-in-class cyclic-peptide IO modality**, **co-authorship**, a **US–China translational bridge building on SYSUCC's existing US ties**, and **platform access** for its own targets.

---

## Honest scope — what is ready, what is in development

- **Ready:** the **design and prioritization** engine and the **closed-loop** methodology.
- **In development / planned:** the **lead candidates are designed and in synthesis/characterization** — **no confirmed binder yet**; the clinical steps are being established. A named organoid/PDX core's scale at SYSUCC is **to be confirmed**.
- **Predictions are computational estimates**, confirmed only by experiment — which is exactly why multi-site wet-lab validation matters.
- We do **not** bring an analysis platform to replace SYSUCC's world-class internal bioinformatics; we collaborate strictly on the **drug-design modality**.

> We state plainly what is proven, what is planned, and what we would build together.

---

## Proposed next step

1. **A 30-minute introductory call** with SYSUCC's relevant PIs and the international-collaboration office (e.g., via Prof. Feng Wang / Prof. Xu Ruihua).
2. **A jointly-scoped Phase-0** on one tumor type and one validation assay.
3. **A collaboration framework** covering data governance, IP, and co-authorship.

**Toward a US–China multi-site cyclic-peptide immuno-oncology program.**

*Contact: Yaoyun Zhang — Founder & CEO, BioMate AI · yaoyun.zhang@biomate.ai · Houston, TX*

---

## Appendix A — An optional SYSUCC-native track

Beyond the αvβ6 / PD-L1 lead program, SYSUCC's own target biology offers a **second, parallel cyclic-peptide track** on targets SYSUCC uniquely owns:

- **EBV-entry receptor peptides** — e.g. **R9AP ↔ gH/gL** (Zeng/Zhong, *Nature* 2025; a functional blocking peptide is already reported) and **EphA2 ↔ gH/gL** (structure-enabled, PDB 7CZE) — causal, extracellular, peptide-precedented, and central to nasopharyngeal carcinoma.

This track is independent of the lead program and can run on SYSUCC's own timeline. *(Detail in the companion survey document.)*

---

## Appendix B — Sources & honesty notes

- SYSUCC facts are cited in the companion survey `docs/20260930_HOSPITAL_SURVEY_SYSUCC_CYCLICPEPTIDE_COLLAB.md` (UPDATE 2026-10-11): departments + GI/medical oncology (SYSUCC English site); PDAC trials (ClinicalTrials.gov); anti-PD-1 biomarker work (PMC9892498); NPC organoid living biobank (Ann Transl Med 2022, DOI 10.21037/atm-22-1076); sister-institution tie (MD Anderson newsroom); HGRAC 2023 rules (Ropes & Gray).
- A named catalog-scale organoid/PDX core and PDX-specific capacity at SYSUCC remain **to be confirmed** (flagged, not asserted).
- BioMate capability claims follow a ready / in-development labeling; lead candidates are **designed, not experimentally confirmed**.
- The SYSUCC ↔ MD Anderson sister-institution tie cited here is a verified institutional relationship **between those two centers, independent of BioMate**.
