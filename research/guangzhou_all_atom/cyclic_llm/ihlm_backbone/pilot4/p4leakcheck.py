"""Pilot 4 leakage check L1(i), rewritten after the independent audit (the original source-string test searched for 'X[idx]' while the code indexes Xt[idx[ii]]: a defect of the check).
Two independent checks on the REAL training functions (p4models.train_mlp_prior, p4models.train_meta) and the real world:
 (A) RUNTIME: every tensor that reaches the network (MLPPrior.forward, Meta.embed) must be (i) 2048 wide and (ii) row-for-row an exact row of the compound fingerprint matrix; no relation/bound/type/assay/document value can be a model input.
 (B) STATIC (ast): every call m(...) / m.embed(...) inside the two training functions must take a subscript of the fingerprint tensor `Xt` (the only name bound to torch.from_numpy(X)) as its argument.
 (C) NEGATIVE CONTROL: a deliberately leaky copy of train_mlp_prior (adds the censoring type to the input) must FAIL both (A) and (B), otherwise the check is vacuous.
usage: python3 p4leakcheck.py OUT.json"""
import os, sys, ast, json, inspect, textwrap, hashlib, types, numpy as np, torch
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p4common as P, p4models as M
torch.set_num_threads(2)


def row_hashes(X): return {hashlib.sha1(np.ascontiguousarray(r, dtype=np.float32).tobytes()).digest() for r in X}


def runtime_check(train_fn, W, rows, Ct, label, **kw):
    seen = []; H = row_hashes(W["X"]); orig_f, orig_e = M.MLPPrior.forward, M.Meta.embed
    def fwd(self, x): seen.append(x.detach().clone()); return orig_f(self, x)
    def emb(self, x): seen.append(x.detach().clone()); return orig_e(self, x)
    M.MLPPrior.forward, M.Meta.embed = fwd, emb
    try:
        for cens in (False, True): train_fn(W["X"], rows, Ct, cens, **kw)
    finally: M.MLPPrior.forward, M.Meta.embed = orig_f, orig_e
    n = 0; bad = 0; widths = set()
    for x in seen:
        widths.add(int(x.shape[-1]))
        for r in x.reshape(-1, x.shape[-1]).numpy():
            n += 1
            if hashlib.sha1(np.ascontiguousarray(r, dtype=np.float32).tobytes()).digest() not in H: bad += 1
    return dict(label=label, n_input_rows_checked=n, n_rows_not_in_fingerprint_matrix=bad, input_widths=sorted(widths), PASS=bool(bad == 0 and widths == {P.NB} and n > 0))


def static_check(fn_source, names=("train_mlp_prior", "train_meta")):
    tree = ast.parse(textwrap.dedent(fn_source)); res = []
    for fn in [n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef) and n.name in names]:
        for c in [n for n in ast.walk(fn) if isinstance(n, ast.Call)]:
            f = c.func; name = None
            if isinstance(f, ast.Name) and f.id == "m": name = "m"
            elif isinstance(f, ast.Attribute) and f.attr == "embed" and isinstance(f.value, ast.Name) and f.value.id == "m": name = "m.embed"
            if name is None: continue
            def root_ok(a):                      # Xt[...] possibly wrapped in .reshape(-1)/subscripts
                while isinstance(a, (ast.Attribute, ast.Call)): a = a.func if isinstance(a, ast.Call) else a.value
                return isinstance(a, ast.Subscript) and isinstance(a.value, ast.Name) and a.value.id == "Xt"
            arg0 = c.args[0] if c.args else None
            res.append(dict(fn=fn.name, call=name, arg=ast.unparse(arg0) if arg0 is not None else None, ok=bool(arg0 is not None and (isinstance(arg0, ast.Subscript) and root_ok(arg0) or (isinstance(arg0, ast.Call) and root_ok(arg0))))))
    return dict(calls=res, n_calls=len(res), PASS=bool(res and all(r["ok"] for r in res)))


def main(out):
    W = M.load_world(); T = M.target_table(W); C = M.censored_table(W); rows, Ct = M.train_rows(W, T, 0, C); rows = rows[:40]
    src = inspect.getsource(M.train_mlp_prior) + "\n" + inspect.getsource(M.train_meta)
    res = dict(runtime_mlp_prior=runtime_check(M.train_mlp_prior, W, rows, Ct, "train_mlp_prior (exact-only and Tobit)", epochs=1),
               runtime_meta=runtime_check(M.train_meta, W, rows, Ct, "train_meta (exact-only and Tobit)", steps=6, ckpts=(6,)), static=static_check(src))
    # (C) negative control: leaky copy adds the censoring type / target value to the input
    leaky = inspect.getsource(M.train_mlp_prior).replace("mu = m(Xt[idx[ii]])", "mu = m(Xt[idx[ii]] + 0.5 * tt[ii].float()[:, None])").replace("def train_mlp_prior(", "def train_mlp_prior_LEAKY(")
    assert "tt[ii].float()" in leaky
    ns = dict(vars(M)); exec(leaky, ns)
    res["negative_control_runtime"] = runtime_check(ns["train_mlp_prior_LEAKY"], W, rows, Ct, "LEAKY copy (type added to input)", epochs=1)
    res["negative_control_static"] = static_check(leaky, names=("train_mlp_prior_LEAKY",))
    res["negative_control_detected_by_runtime"] = not res["negative_control_runtime"]["PASS"]; res["negative_control_detected_by_static"] = not res["negative_control_static"]["PASS"]
    res["L1_i_PASS"] = bool(res["runtime_mlp_prior"]["PASS"] and res["runtime_meta"]["PASS"] and res["static"]["PASS"] and res["negative_control_detected_by_runtime"] and res["negative_control_detected_by_static"])
    json.dump(res, open(out, "w"), indent=1); print(json.dumps({k: (v if not isinstance(v, dict) else {kk: vv for kk, vv in v.items() if kk != "calls"}) for k, v in res.items()}, indent=1))


if __name__ == "__main__": main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(P.HERE, "results", "leakcheck.json"))
