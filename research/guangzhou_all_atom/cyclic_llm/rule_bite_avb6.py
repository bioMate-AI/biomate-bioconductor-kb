"""rule_bite_avb6.py — the decisive 'does the rule matter?' test, in the regime where it CAN matter.

The permeability close showed rule-ON == rule-OFF because v4's output is already developability-clean (the
rule rejected 0 candidates: non-binding). That does NOT mean rules are useless — it means that testbed was
redundant (a strong, in-distribution model). The honest test is a DECISIVE-GATE target the model does NOT
already satisfy: αvβ6, whose rule demands the RGD pharmacophore (RGD + RGDLxxL/I + D-Pro/N-methyl turn +
aromatic flanks + single Lys handle). Our own audit found free LLM generation is 0/12 RGD for αvβ6.

Same v4 model, two couplings:
  RULE OFF : free v4 generation (design.generate) -> measure αvβ6-rule admissibility (avb6_gate ∧ FTO).
  RULE ON  : v4 scores the FREE positions INSIDE the enforced αvβ6 scaffold (neural_generator.gen_avb6_neural)
             -> rule/FTO reject by construction; admissible by design.
Isolates the rule's contribution: both use the SAME model for the free-position chemistry; the only
difference is WHERE the rule acts (nowhere vs. at generation). If RULE OFF ~ 0% admissible and RULE ON =
100%, the rule is DECISIVE (it makes v4 usable for the target), i.e. rule != no-rule. CPU; no training.
"""
from __future__ import annotations
import argparse, json, os
import numpy as np
import design
import neural_generator as ng
from acceptance_gate import avb6_gate
import fto_score

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CKPT = os.path.join(ROOT, "runs_helm/unified_cyclic_llm_v4.pt")


def free_helm(monos):
    return "cyclo(" + "-".join(t if len(t) == 1 else f"[{t}]" for t in monos) + ")"


def avb6_admissible(helm):
    try:
        if not avb6_gate(helm).get("PASS_H1_H5"):
            return False, "rule_fail"
        if fto_score.fto_score(helm, "avb6")["claim"]["verdict"].startswith("INSIDE"):
            return False, "fto_infringing"
        return True, "ok"
    except Exception as e:
        return False, f"err:{type(e).__name__}"


def main():
    ap = argparse.ArgumentParser(description="αvβ6 rule-bite test: free v4 vs rule-constrained v4 (same model).")
    ap.add_argument("--n", type=int, default=300, help="candidates per arm")
    ap.add_argument("--temp", type=float, default=1.0)
    ap.add_argument("--out", default=os.path.join(ROOT, "results/rule_bite_avb6.json"))
    args = ap.parse_args()

    # ---- RULE OFF: free v4 generation (no rule anywhere) ----
    model, toks, stoi, a, dev = design.load(CKPT); block = a["block"]
    zero = np.zeros(design.v3.TFEAT_DIM if hasattr(design, "v3") else 0, dtype="float32")
    try:
        from train_cyclic_llm_v3 import TFEAT_DIM
        zero = np.zeros(TFEAT_DIM, dtype="float32")
    except Exception:
        pass
    free = design.generate(model, toks, stoi, zero, dev, args.n, block, 16, args.temp, e_tok="<e_na>", p_tok="<p_hi>")
    free_adm = [avb6_admissible(free_helm(m)) for m in free]
    off_ok = sum(1 for ok, _ in free_adm if ok)
    off_frac = round(off_ok / max(len(free), 1), 4)
    # why they fail
    from collections import Counter
    off_reasons = Counter(r for ok, r in free_adm if not ok)

    # ---- RULE ON: v4 scores the free positions inside the enforced αvβ6 scaffold (constrain-at-generation) ----
    try:
        _H, con, _meta = ng.gen_avb6_neural(args.n)
        backend = _meta.get("backend", "?")
    except Exception as e:
        con, backend = [], f"error:{type(e).__name__}:{str(e)[:80]}"
    con_helms = [c["helm"] for c in con]
    con_adm = [avb6_admissible(h) for h in con_helms]
    on_ok = sum(1 for ok, _ in con_adm if ok)
    on_frac = round(on_ok / max(len(con_helms), 1), 4) if con_helms else 0.0

    verdict = ("RULE IS DECISIVE (rule != no-rule): free v4 ~{:.0%} αvβ6-admissible vs rule-constrained {:.0%}"
               .format(off_frac, on_frac)) if (on_frac - off_frac) > 0.5 else \
              "inconclusive (rule not decisive here)"
    res = {"what": "αvβ6 rule-bite: same v4 model, rule OFF (free generation) vs ON (constrain-at-generation)",
           "n_per_arm": args.n,
           "rule_OFF_free_v4": {"n": len(free), "avb6_admissible_frac": off_frac, "n_admissible": off_ok,
                                "fail_reasons": dict(off_reasons)},
           "rule_ON_constrained_v4": {"backend": backend, "n": len(con_helms),
                                      "avb6_admissible_frac": on_frac, "n_admissible": on_ok,
                                      "examples": con_helms[:5]},
           "divergence_on_minus_off": round(on_frac - off_frac, 4), "verdict": verdict,
           "note": "Same v4 distribution supplies the free-position chemistry in BOTH arms; the only difference "
                   "is WHERE the rule acts. This is the regime the permeability close lacked (there the model "
                   "already satisfied the rule, so rule==no-rule). Rules help inversely to model strength / data "
                   "coverage: decisive for a target the model has NOT learned (0/12 RGD audit), redundant for a "
                   "property it has."}
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    json.dump(res, open(args.out, "w"), indent=2)
    print(f"RULE OFF (free v4):        {off_frac:.1%} αvβ6-admissible  (fails: {dict(off_reasons)})")
    print(f"RULE ON  (constrained v4): {on_frac:.1%} αvβ6-admissible  backend={backend}  e.g. {con_helms[:3]}")
    print(f"divergence (ON - OFF) = {on_frac - off_frac:+.1%}")
    print(f"VERDICT: {verdict}")
    print(f"wrote {os.path.relpath(args.out, ROOT)}")


if __name__ == "__main__":
    main()
