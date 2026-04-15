"""
ParamPrefillAdapter — Benchmarks BioMate's automatic parameter pre-filling capability.

Calls the /api/ai_assistant/search_nextflow_workflow endpoint directly (not via
chat) because generated_parameters are returned by that endpoint, not in the
chat stream.

Scoring uses F1 over expected_params with a penalty deducted for must_not_fill
violations (hallucinated values on under-specified queries).

Score formula for each case:
    base_score = F1(expected ∩ generated, expected, generated)
    penalty    = 0.2 per must_not_fill key that was incorrectly filled
    score      = max(0.0, base_score - penalty)

Semantic equivalence for genome params is handled via GENOME_ALIASES so that
"hg38" and "GRCh38" are treated as the same value.

Usage:
    adapter = ParamPrefillAdapter(config)
    adapter.prepare(client)           # extracts token from authenticated client
    results = adapter.run(client, max_tasks=None)
"""

from __future__ import annotations

import time
from pathlib import Path
from typing import Any, Optional

import yaml

from evaluation.core.base_adapter import BenchmarkAdapter, BenchmarkTask, BenchmarkResult

_DATASET_PATH = (
    Path(__file__).parent.parent / "datasets" / "param_prefill" / "cases.yaml"
)

# ── Semantic aliases ─────────────────────────────────────────────────────────
# Maps canonical nf-core genome name → set of equivalent user-supplied values
GENOME_ALIASES: dict[str, set[str]] = {
    "GRCh38": {"hg38", "human", "homo_sapiens", "homo sapiens", "grch38",
               "grch38.p14", "homo_sapiens_grch38"},
    "GRCh37": {"hg19", "grch37"},
    "GRCm39": {"mm39", "mouse", "mus_musculus", "mus musculus", "grcm39",
               "mus_musculus_grcm39"},
    "GRCm38": {"mm10", "grcm38"},
    "Rnor_6.0": {"rnor6", "rnor_6.0", "rat", "rattus_norvegicus",
                 "rattus norvegicus"},
    "GRCz11": {"grcz11", "zebrafish", "danio_rerio", "danio rerio"},
    "BDGP6":  {"bdgp6", "drosophila", "dm6", "drosophila_melanogaster",
               "drosophila melanogaster"},
    "WBcel235": {"wbcel235", "c. elegans", "c.elegans", "caenorhabditis_elegans",
                 "caenorhabditis elegans", "wormbase235"},
    "R64-1-1": {"r64-1-1", "r64", "saccharomyces_cerevisiae", "s. cerevisiae",
                "yeast", "s288c"},
    "TAIR10": {"tair10", "arabidopsis", "arabidopsis_thaliana",
               "arabidopsis thaliana", "at"},
}

# Build reverse lookup: any alias → canonical name
_ALIAS_TO_CANONICAL: dict[str, str] = {}
for _canonical, _aliases in GENOME_ALIASES.items():
    _ALIAS_TO_CANONICAL[_canonical.lower()] = _canonical
    for _alias in _aliases:
        _ALIAS_TO_CANONICAL[_alias.lower()] = _canonical

# Strandedness aliases accepted by nf-core/rnaseq
_STRAND_ALIASES: dict[str, set[str]] = {
    "reverse": {"reverse", "rf", "dUTP", "dutp"},
    "forward": {"forward", "fr", "ligation"},
    "unstranded": {"unstranded", "none", "no"},
}
_STRAND_CANONICAL: dict[str, str] = {}
for _s, _sv in _STRAND_ALIASES.items():
    _STRAND_CANONICAL[_s] = _s
    for _alias in _sv:
        _STRAND_CANONICAL[_alias.lower()] = _s

# Boolean truthy/falsy normalization
_TRUTHY = {"true", "yes", "1", "t", "y"}
_FALSY = {"false", "no", "0", "f", "n"}

# Weight for each param component of the F1 calculation
_MUST_NOT_FILL_PENALTY = 0.2


def _normalise(key: str, value: Any) -> Any:
    """
    Normalise a parameter value to a canonical form for comparison.

    Handles:
    - genome aliases (hg38 → GRCh38)
    - strandedness aliases (RF → reverse)
    - boolean strings (true/false)
    - numeric coercion
    - case-insensitive string comparison
    """
    if value is None:
        return None

    v_str = str(value).strip()

    # Genome
    if key == "genome":
        return _ALIAS_TO_CANONICAL.get(v_str.lower(), v_str)

    # Strandedness
    if key == "strandedness":
        return _STRAND_CANONICAL.get(v_str.lower(), v_str.lower())

    # Boolean-like strings
    v_lower = v_str.lower()
    if v_lower in _TRUTHY:
        return True
    if v_lower in _FALSY:
        return False

    # Numeric
    try:
        return int(v_str)
    except ValueError:
        pass
    try:
        return float(v_str)
    except ValueError:
        pass

    return v_str.lower()


def _values_match(key: str, expected: Any, actual: Any) -> bool:
    """Return True if normalised expected and actual values are equivalent."""
    return _normalise(key, expected) == _normalise(key, actual)


class ParamPrefillAdapter(BenchmarkAdapter):
    """
    Benchmark adapter for parameter pre-filling capability.

    Unlike other adapters this one bypasses the chat interface and calls
    /api/ai_assistant/search_nextflow_workflow directly so it can inspect
    generated_parameters from the backend.
    """

    name = "param_prefill"

    def __init__(self, config: dict):
        super().__init__(config)
        self._base_url: str = ""
        self._token: str = ""
        self._session = None  # requests.Session, set in prepare()

    # ------------------------------------------------------------------
    # Setup
    # ------------------------------------------------------------------

    def prepare(self, client) -> None:
        """Extract connection details from an authenticated BioMateEvalClient."""
        self._base_url = client.base_url.rstrip("/")
        self._token = client.token
        self._session = client._session  # reuse existing authenticated session

    # ------------------------------------------------------------------
    # Task loading
    # ------------------------------------------------------------------

    def load_tasks(self) -> list[BenchmarkTask]:
        with open(_DATASET_PATH) as f:
            data = yaml.safe_load(f)

        tasks: list[BenchmarkTask] = []
        for case in data["cases"]:
            task = BenchmarkTask(
                task_id=case["id"],
                question=case["user_query"],
                ground_truth=case.get("expected_params", {}),
                difficulty=case.get("difficulty", "medium"),
                task_type="workflow",
                answer_type="json",
                metadata={
                    "category": case["category"],
                    "workflow": case["workflow"],
                    "must_not_fill": case.get("must_not_fill", []),
                    "notes": case.get("notes", ""),
                    "difficulty": case.get("difficulty", "medium"),
                    "benchmark": "param_prefill",
                },
            )
            tasks.append(task)
        return tasks

    # ------------------------------------------------------------------
    # Core API call
    # ------------------------------------------------------------------

    def _call_generation_endpoint(self, query: str) -> dict:
        """
        POST to /api/ai_assistant/search_nextflow_workflow and return the JSON body.

        Returns an empty dict with success=False on any error.
        """
        if self._session is None:
            raise RuntimeError(
                "ParamPrefillAdapter.prepare(client) must be called before run()"
            )
        resp = self._session.post(
            f"{self._base_url}/api/ai_assistant/search_nextflow_workflow",
            json={"user_intent": query},
            timeout=60,
        )
        resp.raise_for_status()
        return resp.json()

    # ------------------------------------------------------------------
    # Scoring
    # ------------------------------------------------------------------

    def score(self, task: BenchmarkTask, agent_response: str) -> float:
        """
        Not used directly — run() overrides the loop so it can call the
        generation endpoint and pass the raw dict to _compute_score.
        Kept to satisfy the abstract method requirement.
        """
        return 0.0

    def _extract_generated_params(self, response: dict) -> dict[str, Any]:
        """
        Pull generated_parameters out of the endpoint response.

        The endpoint returns:
            {
              "success": bool,
              "generated_parameters": [
                  {"name": str, "value": any, "autoFilled": bool, ...},
                  ...
              ],
              ...
            }
        Returns a flat name→value dict of the parameters that were auto-filled.
        """
        raw: list[dict] = response.get("generated_parameters", []) or []
        result: dict[str, Any] = {}
        for param in raw:
            name = param.get("name") or param.get("key") or ""
            if not name:
                continue
            # Only count parameters that were actually auto-filled by BioMate
            if not param.get("autoFilled", True):
                continue
            value = param.get("value")
            if value is not None and value != "":
                result[name] = value
        return result

    def _compute_score(
        self,
        generated: dict[str, Any],
        expected: dict[str, Any],
        must_not_fill: list[str],
    ) -> float:
        """
        Compute F1 score with penalty for must_not_fill violations.

        F1 calculation:
            precision = |correct_filled| / max(1, |generated_keys|)
            recall    = |correct_filled| / max(1, |expected_keys|)
            F1        = harmonic mean of precision and recall

        Special case: if expected_params is empty, F1 starts at 1.0
        (a perfect negative case — BioMate correctly fills nothing).
        Then penalties are applied for any must_not_fill violations.

        Each must_not_fill key that BioMate incorrectly populates deducts
        _MUST_NOT_FILL_PENALTY from the score.
        """
        expected_keys = set(expected.keys())
        generated_keys = set(generated.keys())

        if expected_keys:
            correct_filled = {
                k for k in expected_keys & generated_keys
                if _values_match(k, expected[k], generated[k])
            }
            precision = len(correct_filled) / max(1, len(generated_keys))
            recall = len(correct_filled) / len(expected_keys)
            if precision + recall > 0:
                base_score = 2 * precision * recall / (precision + recall)
            else:
                base_score = 0.0
        else:
            # Negative case: no expected params → base score = 1.0
            base_score = 1.0

        # Penalise each must_not_fill key that was incorrectly populated
        penalty = 0.0
        for key in must_not_fill:
            if key in generated_keys and generated[key] not in (None, "", [], {}):
                penalty += _MUST_NOT_FILL_PENALTY

        return max(0.0, base_score - penalty)

    # ------------------------------------------------------------------
    # Main run loop (overrides base class to call endpoint directly)
    # ------------------------------------------------------------------

    def run(self, client, max_tasks: Optional[int] = None) -> list[BenchmarkResult]:
        """
        Execute all tasks by calling the generation endpoint directly.
        Uses ThreadPoolExecutor for parallelism (max 8 workers).
        """
        from concurrent.futures import ThreadPoolExecutor, as_completed

        tasks = self.load_tasks()
        if max_tasks:
            tasks = tasks[:max_tasks]

        self.prepare(client)
        results: list[BenchmarkResult] = []
        max_workers = self.config.get("concurrency", {}).get("max_parallel_tasks", 8)

        def _run_one(task: BenchmarkTask) -> BenchmarkResult:
            t0 = time.time()
            error: Optional[str] = None
            score = 0.0
            agent_response = ""

            try:
                api_response = self._call_generation_endpoint(task.question)
                generated = self._extract_generated_params(api_response)
                agent_response = str(generated)
                must_not_fill: list[str] = task.metadata.get("must_not_fill", [])
                score = self._compute_score(
                    generated=generated,
                    expected=task.ground_truth,
                    must_not_fill=must_not_fill,
                )
            except Exception as exc:
                error = str(exc)
                agent_response = ""

            return BenchmarkResult(
                task_id=task.task_id,
                benchmark=self.name,
                score=score,
                agent_response=agent_response[:2000],
                ground_truth=task.ground_truth,
                latency_sec=time.time() - t0,
                metadata=task.metadata,
                error=error,
            )

        with ThreadPoolExecutor(max_workers=max_workers) as pool:
            futures = {pool.submit(_run_one, t): t for t in tasks}
            for future in as_completed(futures):
                result = future.result()
                indicator = (
                    "✓" if result.score >= 0.75
                    else ("~" if result.score >= 0.4 else "✗")
                )
                cat = result.metadata.get("category", "?")
                err_suffix = f" ERR={result.error[:60]}" if result.error else ""
                print(
                    f"  [{result.task_id}] {cat:<28} "
                    f"{indicator} score={result.score:.2f} "
                    f"({result.latency_sec:.0f}s){err_suffix}"
                )
                results.append(result)

        return results
