"""Phase-1.2: the closed optimizer loop.  propose -> score() -> select -> revise -> repeat.

Ties the already-built pieces into one driver:
  - propose : rule_conditioned_generator.gen_avb6 (clean by construction) + a deliberately-failing seed set
  - score   : score.score  (cheap deterministic tier: rule + FTO + developability; expensive tier = hooks)
  - select  : freeze gate-passers, Pareto-rank by score.rank_key
  - revise  : a deterministic, score-record-READING repair operator.  This is the SYMBOLIC STAND-IN for the
              LLM-in-the-loop revise move (the SL-01 -> SL-v3 "read the failing objective, edit the free
              position" step) - same honest stand-in posture as the enumeration generator.  When the neural
              generator / an RL driver lands, it replaces `revise` (and the reward stays score()).

Honest framing: no LLM or RL is wired here yet.  The loop HARNESS and the convergence (failure -> targeted
repair -> re-score -> gated) are real and deterministic; `revise` is a labeled stand-in, not a learned policy.
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from score import score
from rule_conditioned_generator import gen_avb6
from acceptance_gate import raw_tokens, _is_arom, _strip_mods

HERE = os.path.dirname(__file__)

# free positions in the KB scaffold  cyclo(p1 - R - G - D - L - p6 - p7 - [dP] - [NMeK])
P1, P6, P7 = 0, 5, 6


def _helm(toks):
    """Rebuild a HELM string from token cores: canonical 1-letter bare, everything else bracketed."""
    return "cyclo(" + "-".join(t if len(t) == 1 else f"[{t}]" for t in toks) + ")"


def revise(rec):
    """Read the failing objective in a score() record and apply ONE targeted free-position edit.
    Returns (repaired_helm, action) or (None, reason) when the failure is outside the free-position repair set.
    One failure-class per call; the loop re-scores and the next round catches the next class."""
    if rec["hard_gate_pass"]:
        return None, "already-gated"
    toks = raw_tokens(rec["helm"])
    if len(toks) != 9:
        return None, "ring-size!=9 (not repairable by free-position edit)"
    r = rec["hard_gate_reasons"]
    # 1) rule fail -> restore aromatic character at whichever flank is non-aromatic
    if not r["rule"]:
        fixed = []
        for idx in (P1, P7):
            if not _is_arom(toks[idx]):
                toks[idx] = "F"
                fixed.append(f"p{1 if idx==P1 else 7}->F")
        if fixed:
            return _helm(toks), "rule:flank-aromatic(" + ",".join(fixed) + ")"
        return None, "rule-fail not at a free flank"
    # 2) FTO infringing (literal genus) -> diverge the P7 flank with an ncAA homolog -> literally OUTSIDE(MED)
    if not r["fto_not_infringing"]:
        toks[P7] = "2Nal"
        return _helm(toks), "fto:p7->[2Nal] (ncAA-divergent, out of literal genus)"
    # 3) developability fail -> de-grease / drop liability at a free position
    if not r["developability"]:
        dev = rec["developability"]
        act = []
        if dev["greasy"]:
            if "2Nal" in (toks[P7], toks[P1]):                # too many naphthylalanines
                idx = P7 if toks[P7] == "2Nal" else P1
                toks[idx] = "Phe4F"                            # milder aromatic, still satisfies the rule
                act.append(f"p{7 if idx==P7 else 1}:[2Nal]->[Phe4F]")
            else:                                             # high meanH from elsewhere -> least-greasy aromatic
                toks[P7] = "Y"
                act.append("p7->Y (lower hydrophobicity)")
        if dev["liabilities"] and toks[P6] not in ("A", "G"):
            toks[P6] = "A"                                    # neutralize the specificity-knob liability motif
            act.append("p6->A (drop liability)")
        if act:
            return _helm(toks), "dev:" + ",".join(act)
        return None, "developability-fail not repairable at a free position"
    return None, "unknown-failure"


def optimize(seed, target="avb6", rounds=4):
    """Run the closed loop. Gate-passers are frozen; failures are revised and re-entered; stop when no failure
    is repairable or `rounds` is hit. Returns the Pareto-ranked gated set + a per-round trace."""
    population = list(dict.fromkeys(seed))      # dedupe, preserve order
    gated, seen, trace = {}, set(seed), []
    for rnd in range(1, rounds + 1):
        scored = [score(h, target) for h in population]
        passes = [r for r in scored if r["hard_gate_pass"]]
        fails = [r for r in scored if not r["hard_gate_pass"]]
        for r in passes:
            gated[r["helm"]] = r                 # freeze
        nxt, revisions = [], []
        for r in fails:
            new, action = revise(r)
            failed = [k for k, v in r["hard_gate_reasons"].items() if not v]
            if new and new not in seen:
                seen.add(new); nxt.append(new)
                revisions.append({"from": r["helm"], "to": new, "action": action, "status": "revised", "failed": failed})
            elif new:                                    # repaired onto a candidate already in the loop
                revisions.append({"from": r["helm"], "to": new, "action": action,
                                  "status": "converged (= existing candidate)", "failed": failed})
            else:                                        # no free-position edit resolves this failure
                revisions.append({"from": r["helm"], "to": None, "action": action,
                                  "status": "abandoned", "failed": failed})
        trace.append({"round": rnd, "scored": len(scored), "gated_now": len(passes), "failed": len(fails),
                      "revised": len([x for x in revisions if x["status"] == "revised"]),
                      "converged": len([x for x in revisions if x["status"].startswith("converged")]),
                      "abandoned": len([x for x in revisions if x["status"] == "abandoned"]),
                      "revisions": revisions})
        if not nxt:
            break
        population = nxt
    pareto = sorted(gated.values(), key=lambda r: r["rank_key"])
    return {"target": target, "n_gated": len(pareto), "pareto": pareto, "trace": trace}


if __name__ == "__main__":
    # propose: clean by-construction survivors  +  a deliberately-FAILING seed set (so revise has real work)
    _H, clean = gen_avb6(4)
    failing = [
        "cyclo(F-R-G-D-L-A-F-[dP]-[NMeK])",                 # avebehexin  -> INFRINGING (literal genus)
        "cyclo([2Nal]-R-G-D-L-A-[2Nal]-[dP]-[NMeK])",       # di-2Nal     -> GREASY (developability)
        "cyclo(A-R-G-D-L-G-A-[dP]-[NMeK])",                 # di-Ala flank-> RULE FAIL (no aromatic flanks)
    ]
    seed = [c["helm"] for c in clean] + failing
    res = optimize(seed, "avb6", rounds=4)

    print(f"SEED ({len(seed)}): {len(clean)} clean(by-construction) + {len(failing)} deliberately-failing\n")
    for t in res["trace"]:
        print(f"round {t['round']}: scored={t['scored']} gated={t['gated_now']} failed={t['failed']} "
              f"revised={t['revised']} converged={t['converged']} abandoned={t['abandoned']}")
        for rv in t["revisions"]:
            arrow = f"-> {rv['to']}" if rv["to"] else "-> (no free-position repair)"
            print(f"    FAIL {rv['failed']}  {rv['from']}")
            print(f"        [{rv['status']}] {rv['action']}  {arrow}")
    print(f"\nPARETO-RANKED GATED SET ({res['n_gated']}):")
    for r in res["pareto"]:
        print(f"  {r['helm']}  | FTO {r['fto']['verdict']} (DoE {r['fto']['doe']}) | dev meanH={r['developability']['meanH']} | binding={r['binding_dG']}")

    out = os.path.join(HERE, "target_kb", "avb6_loop_result.json")
    json.dump(res, open(out, "w"), indent=2)
    print(f"\nwrote {os.path.relpath(out, HERE)}  (loop result: pareto set + full revise trace)")
