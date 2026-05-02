# Google.org AI4Science — Completed Submission Form
# Questions 16–53 + Budget + Timeline

**Prepared by:** Yaoyun Zhang (Lead PI, BioMate AI)
**Date:** 2026-05-01
**For submission by:** Co-PI ([Sister's name])
**Deadline:** May 1, 2026
**Full proposal:** `docs/20260429_GOOGLE_AI4SCIENCE_PROPOSAL_V2.md`

---

## BEFORE SUBMITTING — Sister's action items

1. **Q49/Q50/Q53** — If you are at a public university, change Q49 and Q50 to **Yes** and add a note in Q53: *"Co-PI [name] is employed by [University], a public institution."*
2. **Q36 / GitHub URL** — Replace `[GitHub URL]` with the real repo URL once Yaoyun creates the `cryoensemble` repository (see `docs/20260429_PROPOSAL_FILLINS.md`).
3. **Author line** — The form asks for organization/PI info; use your institutional affiliation as Co-PI.
4. **Certification (Q53)** — You are the submitting representative; certify on behalf of your institution or BioMate AI as agreed.

---

## Section III — Problem Statement & Solution

### 16. Problem Statement

**16.a — The specific challenge this project addresses is…**
> Cryo-EM systematically misses rare conformational states below ~5% population due to vitrification trapping, air-water interface adsorption bias, and the particle-count resolution floor. These rare states — the ones most relevant to drug discovery — are invisible to every current heterogeneity analysis method. Concurrently, generative AI models predict full conformational ensembles but cannot incorporate cryo-EM experimental density as a conditioning signal. This conformational completeness gap leaves cryptic binding sites undiscoverable in existing datasets.

*(68 words / 75 limit)*

---

**16.b — This challenge is significant because…**
> Approximately 70% of disease-relevant proteins are considered undruggable because their ground-state structures lack accessible binding pockets — yet many transiently sample druggable conformations. PocketMiner estimates 29.4% of human proteins harbor cryptic pockets. If even a fraction are selectively present in rare states, cryo-EM systematically excludes the most important drug targets from structural biology campaigns. With generative AI now capable of predicting these states, the gap between what cryo-EM captures and what AI predicts is bridgeable now.

*(75 words / 75 limit)*

---

**16.c — The core research questions this project seeks to answer are…**
> (1) What fraction of the physically accessible conformational ensemble is systematically missed by cryo-EM heterogeneity analysis — and which protein families are most affected? (2) Can per-particle cryo-EM image likelihoods provide sufficient signal to recover rare states invisible to map-level reconstruction? (3) Can a mixture of generative priors (BioEmu-1, AlphaFold3, ESM3) conditioned on multiple experimental signals converge on thermodynamically accurate conformational posteriors? Traditional methods cannot answer these because they discard particle-level information during reconstruction.

*(73 words / 75 limit)*

---

### 17. Proposed Solution

**17.a — The solution we are proposing is…**
> CryoEnsemble is a multi-modal Bayesian posterior framework that recovers rare conformational states from existing cryo-EM datasets by conditioning a mixture of generative priors — BioEmu-1 (Boltzmann MD dynamics), AlphaFold3 diffusion (all-atom), and ESM3 (language model) — on per-particle cryo-EM image likelihoods and HDX-MS protection factors. Unlike existing methods that condition on reconstructed density maps, CryoEnsemble conditions directly on each particle image, preserving signal from states below the reconstruction floor.

*(67 words / 75 limit)*

---

**17.b — The tools, methods, or techniques we are planning to use are…**
> AI models: BioEmu-1 (Microsoft, JAX/GPU, Boltzmann ensemble sampling), AlphaFold3 diffusion head (Abramson et al. 2024), ESM3 (Meta). Inference: score-based diffusion posterior sampling (DPS) with per-particle cryo-EM log-likelihood and HDX-MS protection factor gradients. Data: EMPIAR particle stacks, BioEmu MD trajectory corpus. Infrastructure: AWS Batch GPU, BioMate Nextflow pipeline orchestration. Validation: CryoBench synthetic benchmarks, EMPIAR experimental datasets, HDX-MS correlations. smFRET validation via planned external collaboration.

*(63 words / 75 limit)*

---

**17.c — The evidence we have that our solution would solve this problem is…**
> Proof-of-concept on adenylate kinase (ADK): 2,000 synthetic particles, 5% rare closed state (7.13 Å RMSD). CryoDRGN fails to represent the rare state (nearest cluster RMSD 7.11 Å). CryoEnsemble's per-particle posterior recovers it (0.82 Å RMSD). Our surrogate-model benchmark across 10 protein families shows 10% of the conformational ensemble consistently missed (lower bound). BioEmu-1 generates large-amplitude domain motions (5–10 Å) validated in published benchmarks (Noé et al., Science 2025), supporting higher gap fractions in real proteins.

*(75 words / 75 limit)*

---

**17.d — Beyond addressing the immediate problem, our use of AI will catalyze lasting impact by…**
> Rare-state structure prediction has been limited by absence of experimental grounding. CryoEnsemble establishes per-particle likelihood conditioning as the field's new standard, enabling any structural biology lab to extract conformational posteriors from existing cryo-EM data without new collection. BioMate deployment makes this accessible to 200+ labs globally. CryoEnsemble demonstrates that generative AI and single-molecule experiments are not alternatives to cryo-EM but multipliers of it — unlocking the full information content of every existing structural dataset.

*(73 words / 75 limit)*

---

### 18. End Beneficiaries

**18.a — The specific populations that will ultimately benefit are…**
> Primary beneficiaries: structural biologists worldwide using cryo-EM for membrane protein, GPCR, and ion channel research — systems where rare-state conformations are most scientifically significant. Secondary: pharmaceutical drug discovery teams seeking cryptic allosteric binding sites in previously undruggable targets. Tertiary: patients with diseases caused by undruggable proteins (GPCRs implicated in cancer, neurological disease, cardiovascular disorders). BioMate's open deployment model ensures access extends to resource-limited academic labs in low- and middle-income countries, not only well-funded pharmaceutical institutions.

*(75 words / 75 limit)*

---

**18.b — Our strategy for centering beneficiary voices is…**
> Year 1: partner with 3–5 structural biology labs as early adopters; monthly feedback sessions on usability, scientific utility, and domain-specific needs. BioMate's existing user community (200+ research groups) provides a feedback pipeline via built-in workflow rating and issue reporting. The co-PI's experimental lab provides ground-truth scientific validation and voices unmet needs in cryo-EM heterogeneity analysis. Year 2–3: public GitHub repository and open BioMate platform enable ongoing community input from structural biologists globally.

*(72 words / 75 limit)*

---

**18.c — The potential reach is…**
> Year 1: 5 early-adopter labs directly using CryoEnsemble, generating validation data on 10 protein targets. Year 2: BioMate deployment reaches 50+ structural biology labs; 3 pharmaceutical partners applying the method to drug discovery pipelines. Year 3: 100+ EMDB datasets processed and publicly released; estimated 500+ individual researchers accessing precomputed posterior ensembles. Long-term: 15,000+ researchers who downloaded cryo-EM heterogeneity tools in the last three years represent the addressable community.

*(68 words / 75 limit)*

---

### 19. Expected Outcomes

**19.a — The specific metrics we will use to demonstrate real-world impact are…**
> (1) Rare-state recall ≥50% (Year 1) and ≥70% (Year 2) on CryoBench, vs. cryoDRGN 0% baseline. (2) HDX-MS correlation r ≥0.65 for flexible regions on ≥2 experimental targets. (3) β₂AR Na⁺ cryptic site conformers enriched ≥2× vs. cryoDRGN clusters (Fisher's exact p<0.05). (4) SERT novel cryptic pocket identified with structural annotation. (5) ≥100 EMDB datasets processed and publicly released. (6) Preprint submitted by Year 1 Q4.

*(62 words / 75 limit)*

---

**19.b — The signals that would demonstrate failure are…**
> (1) CryoEnsemble rare-state recall does not exceed cryoDRGN at Month 12 go/no-go checkpoint — per-particle likelihood insufficient. (2) Posterior distributions collapse to the prior (weight entropy <0.1 bits) — DPS not converging. (3) HDX-MS correlation <0.4 on all targets — posterior ensembles not physically realistic. (4) BioEmu-1 RMSD distributions indistinguishable from the Gaussian surrogate — prior insufficiently diverse. All four trigger formal protocol review and pivot decision.

*(67 words / 75 limit)*

---

**19.c — The changes from baseline we expect to see are…**
> Baseline: cryoDRGN rare-state recall = 0%; conformational completeness gap = 10% (Gaussian surrogate lower bound); β₂AR Na⁺ site not detected in standard reconstruction. Expected changes: rare-state recall increases from 0% to ≥50% by Year 1; gap fraction decreases to ≤5% on EMPIAR datasets; β₂AR Na⁺ site enriched ≥2×; SERT intermediate conformations newly characterized; 100+ EMDB datasets gain public posterior ensemble annotations unavailable from any current tool.

*(65 words / 75 limit)*

---

## Section III — Innovative Use of Technology

**20. What existing technologies will you use?**
> BioEmu-1 (Microsoft Research, JAX): Boltzmann-calibrated conformational ensemble sampling from sequence. AlphaFold3 diffusion head (DeepMind): all-atom multi-chain conformers. ESM3 (Meta): language-model rapid sampling. cryoDRGN (Zhong et al.): baseline comparison. BioMate (AWS/Nextflow): GPU pipeline orchestration, 2,457 deployed workflows. CryoBench (Jeon et al. NeurIPS 2024): evaluation benchmarks. JAX/Haiku/Flax: diffusion posterior sampler implementation. EMPIAR: particle stack data. Adaptations required: custom DPS inference loop coupling three priors; per-particle cryo-EM encoder (256×256 images → likelihood scalars); HDX-MS protection factor encoder.

*(78 words / 100 limit)*

---

**21. Why is a new, custom-developed solution necessary?**
> All current cryo-EM ensemble methods (cryoENsemble, EMMIVox, cryoDRGN) condition on reconstructed density maps, not individual particle images — making it mathematically impossible to recover states below the reconstruction floor. Separately, generative models (BioEmu-1, AlphaFold3) produce conformational ensembles without any experimental conditioning, yielding thermodynamically plausible but experimentally unvalidated distributions. CryoEnsemble is the first method to combine per-particle experimental likelihood with multiple generative priors through a unified diffusion posterior sampler. No existing tool addresses both gaps; simpler reweighting approaches (BME) provably fail at regularization strengths required by noisy cryo-EM data.

*(85 words / 100 limit)*

---

**22. Do you have an existing dataset?** → **Yes**
*(EMPIAR public particle stacks for 16 benchmark proteins; BioEmu-1 MD trajectory corpus)*

---

**23. Ethical risks and Google AI Principles alignment:**
> CryoEnsemble operates exclusively on publicly available structural biology data (EMPIAR, CC-BY licensed) and published generative models. Primary risk: overconfident rare-state predictions used in drug design without experimental validation — mitigated by publishing calibrated uncertainty estimates alongside all posteriors and requiring HDX-MS experimental confirmation for drug discovery applications. Secondary risk: model hallucination of non-existent conformations — mitigated by cross-validation on held-out particle images and HDX-MS correlation checks. All outputs released open-source for community auditing. Aligned with Google AI Principles: beneficial (medicine), human oversight required for clinical decisions, transparent uncertainty, externally reviewable.

*(88 words / 100 limit)*

---

**24. Will all outputs be freely and openly available?** → **Yes**

---

**25. How might you leverage Google's technical support?**
> Three areas where Google expertise would accelerate CryoEnsemble significantly: (1) JAX/XLA optimization — BioEmu-1 and the DPS inference loop are JAX-based; Google engineers' guidance on XLA compilation, pmap multi-GPU parallelism, and TensorFlow/JAX interoperability could accelerate inference 3–5×. (2) Scalable ML infrastructure — training the cryo-EM particle encoder at EMPIAR scale (millions of 256×256 images) requires guidance on efficient data pipelines. (3) Responsible AI — consultation on appropriate uncertainty communication for clinical drug discovery contexts. We commit two team members (Lead PI + ML Research Scientist) for the full six-month program.

*(91 words / 100 limit)*

---

## Section IV — Feasibility

**26. Why is your organization uniquely positioned?**
> BioMate AI combines production-scale cryo-EM infrastructure, diffusion model research, and a deployed bioinformatics platform uniquely suited to this project. The lead PI built BioMate — a platform with 2,457 deployed workflows and demonstrated 1.78 Å cryo-EM reconstruction on EMPIAR-10028 — and has published on score-based diffusion models. GPU Batch execution is verified on real EMPIAR datasets, providing the exact computational infrastructure CryoEnsemble requires. The co-PI brings experimental structural biology expertise: cryo-EM data collection, grid optimization, and HDX-MS capabilities, providing experimental validation ground truth that computational-only groups cannot access. EMPIAR particle stacks are already integrated into the BioMate workflow system. The ADK proof-of-concept (RMSD recovery from 7.11 Å to 0.82 Å) and the 10-protein surrogate benchmark (consistent 10% gap fraction, lower bound) provide documented pilot evidence. No existing group combines deployed GPU cryo-EM infrastructure, score-based diffusion expertise, and experimental validation capability in a single team.

*(150 words / 150 limit)*

---

**27. AI Maturity** → **AI First**
*(AI is core to BioMate's offerings with demonstrated value across 2,457 deployed workflows)*

---

**28. Technical feasibility evidence:**
> (1) ADK synthetic benchmark: per-particle conditioning recovers rare closed state, RMSD 0.82 Å vs. cryoDRGN 7.11 Å (2,000 particles, 5% rare fraction — documented; code at scripts/cryo_pilot/poc_cryoensemble.py). (2) BioMate cryo-EM pipeline: 1.78 Å FSC reconstruction on EMPIAR-10028, verified AWS Batch execution. (3) BioEmu-1 operational on AWS Batch GPU for β₂AR and TRPV1. (4) 10-protein conformational completeness benchmark: consistent 10% gap (Gaussian surrogate lower bound; real BioEmu expected higher). (5) CryoBench baselines computed; cryoDRGN rare-state recall confirmed at 0%.

*(81 words / 100 limit)*

---

**29. Risks, dependencies, and mitigation:**
> **Technical:** (1) BioEmu inference scale — JAX compilation for 700+ aa proteins takes 30+ min; mitigation: S3 checkpoint caching, AOT compilation. (2) DPS convergence — posterior may collapse to prior modes for low-SNR data; mitigation: Month 12 go/no-go checkpoint with clear pass/fail criteria; resampling fallback. (3) AlphaFold3 weight access pending DeepMind approval; mitigation: Boltz-1 and Chai-1 (Apache 2.0) are drop-in alternatives already deployed and tested. (4) GPU quota constraints on AWS us-west-2; mitigation: multi-region deployment and reserved instances by Year 2. **Policy:** (5) EMPIAR data terms — all CC-BY, verified per-dataset. **Administrative:** (6) HDX-MS requires dedicated postdoctoral time; mitigated by Year 1 postdoc hire budgeted at $230K/year. (7) smFRET explicitly scoped as stretch goal (λ_fret = 0 fallback); project viable without it. **Maintenance:** BioMate CI/CD infrastructure sustains deployment; CryoEnsemble models versioned on HuggingFace Hub. GPU costs ~$133K/year average, reducing in Year 3 via spot pricing and model distillation.

*(162 words / 200 limit)*

---

**30. Key team members:**
> **Lead PI (existing):** 10+ years diffusion model research; built BioMate platform (2,457 workflows, AWS production deployment). **Co-PI (existing):** Ph.D. structural biologist; cryo-EM expert, HDX-MS capabilities, protein biochemistry. **ML Research Scientist (hire Y1):** JAX/GPU implementation; DPS inference network; cryo-EM particle encoder training. **Structural Biology Postdoc (hire Y1, co-PI lab):** cryo-EM data collection, HDX-MS experiments, biological interpretation of posterior ensembles. **Data/Platform Engineer (hire Y2):** BioMate scaling, EMDB batch processing pipeline, community API development for 100+ dataset public release.

*(78 words / 100 limit)*

---

### 31. Partner Organizations

**Partner 1:**
- Name: Microsoft Research
- Website: research.microsoft.com
- Role: Developers of BioEmu-1, the primary generative prior. We use their published model and JAX checkpoint. Aspirational collaboration on embedding generation optimization for CryoEnsemble scale. *(27 words / 50 limit)*
- Relationship: **Aspirational partner, not yet contacted**

**Partner 2:**
- Name: European Bioinformatics Institute (EMBL-EBI) / EMPIAR
- Website: ebi.ac.uk/empiar
- Role: Primary particle stack data provider. Existing data-use relationship. Aspirational: co-releasing CryoEnsemble posterior ensemble annotations integrated directly into the EMPIAR database. *(28 words / 50 limit)*
- Relationship: **In contact but not a solidified partner**

**Partner 3:**
- Name: smFRET specialist laboratory (TBD — GPCR or transporter expertise)
- Website: TBD
- Role: External validation collaboration for smFRET population fraction comparison (stretch goal). Requires site-specific dye labeling and single-molecule instrumentation. Budget reserved: $30K contingent. *(30 words / 50 limit)*
- Relationship: **Aspirational partner, not yet contacted**

---

## Section V — Scalability

**32. Scale pathway** — check all that apply:
- ✅ Adaptation to different sectors (protein design, cryo-ET, antibody engineering)
- ✅ Exponential user growth (BioMate open platform, community API)
- ✅ Technical & performance maturity (model distillation, enterprise throughput)
- ✅ Ecosystem & integration (foundational tool for cryo-EM community)

---

**33. Team evolution to support growth:**
> Year 1–2: 5-person core team (2 existing PIs + 3 hires). For Year 3 scale, expand to 8 members: 2 additional ML engineers for distilled inference models and community API; 1 community manager for open-source contributor coordination. Geographic scale requires no additional hires — BioMate's cloud-native architecture serves global users from a single AWS deployment. Sector adaptation (protein design, cryo-ET, antibody engineering) handled by modular encoder architecture: new experimental likelihoods (EPR, NMR) added without core model changes; domain experts engaged as short-term advisors. Revenue-driven scaling: pharmaceutical partnerships ($50–150K/year per client) fund incremental development beyond the grant. The Google.org Accelerator provides mentorship specifically needed for open-source community building and enterprise API strategy — the two scaling dimensions least covered by the current team's expertise.

*(133 words / 150 limit)*

---

**34a. Financial sustainability:**
> BioMate operates a SaaS model with pharmaceutical and biotech clients for computational CRO services. Year 3+ pharmaceutical partnerships ($50–150K/year) and academic institutional licenses ($10–20K/year) sustain the platform. NIH R01 (computational structural biology) and pharma-sponsored research agreements are planned as follow-on funding mechanisms.

*(45 words / 50 limit)*

**34b. Technical sustainability:**
> CryoEnsemble models versioned on HuggingFace Hub; inference code on GitHub under MIT license. BioMate's existing AWS infrastructure sustains compute costs. Open GitHub repository enables community contributions to reduce maintenance burden. Distilled inference models (Year 3) reduce per-query GPU cost ~10×, enabling long-term affordable operation.

*(44 words / 50 limit)*

---

**35. Key learnings and dissemination:**
> Key learnings: (1) whether per-particle conditioning provides sufficient signal across diverse protein families and stack quality levels; (2) which generative prior contributes most to posterior accuracy for different structural motif types (GPCRs vs. transporters vs. enzymes); (3) whether HDX-MS correlation scales as a reliable proxy for ensemble accuracy without direct structural ground truth. All findings published: preprint (Year 1 Q4), peer-reviewed manuscript (Year 2), and a public CryoBench-compatible benchmark dataset released to the community. Open-source model weights and code on GitHub ensure findings are immediately reproducible and extendable.

*(90 words / 100 limit)*

---

**36. Public presence and project visibility:**
> BioMate AI Platform: biomate.ai — deployed bioinformatics platform with 2,457 workflows. CryoEnsemble proof-of-concept code and ADK benchmark results: available at [GitHub URL — fill in before submitting]. BioMate cryo-EM pipeline: 1.78 Å reconstruction on EMPIAR-10028 documented in technical report. Lead PI publication: score-based diffusion models [citation — fill in before submitting]. ADK PoC reproducibility: scripts/cryo_pilot/poc_cryoensemble.py and poc_results.json.

*(60 words / 100 limit)*

---

## Section VI — Project Budget and Timeline

**37. Funding Request** → **$2,500,000**

---

**38. Budget Category 1**
- Name: Personnel & Staffing
- Amount: $1,650,000
- Description: Computational personnel (2 FTE including Lead PI): $320K Y1 / $330K Y2 / $340K Y3 = $990K. Covers Lead PI (0.5 FTE) and ML Research Scientist (1.0 FTE, hired Y1). Experimental personnel (1.5 FTE postdoc + 0.5 FTE technician in co-PI lab): $210K Y1 / $220K Y2 / $230K Y3 = $660K. Covers cryo-EM data collection, HDX-MS experiments, protein biochemistry, and biological interpretation of posterior ensembles. All figures include salary, fringe benefits (~25%), and payroll taxes. *(83 words / 100 limit)*

**39. Budget Category 2**
- Name: Technology Development & Compute Infrastructure
- Amount: $400,000
- Description: AWS Batch GPU compute (g6/g4dn spot instances, ~65% spot discount): Y1 $175K / Y2 $140K / Y3 $85K = $400K. Covers BioEmu-1 inference for 16 proteins (1,000 conformers each), DPS posterior sampler training, and batch processing of 100+ EMDB datasets in Year 3. Spot pricing saves ~$300K vs. on-demand. Year 3 compute decreases as distilled inference models reduce per-query cost ~10×. Includes S3 storage for particle stacks, model checkpoints, and posterior ensemble outputs. *(83 words / 100 limit)*

**40. Budget Category 3**
- Name: Experimental Materials & Validation
- Amount: $220,000
- Description: HDX-MS experiments (deuterium labeling reagents, LC-MS/MS instrument time) for β₂AR, TRPV1, SERT: $90K total. Cryo-EM grid preparation (detergents, lipids, nanodisc assembly, EM grids, liquid nitrogen): $60K. Protein production consumables (expression and purification for 5 targets not in existing lab stocks): $40K. External smFRET collaboration materials reserve: $30K contingent — project proceeds at full scope without it if collaboration is not established. All experimental costs tied to co-PI lab activities in Milestones 2–3. *(78 words / 100 limit)*

**41. Budget Category 4**
- Name: Advisory, Dissemination & Project Amplification
- Amount: $120,000
- Description: Subcontract — advisory expertise in Bayesian inference and diffusion models: $60K Y1 / $40K Y2 / $20K Y3 = $120K. Covers formal advisory consultation on DPS inference design, ELBO training, and publication review. If no specific advisor is identified by Month 6, funds redirect to additional ML compute or conference dissemination. Travel and conference fees (ICLR, ISMB, Cryo-EM Gordon Conference, bioRxiv preprint): $70K total — also covered under this category. *(78 words / 100 limit)*

**42. Budget Category 5**
- Name: Open-Access Publication & Community Dissemination
- Amount: $110,000
- Description: Open-access publication fees (Nature Methods or equivalent, 2 papers): $30K. GitHub/HuggingFace model hosting and CI/CD infrastructure: $10K. BioMate community outreach — tutorial development, API documentation, academic onboarding workshops: $40K over Years 2–3. Journal and data repository fees for EMPIAR submission of CryoEnsemble posterior ensemble annotations: $25K. bioRxiv preprint and CryoBench dataset hosting: $5K. All publications open access; all code and model weights released MIT/Apache 2.0. *(76 words / 100 limit)*

---

## Project Timeline

### 43. Milestone 1
- **Timeframe:** Months 1–9
- **Activities:** Hire ML Research Scientist and Structural Biology Postdoc. Curate BioEmu-1 trajectory corpus and EMPIAR particle stack dataset for 10 initial proteins. Implement per-particle cryo-EM log-likelihood encoder (256×256 particle images → likelihood scalars). Train CryoEnsemble v0.1 on 3 CryoBench synthetic proteins using ELBO training objective. Establish cryoDRGN baseline: rare-state recall = 0% confirmed. Begin BioEmu-1 inference for prior generation on all 16 benchmark proteins via BioMate pipeline. Co-PI lab begins β₂AR protein expression and purification for HDX-MS sample preparation. Set up BioMate automated pipeline for EMPIAR particle stack ingestion. Go/no-go checkpoint (Month 9): CryoEnsemble v0.1 rare-state recall must exceed cryoDRGN on ≥2/3 CryoBench proteins before proceeding. *(122 words / 150 limit)*
- **Outcomes:** CryoEnsemble v0.1 trained and benchmarked; rare-state recall exceeds cryoDRGN 0% baseline on ≥2/3 CryoBench proteins. Per-particle encoder validated on synthetic ground truth. BioEmu-1 pipeline operational for all 16 proteins. Key hires onboarded. Go/no-go checkpoint passed. *(40 words / 100 limit)*

### 44. Milestone 2
- **Timeframe:** Months 10–18
- **Activities:** Train full CryoEnsemble v1.0 with mixture-of-priors (BioEmu-1 + Boltz-1) and DPS inference loop on 10 EMPIAR experimental protein stacks. Apply to β₂AR (EMPIAR-10258) and TRPV1 (EMPIAR-10059). Validate β₂AR Na⁺ cryptic site recovery against Liu et al. 2012 reference geometry. Begin HDX-MS experiments on β₂AR recovered posterior conformers (co-PI lab). Implement HDX-MS encoder: residue-level protection factors → ASA constraint gradients in DPS loop. Test DPS convergence across high-SNR (β₂AR) and moderate-SNR (TRPV1) datasets. Evaluate ESM3 contribution to prior mixture diversity. Submit preprint to bioRxiv. Initiate smFRET collaboration discussions with specialist labs (stretch goal). Hire Data/Platform Engineer (Month 15). *(113 words / 150 limit)*
- **Outcomes:** CryoEnsemble v1.0 achieving rare-state recall ≥50% on CryoBench. β₂AR Na⁺ cryptic site conformers enriched ≥2× vs. cryoDRGN (Fisher's exact p<0.05). TRPV1 gating conformers characterized. HDX-MS data collected; correlation r ≥0.65 confirmed. Preprint submitted. DPS inference runtime ≤4 hours per protein on single GPU. *(48 words / 100 limit)*

### 45. Milestone 3
- **Timeframe:** Months 19–27
- **Activities:** Expand to full 16-protein benchmark including SERT (SLC6 discovery case), A2A, GLP-1R, 5-HT2B, TRPA1, ASIC1a, μOR, Hsp90, p53, HIV-RT, CaM. For SERT: characterize alternating-access intermediate conformations absent from current EMPIAR data; identify novel cryptic pocket candidates in inward-facing and occluded states. HDX-MS validation on TRPV1 and SERT (co-PI lab). BioMate deployment of CryoEnsemble API for 5 early-adopter labs (Data/Platform Engineer). Submit peer-reviewed manuscript targeting Nature Methods. Initiate pharmaceutical partnership discussions with 3 target companies for cryptic pocket discovery validation. Implement model distillation pipeline targeting 10× inference speedup. Begin batch processing of first 50 EMDB datasets. *(108 words / 150 limit)*
- **Outcomes:** All 16 benchmark proteins characterized. SERT novel cryptic pocket candidates identified with structural annotation. HDX-MS validation complete for ≥2 targets. Peer-reviewed manuscript under review. 5+ early-adopter labs using CryoEnsemble via BioMate API. 50+ EMDB datasets publicly released. Pharmaceutical discussions active with ≥2 companies. *(47 words / 100 limit)*

### 46. Milestone 4
- **Timeframe:** Months 28–36
- **Activities:** Complete processing of 100+ EMDB datasets; publish public posterior ensemble resource with BioMate search interface. Pharmaceutical partner validation: 1–2 partners applying CryoEnsemble to internal drug discovery pipelines, validating cryptic pocket recall against proprietary allosteric compound data. Finalize CryoEnsemble v2.0 with distilled inference models (10× speedup) and community API. Present at ICLR, ISMB, and Cryo-EM Gordon Research Conference. Complete open-source release: models on HuggingFace Hub, code on GitHub under MIT license. Assess smFRET collaboration results if established. Submit NIH R01 for continuation funding. Deliver final Google.org impact report with all pre-registered benchmark results and community adoption metrics. *(107 words / 150 limit)*
- **Outcomes:** ≥100 EMDB datasets publicly released. CryoEnsemble v2.0 open-source on GitHub/HuggingFace. Pharmaceutical validation data from ≥1 industry partner. Rare-state recall ≥70% on CryoBench Year 3 target achieved. NIH R01 submitted. ≥50 active researchers using CryoEnsemble. Final benchmark report published openly. *(42 words / 100 limit)*

---

## Section VII — Ethics and Compliance

**48.** Ongoing commercial contracts/negotiations with Google related to this project: **No**

**49.** Government officials employed by organization or on board: **[SISTER TO FILL — Yes if at public university, No otherwise]**

**50.** Government entities involved in project: **[SISTER TO FILL — Yes if at public university, No otherwise]**

**51.** Law enforcement engagement: **No**

**52.** Dealings in sanctioned regions (Crimea, Cuba, Iran, North Korea, Russia, DNR/LNR, Syria): **No**

**53.** If yes to any above: **[If public university: "Co-PI [name] is employed by [University name], a public institution. No government funds will be used in this project; all experimental work occurs within the co-PI's standard academic research activities."]**
*(If all No: enter N/A)*

---

**Certification** → **Yes, I certify**

---

## Summary of items still to fill before submitting

| # | Item | Who |
|---|------|-----|
| Q36 | GitHub URL for `cryoensemble` repo | Yaoyun (create repo, push scripts) |
| Q26 / Q28 | Lead PI publication citation | Yaoyun (or remove clause) |
| Q9 (author line) | Sister's full name, department, institution | Sister |
| Q49 / Q50 / Q53 | Public university disclosure | Sister |
| Q31 Partner 3 | smFRET lab name + website if identified | Both |
| Certification | Submitting representative must certify | Sister (as submitting PI) |
