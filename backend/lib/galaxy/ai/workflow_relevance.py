"""Relevance floor for attaching a catalog workflow to a chat request.

See docs/20261110_ROUTING_CLASSIFIER_AUTHORITY.md section 4.
"""
import os

# Calibrated on the held-out routing replay set (scripts/routing_replay, 2026-11-10): top-1 scores of
# the intended workflow for genuine workflow requests were 51.4–147.6 (min: nf-core/scdownstream for a
# macrophage scRNA request); the best catalog hit for requests no workflow serves (ad-hoc table
# statistics, follow-ups, explicit "no workflow") was 18.6–40.7. Floor = 45 (midpoint gap).
WORKFLOW_RELEVANCE_FLOOR = float(os.environ.get('BIOMATE_WORKFLOW_RELEVANCE_FLOOR', '45'))


def workflow_relevance_verdict(search_results, best_score, input_compatible=None, floor=None):
    """Decide whether the best catalog hit may be attached at all.

    Returns {'reject': bool, 'reason': str, 'message': str, 'promote': match|None}. A hit is usable when
    its score is >= floor AND it is not input-incompatible with the user's data (input_compatible(r)
    returning False; None = unknown, allowed). When the top hit is incompatible but another hit above
    the floor is compatible, that one is promoted instead of rejecting.
    """
    floor = WORKFLOW_RELEVANCE_FLOOR if floor is None else floor
    usable = []
    for r in search_results or []:
        if getattr(r, 'score', 0.0) < floor:
            continue
        ok = input_compatible(r) if input_compatible else None
        if ok is False:
            continue
        usable.append(r)
    if not search_results:
        return {'reject': False, 'reason': '', 'message': '', 'promote': None}
    top = search_results[0]
    if not usable:
        if best_score < floor:
            reason = f"best match {top.name!r} scored {best_score:.1f} < relevance floor {floor:.0f}"
        else:
            reason = f"no match above the floor accepts the user's data kind (top {top.name!r})"
        return {
            'reject': True, 'reason': reason, 'promote': None,
            'message': ("No workflow in the catalog fits this request closely enough to run it — "
                        "I won't attach an unrelated one. I can compute this directly on your data instead."),
        }
    return {'reject': False, 'reason': '', 'message': '', 'promote': usable[0] if usable[0] is not top else None}

