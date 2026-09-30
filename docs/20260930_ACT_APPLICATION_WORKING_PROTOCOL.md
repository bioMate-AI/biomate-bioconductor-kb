# ACT Application — Working Protocol (Cyclic-Peptide Immuno-Oncology)

**Date:** 2026-09-30
**Owner (this doc):** the three technical/strategy lines of the ACT task —
(1) accelerator landscape, (2) top-3 target directions for cyclic-peptide
generation + wet-lab validation, (3) cyclic-peptide generation using existing
models + our own model. The remaining two lines of the ACT task (validation
**quota/cost-as-therapy**, and the **MD Anderson / Texas clinical-collaborator**
map) are owned by a parallel session — referenced here, not duplicated.

**What "ACT" is:** TMC Innovation's **Accelerator for Cancer Therapeutics**
(Texas Medical Center, Houston). Cancer-therapeutics-focused → our submission is
**immuno-oncology only** (the broader immune-LLM covers all axes; for ACT we lead
with the IO cyclic-peptide therapy program). This scope was already fixed in
`20260926_IO_MULTITARGET_MARKET_LANDSCAPE.md` ("ACT / cancer, immuno-oncology only").

**Honesty contract:** demonstrated (approved/failed trials, filed deals, PDB
structures) vs reasoned (mechanistic/topological) vs our forward capability
(not-yet-built) are kept distinct. Deadlines/terms are VERIFY-on-web and dated;
anything unverified is flagged, never asserted.

---

## 0 · The one-paragraph thesis (what we pitch to ACT)

An AI-driven, **immune-mechanism-aware** discovery platform that nominates
non-redundant immuno-oncology targets/pairs and generates **cyclic-peptide**
therapeutics against them through a **dry→wet closed loop** (compute design →
CRO validation → model update). First-in-class shape (from the market landscape):
**not** another checkpoint×checkpoint pair (dead) and **not** "our PD-1×VEGF"
(crowded, >$20B committed) — but a **differentiated macrocycle format** on a
peptide-druggable IO target, with a staged path to an **LLM-nominated novel-axis /
multi-target, tumor-conditional macrocycle** — the sub-niche only Bicycle occupies
(and it is retrenching). Round-1 wet-lab proves the loop on a de-risked target;
the differentiated asset is staged on that proof.

---

## 1 · Accelerator landscape (Task 1)

Web-verified Sept 2026; every material fact carries a source URL in the agent
transcript. Deadlines/terms flagged ⚠️ are aggregator-sourced — **confirm before
relying**. **ACT confirmed** as an excellent, on-thesis fit.

### 1.1 Best-fit programs (the stack to pursue — all keep us in Houston)

| Program | Fit | Stage | Size / terms | Location | Next 2026 deadline |
|---|---|---|---|---|---|
| **TMCi ACT (Accelerator for Cancer Therapeutics)** ★ANCHOR | Cancer-only; explicit immunotherapy + precision drug discovery + **free computational-chemistry (virtual screening, lead-opt, MD)** — maps onto our dry+wet loop | Pre-seed / earliest | **No equity, no fee**; 9-mo; mentors, EIR, grant-writing, CRO + compute access; **TX-based required** | Houston, TMC | **~Oct 30, 2026** (Feb–Sep 2027 cohort) ⚠️confirm yr → act@tmc.edu |
| **CPRIT Seed / Product-Dev (non-dilutive)** | TX cancer co.; AI/IO welcomed; ACT coaches this | Company-formation | **Up to $3.0M / 3yr, no equity**; **50% first-yr match**; TX-domiciled | Texas | Prelim ⚠️~Apr 16 / Full ⚠️Jul 9 (or Jun 10) 2026 |
| **NIH/NCI SBIR (R43/R44)** | Oncology drug dev; peptide+CRO+AI ideal; **no match, no equity** | Feasibility→dev | Ph I ⚠️$314K–$700K; Ph II ⚠️~$2–2.5M+ | US (Houston fine) | **Sept 5, 2026**, then Jan 5 / Apr 5, 2027 |
| **NIH/NCI STTR (R41/R42)** | Same, **requires academic partner** (unlocks TMC tie) | Same | Same; no match | US + non-profit RI | Same NIH cycles |
| **Portal Innovations (TMC Helix Park)** | Only platform with **Houston wet-lab (30k sqft) + seed capital + IO-heavy residents** — operationalizes the loop w/o relocating | Pre-seed→Series A | **$500K–$3M equity** + lab/equipment; terms ⚠️undisclosed | Houston + 3 | **Rolling** |
| **Y Combinator (bio)** | Largest annual biotech funder; AI-native therapeutics OK; no lab; relocate | Pre-seed/seed | **$500K** ($125K/7% + $375K MFN SAFE) | SF (relocate ~3mo) | **Nov 2, 2026, 8pm PT** (verified, W27) |
| **Nucleate Activator (TX chapter)** | Equity-free, Houston-local; **only program w/ cyclic-peptide alumnus** (Unnatural Products); academic-eligibility gated | Academic spinout | **Free, no equity/cash/lab** (mentorship) | TX incl. Houston | ⚠️~late-Oct 2026 (confirm) |

**Off-thesis / disqualifying (do not spend time):** Activate/Cyclotron Road
(**explicitly excludes FDA-path therapeutics** — despite a Houston site);
Techstars (no TX, no therapeutics, no wet-lab); MedTech/BioTools Innovator
(devices/tools only — a drug asset is off-scope); Newlab, Bayer G4A (wrong
profile). **JLABS @ TMC Houston CLOSED Jan 2026** (replaced by TMC's own
Innovation Labs @ TMC — no J&J pipeline). **IndieBio → SOSV NY/SF** (Mar 2026;
strong IO thesis but relocation + no published deadline). MassChallenge 2027
Biotech & Therapeutics (Dallas node, Eli Lilly partner) = clean non-dilutive
add-on when it reopens.

### 1.2 Ranked shortlist (what to apply to)
1. **TMCi ACT — PRIMARY, apply now.** Only accelerator built for early-stage
   cancer therapeutics; free comp-chem resources map onto our loop; no
   equity/fee; Houston (we're already here). Alumni: March Biosciences (CAR-T),
   CrossBridge Bio (ADC). ~50 innovators / ~23 teams per cohort, 77 co. since
   2021 raising >$202M. **Expects:** incorporate during the program + commit to
   an SBIR/STTR or CPRIT submission by program end.
2. **CPRIT Seed — best non-dilutive $.** Up to $3.0M/3yr, zero equity; gate =
   50% first-year match. Pairs with ACT.
3. **NIH/NCI SBIR — largest no-equity capital.** No cost-share; NCI oncology
   ceilings. STTR variant if we want a TMC academic co-PI.
4. **Portal Innovations (Houston) — equity + wet-lab.** Rolling; the physical
   home for the wet side of the loop.
5. **YC W27 (Nov 2, 2026)** — money + brand + AI-native signal; relocation cost.
6. **Nucleate (TX)** — free local parallel shot **if** an academically-affiliated
   founder + university-IP link exists.

### 1.3 Must-have application elements (ACT / IO accelerator)
1. **Traction = real dry+wet loop evidence** — a computationally designed
   cyclic-peptide binder with *experimental* confirmation (affinity + cell-based
   IO activity + early permeability/ADMET). Reviewers discount "AI platform"
   claims without wet-lab proof → **this is exactly what Round-1 generation +
   validation (§2–§3) produces.**
2. **Defensible IP + Texas nexus** — provisional on composition and/or design
   method; FTO awareness; incorporate in TX (ACT requires it; CPRIT requires TX
   domicile).
3. **Team across the dry+wet seam** — design (ML/comp-chem) + validate
   (assay/CRO, translational oncology); a named academic co-PI also unlocks STTR.
4. **Concrete milestones + a specific non-dilutive ask** — IND-directed roadmap
   with go/no-go gates, naming the grant + cycle ("NCI SBIR Ph I, Sept 2026" /
   "CPRIT Seed 2026"). ACT expects a grant submission by program end — enter
   with it drafted.

**Bottom-line stack:** **ACT (anchor, ~Oct 30 2026 — confirm)** + **CPRIT Seed**
+ **NCI SBIR** for capital + **Portal (Houston)** for wet-lab, all Houston-local;
**YC W27** + **Nucleate** as high-upside parallel shots.

**⚠️ Confirm before relying:** ACT "Oct 30" *year* (source omits it; older
article said Oct 13 → email act@tmc.edu); ACT dedicated bench space (compute +
CRO access confirmed, per-team bench not); CPRIT full-app date (Jul 9 vs Jun 10)
+ current ceiling/match; NCI 2026–27 budget ceilings (post-reauthorization, in
flux); Portal/SOSV equity % + deadlines; Nucleate deadline.

---

## 2 · Top-3 target directions for cyclic-peptide generation + wet-lab validation (Task 2)

**Ranking axis:** we optimize jointly for (a) **generatability** — is there a
structure/epitope our design models can condition on?; (b) **validatability** —
is there a cheap, fast, unambiguous wet-lab assay for round 1?; (c) **strategic
fit** — does it advance the first-in-class thesis without walking into a known
graveyard?; (d) **IP cleanliness** — can we claim novel composition, not a me-too.
Grounded in `20260926_IO_MULTITARGET_MARKET_LANDSCAPE.md` §4–§6.

### Direction 1 — **PD-L1 single-target macrocycle** — *the de-risking anchor / platform proof* ✅ round-1
- **Generatability: HIGHEST.** PD-L1 IgV domain; multiple co-crystal macrocycle
  structures (WL12 / pAC65-class; BMS-986189 series) → a well-defined binding
  groove our generator (PepGLAD / RFpeptides) can condition on.
- **Validatability: cheapest + fastest.** Off-the-shelf Promega PD-1/PD-L1
  blockade reporter bioassay + SPR/BLI affinity; co-crystal feasible. Orderable
  in round 1.
- **Precedent = de-risk, not crowding-out:** BMS-986189 reached the clinic then
  **suspended for PK/half-life** — the *chemistry* works; the open problem is
  **developability/PK**, which our permeability scorer + a tumor-conditional
  format directly attack. That is the wedge, not a me-too.
- **Role:** prove the dry→wet loop end-to-end on a target where success is
  unambiguous; produces the traction data ACT wants. **Not** the first-in-class
  story alone.
- **IP:** must design **around** BMS/PeptiDream scaffolds — novelty from a new
  macrocyclic scaffold + conditional gating, not a WL12 analog.
- **Risk:** crowded single-target field → win on format/PK, and keep it as the
  platform-validation vehicle, not the headline asset.

### Direction 2 — **CD47 / SIRPα macrocycle** — *the innate-axis complement, format-differentiated* ⚠️ round-1 stretch
- **Generatability: MODERATE–STRONG.** SIRPα/CD47 interface has structures + an
  existing **macrocyclic SIRPα blocker** (PMID 32640189) and D-peptide binders
  (D4-2, PDB 6LYC-class) → conditionable, but existing affinities are **µM**
  (needs affinity maturation).
- **Validatability:** phagocytosis / blockade reporter assays — established but
  more involved than PD-L1.
- **Strategic role:** opens the **adaptive + innate** combination story (the one
  non-redundant axis class that is mechanistically complementary).
- **The landmine, turned into the pitch:** PD-L1+CD47 is exactly the
  **magrolimab graveyard** (systemic tox + RBC antigen-sink, ~$4.9B write-off).
  A **macrocycle** (short half-life, tunable, tumor-conditional) is a credible
  answer to the *specific* failure mode that killed the antibody — this must be
  argued head-on, not hidden.
- **Risk:** µM starting affinity + the CD47-tox narrative are real headwinds;
  only pursue in round 1 if capacity allows, else stage to round 2.

### Direction 3 — **LLM-nominated novel-axis / multi-target tumor-conditional macrocycle** — *the first-in-class wedge* 🔜 round-2, gated
- **Candidates (partner to be chosen by our pair-nominator, not pre-guessed):**
  CCR8 (Treg depletion — hottest non-redundant axis, BMS-986340 furthest),
  CD73/adenosine (metabolic axis), or a **bivalent PD-L1 × novel-axis** tumor-
  conditional macrocycle — the format "**never built**" per the landscape.
- **Generatability: LOWER / variable.** CCR8 is a GPCR (7-TM → harder peptide
  epitope, fewer clean groove structures); CD73 is enzymatic (has a druggable
  pocket); a bivalent needs scaffold + linker design beyond single-binder
  generation. **Blocked on** running the immune-LLM **pair-nominator** to pick
  the partner with a broken-down evidence rationale (landscape Open Decision #1).
- **Strategic role:** THE differentiated, defensible asset (LLM-nominated novel
  axis + multi-target macrocycle + tumor-conditional gating) — solves the
  systemic-tox / PK failure modes that sank the incumbents.
- **Recommendation:** **do not** spend round-1 generation budget here. Run the
  pair-nominator **in parallel** during round 1; commit Direction-3 generation
  in round 2 once (a) the loop is proven on Direction 1 and (b) the nominator has
  produced a ranked, evidence-broken-down partner menu.

### Recommendation (what to actually generate)
| Round | Generate | Rationale |
|---|---|---|
| **Round 1** | **PD-L1** (Direction 1), + CD47 as stretch | Fastest unambiguous dry→wet proof; cheap assay; de-risks the platform for the ACT pitch |
| **Parallel** | *(no wet-lab)* run LLM pair-nominator | Selects the Direction-3 partner on evidence, not guess |
| **Round 2** | Direction-3 differentiated asset | First-in-class; gated on round-1 proof + nominator output |

---

## 3 · Cyclic-peptide generation protocol (Task 3)

Verified against repo code + internal docs. **Key finding: a full single-round
generation is runnable TODAY on any IO target with a structure** (~$65–90
compute/target/round) — the chain has already been run end-to-end on 4 receptor
targets. Harness root: `research/guangzhou_all_atom/`.

### 3.1 Bottom line
- **Near-term route (runnable now, IP-clean):** **BoltzGen** (open-source
  de-novo cyclic binder design + folding + 9-filter developability) → **our
  cyclic MM-GBSA** physics re-rank (non-circular; iptm⟂ΔG ρ=−0.04) → **our
  permeability GBM** (logPapp, R²~0.45, ranking-grade) → **our GP-Pareto/HVI
  selector** → order 12–15. Proven on 4 targets (best iptm 0.79, 0.45 Å refold,
  9/9 filters).
- **Our own generator (PepGLAD fine-tune "M2c"): trained & works** — DockQ
  **0.437** on 140 cyclic complexes. Usable now as a **diversity arm**, but it is
  **bound-complex-data-limited** (ceiling = ~140 target-bound cyclic complexes,
  not model size). **For the first IO run, lead with BoltzGen** (stronger measured
  results, fully IP-clean); use PepGLAD-M2c alongside — do **not** pitch our own
  generator as SOTA-beating yet.
- **The moat is the loop + proprietary wet-lab/assay data, not any single
  model.** The permeability model is a commodity (R²~0.45, field SOTA ~0.55).
  No published end-to-end macrocycle DBTL loop exists — that is the defensible
  asset.

### 3.2 Capability inventory (runnable-now core)
| Component | Role | Where | Status |
|---|---|---|---|
| **BoltzGen** | primary de-novo cyclic generator + fold + 9 developability filters | public + `boltzgen_ourtarget.sh` | ✅ run on 4 targets |
| **PepGLAD-M2c** (ours) | all-atom co-design diffusion, pocket-conditioned (diversity arm) | `runtime/PepGLAD/` + `m2c_*` | ✅ DockQ 0.437 (MIT) |
| **Cyclic MM-GBSA verify** (ours) | headless head-to-tail build + OpenMM GBn2 physics ΔG re-rank | `peptide_mmgbsa_run.sh` | ✅ 32/32 rings closed |
| **Permeability GBM** (ours) | logPapp ranker (3D-PSA descriptors) | `permeability_predictor.py` | ✅ R²~0.45, ranking-grade |
| **GP-Pareto / HVI selector** (ours) | multi-objective select: bind×physics×perm×SA | `peptide_select.py` | ✅ |
| **DMTA orchestrator** (ours) | chains generate→gate→verify→select→DPO-pair-emit (CPU) | `peptide_loop.py` | ✅ |
| RFpeptides / AfCycDesign / HighFold / ADCP | external comparators / QC / docking cross-check | public, needs install | reference-only |

### 3.3 Pipeline (chosen IO target → orderable panel)
`[0] target prep` (receptor mmCIF + pocket = residues <5 Å of reference ligand,
indexed over **resolved** residues; length 8–16-mer — keep the length-cap fix) →
`[1] GENERATE` BoltzGen (200–500 oversampled) + PepGLAD-M2c diversity →
`[2] A3 gate` (RDKit-valid; SA≤6.5; logPapp≥−7.0 floor) →
`[3] designability` (filter-RMSD <2.0 Å; BoltzGen filters passed) →
`[4] MM-GBSA ΔG` (expensive, non-circular re-rank on survivors; size-bias → rank within-target) →
`[5] permeability/developability` (logPapp as an **objective**, not a hard reject at this maturity — designs run perm-poor) →
`[6] synthesizability` (SA ceiling + cyclization feasibility) →
`[7] SELECT` GP-Pareto front + HVI + diversity → N=12–15 →
`[8] order sheet` → wet lab (synthesis + PAMPA + SPR/BLI) →
`[9] LEARN` assay results → DPO pairs → retrain (**A4 DPO trainer = TO BUILD**;
emitter ready).

**Key thresholds:** iptm prioritize ≥0.6 (strong ≥0.79); consistency ≥0.8;
diversity ≥0.75 (no mode collapse); select top N=12–15 Pareto-optimal.

### 3.4 Compute (spot always; self-terminating; stream to S3)
| Step | Instance | Wall | ~Cost (spot) |
|---|---|---|---|
| BoltzGen generate 200–500 | g5/g6 (A10G), H100 if avail | 1–3 h | $5–15 |
| PepGLAD-M2c diversity arm | g5/g6 / H100 | 1–2 h | $5–10 |
| MM-GBSA verify ~50 survivors | GPU (parallel spots) | ~10 GPU-h | ~$50 |
| gate + perm + Pareto select | CPU | minutes | ~$0.10 |
| **compute / target / round** | | | **~$65–90** |
| wet lab (12–15 pep: synth+PAMPA+SPR) | CRO | 4–8 wk | **~$15–25k** |

Spot fallback g5.xlarge→g5.2xlarge→g6.xlarge→g4dn across us-west-2 AZs;
dead-man's-switch auto-shutdown; 60 s heartbeat (launchers implement this).

### 3.5 IP posture (commercial/therapeutic)
- **Clean:** PepGLAD (MIT, PepBench-trained), BoltzGen (open), our
  MM-GBSA/permeability/loop/selector code, ProteinMPNN (MIT). CRO fee-for-service
  assigns IP to us.
- **Avoid / flag on commercial path:** **HighFold3/AF3 weights** (gated,
  research-only → use Boltz fallback); **HADDOCK** commercial license;
  **RosettaCommons weights** (RFdiffusion/RFpeptides) commercial terms; **ADCP**
  academic terms. CREMP dataset = Genentech CC-BY (attribution only).
- **Protect:** keep the loop + flywheel data proprietary (trade secret); file
  provisionals on novel *compositions* before disclosure.

### 3.6 Ready-now vs. needs-building
**Ready (has been run):** BoltzGen + filters, PepGLAD-M2c, MM-GBSA, permeability,
gate, GP-Pareto, DMTA orchestrator → **a full single-round run on a PD-L1
structure is executable today.** **Needs building to compound the loop:** A4 DPO
trainer (emitter done); unified verify service; native ncAA generation; scaling
the bound-complex corpus (~140→1–2k) to lift the PepGLAD ceiling.

---

## 4 · The ACT application working protocol (assembly)

**A. Narrative** (from §0 thesis + §2 ranking): platform + de-risked round-1
target + staged first-in-class asset; lead with the closed-loop moat.

**B. Traction to show** (the point of round-1 generation): a generated,
folded, physics-re-ranked, developability-filtered PD-L1 macrocycle panel → the
wet-lab validation result (affinity + blockade) → model-update = a *demonstrated*
loop, not a slide. **This is runnable now** — the §3 chain (BoltzGen → MM-GBSA →
permeability → GP-Pareto) executes on a PD-L1 structure for **~$65–90 compute**
and yields the 12–15-candidate order sheet; only the CRO synthesis+assay
(~$15–25k, the parallel session's quota line) and A4 DPO retrain (to build) sit
beyond it. The *in-silico* panel alone is a credible pre-application artifact;
the wet-lab-confirmed hit is the winning one.

**Immediate next action (this program):** run Round-1 PD-L1 generation now —
obtain a PD-L1 IgV co-crystal (PD-1-binding face as the pocket), run the §3
pipeline on spot, produce the ranked panel → decision-gate on ordering. Do **not**
spend round-1 budget on Direction 3; run the LLM pair-nominator in parallel.

**C. Milestones (proposed, to be timeboxed to ACT's cycle in §1):**
1. Generate + in-silico rank PD-L1 macrocycle panel (compute; per §3).
2. Order top-N from an IP-clean CRO; run blockade + affinity (per the parallel
   session's **quota/cost** line).
3. Feed results back → model update → round-2 candidate set (Direction 3).
4. Pair-nominator output → chosen novel axis for the differentiated asset.

**D. Must-have application elements:** _(from Task-1 agent — pending)_ team, IP
position, validation data, defensible milestones, the ask.

**E. Cross-references:** target thesis =
`20260926_IO_MULTITARGET_MARKET_LANDSCAPE.md`; closed-loop mechanics =
`20260721_MACROCYCLE_CLOSEDLOOP_MASTER.md`, `20260730_DRY_WET_CLOSED_LOOP_PROTOCOL.md`;
cost model = `20260721_WETLAB_CLOSEDLOOP_FIRST_ROUND_COST_MODEL.md`;
validation quota + clinical-collaborator map = **parallel session**.

---

## 6 · Business committee review (GPT-5 + Gemini-2.5-pro + Claude, 2026-09-30)

Three advanced LLMs, independent, identical adversarial brief (VC/BD/commercial
lens), reviewing the §2 directions + the all-oncology scope question. **The panel
reordered the §2 ranking** — recorded honestly here; §2 is the original draft, §6
is the committee's correction.

### 6.1 UNANIMOUS (all three — treat as decided)
1. **CUT CD47 (Direction 2)** — not a stretch, gone. Magrolimab $4.9B/mortality
   signal = "commercially toxic/radioactive"; µM affinity burns CRO budget pre-PK.
2. **PD-L1 (Direction 1) is NOT a lead asset** — commodity (~40 binders,
   biosimilar-dominated); a win proves the *loop*, not the *company*.
3. **Direction 3 → the headline, Day-1 not round-2. Run the nominator FIRST,
   before pitching.** The draft staging (PD-L1 de-risk → then Direction 3) is a
   **trap** (PD-L1 traction doesn't transfer; "round-2" never gets resourced).
4. **IO-only is correct — do NOT broaden to all-oncology** (the explicit scope
   question, answered unanimously No). Broadening dissolves the immune moat →
   generic AI-drug-discovery → due-diligence death spiral. Footnote the expansion
   path only.
5. **Monetize the nominator as a product** — paid pair-nomination pilots /
   "Target Intelligence" — for non-dilutive cash + external black-box validation
   before drugging a pair.

### 6.2 STRONG CONVERGENCE — the pivot (all three surface it)
**The real white-space = a tumor-conditional cyclic-peptide CD3 T-cell engager,
not a dual-checkpoint macrocycle.** TCEs are the validated/hottest IO mechanism
(tarlatamab full approval 2025); the *peptide* TCE is empty; a macrocycle's short
half-life + tumor-conditional gating answers the CRS/off-tumor-tox/PK that limit
antibody TCEs. Instantiation: an **AI-nominated TAA×CD3 (or PD-L1×CD3) macrocyclic
engager.** → This should likely *replace* "dual-checkpoint macrocycle" as
Direction 3's lead instantiation.

### 6.3 DIVERGENCE (founder decisions — the panel split)
- **How far to demote PD-L1:** GPT+Claude = keep as a *time-boxed, internal-only*
  loop-proof w/ kill criteria (KD<10nM, >30–100× tumor-conditional activation),
  never pitched as an asset; Gemini = cut entirely (even doing it signals no
  confidence). Reconciler: let the nominator pick the round-1 loop-proof target →
  loop-proof + differentiation from one run.
- **Identity fork:** therapeutics-co-powered-by-platform (Gemini: don't straddle)
  vs platform/BD-product-first, assets-as-validation (Claude: may be *more*
  fundable) vs hybrid w/ capped option-pilots (GPT). Maps onto our own fundability
  thesis (Immunai-style recurring deals + asset-side economics).
- **Sharpest framing (Gemini):** "Resistance & Synergy Engine — we sell solutions
  to clinical failure, not targets."

### 6.4 Consensus plan
Cut CD47 · demote PD-L1 to an internal loop-proof (or replace it with a
nominator-picked druggable target) · **run the pair-nominator now** · lead with a
nominated **tumor-conditional macrocyclic (TAA or PD-L1)×CD3 T-cell engager** ·
stay **IO-only**. Credibility floor (all three): close the dry→wet loop **once**
before pitching.

### 6.5 Founder decision — RESOLVED 2026-09-30: THERAPEUTICS-FIRST
The identity fork (§6.3) is **decided: a therapeutics company powered by the
platform** — Gemini's "don't straddle," not the platform/BD-product-first path.
Implications that now govern the plan:
- **The nominator's job is to generate INTERNAL assets**, and it is validated by
  producing our own lead program (eat-our-own-dogfood), **not** sold as the
  product. It is the engine, the pipeline is the value.
- **Optional pair-nomination pilots** (§6.1.5) are demoted to *non-dilutive
  cash + external validation only* — capped, tied to option-to-license, never
  the business. Do not let pilots become a services trap.
- **Pitch framing:** "a computational-immunology company that delivers its
  insights as proprietary therapeutics" — lead asset = the AI-nominated
  tumor-conditional macrocyclic (TAA or PD-L1)×CD3 engager.
- **The gating dependency is now explicit** (see §6.6): therapeutics-first means
  the lead asset rests on the nominator being real — so finishing the nominator's
  technical validation is the critical path, not optional.

### 6.6 Critical through-line (business ↔ technical)
All three models say the moat is the **pair-nominator** — but the nominator IS the
immune-LLM's target-pair head, which our technical committee finds **not yet
validated**: target-ID fails the degree-null on all 3 axes, batch-leakage ~28×,
and the responder-stratification confound test shows the negative **persists**
(study-leaky-z *content*, not a crude-eval artifact). **#1 priority for the
therapeutics-first plan: make the nominator real (fix batch-leakage → beat nulls)
before it can be the thing we pitch.** This is the same "validate the black box /
close the loop once before pitching" credibility floor the committee named.

Raw model outputs: `scratchpad/committee_{GPT,Gemini}.md` + Claude review in the
task transcript.

---

## 5 · Caveats
- Accelerator deadlines/terms (§1) are web-verified + dated; treat any unverified
  item as flagged, not fact.
- ACT = TMCi Accelerator for Cancer Therapeutics is inferred from the Texas/TMC/
  cancer context + the landscape doc's usage; confirm against the actual program
  the founder is targeting.
- §2 generatability/validatability calls rest on the landscape doc's peptide-
  druggability findings (PD-L1 strong, CD47 moderate, TIGIT none) — Direction-3
  partner peptide-druggability is explicitly TBD pending the nominator + a
  structure check.
- "First-in-class" claims are the *reasoned* strategic thesis, not a filed/proven
  position.
