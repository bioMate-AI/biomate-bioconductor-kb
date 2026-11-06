# Integrating the generate–verify–learn cycle into BioMate — grounded design

Verified against BioMate's live catalog (MCP `search_workflow` / `get_workflow_spec`, 2026-09-16). Question
answered: can the *process* (model training/validation cycle), not our specific peptide model, run on
BioMate? **Yes — ~80–90% is already native workflows; the delta is a stateful campaign-orchestration layer.**

## Loop stage → real BioMate workflow (verified IDs)
| Stage | Existing workflow(s) | Evidence |
|---|---|---|
| **Generate** | `biomate-ai-tools/cyclic_peptide_design` (5-phase de-novo **cyclic peptide** design), `biomate-ai-tools/bionemo_structure_design` (Boltz2 / RFdiffusion+ProteinMPNN / DiffDock / **GenMol**+MolMIM+MoFlow — 19 NVIDIA BioNeMo models), `drug_discovery/reinvent4_lead_design` (RL SMILES gen) | confirmed |
| **Verify — physics (non-circular)** | `drug_discovery/amber_pmemd_md` (GPU MD → **MM-GBSA ΔGbind**, AWS), `drug_discovery/gromacs_protein_md`, **`drug_discovery/openfe_rbfe` (alchemical FEP ΔΔG)**, `molecular_dynamics/mlip_md_simulation` (MACE-style) | confirmed |
| **Verify — fast/ML + rank** | `drug_discovery_screening` chain (ADMET → docking → binding-affinity → prioritization) | confirmed chain |
| **Learn / select** | REINVENT4 internal RL (reward `qed_sa`\|`docking_gnina`\|**`custom_toml`**); auto-loop QC gate; `chain` engine | `custom_toml` = reward hook |

My bespoke spot-instance scripts this session were re-implementing capabilities BioMate already ships
(MM-GBSA, FEP, generative design, even a cyclic-peptide pipeline).

## Striking finding: BioMate already has a cyclic-peptide design pipeline that mirrors our program
`cyclic_peptide_design` (5 phases): (A) target-pocket analysis with a **curated autoimmune hotspot DB
(IL17A / IL6R / CALCA / PTPN22)** — same autoimmune framing as our `AutoimmuneCorpusProfile`; (B)
**CyclicMPNN sequence design with N-methylation optimization**; (C) **macrocycle-specific ADMET using
Yudin-2015 rules (NOT Lipinski — MW 500–1200 Da, chameleonic-potential scoring, effective HBD after
N-Me)** — i.e. it already encodes the chameleon/permeability thinking our survey converged on; (D)
**AlphaFold3** input generation for the top-5; (E) IND-prep design report. Explicitly validated against
the **voclosporin / cyclosporin A** oral-macrolactam precedent — the same positive controls in our
`approved_cyclic_peptide_drugs` set. Outputs incl. `rfdiffusion_input.json`.

## Honest comparison: BioMate's cyclic pipeline vs our BoltzGen stack
| Dimension | BioMate `cyclic_peptide_design` | Our BoltzGen stack | Verdict |
|---|---|---|---|
| Generator paradigm | RFdiffusion backbone + **CyclicMPNN** inverse-folding + AF3 fold-check | **all-atom pocket-conditioned generative** with native covalent macrocyclization, wet-lab-validated | complementary; BoltzGen is a distinct, validated all-atom macrocycle generator not in BioMate's set |
| Closure | via RFdiffusion/CyclicMPNN cyclic handling | native covalent-bond spec (head-to-tail/disulfide/staple) | both handle it |
| Verify | ADMET rules + AF3 self-consistency (ML, partly circular) | **physics MD/FEP** (non-circular) — and BioMate already has `amber_pmemd_md`/`openfe_rbfe`, just not wired into this pipeline | **integration opportunity**: wire existing MD/FEP as the verify layer |
| Permeability | Yudin rule-based chameleon scoring | **conformation-aware MD-ensemble** (CREMP + MDML_PeptPerm) — an upgrade | our track upgrades their rules |
| Loop | linear 5-phase (produces candidates, not iterated) | iterated generate→verify→select (what we're building) | **the gap for both** |

Takeaway: don't compete with BioMate's cyclic pipeline — **contribute to it.** Our differentiators
(all-atom BoltzGen generator, physics-in-the-loop, conformation-aware permeability, the closed loop) are
exactly the pieces its linear rule-based version lacks.

## The one real gap: a stateful "closed-loop design campaign"
REINVENT's RL loop is *internal* and uses a *fast* reward (per-epoch) — physics MD/FEP is far too slow to
be that reward. So the generate→**physics**-verify→learn cycle must be an **outer active-learning loop**:
```
round r:  generate           (cyclic_peptide_design | bionemo_structure_design | reinvent4 | BoltzGen)
       →  physics-verify batch (amber_pmemd_md | openfe_rbfe)        ← non-circular oracle
       →  update surrogate on (design → ΔG/permeability) pairs
       →  select next batch    (qNEHVI/MOO) + export surrogate as REINVENT `custom_toml` reward
       →  round r+1
```

### Build items (orchestration layer, not new science)
1. **Campaign object carrying cross-round state** — surrogate model + growing candidate pool persisted
   between rounds (BioMate's auto-loop remediates *params* within one run; this needs a model artifact).
2. **qNEHVI / MOO selection node** as a first-class "learn" operator (vs threshold QC gates).
3. **`custom_toml` bridge** — turn the physics-trained surrogate into REINVENT's per-round reward.
4. **Non-circular-oracle tag** — mark physics verify workflows so the loop can't optimize against its own
   generator's ML scorer (the reward-hacking failure mode the optimization survey documented).

### Reuses that already exist
- Execution: AWS Batch + `nextflow_executor` + run-state persistence + `watch_run`/SSE (replaces my raw
  `run-instances` + `/tmp` monitors).
- Multi-workflow wiring: the `chain` engine (output→input connections + prioritization).
- Gating/reporting: auto-loop QC, findings panel, `export_report`, billing/quota.

## Recommendation
The training/validation cycle is a strong, general BioMate feature — a **"closed-loop design campaign"
engine** usable for peptides *and* small molecules. Concrete path:
1. **Wire existing MD/FEP (`amber_pmemd_md`, `openfe_rbfe`) as a verify stage** after `cyclic_peptide_design`
   / BoltzGen output — immediate non-circular-oracle upgrade, zero new science.
2. **Register BoltzGen (or our cyclic model) as an alternative generator** alongside `cyclic_peptide_design`.
3. **Upgrade permeability** from Yudin rules to conformation-aware (CREMP + MDML_PeptPerm) as a scoring node.
4. **Build the outer campaign orchestrator** (items 1–4 above) — the ~10–20% that doesn't exist yet.

My spot-instance prototype this session is exactly what BioMate should run natively; the honest next step
for productionization is to move it onto BioMate rather than extend the bespoke scripts.
