# Providing a Target to a Hospital Partner — Exact Package Contents & Collaboration Model

**Date:** 2026-09-30
**Answers:** *If we provide a target to them, (1) what specifically do we hand over, and (2) how exactly does the collaboration run?*
**Companion to:** `20260930_FIRSTINCLASS_TARGET_PEPTIDE_COLLAB_PROTOCOL.md` (the stage-gated process) and the two survey briefs + roster doc. This doc is the **tangible layer**: the actual deliverable package and the deal mechanics.

> **Core principle.** "Providing a target" is **not handing over a gene name.** It is delivering a **decision-ready package**: a credentialed target + a designed molecule to hit it + a pre-registered validation plan with objective pass/fail criteria. The partner should be able to go straight to the bench without doing any discovery work themselves — that is what makes us worth collaborating with and keeps the IP ours.

---

## 1 · What we hand over — the Target Provision Package

Four bundled deliverables (A–D). Concrete artifacts and formats below.

### A · Target Dossier — *the target itself, credentialed*
| Item | Exact content / format |
|---|---|
| **Target identity** | Gene symbol + **UniProt accession** + isoform; the **specific site** we drug (residue ranges of the epitope / PPI interface / pocket), and the **binding partner** if it's a PPI (e.g. "block IL-23 p19 ↔ IL-23R interface, residues …") |
| **Causal-evidence dossier** | Human-genetic support with the actual evidence and tier: GWAS locus → **L2G score**, **colocalization** (eQTL/pQTL PP.H4), **cis-MR** estimate + direction, rare-variant burden if any; **direction of effect** call (inhibit vs activate) with justification; disease + **cell-type/state** specificity; expression evidence |
| **Null-model controls** | Degree/annotation-depth null + matched-annotation subset results (so a network-centrality artifact is not mistaken for signal) |
| **First-in-class justification** | ChEMBL + clinicaltrials.gov + patent scan showing **no approved / advanced-clinical drug of any modality** against this mechanism; label **FIC-target** (novel biology) vs **FIC-modality** (known target, no peptide) |
| **Druggability / why-a-peptide** | The structural basis: experimental **PDB ID** if it exists, else an **AlphaFold/co-folded model** with confidence (pLDDT/PAE); the defined hotspot; why small molecules/antibodies fail here (flat interface / intracellular / undruggable pocket) |
| **Predicted mechanism-of-action** | What blocking (or engaging) the site should do phenotypically — the testable hypothesis the wet-lab will confirm |

### B · Molecule Package — *the peptide(s) we designed against it*
| Item | Exact content / format |
|---|---|
| **Designed candidates** | A **ranked, diverse panel** (typ. **8–24** macrocycles) — each with: linear/cyclic **sequence**, explicit **non-canonical chemistry** (N-methyl positions, D-amino acids, **staple/cyclization** type & positions), **SMILES + HELM** notation, and **3D coordinates (PDB/mol2)** |
| **Predicted binding pose** | Docked/modeled complex of each candidate against the target epitope (coordinates + interface contact map) |
| **Property vector (per candidate)** | Predicted **affinity** (docking → MM-GBSA → FEP ΔG on finalists), **membrane permeability** (ΔPSA3D), **synthetic accessibility**, **selectivity/off-target & safety** flags, **developability**, each with an **uncertainty** estimate and a **measured-vs-predicted provenance tag** |
| **Controls** | ≥1 **scrambled / non-binder** and (if available) a **known reference binder** (e.g. R9AP19–30 for the EBV-entry case) so their assay has positive + negative controls |
| **Synthesis spec (for the CRO)** | Exact chemistry per candidate, target **quantity** (e.g. 5–10 mg), **purity** (≥95% HPLC), salt/counter-ion form, QC deliverables (HPLC + MS) — so the peptide CRO can quote and make it directly |

### C · Validation Playbook — *pre-registered assays + objective pass/fail*
| Item | Exact content / format |
|---|---|
| **Assay cascade** | The specific assays mapped to this target, in order: **binding** (SPR/BLI/ITC — including the exact **protein construct** they need to express/purchase), **specificity/competition**, **functional** (named cell line / organoid / PDX / primary-cell reporter), **in-vivo** (named disease model) |
| **Pre-defined success criteria** | Numeric thresholds fixed *before* the experiment: e.g. **KD < 100 nM** by SPR; **functional IC50 < 1 µM**; **≥50% blockade** in the reporter; a specific in-vivo endpoint. "Validated" is objective, not argued after the fact |
| **Design of experiment** | Replicates, dose range, controls, blinding where relevant, and the exact **readouts** |
| **Data-return spec** | Raw + processed formats we need back (SPR sensorgrams, dose–response tables, flow FCS, images) to feed our loop |

### D · Data-return & loop spec — *how results come back to us*
- A **structured results template** (per-candidate: measured affinity, functional value, pass/fail vs criteria, raw files) so every result — **success and failure** — is machine-ingestible and **DPO-retrains our generator**. This is the moat; it must be contractually ours to use for model training (see §3).

**Deliverable format:** a single versioned **dossier PDF/HTML + a data folder** (structures, SMILES/HELM, property tables, synthesis spec, validation playbook). One artifact, decision-ready.

---

## 2 · How the collaboration runs — the operating model

### 2.1 Roles (who does what)
| | **Us (BioMate + Chinese entity)** | **Partner hospital** | **Peptide CRO (3rd party)** |
|---|---|---|---|
| Target ID + credentialing | ✅ | reality-check on biology | — |
| Peptide design + in-silico verify | ✅ | — | — |
| Synthesis | fund + spec | — | ✅ make + QC |
| Target/binding/function/in-vivo validation | define + fund | ✅ **run** | — |
| Clinical translation (Phase-I) | support | ✅ **run** (their trial unit) | — |
| Loop: ingest data → retrain | ✅ | supply data | — |

### 2.2 The exact sequence (artifacts exchanged)
1. **CDA/NDA signed** → we share a 1-page **target teaser** (target class + why-a-peptide + proposed validation), *not* the full dossier.
2. **Scientific alignment call** → partner confirms the biology is credible and the proposed assays are runnable in their lab (their domain gate).
3. **Collaboration agreement executed** (SRA/RCA + MTA + IP terms — §3) → we deliver the **full Target Provision Package (A–D)**.
4. **We fund + place the CRO synthesis order** → CRO ships QC'd peptides **to the partner** (MTA covers the transfer).
5. **Partner runs the Validation Playbook (C)** against the pre-registered criteria → returns the **structured results (D)**.
6. **We ingest results** → DPO-retrain → deliver a **round-2 optimized panel** (loop turns).
7. **Go/no-go at each gate** → advance to in-vivo → IND-enabling → **Phase-I via their unit**.

### 2.3 Agreements needed (in order)
- **CDA/NDA** — before any disclosure.
- **MTA (Material Transfer Agreement)** — governs the peptide going to them (and any of their samples/reagents used); specifies permitted use, no reverse-engineering, no onward transfer.
- **Sponsored Research Agreement (SRA)** or **Research Collaboration Agreement (RCA)** — the master deal: scope, deliverables, funding, **IP allocation**, publication, data rights, term.
- **HGRAC structuring** — the collaboration is **held by our Chinese entity domestically**; patient samples/data stay in-country; only de-identified target biology + assay results cross the border. Confirm exact structure with counsel (mitigated, not a blocker — see engagement plan).

### 2.4 Money (who pays for what)
- **We fund:** target ID + design (our compute), and typically the **CRO synthesis** (**~$15–25k / IP-clean round**).
- **Validation cost:** either (a) we sponsor it (fee-for-validation — cleanest for IP), or (b) partner cost-shares in exchange for co-authorship / milestone participation. Recommend **we sponsor round-1** to keep IP unambiguous and the ask small.
- **Downstream:** in-vivo, GMP, tox, Phase-I are larger — staged and milestone-gated, funded per the SRA (often shared or grant-supported on their side).

### 2.5 Indicative timeline (per target, round 1)
| Phase | Owner | Time |
|---|---|---|
| CDA → alignment → SRA/MTA | both | 3–8 wk (legal is the long pole) |
| Deliver package (A–D) | us | already in hand at signing |
| CRO synthesis | CRO | 4–8 wk |
| Binding + functional validation | them | 2–4 mo |
| Round-2 optimized panel | us | 2–4 wk after data |
| In-vivo efficacy | them | 3–6 mo |

### 2.6 Decision gates (what happens on each outcome)
- **Binding fails** → results feed DPO; redesign; no wet cost beyond the one round.
- **Binds but no function** → interrogate MOA/target hypothesis; may re-nominate epitope.
- **Function confirmed** → advance to in-vivo; trigger next SRA milestone.
- **Target hypothesis wrong (Stage-4 causality)** → back to target ID; **this is why a validated "anchor" target runs in parallel** so there's always a live wet program.

### 2.7 IP & data flow (the crux)
- **Composition-of-matter** on every peptide = **ours** (we designed it).
- **Method-of-treatment (target × peptide) use IP** — structured so target nomination + design origin is ours; co-generated validation data can be jointly owned **with a license-back**, but **generator-training rights on that data must be ours** (the moat).
- **Inventorship** defined up front: target-ID + design = our inventors; validation may earn co-inventorship on the *use* claim per contribution.
- **Publication** — partner gets academic authorship on the validation; we keep method/stack internal (state *what* we deliver externally, not the tool recipe).

---

## 3 · Collaboration-structure options (pick one per target)

| Structure | How it works | IP | Best when |
|---|---|---|---|
| **A. Fee-for-validation / sponsored research** *(recommended for target #1)* | We pay them (or the CRO) to run the pre-registered validation; we own the results + IP | Cleanest — **ours** | First target; keep IP unambiguous; fast |
| **B. Joint research collaboration** | Shared work + cost; co-authorship; co-IP on use claim with license-back to us | Shared use, our platform | When they contribute unique target biology / samples heavily |
| **C. Staged option / milestone** | They validate; we hold an **option** to advance; milestone payments on success | Ours, with milestones to them | When the target is theirs-nominated or they want upside |

**Recommendation:** lead with **A** for the first (anchor) target to prove the loop with clean IP, then move differentiated first-in-class programs into **C** (milestones align incentives on the upside).

---

## 4 · Two worked examples (exactly what "providing a target" looks like)

### Example 1 — Soochow (autoimmune): provide **IL-23 / IL-23R** *(the causal anchor; a FIC nomination follows the same format)*
- **A Target Dossier:** IL-23 (p19 subunit, UniProt Q9NPF7) ↔ IL-23R interface; causal evidence = their own **MRL/lpr IL-23p19-blockade reversed nephritis** (PMID 40620119) + IL-23R human-genetic support in autoimmunity; direction = **inhibit**; FIC-modality (peptide vs the marketed antibodies — differentiate on a macrocycle's tissue/PK profile).
- **B Molecule Package:** 8–16 macrocycles designed to the p19/IL-23R interface; SMILES/HELM + 3D poses; property vector; **anti-IL-23 mAb epitope-peptide as reference control**.
- **C Validation Playbook:** **IL-23–IL-23R competition ELISA/SPR** (KD < 100 nM); cell-based **IL-23-driven STAT3/IL-17 reporter** (IC50 threshold); then **head-to-head vs their mAb in the same MRL/lpr readout** (proteinuria, anti-dsDNA, Th17/Treg). Success criteria pre-registered.
- **Contacts:** Liu Cuiping (wet-lab) / Chang Xin (bridge) / Wu Jian (authority).

### Example 2 — SYSUCC (oncology): provide **R9AP ↔ EBV gH/gL** *(entry-blocking macrocycle)*
- **A Target Dossier:** R9AP (host receptor) ↔ EBV gH/gL; causal evidence = Zeng-lab **Nature 2025** (KO/KD + a functional blocking peptide R9AP19–30, Kd 3.27 nM); direction = **block entry**; FIC (no approved EBV-entry peptide). Structure: R9AP–gH/gL has no crystal yet → offer **joint structure determination**; EphA2 co-target has **PDB 7CZE** for immediate conditioning.
- **B Molecule Package:** macrocycles mimicking/competing the R9AP19–30 interface; **R9AP19–30 itself as the reference positive control**; scrambled negative; property vector incl. permeability (extracellular target → low bar).
- **C Validation Playbook:** **BLI vs gH/gL** (KD target); **EBV-entry blockade assay on primary NPECs + B cells** (their existing assay; % inhibition threshold); advance to NPC organoid/PDX.
- **Contacts:** Zeng Mu-Sheng (owns the franchise + assays) / Zhong Qian, Xu Miao (working level) / Zhang Li, Xu Rui-Hua (clinical translation).

---

## 5 · Launch checklist
1. Pick the **target + partner** (recommend an anchor target under structure **A** first).
2. Generate the **Target Provision Package (A–D)** — most of the dry work is already specified in the protocol doc.
3. Get **CDA signed** → send the 1-page teaser → alignment call.
4. Execute **SRA + MTA** (Chinese entity as contracting party; HGRAC-clean).
5. Fund + place **CRO synthesis**; ship to partner under MTA.
6. Partner runs the **Validation Playbook**; returns structured data.
7. **Ingest → retrain → round 2**; advance on the gates.

---

*One line for the partner: "We give you a credentialed first-in-class target, a ready-to-test designed macrocycle against it, and a pre-agreed pass/fail validation plan — you run the assay you already have, and we optimize from your data. You get authorship, a validated asset in your pipeline, and a clinical program for your unit; we own the molecule."*
