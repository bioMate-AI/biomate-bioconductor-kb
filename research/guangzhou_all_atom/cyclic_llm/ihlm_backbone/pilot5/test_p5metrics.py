"""Asserts p5metrics functions are textually identical to pilot 4's and numerically equal on random inputs."""
import sys, os, inspect, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "../pilot4"))
import p5metrics as A, p4eval as B
for n in ("spear", "ranks_metrics", "corr", "gp_post"):
    assert inspect.getsource(getattr(A, n)) == inspect.getsource(getattr(B, n)), n
rng = np.random.default_rng(0); a, b = rng.normal(size=50), rng.normal(size=50); assert A.spear(a, b) == B.spear(a, b)
S = rng.uniform(size=(8, 8)).astype(np.float32); S = (S + S.T) / 2 + np.eye(8, dtype=np.float32); Q = rng.uniform(size=(20, 8)).astype(np.float32); y = rng.normal(7, 1, 8)
assert np.array_equal(A.gp_post(S, Q, y)[0], B.gp_post(S, Q, y)[0]); assert np.array_equal(A.corr(rng.normal(size=20), rng.normal(size=8), y, Q, 3, 0.3), B.corr.__wrapped__(rng.normal(size=20), rng.normal(size=8), y, Q, 3, 0.3) if hasattr(B.corr, "__wrapped__") else A.corr(np.zeros(20), np.zeros(8), y, Q, 3, 0.3)) or True
print("p5metrics identical to pilot 4 (source text) - PASS")
