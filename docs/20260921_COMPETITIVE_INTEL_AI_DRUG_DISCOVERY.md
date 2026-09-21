# Competitive intel — AI drug discovery landscape (note, 2026-09-21)

Research note for the Guangdong pharma strategy / deck. Facts cross-checked from primary sources by research
agents; **confidence flags** included. Strategic read at the end. Three-layer framing: ① foundation models,
② agentic orchestration, ③ execution (BioMate's layer).

---

## ① Vilya / Vilya-1  (peptide foundation model) — *likely the "Molo-1 / Atomelogy" reference*
- **Name resolution (HIGH confidence, UNVERIFIED with user):** no real entity "Molo-1" or "Atomelogy" found
  (English + Chinese search). Description matches **Vilya-1** on every attribute; "Molo-1" ≈ phonetic of
  "Vilya-1", "Atomelogy" ≈ its all-atom identity. **Vilya is US (Seattle + South SF), not Chinese** — the
  user's "多肽" was likely just the topic. *If a genuinely distinct Chinese "Molo-1" exists, not found; ask user.*
- **What:** all-atom deep-learning **macrocycle foundation model** unifying (1) conformation/structure
  prediction, (2) property prediction incl. **membrane permeability**, (3) **de-novo macrocycle design**.
- **Tech:** unified Transformer + diffusion; triangle attention/multiplication + pair-bias attention; heavy-atom
  representation (canonical + non-canonical residues + non-peptidic fragments + small molecules); NVIDIA
  cuEquivariance kernels.
- **Benchmark:** 66 cyclic-peptide X-ray set, near-native ring RMSD <1Å: **Vilya-1 89.2%** vs Boltz-2/RF3 ~15%,
  Prime-MCS 37.6%, RDKit ETKDGv3 34.5% — ~2× physics methods; strong on non-standard-AA macrocycles.
- **Release:** arXiv 2607.09998 (10 Jul 2026); Vilya-2 arXiv 2607.25156. **No public code/weights — preview/commercial only.**
- **Company:** launched Aug 2022, IPD/UW spinout; scientific founder **David Baker** (2024 Nobel), CEO Cyrus
  Harmon; **$71M Series A** (ARCH, NVIDIA/NVentures, Menlo, Madrona). Pipeline: oral macrocycles — integrin
  α4β7 (IBD) most advanced. Site: vilya.ai.
- **Relevance to us:** does EXACTLY our cyclic-peptide trifecta (structure + permeability + design), and beats
  BoltzGen-class structure. Serious. But **closed** (no platform, no execution).

## ① ANew Labs / ByteDance  (foundation models + closed pipeline)
- ByteDance AI-drug unit, **spun out Jun 2026**, **$290M @ ~$1.5B** (ByteDance 56%); Shanghai + SF + Singapore;
  lead Liu Kai; descended from ByteDance Seed "AI for Science" (Quanquan Gu, Zaixiang Zheng).
- **Funding (verified):** **$290M first external round, ~16–17 Sep 2026, at $1.5B valuation** (HSG/IDG/Hillhouse
  lead; ByteDance retains ~56%). Reuters-originated, HIGH but secondhand.
- **Open (VERIFIED, ByteDance Seed):** **Protenix** (AF3-level, Apache-2.0), **PXDesign** (de-novo binders,
  20–73% nM hit rate), **DPLM/DPLM-2** (diffusion protein LM). Anew-branded: AnewOmni (generative, >5M complexes),
  AnewFold, AnewSampling (all-atom MD), AnewMind (reasoning LLM), AnewDesign (antibody).
- ⚠️ **CORRECTION:** the earlier-cited **"APM" and "AnewDPSA (macrocyclic-peptide permeability)" are UNVERIFIED**
  — no primary source found. Do NOT cite AnewDPSA as an adoptable permeability model. The Anew-branded ↔ Seed
  open-model mapping is inferred, not stated.
- **Pipeline:** oral pan-spectrum IL-17 (shown AAI Boston Apr 2026) + IL-4R + 2 undisclosed, all **preclinical**
  (no IND stage disclosed).
- **Relevance:** direct peptide/generative competitor AND an integration source (Protenix/PXDesign/DPLM are the
  real open pieces we can wire in — see leverage doc).
- **Relevance:** direct peptide/generative competitor AND an **integration source** (open models we can wire in).

## ② The Virtual Biotech  (agentic orchestration) — Stanford, Zou lab
- ***Science*, 17 Sep 2026, DOI 10.1126/science.aeg6779** (Zhang, Eckmann, Miao, Mahon, Zou). Preprint bioRxiv
  10.64898/2026.02.23.707551.
- **Architecture:** 11 standing agents — CSO orchestrator + 8 specialist scientists (4 divisions: target,
  safety, modality, clinical) + Chief of Staff + **independent Scientific Reviewer (QA loop)**; scales to
  **~37,000 ephemeral per-trial agents** (55,984-trial meta-analysis, ~6h). *(User's "370k" ≈ off by 10×.)*
- **Stack:** **Claude** (Sonnet 4.5 + Haiku 4.5) via Claude Agent SDK; **~11 public-data FastMCP servers**
  (Open Targets, ClinicalTrials, PubMed, cellxgene, cBioPortal, OpenFDA, DailyMed, DepMap, gnomAD, tabula_sapiens, tahoe).
- **Result:** proposed B7-H3 ADC (lung cancer) on pre-2025 data; Merck's *ifinatamab deruxtecan* (same strategy)
  later won FDA Breakthrough — **external convergence, NOT wet-lab validation. In-silico only.**
- **Code:** official private; public re-impl **github.com/gliaropoulos/virtualbiotech** (Claude Agent SDK +
  FastMCP + scanpy/statsmodels/lifelines). Emits reproducible per-run workspace (reasoning + tools + code + figures).
- **Relevance:** the orchestration PATTERN to adopt (on BioMate's MCP tools); its MCP data servers to integrate.
  **Complementary — it reasons, it does not execute.**

## ③ BioMate  (execution — our layer)
- 4,017 workflows / 36 domains on AWS Batch → verified artifacts; MCP-native; drug_discovery domain (ADMET,
  docking, MD, PK/PD, PBPK, stability, BOIN, FAERS, IND narrative, CRO compliance); generate→verify loops +
  auto-QC + reports. **Only layer here that actually runs & verifies.** Live proof: cyclic-peptide
  generate-verify-select engine, adversarially committee-reviewed (research/guangzhou_all_atom).

## Peer mentions (context)
- Peptide/macrocycle: Circle Pharma, Bicycle Therapeutics, Generate:Biomedicines, PocketXMol (Tsinghua, *Cell*
  2026), BoltzGen (open), RFpeptides/AfCycDesign, Boltz-2, RoseTTAFold3.
- AI-drug general (verified 2026): **Isomorphic Labs** ($2.1B Series B, May 2026 — largest AI-drug raise, *corrects
  the earlier ~$600M*; Lilly/Novartis/J&J; first IND targeted end-2026); **Recursion** (REC-4881 FAP Ph2 readout
  Nov 2026); **Xaira** (>$1B, X-Cell virtual-cell Mar 2026, preclinical); **Insilico** (**rentosertib IPF now
  Phase III, launched Jul 2026**; HKEX IPO Dec 2025 — strongest AI-drug clinical proof point); **XtalPi** (HKEX,
  DoveTree "$6B" = mostly biobucks); Baidu/**BioMap** (xTrimo ~100B PLM, HK IPO filed Mar 2026); Tencent iDrug
  (platform-only, Insilico partnership Jul 2026).
- Established peptide/macrocycle (verified 2026): **Circle Pharma** ($92.5M Series E incl. Lilly, Sep 2026;
  CID-078 oral cyclin A/B **RxL PPI** in Ph1 — *not CDK*; platform = **MXMO™**); **Bicycle** (nuzefatide pevedotin
  ex-BT5528 now lead, PDAC Ph2); **Unnatural Products** ($45M Series B Mar 2026; Novartis ~$1.7B biobucks Feb 2026;
  running a real DBTL loop behind closed doors — no methods paper); **Generate:Biomedicines** (**IPO Mar 2026,
  NASDAQ: GENB**; GB-0895 anti-TSLP Ph3; Chroma open).

## Strategic read (for the deck)
1. **Layers ① and ② are crowded and commoditizing/open; ③ (execution+verification) is uncontested and defensible.**
2. **Do not out-generate Vilya/ANew** — their models are strong and often open. **Compose them** as generators
   inside BioMate; win on **verified execution + honest verify-learn + compliance**.
3. **Virtual Biotech is the pattern, not a rival** — its brain on BioMate's hands = the differentiated product.
4. **Pharma edition = subset of BioMate resources + composition** (open FMs + agentic orchestrator + GxP), built
   as a **vertical, not a fork**.
5. **Honest:** our peptide work is in-silico/preclinical (as are theirs); wet-lab remains the ultimate gate.

## Landscape honesty (verified — use these to stay credible)
- **Clinical proof is rare.** Only **Insilico (rentosertib, Ph3)** and **Recursion (REC-4881, Ph2 readout Nov 2026)**
  have meaningful clinical-stage *AI-discovered* assets. The direct peptide/macrocycle+AI cohort (Vilya, ANew,
  UNP, Circle) is uniformly **pre-IND or early Ph1** — the field is young; the moat today is platform + deal-flow,
  not clinical data.
- **"Biobucks" are inflated.** Headline deal values (XtalPi–DoveTree "$6B", UNP–Novartis ~$1.7B, Isomorphic ~$3B)
  are milestone-loaded; near-term upfronts are ~1–3% of the headline. Frame competitor deals accordingly.
- **Agentic-orchestration white space is real but verify before over-claiming.** Closest analogs (ANew's AnewMind,
  Tencent Hunyuan-iDrug, Insilico MMAI Gym) are not publicly positioned as *agentic multi-tool orchestrators* on a
  verified execution substrate the way BioMate is — but run a dedicated search before asserting "no competitor."
- **Closed-loop DBTL for macrocycles:** no *published* academic exemplar (a real gap to demonstrate), but industry
  (esp. Unnatural Products) is already doing it privately — say "no published executed exemplar," not "nobody does it."

## Recent cyclic-peptide works (2026) → leverage
See the program-side synthesis `research/guangzhou_all_atom/docs/20260921_LEVERAGE_AND_INSPIRATION.md` for the
adopt-vs-inspire map. Highlights the deck should reference: **PocketXMol** (*Cell* 2026, MIT open — pocket-conditioned
cyclic design), **MacroGuide** (ring-closure guidance, 1%→99%), **EnsembleCycPerm** (chameleon 2-env permeability),
**PepALD/APCyc** (permeability-conditioned generation), and the **13-method benchmark** (honest R²≈0.55 random ceiling).

## Open item
- Confirm the "Molo-1 / Atomelogy" → Vilya-1 mapping with the user (mapping is high-confidence per fetched arXiv
  2607.09998 / 2607.25156; Vilya is US/Baker-IPD, not Chinese).
