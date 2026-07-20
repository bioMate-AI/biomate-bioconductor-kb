# QC Gate Regulatory Basis Classification

**Date:** 2026-07-15
**Status:** Implemented — `regulatory_basis` field live in `GateResult`, `qc_evidence.yaml`, and SSE events.

---

## The Core Question

Not all QC gates exist for the same reason. Mixing regulatory requirements, literature-based
risk filters, and computational heuristics in the same UI — with the same visual weight — is
misleading. A user should immediately know:

1. **Is this going to block my IND?** — only if a regulatory body requires a response
2. **Can the system help me fix this by re-running with different parameters?** — only if changing
   a filter setting actually changes the outcome
3. **Is this a risk signal I should document?** — always, but the response differs by tier

---

## Three Tiers

### REGULATORY

The gate directly implements a named FDA/ICH/EMA criterion. Failing it means a specific
regulatory action is **required** — not optional, not risk-managed.

Auto-loop behaviour: **emit guidance text only. Never substitute parameter tuning.**
Reason: the compound's properties are what they are. Changing a filter parameter does not
change whether the compound inhibits CYP3A4 or tests positive in the Ames assay.

| Gate | Guideline | Required action when failing |
|---|---|---|
| `ames_mutagenicity` | ICH S2(R1) (2012) | Wet-lab Ames test required; genotoxicity battery before IND |
| `cyp_ddi_r1_basic` | FDA DDI Guidance (2020), verbatim R1 ≥ 1.1 criterion | Clinical DDI study or mechanistic PBPK assessment |
| `cyp_ddi_r2_mbi` | FDA DDI Guidance (2020), verbatim R2 ≤ 0.71 criterion | TDI assay (KI/kinact); clinical DDI study or NDA label |
| `pbpk_auc_fold_error` | FDA PBPK Guidance (2018), 2× fold-error criterion | PBPK model revision; 2× tolerance is the IND standard |

**Note on Ames:** This gate is REGULATORY because ICH S2(R1) mandates the wet-lab Ames test.
The computational predictor is an early warning that the test will likely be positive. The
auto-loop CAN suggest `ames_strict=True` as a **pre-screening** action — filtering structurally
alerted scaffolds before the in vitro test — but it is explicit that the wet-lab test is still
required. The parameter change is scaffold pre-selection, not a regulatory response.

---

### RISK_STRATIFICATION

The gate is anchored to peer-reviewed literature but no regulatory body mandates it as a
pass/fail criterion. Failing it is a risk signal: you may proceed, but should understand
and document the risk. Critically, **changing a filter parameter shifts the risk** — these are
the only gates where auto-loop parameter tuning makes scientific sense.

| Gate | Literature anchor | What "risk" means | Auto-loop eligible? |
|---|---|---|---|
| `herg_ic50` | Redfern 2003, Bowes 2012; industry 10 µM convention | Cardiac arrhythmia risk — not a hard ICH threshold | Yes (heuristic → confident once QSAR descriptors available) |
| `dili_probability` | Lammert 2010 logP>4 + MW>400 boundary | Elevated hepatotoxicity risk | Yes (categorical Lammert fix, confident) |
| `dili_risk_level` | Lammert 2010 | Same | Yes |
| `logp` (Ro5) | Lipinski 1997 | Oral absorption risk | Advisory only — never halts |
| `molecular_weight` (Ro5) | Lipinski 1997 | Oral absorption risk | Advisory only |
| `nca_auc_extrap_pct` | FDA BA/BE Guidance 2003 (healthy-volunteer standard) | Unreliable AUC_inf estimation | Yes — extend sampling window |
| `pbpk_tmax_fraction` | EMA PBPK guideline | Incomplete absorption characterisation | Yes — extend simulation duration |
| `pbpk_mass_balance` | EMA PBPK guideline | Numerical solver drift | Yes — tighten ODE solver tolerance |

**Important:** ICH S7B requires *some* hERG assessment but does not state a numerical IC50
threshold. The 10 µM value is cross-pharma industry convention from Bowes 2012 — a SILVER-tier
threshold. A hERG HALT is a serious risk signal but is not itself a regulatory violation.

---

### OPERATIONAL

BioMate computational conventions — sanity checks on solver output or workflow quality.
No external anchor, no regulatory mandate. Used to catch numerical failures.

| Gate | Basis | Auto-loop eligible? |
|---|---|---|
| `pbpk_cl_min` | BioMate convention (CL < 0.01 L/h is physiologically implausible) | Advisory only |
| `docking_binding_score` | Community heuristic (−7 kcal/mol) | Advisory only |
| `docking_valid_poses` | Community practice (≥3 poses) | Yes — adjust exhaustiveness |

---

## What This Changes in the Auto-Loop

### Before this classification

- A CYP-DDI HALT and a DILI HALT both produced the same SSE event structure
- Both suggested parameter changes (even though you cannot fix CYP-DDI with a filter change)
- A user seeing a CYP-DDI HALT might wait for a re-run to clear it — which will never happen

### After this classification

The `autoloop_update` SSE event now includes:

```json
{
  "regulatory_gate_count": 1,
  "tunable_gate_count": 0,
  "regulatory_actions": [
    {
      "gate": "cyp_ddi_r1_basic",
      "regulatory_basis": "REGULATORY",
      "action_required": "Clinical DDI study required per FDA 2020 guidance R1 ≥ 1.1 criterion.",
      "param_changes": {}
    }
  ],
  "remediations": [...]
}
```

The `autoloop_gate_results` SSE event includes `regulatory_basis` on each gate:

```json
{
  "gate": "ames_mutagenicity",
  "action": "halt",
  "regulatory_basis": "REGULATORY",
  "suggestion": "ICH S2(R1) requires a wet-lab Ames test ..."
}
```

### Auto-loop is only triggered on confident, tunable workflows

The auto-loop (when uncommented for live re-runs) will only trigger on workflows where:
1. At least one `RISK_STRATIFICATION` gate has failed (tunable_gate_count > 0)
2. That gate has a confidence level of "confident" or "heuristic" (not "manual")

It will NOT auto-re-run on:
- Pure REGULATORY gate failures (CYP-DDI, pure Ames package — not pre-screening)
- OPERATIONAL gate failures (parameter tuning won't fix a solver convergence error)
- "manual" confidence failures (system cannot determine the right value)

---

## Implementation Files

| File | Change |
|---|---|
| `experiments/admet_autoloop/qc_evaluator.py` | `RegulatoryBasis` enum added; `regulatory_basis` field on `GateResult`; each gate annotated |
| `experiments/autoloop_bridge.py` | `regulatory_basis` in gate SSE events; `regulatory_actions` list; `tunable_gate_count` / `regulatory_gate_count` in update event; param tuning gated to RISK_STRATIFICATION only |
| `config/qc_evidence.yaml` | `regulatory_basis`, `regulatory_note`, `auto_loop_eligible`, `auto_loop_basis` added to all ADMET and CYP-DDI gates |
