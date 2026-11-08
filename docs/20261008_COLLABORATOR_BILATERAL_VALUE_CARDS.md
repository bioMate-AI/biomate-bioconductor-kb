# Collaborator Bilateral Value Cards — Per-Person "What They Host / Two-Way Value"

**Date:** 2026-10-08 · **Companion to** `docs/20261006_PHYSICIANS_FACULTIES_CROS_CLINICAL_DATA_TEXAS_AND_BEYOND.md`
(the who/where/warm-cold map) and `docs/20260930_ACT_APPLICATION_WORKING_PROTOCOL.md` §8 (the
~40-faculty MD Anderson/Texas collaborator map). **This document does not replace the map** — it adds, per
named person, (a) what they host (program / data / trial / core / cohort, cited), (b) the concrete benefit to
BioMate/ACT, (c) the honest benefit to them, and (d) the realistic first move.

**Honesty contract (inherited verbatim from the source map; strict):**
- **Warm/cold is preserved exactly** from the map — no cold entry is upgraded to warm. MD Anderson is
  **genuinely cold**; the SBMI trio is **affiliation-warm, outreach-not-confirmed**; Decker (BCM) is the
  warmest MDACC-*adjacent* path.
- **No invented people, emails, relationships, PMIDs, or data.** Every "hosts" fact carries either a repo
  path, an official profile, and a real pub/trial (PMID/NCT/DOI), **or** the token **"verify"** where it
  could not be confirmed this pass. Light web verification (accessed 2026-10-08) is marked `[web]`.
- **Every offered BioMate capability is labeled** `[E]` Evidenced / `[P]` Partial / `[A]` Aspirational,
  per `docs/20261005_SEGMENT_DEMAND_DIFFERENTIATION.md` §A.3/§B.3 and `internal_evidence_and_manuscripts.md`.
  Universal caveats apply to every card and are **not** restated per card: **no SOC 2 / HIPAA BAA / 21 CFR
  Part 11 / GxP certification; single-cell/spatial/proteomics/ChIP E2E unproven; no wet lab (predictions are
  estimates); IND §2.6.1 / CRO-compliance UX is commented out because it crashes `[A]`; no MGI/BGI connector;
  Chinese-native routing degraded.** Do not over-promise past these.
- **IP / data-ownership caveats are flagged inline** where a collaboration crosses one (fee-for-service cores
  own their output; CRO fee-for-service assigns IP to us; a modeling peer is also a competitor).

**Capability shorthand used below (with its honest label and source):**
- **Chat routing over the validated catalog** `[E]` — `biomate_session`, routing 0.965, 1,092 validated
  workflows on AWS Batch (`SEGMENT_DEMAND` §A.3).
- **Managed compute (AWS Batch GPU/CPU), spot** `[E]`.
- **QC auto-loop + AI findings + methods/report export** `[P]` — plumbing Evidenced; the *live
  fire-and-remediate* artifact is Evidenced only for the ADMET hERG hero demo, Partial elsewhere.
- **scGWAS (GWAS→cell-type)** `[P]` — chain id 72, smoke-tested on Crohn's × Tregs (`20260701_...` §Faculty 1).
- **Immune stratification / responder nomination** `[P]`→`[A]` — anti-TNF IBD responder AUROC 0.833 on real
  public GEO data `[P]`; M1–M5 endotyping not run E2E `[A]`; immune-LLM pair-nominator still in technical
  validation (`20260930_ACT_...` §6.6).
- **Cyclic-peptide / macrocycle target-ID (the ACT stack)** `[P]` — BoltzGen + PepGLAD-M2c (DockQ 0.437) +
  cyclic MM-GBSA + permeability GBM (R²~0.45) + GP-Pareto selector; a full single-round PD-L1 run is
  executable in silico (~$65–90/target); **no wet-lab-confirmed hit yet** (`20260930_ACT_...` §3).
- **ADMET/tox screening** `[E]` vs screening standard (bench 96.3%); **PBPK** `[P]`.
- **Instrument connectors** `[E]` (code, 10 connectors) / `[P]` (live instrument→run flow).
- **Co-authorship / methods support / student platform access** `[E]` (offer).

---

## 1 · Warm ties — UTHealth SBMI (founder's former department; lead the quarter)

> *Status for all three: **affiliation-warm**, outreach not yet confirmed initiated (`20261006_...` §A1,
> §E; `20261005_HOUSTON_...` §W2, §6). Do not represent as active relationships.*

### Card 1 — Dr. Zhongming Zhao · UTHealth Houston SBMI · **WARM (affiliation)**
- **Hosts:** Bioinformatics & Systems Medicine Lab (bsml320; https://www.uth.edu/bioinfo/; GitHub bsml320);
  single-cell + immuno-oncology methods (scGWAS, *Genome Biol* 2022; turep bioRxiv 2026; ImmuneApp; Scupa).
  Chairs the **Center for Precision Health / UTHealth Cancer Genomics Center** (CPRIT-funded ~$2M + BIG-TCR
  training; a **164-investigator / 18-institution** network). Cite: `20260701_...` §Faculty 1; `20261006_...`
  §A1. **IP/data caveat:** the Cancer Genomics Center is a **fee-for-service core** — commissioned data
  belongs to the investigator and goes to public repos on publication; his value is the custom-data engine +
  network + CPRIT credibility, **not** proprietary data.
- **Benefit to US:** the single warmest, zero-friction first call; the strongest local computational-IO
  scientist; a methods co-author; a CPRIT-credibility and 18-institution fan-out channel; scGWAS is already
  running in BioMate so the opening demo is live.
- **Benefit to THEM:** managed AWS Batch compute + execution infra for his tools `[E]`; scGWAS productionized
  and reproducible `[P]`; co-development of the "Autoimmune Immune Cell Virtual Cell" (Nature Methods / Genome
  Biology target) with BioMate as the execution/integration layer `[E offer]`; student/lab platform access
  `[E]`. Honest: downstream ADMET/PBPK integration is screening-grade `[E/P]`, not NDA depth.
- **Mutual ask / first move:** 30-min call opening on the **live scGWAS chain (Crohn's × Tregs)**, then pitch
  the co-developed virtual-cell paper. Warm route = founder's former-department tie. Sequence head: Zhao → Zhi
  → Zheng → one joint UTHealth kickoff.

### Card 2 — Dr. Degui Zhi · UTHealth Houston SBMI (Department Chair) · **WARM (affiliation)**
- **Hosts:** population-scale GWAS + EHR foundation models — TorchGWAS (arXiv 2026), RaPID2, **Med-BERT**
  (Apache-2.0, 329★ EHR FM), UDIP brain-imaging-genetics (*Nat Commun* 2026). GitHub ZhiGroup. Cite:
  `20260701_...` §Faculty 2.
- **Benefit to US:** population-scale GWAS target-prioritization methodology + Med-BERT backbone for the
  clinical-trial-design layer; UKB credential as a methods collaborator; a Nature Genetics / Bioinformatics
  co-paper. Same-campus reference after Zhao.
- **Benefit to THEM:** GPU GWAS orchestration on AWS Batch `[E]` (TorchGWAS chain id 69 wired); BioMate as the
  execution + downstream-integration layer for a joint methods paper `[E offer]`. Honest: his FDA
  (Folding-Docking-Affinity) repo is paper-repro, no inference CLI — deferred, not integrated.
- **Mutual ask / first move:** email referencing the Zhao conversation; pitch TorchGWAS + Med-BERT as the
  complementary target-prioritization/clinical layer. *Priority P2.*

### Card 3 — Dr. W. Jim Zheng · UTHealth Houston SBMI (Professor) · **WARM (affiliation)**
- **Hosts:** biomedical-literature LLM knowledge extraction (ensemble pretrained LMs, *JAMA* 2024);
  EHR representation-learning review (*J Biomed Inform* 2021); HiCPlus (*Nat Commun* 2018). ORCID
  0000-0001-7411-6047. Cite: `20260701_...` §Faculty 4.
- **Benefit to US:** the exact methodology to mine 100K+ GEO/PubMed methods sections into structured
  workflow-orchestration training data — the bootstrapping strategy for BioMate's Layer-4 routing LLM; a
  well-scoped, low-touch third-PI deliverable.
- **Benefit to THEM:** co-authorship + compute on a GEO/PubMed literature-mining workstream `[E offer]`;
  his NLP pipeline deployed at scale on BioMate infra `[E compute]`.
- **Mutual ask / first move:** invite as third PI on the joint UTHealth proposal, scoped to the LLM-training-
  data workstream. *Priority P2.*

---

## 2 · Flagship IO / HPV16+ HNSCC clinical anchors (ACT flagship — approach ≥2 as an advisory group)

> *All MDACC entries are **cold** (`20261006_...` §A2; §E). Big-name MDACC faculty are unlikely to partner
> pre-seed; the realistic MDACC on-ramp is **entering the TMC ACT accelerator**. Do not build around a single
> co-PI dependency. (Maura Gillison is deceased July 2026 — do **not** build around her; Ferrarotto is the
> active successor-generation lead.)*

### Card 4 — Dr. Renata Ferrarotto · MD Anderson, Head & Neck Medical Oncology · **COLD**
- **Hosts:** the HPV16+ HNSCC therapeutic-vaccine + checkpoint clinical program. Led the randomized
  peltopepimut-S (PDS0101) + cemiplimab vs cemiplimab trial in recurrent/metastatic **HPV16+ HNSCC** (JITC
  2025; `20261006_...` §A2). Verified program context `[web, 2026-10-08]`: the PDS0101 HNSCC landscape =
  VERSATILE-002 (PDS0101 + pembrolizumab, **NCT04260126**, Ph2, mOS 39.3 mo HPV16+) and the Phase-3
  randomized PDS0101 + pembrolizumab vs pembrolizumab (**NCT06790966**). *Flag:* the specific
  cemiplimab-arm/randomization detail is as stated in the map (JITC 2025) — confirm the exact NCT before
  citing externally.
- **Benefit to US:** the single best **clinical-validation anchor / SAB voice** for the ACT IO thesis — exact
  modality (HPV16 vaccine + checkpoint), active trialist, successor-generation lead; a Letter of Support
  target before Oct 31.
- **Benefit to THEM:** responder/resistance stratification on her trial cohorts `[P]` (anti-TNF-class real-
  data precedent, not yet run on HNSCC); reproducible, QC-governed multi-omics analysis of trial biospecimens
  with methods/report output `[P]`; co-authorship `[E offer]`. **Do not** pitch IND/CRO deliverables `[A]`.
- **Mutual ask / first move:** send the "HPV16 immunotherapy advisory group" outreach the same week as Sikora
  + Sastry; **ask ACT to broker** the intro. No warm line exists.

### Card 5 — Dr. Andrew G. Sikora, MD PhD · MD Anderson Head & Neck Surgery (also Baylor Oto) · **COLD**
- **Hosts:** HPV E6/E7 **therapeutic-vaccine + surgery** program; ran a window-of-opportunity trial.
  Surgeon-scientist; the strongest thematic anchor (`20261006_...` §A2). Verified `[web, 2026-10-08]`:
  investigator-sponsored **Window-of-Opportunity Trial of neoadjuvant ADXS11-001 vaccination prior to
  robot-assisted resection of HPV-positive oropharyngeal SCC** — **NCT02002182**, A.G. Sikora listed as
  Study Chair (sponsor-investigator; Advaxis collaboration). Confirms the window-of-opportunity HPV-vaccine
  modality in the card. (No Sikora-first/senior HPV-vaccine *paper* reconfirmed in 2023–2026; recent pubs are
  HNSCC-immunology co-authorships — cite the NCT, not a PMID.)
- **Benefit to US:** the strongest **thematic clinical anchor** (peptide vaccine + checkpoint = our exact
  macrocycle-IO story); a surgeon-scientist validator who bridges design → window-of-opportunity trial.
- **Benefit to THEM:** QC-governed reproducible analysis of window-trial biospecimens + immune-monitoring
  readouts `[P]`; epitope/antigen nomination to prioritize vaccine targets `[P]` (ImmuneApp/immunopeptidome
  stack is stub-stage — honest); co-authorship `[E offer]`; compute `[E]`.
- **Mutual ask / first move:** approach as a package with Sastry (known pairing); route via ACT. Confirm a
  recent publication before outreach.

### Card 6 — Dr. K. Jagannadha (Jagan) Sastry, PhD · MD Anderson, Immunology · **COLD**
- **Hosts:** ~25 years of HPV therapeutic **peptide-vaccine + checkpoint** immunology (`20261006_...` §A2).
  Verified `[web, 2026-10-08]`, senior/last author on both: the landmark modality paper **"Mucosal HPV
  E6/E7 Peptide Vaccination in Combination with Immune Checkpoint Modulation Induces Regression of HPV(+)
  Oral Cancers"** (Cancer Research 2018, **PMID 30054333**) — exactly the vaccine + checkpoint thesis — and
  recent **"Immunity from NK Cell Subsets Is Important for Vaccine-Mediated Protection in HPV+ Cancers"**
  (Vaccines 2024, **PMID 38400189**). (Sikora is not a co-author on these; "Sikora pairing" = both are HPV-
  vaccine investigators at MDACC, not a verified joint publication.)
- **Benefit to US:** the **immunology anchor** that complements a clinician — mechanistic depth on HPV
  peptide-vaccine immunogenicity; pairs cleanly with Sikora for a credible advisory dyad.
- **Benefit to THEM:** antigen/epitope prioritization + immune-repertoire analysis `[P]`; reproducible
  pipelines + methods output for his immunogenicity data `[P]`; compute + co-authorship `[E]`.
- **Mutual ask / first move:** approach as the Sikora + Sastry package; route via ACT.

### Card 7 — Dr. Amir A. Jazaeri, MD · MD Anderson, GYN Oncology · **COLD**
- **Hosts:** cervical-cancer immunotherapy program (`20261006_...` §A2) — Director, Gynecologic Cancer
  Immunotherapy Program, MDACC — the anchor for a cervical HPV16 pivot / fast-follow. Verified
  `[web, 2026-10-08]`, senior/last author: **"Integrating CTLA-4/PD-1 blockade into cervical cancer
  management: Results of COMPASSION-16"** (Med 2025, **PMID 39798550**) and **"Immunotherapy in locally
  advanced cervical cancer: Integrating KEYNOTE-A18 into management strategies"** (Med 2024, **PMID
  38878765**) — checkpoint-IO in cervical cancer. (Cervical HPV16-vaccine landscape context, separate PI:
  IMMUNOCERV = PDS0101 + chemoradiation, **NCT04580771**, A.H. Klopp PI — *not* Jazaeri.)
- **Benefit to US:** a **cervical-cancer on-ramp** that extends the HPV16 thesis beyond HNSCC (fast-follow
  indication); a second IO clinical validator.
- **Benefit to THEM:** responder stratification + reproducible multi-omics on cervical IO cohorts `[P]`;
  compute + co-authorship `[E]`.
- **Mutual ask / first move:** secondary HPV16 outreach after the HNSCC dyad lands; route via ACT.

---

## 3 · ACT §8 shortlist + the UTSW/BCM warmer ties (fullest per the brief)

### Card 8 — Dr. Brian Grindel · MD Anderson, Cancer Systems Imaging · **COLD (low-risk, peer approach)**
- **Hosts:** **cyclic/linear peptide binder discovery via mRNA display, with a PD-L1 track.** Co-author on
  "Using extension-based mRNA display to design antibody-like proteinogenic peptides for human PD-L1"
  (*Protein Science* 34(9):e70268, 2025, **PMID 40852896** — SPAM2/SPAM3 PD-L1 binders, ~250–300 pM; senior
  authors Curran/Roche/Millward) `[web, 2026-10-08]`; profile https://faculty.mdanderson.org/profiles/brian_grindel.html.
  Cite also `20260930_ACT_...` §8. **IP caveat:** any joint peptide work needs explicit composition-IP terms;
  his group's wet-lab output is fee-for-service / investigator-owned.
- **Benefit to US:** the **exact wet-lab match for the ACT PD-L1 macrocycle loop-proof** (§2 Direction-1) — he
  makes the PD-L1 peptide binders we design-and-rank in silico; an MDACC co-author on the ACT traction data;
  early-career and approachable → low partnership risk.
- **Benefit to THEM:** our full in-silico design loop pointed at his target — BoltzGen de-novo generation +
  cyclic MM-GBSA re-rank + permeability GBM + GP-Pareto selection → a ranked, developability-filtered order
  sheet `[P]`; spot GPU compute `[E]`; co-authorship `[E offer]`. Honest: no wet-lab-confirmed hit yet; this
  closes **his** loop faster, ours proves the platform.
- **Mutual ask / first move:** cold **peer-to-peer** methods-collaboration email on PD-L1 macrocycles —
  "we design + rank, you validate by mRNA display." Low-risk, direct; also names him a prospective ACT
  co-author/advisor.

### Card 9 — Dr. Yang-Xin Fu · UT Southwestern · **COLD (strong scientific fit)**
- **Hosts:** engineering of **tumor-masked cytokine/checkpoint prodrugs + bispecifics** — e.g. a
  cytokine-receptor-masked IL-2 prodrug activated by tumor-associated protease `[web, 2026-10-08]`; a
  world-leading tumor-conditional-biologics lab. Cite `20260930_ACT_...` §8. Specific primary PMID: confirm
  the exact masked-IL2 paper before external citation (**verify PMID**).
- **Benefit to US:** a **near-exact scientific validator** for our corrected lead — the tumor-conditional
  masked (TAA)×CD3 TCE (`20260930_ACT_...` §7); top-tier credibility and a real prospective advisor on the
  masking mechanism that is the asset's differentiator.
- **Benefit to THEM:** AI target/axis nomination + de-novo binder/macrocycle design against his masked
  formats `[P]`; compute `[E]`; co-authorship `[E offer]`. **IP caveat:** masking-architecture IP is a
  crowded space (CytomX/Janux) — any joint design needs a clear composition/FTO boundary (`20260930_ACT_...`
  §7①).
- **Mutual ask / first move:** cold scientific email framed on the tumor-masked-bispecific overlap; position
  as advisor/co-author for the ACT masked-TCE lead.

### Card 10 — Dr. Ann Leen · Baylor College of Medicine, Center for Cell & Gene Therapy (CAGT) · **COLD (warm-adjacent via BCM standing)**
- **Hosts:** **multi-TAA antigen-specific T-cell therapy** (PRAME / MAGEA4 / NY-ESO-1) with GMP cohorts —
  *Nat Med* 2026, **PMID 41482561** (per `20260930_ACT_...` §8, API-confirmed); BCM CAGT.
- **Benefit to US:** **TAA target validation + real antigen-specific T-cell cohorts + a clinical on-ramp** for
  the TAA arm of the TCE lead; GMP-cohort credibility.
- **Benefit to THEM:** antigen/epitope nomination to prioritize TAAs `[P]`; TCR/immune-repertoire + reproducible
  multi-omics analysis of her cohort data `[P]`; compute + co-authorship `[E]`. **IP/data caveat:** GMP/
  clinical-trial cohort data is BCM/trial-owned — federated/de-identified analysis only.
- **Mutual ask / first move:** cold intro via BCM standing; propose antigen-prioritization + repertoire
  analysis on a multi-TAA cohort as a methods collaboration.

### Card 11 — Dr. William Decker · Baylor College of Medicine (Pathology & Immunology) · **WARM-ADJACENT (warmest MDACC-adjacent path)**
- **Hosts:** inventor of **DOC1021**, the autologous "double-loaded" dendritic-cell vaccine; co-founder of
  **Diakonos Oncology**; FDA Fast Track in GBM; CNS-2024 data (14/15 evaluable alive at 12 mo) `[web,
  2026-10-08]`; IND-experienced, startup-friendly. Cite `20260930_ACT_...` §8 (ranked **most actionable**).
- **Benefit to US:** the **most actionable** IO clinical/translational partner in the map — IND experience,
  startup empathy, DC-vaccine IO trials + immunophenotyping; the realistic first MDACC-adjacent partnership
  (with Zhao) at pre-seed.
- **Benefit to THEM:** **prospective responder prediction** (pre-treatment scRNA/CyTOF signature) for DOC1021
  enrollment `[P]`; reproducible, QC-governed immunophenotyping analysis + methods output `[P]`; compute
  `[E]`; co-authorship `[E offer]`. Honest: this is a predictive-biomarker pilot, not a regulated deliverable.
- **Mutual ask / first move:** reachable warm-adjacent via BCM; propose a prospective DOC1021 responder-
  prediction pilot. (Note: the prior Zhandong-Liu → Diakonos routing is **void** per the 2026-10-05 founder
  decision — approach Decker directly / via BCM, not via Liu.)

### Card 12 — Dr. Sarina Piha-Paul · MD Anderson, Investigational Cancer Therapeutics · **COLD (via ACT)**
- **Hosts:** first-in-human **bispecific / T-cell-engager** solid-tumor Phase-1 trials — e.g. MAGE-A1/HLA-
  A*02:01 TCE CRPA1A2 (**NCT07583316**), GPC3 TCE SAR444200, AMV564 `[web, 2026-10-08]`; profile
  https://profiles.viictr.org/profile/12582720. Cite `20260930_ACT_...` §8.
- **Benefit to US:** the **TCE clinical on-ramp** — a first-in-human bispecific/TCE trialist whose Phase-1
  machine is exactly where our macrocyclic/mini-protein TCE would eventually need a clinical home.
- **Benefit to THEM:** biomarker/responder stratification + reproducible analysis across her Phase-1 TCE
  cohorts `[P]`; compute + co-authorship `[E]`. **Do not** pitch IND/CRO UX `[A]`.
- **Mutual ask / first move:** cold; the realistic route is **entering TMC ACT**, which is itself the
  institutional on-ramp to this MDACC Phase-1 network.

### Card 13 — Dr. Funda Meric-Bernstam · MD Anderson, Chair, Investigational Cancer Therapeutics · **COLD (aspirational pre-seed; via ACT)**
- **Hosts:** the largest Phase-1 solid-tumor trial program in the field — bispecific/ADC first-in-human work
  (e.g. zanidatamab/ZW25 HER2 bispecific); NAM-elected Oct 2024 `[web, 2026-10-08]`; profile
  https://profiles.viictr.org/display/12583329. Cite `20260930_ACT_...` §8.
- **Benefit to US:** the **flagship TCE/bispecific clinical on-ramp** and the field's leading precision-
  oncology trialist — enormous credibility and a trial home for a future asset.
- **Benefit to THEM:** reproducible multi-omics + biomarker stratification across a very large Phase-1
  portfolio `[P]`; compute + co-authorship `[E]`.
- **Mutual ask / first move:** **cold and big-name → unlikely to partner pre-seed** (map flags this
  explicitly). Route only via ACT, as institutional validator, not an early co-PI.

### Card 14 — Dr. Jennifer Wargo · MD Anderson · **COLD**
- **Hosts:** **ICB responder vs non-responder** cohorts; B-cell / tertiary-lymphoid-structure response
  biology (landmark *Nature* 2020, doi:10.1038/s41586-019-1922-8); gut/tumor microbiome; leads **PRIME-TR**;
  2024 AACR spatial-TLS melanoma `[web, 2026-10-08]`; profile https://faculty.mdanderson.org/Jennifer_Wargo/.
  Cite `20260930_ACT_...` §8.
- **Benefit to US:** a gold-standard **responder-cohort + TLS/B-cell** data anchor for validating immune-
  stratification; benchmark-grade ICB response phenotypes.
- **Benefit to THEM:** our immune-stratification / responder-nomination applied to her cohorts `[P]` (anti-TNF
  AUROC 0.833 precedent — honest: not yet run on melanoma ICB); reproducible spatial/multi-omics analysis
  `[P]` (spatial E2E unproven — honest caveat); compute + co-authorship `[E]`. **Data caveat:** cohort data is
  trial/institution-owned.
- **Mutual ask / first move:** cold, big-name → via ACT or a methods-collaboration framing on responder
  stratification; realistically an advisory/validation relationship, not pre-seed co-development.

### Card 15 — Dr. Alexandre Reuben · MD Anderson · **COLD (ACT alum — easier warm intro)**
- **Hosts:** **TCR-repertoire / neoantigen** ICB-predictor biology — e.g. peripheral T-cell diversity
  predicting dual-ICI response & toxicity in NSCLC (*JITC*, Dec 2024) `[web, 2026-10-08]`; profile
  https://faculty.mdanderson.org/profiles/alexandre_reuben.html. **ACT alum** (easier intro). Cite
  `20261006_...` §A2, `20260930_ACT_...` §8.
- **Benefit to US:** **bridges the immune-LLM to real TCR data** — target-discovery validation + a repertoire-
  predictor collaborator; an ACT alum = a plausibly warmer MDACC door.
- **Benefit to THEM:** TCR/BCR repertoire + neoantigen analysis on BioMate (AIRR stack) `[P]`; reproducible
  pipelines + compute + co-authorship `[E]`. Honest: our TCR tools (turep/ImmuneApp) are stub-stage.
- **Mutual ask / first move:** ask ACT to broker the alum intro; propose a TCR-repertoire predictor
  methods collaboration bridging to the immune-LLM.

### Card 16 — Dr. Cassian Yee · MD Anderson (Director, Solid Tumor Cell Therapy Program) · **COLD (ACT alum — easy warm intro)**
- **Hosts:** **endogenous / adoptive antigen-specific T-cell therapy (ETC)** program; T-cell potency assays;
  profile https://faculty.mdanderson.org/profiles/cassian_yee.html `[web, 2026-10-08]`. **ACT alum.** Cite
  `20261006_...` §A2, `20260930_ACT_...` §8.
- **Benefit to US:** **immunogenicity + tumor-killing functional validation** (T-cell potency readouts) for
  designed binders/epitopes; an ACT alum = easy warm intro and a wet-lab functional-assay partner.
- **Benefit to THEM:** epitope/antigen prioritization feeding his ETC target selection `[P]`; reproducible
  analysis + compute + co-authorship `[E]`. **Data caveat:** patient T-cell data is clinically owned.
- **Mutual ask / first move:** ask ACT to broker the alum intro; offer epitope nomination + analysis in
  exchange for T-cell potency validation of designed peptides.

### Card 17 — Dr. Cara Haymaker · MD Anderson (Translational Molecular Pathology) · **COLD (fee-for-service core)**
- **Hosts:** Director of the **ORION immune-monitoring core** (clinical-trial immune monitoring; flow/CyTOF/
  mIF/spatial) and the TMP-IL multiplex-IF lab `[web, 2026-10-08]`; profile
  https://faculty.mdanderson.org/profiles/cara_haymaker.html. Cite `20260930_ACT_...` §8.
- **Benefit to US:** the **in-vitro immune-monitoring validation package** (ELISpot/multimer/CyTOF/mIF) — a
  cheap/fast wet-lab customer-and-collaborator for functional readouts on designed assets. **Data caveat:**
  fee-for-service core → output is investigator-owned.
- **Benefit to THEM:** BioMate as the reproducible **analysis + QC + methods-report layer** for the high-
  dimensional flow/CyTOF/mIF data her core generates `[P]` (flow/CyTOF E2E unproven — honest); compute `[E]`.
- **Mutual ask / first move:** engage as a **core customer** (name ORION in the ACT wet-lab package) and
  pitch BioMate as the downstream analysis/reporting layer; no PI-level relationship needed.

### Card 18 — Dr. Gregory Lizée · MD Anderson (Melanoma Med Onc / Immunology) · **COLD**
- **Hosts:** **tumor immunopeptidome → personalized-vaccine target discovery** (MS-based HLA-peptide elution
  with the Proteomics Facility); computational pMHC modeling (APE-Gen2.0, *J Chem Inf Model*, Mar 2024)
  `[web, 2026-10-08]`; profile https://faculty.mdanderson.org/profiles/gregory_lizee.html. Cite
  `20260930_ACT_...` §8.
- **Benefit to US:** **immunopeptidome → non-redundant target nomination** — a methods partner who resolves
  which predicted epitopes are actually presented (the "LLM-validated-in-wet-lab" data point).
- **Benefit to THEM:** pMHC / HLA-binding prediction + reproducible immunopeptidomics analysis `[P]`
  (proteomics E2E unproven — honest); compute + co-authorship `[E]`.
- **Mutual ask / first move:** cold methods-collaboration email pairing our epitope prediction with his
  MS-presented immunopeptidome as orthogonal validation.

### Card 19 — Dr. Sachet Shukla · MD Anderson (Hematopoietic Biology & Malignancy) · **COLD**
- **Hosts:** **computational immunogenomics / neoantigen discovery** — author of **Polysolver** (HLA typing);
  neoantigen-vaccine design pipeline (used in 2 FIH trials at DFCI); Computational Director, ECLIPSE Moon
  Shot; recent neoantigen-vaccine work (RCC *Nature* Mar 2025; melanoma *Cell* Sep 2025) `[web, 2026-10-08]`;
  profile https://faculty.mdanderson.org/profiles/sachet_shukla.html. Cite `20260930_ACT_...` §8.
- **Benefit to US:** **target/biomarker — non-redundant neoantigen/epitope nomination**; a rigorous
  computational-immunogenomics methods collaborator who bridges to our immune-LLM target-ID.
- **Benefit to THEM:** execution infra + compute for his HLA/neoantigen pipelines `[E]`; reproducible,
  QC-governed analysis + co-authorship `[E/P]`.
- **Mutual ask / first move:** cold peer methods-collaboration on neoantigen/epitope nomination;
  complementary to Lizée (prediction × MS-presentation).

### Card 20 — Dr. Linghua Wang · MD Anderson (Allison Institute + Institute for Data Science in Oncology) · **COLD**
- **Hosts:** **spatial transcriptomics + single-cell tumor-microenvironment** deep profiling; author of METI
  (*Nat Commun*, Aug 2024); appointed to the Allison Institute + IDSO (Sep 2024) `[web, 2026-10-08]`; profile
  https://faculty.mdanderson.org/profiles/linghua_wang.html. Cite `20260930_ACT_...` §8 (with Kenneth Hu).
- **Benefit to US:** **spatial-TME** methods + data for immune-context target validation; an Allison-Institute
  computational anchor.
- **Benefit to THEM:** reproducible single-cell/spatial pipelines + compute `[P]` (**single-cell/spatial E2E
  unproven — the sharpest honest caveat here**); co-authorship `[E offer]`.
- **Mutual ask / first move:** cold methods collaboration; be explicit that spatial E2E is a development
  partnership, not a proven capability (do not over-promise).

---

## 4 · Broader MDACC / BCM / UH IO + discovery pool (briefer)

### Card 21 — Dr. Padmanee Sharma · MD Anderson · **COLD / aspirational (SAB/credibility only)**
- **Hosts:** checkpoint-immunotherapy mechanism + ICB responder biology (`20261006_...` §A2; `20260930_...`
  §8). Specific PMID: verify. **Benefit to US:** SAB credibility; responder-biology context. **Benefit to
  THEM:** immune-stratification analysis `[P]`; compute `[E]`. **First move:** cold/aspirational — no direct
  line; SAB only, via ACT at most.

### Card 22 — Dr. James Allison · MD Anderson (Nobel laureate) · **COLD / aspirational**
- **Hosts:** checkpoint-blockade field leadership; the Allison Institute (`20261006_...` §A2). **Benefit to
  US:** SAB/credibility symbol only. **Benefit to THEM:** n/a at this stage. **First move:** explicitly **no
  direct line exists** — aspirational; do not represent any path.

### Card 23 — Dr. Michael Curran · MD Anderson, Immunology · **COLD**
- **Hosts:** IO target biology + immune-agonist work; founder of **ImmunoGenesis** (IMGS-001, immune-excluded
  tumors); senior author on the Grindel PD-L1 mRNA-display peptide paper (PMID 40852896) `[web]`. **Benefit to
  US:** a bridge between the PD-L1-peptide wet-lab (Grindel) and an IO biotech (ImmunoGenesis) buyer; target
  biology. **Benefit to THEM:** responder/resistance stratification for IMGS-001 `[P]`; design loop + compute
  `[E/P]`. **IP caveat:** composition-IP boundary on any peptide collaboration. **First move:** the
  ImmunoGenesis pilot route (`20261005_HOUSTON_...` #12) is the actionable channel.

### Card 24 — Dr. Jared Burks · MD Anderson · **COLD (core)**
- **Hosts:** flow/cytometry + imaging core capability for immune functional readouts (`20260930_...` §8).
  Specific profile/PMID: verify. **Benefit to US:** wet-lab functional-readout core (with Haymaker).
  **Benefit to THEM:** analysis/QC layer for cytometry data `[P]`; compute `[E]`. **First move:** engage as a
  core customer alongside ORION.

### Card 25 — Dr. Kenneth Hu · MD Anderson · **COLD**
- **Hosts:** spatial-TME methods (paired with Linghua Wang; `20260930_...` §8). Specific PMID: verify.
  **Benefit to US:** spatial-TME validation. **Benefit to THEM:** spatial pipelines `[P]` (E2E unproven —
  caveat); compute `[E]`. **First move:** cold, bundle with the Linghua Wang approach.

### Card 26 — Dr. Michael Matzuk · Baylor College of Medicine (Center for Drug Discovery) · **COLD**
- **Hosts:** the **BCM Center for Drug Discovery** — DNA-templated **macrocycle DELs** + a Sept-2025 immune-
  targeted discovery collaboration (`20260930_...` §8). Specific PMID: verify. **Benefit to US:** modality-
  relevant **macrocycle discovery infrastructure without MDACC** — a complementary wet chemistry engine for
  the ACT loop. **IP caveat:** DEL output IP terms must be defined. **Benefit to THEM:** in-silico design +
  ranking + permeability/developability scoring on top of DEL hits `[P]`; compute `[E]`. **First move:** cold
  intro to BCM CDD; propose dry-design × DEL-screen complementarity.

### Card 27 — Dr. Weiyi Peng · University of Houston (Drug Discovery Institute) · **COLD**
- **Hosts:** IO drug-discovery / immune-target biology at UH (`20260930_...` §8). Specific PMID: verify.
  **Benefit to US:** a Houston non-MDACC IO discovery collaborator. **Benefit to THEM:** target nomination +
  design loop + compute `[P/E]`. **First move:** cold intro via UH Drug Discovery Institute.

### Card 28 — Dr. Tao Wang · UT Southwestern · **COLD (collaborator-OR-competitor — hard IP boundary)**
- **Hosts:** **pMTnet** (TCR–pMHC deep learning); founder of **NightStar Biotechnologies** (AI TCR/neoantigen;
  ACT 2024) (`20261006_...` §A5). **Benefit to US:** nearest modeling peer — a possible TCR–pMHC methods
  collaborator. **Benefit to THEM:** execution/compute for his models `[E]`. **IP caveat (critical):** he is
  **our nearest competitor** on the immune-LLM — **clear IP boundaries only**; do not share immune-LLM
  internals. **First move:** if engaged at all, a narrowly-scoped, boundaried methods comparison.

### Card 29 — Dr. Gomika Udugamasooriya · University of Houston · **COLD (ACT 2025 alum)**
- **Hosts:** **peptide chemistry / developability** (peptoid/peptide ligands); ACT 2025 alum (`20261006_...`
  §A4). Specific PMID: verify. **Benefit to US:** peptide-developability wet-lab partner for the macrocycle
  arm; alum credibility. **Benefit to THEM:** in-silico permeability/SA/developability scoring + design
  ranking `[P]`; compute `[E]`. **First move:** alum-to-alum/ACT intro on peptide developability.

### Card 30 — Dr. Kyoji Tsuchikama · UTHealth (Texas Therapeutics Institute) · **COLD**
- **Hosts:** CMC/developability + **PDC (peptide-drug-conjugate) / ADC linker** chemistry (`20261006_...`
  §A4). Specific PMID: verify. **Benefit to US:** CMC/developability + conjugation route for a peptide asset.
  **Benefit to THEM:** design/developability scoring + compute `[P/E]`. **First move:** cold intro via UTHealth
  TTI on the PDC route.

### Card 31 — Dr. Zhiqiang An · UTHealth (Texas Therapeutics Institute) / UH · **COLD**
- **Hosts:** **antibody discovery + cancer genomics** at the Texas Therapeutics Institute (`20261006_...`
  §A3/§A4). Specific PMID: verify. **Benefit to US:** antibody/biologics discovery depth (complements the CD3
  mini-protein arm). **Benefit to THEM:** execution infra + genomics pipelines + compute `[E]`; co-authorship
  `[E]`. **First move:** cold intro via TTI.

### Card 32 — Dr. Shu-Hsia Chen · Houston Methodist · **COLD (2025 ACT, IO)**
- **Hosts:** IO immunology at Houston Methodist Research Institute; 2025 ACT participant (`20261006_...` §A3).
  Specific PMID: verify. **Benefit to US:** an IO collaborator + a fan-out via the Houston Methodist core.
  **Benefit to THEM:** immune-stratification + reproducible pipelines + compute `[P/E]`. **First move:** cold
  intro; ACT-adjacent.

---

## 5 · Texas academic / clinical-genomics centers (reproducibility + on-prem wedge; all COLD, briefer)

> *For these, "hosts" = the named department/center (cited in the map); an individual recent PMID was **not**
> verified this pass and is marked **verify**. The two-way value is the generic academic-core motion:
> **US gets** a methods/reproducibility collaborator + a fan-out channel + student adoption; **THEY get**
> no-code chat routing over the validated catalog `[E]`, reproducible pipelines + QC/methods output `[P]`,
> on-prem option `[A→P]`, compute `[E]`, co-authorship + student platform access `[E]`. First move = cold
> intro to the department, reproducibility/methods pilot. Per-person specifics below.*

- **Card 33 — Gaudenz Danuser** · UTSW, inaugural Chair, **Lyda Hill Dept. of Bioinformatics** (17 faculty,
  120 scientists; imaging + multi-omics). *US:* flagship computational dept = co-dev/methods partner + 120-
  scientist fan-out. *First move:* cold intro to the department; reproducibility/methods collaboration +
  student platform access (`20261005_HOUSTON_...` #16). Verify recent PMID.
- **Card 34 — Yang Xie** · UTSW, Director, QBRC (quantitative biomedical research). *US:* multi-omics methods
  + a core that serves many labs. Verify PMID.
- **Card 35 — Lin Xu** · UTSW Bioinformatics (pediatric/cancer genomics). Verify PMID.
- **Card 36 — Jeon Lee** · UTSW Bioinformatics (BioHPC / multi-omics). Verify PMID.
- **Card 37 — Chao Xing** · UTSW Bioinformatics (statistical genetics). Verify PMID.
- **Card 38 — Xiaowei Zhan** · UTSW Bioinformatics (statistical/population genetics). Verify PMID.
- **Card 39 — Richard Gibbs** · BCM, Director, **Human Genome Sequencing Center** (200+ staff; DNAnexus power-
  user → compliance-aware buyer). *US:* the "instrument → reproducible pipeline" wedge + a compliance-aware
  reference buyer. *First move:* cold intro to a core-facility director; reproducibility/methods-audit pilot
  (`20261005_HOUSTON_...` #1). Verify current PMID.
- **Card 40 — Fritz Sedlazeck** · BCM HGSC (structural variants, long-read). *US:* SV/long-read methods
  collaborator. Verify PMID.
- **Card 41 — Ken Chen** · MD Anderson, Chair, Bioinformatics & Computational Biology (cancer genomics).
  **COLD (MDACC).** *US:* cancer-genomics methods collaborator. Verify PMID.
- **Card 42 — Todd Treangen** · Rice (metagenomics / biothreat; profiles.rice.edu/faculty/todd-treangen).
  *US:* metagenomics reproducibility + teaching user, TMC-adjacent. *First move:* cold intro; metagenomics
  reproducibility pilot / student platform access (`20261005_HOUSTON_...` #6). Verify recent PMID.
- **Card 43 — Lydia Kavraki** · Rice (AI2Health / computational biology; Ken Kennedy Institute). *US:* AI-for-
  health methods collaborator. Verify PMID.
- **Card 44 — Luay Nakhleh** · Rice (computational biology / phylogenomics). Verify PMID.
- **Card 45 — Michael Qiwei Zhang** · UT Dallas (epigenomics; Genome Center). *US:* epigenomics (ATAC/ChIP)
  methods — honest caveat: ChIP E2E unproven. Verify PMID.
- **Card 46 — Kelli Palmer** · UT Dallas (microbial genomics). Verify PMID.
- **Card 47 — Li Zhang** · UT Dallas (bioinformatics). Verify PMID.
- **Card 48 — Yuriy Fofanov** · UTMB Galveston (infectious-disease genomics; Galveston National Lab). *US:*
  infectious-disease metagenomics + a biosecure on-prem fit. Verify PMID.
- **Card 49 — Edward Marcotte** · UT Austin, Center for Computational Biology (proteomics/systems). *US:*
  systems/proteomics methods — honest caveat: proteomics E2E unproven. Verify PMID.
- **Card 50 — Claus Wilke** · UT Austin, Center for Computational Biology (evolution/statistics; data viz).
  Verify PMID.
- **Card 51 — Claudia Lucchinetti** · UT Austin, Dean, Dell Medical School (precision medicine). *US:* a
  clinical-research-arm on-ramp. Verify PMID.
- **Card 52 — Joshua Yuan** · Texas A&M, TIGSS (synthetic biology; AgriLife TxGen core). *US:* synbio +
  genomics-core fan-out. Verify PMID.
- **Card 53 — Bruce Budowle** · UNT Health Science Center (forensic/molecular genetics). *US:* niche genomics
  reproducibility. Verify PMID.
- **Card 54 — Arthur Eisenberg** · UNT Health Science Center (molecular genetics). Verify PMID.
- **Card 55 — Larry Schlesinger** · Texas Biomedical Research Institute (Pres./CEO; TB/infectious-disease;
  BSL-4). *US:* immune/vaccine multi-omics + a biosecure **on-prem** fit (28 PIs). *First move:* cold intro;
  immune-profiling / reproducible-pipeline pilot, on-prem angle fits BSL-4 data sensitivity
  (`20261005_HOUSTON_...` #21). Verify PMID.
- **Card 56 — Binhua Ling** · Texas Biomed (HIV/SIV immunology). Verify PMID.
- **Card 57 — Carlos Arteaga** · UTSW, Director, Simmons Comprehensive Cancer Center. *US:* a cancer-center
  institutional on-ramp. Verify PMID.
- **Card 58 — Huda Zoghbi** · Texas Children's, Director, Duncan Neurological Research Institute (rare-neuro
  genomics). *US:* rare-disease multimodal workup fit (BioMate chain id 1). Verify PMID.
- **Card 59 — Josh Bhatt** · Children's Medical Center Dallas (genomics & rare disease). Verify contact + PMID.
- **Card 60 — Joseph Rogers** · Texas Heart Institute (Pres./CEO; cardiovascular genomics). *US:* a
  cardiovascular-genomics on-ramp (a top Chinese-hospital demand field too). Verify PMID.

---

## 6 · Beyond Texas — named investigators (national SAB credibility; COLD unless noted)

- **Card 61 — Dr. Jared Weiss** · UNC Chapel Hill. **Hosts:** VERSATILE-002 (PDS0101 + pembrolizumab) HPV16+
  HNSCC investigator (NCT04260126) `[web]`; a national SAB voice on the exact modality. *US:* out-of-state SAB
  credibility on HPV16 + checkpoint. *Them:* reproducible biomarker analysis + compute `[P/E]`. *First move:*
  cold national-SAB outreach on the shared modality (`20261006_...` §B1).
- **Card 62 — Dr. Charalampos Floudas** · National Cancer Institute (Bethesda). **Hosts:** PI,
  "Combination Immunotherapy in Advanced HPV-Associated Malignancies" (**NCT04287868**, NCI; Overall Official)
  (`20261006_...` §B1). *US:* an NCI-level HPV+checkpoint SAB anchor. *Them:* analysis/QC layer + compute
  `[P/E]`. *First move:* cold outreach as modality SAB.
- **Card 63 — Pr. Christophe Borg** · CHU Besançon, France. **Hosts:** PI, UCPVax HPV-telomerase vaccine +
  atezolizumab (VolATIL, **NCT03946358**) (`20261006_...` §B1). *US:* an international modality anchor. *Them:*
  reproducible analysis + compute `[P/E]`. *First move:* cold international SAB outreach. **Caveat:** cross-
  border data (EU GDPR) — on-prem/federated framing only.
- **Card 64 — Kirk V. Shepard, MD** · PDS Biotechnology (industry study director). **Hosts:** clinical
  development of the PDS0101 program (`20261006_...` §B1). *Note:* **industry, not academic SAB** — modality-
  adjacent context, not a research collaborator. *First move:* none as an academic partner; track as program
  context only. (Hookipa's Head of Clinical Development is similarly industry-context, not carded as a named
  academic.)

---

## 7 · Top-5 by mutual value (and why)

Mutual value is scored as **(clinical/scientific anchor value to BioMate) × (realness of what BioMate can
honestly offer them) × actionability (warmth + pre-seed partnerability)**. The actionability factor is
decisive: the map's own §8 conclusion is that the **realistic first partnerships are Houston non-MDACC
(Decker + Zhao), while Grindel and Fu are near-exact scientific matches** to the corrected ACT lead. The
ranking below reflects that, not raw institutional prestige (which is why big-name MDACC anchors score lower).

1. **Dr. Zhongming Zhao (UTHealth SBMI) — WARM.** Highest on all three factors: the only genuinely warm,
   zero-friction call; the strongest local computational-IO scientist; and the demo is already live (scGWAS
   in BioMate). Both sides gain immediately — he gets a co-developed virtual-cell paper + compute; we get a
   warm validation anchor, a CPRIT/18-institution channel, and a methods co-author.
2. **Dr. Brian Grindel (MDACC) — COLD but low-risk.** The **exact wet-lab counterpart to the ACT PD-L1
   macrocycle loop-proof** (his mRNA-display PD-L1 binders, PMID 40852896 ↔ our in-silico design loop).
   Directly on the ACT critical path, early-career/approachable, and an MDACC co-author on the traction data.
   Near-perfect scientific complementarity makes the mutual value very high despite cold status.
3. **Dr. William Decker (BCM) — WARM-ADJACENT.** The map's **most actionable** IO partner: IND-experienced,
   startup-friendly, DC-vaccine trials + immunophenotyping. We offer prospective responder prediction + QC-
   governed analysis for DOC1021; he offers the warmest real clinical-translational partnership at pre-seed.
4. **Dr. Yang-Xin Fu (UTSW) — COLD, strong fit.** A world-leading **tumor-masked bispecific/prodrug** lab =
   near-exact validator for the corrected ACT lead (tumor-conditional masked ×CD3 TCE). Enormous scientific
   credibility; we offer AI axis/binder nomination + design. Slightly lower actionability than the top three
   (cold, big lab), with a masking-IP boundary to manage.
5. **Dr. Ann Leen (BCM CAGT) — COLD, warm-adjacent.** Multi-TAA antigen-specific T-cell therapy + GMP cohorts
   (Nat Med 2026, PMID 41482561) = the **TAA-arm validation + clinical on-ramp** for the TCE lead; BCM standing
   makes it warm-adjacent. We offer antigen/epitope nomination + repertoire analysis.

**Honorable mention (highest clinical-theme value, lower actionability):** **Dr. Andrew Sikora** (the
strongest HPV16 peptide-vaccine + checkpoint thematic anchor) and **Dr. Renata Ferrarotto** (the flagship
HPV16+ HNSCC trial lead) — both are top clinical-validation anchors, but **cold, big-name, and unlikely to
partner pre-seed**; their realistic path is via the ACT accelerator as advisors/validators, not early
co-developers, which is why they sit just outside the actionable top-5.

---

## 8 · Honesty log — count, caveats, and who could not be verified

- **Card count: 64** named faculty/physicians (CRO organizations are intentionally **not** carded, per the
  brief). Full cards: 20 (Cards 1–20); briefer cards: 44 (Cards 21–64). The industry study directors (Shepard
  + the Hookipa head) are noted as program context, not academic collaborators (one card, Card 64).
- **Verified this pass `[web, 2026-10-08]`** with official profile + a real recent pub/trial: Grindel
  (PMID 40852896), Fu (masked-IL2 prodrug line — exact primary PMID still to confirm), Ferrarotto/PDS0101
  (NCT04260126 + NCT06790966), Piha-Paul (NCT07583316 TCE), Meric-Bernstam (zanidatamab Ph1; NAM 2024),
  Wargo (Nature 2020 TLS; PRIME-TR; 2024 AACR), Reuben (JITC Dec 2024), Yee (ETC program + profile), Haymaker
  (ORION core director), Lizée (APE-Gen2.0, 2024), Shukla (Polysolver; RCC Nature 2025 / melanoma Cell 2025),
  Linghua Wang (METI, Nat Commun 2024; Allison Institute 2024), Decker (DOC1021 inventor; CNS 2024 data).
  From the repo (PMIDs API-confirmed per `20260930_ACT_...` §8): Leen (PMID 41482561). From the repo
  (faculty survey, verified 2026-06-17): Zhao, Zhi, Zheng.
- **HPV16+/HNSCC flagship anchors — now web-verified `[2026-10-08]` (identifiers opened + confirmed):**
  Sikora (NCT02002182, window-of-opportunity ADXS11-001 HPV+ oropharyngeal vaccine trial, Study Chair);
  Sastry (PMID 30054333 Cancer Research 2018 + PMID 38400189 Vaccines 2024, senior author on both);
  Jazaeri (PMID 39798550 Med 2025 + PMID 38878765 Med 2024, senior author). Ferrarotto + Piha-Paul were
  already verified. All stay **cold**; no status upgraded.
- **Could NOT verify an individual recent PMID this pass (marked "verify" on the card; the department/center
  is cited):** Sharma, Allison (cold/aspirational, SAB-only); Burks, Kenneth Hu, Matzuk, Weiyi Peng,
  Udugamasooriya, Tsuchikama, Zhiqiang An, Shu-Hsia Chen; and **all of §5** (Danuser, Yang Xie, Lin Xu, Jeon
  Lee, Chao Xing, Xiaowei Zhan, Gibbs, Sedlazeck, Ken Chen, Treangen, Kavraki, Nakhleh, M.Q. Zhang, Palmer,
  Li Zhang, Fofanov, Marcotte, Wilke, Lucchinetti, Joshua Yuan, Budowle, Eisenberg, Schlesinger, Ling,
  Arteaga, Zoghbi, Bhatt, Rogers). Their "hosts" = the named department/center cited in the source map; a
  per-person recent PMID must be pulled before external outreach. Josh Bhatt and several A3/A3b entries also
  need **contact confirmation** ("identify contact" per `20261006_...` §E).
- **Warm/cold preserved exactly:** only the SBMI trio (Zhao/Zhi/Zheng) is warm (affiliation, outreach not
  confirmed); Decker is warm-adjacent via BCM; **every MDACC entry stays cold** and every big-name MDACC
  anchor is flagged as unlikely pre-seed. No cold→warm upgrade was made.
- **IP / data-ownership flags raised:** Zhao's Cancer Genomics Center (fee-for-service; investigator-owned
  data); Haymaker/ORION + Burks + wet-lab cores (fee-for-service; investigator-owned); Grindel/Fu/Matzuk/
  Udugamasooriya (composition-IP boundary on any peptide/macrocycle co-design; CRO fee-for-service assigns IP
  to us, academic co-design does not — define terms); **Tao Wang (UTSW) — nearest competitor, hard IP
  boundary, do not share immune-LLM internals**; Leen (GMP/trial cohort data is clinically owned → federated/
  de-identified only); Borg (EU GDPR cross-border → on-prem/federated framing).
- **Capability honesty:** no card promises SOC 2 / HIPAA BAA / 21 CFR Part 11 / GxP (none exist); the IND
  §2.6.1 / CRO-compliance deliverable is never offered as live (`[A]`, commented out because it crashes);
  single-cell/spatial (Linghua Wang, Kenneth Hu), proteomics (Marcotte, Lizée), and ChIP (M.Q. Zhang) cards
  explicitly flag the unproven-E2E caveat; all predictions are labeled estimates, not wet-lab truth.
