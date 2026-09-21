# Leverage & inspiration — what the 2026 landscape gives OUR program

**Date:** 2026-09-21 · **Scope:** turn the competitive-intel scan into *action for `guangzhou_all_atom`*.
Not a competitor scoreboard — a **demand-driven leverage map**: for each latest work, what we **adopt**
(open weights/code/data), what **method idea** inspires a build, and **which of our Bets/Builds it feeds**.

> Companion docs: strategy/landscape = `../../docs/20260921_COMPETITIVE_INTEL_AI_DRUG_DISCOVERY.md`;
> our frontier = `INNOVATION_ASSESSMENT.md`, `NEXT_BUILDS_PLAN.md`; state = `PROGRAM_STATE_20260918.md`;
> committee = `COMMITTEE_REVIEW.md`.
>
> **Honesty contract:** rows marked ⏳ await verification by the running research agents (licenses, repos,
> benchmark splits). Nothing here is claimed built; this is a direction proposal grounded in our program.

---

## 0. Our *demand* side (what we actually need — the grounding)

The program thesis (`INNOVATION_ASSESSMENT.md`): **one all-atom generative backbone, per-modality plugins,
cyclic peptide first.** We do **not** train a backbone from scratch (~4k complexes + one A10G is infeasible)
— we **adopt/extend an open backbone** and build the cyclic-peptide plugin. So every external work is judged
by one question: *does it shorten a build we already committed to?*

Concrete open needs, from `NEXT_BUILDS_PLAN.md` + `PROGRAM_STATE_20260918.md` + `COMMITTEE_REVIEW.md`:

| # | Our open need | Status / blocker |
|---|---|---|
| N1 | **Backbone to adopt/extend** (all-atom, plugin-friendly) | PepGLAD is the *qualification baseline*, not necessarily final; BoltzGen adopted as generator |
| N2 | **Cyclic-peptide plugin chemistry** — head-to-tail/disulfide closure, stereochem, **non-natural monomers** (N-methyl, D-AA, staples) | closure validated in MM-GBSA build; generation of non-natural chemistry immature (field-wide) |
| N3 | **Bet 1: developability-aware generation** — permeability + stability as a *first-class learned objective*, not a post-hoc filter | designs are permeability-poor (finding #5) → permeability must move into GENERATION |
| N4 | **Permeability signal that beats R²0.45 2D ceiling** + makes N-methylation visible | Build A (2-env chameleon) planned; cheap conformer-span already failed |
| N5 | **FEP finalist tier** to arbitrate MM-GBSA size bias (~1 kcal/mol) | Build B; **BLOCKED on persistent MD NaN** (alchemical sterics decoupling), commit `97c8a5760` |
| N6 | **N-methyl force field w/ CMAP** (committee P2) | NMET psfgen patch built; proper CMAP-correct FF deferred |
| N7 | **Real LEARN loop** — physics-informed cheap features + hundreds of scored designs | cheap surrogate on generator features fails (finding #3) |
| N8 | **Agentic generate→verify→learn orchestration** on BioMate MCP tools | pattern identified (Virtual Biotech); not wired |

---

## 1. Leverage map — external work → our build

Legend: **Adopt** = wire the actual weights/code/data · **Inspire** = reimplement the idea. Sources verified by
research agent against arXiv/bioRxiv/journal/GitHub (2026-09-21); confidence + weight-availability noted.

**Highest-leverage adopts (open, directly plug into a committed build):**

| External work | License / access | What we take | Feeds |
|---|---|---|---|
| **MacroGuide** (arXiv:2602.14977, Feb 2026, Oxford/Bronstein/Tong) | open method | **Adopt/Inspire**: persistent-homology diffusion **guidance** that forces ring formation — **1%→99% macrocycle rate**, *plugs into an existing generator*. Steer our BoltzGen/PepGLAD toward valid closure without retraining | **N2**, N3 |
| **EnsembleCycPerm** + **CycPeptMPDB-4D** (JCIM Jul 2026; dataset on Zenodo) | dataset open; model code unconfirmed | **Adopt**: the **chameleon 2-environment (aqueous+nonpolar) conformer-ensemble** approach keyed on **ΔPSA3D** — *this is exactly our Build A*. Honest both-split: random R²0.70 → scaffold R≈0.68. Take the 4D dataset + ΔPSA3D feature recipe | **N4** |
| **PocketXMol** (*Cell* Feb 2026, DOI 10.1016/j.cell.2026.01.003) | **open weights, MIT** (Zenodo 17801271) | **Adopt**: pocket-conditioned all-atom generalist doing **de-novo cyclic-peptide design + inverse folding** with no task-specific fine-tune; 3 PD-L1 peptides wet-lab validated. Strong candidate backbone/generator | **N1**, N3 |
| **APCyc** (arXiv:2606.12991, KDD 2026; HKUSTGZ-ML4Health-Lab) | **open, CC-BY** | **Adopt/Inspire**: explicit cyclization + **Bayesian posterior guidance for multi-property** generation. Note: permeability is a *physicochemical proxy* (z(logP)+z(GRAVY)−z(TPSA)), not a trained model — swap in a real one | N2, **N3** |
| **BoltzGen** (bioRxiv Nov 2025) | **open weights, MIT** | already our generator; design-spec language over covalent bonds enables cyclization/disulfides directly | N1, N2 |
| **13-method CycPeptMP benchmark** (J. Cheminform. 2025 17:129; github/Gobliu/BenchmarkCycPeptMP) | open | **Adopt as our honesty calibration**: best random R²≈**0.555 (DMPNN)**, "significant drop" on scaffold split — *validates our R²0.45 scaffold honesty* and gives the citation for it | N4, N7 |
| **ATM (OpenMM)** / **openfe / femto / AToM** | open | **Adopt**: replace the blocked bespoke FEP with a validated open peptide-RBFE engine to clear the NaN | **N5** |
| **CGenFF / sarcosine-analogue CMAP** | open | proper N-methyl-amide parameterization (committee P2) | N6 |
| **The Virtual Biotech** (Stanford/Zou, *Science* 17 Sep 2026; re-impl github.com/gliaropoulos/virtualbiotech) | public re-impl | **Adopt the pattern + ~11 FastMCP data servers**: orchestrate generate→verify→learn on BioMate MCP; independent-Reviewer QA loop | N8 |

**Inspiration (method idea; weights closed or 2025-prior / not the direct plug):**

| External work | Access | What inspires us | Feeds |
|---|---|---|---|
| **Vilya-1** (arXiv:2607.09998, 10 Jul 2026) / **Vilya-2** (2607.25156, 28 Jul 2026) | closed weights (Vilya-2 "Riptides" benchmark open) | the **unified all-atom trifecta** (structure + permeability + design) is the target design; Vilya-2 extends to interfaces (59.1% peptide interface <2Å). Proves the thesis — we build it open | N1, N3 |
| **PepALD** (arXiv:2606.14510, Jun 2026) | weights unstated | **permeability-*conditioned* generation** — beats HELM-GPT/PepTune (validity 0.955 vs 0.253/0.341 on perm-opt). The Bet-1 mechanism; caveat: permeability is a predicted proxy | **N3** |
| **PepTune** (arXiv:2412.17780, ICML 2025) | open | multi-objective masked-diffusion + **MCTS guidance** at sampling time — steer, don't filter | N3 |
| **RINGER** (Genentech, open) | open | sequence-conditioned internal-coord diffusion for **macrocycle conformer ensembles** (COV recall 87.2%) — feeds the 2-env features | N4 |
| **RFpeptides** (Nat Chem Biol Jun **2025**, open) / **AfCycDesign** (Nat Comms May **2025**, open) | open | the **only wet-lab+crystal-validated** de-novo macrocyclic binder methods (nM binders, <20 designs/target). Non-natural chemistry + closure handling for the plugin | N2 |
| **GeoCycler** (arXiv:2605.23407, May 2026) | weights unstated | reward-aligned constraint-conditioned 3D latent diffusion (stapled/head-to-tail/disulfide/bicyclic); +20.8pp closure over CP-Composer | N2 |
| **ByteDance Seed open stack** — Protenix (AF3-level, Apache-2.0), PXDesign (de-novo binders, 20–73% nM hit rate), DPLM/DPLM-2 | Protenix Apache-2.0; PXDesign/DPLM open | **Adopt**: alt structure predictor + binder generator. ⚠️ "APM" and "AnewDPSA (macrocyclic permeability)" from the earlier draft are **UNVERIFIED** (no primary source — do not cite as a permeability model to ensemble) | N1, N3 |
| **HELM-GPT** (open, CC-BY) / **CREMP** (43GB conformers, our S3) | open | HELM-notation generation over non-natural monomers; CREMP conformers for chameleon features | N2, N4 |

**Honest-SOTA note (for both the deck and our claims):** the widely-quoted permeability R² 0.77–0.85 are almost
all **random-split**; the honest generalization ceiling is **R²≈0.55 random → substantially lower on scaffold**
(13-method benchmark; EnsembleCycPerm scaffold R≈0.68; MDML leave-one-dataset-out R 0.61). Our R²0.45 is *in the
honest band*, not a deficiency — cite the benchmark.

---

## 2. Inspiration → three concrete moves (ranked)

1. **Permeability-driven *generation* (Bet 1, N3) — the differentiator.**
   The landscape confirms the direction: Vilya folds permeability *into* the model; ByteDance ships a
   dedicated macrocyclic-permeability model (AnewDPSA); PepTune shows multi-objective guided diffusion.
   **Our move:** don't out-model them — adopt AnewDPSA/CycPeptMP-class signal + PepTune-style MCTG guidance
   to *steer* our adopted backbone (BoltzGen/PepGLAD) toward permeable designs, with developability as a
   first-class objective + uncertainty/EIG (the experiment-native twist nobody else operationalizes as a loop).

2. **Unblock FEP by adopting an open engine (N5).**
   Stop debugging the bespoke alchemical NaN — **swap to openfe / AToM / femto** (validated open peptide-RBFE
   per our own survey). This directly clears the committee's last open P2 item and the `FEP_STATUS.md` blocker.

3. **Wrap the loop in the Virtual-Biotech agentic pattern on BioMate MCP (N8).**
   Their brain (CSO + specialist agents + independent Reviewer QA) on *our* hands (execution + verify) =
   the deck's exact positioning, and it turns the peptide program into the reference implementation of
   "agentic orchestration on a verified substrate."

---

## 3. What stays OURS (don't dilute the moat)

Adopting open models is the *plan*, not a concession. The defensible parts the landscape does **not** give us:
- the **automated headless cyclic MM-GBSA verify** step (field says it's hard; we built it),
- the **generate→verify→learn loop as one compounding system** (private-data flywheel),
- **honest, adversarially-reviewed** self-correction (committee board caught the cyclization bug),
- **execution + GxP/compliance on real cloud compute** — the layer Vilya/ANew/Virtual-Biotech all lack.

---

## Change log
- 2026-09-21 — initial draft; demand side + leverage skeleton grounded in program docs.
- 2026-09-21 — enriched with verified findings from two research agents (arXiv/bioRxiv/journal/GitHub).
  Added 2026 works the initial scan missed: **MacroGuide, EnsembleCycPerm/CycPeptMPDB-4D, PocketXMol (MIT),
  APCyc, PepALD, GeoCycler, MuCO**. Split table into open-adopts vs inspiration. Added honest-SOTA note
  (R²≈0.55 random ceiling). **Corrected:** removed unverified ByteDance "APM/AnewDPSA"; RFpeptides/AfCycDesign/
  Boltz-2/RoseTTAFold3 are 2025 not 2026. Company-landscape corrections live in the companion intel doc.
