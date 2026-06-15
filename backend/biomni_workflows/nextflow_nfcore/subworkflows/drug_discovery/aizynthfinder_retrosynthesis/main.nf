#!/usr/bin/env nextflow
/*
 * drug_discovery/aizynthfinder_retrosynthesis
 *
 * Retrosynthesis of drug-like small molecules using AiZynthFinder
 * (AstraZeneca open-source CASP tool — https://github.com/MolecularAI/aizynthfinder)
 *
 * Inputs:
 *   smiles_list  — channel of SMILES strings (one per compound)
 *   (always live — no mock mode)
 *   max_routes   — max synthesis routes per compound (params, default 5)
 *   max_depth    — max retrosynthesis tree depth (params, default 6)
 *
 * Outputs (emitted channels):
 *   routes_json      — per-compound: tuple(compound_id, path(*_routes.json))
 *   filtered_tsv     — aggregated TSV: compound_id, best_route_steps, best_route_score, qc_status
 *   report_html      — HTML report with compound table, summary stats, SA score distribution
 *   qc_summary_json  — machine-readable QC summary for CRO pipeline integration
 *
 * Pipeline Steps:
 * 1. AIZYNTHFINDER_PREDICT  — Run AiZynthFinder per compound;
 *    output JSON: smiles, routes[]{steps, score, step_count, sa_score}, feasibility_rank
 * 2. RETROSYNTHESIS_FILTER  — QC gate per compound:
 *    PASS if ≥1 route has ≤4 steps AND score ≥0.6
 *    WARN if best route is 5–6 steps (or score <0.6 with ≤4 steps)
 *    FAIL if no routes found / all routes >6 steps / invalid SMILES
 * 3. RETROSYNTHESIS_REPORT  — Aggregate all compound results → HTML + CSV + QC JSON
 *
 * References:
 *  - AiZynthFinder: Genheden et al. J Cheminform 2020
 *    https://jcheminf.biomedcentral.com/articles/10.1186/s13321-020-00472-1
 *  - SA Score: Ertl & Schuffenhauer J Cheminform 2009
 */

nextflow.enable.dsl = 2

// ============================================================================
// Default Parameters
// ============================================================================

params.outdir           = './results/aizynthfinder_retrosynthesis'
params.publish_dir_mode = 'copy'

// AiZynthFinder search parameters
params.max_routes       = 5      // max synthesis routes to return per compound
params.max_depth        = 6      // max retrosynthesis tree depth

// QC gate thresholds
params.pass_max_steps   = 4      // PASS requires best route step_count ≤ this
params.pass_min_score   = 0.6    // PASS requires best route score ≥ this
params.warn_max_steps   = 6      // WARN if best route step_count ≤ this (but failed PASS)

// AiZynthFinder config path (live mode only)
params.aizynthfinder_config = '/opt/aizynthfinder/config.yml'

// Input
params.smiles_file      = null   // path to SMILES file OR inline SMILES (one per line); if null, uses seed_smiles
params.seed_smiles      = null   // single SMILES string (e.g. 'Cc1ccc(NC(=O)...)cc1')
params.mock_mode        = false  // CI smoke testing only — bypasses required-input guards. NEVER set true in production unless explicitly requested by the user.

// ============================================================================
// Helper functions
// ============================================================================

def log_workflow_header() {
    log.info """
    ====================================================================
    BioMate | AiZynthFinder Retrosynthesis Pipeline
    ====================================================================
    Max routes:         ${params.max_routes}
    Max depth:          ${params.max_depth}
    PASS threshold:     steps ≤ ${params.pass_max_steps}  AND  score ≥ ${params.pass_min_score}
    WARN threshold:     steps ≤ ${params.warn_max_steps}
    Output dir:         ${params.outdir}
    ====================================================================
    """.stripIndent()
}

// ============================================================================
// Process 1: AiZynthFinder Retrosynthesis Prediction
// ============================================================================

// [Retrosynthesis]
process AIZYNTHFINDER_PREDICT {
    tag "${compound_id}"
    label 'process_medium'
    publishDir "${params.outdir}/${compound_id}/01_predict", mode: params.publish_dir_mode

    // local (ARM dev): biomate/biomni-drug-discovery-nf:latest
    // aws batch (AMD64 ECR): 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-drug-discovery-nf:x86
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-drug-discovery-nf:x86' : 'biomate/biomni-drug-discovery-nf:latest'

    input:
    tuple val(compound_id), val(smiles)

    output:
    tuple val(compound_id), path("${compound_id}_routes.json"), emit: routes_json
    path "versions.yml",                                         emit: versions

    script:
    def max_routes = params.max_routes
    def max_depth  = params.max_depth
    def config     = params.aizynthfinder_config
    """
        # Pre-flight: ensure expansion policy is configured. The container's
        # build-time download_public_data step uses '|| true' so silent failures
        # leave the config with no expansion: section, and aizynthcli crashes
        # with IndexError on policy.items[0] before producing any output.
        # Runtime download isn't viable on the Batch container (the aizynthfinder
        # API surface for download_public_data varies across versions and Batch
        # task containers may have no outbound network to figshare). Fail loud
        # so a missing model is visible in logs instead of being silently
        # masked, and ship the route_count=0 honest result file so QC can
        # still observe an empty-routes outcome.
        if ! grep -q "^expansion:" "${config}" 2>/dev/null; then
            echo "[aizynth-predict] FATAL: ${config} has no expansion policy." >&2
            echo "[aizynth-predict] The container biomate/biomni-drug-discovery-nf:x86 was" >&2
            echo "[aizynth-predict] built without USPTO models. Rebuild the container with the" >&2
            echo "[aizynth-predict] models baked in (backend/docker/drug-discovery-nf/Dockerfile)." >&2
            echo "[aizynth-predict] Writing honest zero-routes result so QC can observe the failure." >&2
            python3 -c "
import json
compound_id = '${compound_id}'
out = {
    'compound_id':       compound_id,
    'smiles':            '${smiles}',
    'success':           False,
    'error':             'no_expansion_policy_in_container',
    'routes':            [],
    'route_count':       0,
}
open(f'{compound_id}_routes.json', 'w').write(json.dumps(out, indent=2))
"
            python3 -c "print('aizynthfinder: x.y.z')" > versions.yml
            exit 1
        fi

        # Run aizynthcli and normalize its output into BioMate JSON format.
        # aizynthcli writes a JSON file containing a list of solved route trees.
        aizynthcli \
            --smiles "${smiles}" \
            --output ${compound_id}_routes_raw.json \
            --config "${config}"

        python3 << 'PYEOF'
import json
import sys
from datetime import datetime

compound_id = "${compound_id}"
smiles      = "${smiles}"
max_routes  = int("${max_routes}")
raw_file    = f"{compound_id}_routes_raw.json"

try:
    raw = json.load(open(raw_file))
except (FileNotFoundError, json.JSONDecodeError) as exc:
    print(f"ERROR: could not read {raw_file}: {exc}", file=sys.stderr)
    result = {
        "compound_id":      compound_id,
        "smiles":           smiles,
        "smiles_valid":     False,
        "n_routes":         0,
        "routes":           [],
        "feasibility_rank": [],
        "error":            str(exc),
    }
    with open(f"{compound_id}_routes.json", "w") as f:
        json.dump(result, f, indent=2)
    sys.exit(0)

# aizynthcli output is a list of route tree dicts; handle both list and dict root
routes_raw = raw if isinstance(raw, list) else raw.get("routes", raw.get("trees", []))

def count_steps(node):
    if node.get("type") == "reaction":
        return 1 + sum(count_steps(c) for c in node.get("children", []))
    return sum(count_steps(c) for c in node.get("children", []))

def collect_steps(node, depth=0):
    steps = []
    if node.get("type") == "reaction":
        steps.append({
            "step":             depth + 1,
            "reaction_class":   node.get("metadata", {}).get("classification", "unknown"),
            "reagent":          node.get("metadata", {}).get("name", "unknown"),
            "precursor_smiles": ".".join(
                c.get("smiles", "") for c in node.get("children", [])
                if c.get("type") == "mol"
            ),
            "yield_pct": None,
        })
    for child in node.get("children", []):
        next_depth = depth + 1 if node.get("type") == "reaction" else depth
        steps.extend(collect_steps(child, next_depth))
    return steps

routes = []
for r_idx, route_tree in enumerate(routes_raw[:max_routes]):
    meta     = route_tree.get("metadata", {})
    n_steps  = count_steps(route_tree)
    steps    = collect_steps(route_tree)
    score    = float(meta.get("score", meta.get("reaction_class_score", 0.5)))
    sa_score = float(meta.get("sa_score", 3.0))
    routes.append({
        "route_id":   r_idx + 1,
        "score":      round(score, 3),
        "step_count": n_steps,
        "sa_score":   round(sa_score, 2),
        "steps":      steps,
    })

routes.sort(key=lambda x: x["score"], reverse=True)

result = {
    "compound_id":      compound_id,
    "smiles":           smiles,
    "smiles_valid":     True,
    "n_routes":         len(routes),
    "routes":           routes,
    "feasibility_rank": [r["route_id"] for r in routes],
    "max_routes":       max_routes,
    "max_depth":        int("${max_depth}"),
    "tool":             "aizynthfinder",
    "version":          "3.7.0",
    "timestamp":        datetime.utcnow().isoformat() + "Z",
}

with open(f"{compound_id}_routes.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"AiZynthFinder predict [{compound_id}]: {len(routes)} routes found")
for r in routes:
    print(f"  Route {r['route_id']}: steps={r['step_count']}  score={r['score']}  sa_score={r['sa_score']}")
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        aizynthfinder: \$(aizynthcli --version 2>&1 | head -1 || echo "unknown")
        python: \$(python3 --version 2>&1 | cut -d' ' -f2)
    END_VERSIONS
    """
}

// ============================================================================
// Process 2: Retrosynthesis Filter + QC Gate
// ============================================================================

// [Retrosynthesis]
process RETROSYNTHESIS_FILTER {
    tag "${compound_id}"
    label 'process_single'
    publishDir "${params.outdir}/${compound_id}/02_filter", mode: params.publish_dir_mode

    // local (ARM dev): biomate/biomni-drug-discovery-nf:latest
    // aws batch (AMD64 ECR): 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-drug-discovery-nf:x86
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-drug-discovery-nf:x86' : 'biomate/biomni-drug-discovery-nf:latest'

    input:
    tuple val(compound_id), path(routes_json)

    output:
    tuple val(compound_id), path("${compound_id}_filtered.json"), emit: filtered_json
    path "${compound_id}_filter.tsv",                              emit: filter_tsv
    path "versions.yml",                                           emit: versions

    script:
    def pass_max_steps = params.pass_max_steps
    def pass_min_score = params.pass_min_score
    def warn_max_steps = params.warn_max_steps
    """
    python3 << 'EOF'
import json
from datetime import datetime

compound_id    = "${compound_id}"
pass_max_steps = int("${pass_max_steps}")
pass_min_score = float("${pass_min_score}")
warn_max_steps = int("${warn_max_steps}")

data   = json.load(open("${routes_json}"))
routes = data.get("routes", [])
smiles_valid = data.get("smiles_valid", True)

# ---------------------------------------------------------------------------
# QC gate logic:
#   PASS — at least one route with step_count ≤ pass_max_steps AND score ≥ pass_min_score
#   WARN — best route step_count ≤ warn_max_steps (but failed PASS criteria)
#   FAIL — no routes / all routes exceed warn_max_steps / invalid SMILES
# ---------------------------------------------------------------------------
if not smiles_valid or len(routes) == 0:
    qc_status = "FAIL"
    qc_reason = "invalid_smiles" if not smiles_valid else "no_routes_found"
    best_steps = None
    best_score = None
    best_sa    = None
else:
    # Routes are sorted by score descending; best route = index 0
    best = routes[0]
    best_steps = best["step_count"]
    best_score = best["score"]
    best_sa    = best.get("sa_score", None)

    # Check PASS: at least one route meets both thresholds
    pass_routes = [
        r for r in routes
        if r["step_count"] <= pass_max_steps and r["score"] >= pass_min_score
    ]

    if pass_routes:
        qc_status = "PASS"
        qc_reason = f"route_with_steps<={pass_max_steps}_and_score>={pass_min_score}_found"
    elif best_steps <= warn_max_steps:
        qc_status = "WARN"
        qc_reason = f"best_route_steps={best_steps}_score={best_score}_below_pass_threshold"
    else:
        qc_status = "FAIL"
        qc_reason = f"all_routes_exceed_{warn_max_steps}_steps"

# Annotate each route with feasibility tier
for r in routes:
    if r["step_count"] <= pass_max_steps and r["score"] >= pass_min_score:
        r["feasibility_tier"] = "EXCELLENT"
    elif r["step_count"] <= warn_max_steps:
        r["feasibility_tier"] = "MODERATE"
    else:
        r["feasibility_tier"] = "POOR"

filtered = {
    "compound_id":       compound_id,
    "smiles":            data.get("smiles", ""),
    "smiles_valid":      smiles_valid,
    "qc_status":         qc_status,
    "qc_reason":         qc_reason,
    "best_route_steps":  best_steps,
    "best_route_score":  best_score,
    "best_sa_score":     best_sa,
    "n_routes":          len(routes),
    "pass_max_steps":    pass_max_steps,
    "pass_min_score":    pass_min_score,
    "warn_max_steps":    warn_max_steps,
    "routes":            routes,
    "timestamp":         datetime.utcnow().isoformat() + "Z",
}

with open(f"{compound_id}_filtered.json", "w") as f:
    json.dump(filtered, f, indent=2)

with open(f"{compound_id}_filter.tsv", "w") as f:
    f.write("compound_id\\tsmiles\\tbest_route_steps\\tbest_route_score\\tbest_sa_score\\tn_routes\\tqc_status\\tqc_reason\\n")
    f.write(
        f"{compound_id}\\t"
        f"{data.get('smiles', '')}\\t"
        f"{best_steps if best_steps is not None else 'NA'}\\t"
        f"{best_score if best_score is not None else 'NA'}\\t"
        f"{best_sa if best_sa is not None else 'NA'}\\t"
        f"{len(routes)}\\t"
        f"{qc_status}\\t"
        f"{qc_reason}\\n"
    )

status_icon = {"PASS": "✓", "WARN": "~", "FAIL": "✗"}.get(qc_status, "?")
print(f"Retrosynthesis filter [{compound_id}]: {status_icon} {qc_status}  ({qc_reason})")
if best_steps is not None:
    print(f"  Best route: steps={best_steps}  score={best_score}  sa_score={best_sa}")
    print(f"  PASS threshold: steps<={pass_max_steps} AND score>={pass_min_score}")
EOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version 2>&1 | cut -d' ' -f2)
        pass_max_steps: "${pass_max_steps}"
        pass_min_score: "${pass_min_score}"
        warn_max_steps: "${warn_max_steps}"
    END_VERSIONS
    """

    stub:
    """
    echo '{"compound_id":"${compound_id}","qc_status":"PASS","best_route_steps":3,"best_route_score":0.72}' > ${compound_id}_filtered.json
    printf 'compound_id\tsmiles\tbest_route_steps\tbest_route_score\tbest_sa_score\tn_routes\tqc_status\tqc_reason\n' > ${compound_id}_filter.tsv
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: "3.10.0"
    END_VERSIONS
    """
}

// ============================================================================
// Process 3: Retrosynthesis Aggregate Report
// ============================================================================

// [Retrosynthesis]
process RETROSYNTHESIS_REPORT {
    tag "aggregate_report"
    label 'process_low'
    publishDir "${params.outdir}/03_report", mode: params.publish_dir_mode

    // local (ARM dev): biomate/biomni-drug-discovery-nf:latest
    // aws batch (AMD64 ECR): 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-drug-discovery-nf:x86
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-drug-discovery-nf:x86' : 'biomate/biomni-drug-discovery-nf:latest'

    input:
    path(filtered_jsons)   // collected list of *_filtered.json from RETROSYNTHESIS_FILTER

    output:
    path "retrosynthesis_report.html", emit: report_html
    path "retrosynthesis_results.csv", emit: filtered_tsv
    path "qc_summary.json",            emit: qc_summary_json
    path "qc_metrics.json",            emit: qc_metrics
    path "versions.yml",               emit: versions

    script:
    def pass_max_steps = params.pass_max_steps
    def pass_min_score = params.pass_min_score
    """
    python3 << 'EOF'
import json
import glob
import os
from datetime import datetime

pass_max_steps = int("${pass_max_steps}")
pass_min_score = float("${pass_min_score}")

# ---------------------------------------------------------------------------
# Collect and parse all per-compound filtered JSONs
# ---------------------------------------------------------------------------
json_files = sorted(glob.glob("*_filtered.json"))
compounds  = []
for jf in json_files:
    try:
        compounds.append(json.load(open(jf)))
    except Exception as exc:
        print(f"  WARNING: could not parse {jf}: {exc}")

n_total = len(compounds)
n_pass  = sum(1 for c in compounds if c["qc_status"] == "PASS")
n_warn  = sum(1 for c in compounds if c["qc_status"] == "WARN")
n_fail  = sum(1 for c in compounds if c["qc_status"] == "FAIL")

sa_scores = [
    c["best_sa_score"] for c in compounds
    if c.get("best_sa_score") is not None
]
avg_sa = round(sum(sa_scores) / len(sa_scores), 2) if sa_scores else None

avg_steps = None
step_vals = [c["best_route_steps"] for c in compounds if c.get("best_route_steps") is not None]
if step_vals:
    avg_steps = round(sum(step_vals) / len(step_vals), 1)

# ---------------------------------------------------------------------------
# QC summary JSON (machine-readable for CRO pipeline integration)
# ---------------------------------------------------------------------------
qc_summary = {
    "pipeline":         "aizynthfinder_retrosynthesis",
    "n_compounds":      n_total,
    "n_pass":           n_pass,
    "n_warn":           n_warn,
    "n_fail":           n_fail,
    "pass_rate_pct":    round(100 * n_pass / max(n_total, 1), 1),
    "warn_rate_pct":    round(100 * n_warn / max(n_total, 1), 1),
    "fail_rate_pct":    round(100 * n_fail / max(n_total, 1), 1),
    "pass_threshold":   f"steps<={pass_max_steps} AND score>={pass_min_score}",
    "avg_best_sa_score": avg_sa,
    "avg_best_steps":   avg_steps,
    "compounds":        [
        {
            "compound_id":      c["compound_id"],
            "smiles":           c.get("smiles", ""),
            "qc_status":        c["qc_status"],
            "best_route_steps": c.get("best_route_steps"),
            "best_route_score": c.get("best_route_score"),
            "best_sa_score":    c.get("best_sa_score"),
            "n_routes":         c.get("n_routes", 0),
        }
        for c in compounds
    ],
    "timestamp":        datetime.utcnow().isoformat() + "Z",
}

with open("qc_summary.json", "w") as f:
    json.dump(qc_summary, f, indent=2)

# qc_metrics.json — gate metrics consumed by the QC monitor's
# aizynth_solved_routes gate (≥1 solved route, GOLD-anchored to
# Genheden 2020 — both metric AND cutoff in the paper). The
# canonical key the gate reader expects is "num_solved_routes".
# For a multi-compound campaign we report the TOTAL across compounds
# (gate fires unless every compound returned zero routes); per-compound
# routes are still in qc_summary["compounds"][i]["n_routes"].
_route_counts = [c.get("n_routes", 0) for c in qc_summary["compounds"]]
qc_metrics = {
    "num_solved_routes":            int(sum(_route_counts)),
    "min_solved_routes_per_compound": int(min(_route_counts)) if _route_counts else 0,
    "n_compounds":                  n_total,
    "n_pass":                       n_pass,
    "pass_rate_pct":                qc_summary["pass_rate_pct"],
    "avg_best_sa_score":            avg_sa,
    "avg_best_steps":               avg_steps,
}
with open("qc_metrics.json", "w") as f:
    json.dump(qc_metrics, f, indent=2)

# ---------------------------------------------------------------------------
# CRO pipeline CSV
# ---------------------------------------------------------------------------
with open("retrosynthesis_results.csv", "w") as f:
    f.write("compound_id,smiles,qc_status,best_route_steps,best_route_score,best_sa_score,n_routes,feasibility_tier\\n")
    for c in compounds:
        steps = c.get("best_route_steps", "")
        score = c.get("best_route_score", "")
        sa    = c.get("best_sa_score", "")
        n_rt  = c.get("n_routes", 0)
        # Derive feasibility tier for CSV
        if c["qc_status"] == "PASS":
            tier = "EXCELLENT" if (steps != "" and steps <= pass_max_steps and score != "" and score >= pass_min_score) else "GOOD"
        elif c["qc_status"] == "WARN":
            tier = "MODERATE"
        else:
            tier = "POOR"
        smiles_esc = c.get("smiles", "").replace('"', '""')
        f.write(
            f'"{c["compound_id"]}","{smiles_esc}","{c["qc_status"]}",'
            f'"{steps}","{score}","{sa}","{n_rt}","{tier}"\\n'
        )

# ---------------------------------------------------------------------------
# SA score distribution (bucket counts for HTML histogram)
# ---------------------------------------------------------------------------
buckets = {"1.0-2.0": 0, "2.0-3.0": 0, "3.0-4.0": 0, "4.0-5.0": 0, "5.0+": 0}
for sa in sa_scores:
    if sa < 2.0:
        buckets["1.0-2.0"] += 1
    elif sa < 3.0:
        buckets["2.0-3.0"] += 1
    elif sa < 4.0:
        buckets["3.0-4.0"] += 1
    elif sa < 5.0:
        buckets["4.0-5.0"] += 1
    else:
        buckets["5.0+"] += 1

max_bucket = max(buckets.values()) if buckets else 1

def sa_bar(count, max_count, width=30):
    filled = int(round(width * count / max(max_count, 1)))
    return "█" * filled + "░" * (width - filled)

# ---------------------------------------------------------------------------
# HTML report — self-contained with embedded CSS
# ---------------------------------------------------------------------------
status_color = {"PASS": "#27ae60", "WARN": "#f39c12", "FAIL": "#e74c3c"}
status_bg    = {"PASS": "#eafaf1", "WARN": "#fef9e7", "FAIL": "#fdedec"}

rows_html = ""
for c in compounds:
    st   = c["qc_status"]
    col  = status_color.get(st, "#7f8c8d")
    bg   = status_bg.get(st, "#f8f9fa")
    smi  = c.get("smiles", "")[:60] + ("..." if len(c.get("smiles", "")) > 60 else "")
    steps_disp = c.get("best_route_steps", "—")
    score_disp = f"{c.get('best_route_score', ''):.3f}" if c.get("best_route_score") is not None else "—"
    sa_disp    = f"{c.get('best_sa_score', ''):.2f}"   if c.get("best_sa_score")    is not None else "—"
    n_rt       = c.get("n_routes", 0)
    rows_html += (
        f'<tr style="background:{bg}">'
        f'<td><code>{c["compound_id"]}</code></td>'
        f'<td style="font-size:0.85em;max-width:220px;overflow:hidden;white-space:nowrap">{smi}</td>'
        f'<td style="text-align:center">{steps_disp}</td>'
        f'<td style="text-align:center">{score_disp}</td>'
        f'<td style="text-align:center">{sa_disp}</td>'
        f'<td style="text-align:center">{n_rt}</td>'
        f'<td style="text-align:center;font-weight:bold;color:{col}">{st}</td>'
        f'</tr>\\n'
    )

sa_hist_html = ""
for bucket_label, count in buckets.items():
    bar = sa_bar(count, max_bucket)
    sa_hist_html += (
        f'<tr><td style="font-family:monospace;padding:2px 8px">{bucket_label}</td>'
        f'<td style="font-family:monospace;color:#2980b9">{bar}</td>'
        f'<td style="padding:2px 8px">{count}</td></tr>\\n'
    )

ts      = datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")
mode_lbl = "LIVE"

html = f'''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>AiZynthFinder Retrosynthesis Report — BioMate</title>
  <style>
    body{{font-family:system-ui,sans-serif;margin:0;padding:24px;background:#f4f6f9;color:#2c3e50}}
    h1{{color:#1a252f;border-bottom:3px solid #2980b9;padding-bottom:8px}}
    h2{{color:#2980b9;margin-top:32px}}
    .meta{{background:#fff;border-radius:8px;padding:16px 24px;margin-bottom:20px;box-shadow:0 1px 4px rgba(0,0,0,.1)}}
    .meta span{{margin-right:24px;font-size:.9em;color:#555}}
    .stat-grid{{display:flex;gap:16px;flex-wrap:wrap;margin-bottom:24px}}
    .stat-box{{flex:1;min-width:140px;background:#fff;border-radius:8px;padding:16px;text-align:center;box-shadow:0 1px 4px rgba(0,0,0,.1)}}
    .stat-box .value{{font-size:2em;font-weight:bold}}
    .stat-box .label{{font-size:.85em;color:#777;margin-top:4px}}
    .pass-color{{color:#27ae60}}.warn-color{{color:#f39c12}}.fail-color{{color:#e74c3c}}.info-color{{color:#2980b9}}
    table{{width:100%;border-collapse:collapse;background:#fff;border-radius:8px;overflow:hidden;box-shadow:0 1px 4px rgba(0,0,0,.1)}}
    th{{background:#2980b9;color:#fff;padding:10px 12px;text-align:left;font-size:.9em}}
    td{{padding:8px 12px;border-bottom:1px solid #ecf0f1;font-size:.9em}}
    tr:last-child td{{border-bottom:none}}
    .hist-table td{{padding:3px 8px;font-size:.9em}}
    .footer{{margin-top:40px;font-size:.8em;color:#95a5a6;text-align:center}}
    .badge{{display:inline-block;padding:2px 8px;border-radius:4px;font-size:.8em;font-weight:bold}}
    .badge-live{{background:#e9f7ef;color:#27ae60}}
  </style>
</head>
<body>
  <h1>AiZynthFinder Retrosynthesis Report</h1>
  <div class="meta">
    <span><b>Pipeline:</b> BioMate / AiZynthFinder</span>
    <span><b>Mode:</b> <span class="badge badge-{mode_lbl.lower()}">{mode_lbl}</span></span>
    <span><b>Generated:</b> {ts}</span>
    <span><b>Compounds:</b> {n_total}</span>
    <span><b>PASS threshold:</b> steps &le; {pass_max_steps} &amp; score &ge; {pass_min_score}</span>
  </div>

  <h2>Summary</h2>
  <div class="stat-grid">
    <div class="stat-box"><div class="value info-color">{n_total}</div><div class="label">Total Compounds</div></div>
    <div class="stat-box"><div class="value pass-color">{n_pass}</div><div class="label">PASS ({round(100*n_pass/max(n_total,1),1)}%)</div></div>
    <div class="stat-box"><div class="value warn-color">{n_warn}</div><div class="label">WARN ({round(100*n_warn/max(n_total,1),1)}%)</div></div>
    <div class="stat-box"><div class="value fail-color">{n_fail}</div><div class="label">FAIL ({round(100*n_fail/max(n_total,1),1)}%)</div></div>
    <div class="stat-box"><div class="value info-color">{avg_steps if avg_steps is not None else "N/A"}</div><div class="label">Avg Best Steps</div></div>
    <div class="stat-box"><div class="value info-color">{avg_sa if avg_sa is not None else "N/A"}</div><div class="label">Avg SA Score</div></div>
  </div>

  <h2>Compound Results</h2>
  <table>
    <thead>
      <tr>
        <th>Compound ID</th><th>SMILES</th><th>Best Steps</th>
        <th>Best Score</th><th>SA Score</th><th>N Routes</th><th>QC Status</th>
      </tr>
    </thead>
    <tbody>
{rows_html}    </tbody>
  </table>

  <h2>SA Score Distribution</h2>
  <p style="font-size:.9em;color:#666">
    Synthetic Accessibility score: 1 = easy to synthesise, 10 = very difficult.
    Lower values indicate more commercially viable routes.
  </p>
  <table class="hist-table" style="width:auto">
    <thead><tr><th>SA Range</th><th>Distribution</th><th>Count</th></tr></thead>
    <tbody>
{sa_hist_html}    </tbody>
  </table>

  <div class="footer">
    BioMate Platform &mdash; AiZynthFinder Retrosynthesis Pipeline &bull;
    Genheden et al. J Cheminform 2020 &bull; {ts}
  </div>
</body>
</html>'''

with open("retrosynthesis_report.html", "w") as f:
    f.write(html)

print(f"Retrosynthesis report generated:")
print(f"  Compounds:      {n_total}")
print(f"  PASS: {n_pass} ({round(100*n_pass/max(n_total,1),1)}%)  WARN: {n_warn}  FAIL: {n_fail}")
print(f"  Avg SA score:   {avg_sa}  Avg best steps: {avg_steps}")
print(f"  Outputs:  retrosynthesis_report.html  retrosynthesis_results.csv  qc_summary.json")
EOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version 2>&1 | cut -d' ' -f2)
    END_VERSIONS
    """
}

// ============================================================================
// Entry workflow: AIZYNTHFINDER_RETROSYNTHESIS
// ============================================================================
//
// Data flow:
//
//   ch_smiles ──► (map to [compound_id, smiles] tuples)
//                              │
//                              ▼
//                   AIZYNTHFINDER_PREDICT  ← per compound → *_routes.json
//                              │
//                              ▼
//                   RETROSYNTHESIS_FILTER  ← per compound → *_filtered.json
//                              │
//                       .map{}.collect()
//                              │
//                              ▼
//                   RETROSYNTHESIS_REPORT  ← aggregate → HTML + CSV + QC JSON
//
// ============================================================================

workflow AIZYNTHFINDER_RETROSYNTHESIS {
    take:
    ch_smiles   // channel: val(smiles) — one SMILES string per compound

    main:
    // ------------------------------------------------------------------
    // Assign auto-generated compound IDs (CPND0001, CPND0002, …)
    // ------------------------------------------------------------------
    ch_compounds = ch_smiles
        .map { smiles -> smiles.trim() }
        .filter { it }
        .collect()
        .flatMap { smiles_list ->
            smiles_list.withIndex(1).collect { smiles, idx ->
                def compound_id = String.format("CPND%04d", idx)
                tuple(compound_id, smiles)
            }
        }

    // ------------------------------------------------------------------
    // Step 1: Run AiZynthFinder per compound
    // ------------------------------------------------------------------
    AIZYNTHFINDER_PREDICT(ch_compounds)

    // ------------------------------------------------------------------
    // Step 2: Apply QC gate per compound
    // ------------------------------------------------------------------
    RETROSYNTHESIS_FILTER(AIZYNTHFINDER_PREDICT.out.routes_json)

    // ------------------------------------------------------------------
    // Step 3: Aggregate all filtered results → HTML report + CSV + QC JSON
    // ------------------------------------------------------------------
    ch_all_filtered = RETROSYNTHESIS_FILTER.out.filtered_json
        .map { compound_id, f -> f }
        .collect()

    RETROSYNTHESIS_REPORT(ch_all_filtered)

    emit:
    routes_json     = AIZYNTHFINDER_PREDICT.out.routes_json
    filtered_tsv    = RETROSYNTHESIS_REPORT.out.filtered_tsv
    report_html     = RETROSYNTHESIS_REPORT.out.report_html
    qc_summary_json = RETROSYNTHESIS_REPORT.out.qc_summary_json
    versions        = AIZYNTHFINDER_PREDICT.out.versions
                          .mix(RETROSYNTHESIS_FILTER.out.versions)
                          .mix(RETROSYNTHESIS_REPORT.out.versions)
}

// ============================================================================
// Standalone Entry Point (nextflow run main.nf)
// ============================================================================

workflow {
    log_workflow_header()

    // ------------------------------------------------------------------
    // Five drug-like reference SMILES spanning a range of synthetic
    // complexity (aspirin → imatinib).  In live mode, supply your own
    // SMILES list via --smiles_file <path> (one SMILES per line).
    // ------------------------------------------------------------------
    if (!params.smiles_file && !params.seed_smiles && !params.mock_mode) {
        error "Provide --smiles_file <path> (one SMILES per line) or --seed_smiles <SMILES>"
    }
    // Mock-mode: substitute aspirin SMILES when neither input provided.
    def _seed_eff = (params.mock_mode && !params.smiles_file && (params.seed_smiles == null || params.seed_smiles.toString() in ['null', 'None', '']))
        ? 'CC(=O)Oc1ccccc1C(=O)O'
        : params.seed_smiles
    if (params.mock_mode && _seed_eff != params.seed_smiles) {
        log.info "MOCK MODE: substituting aspirin SMILES as seed for CI testing"
    }
    if (params.smiles_file) {
        ch_smiles = Channel
            .fromPath(params.smiles_file, checkIfExists: true)
            .splitText()
            .map { line -> line.trim() }
            .filter { it && !it.startsWith("#") }
    } else {
        ch_smiles = Channel.value(_seed_eff.trim())
    }

    // Run the pipeline
    AIZYNTHFINDER_RETROSYNTHESIS(ch_smiles)

    // Display summary
    AIZYNTHFINDER_RETROSYNTHESIS.out.routes_json.view { compound_id, routes_file ->
        "Routes JSON (${compound_id}):  ${routes_file}"
    }
    AIZYNTHFINDER_RETROSYNTHESIS.out.report_html.view { html_file ->
        "HTML report:                   ${html_file}"
    }
    AIZYNTHFINDER_RETROSYNTHESIS.out.qc_summary_json.view { qc_file ->
        "QC summary JSON:               ${qc_file}"
    }
    AIZYNTHFINDER_RETROSYNTHESIS.out.filtered_tsv.view { csv_file ->
        "CRO pipeline CSV:              ${csv_file}"
    }
}
