# CRO antibody & reagent decision — αvβ6 / PD-L1 cyclic-peptide program

**Date:** 2026-10-19 · Decision record for the CRO's offer to produce antibodies (they are strong at
antibody expression and asked whether we need any). Covers what we need, what we don't, and why. Ties to
the current synthesis order `docs/20261014_CRO_ORDER.csv` and the program master `docs/20261014_CYCLIC_PEPTIDE_PROGRAM_MASTER.md`.

## Context
The CRO asked us to name "two antibodies" they could check for public VH/VL and produce recombinantly.
They raised it because antibody production is their strength — i.e. an offer, not a program requirement.
Our modality is the **cyclic peptide** (αvβ6 radioligand; PD-L1 blocker); we do **not** develop antibodies
as therapeutics. Antibodies are only ever **assay tooling / comparators** here.

## Decision (one antibody, not two)

| Target | Antibody? | Rationale |
|---|---|---|
| **PD-L1 (blocker)** | **YES** — one reference **anti-PD-L1** (atezolizumab or avelumab) | A PD-1/PD-L1 **blockade** assay's gold-standard positive control is a clinical anti-PD-L1. Head-to-head benchmarking of our macrocyclic blocker vs the antibody standard of care is scientifically meaningful and expected by partners/investors. VH/VL are **public**, so recombinant production is cheap/clean. |
| **αvβ6 (radioligand)** | **NO** | αvβ6 binding is at the **RGD/MIDAS site**; our comparators are the **peptide binders** (avebehexin, Trivehexin-mono), already on the synthesis order as DOTA-conjugated positive controls (`CRO_ORDER.csv` rows 5–6). An anti-αvβ6 mAb (e.g. BG00011/STX-100) binds a **different protein epitope** and stabilizes the opposite (bent-closed) conformation — not a valid comparator for an RGD-site radioligand. Off-the-shelf anti-αvβ6 suffices if cell-expression QC is ever needed. |

## The higher-value ask for a protein-capable CRO: target antigens
The reagents that actually gate the assays are the **antigens**, not antibodies: recombinant **αvβ6**,
**PD-L1**, and especially **PD-L2**. PD-L1/PD-L2 selectivity is the **documented bottleneck** of the PD-L1
program (G2: 0/8 selective; see program master §3), so a **PD-L2 counter-screen** alongside PD-L1 is
high-value. Direct their protein-production capability here.

## On the αvβ6 controls (not a waste)
`CRO_ORDER.csv` already includes **avebehexin (#5)** and **Trivehexin-mono (#6)** as DOTA-conjugated
positive controls. These are required, not redundant: (1) positive control that the assay detects αvβ6
binding at all; (2) two known binders → **A2 rank-order recovery**, which is what makes the hop ranking
trustworthy; (3) **monomeric** references matched to our monomeric hops (M7/M11/SL/BCY). The trivalent
**Trivehexin trimer** is a separate, **optional, finalist-stage** benchmark (avidity/clinical-parity
claim) — not needed to rank candidates now.

## Email sent
A reply to the CRO (below / sent 2026-10-19) communicates: yes to one anti-PD-L1 (atezolizumab/avelumab,
public VH/VL); no anti-αvβ6 (peptide controls already ordered); and points their protein capability at the
αvβ6 / PD-L1 / PD-L2 antigens, flagging PD-L2 for the selectivity counter-screen.

## Open items to confirm (not blockers)
- Confirm the two antibodies the CRO meant were indeed one-per-target (αvβ6 + PD-L1), not something specific.
- Decide whether this synthesis round needs all four PD-L1 candidates (K-05 is the only selective lead;
  A08/F05/F13 were non-selective) or should be scoped to K-05 + the αvβ6 set + the two controls.
