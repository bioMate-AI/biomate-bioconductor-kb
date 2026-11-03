"""ADMET as a design constraint must not route a generation request to ADMET prediction.

Measured 2026-11-03 on dev with the exact cold-start payloads: "Generate candidates for this
target with drug-like properties", "Optimise this series for potency without losing
solubility", "Adapt the generative model to our chemical series" all returned Predict ADMET —
the ADMET fast path fires on any "admet", which here came from the intent classifier's
subQuery / the demo context's ADMET cut-offs. Requests whose TASK is ADMET prediction must
keep the fast path.

Run: cd backend && PYTHONPATH=lib pytest tests/test_admet_generation_constraint.py -v
"""
from __future__ import annotations

import pytest

from galaxy.ai.ai_assistant import AIAssistant

constraint = AIAssistant._admet_is_generation_constraint


@pytest.mark.parametrize("intent", [
    # the actual Node intent for cold-start [27] (classifier subQuery + user message), from dev logs
    "fragment-based candidate generation and scoring with ADMET filtering "
    "Generate candidates for this target with drug-like properties.",
    "Optimise this series for potency without losing solubility. Apply the ADMET gate (hERG > 30 uM).",
    "Improve druglikeness while keeping hERG above 30 uM; re-score with ADMET.",
    "Fix the metabolic liability on this scaffold and re-score ADMET.",
    "Adapt the generative model to our chemical series and filter by ADMET.",
    "Design macrocycle candidates with good permeability; ADMET filter on the output.",
    "De novo lead generation for ABL1 with ADMET constraints.",
])
def test_generation_with_admet_constraint(intent):
    assert constraint(intent) is True


@pytest.mark.parametrize("intent", [
    # ADMET prediction / screening IS the task
    "Screen these SMILES for ADMET liabilities and rank them by developability: CC(=O)Oc1ccccc1C(=O)O",
    "Predict ADMET properties for SMILES: CC(=O)Oc1ccccc1C(=O)O",
    "Run ADMET prediction on pilot_compounds.csv and flag hERG risk.",
    # explanation, not generation
    "Why might this hit series be failing on hERG? Cite the evidence. ADMET context attached.",
    # training a PREDICTOR is not generative design
    "Train an hERG classifier on our assay data and gate the design loop on its ADMET calls.",
    # no ADMET at all -> nothing to override
    "Generate candidates for this target with drug-like properties.",
])
def test_admet_task_or_no_admet_keeps_current_routing(intent):
    assert constraint(intent) is False


def test_past_corrections_do_not_count():
    intent = ("Generate candidates for this target.\n\n[Memory context] This user previously corrected:\n"
              "- Suggested: predict_admet_properties → User chose: reinvent4_lead_design (ADMET)")
    assert constraint(intent) is False


# ── task = first paragraph (supporting context after a blank line is not the task) ──
DEMO_CONTEXT = ("\n\nPrepared demo context:\nThese are prepared public tutorial inputs, not new experimental "
                "results. Use the 500 existing BACE compounds in candidate_library.csv as an explicitly labeled "
                "test library. Target for this design exercise is ABL1 ATP pocket, 1IEP.pdb; generate and score "
                "only within this exercise. ADMET gates: hERG > 30 uM, MW < 500.")

generative = AIAssistant._is_generative_task


@pytest.mark.parametrize("goal", [
    "Generate candidates for this target with drug-like properties.",
    "Grow this fragment into a lead-like molecule.",
    "Optimise this series for potency without losing solubility.",
    "Fix the metabolic liability on this scaffold and re-score.",
    "Design cyclic peptides against this binding site.",
    "Adapt the generative model to our chemical series.",
])
def test_generative_goals_with_demo_context(goal):
    assert generative(goal + DEMO_CONTEXT) is True


@pytest.mark.parametrize("goal", [
    # measured false positives when the whole text was matched — the context says "design exercise"/"generate"
    "Predict binding affinity for these candidates against my target.",
    "Dock the top 50 and check the poses are plausible.",
    "Rank these candidates for developability and show me the top 20.",
    "Which candidates pass every safety gate?",
    "Triage this library into synthesise-now and park.",
])
def test_predict_dock_rank_goals_are_not_generative_despite_context(goal):
    assert generative(goal + DEMO_CONTEXT) is False


def test_admet_in_context_of_a_ranking_request_keeps_the_admet_fast_path():
    assert constraint("Rank these candidates for developability." + DEMO_CONTEXT) is False
