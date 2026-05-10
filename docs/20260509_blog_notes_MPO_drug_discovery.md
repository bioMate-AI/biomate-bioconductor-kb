# Blog Notes: Multi-Parametric Optimization (MPO) in Drug Discovery

Source: `keypoint_newdrugdevelopment.jpg`

## Core Insight

Modern drug discovery is not a linear pipeline — it is a **multi-parametric optimization problem** where activity, ADMET, selectivity, and solubility must all be co-optimized **from the hit-finding stage**. Projects that treat these as sequential gates fail: a late-stage ADMET failure wipes out years of lead optimization.

## Key Principles

1. **Early decisions determine the project ceiling** — hit selection criteria lock in structural chemotypes; changing scaffolds at lead optimization is extremely expensive
2. **Incentive structures are misaligned** — traditional pharma rewards milestones (IND filing) not quality; pushes teams to advance flawed compounds
3. **MPO scoring** — desirability functions weight pIC50 + logP + PSA + hERG + Fsp3 simultaneously; no single-metric optimization
4. **AI role** — generative models (REINVENT, LSTM/transformer + RL) optimize MPO scores jointly rather than sequential filter application

## Common Failure Modes

- Optimizing only potency → ADMET liabilities discovered at Phase II
- hERG not measured early → cardiac safety failure in clinic
- Metabolic stability ignored → short half-life requires BID/TID dosing

## Implications for BioMate

BioMate's ADMET auto-loop already addresses this partially. The gap is **integration**: ADMET score feeding back into generative optimization rather than just flagging failures.
