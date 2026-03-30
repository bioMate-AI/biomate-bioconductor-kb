#!/bin/bash -ue
python3 << 'EOF'
import json
import glob
import os
from datetime import datetime

pass_max_steps = int("4")
pass_min_score = float("0.6")

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
    "mock_mode":        bool("false" == "true"),
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

# ---------------------------------------------------------------------------
# CRO pipeline CSV
# ---------------------------------------------------------------------------
with open("retrosynthesis_results.csv", "w") as f:
    f.write("compound_id,smiles,qc_status,best_route_steps,best_route_score,best_sa_score,n_routes,feasibility_tier\n")
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
            f'"{steps}","{score}","{sa}","{n_rt}","{tier}"\n'
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
        f'</tr>\n'
    )

sa_hist_html = ""
for bucket_label, count in buckets.items():
    bar = sa_bar(count, max_bucket)
    sa_hist_html += (
        f'<tr><td style="font-family:monospace;padding:2px 8px">{bucket_label}</td>'
        f'<td style="font-family:monospace;color:#2980b9">{bar}</td>'
        f'<td style="padding:2px 8px">{count}</td></tr>\n'
    )

ts      = datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")
mode_lbl = "MOCK" if bool("false" == "true") else "LIVE"

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
    .badge-mock{{background:#e8f4fd;color:#2980b9}}
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
    "AIZYNTHFINDER_RETROSYNTHESIS:RETROSYNTHESIS_REPORT":
        python: $(python3 --version 2>&1 | cut -d' ' -f2)
        mock_mode: "false"
    END_VERSIONS
