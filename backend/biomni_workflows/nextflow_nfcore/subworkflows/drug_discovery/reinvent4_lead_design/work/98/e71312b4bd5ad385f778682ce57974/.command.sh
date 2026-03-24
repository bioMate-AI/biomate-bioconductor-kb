#!/bin/bash -ue
python3 << 'PYEOF'
import json, csv
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

with open('score_history.json') as f:
    history_data = json.load(f)
with open('filter_stats.json') as f:
    filter_data = json.load(f)
with open('validated_input.json') as f:
    input_cfg = json.load(f)

history = history_data.get('history', [])

# Score trajectory plot
if history:
    epochs      = [h['epoch'] for h in history]
    mean_scores = [h['mean_score'] for h in history]
    top_scores  = [h['top_score']  for h in history]

    fig, ax = plt.subplots(figsize=(10, 5))
    ax.plot(epochs, mean_scores, 'b-', linewidth=2, label='Mean score')
    ax.plot(epochs, top_scores,  'r-', linewidth=2, label='Top score')
    ax.fill_between(epochs, mean_scores, top_scores, alpha=0.1, color='purple')
    ax.set_xlabel('RL Epoch'); ax.set_ylabel('Score')
    ax.set_title('REINVENT4 Score Trajectory'); ax.legend(); ax.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig('score_trajectory.png', dpi=150, bbox_inches='tight')
    plt.close()

# Read top compounds
top_rows = []
with open('top_compounds.csv') as f:
    for row in csv.DictReader(f):
        top_rows.append(row)

summary = {
    "mock_mode": False,
    "seed_smiles": input_cfg['seed_smiles'],
    "design_mode": input_cfg['mode'],
    "scoring_function": input_cfg['scoring_function'],
    "n_steps": history_data.get('n_steps_total', 0),
    "batch_size": 128,
    "molecules_generated": filter_data.get('input_molecules', 0),
    "molecules_after_filter": filter_data.get('final_selected', 0),
    "final_mean_score": history_data.get('final_mean_score', 0),
    "final_top_score": history_data.get('final_top_score', 0),
    "top_compound": {
        "smiles": top_rows[0]['smiles'],
        "score": float(top_rows[0]['score']),
        "qed": float(top_rows[0].get('qed', 0)),
        "sa_score": float(top_rows[0].get('sa_score', 0)),
        "mw": float(top_rows[0].get('mw', 0)),
    } if top_rows else None,
}

with open('design_summary.json', 'w') as f:
    json.dump(summary, f, indent=2)

# HTML report
html_rows = ""
for i, row in enumerate(top_rows[:20], 1):
    score = float(row.get('score', 0))
    color = '#c8e6c9' if score > 0.75 else '#fff9c4' if score > 0.5 else '#ffccbc'
    html_rows += f'<tr style="background:{color}"><td>{i}</td><td><code>{row.get("smiles","")}</code></td><td><b>{score:.4f}</b></td><td>{row.get("qed","")}</td><td>{row.get("sa_score","")}</td><td>{row.get("mw","")}</td></tr>'

with open('design_report.html', 'w') as f:
    f.write(f'''<!DOCTYPE html><html><head><meta charset="utf-8"><title>REINVENT4 Report</title>
<style>body{{font-family:Arial,sans-serif;margin:40px}} table{{border-collapse:collapse;width:100%}} th{{background:#1565c0;color:white;padding:8px}} td{{padding:6px;border-bottom:1px solid #ddd}}</style></head>
<body><h1>REINVENT4 Design Report</h1>
<p>Seed: <code>{summary["seed_smiles"]}</code> | Mode: {summary["design_mode"]} | Molecules: {summary["molecules_after_filter"]}</p>
<table><tr><th>Rank</th><th>SMILES</th><th>Score</th><th>QED</th><th>SA</th><th>MW</th></tr>{html_rows}</table>
</body></html>''')

print(json.dumps(summary, indent=2))
PYEOF
