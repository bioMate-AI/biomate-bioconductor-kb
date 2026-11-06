"""VerificationLayer — reusable inference-time verification for the BioMate harness.

The moat is the harness, not model size: open/small agents match frontier at a fraction of the cost when they
are (a) grounded, (b) executed, and (c) VERIFIED. Our QC auto-loop already is "verifiable rewards"; this
module formalizes the *generation-time* half the harness was missing, as model-agnostic primitives any task
path can wrap its LLM call with:

  * majority_vote / self_consistent  — sample K completions, return the modal answer + a confidence
    (self-consistency; free accuracy on hard tasks — the Aviary result).
  * verified_sample                  — pass@k oracle: return the first sample a deterministic verifier accepts.
  * consensus                        — do N independent answers (e.g. two teacher models) agree?
  * grounded_pick                    — grounded-by-construction: a selection must be one of the PROVIDED
    candidates, else reject (kills off-catalog hallucination at the harness boundary).

Pure, dependency-light (stdlib + typing only, Python 3.9-safe — no PEP 604 unions) so it can never crash the
Galaxy import chain. Model/IO is injected as callables, so this is trivially unit-testable and provider-agnostic.
"""
from typing import Any, Callable, Dict, List, Optional, Tuple
from concurrent.futures import ThreadPoolExecutor
import collections
import re

_WS = re.compile(r"\s+")


_STOP = frozenset("the a an of to and or for with is are was on in at by from this that these those into as be it its".split())


def default_normalize(s: Any) -> str:
    """Canonical form for answer-equality: lowercased, punctuation->space, whitespace-collapsed."""
    return _WS.sub(" ", re.sub(r"[^a-z0-9 ]", " ", str(s).lower())).strip()


def salient_set(s: Any) -> set:
    """Salient tokens (backtick/quoted names, numbers, content words) — for fuzzy answer-equality on PROSE."""
    s = str(s or "")
    bt = re.findall(r"`([^`]+)`", s)
    nums = re.findall(r"\d+\.?\d*", s)
    words = [w for w in default_normalize(s).split() if len(w) > 3 and w not in _STOP]
    return {t for t in (set(x.lower() for x in bt) | set(nums) | set(words)) if t}


def salient_f1(a: Any, b: Any) -> float:
    """Harmonic mean of salient-token precision/recall — verbosity-robust prose similarity (0..1)."""
    A, B = salient_set(a), salient_set(b)
    if not A or not B:
        return 0.0
    inter = len(A & B)
    if inter == 0:
        return 0.0
    p, r = inter / len(B), inter / len(A)
    return 2 * p * r / (p + r)


def majority_vote(samples: List[Any], normalize: Optional[Callable[[Any], str]] = None
                  ) -> Tuple[Optional[Any], float, Dict[str, int]]:
    """Return (modal_raw_answer, confidence, vote_counts_by_norm). confidence = votes/total.

    Ties break deterministically by first-seen order. Empty/blank samples are ignored.
    """
    norm = normalize or default_normalize
    counts: "collections.OrderedDict[str, int]" = collections.OrderedDict()
    rep: Dict[str, Any] = {}
    total = 0
    for s in samples:
        k = norm(s)
        if not k:
            continue
        total += 1
        counts[k] = counts.get(k, 0) + 1
        if k not in rep:
            rep[k] = s
    if total == 0:
        return None, 0.0, {}
    best_k = max(counts, key=lambda k: counts[k])          # max() keeps first on ties (OrderedDict order)
    return rep[best_k], counts[best_k] / total, dict(counts)


def self_consistent(generate: Callable[[], Any], k: int = 5, normalize: Optional[Callable[[Any], str]] = None,
                    workers: int = 1) -> Tuple[Optional[Any], float, Dict[str, int]]:
    """Sample `generate()` k times (optionally in parallel) and majority-vote. generate must be side-effect-light."""
    if k < 1:
        k = 1
    if workers > 1 and k > 1:
        with ThreadPoolExecutor(max_workers=min(workers, k)) as ex:
            samples = list(ex.map(lambda _i: generate(), range(k)))
    else:
        samples = [generate() for _ in range(k)]
    return majority_vote(samples, normalize)


def verified_sample(generate: Callable[[], Any], verify: Callable[[Any], bool], k: int = 5
                    ) -> Tuple[Optional[Any], bool]:
    """pass@k oracle verification: return (first_sample_that_passes, True); else (last_sample, False).

    Use when a DETERMINISTIC verifier exists (schema-valid, runs on Batch, grader==gold). Cheap accuracy:
    any correct rollout among k is retained.
    """
    last = None
    for _ in range(max(1, k)):
        s = generate()
        last = s
        try:
            if verify(s):
                return s, True
        except Exception:
            continue
    return last, False


def consensus(answers: List[Any], normalize: Optional[Callable[[Any], str]] = None, min_agree: int = 2,
              fuzzy_threshold: Optional[float] = None) -> Tuple[Optional[Any], int]:
    """Do >= min_agree independent answers agree? Return (representative_raw, cluster_size); (None, top) otherwise.

    Default: EXACT normalized-string agreement — right for terse answers (routing names, param values, labels).
    fuzzy_threshold set (e.g. 0.4): cluster by salient-F1 >= threshold instead — right for PROSE (two teacher
    LLMs phrasing the same finding differently). Greedy largest-cluster.
    """
    cands = [a for a in answers if a is not None and str(a).strip()]
    if not cands:
        return None, 0
    if fuzzy_threshold is None:
        best, _conf, counts = majority_vote(cands, normalize)
        top = max(counts.values()) if counts else 0
        return (best, top) if top >= min_agree else (None, top)
    # fuzzy: greedy clusters by salient-F1; return the largest
    best_rep, best_size = None, 0
    for i, a in enumerate(cands):
        size = 1 + sum(1 for j, b in enumerate(cands) if j != i and salient_f1(a, b) >= fuzzy_threshold)
        if size > best_size:
            best_rep, best_size = a, size
    return (best_rep, best_size) if best_size >= min_agree else (None, best_size)


def grounded_pick(answer: Any, candidates: List[Any], normalize: Optional[Callable[[Any], str]] = None
                  ) -> Optional[Any]:
    """Grounded-by-construction: map a free-form selection to the PROVIDED candidate it names, else None.

    Matches on exact normalized equality first, then substring containment (the model may wrap the name in
    prose). Returns the canonical candidate (not the model's wording) so downstream gets an exact catalog id.
    Rejecting None here is the harness refusing an off-catalog hallucination.
    """
    norm = normalize or default_normalize
    na = norm(answer)
    if not na:
        return None
    cand_norm = [(c, norm(c)) for c in candidates]
    for c, cn in cand_norm:
        if cn and cn == na:
            return c
    # containment: prefer the longest candidate name present in the answer (most specific)
    hits = [(c, cn) for c, cn in cand_norm if cn and (cn in na or na in cn)]
    if hits:
        return max(hits, key=lambda x: len(x[1]))[0]
    return None
