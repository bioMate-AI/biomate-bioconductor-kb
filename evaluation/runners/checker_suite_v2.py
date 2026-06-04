"""LLM-judge eval (v2) for regulatory LLM outputs.

Replaces the regex-based checker_suite.py which rewarded input regurgitation
and penalized correct regulatory writing. See docs/20260603_V6_EVAL_DIAGNOSIS.md.

Per-example Claude Opus 4.7 judge with a strict 6-dimension rubric (0-2 each,
total 0-12 -> normalized to 0-1).
"""
from __future__ import annotations

import json
import os
import re
import time
from dataclasses import dataclass
from typing import Optional


JUDGE_MODEL_DEFAULT = "claude-opus-4-7"
JUDGE_MAX_TOKENS = 800

RUBRIC_DIMENSIONS = [
    "substance",
    "citation",
    "transformation",
    "adversity_tense",
    "numeric_consistency",
    "ich_m4_shape",
]

JUDGE_SYSTEM_PROMPT = """You are an FDA/ICH-trained regulatory writer grading a candidate IND section 2.6 paragraph.

You will receive:
  - SECTION_TYPE (tox_overview, pbpk, tox_genotox, tox_cardiac, admet, pk_overview, overview, ...)
  - PROMPT: the input given to the model
  - CANDIDATE: the model output

Score the CANDIDATE on six dimensions, each 0/1/2.

1) substance: 2 if any required computation (NOAEL->HED->MRSD) is correct using right BSA factor
   (6.2 mouse, 12.3 rat, 3.1 monkey, 8.0 dog) and right safety factor (default 10), and most
   sensitive species chosen correctly. For non-computational sections, 2 means substance is
   accurate. 1 = partial. 0 = wrong / generic.

2) citation: 2 if correct guideline for section_type:
   tox_overview -> ICH M3(R2) and/or FDA 2005 MRSD;
   tox_genotox  -> ICH S2(R1);
   tox_cardiac  -> ICH S7B;
   pbpk         -> EMA/CHMP/EWP/37498/2011 or FDA 2018 PBPK;
   admet        -> ICH M4S;
   pk_overview  -> ICH M3, ICH E5;
   overview     -> 21 CFR 312, ICH M4.
   Do NOT confuse M4 (format) with M3 (safety), or S7B (cardiac) with S2 (genotox).
   1 = real guideline but wrong section. 0 = none or fake.

3) transformation: 2 if regulatory paragraph - terse, transforms inputs into a conclusion.
   No markdown headers, no LaTeX, no bullet lists restating inputs.
   1 = mostly prose with tutorial framing. 0 = tutorial / Q&A / restates question.

4) adversity_tense: 2 if past-tense adverse findings and no overclaims (no "safe",
   "well tolerated", "no toxicity"). 1 = one slip. 0 = present-tense or overclaim.
   For non-tox sections, 2 if no overclaims.

5) numeric_consistency: 2 if every number is verbatim from prompt or correctly derived
   (NOAEL 25 monkey / 3.1 BSA = HED 8.06). 1 = mostly traceable, one slip.
   0 = invented numbers or frank arithmetic error.

6) ich_m4_shape: 2 if present-tense section framing, past-tense findings, citation in parens,
   single coherent paragraph. 1 = minor drift. 0 = bullet list / Q&A / multi-section markdown.

Return ONLY JSON, no prose, no markdown fence:
{"substance":0,"citation":0,"transformation":0,"adversity_tense":0,"numeric_consistency":0,"ich_m4_shape":0,"rationale":"<=200 chars"}
"""


@dataclass
class JudgeResult:
    rubric_scores: dict
    macro: float
    rationale: str
    error: Optional[str] = None


_client = None


def _get_client():
    global _client
    if _client is not None:
        return _client
    from anthropic import Anthropic
    key = os.environ.get("ANTHROPIC_API_KEY", "").strip()
    if not key:
        raise RuntimeError("ANTHROPIC_API_KEY not set")
    _client = Anthropic(api_key=key)
    return _client


def _strip_thinking(text: str) -> str:
    return re.sub(r"<think>.*?</think>\s*", "", text, flags=re.DOTALL).strip()


def _parse_json(raw: str) -> Optional[dict]:
    raw = re.sub(r"^```(?:json)?\s*|\s*```$", "", raw.strip(), flags=re.MULTILINE)
    m = re.search(r"\{.*\}", raw, re.DOTALL)
    if not m:
        return None
    try:
        return json.loads(m.group(0))
    except json.JSONDecodeError:
        return None


def _call_judge(section_type, prompt, candidate, judge_model):
    client = _get_client()
    user = (
        f"SECTION_TYPE: {section_type}\n\n"
        f"PROMPT:\n{prompt}\n\n"
        f"CANDIDATE:\n{candidate}\n\n"
        "Return the JSON only."
    )
    kwargs = dict(
        model=judge_model,
        system=JUDGE_SYSTEM_PROMPT,
        messages=[{"role": "user", "content": user}],
        max_tokens=JUDGE_MAX_TOKENS,
    )
    if "opus" not in judge_model:
        kwargs["temperature"] = 0.0
    resp = client.messages.create(**kwargs)
    text = "".join(b.text for b in resp.content if getattr(b, "type", "") == "text")
    text = _strip_thinking(text)
    parsed = _parse_json(text)
    if parsed is None:
        return None, text[:500]
    return parsed, None


def score_with_judge(section_type, prompt, candidate, judge_model=JUDGE_MODEL_DEFAULT):
    if not candidate or not candidate.strip():
        return JudgeResult(
            rubric_scores={d: 0 for d in RUBRIC_DIMENSIONS},
            macro=0.0,
            rationale="empty candidate",
            error="empty_output",
        )
    candidate = _strip_thinking(candidate)
    last_err = None
    for attempt in range(2):
        try:
            parsed, raw_err = _call_judge(section_type, prompt, candidate, judge_model)
            if parsed is not None:
                scores = {d: int(parsed.get(d, 0)) for d in RUBRIC_DIMENSIONS}
                scores = {k: max(0, min(2, v)) for k, v in scores.items()}
                total = sum(scores.values())
                macro = total / (2 * len(RUBRIC_DIMENSIONS))
                return JudgeResult(
                    rubric_scores=scores,
                    macro=round(macro, 4),
                    rationale=str(parsed.get("rationale", ""))[:300],
                )
            last_err = f"parse_fail: {raw_err}"
        except Exception as e:
            last_err = f"{type(e).__name__}: {e}"
            time.sleep(1.0 + attempt)
    return JudgeResult(
        rubric_scores={d: 0 for d in RUBRIC_DIMENSIONS},
        macro=0.0,
        rationale="",
        error=last_err or "unknown",
    )
