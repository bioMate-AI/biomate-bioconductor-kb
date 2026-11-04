#!/usr/bin/env python3
"""Score the generative-routing A/B (criterion fixed BEFORE the after-arm was run).

Generative prompts: correct if the card is a generative / optimisation design workflow of the
right modality. Controls (predict, dock, rank, safety gate, ADMET screen): correct if the card is
NOT a generative design workflow — the generative-task hint must not leak into them.
Indices refer to scripts/routing_eval/dump_payloads.sh output (2026-11-03 catalog of examples).
Usage: scripts/routing_eval/gen_score.py <rows.jsonl> [...]
"""
import collections
import json
import re
import sys

GEN_SM = re.compile(r"reinvent|de ?novo|\bmpo\b|scaffold hop|generative|lead design|fragment|active learning|bayesian|design[- ]make", re.I)
GEN_PEP = re.compile(r"peptide.*design|cyclic peptide|macrocycle design|stapled", re.I)
GEN_AB = re.compile(r"antibod|nanobod|vhh|scfv", re.I)
ANY_GEN = re.compile(GEN_SM.pattern + "|" + GEN_PEP.pattern + "|antibody design|nanobody design|scfv antibody design|bispecific antibody design", re.I)

PROMPTS = {  # idx -> (kind, modality)
    27: ("gen", "sm"), 30: ("gen", "sm"), 54: ("gen", "sm"), 55: ("gen", "sm"), 57: ("gen", "sm"),
    58: ("gen", "sm"), 59: ("gen", "sm"), 81: ("gen", "sm"), 83: ("gen", "sm"),
    33: ("gen", "pep"), 35: ("gen", "pep"), 60: ("gen", "pep"), 62: ("gen", "pep"),
    36: ("gen", "ab"),
    39: ("ctl", None), 41: ("ctl", None), 66: ("ctl", None), 67: ("ctl", None), 85: ("ctl", None),
}
IDS = ",".join(str(i) for i in PROMPTS)


def ok(idx, wf):
    kind, mod = PROMPTS[idx]
    wf = wf or ""
    if kind == "ctl":
        return bool(wf) and not ANY_GEN.search(wf)
    return bool({"sm": GEN_SM, "pep": GEN_PEP, "ab": GEN_AB}[mod].search(wf))


def main():
    for path in sys.argv[1:]:
        rows = [json.loads(l) for l in open(path)]
        per = collections.defaultdict(list)
        for r in rows:
            if r["idx"] in PROMPTS and r["state"] == "workflow_ready":
                per[r["idx"]].append(ok(r["idx"], r["wf"]))
        gen = [v for i, vs in per.items() if PROMPTS[i][0] == "gen" for v in vs]
        ctl = [v for i, vs in per.items() if PROMPTS[i][0] == "ctl" for v in vs]
        dropped = sum(1 for r in rows if r["http"] in (-1, -2))
        print(f"{path}: rows={len(rows)}  generative correct {sum(gen)}/{len(gen)}  controls unchanged {sum(ctl)}/{len(ctl)}  "
              f"client-dropped={dropped}")
        for i in sorted(per):
            cards = collections.Counter(r["wf"] for r in rows if r["idx"] == i and r["state"] == "workflow_ready")
            print(f"   [{i:3d}] {PROMPTS[i][0]}/{PROMPTS[i][1] or '-'} {sum(per[i])}/{len(per[i])}  {dict(cards)}")


if __name__ == "__main__":
    main()
