"""Offline test for the clinical arm (in-memory cohorts; no S3/files).

Run: PYTHONPATH=backend/lib python3 backend/lib/galaxy/ai/target_id/clinical_arm_test.py
"""
import sys


def _run():
    import pandas as pd
    from galaxy.ai.target_id.clinical_arm import cyt_score, evaluate_signature, signature_score

    # Cohort 1: responders (r1-3) have high CYT (GZMA/PRF1), non-responders (n1-3) low.
    expr1 = pd.DataFrame(
        {"r1": [50, 60, 5], "r2": [40, 55, 6], "r3": [45, 50, 5],
         "n1": [3, 4, 5], "n2": [2, 3, 6], "n3": [4, 2, 5]},
        index=["GZMA", "PRF1", "ACTB"])
    meta1 = pd.DataFrame({"response_binary": [1, 1, 1, 0, 0, 0]},
                         index=["r1", "r2", "r3", "n1", "n2", "n3"])
    # Cohort 2: same structure, different scale
    expr2 = pd.DataFrame(
        {"a1": [80, 90, 7], "a2": [70, 85, 8], "b1": [5, 6, 7], "b2": [4, 5, 8]},
        index=["GZMA", "PRF1", "ACTB"])
    meta2 = pd.DataFrame({"response_binary": [1, 1, 0, 0]}, index=["a1", "a2", "b1", "b2"])

    sc = cyt_score(expr1)
    assert sc["r1"] > sc["n1"], sc
    assert set(sc) == set(expr1.columns)

    out = evaluate_signature({"C1": (expr1, meta1), "C2": (expr2, meta2)}, cyt_score)
    assert out["per_cohort"]["C1"]["auroc"] == 1.0, out["per_cohort"]
    assert out["per_cohort"]["C2"]["auroc"] == 1.0, out["per_cohort"]
    assert out["pooled_auroc"] == 1.0, out
    assert out["pooled_n"] == 10 and out["pooled_n_resp"] == 5, out

    # missing genes -> empty (fail soft), not crash
    assert signature_score(expr1, ["NOTAGENE"], "geomean") == {}
    # single-class cohort -> auroc None (not crash)
    metabad = pd.DataFrame({"response_binary": [1, 1, 1, 1, 1, 1]}, index=list(expr1.columns))
    assert evaluate_signature({"X": (expr1, metabad)}, cyt_score)["per_cohort"]["X"]["auroc"] is None

    print("clinical_arm test: PASS  (CYT geomean separates responders; per-cohort+pooled AUROC=1.0; "
          "fail-soft on missing genes / single-class)")


if __name__ == "__main__":
    try:
        _run()
    except AssertionError as e:
        print("clinical_arm test: FAIL ->", e)
        sys.exit(1)
    except Exception as e:  # pragma: no cover
        print("clinical_arm test: ERROR ->", type(e).__name__, e)
        sys.exit(2)
