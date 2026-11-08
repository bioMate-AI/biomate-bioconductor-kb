#!/usr/bin/env python3
"""Re-score ONLY the re-captured manual assets (2026-10-13) with the same 3-model
vision committee, compare to the first pass, and write to NEW result files
(does not overwrite committee_raw.json / aggregated.json)."""
import os, json, glob, base64, time, urllib.error
import review as R  # reuse models(), build_map(), usecase_of(), RUBRIC, parse(), ask(), ASSETS, RES

SUBSET = [s + ".png" for s in (
    "t7-2-members-roles i12-1-connectors-dialog s1-1-sidebar "
    "t3-2-after-run-summary r5-outputs t3-3-after-run-outputs i08-1-outputs-tab "
    "r6-reproducibility t3-4-after-run-reproducibility i09-1-three-tabs i09-2-reproducibility-record "
    "r1-prerun-param-strip t3-1-workflow-panel r2-running w1-1-phases w1-2-workflow-settings "
    "i11-3-multi-objective t11-2-design-candidates i05-0-data-hub t10-1-dataset-preview "
    "t10-2-dataset-lineage t10-4-dataset-versions t6-1-instruments-tab t7-0-project-overview "
    "t7-1-standing-instructions w3-1-step-row w3-2-fullstep-provenance"
).split()]
SUBSET += sorted(os.path.basename(p) for p in glob.glob(R.ASSETS + "/domain-*-prerun.png"))

# Corrected intended-states: the manual's alt-text for some shots is now stale
# relative to the (correct) re-captured image. Override so the committee judges
# against the true intended state, not the old caption.
CONTEXT_OVERRIDE = {
    "t3-2-after-run-summary.png": "Results tab of a COMPLETED ADMET run that HAS readable findings — the Findings Summary + Key Results table SHOULD be populated (the older 'findings withheld' caption is stale; showing real findings is correct). A separate top-right 'Download report' button is legitimate.",
    "t3-3-after-run-outputs.png": "Results tab, Outputs section of a completed ADMET run — inline output-file previews. 'Download report' top-right is a legitimate separate button.",
    "r5-outputs.png": "Outputs section of a completed ADMET run on the Results tab — inline file previews. 'Download report' top-right is legitimate.",
    "r6-reproducibility.png": "The Reproducibility record tab of a completed run (identity, resolved params, outputs table with SHA-256) — this figure is SUPPOSED to show the Reproducibility tab, not the Results tab.",
    "t3-4-after-run-reproducibility.png": "The Reproducibility record tab of a completed run — this figure is SUPPOSED to show the Reproducibility tab.",
    "i09-2-reproducibility-record.png": "The Reproducibility record tab — identity, resolved parameters, outputs table with SHA-256 column. Showing this tab is correct.",
    "i09-1-three-tabs.png": "The Results (landing) tab — Findings Summary banner + Key Results table; a separate top-right 'Download report' button is legitimate (coexists with 'Download findings').",
    "r2-running.png": "A RUNNING ADMET workflow (running-state figure) — Running badge, a phase card RUNNING, QC gates, Pause/Stop. This is the ADMET running state, NOT design results.",
    "r1-prerun-param-strip.png": "IDLE pre-run ADMET Workflow-settings panel — filled params, Confirm & Run ready. Pre-run/idle state is correct.",
    "t3-1-workflow-panel.png": "IDLE pre-run ADMET Workflow-settings panel (not a completed run).",
    "t7-2-members-roles.png": "The Members & roles panel, OWNER view — invite box + role selector + share-link + member list. Only the owner is present (adding real Editor/Viewer members requires live invites, so owner-only is acceptable for this capture).",
}

def consensus(rec):
    sevs = [rec["reviews"].get(p, {}).get("verdict", {}).get("severity") for p in ("openai", "google", "anthropic")]
    sevs = [s for s in sevs if s in ("ok", "minor", "major")]
    if not sevs: return "ERR"
    if sevs.count("major") >= 2: return "major"
    if sevs.count("major") == 1 or sevs.count("minor") >= 2: return "minor"
    if "minor" in sevs: return "minor"
    return "ok"

def main():
    M = R.models(); print("committee:", M, flush=True)
    amap = R.build_map()
    present = [a for a in SUBSET if os.path.exists(os.path.join(R.ASSETS, a))]
    print(f"{len(present)}/{len(SUBSET)} subset assets present\n", flush=True)
    allres = {}
    for i, a in enumerate(present):
        info = amap.get(a, {"pages": set(), "captures": []})
        uc = R.usecase_of(info["pages"])
        if a in CONTEXT_OVERRIDE:
            ctx = f"use-case/page: {uc}. INTENDED STATE: {CONTEXT_OVERRIDE[a]}"
        else:
            ctx = f"use-case/page: {uc}. " + (" | ".join(info["captures"][:2]) if info["captures"] else "(not referenced by any manual page)")
        b64 = base64.b64encode(open(os.path.join(R.ASSETS, a), "rb").read()).decode()
        rec = {"asset": a, "usecase": uc, "reviews": {}}
        for prov, model in M.items():
            if not model: rec["reviews"][prov] = {"error": "no model"}; continue
            for attempt in range(2):
                try:
                    raw = R.ask(model, b64, ctx)
                    if raw and raw.strip():
                        rec["reviews"][prov] = {"model": model, "verdict": R.parse(raw)}; break
                    rec["reviews"][prov] = {"model": model, "error": "empty"}
                except urllib.error.HTTPError as e:
                    rec["reviews"][prov] = {"model": model, "error": f"HTTP {e.code}"}
                except Exception as e:
                    rec["reviews"][prov] = {"model": model, "error": str(e)[:120]}
                time.sleep(4)
        rec["consensus"] = consensus(rec)
        print(f"  [{i+1}/{len(present)}] {a:38} {rec['consensus']}", flush=True)
        allres[a] = rec
        json.dump({"committee": M, "results": allres}, open(os.path.join(R.RES, "rescore_raw.json"), "w"), indent=2)
        time.sleep(0.3)
    # aggregate
    agg = {a: {"consensus": r["consensus"],
               "issues": sum((r["reviews"].get(p, {}).get("verdict", {}).get("issues", []) for p in ("openai", "google", "anthropic")), [])}
           for a, r in allres.items()}
    json.dump(agg, open(os.path.join(R.RES, "rescore_aggregated.json"), "w"), indent=2)
    from collections import Counter
    print("\nconsensus tally:", dict(Counter(r["consensus"] for r in allres.values())), flush=True)
    print("DONE -> results/rescore_raw.json + rescore_aggregated.json", flush=True)

if __name__ == "__main__":
    main()
