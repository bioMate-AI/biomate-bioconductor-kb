# Home Self-Driving Lab for Macrocycle Target–Drug Validation — Master Plan

**Date:** 2026-10-06
**Owner:** Yaoyun Zhang
**Status:** ACTIVE — hybrid build chosen; orchestrator scaffold started
**Program link:** αvβ6 (PDAC, PDB 4UM9) and GRPR cyclic-peptide macrocycle closed-loop
([[project_macrocycle_closedloop]], [[project_act_target_simplification]], [[project_peptide_pk_learning_gap]])

> This is the living master doc for the workstream (one doc per workstream, updated each step).
> Code scaffold lives at `/Users/kky/sdl-macrocycle/` (standalone, git-init'd; can be linked into
> the macrocycle program repo later). This doc records the reasoning, decisions, spend policy,
> timeline, risks, and a running action log.

---

## 0. Decision record

- **Question asked:** Can a home wet lab be built for target–drug validation without external
  funding (per a cited Harvard-PhD precedent)? Then: budget is not a hard constraint but spend
  deliberately, and **make it automatic ASAP**.
- **Decision:** Build a **self-driving lab (SDL)** as a **hybrid** — cloud lab for immediate
  automation + capital-heavy/rare assays, and an owned Opentrons Flex bench for the 3 recurring
  cell-free assays. Outsource synthesis and all capital-heavy readouts.
- **Rationale:** The automation *is* the product (physical closed loop feeding the αvβ6/GRPR
  models). "Don't spend unnecessary money" resolves precisely for an SDL: automate only the assays
  you run every loop; outsource everything capital-heavy or rare; never automate "make."

---

## 1. Answer #1 — Can it be built without funding? (reality check)

The famous "garage biotech without funding" stories are **computational** (Atul Butte: a drug from
a garage with a computer + public data — that is already your BioMate/closed-loop work) or
**DIYbio molecular biology** (PCR/cloning; a rudimentary bench is well under $50k on used-gear
markets: LabX, BioSurplus, DOTmed).

**Target-based drug *validation*** (does my macrocycle bind αvβ6/GRPR, with what affinity,
selectivity, cell potency, permeability, stability) is a harder category — the binding and
mass-spec readouts are the capital-intensive part, which is where the "no funding" narrative
quietly breaks. Correct framing: **do not build a mini-pharma. Build the cheapest physical
feedback loop for the design models, and outsource every capital-intensive readout.**

### Validation cascade for peptide macrocycles (cheap → expensive)

| Assay | Answers | Home-feasible | Route |
|---|---|---|---|
| Identity/purity | Is it what the vendor said? | Readout no, prep yes | Vendor LC-MS CoA; spot-check at a core |
| Binding affinity (Kd) | Does it bind? how tight? | Partial | FP at home; SPR/BLI at core or used Octet |
| Selectivity | αvβ6 vs αvβ3/αvβ8; GRPR vs bombesin | Partial | Same platforms, counter-screen panel |
| Cell potency | Does it do something to cells? | Yes (BSL-1) | αvβ6 adhesion / GRPR Ca²⁺ flux |
| **Permeability** | Will it get in/through? | **Yes — ideal** | PAMPA (cell-free, plate-based) |
| **Metabolic/plasma stability** | Does it survive? | Prep yes, readout no | Incubate home, LC-MS at core/CRO |
| In vivo PK/efficacy/tox | Works in an animal? | **No** | CRO only (IACUC/GLP) |

**Key corollary:** do **not** buy a peptide synthesizer. Vendors (GenScript, WuXi, Biomatik, CPC
Scientific) make and HPLC-purify macrocycles with a CoA for ~$200–1,500/peptide. That is your
reagent, not your capability.

### Hard constraints (apply regardless of route)

- **Legal/zoning:** residential BSL-1 is legal in most US states; check state + local zoning +
  lease/HOA. Some states regulate DIYbio.
- **Reagent shipping:** many vendors won't ship certain reagents/solvents to a residential address;
  some are DEA/EPA-regulated. Use a registered entity / community-lab membership for those.
- **Biosafety ceiling:** recombinant protein + synthetic peptide + established cell lines = BSL-1/2.
  Primary human tissue, bloodborne pathogens, live virus = **off-limits at home** → CRO/IBC.
- **No animals, no radioactivity, no GLP at home** → CRO.
- **Insurance & waste:** licensed biohazard/solvent disposal contract; homeowner/renter policy
  excludes lab activity → rider or LLC.
- **Data integrity:** informal home data is **internal model-validation/triage grade only**, not
  pivotal for ACT/IND/partnering. Keep regulatory-grade work at qualified CROs.

### Alternative weighed: don't build, *join*
Shared/community labs (BioLabs, university cores) rent bench + instrument + LC-MS time monthly.
For a solo program this out-runs a home build on capability and compliance for the first 12–18 mo.

---

## 2. Answer #2 — Make it automatic (self-driving lab)

An SDL is the closed loop made physical: model **proposes** → peptides **made** → assays run
**hands-free** → data flows **back** to the model.

**Frugality rule for an SDL (precise meaning of "no unnecessary money"):**
1. Automate only the assays run every loop (permeability, binding, stability).
2. Outsource everything capital-heavy or rare (LC-MS, SPR, cell potency, in vivo).
3. Never automate "make" (synthesis robotics = six-figure sink; vendors are better/cheaper).

**The real rate-limiter is synthesis turnaround, not pipetting.** GenScript online Quick Order
(sequence-upload template, **no public API**) returns macrocycles in ~5 days–2 weeks. A fully
walk-away loop is therefore impossible while synthesis is external — and that's fine. Design for it:
automate the **test→learn** arc to run unattended in hours, and **batch** designs (48–96 per order)
to amortize the make latency. Chasing synthesis automation to shave that window is the
"unnecessary money." Don't.

### Two routes → run both (hybrid)

- **Route A — Cloud lab (automated in days, zero capital):** Emerald Cloud Lab / Strateos are
  remote robotic labs driven entirely in code. ECL pitch: a year of access < the upfront cost of
  one instrument. Caveats: subscription + per-experiment billing, fixed assay menu (confirm FP /
  PAMPA / stability support), data latency, documented non-institutional-user friction. Use it to
  **prove the orchestration + model-feedback loop** with zero procurement.
- **Route B — Owned Opentrons Flex bench (cheapest per-run long-term, full control):** Flex (not
  OT-2) because the **gripper** moves plates between modules autonomously — that is what makes it
  walk-away. Open-source **Python Protocol API**; absorbance plate reader natively integrated
  (API ≥ 2.21). Opentrons-integration agent skills already exist → drive it from the same agent
  layer as BioMate.

---

## 3. Chosen architecture (hybrid)

```
 BioMate model (αvβ6 / GRPR) + active-learning policy (Bayesian opt / ranker)
        │ proposes batch                         ▲ updated posterior
        ▼                                         │
 MAKE (human-triggered)                    LEARN (auto)
   → vendor Quick Order (batch 48–96)        parse reader output → Kd / Papp / t½ → DB
        │ plated peptides arrive                  ▲ structured results
        ▼                                         │
 TEST (auto, walk-away) — Opentrons Flex orchestrator
   • PAMPA permeability   • FP competition binding   • plasma/serum stability sampling
   → on-deck absorbance reader; FP/stability readout via gripper-fed multimode reader
     or cloud-lab LC-MS
```

**The orchestrator (Python scheduler wrapping Opentrons API + reader drivers + the model) is the
IP.** It is small, owned, and uncopyable because it is wired to *your* models and *your* data.

### Spend policy

| Buy | Why | Rough cost |
|---|---|---|
| Opentrons Flex + gripper + labware | the one capital item that makes the loop hands-free | ~$30–50k |
| Multimode plate reader (abs + fluor + FP) | FP binding + PAMPA + quantitation; gripper/stacker-feedable | ~$15–40k used |
| 37 °C heat block/shaker, −80/−20 storage, consumables | stability incubation + storage | ~$5–10k |
| Cloud-lab subscription (ECL/Strateos) | day-one automation + assays not built in-house | subscription + per-run |

| Do NOT buy | Use instead |
|---|---|
| Peptide synthesizer / synthesis robotics | vendor Quick Order, batched |
| SPR (Biacore) | cloud lab / core, per-run |
| LC-MS | cloud lab / core for stability + permeability readout |
| Cell-culture automation | keep cell potency on cloud lab until volume justifies |
| Hamilton/Tecan handlers (~$100k+) | Opentrons Flex covers the throughput |

---

## 4. Timeline to "automatic"

1. **Week 1–2 — automate on cloud lab.** Script the 3 assays on ECL/Strateos. No capital, no build.
   Run current top designs → automated loop within ~2 weeks.
2. **Week 1–4 (parallel) — wire the orchestrator.** Python scheduler: model AL output → batched
   vendor order → results DB → model update. Test end-to-end against the cloud lab first.
3. **Week 3–10 — stand up the Flex cell;** port PAMPA + FP binding + stability sampling; migrate off
   cloud lab once reproduced.
4. **Steady state** — Flex runs recurring test→learn unattended; cloud lab/cores handle LC-MS, SPR,
   cell potency, exotic assays; synthesis batched every 1–2 weeks.

---

## 5. Risks / open questions

- **Cloud-lab assay menu:** confirm ECL/Strateos support FP competition binding, HDM-PAMPA, and
  plasma-stability + LC-MS readout for macrocyclic peptides. (Action: vendor call.)
- **FP tracer:** FP binding needs a fluorescently labeled tracer ligand for αvβ6 and GRPR. Source or
  commission (vendor labeling). Without a tracer, binding stays SPR/BLI-only (cloud/core).
- **Reader ↔ robot integration:** Opentrons natively integrates an absorbance reader; FP/fluor needs
  a multimode reader the Flex gripper (or a stacker) can feed. Confirm model compatibility before buy.
- **Synthesis latency** is the hard floor on loop speed — mitigate by batching + a small on-hand
  library, not by automating synthesis.
- **Reagent residential-shipping** restrictions may force a registered entity / community-lab
  membership for part of the reagent list.

---

## 6. Action log

- **2026-10-06** — Decision: hybrid. Created this master doc. Scaffolded orchestrator at
  `/Users/kky/sdl-macrocycle/` (data models, vendor-order worklist generator, cloud-lab + Opentrons
  adapter interfaces, active-learning selection stub, SQLite results store, and **real** assay
  analysis functions: PAMPA Pe, one-site FP Kd with ligand-depletion, first-order stability t½).
  Next: (a) vendor calls to confirm cloud-lab assay menu + FP tracer sourcing; (b) wire the
  orchestrator to the αvβ6/GRPR model's candidate output; (c) dry-run the loop end-to-end against
  cloud-lab stubs.
- **2026-10-06 (same session)** — Scaffold built, verified, committed.
  - Assay-math unit tests green (3/3): PAMPA Pe, FP one-site Kd (ligand-depletion), first-order
    t½ each recover their known forward-simulated values (`pytest -q`).
  - End-to-end loop dry-run runs (`examples/run_loop.py`): propose 60 → select 12 (UCB, per-target
    cap) → order → deliver 11/12 → FP/PAMPA/stability → ranked hit table. Simulated results only.
  - Committed: `sdl-macrocycle` repo `37f1502`; plan doc `c9d69db0b` in biomate-review.
  - Standalone at `/Users/kky/sdl-macrocycle/` (own git repo) to keep the biomate tree clean;
    can be linked into the macrocycle program repo later.

---

## 7. Next steps (actionable)

- [ ] Call Emerald Cloud Lab + Strateos: confirm FP binding / HDM-PAMPA / plasma-stability+LC-MS
      menu, macrocyclic-peptide handling, onboarding time, and per-assay pricing.
- [ ] Source/commission fluorescent tracers for αvβ6 (4UM9) and GRPR FP binding.
- [ ] Confirm multimode reader model that the Opentrons Flex gripper can feed (or a stacker path).
- [ ] Legal/zoning + biohazard-waste + insurance check for a residential BSL-1 bench.
- [ ] Wire orchestrator `select` step to the real αvβ6/GRPR ranker output.
- [ ] Dry-run the full loop against cloud-lab adapter stubs; then first real batch (top ~48 designs).
</content>
</invoke>
