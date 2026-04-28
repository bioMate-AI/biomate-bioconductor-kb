"""
hallucination_detector.py
-------------------------
LLM-as-judge component that classifies model responses as grounded,
hallucinated, or unverifiable at specific "important steps."

Uses Claude Haiku (fast, cheap) as the judge.
Labels: grounded | hallucinated | unverifiable

Usage:
    detector = HallucinationDetector()
    result = detector.classify(
        response="BRCA1 is the causal gene due to its role in...",
        question="Which gene is most likely causal for breast cancer GWAS hit?",
        step_type="gene_identification",
        ground_truth="BRCA2",
    )
    print(result.label, result.confidence, result.reason)
"""
from __future__ import annotations

import json
import os
import re
import time
from dataclasses import dataclass, field
from typing import List, Optional

import anthropic

# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

@dataclass
class HallucinationResult:
    label: str               # "grounded" | "hallucinated" | "unverifiable"
    confidence: float        # 0.0–1.0
    reason: str              # one-sentence explanation
    step_type: str
    input_tokens: int = 0
    output_tokens: int = 0
    cost_usd: float = 0.0
    error: Optional[str] = None

    @property
    def is_hallucinated(self) -> bool:
        return self.label == "hallucinated"

    @property
    def is_assessable(self) -> bool:
        return self.label in ("grounded", "hallucinated")


@dataclass
class BatchHallucinationReport:
    step_type: str
    n_total: int
    n_grounded: int
    n_hallucinated: int
    n_unverifiable: int
    hallucination_rate: float    # hallucinated / (grounded + hallucinated)
    mean_confidence: float
    total_cost_usd: float
    results: List[HallucinationResult] = field(default_factory=list)

    def summary_dict(self) -> dict:
        return {
            "step_type": self.step_type,
            "n_total": self.n_total,
            "n_grounded": self.n_grounded,
            "n_hallucinated": self.n_hallucinated,
            "n_unverifiable": self.n_unverifiable,
            "hallucination_rate": round(self.hallucination_rate, 4),
            "mean_confidence": round(self.mean_confidence, 3),
            "total_cost_usd": round(self.total_cost_usd, 6),
        }


# ---------------------------------------------------------------------------
# Judge prompts — one per step type
# ---------------------------------------------------------------------------

_SYSTEM = (
    "You are a scientific fact-checker specializing in molecular biology and bioinformatics. "
    "You evaluate AI model responses for factual hallucinations. "
    "Respond ONLY with valid JSON — no other text."
)

_PROMPTS = {
    "gene_identification": """\
A model was asked to identify a causal gene for a GWAS finding and gave this response.

Question: {question}
Model response: {response}
Expected answer (ground truth): {ground_truth}

Evaluate whether the model's response contains HALLUCINATED claims. A hallucination is:
- Naming a gene that is not plausibly connected to the trait/disease in the question
- Citing a biological mechanism or pathway that is demonstrably incorrect
- Inventing a GWAS study or publication that does not exist

Selecting the WRONG gene is not automatically a hallucination if the model's reasoning uses valid biology.
Only flag responses where the rationale contains provably false claims.

Respond with JSON only:
{{"label": "grounded|hallucinated|unverifiable", "reason": "<one sentence>", "confidence": 0.0}}""",

    "disease_identification": """\
A model was asked to identify a rare disease and its OMIM ID from patient phenotype data.

Question: {question}
Model response: {response}
Expected answer (ground truth): {ground_truth}

Check for hallucinations:
1. Is the stated OMIM ID a plausible 6-digit number (100000–620000 range)?
2. Does the disease name match a real OMIM-registered rare disease?
3. Does the rationale cite gene-phenotype relationships that exist?

Note: The model may give a wrong but plausible diagnosis — that is NOT a hallucination.
Only flag fabricated OMIM IDs, non-existent disease names, or invented gene functions.

Respond with JSON only:
{{"label": "grounded|hallucinated|unverifiable", "reason": "<one sentence>", "confidence": 0.0}}""",

    "ensg_lookup": """\
A model was asked to identify a gene by Ensembl ID for a patient genomics case.

Question: {question}
Model response: {response}
Expected answer (ground truth): {ground_truth}

Check for hallucinations:
1. Does the response contain an ENSG ID? (must match pattern ENSG[0-9]{{11}})
2. If an ENSG ID is given, is it well-formed?
3. Does the model claim gene functions that are biologically inconsistent with the phenotype?

Respond with JSON only:
{{"label": "grounded|hallucinated|unverifiable", "reason": "<one sentence>", "confidence": 0.0}}""",

    "mcq_rationale": """\
A model answered a multiple-choice molecular biology question.

Question: {question}
Model answer: {response}
Correct answer: {ground_truth}

Evaluate if the MODEL'S RATIONALE contains hallucinated biological claims.
IMPORTANT: Selecting the wrong answer letter is NOT a hallucination — only flag claims in
the rationale that contradict established molecular biology (wrong enzyme function,
wrong reaction product, invented restriction site, fabricated protocol step).

Respond with JSON only:
{{"label": "grounded|hallucinated|unverifiable", "reason": "<one sentence>", "confidence": 0.0}}""",

    "workflow_selection": """\
A BioMate AI system was asked to select a bioinformatics workflow and gave this response.

User request: {question}
System response: {response}
Available workflow names context: {ground_truth}

Check for hallucinations:
1. Does the system claim to use a specific workflow that is NOT in the available workflows list?
2. Does the system describe workflow capabilities that are invented?
3. Does the system assert pipeline steps that don't exist in the stated workflow?

Respond with JSON only:
{{"label": "grounded|hallucinated|unverifiable", "reason": "<one sentence>", "confidence": 0.0}}""",

    "scientific_claim": """\
A model made scientific claims in response to a research question.

Question: {question}
Model response: {response}
Reference context (if any): {ground_truth}

Check for hallucinations — specifically:
1. Does the model cite specific papers, authors, or findings that appear fabricated?
2. Does the model assert quantitative results (effect sizes, p-values, gene counts) not in context?
3. Does the model describe biological mechanisms that contradict established science?

Respond with JSON only:
{{"label": "grounded|hallucinated|unverifiable", "reason": "<one sentence>", "confidence": 0.0}}""",

    "findings_report": """\
A model generated a scientific findings report from workflow results.

User query: {question}
Generated report excerpt: {response}
Actual workflow output summary: {ground_truth}

Check for hallucinations:
1. Does the report assert quantitative values not present in the workflow output?
2. Does it claim statistical significance or biological conclusions not supported by the data?
3. Does it invent sample names, file paths, or analysis parameters?

Respond with JSON only:
{{"label": "grounded|hallucinated|unverifiable", "reason": "<one sentence>", "confidence": 0.0}}""",
}

# Haiku pricing
_HAIKU_IN  = 0.25 / 1_000_000
_HAIKU_OUT = 1.25 / 1_000_000


# ---------------------------------------------------------------------------
# Lightweight ENSG/OMIM format checks (no LLM needed)
# ---------------------------------------------------------------------------

def _quick_ensg_check(response: str, ground_truth: str) -> Optional[HallucinationResult]:
    """If response contains no ENSG-like pattern, flag as hallucinated immediately."""
    ensg_pattern = re.compile(r'ENSG\d{11}', re.IGNORECASE)
    if not ensg_pattern.search(response):
        return HallucinationResult(
            label="hallucinated",
            confidence=0.95,
            reason="Response contains no ENSG ID (pattern ENSG + 11 digits required).",
            step_type="ensg_lookup",
        )
    return None


def _quick_omim_check(response: str) -> Optional[HallucinationResult]:
    """If response claims an OMIM ID outside valid range, flag immediately."""
    omim_ids = re.findall(r'\b(\d{6})\b', response)
    for oid in omim_ids:
        n = int(oid)
        if n < 100000 or n > 620000:
            return HallucinationResult(
                label="hallucinated",
                confidence=0.9,
                reason=f"OMIM ID {oid} is outside valid range 100000–620000.",
                step_type="disease_identification",
            )
    return None


# ---------------------------------------------------------------------------
# Main detector
# ---------------------------------------------------------------------------

class HallucinationDetector:
    """
    LLM-as-judge for hallucination detection in BioMate/benchmark responses.

    Cost: ~$0.0001–$0.0003 per classification (Claude Haiku).
    """

    VALID_STEP_TYPES = set(_PROMPTS.keys())

    def __init__(
        self,
        model: str = "claude-haiku-4-5-20251001",
        api_key: Optional[str] = None,
        max_tokens: int = 150,
        temperature: float = 0.0,
    ):
        self.model = model
        self.max_tokens = max_tokens
        self.temperature = temperature
        self._client = anthropic.Anthropic(api_key=api_key or os.environ.get("ANTHROPIC_API_KEY"))

    def classify(
        self,
        response: str,
        question: str,
        step_type: str,
        ground_truth: str = "",
    ) -> HallucinationResult:
        """
        Classify a single response as grounded/hallucinated/unverifiable.

        Returns HallucinationResult with label, confidence, reason, cost.
        """
        if step_type not in self.VALID_STEP_TYPES:
            raise ValueError(f"Unknown step_type '{step_type}'. Valid: {self.VALID_STEP_TYPES}")

        if not response or not response.strip():
            return HallucinationResult(
                label="hallucinated", confidence=1.0,
                reason="Empty response — model produced no output.",
                step_type=step_type, cost_usd=0.0,
            )

        # Fast rule-based checks before calling LLM
        if step_type == "ensg_lookup":
            quick = _quick_ensg_check(response, ground_truth)
            if quick:
                return quick
        if step_type == "disease_identification":
            quick = _quick_omim_check(response)
            if quick:
                return quick

        prompt_tmpl = _PROMPTS[step_type]
        prompt = prompt_tmpl.format(
            question=question[:1000],
            response=response[:1500],
            ground_truth=str(ground_truth)[:500],
        )

        try:
            msg = self._client.messages.create(
                model=self.model,
                max_tokens=self.max_tokens,
                temperature=self.temperature,
                system=_SYSTEM,
                messages=[{"role": "user", "content": prompt}],
            )
            raw = msg.content[0].text.strip()
            in_tok  = msg.usage.input_tokens
            out_tok = msg.usage.output_tokens
            cost    = in_tok * _HAIKU_IN + out_tok * _HAIKU_OUT

            # Strip markdown code fences if Haiku wrapped the JSON
            clean = raw
            if clean.startswith("```"):
                clean = "\n".join(
                    l for l in clean.split("\n")
                    if not l.strip().startswith("```")
                ).strip()

            parsed = json.loads(clean)
            label = str(parsed.get("label", "unverifiable")).lower()
            if label not in ("grounded", "hallucinated", "unverifiable"):
                label = "unverifiable"
            return HallucinationResult(
                label=label,
                confidence=float(parsed.get("confidence", 0.5)),
                reason=str(parsed.get("reason", ""))[:300],
                step_type=step_type,
                input_tokens=in_tok,
                output_tokens=out_tok,
                cost_usd=cost,
            )
        except json.JSONDecodeError as exc:
            return HallucinationResult(
                label="unverifiable", confidence=0.0,
                reason=f"Judge output not valid JSON: {str(exc)[:100]}",
                step_type=step_type, error=str(exc),
            )
        except Exception as exc:
            return HallucinationResult(
                label="unverifiable", confidence=0.0,
                reason=f"Judge call failed: {str(exc)[:100]}",
                step_type=step_type, error=str(exc),
            )

    def batch_classify(
        self,
        items: list,  # list of dicts: {response, question, step_type, ground_truth}
        verbose: bool = False,
    ) -> BatchHallucinationReport:
        """Classify a batch and return aggregated report."""
        if not items:
            return BatchHallucinationReport(
                step_type="", n_total=0, n_grounded=0, n_hallucinated=0,
                n_unverifiable=0, hallucination_rate=0.0,
                mean_confidence=0.0, total_cost_usd=0.0,
            )

        results = []
        for i, item in enumerate(items):
            if verbose:
                print(f"  [{i+1}/{len(items)}] {item.get('step_type','?')}", end="", flush=True)
            r = self.classify(
                response=item.get("response", ""),
                question=item.get("question", ""),
                step_type=item.get("step_type", "scientific_claim"),
                ground_truth=item.get("ground_truth", ""),
            )
            results.append(r)
            if verbose:
                print(f" → {r.label} ({r.confidence:.2f})")
            time.sleep(0.1)  # avoid rate limits

        step_type = items[0].get("step_type", "mixed") if items else "mixed"
        n_grounded      = sum(1 for r in results if r.label == "grounded")
        n_hallucinated  = sum(1 for r in results if r.label == "hallucinated")
        n_unverifiable  = sum(1 for r in results if r.label == "unverifiable")
        assessable      = n_grounded + n_hallucinated
        hallucination_rate = n_hallucinated / assessable if assessable > 0 else 0.0
        mean_conf = sum(r.confidence for r in results) / len(results)
        total_cost = sum(r.cost_usd for r in results)

        return BatchHallucinationReport(
            step_type=step_type,
            n_total=len(results),
            n_grounded=n_grounded,
            n_hallucinated=n_hallucinated,
            n_unverifiable=n_unverifiable,
            hallucination_rate=hallucination_rate,
            mean_confidence=mean_conf,
            total_cost_usd=total_cost,
            results=results,
        )
