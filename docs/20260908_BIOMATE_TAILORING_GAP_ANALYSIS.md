# BioMate Tailoring Gap Analysis — Pharma & Hospital Researcher Needs vs. Where We Are

**Date:** 2026-09-08
**What this is:** the synthesis the founder asked for — a *categorized* survey of what pharma R&D scientists and hospital/translational researchers actually need, cross-mapped against a *careful, anti-under-claim* audit of BioMate's real capabilities, to show exactly where BioMate is well-tailored vs. where it must be filled.
**Inputs:** (1) cited needs survey (deep research, adversarially verified — `tasks/wr05fetdh`); (2) grounded capability audit (`docs/20260908_BIOMATE_TAILORING_AUDIT.md`, direct file enumeration: 3,758 `.nf`, 236 verified-executable, 46 real drug-dev Python modules); (3) competitive landscape (`docs/20260908_AI_BIO_COMPETITIVE_LANDSCAPE_AND_LLM_STRATEGY.md`).

> **Honesty contract:** severities and "what good looks like" are from cited external evidence (some percentages are small/vendor samples — attributed, not universalized). BioMate maturity is stated truthfully, including stubs, untested areas, and fabrication landmines.

---

## 1. The headline (read this first)

**BioMate's fit is genuinely strong where it matters most — but its two highest-value strengths each have a reachability gap, and its core differentiator (trust) has an integrity risk that must be closed.**

1. **The #1 pharma need is multi-objective optimization** (potency + PK + ADMET *simultaneously*, with explicit *and* implicit med-chem criteria). **BioMate has a real GP + expected-hypervolume MPO/DMTA engine in code — but it is not wired to the product** (no API/executor/UI). → **Wiring it is the single highest-leverage tailoring fix.**
2. **The #1 hospital need is turning NGS into an actionable clinical report** (ACMG/oncogenicity classification, reconciling many tools/knowledgebases). **BioMate does variant *calling* but clinical *interpretation + reporting* is absent.** → **The key hospital-fit build.**
3. **The most-neglected cross-cutting needs — non-bioinformatician usability (only ~21% of tools serve novices) and non-negotiable provenance/audit (EU AI Act, 21 CFR Part 11, ICH E6R3) — are exactly BioMate's conversational front door + hash-chain audit / QC-gate design.** This is a real, defensible fit-advantage over the field.
4. **BUT** — that trust advantage is undercut by **fabrication landmines** (`bispecific_antibody_design/main.nf:171` fabricates CDR sequences via `random.choices`; the `#19` multiome `random.gauss`; ~92 `.nf` touch RNG) and **regulatory fail-opens** (`ich_corpus` returns grounded=True when PDFs are missing). A platform that sells "auditable/transparent" and is caught fabricating loses the exact thing that differentiates it. **Closing these is not optional.**

5. **A distinct high-value category surfaced from the partner: the scholarly knowledge-work loop** — research → literature survey → manuscript writing → slides → revision. This is the **daily currency** of hospital KOLs/academic clinicians and pharma medical-affairs/regulatory writers, it is **where LLMs are genuinely strong today** (high need × high adoption × high feasibility — a rare corner where all three align), and BioMate already owns the two *hard* pieces: a **real, source-verified literature engine with a working anti-confabulation guard** and a **regulatory-grade generate→audit→revise writing engine** (IND §2.6 CTD, DOCX). The gaps are productization (multi-paper review, scientific-manuscript sections, slide generation, generic "review my draft"), not the hard science. See the dedicated category below.

**Net:** BioMate is *tailored to the right needs* but under-delivers on reachability (wire what's built) and must *harden its integrity* to keep its differentiator credible.

---

## 2. Category-by-category: need → what good looks like → BioMate now → gap → fill priority

**Maturity:** 🟢 production-tested · 🟡 built, untested/unwired · 🟠 partial/stub · 🔴 fabricates/absent

### Pharma R&D
| Need (severity) | What good looks like | BioMate now | Gap → Fill priority |
|---|---|---|---|
| **Multi-objective lead optimization** (HIGH — the dominant need) | User-declared Pareto/MOO over potency+PK+ADMET incl. implicit med-chem constraints | 🟡 **Real GP+hypervolume MPO engine (`bayesian_optimizer.py`) — but no API/executor/UI** | **Wire the closed MPO/DMTA loop to the product — P0, highest value-to-effort** |
| Instrument translational/Phase-II risk (HIGH — the *value* gap; AI hasn't moved Phase-II ~40%) | MoA, biomarker, patient stratification tied to the candidate | 🟢 `drug_moa_rnaseq`, stratification, biomarker paths | Package MoA/biomarker/stratification as the value story — P1 |
| ADMET / safety / tox (HIGH; low adoption b/c data scattered) | Validated multi-endpoint + gated | 🟢 ADMET-AI/Chemprop/DeepPurpose + **QC auto-loop gate** | **Prove the auto-loop gate LIVE on real dev data (never fired) — P0** |
| Structure prediction + docking + FEP (HIGH; *high* adoption task) | AF3-class + docking + RBFE | 🟢 Boltz-2/Chai-1/AF, GNINA/Vina/DiffDock/Glide, OpenFE ~1.73 kcal/mol | Strength — keep 🟢; surface it |
| Target ID/validation (MED; high adoption) | Evidence-linked targets | 🟢/🟡 TxGNN, research agent, pocket detection | Solidify evidence linkage — P2 |
| Synthesizability / retrosynthesis | Real routes + in-loop SA gate | 🟢 aizynthfinder; 🟠 SA proxy | Promote SA→RDKit + in-loop gate — P2 |
| PK/PD/PBPK | Validated vs reference | 🟢 PBPK vs 108-drug ref set | Strength |
| **Generative de novo** (MED adoption — data scattered) | Trained target-conditioned generator | 🔴 **BRICS enumeration mislabelled REINVENT4** | Real generator (self-host GenMol/etc.) — P1 (real gap, but lower-adoption need) |
| Regulatory / IND (HIGH; mandated) | ICH M4 CTD, audit, e-sign | 🟢 **deepest category** (ind_assembly, MRSD, phase-gating, 21 CFR Part 11) | **Close fail-opens (ich_corpus grounded-when-empty; non-FDA=not_implemented) — P0** |
| Data provenance / ELN / collaboration | Reproducible, audited, multi-team | 🟢 hash-chain audit, provenance; 🟡 ELN connector | Wire ELN + multi-party — P1 |
| Modality coverage | small-mol/Ab/bispecific/PROTAC/peptide/siRNA | 🟢 small-mol; 🟡 antibody(ProteinMPNN); 🔴 **bispecific fabricates CDRs**; ❌ PROTAC/peptide | **Fix bispecific fabrication; add PROTAC/peptide — P0 (integrity)/P2** |

### Hospital / Translational
| Need (severity) | What good looks like | BioMate now | Gap → Fill priority |
|---|---|---|---|
| **NGS → actionable clinical report** (HIGH — the central need) | ACMG/oncogenicity auto-classification, public-DB integrated, transparent, on-prem | 🟠 variant *calling* yes; **clinical *interpretation + report* absent** | **Build ACMG/oncogenicity interpretation + report generator — P0 (key hospital fit)** |
| MTB workflow consolidation (HIGH; fragmented, manual, cross-site inconsistent) | One reconciled workflow over many tools/knowledgebases | 🟡 conversational orchestration is the right shape | Wire the NGS→report chain into the front door — P0 |
| Open-source / on-prem / public-DB / transparent (HIGH — *required*, not extra) | Self-deployable, DB-integrated, inspectable | 🔴 cloud-only today | On-prem/air-gap + public-DB integration — P0 (also the China requirement) |
| Bulk RNA-seq / DE | End-to-end, reproducible | 🟢 **one of two truly-green journeys** | Strength |
| Single-cell & spatial | Validated e2e | 🔴 **indexed-only, no real-run evidence** | Prove e2e — P1 |
| Multi-omics integration | Real integration + QC | 🟡 MOFA2/SNF built | Prove e2e — P1 |
| Patient stratification / biomarker | Responder signatures | 🟡 built paths | Package for hospital — P1 |
| Cohort / survival | KM/Cox | 🟡 survival workflow present | Verify — P2 |
| Proteomics / metabolomics | Validated e2e | 🔴 indexed-only | Prove e2e — P1 |
| CryoEM SPA | End-to-end | 🟢 **the other truly-green journey** | Strength |

### Cross-cutting adoption levers (govern adopt-vs-reject)
| Need (severity) | BioMate now | Gap → Fill priority |
|---|---|---|
| **Usability for non-bioinformaticians** (HIGH; only ~21% of tools serve novices) | 🟢 **conversational front door + SSE + hybrid prefill** — a genuine fit-advantage | Keep + the data-centric UI (cold-start, dataset object) — P1 |
| **Data quality / de-siloing** (HIGH; #1 reason AI pilots fail; data-integration the #1 PI gap @89%) | 🟡 perception-at-ingest built (unwired); source registry fragmented (chat sees 20 of 60+) | **Wire perception-at-ingest + unify source registry — P1** |
| **Provenance / audit** (HIGH; legally mandated) | 🟢 hash-chain, 21 CFR Part 11, QC gates | **Harden (close fail-opens) + prove — P0** |
| **Clinical-workflow fit** (HIGH; misfit → rejected regardless of merit) | 🔴 no hospital-system integration | HIS/LIS/sequencer/ELN connectors — P0 (China) |
| **Reproducibility/transparency** (HIGH; only ~6% of AI-discovery studies release code) | 🟢 auditable design — but ⚠️ fabrication landmines undercut it | **Fabrication sweep (bispecific/#19/RNG triage) — P0 (integrity)** |
| **Chinese localization / language** | 🔴 English-only | Chinese UI + domestic on-prem LLM — P0 (China) |

### Scientific knowledge work / scholarly communication (the daily-currency loop)
*Why it ranks high: highest-frequency touchpoint for this exact audience (clinicians publish; medical-affairs & regulatory writers write daily); the one major category where LLM feasibility is high TODAY; and it closes BioMate's own loop — a run already produces results + provenance, so drafting the paragraph/slide from it is a short step with every number traceable.*

| Need (severity) | What good looks like | BioMate now | Gap → Fill priority |
|---|---|---|---|
| **Literature search / evidence retrieval** (HIGH; universal) | Cited answers from real sources; *never* invents citations | 🟢 **REAL** — `research_agent.py` + `literature_clients.py` hit PubMed/PMC/arXiv/Semantic Scholar/OpenAlex, inject live DB facts (Ensembl/ClinVar/GTEx…), **verify every DOI/PMID against NCBI and abstain on zero retrieval** (the rare, defensible anti-confabulation property) | Residual = **retrieval recall (~16.6%)**: it *misses/abstains*, does not fabricate. Fill = improve recall (query decomposition already in; keep pushing) — P1 |
| **Literature survey / multi-paper review** (HIGH for academics) | Standalone structured review / mini meta-analysis | 🟠 **PARTIAL** — synthesizes multi-paper evidence into a *Q&A answer*; `literature_survey` intent is only a label, no review-generation workflow | **Extend research agent → structured review output — P1** |
| **Manuscript / paper writing** (HIGH) | Draft methods/results/abstract from a run, cited | 🟢 **REAL for IND** (`ind_assembly.py`: ICH M4 §2.6 CTD, multi-backend LLM, RAG few-shot, DOCX via pandoc, generate→audit→revise) · 🔴 **absent for scientific manuscripts** | **Generalize the IND engine → scientific-manuscript sections from run provenance — P1 (high value, engine already exists)** |
| **Slide / deck generation** (MED–HIGH; conferences, tumor boards) | Auto-deck from a run/result, editable | 🔴 **ABSENT** as a product feature | Build slide generation (pandoc/pptx infra is trivial; value = auto-populate from run + provenance) — P1 |
| **Document revision / review** (MED–HIGH) | "Review/critique my draft" with tracked, sourced feedback | 🟢 **REAL for IND narratives** (audit→Gemini-fallback→recheck loop) · 🔴 **no generic user-facing review** | **Generalize the audit/revise loop → "review my draft" — P2** |

*Strategic note: BioMate's anti-confabulation architecture (verify-or-abstain, honest-fail) is itself the **differentiator** for this audience — "writing that shows verified sources and says when it doesn't know," which is exactly what a rigorous clinician/regulator wants and what generic chatbots don't provide. This is the same integrity discipline as the drug-dev side; keep the two consistent.*

---

## 3. Prioritized fill roadmap

**P0 — do first (highest value / integrity-critical):**
1. **Wire the MPO/DMTA optimization engine to the product** (API + executor + UI). Turns BioMate's #1 latent strength into its #1 tailored capability.
2. **Clinical variant interpretation + report generator (ACMG/oncogenicity)** — the key hospital-fit build; consolidates the fragmented MTB workflow.
3. **Prove the ADMET/QC auto-loop gate live** on real dev data — the signature moat has never fired.
4. **Integrity pass:** fabrication sweep (fix `bispecific` CDR fabrication, `#19` multiome, triage the ~92 RNG `.nf`) + close regulatory fail-opens (`ich_corpus` grounded-when-empty; non-FDA render). *Non-negotiable — it protects the trust differentiator.*
5. **On-prem + Chinese localization + hospital-system integration** (the China partnership build; also the "transparent/self-deployable = required" hospital need).

**P1:**
6. Wire perception-at-ingest + unify the source registry (data-quality/de-siloing — the #1 pilot-failure cause).
7. Real end-to-end evidence for single-cell/spatial/proteomics/metabolomics/multi-omics.
8. Real trained target-conditioned generator (fills the generative gap; note generative is a *lower-adoption* need, so P1 not P0).
9. Package MoA/biomarker/stratification as the translational-value story.
10. **Scholarly knowledge-work loop** — the hard pieces already exist (verified literature engine; IND generate→audit→revise engine), so this is high-value/low-risk productization: (a) multi-paper **literature-survey/review** output on the research agent; (b) **generalize the IND narrative engine → scientific-manuscript sections** drafted from run provenance (cited, traceable); (c) **slide generation** auto-populated from a run.

**P2:** PROTAC/peptide modalities; synthesizability in-loop; target-evidence linkage; survival verification; **generalize the IND audit/revise loop → generic "review my draft."**

---

## 4. Strategic read for the partnership & product

- **Lead the story with what's real and needed:** regulatory/audit depth, structure+docking+FEP, ADMET+QC-gate, PBPK, and the conversational front door for non-bioinformaticians — these are strong *and* address top, under-served needs.
- **The two P0 builds (wire MPO; clinical variant interpretation) are exactly where "broad platform" becomes "tailored to how they work."**
- **Do not sell "auditable/transparent" until the integrity pass is done** — the fabrication landmines would fail exactly the rigorous, provenance-driven users who most value the pitch.
- The hospital "open-source/on-prem/transparent = required" finding and the China 国产化 requirement are the *same* requirement — one build serves both.

---

## 5. Honesty / provenance
- Needs severities cite peer-reviewed/industry 2026 sources; small/vendor-sample figures (e.g. ~21% novice-targeting, ~6% code-release, 89% PI data-integration gap) are attributed, not universalized. Adoption varies by task (high for clean-data structure/lit/target-ID; low for generative/biomarker/ADMET).
- BioMate maturity from direct file audit; stubs, untested (🔴 indexed-only) categories, and fabrication landmines are stated, not hidden.
- Supersedes the market-claims of the 2026-04 moat briefing; complements `DRUG_DEV_ABILITY_MAP_V2` and the tailoring audit.
