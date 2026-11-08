# Wet-lab CRO send-panel audit against our own examination chain (2026-10-24)

**Trigger:** "have the sequences we ordered for wet lab passed [our filters]?" Ran the two staged CRO
send panels through the pre-wet-lab gates that are runnable locally (αvβ6 pharmacophore acceptance gate
`cyclic_llm/acceptance_gate.py`, liability/SAR/selectivity `knowledge_liability_flags.py`, merged
rule+FTO+developability `cyclic_llm/score.py`; FTO novelty already in `results/fto_novelty_22.json`).

## Headline — the staged panels do NOT pass our examination

| Panel | n | pass our hard gate | detail |
|---|---|---|---|
| `CRO_SEND_avb6_panelB.csv` | 12 | **0 / 12** | **none contain RGD** — αvβ6 is an RGD-binding integrin; all fail the pharmacophore rule (`PASS_H1_H5=False`, `rule=False`) and liability tier = **HOLD** (`sar:no-lock`, `sar:renal-charge`) for every one |
| `CRO_SEND_pdl1_panelA.csv` | 10 | **0 / 10** | binding **unverified** — no PD-L1 binding rule exists in the gate (`rule=None`); developability/FTO mostly OK (7 PASS, 2 WATCH, 1 HOLD) but no evidence they bind PD-L1 |

The previously-cited "**20/22 passed**" result (`fto_novelty_22.json`) was the **FTO novelty gate only** —
"are these dissimilar to known actives." Non-binders trivially pass that (they are "novel" precisely
because they are not real binders). It is not a readiness signal, and it was being read as one.

### The 12 αvβ6 send sequences (none has RGD)
GRGRNKYYP, NKYRSRRGK, GSLASLGIGRR, ARRGNLAPLG, KGLRGRSG, GLFGGRGRR, RGKLMPGRG, GTGTGSLGRLR, SSRSSLGHLLG,
SRKGIVKGP, GTGIGSLGKLL, APRGALASLG — these are free-generated sequences; `cyclic_llm/rule_bite_avb6.py`
already documented that unconstrained generation yields 0/12 RGD-admissible αvβ6 peptides. This panel is
that failure mode, staged for synthesis.

## We DO have gate-passing αvβ6 candidates — the wrong panel was staged
Running the RGD candidate pools through the same gate:
- **`round4_avb6_candidates.json`: 8/10 pass the hard gate** (AVB6-R4-01/02/03/04/06/07/08/10;
  `PASS_H1_H5=True`, rule+FTO+developability pass). R4-05/R4-09 pass pharmacophore but fail FTO/developability.
- Controls behave correctly: CTRL-TRIVEHEXIN / CTRL-AVEBEHEXIN pass the pharmacophore (`PASS_H1_H5=True`)
  but fail the hard gate on **FTO** (they are known/patented) — exactly as a correct gate should.
- `knowledge_grounded_candidates_v2.json` (AVB6-K-01..10) do **not** pass pharmacophore here (HELM lacks
  the parsed RGD/RGDL) — worth a separate look, but they are not the gate-passing set.

So: valid, gate-passing αvβ6 candidates exist (round4 R4 pool); the CRO send panel used a different,
non-RGD set that our own examination rejects.

## What this means
1. **The examination chain was not applied to the send panel before it was staged.** The gate works — it
   correctly rejects the non-binders and passes the RGD candidates — but it was bypassed for `panelB`.
2. **Do not order/synthesize `CRO_SEND_avb6_panelB` as αvβ6 binders** (and halt it if already ordered):
   by our own rules none can bind αvβ6. PD-L1 panelA binding is unverified (no PD-L1 rule) — do not treat
   it as validated either.
3. **Re-stage the αvβ6 CRO panel from the gate-passing set** (round4 R4-01/02/03/04/06/07/08/10), then run
   the still-pending expensive gates before CRO: quantitative binding (MM-GBSA/FEP — `fep_production.py`,
   control edge already validated) and αvβ6-vs-αvβ3/5/8 selectivity (currently `selectivity_gap="pending"`).

## Caveats / to confirm
- **Confirm whether `CRO_SEND_avb6_panelB.csv` was actually ordered**, or is a stale/erroneous draft — the
  repo shows it staged (`results/`), with an FTO sidecar; it cannot tell me if a PO was placed. (User knows.)
- Local gates cover pharmacophore + FTO + developability + liability. **Binding and selectivity are not
  run** (need GPU/AWS), so even the round4 set is "passes the cheap gate," not "validated binder" yet.
- HELM was reconstructed as head-to-tail `cyclo(residues)` from the CSV `Sequence_N_to_C`; the RGD-absence
  is sequence-level and model-independent, so it is not an artifact of HELM construction.

## This is also the retrospective validation the examination was asked for
The gate **correctly separates** known-valid pharmacophores (round4 RGD candidates pass; Trivehexin/
avebehexin pass pharmacophore, fail on FTO as known compounds) from non-binders (panelB fails). That is a
real, defensible positive about the *examination chain* — and it caught a concrete, costly error.
