"""Runtime overlay: insert the M6 cryo-EM density-guidance block into OM-TPS's
models/flow_matching.py om_interpolate loop, right before the OM gradient is applied.
Gated by env M6_DENSITY_LAM (absent -> baseline/OFF; identical image runs both arms).
Idempotent. Usage: python m6_patch.py <path-to-flow_matching.py>"""
import sys, io

BLOCK = '''                    # ===== M6 CryoDynamics density guidance (injected) =====
                    _m6lam = __import__("os").environ.get("M6_DENSITY_LAM")
                    if _m6lam is not None:
                        import density_guidance as _dg
                        if not hasattr(self, "_m6cache"):
                            import numpy as _np
                            _d = _np.load(__import__("os").environ["M6_DENSITY_NPZ"])
                            self._m6cache = (
                                torch.tensor(_d["grid"], dtype=noised_xs.dtype, device=self.device),
                                torch.tensor(_d["d_exp"], dtype=noised_xs.dtype, device=self.device),
                                float(_d["sigma"]))
                        _g, _de, _sig = self._m6cache
                        with torch.enable_grad():
                            _c = (noised_xs.detach() * self.norm_factor).requires_grad_(True)
                            _dl = float(_m6lam) * _dg.density_term(_c, _g, _de, _sig)
                            _dgrad = torch.autograd.grad(_dl, _c)[0] * self.norm_factor
                        _dgrad[:, 0] = 0
                        _dgrad[:, -1] = 0
                        grads_accumulator = grads_accumulator + _dgrad
                        actions and actions.__setitem__(-1, actions[-1] + float(_dl.item()))
                    # ===== end M6 =====
'''
ANCHOR = "                    noised_xs.grad = grads_accumulator"

def main(path):
    src = open(path).read()
    if "M6 CryoDynamics density guidance (injected)" in src:
        print("[m6_patch] already patched"); return
    if ANCHOR not in src:
        print("[m6_patch] ERROR: anchor line not found; aborting", file=sys.stderr); sys.exit(2)
    src = src.replace(ANCHOR, BLOCK + ANCHOR, 1)
    open(path, "w").write(src)
    print("[m6_patch] injected density guidance before OM grad application")

if __name__ == "__main__":
    main(sys.argv[1])
