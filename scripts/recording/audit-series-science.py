#!/usr/bin/env python3
"""Check the worked example's displayed claims against preserved run artifacts.

Passing checks establish faithful presentation of this run, not model validity.
"""
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];QA=ROOT/'docs/qa/20261003-tutorial-release'
def load(p):return json.loads(p.read_text())
def main():
    story=load(ROOT/'reference/claude_design/tutorials/review-pilot/storyboard.json');tox=load(QA/'toxicity_report.json');qc=load(QA/'qc_metrics.json');record=load(QA/'reproducibility-record.json');checks=[]
    def check(name,passed,evidence):checks.append({'claim':name,'passed':bool(passed),'evidence':evidence})
    check('Three compound inputs in preserved order', [p['smiles'] for p in tox['per_compound_admet_ai']]==['CC(=O)Oc1ccccc1C(=O)O','CN1C=NC2=C1C(=O)N(C(=O)N2C)C','CC(C)Cc1ccc(C(C)C(=O)O)cc1'],'toxicity_report.json:per_compound_admet_ai[*].smiles')
    for lang in ['en','zh']:
        values=[float(x.split('|')[1]) for x in story['scenes'][5][lang]['items']]
        check(f'{lang}: all three displayed hERG scores',[p['hERG_prob'] for p in tox['per_compound_admet_ai']]==values,'toxicity_report.json:per_compound_admet_ai[*].hERG_prob')
        panel=float(story['scenes'][7][lang]['items'][0].split('|')[1]);threshold=float(story['scenes'][7][lang]['items'][1].split('|')[1])
        check(f'{lang}: DILI display matches QC and rounded maximum',panel==qc['dili_probability']==round(max(p['DILI_prob'] for p in tox['per_compound_admet_ai']),3),'qc_metrics.json:dili_probability; toxicity_report.json:per_compound_admet_ai[*].DILI_prob')
        check(f'{lang}: failed DILI check and configured threshold',threshold==qc['dili_probability_threshold'] and panel>threshold and qc['admet_dili_probability_passes'] is False,'qc_metrics.json:dili_probability_threshold/admet_dili_probability_passes')
    check('DILI maximum belongs to second compound',max(range(3),key=lambda i:tox['per_compound_admet_ai'][i]['DILI_prob'])==1,'toxicity_report.json:per_compound_admet_ai')
    check('Six output records',len(record['outputs'])==6,'reproducibility-record.json:outputs')
    check('Default input and tool bindings are empty',record['inputBindings']==[] and record['parameters']['toolParameters']=={},'reproducibility-record.json:inputBindings/parameters.toolParameters')
    check('Default output checksums absent',all(o.get('sha256') is None for o in record['outputs']),'reproducibility-record.json:outputs[*].sha256')
    result={'scope':'Presentation fidelity for this preserved example, not predictive validation','checks':checks,'allPassed':all(x['passed'] for x in checks),'artifactsSha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [QA/'toxicity_report.json',QA/'qc_metrics.json',QA/'reproducibility-record.json']},'releaseApproved':False}
    (QA/'science-claim-audit.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({'checks':len(checks),'passed':sum(x['passed'] for x in checks)}))
    if not result['allPassed']:raise SystemExit(1)
if __name__=='__main__':main()
