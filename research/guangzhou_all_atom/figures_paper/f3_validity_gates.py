"""F3 — benchmark validity gates. For analyses I, M, M2, M3: AUROC (family-cluster 95% CI) of the strongest
baseline, the best scored arm, and the three primary no-target controls (C1 atom-LM typicality, C2 multi-proxy
leave-fold-out, C3 Morgan leave-fold-out). Vertical line = chance. A control above chance means compound-only
information separates positives from decoys, so the analysis cannot be used to credit a model with target knowledge.
Artifacts: retro_recovery results_V2_{I,M,M2}.json, validity_gate_{I,M,M2,M3}.json.
"""
import json

import numpy as np

from common import C, check, plt, reread, savefig, sources_of, src

RR = "research/guangzhou_all_atom/multitarget/integrin_chembl/retro_recovery/results/"
analyses = [("I", "analysis I (same-target inactives)", True), ("M", "M (cross-target decoys, diagnostic)", True),
            ("M2", "M2 (matched decoys v1)", True), ("M3", "M3 (matched decoys v2; arms not scored)", False)]
rows = []
used = []
for key, label, has_arms in analyses:
    gate = json.load(open(src(RR + f"validity_gate_{key}.json")))
    used.append(RR + f"validity_gate_{key}.json")
    pts = {}
    if has_arms:
        res = json.load(open(src(RR + f"results_V2_{key}.json")))["all"]
        used.append(RR + f"results_V2_{key}.json")
        sb = res["strongest_baseline_auc"]
        pts["strongest baseline (" + sb + ")"] = (res["arms"][sb]["auc"], (RR + f"results_V2_{key}.json", "all", "arms", sb, "auc"))
        s_arms = {a: v["auc"] for a, v in res["arms"].items() if a.startswith("S") and "leaky" not in a}
        best = max(s_arms, key=lambda a: s_arms[a]["point"])
        pts["best scored arm (" + best + ")"] = (s_arms[best], (RR + f"results_V2_{key}.json", "all", "arms", best, "auc"))
    for ck, name in (("C1_atomlm_typicality", "C1 typicality (atom LM)"), ("C2_multiproxy_leave_fold_out", "C2 multi-proxy"),
                     ("C3_morgan_fp_leave_fold_out", "C3 Morgan leave-fold-out")):
        pts[name] = (gate["primary"][ck], (RR + f"validity_gate_{key}.json", "primary", ck))
    rows.append((label, gate["VALID"], gate["failed_controls"], pts))

series = ["strongest baseline", "best scored arm", "C1 typicality (atom LM)", "C2 multi-proxy", "C3 Morgan leave-fold-out"]
colors = [C["blue"], C["orange"], C["green"], C["purple"], C["vermilion"]]
fig, ax = plt.subplots(figsize=(8.2, 3.9))
ypos = 0.0
yticks, ylabels = [], []
for label, valid, failed, pts in rows:
    base = ypos
    for si, sname in enumerate(series):
        k = next((kk for kk in pts if kk.startswith(sname)), None)
        if k is None:
            continue
        p, keypath = pts[k]
        y = base - si * 0.16
        cont = ax.errorbar(p["point"], y, xerr=[[p["point"] - p["lo"]], [p["hi"] - p["point"]]], fmt="o", ms=3.6, color=colors[si],
                           capsize=1.8, lw=1.0)
        ax.text(p["hi"] + 0.012, y, f"{p['point']:.2f} (n={p['n_families']})", va="center", fontsize=5.8, color=colors[si])
        # consistency check against the artifact value
        rel, *ks = keypath
        check(f"{label[:14]} | {k} | point", float(cont.lines[0].get_xdata()[0]), float(reread(rel, *ks, "point")))
        seg = cont.lines[2][0].get_segments()[0]          # drawn error-bar segment [[lo, y], [hi, y]]
        check(f"{label[:14]} | {k} | lo", float(seg[0][0]), float(reread(rel, *ks, "lo")))
        check(f"{label[:14]} | {k} | hi", float(seg[1][0]), float(reread(rel, *ks, "hi")))
    yticks.append(base - 0.32)
    verdict = "gate VALID" if valid else "gate FAILED: " + ", ".join(f.replace("secondary:", "").replace("_leave_fold_out", "") for f in failed[:3]) + ("…" if len(failed) > 3 else "")
    ylabels.append(f"{label}\n{verdict}")
    ypos -= 1.15
ax.axvline(0.5, color=C["black"], lw=0.8, ls="--")
ax.text(0.5, 0.18, "chance", ha="center", fontsize=6)
ax.set_yticks(yticks, ylabels, fontsize=6.4)
ax.set_xlim(0.2, 1.0)
ax.set_xlabel("AUROC (family-cluster bootstrap 95% CI)")
ax.set_title("F3. Benchmark validity gates: no-target controls vs strongest baseline and best arm", loc="left")
for si, sname in enumerate(series):
    ax.plot([], [], "o", color=colors[si], label=sname, ms=4)
ax.legend(frameon=False, loc="upper center", bbox_to_anchor=(0.45, -0.13), ncol=5, fontsize=6, columnspacing=1.2, handletextpad=0.2)
fig.tight_layout()
caption = ("F3. Validity gates for the four benchmark analyses. Points: AUROC with 95% family-cluster bootstrap interval (n families in labels). "
           "C1–C3 use no target information; a control above 0.5 (interval excluding 0.5) fails the gate. M3 arms were not scored (analysis not valid). "
           "Gate designed after M2's failing control was known (retrospective for I, M, M2).")
savefig(fig, "F3_validity_gates", "F3 validity gates", caption, sources_of(*dict.fromkeys(used)))
