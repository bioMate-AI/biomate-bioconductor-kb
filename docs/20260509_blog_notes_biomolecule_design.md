# Blog Notes: AI Biomolecule Design — Proteins and RNA

Source: `large_molecul_design.jpg`

## Core Insight

AI-driven design has expanded far beyond small molecules. Two macro-categories are maturing: **protein design** (scaffolds, enzymes, binders) and **RNA design** (aptamers, ribozymes, siRNA). Both share a generative-then-validate loop but differ fundamentally in fitness landscape geometry.

## Protein Design Landscape

- **Cyclic peptides and macrocycles** — RFdiffusion + ProteinMPNN generates cyclic scaffolds; membrane permeability + metabolic stability better than linear peptides
- **Artificial enzymes** — ProteinMPNN with active-site constraints; catalytic residue positioning → de novo enzymes for non-natural reactions
- **Logic circuits** — synthetic gene circuits with protein-based switches; AND/OR/NOT gates from designed binding domains
- **CAR-T binders** — scFv design via ProteinMPNN; antigen-specific VHH (nanobody) generation
- **GPCR modulators** — cryo-EM structure → allosteric pocket identification → binder design

## RNA Design Landscape

- **siRNA design** — automated siRNA generation from mRNA sequence + BLAST-based off-target screening
- **RNA aptamers** — SELEX-derived; AI accelerates sequence-to-structure prediction; targets: proteins, small molecules
- **Ribozymes** — catalytic RNA; therapeutic applications in RNA knockdown (hammerhead, HDV)

## Key Gap: Cross-Family Generalization

Models trained on protein families generalize poorly across fold classes. Membrane proteins, intrinsically disordered regions, and RNA-protein interfaces remain challenging.

## siRNA Platform Notes (from `smallRNA_design.jpg`)

A practitioner built a fully automated siRNA design platform: input mRNA → generate all possible siRNAs → filter top 10% by efficacy score → local BLAST database for off-target scoring. The BLAST local DB can compare 1000+ sequences in 20 minutes vs 3-5 min per sequence on NCBI. This is now table stakes at competitive biotech firms.
