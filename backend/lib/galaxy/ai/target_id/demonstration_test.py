"""Offline test for the demonstration harness.

Constructed so the fused system MUST beat every single channel: each gold target is high in 2 of 3
channels (corroborated) while each channel also has a private false-positive (high in 1 channel).
The gate rewards corroboration, so system ranks gold above every channel's private FP -> system
AUROC=1.0 > best single; P1 passes. Run:
  PYTHONPATH=backend/lib python3 backend/lib/galaxy/ai/target_id/demonstration_test.py
"""
import sys


def _run():
    from galaxy.ai.target_id import MockChannel
    from galaxy.ai.target_id.demonstration import run_demonstration

    gold = ["TP53", "BRAF", "EGFR"]
    noise = ["NA1", "NB1", "NC1"]
    bg = ["BG%d" % i for i in range(1, 16)]
    universe = gold + noise + bg
    highs = {
        "chA": {"TP53", "BRAF", "NA1"},
        "chB": {"TP53", "EGFR", "NB1"},
        "chC": {"BRAF", "EGFR", "NC1"},
    }
    channels = [MockChannel(ch, {g: (9.0 if g in hi else 1.0) for g in universe}) for ch, hi in highs.items()]
    results = [c.run({}) for c in channels]

    out = run_demonstration(results, gold, k_list=(3, 5), n_perm=300)

    sys_auroc = out["system_auroc"]
    best_single = out["best_single_channel_auroc"]
    null_bar = out["null_bar_auroc_p95"]
    assert sys_auroc is not None and best_single is not None, out
    assert sys_auroc > best_single, "system (%s) must beat best single channel (%s)" % (sys_auroc, best_single)
    assert sys_auroc >= 0.99, "corroborated gold should rank top -> ~1.0; got %s" % sys_auroc
    assert sys_auroc > null_bar, "system (%s) must beat permutation null bar (%s)" % (sys_auroc, null_bar)
    assert out["pass_P1_system_beats_singles_and_null"] is True, out
    assert out["arms"]["system"]["prec_at_k"][3] == 1.0, out["arms"]["system"]["prec_at_k"]

    print("demonstration test: PASS  (system AUROC=%s > best_single=%s > null=%s; P1=%s)" % (
        sys_auroc, best_single, null_bar, out["pass_P1_system_beats_singles_and_null"]))


if __name__ == "__main__":
    try:
        _run()
    except AssertionError as e:
        print("demonstration test: FAIL ->", e)
        sys.exit(1)
    except Exception as e:  # pragma: no cover
        print("demonstration test: ERROR ->", type(e).__name__, e)
        sys.exit(2)
