"""Two prompt templates so each model is asked the question in its native style.

The Qwen-fine-tuned models were trained on the SFT format from
`scripts/build_sft_corpus.py` (terse system, /no_think prefix, plain user
instruction). Frontier APIs are tuned for natural instruction-style. Using
the SAME template across both would unfairly disadvantage one side.

The orchestrator picks the template via `adapter.style`.
"""
from __future__ import annotations

from .corpus import Example


def render(style: str, ex: Example) -> tuple[str, str]:
    if style == "sft_style":
        return _sft_style(ex)
    if style == "instruction_style":
        return _instruction_style(ex)
    raise ValueError(f"unknown style: {style}")


# ---------------------------------------------------------------------------
# Qwen / SFT-fine-tuned models — terse, format the model was trained on
# ---------------------------------------------------------------------------

def _sft_style(ex: Example) -> tuple[str, str]:
    system = ex.system_prompt
    user = ex.user_prompt
    return system, user


# ---------------------------------------------------------------------------
# Frontier APIs (Claude, GPT, Gemini) — same content, instruction framing
# adds the implicit guidance the SFT corpus bakes into the model weights.
# ---------------------------------------------------------------------------

_INSTRUCTION_PREAMBLE = (
    "You are drafting prose for IND Module 2.6 (Nonclinical Written Summaries) "
    "for FDA / EMA / NMPA / PMDA submission. Your output is scored by 9 "
    "deterministic regulatory checkers; pass ALL nine.\n"
    "\n"
    "GUIDELINE (binding):\n"
    " 1. MRSD calculation: when an MRSD is stated, it MUST be derived from "
    "NOAEL x BSA conversion factor / safety factor (ICH M3(R2) + FDA 2005 MRSD "
    "guidance). Show the arithmetic inline (e.g. \"NOAEL 50 mg/kg / 6.2 (HED) / "
    "10 (SF) = 0.81 mg/kg HED\").\n"
    " 2. Adversity tense: adverse findings ALWAYS past tense, attributed to the "
    "specific dose group (\"At 300 mg/kg/day, transient ALT elevation was "
    "observed in 4/10 males\"). Never present tense.\n"
    " 3. Phase gating: only describe studies appropriate to the phase. A "
    "section 2.6.6 (toxicology) for Phase 1 IND requires 28-day repeat-dose + "
    "genotox battery; do not invent 6-month chronic data.\n"
    " 4. Tabulated/prose consistency: every number that appears in your prose "
    "must appear verbatim in the tabulated source data provided; do not "
    "introduce new numerics, do not round silently.\n"
    " 5. Citation accuracy: cite the specific governing guideline by ID (ICH "
    "M3(R2), ICH S2(R1), ICH S7B, 21 CFR 312.23(a)(8)(ii)(b), EMA/CHMP/ICH/"
    "286/1995). Do NOT fabricate guideline numbers.\n"
    " 6. Hedge language: no over-confident claims (\"proves\", \"demonstrates "
    "that\", \"no risk\", \"completely safe\", \"guarantees\"). Use \"was "
    "associated with\", \"was observed\", \"supports\", \"is consistent with\".\n"
    " 7. Structural: 2-4 sentences, complete paragraph form. Prefix output "
    "with literal token [BioMate-generated draft]. End with the citation in "
    "parentheses.\n"
    " 8. Numeric ranges: doses, exposures, animal counts must lie within "
    "plausible ranges for the species + study type (rat 28-day: typically "
    "10-1000 mg/kg/day; dog 28-day: 1-300 mg/kg/day).\n"
    " 9. Cross-section consistency: do not contradict prior sections in the "
    "same submission (if section 2.6.4 PK reports t-half=4h, section 2.6.6 "
    "tox cannot assume daily accumulation).\n"
    "\n"
    "EXAMPLE (good):\n"
    "[BioMate-generated draft] In the pivotal 28-day repeat-dose oral "
    "toxicity study in Sprague-Dawley rats (Study TX-204), transient, "
    "dose-dependent ALT elevation was observed in 4/10 males at 300 mg/kg/day "
    "and 7/10 males at 1000 mg/kg/day; findings reversed by Day 14 of "
    "recovery. The 100 mg/kg/day dose was identified as the NOAEL, yielding "
    "a Human Equivalent Dose of 100 / 6.2 = 16.1 mg/kg and an MRSD of "
    "16.1 / 10 = 1.6 mg/kg (96 mg in a 60-kg adult), consistent with ICH "
    "M3(R2) and the FDA 2005 MRSD guidance. (ICH M3(R2); FDA 2005 Estimating "
    "the Maximum Safe Starting Dose).\n"
    "\n"
    "EXAMPLE (bad - do not emit):\n"
    "\"This proves the compound is safe at all doses tested. The MRSD will "
    "be 2 mg/kg.\" -- violates checker 6 (hedge), 1 (MRSD shown without "
    "arithmetic), 5 (no guideline cited).\n"
    "\n"
    f"Section type: {{section_type}}, region: {{region}}.\n"
)


def _instruction_style(ex: Example) -> tuple[str, str]:
    system = ex.system_prompt + "\n\n" + _INSTRUCTION_PREAMBLE.format(
        section_type=ex.section_type, region=ex.region,
    )
    return system, ex.user_prompt
