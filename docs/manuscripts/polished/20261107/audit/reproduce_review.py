from pathlib import Path
import re,json,csv,hashlib,importlib.util,subprocess
R=Path('/Users/kky/biomate-review'); D=R/'docs/manuscripts/polished/20261107'; P=R/'evaluation/datasets/public_export'
def mod(name,p):
 s=importlib.util.spec_from_file_location(name,p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
S=mod('bench_score',P/'score.py')
# Preserve source fingerprints and reproducible, read-only audit results.
manifest={str(p.relative_to(R)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (R/'docs/manuscripts').glob('20261027_*benchmark.md')}
(D/'audit/original_sha256.json').write_text(json.dumps(manifest,indent=2))
for script,name in [('evaluation/datasets/public_export/regen_leaderboard_csv.py','realbio_recomputed.csv'),('evaluation/datasets/drugdev_export/leaderboard.py','drugdev_recomputed.txt'),('evaluation/datasets/public_export/heldout_independence/check_independence.py','heldout.txt'),('evaluation/local_trial/measure_production_param_rules.py','parameter_rules.txt')]:
 p=subprocess.run(['python3','-I',str(R/script)]+(['--stdout'] if 'leaderboard' in script else []),capture_output=True,text=True)
 (D/'audit'/name).write_text(p.stdout); assert p.returncode==0,p.stderr
# Derive transparent tables from retained result artifacts; do not overwrite any source score.
board=list(csv.DictReader((R/'evaluation/datasets/drugdev_export/leaderboard.csv').open()))
pktable='| Model | Within twofold |\n|---|---:|\n'+'\n'.join(f"| {x['model']} | {float(x['pbpk_2fold']):.3f} |" for x in board)
B=P/'boin_benchmark'; audit=[]
for folder in ['results_fixed','results_direct','results_gen','onprem_spark']:
 for p in sorted((B/folder).glob('*.json')):
  if p.name.startswith('_'):continue
  obj=json.loads(p.read_text()); rows=obj if isinstance(obj,list) else obj.get('per_item',[])
  if not rows:continue
  audit.append(dict(file=str(p.relative_to(R)),n=len(rows),outcome=sum(x['outcome'] for x in rows)/len(rows),fidelity=sum(x['fidelity'] for x in rows)/len(rows),empties=sum(bool(x.get('empty')) for x in rows)))
(D/'audit/dose_receipt_summary.json').write_text(json.dumps(audit,indent=2))
checks=[]
for row in board:
 pass
for p in sorted((P/'results').glob('*/boin_benchmark.jsonl')):
 checks.append(dict(file=str(p.relative_to(R)),**S.score_boin(S.load('boin_benchmark'),S.load_preds(str(p)))))
(D/'audit/legacy_dose_denominators.json').write_text(json.dumps(checks,indent=2))
# Import oracle without its CLI, which would overwrite source artifacts.
E=mod('scorecard',R/'evaluation/datasets/drugdev_export/boin_benchmark/e2e_scorecard.py')
(D/'audit/oracle_recomputed.json').write_text(json.dumps(E.mechanistic_row(),indent=2))
print('Read-only source audit completed; dose receipt files:',len(audit))
