#!/bin/bash -ue
python3 - <<'PYEOF'
import csv, json

with open('scored_compounds.csv') as f:
    rows = list(csv.DictReader(f))

# Add rank column
for i, r in enumerate(rows):
    r['rank'] = i + 1

top_n = min(int('10'), len(rows))
top_rows = rows[:top_n]

# Ranked CSV
with open('ranked_compounds.csv', 'w', newline='') as f:
    fields = ['rank', 'compound_id', 'potency_ic50_nm', 'herg_ic50_um',
              'potency_score', 'safety_score', 'composite_score', 'safety_flag']
    writer = csv.DictWriter(f, fieldnames=fields, extrasaction='ignore')
    writer.writeheader()
    writer.writerows(rows)

# HTML report
html_rows = ''
for r in rows:
    bg = '#d4edda' if r['safety_flag'] == 'SAFE' else '#f8d7da'
    html_rows += (
        f'<tr style="background:{bg}">'
        f'<td>{r["rank"]}</td><td>{r["compound_id"]}</td>'
        f'<td>{r["potency_ic50_nm"]}</td><td>{r["herg_ic50_um"]}</td>'
        f'<td>{r["potency_score"]}</td><td>{r["safety_score"]}</td>'
        f'<td><b>{r["composite_score"]}</b></td><td>{r["safety_flag"]}</td>'
        f'</tr>\n'
    )

html = f'''<!DOCTYPE html>
<html><head><title>Compound Ranking Report</title>
<style>body{{font-family:Arial,sans-serif;margin:20px}}
table{{border-collapse:collapse;width:100%}}
th,td{{border:1px solid #ddd;padding:8px;text-align:right}}
th{{background:#4472c4;color:white;text-align:center}}
td:nth-child(2){{text-align:left}}</style></head>
<body>
<h2>BCR-ABL1 Campaign -- Composite Safety-Potency Ranking</h2>
<p>Total compounds: {len(rows)} | Top {top_n} shown in detail</p>
<table>
<tr><th>Rank</th><th>Compound</th><th>BCR-ABL1 IC50 (nM)</th><th>hERG IC50 (uM)</th>
<th>Potency Score</th><th>Safety Score</th><th>Composite Score</th><th>Flag</th></tr>
{html_rows}
</table>
<p><small>Scoring: composite = {float("0.6")*100:.0f}% potency + {float("0.4")*100:.0f}% safety | hERG threshold: {params.herg_safe_threshold} uM</small></p>
</body></html>'''

with open('ranking_report.html', 'w') as f:
    f.write(html)

summary = {
    'total_compounds': len(rows),
    'safe_compounds': sum(1 for r in rows if r['safety_flag'] == 'SAFE'),
    'unsafe_compounds': sum(1 for r in rows if r['safety_flag'] == 'UNSAFE'),
    'top_compound': rows[0]['compound_id'] if rows else None,
    'top_score': float(rows[0]['composite_score']) if rows else 0.0,
    'top_10': [{'rank': r['rank'], 'compound_id': r['compound_id'],
                'composite_score': r['composite_score'], 'safety_flag': r['safety_flag']}
               for r in rows[:10]],
}
with open('ranking_summary.json', 'w') as f:
    json.dump(summary, f, indent=2)

print(f'Ranking complete. Top compound: {rows[0]["compound_id"]} score={rows[0]["composite_score"]}')
print(f'Safe: {summary["safe_compounds"]} / Unsafe: {summary["unsafe_compounds"]}')
PYEOF
