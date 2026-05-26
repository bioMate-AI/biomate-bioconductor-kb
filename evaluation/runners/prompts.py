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
    "You are drafting prose for IND Module 2.6 (Nonclinical Written Summaries). "
    "Strict requirements:\n"
    " - Cite the specific ICH or region guideline that governs the section.\n"
    " - Adverse findings: past tense, attributed to the dose group.\n"
    " - Numbers from the input data must appear verbatim in the prose.\n"
    " - No over-confident claims ('proves', 'demonstrates that', 'no risk').\n"
    " - 2-4 sentences, complete paragraph form.\n"
    " - Prefix the output with the literal token [BioMate-generated draft].\n"
    f" - Section type: {{section_type}}, region: {{region}}.\n"
)


def _instruction_style(ex: Example) -> tuple[str, str]:
    system = ex.system_prompt + "\n\n" + _INSTRUCTION_PREAMBLE.format(
        section_type=ex.section_type, region=ex.region,
    )
    return system, ex.user_prompt
