import json,re,hashlib
from pathlib import Path
root=Path(__file__).resolve().parent
manifest=json.loads((root/'acquisition_manifest.json').read_text())
for x in manifest:
 if x['status']=='downloaded':
  assert hashlib.sha256((root/'raw'/x['file']).read_bytes()).hexdigest()==x['sha256']
report={'training_eligible':False,'label_audit':'pending','geo':{},'trials':{},'downloaded_bytes':sum(x.get('bytes',0) for x in manifest),'failed_downloads':sum(x['status']=='failed' for x in manifest)}
for p in (root/'raw').glob('*.soft.txt'):
 samples=[];keys=set();in_table=False;table_rows=0
 for line in p.open():
  if line.startswith('^SAMPLE = '):samples.append(line.strip().split(' = ',1)[1])
  if line.startswith('!Sample_characteristics_ch1 = '):keys.add(line.split(' = ',1)[1].split(':',1)[0].strip())
  if line.startswith('!sample_table_end'):in_table=False
  elif line.startswith('!sample_table_begin'):in_table=True
  elif in_table:table_rows+=1
 report['geo'][p.stem]={'unique_sample_records':len(set(samples)),'patient_count':'not yet reconciled','characteristic_keys':sorted(keys),'sample_table_lines_including_headers':table_rows}
all_ids=set()
for disease in ['rheumatoid_arthritis','asthma','lupus']:
 studies={}
 for p in (root/'raw').glob(disease+'_trials_*.json'):
  for s in json.loads(p.read_text()).get('studies',[]):studies[s['protocolSection']['identificationModule']['nctId']]=s
 all_ids.update(studies)
 report['trials'][disease]={'candidate_studies':len(studies),'with_results_section':sum(bool(s.get('resultsSection')) for s in studies.values()),'with_outcome_module':sum(bool(s.get('resultsSection',{}).get('outcomeMeasuresModule')) for s in studies.values()),'with_adverse_event_module':sum(bool(s.get('resultsSection',{}).get('adverseEventsModule')) for s in studies.values()),'relevance':'broad query; manual endpoint adjudication pending','individual_patient_records':0}
report['unique_trials_across_queries']=len(all_ids)
(root/'AUDIT.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
