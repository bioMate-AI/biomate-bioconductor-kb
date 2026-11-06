"""
map_reduce.py -- a shared, backend-agnostic map-reduce fan-out layer.

Both the Pattern-Router orchestration work (PARALLEL_FANOUT) and the
corpus-as-filesystem retrieval work (per-document sub-agents) need the same
primitive: fan a ``worker_fn`` out over a list of independent units, collect the
per-unit results *in input order*, capture any per-unit exception without
crashing the whole fan-out, and optionally reduce the successful results into a
single structure. This is the "Virtual Biotech"-style map (fan-out) -> reduce
(synthesize) shape, factored out so each consumer injects its own worker.

Design properties:
  - **Backend-agnostic / hermetically testable**: the worker is injected, so a
    test can exercise ordering, the concurrency cap, and error isolation with a
    pure in-process function -- no network, no LLM, no orchestrator.
  - **Bounded**: a ``ThreadPoolExecutor(max_workers=max_concurrent)`` caps the
    number of simultaneously in-flight workers.
  - **Deterministic ordering**: results and errors are returned in input order,
    independent of completion order.
  - **Fault-isolating**: a single failing unit is captured into ``errors`` while
    the others still succeed (``on_error="collect"``, the default). Opt into
    fail-fast with ``on_error="raise"``.

Python 3.9-safe: ``from __future__ import annotations`` + ``typing`` generics,
no PEP 604 unions. No network, no external services; additive and inert until a
caller invokes it.
"""

from __future__ import annotations

import logging
import threading
from concurrent.futures import ThreadPoolExecutor
from typing import Any, Callable, Dict, List, Optional

log = logging.getLogger(__name__)

# on_error modes.
ON_ERROR_COLLECT = "collect"
ON_ERROR_RAISE = "raise"


def map_reduce(
    units: List[Any],
    worker_fn: Callable[[Any], Any],
    reduce_fn: Optional[Callable[[List[Any]], Any]] = None,
    max_concurrent: int = 8,
    on_error: str = ON_ERROR_COLLECT,
) -> Dict[str, Any]:
    """Parallel map of ``worker_fn`` over ``units``, then an optional reduce.

    Args:
        units: the independent work items. Order is preserved in the output.
        worker_fn: called once per unit as ``worker_fn(unit)``. Runs on a worker
            thread. May raise -- the exception is isolated per unit.
        reduce_fn: optional; called once with the list of successful results
            (in input order) to produce ``reduced``. When None, ``reduced`` is
            None.
        max_concurrent: max number of simultaneously in-flight workers (the
            thread-pool size). Clamped to >= 1.
        on_error: ``"collect"`` (default) captures each unit's exception into
            ``errors`` and keeps going; ``"raise"`` re-raises the first
            exception encountered (in input order) after the pool drains.

    Returns:
        ``{"results": [...], "errors": [...], "reduced": <...>}`` where
          - ``results``: successful results, in input order;
          - ``errors``: ``[{"index": int, "unit": <unit>, "error": str,
            "type": str}]`` for failed units, in input order;
          - ``reduced``: ``reduce_fn(results)`` if ``reduce_fn`` else None.
    """
    if on_error not in (ON_ERROR_COLLECT, ON_ERROR_RAISE):
        raise ValueError(
            "on_error must be {!r} or {!r}, got {!r}".format(
                ON_ERROR_COLLECT, ON_ERROR_RAISE, on_error
            )
        )

    units_list = list(units) if units is not None else []
    n = len(units_list)

    # Empty fan-out: nothing to run; still apply reduce_fn([]) for a uniform shape.
    if n == 0:
        reduced = None
        if reduce_fn is not None:
            reduced = reduce_fn([])
        return {"results": [], "errors": [], "reduced": reduced}

    # Per-unit outcome slots preserve input order regardless of completion order.
    # Each slot is a (ok, value) pair; `value` is the result when ok, else the
    # captured exception.
    outcomes: List[Optional[Any]] = [None] * n

    workers = max(1, min(int(max_concurrent) if max_concurrent else 1, n))

    def _run(index_unit):  # type: ignore[no-untyped-def]
        index, unit = index_unit
        try:
            return index, True, worker_fn(unit)
        except Exception as exc:  # isolate: one unit's failure must not crash the fan-out
            return index, False, exc

    with ThreadPoolExecutor(max_workers=workers) as pool:
        # executor.map keeps submission order; we also carry the index explicitly
        # so ordering never depends on it.
        for index, ok, value in pool.map(_run, list(enumerate(units_list))):
            outcomes[index] = (ok, value)

    results: List[Any] = []
    errors: List[Dict[str, Any]] = []
    first_exc: Optional[BaseException] = None
    for index in range(n):
        slot = outcomes[index]
        # slot is always set (pool.map yields exactly one per unit), but guard.
        if slot is None:  # pragma: no cover - defensive
            continue
        ok, value = slot
        if ok:
            results.append(value)
        else:
            if first_exc is None:
                first_exc = value
            errors.append(
                {
                    "index": index,
                    "unit": units_list[index],
                    "error": str(value),
                    "type": type(value).__name__,
                }
            )

    if on_error == ON_ERROR_RAISE and first_exc is not None:
        raise first_exc

    reduced = None
    if reduce_fn is not None:
        reduced = reduce_fn(results)

    return {"results": results, "errors": errors, "reduced": reduced}


__all__ = ["map_reduce", "ON_ERROR_COLLECT", "ON_ERROR_RAISE"]
