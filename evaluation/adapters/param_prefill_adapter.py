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

-- ROOT CAUSE OF ALL-ZERO SCORES (diagnosed 2026-04-27) --

Two bugs were found and fixed:

Bug 1 — Wrong port / host down:
    The adapter called client.base_url (port 5000, the Node.js proxy) which is
    only available when the full frontend stack is running.  The endpoint
    /api/ai_assistant/search_nextflow_workflow lives on the Galaxy backend
    (port 8081).  When port 5000 is down the request times out → score 0.0.
    Fix: prepare() now probes port 5000 first; if unavailable it falls back to
    the Galaxy backend directly on http://localhost:8081 (or GALAXY_URL env var).
    When port 5000 is up, the proxy path is used normally.

Bug 2 — Wrong field name for extracted parameter values:
    The backend's _infer_params_from_intent_llm() writes extracted values into
    the 'default' field of each param dict (not a 'value' field):
        {**p, 'default': str(_llm_extracted[p['name']]), 'autoFilled': True}
    The adapter's _extract_generated_params() was reading param.get("value")
    which is always None → nothing scored as filled → all 0.0.
    Fix: _extract_generated_params() now checks 'value' first, then 'default'.
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
        """
        Extract connection details from an authenticated BioMateEvalClient.

        Bug 1 fix: probe port 5000 (Node.js proxy); fall back to Galaxy backend
        on port 8081 when the proxy is not reachable.  This makes the benchmark
        runnable even when only the Galaxy backend is up.
        """
        import os
        import requests as _requests

        client_url = client.base_url.rstrip("/")
        self._token = client.token

        # Try the client URL first (may be port 5000 proxy or remote host)
        probe_ok = False
        try:
            r = _requests.get(f"{client_url}/api/version", timeout=5)
            probe_ok = r.status_code < 500
        except Exception:
            probe_ok = False

        if probe_ok:
            self._base_url = client_url
            self._session = client._session
        else:
            # Fall back to Galaxy backend directly
            galaxy_url = (
                os.environ.get("GALAXY_URL", "").rstrip("/")
                or "http://localhost:8081"
            )
            self._base_url = galaxy_url
            # Create a new bare session — Galaxy backend doesn't need JWT auth
            # for this endpoint when called directly (no auth middleware on port 8081)
            self._session = _requests.Session()
            self._session.headers.update({"Content-Type": "application/json"})
            print(
                f"  [ParamPrefillAdapter] Port 5000 unavailable; "
                f"falling back to Galaxy backend at {galaxy_url}"
            )

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
        POST to the workflow search endpoint and return the JSON body.

        Port 5000 (Node.js proxy): POST /api/workflows/search  {"query": "..."}
        Port 8081 (Galaxy direct): POST /api/ai_assistant/search_nextflow_workflow  {"user_intent": "..."}

        Returns an empty dict with success=False on any error.
        """
        if self._session is None:
            raise RuntimeError(
                "ParamPrefillAdapter.prepare(client) must be called before run()"
            )
        # Use the right path and payload format depending on which server we're talking to
        if ":5000" in self._base_url or "localhost:5000" in self._base_url:
            url     = f"{self._base_url}/api/workflows/search"
            payload = {"query": query}
        else:
            url     = f"{self._base_url}/api/ai_assistant/search_nextflow_workflow"
            payload = {"user_intent": query}

        resp = self._session.post(url, json=payload, timeout=180)
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
                  {"name": str, "default": any, "autoFilled": bool, "llm_extracted": bool, ...},
                  ...
              ],
              ...
            }

        Bug 2 fix: the backend's _infer_params_from_intent_llm() stores the
        extracted value in the 'default' field (not a 'value' field):
            {**p, 'default': str(_llm_extracted[p['name']]), 'autoFilled': True}
        We check 'value' first for forward-compatibility, then fall back to 'default'.

        Additionally, params without 'autoFilled' key default to False (not True)
        because un-filled params from the workflow schema have null/None defaults
        and should not be counted as filled.  Only params explicitly marked
        autoFilled=True by the LLM extraction pass are counted.
        """
        raw: list[dict] = response.get("generated_parameters", []) or []
        result: dict[str, Any] = {}
        for param in raw:
            name = param.get("name") or param.get("key") or ""
            if not name:
                continue
            # Only count parameters actually auto-filled by BioMate's LLM pass.
            # autoFilled is only set to True when _infer_params_from_intent_llm
            # successfully extracted a value; absent = not filled (default False).
            auto_filled = param.get("autoFilled", False)
            llm_extracted = param.get("llm_extracted", False)
            if not (auto_filled or llm_extracted):
                continue
            # Value is stored in 'default' by the backend (Bug 2 fix); 'value' is
            # checked first for forward-compatibility with future schema changes.
            value = param.get("value")
            if value is None:
                value = param.get("default")
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
                # Prepend workflow name as a routing hint when known.
                # This prevents ambiguous queries (e.g. "RNA-seq differential expression")
                # from being mis-routed to pipeline chains instead of the target workflow.
                # The param_prefill benchmark tests param extraction given correct routing,
                # not routing itself (routing is tested in the routing benchmark).
                workflow_hint = task.metadata.get("workflow", "")
                query = task.question
                if workflow_hint:
                    query = f"Run {workflow_hint}: {task.question}"
                api_response = self._call_generation_endpoint(query)
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
