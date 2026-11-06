#!/usr/bin/env python3
"""Index BioMate knowledge and repair provenance without inventing training targets."""
import argparse,hashlib,json,re,sqlite3,subprocess
from collections import Counter
from pathlib import Path

def sha(data):return hashlib.sha256(data).hexdigest()
def family(text):return re.sub(r'[^a-z0-9]+','-',text.lower()).strip('-')
def tool_family(identifier):
    parts=identifier.split('/')
    return '/'.join(parts[:-1]) if len(parts)>=5 and parts[1]=='repos' else identifier

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--database',type=Path,required=True);ap.add_argument('--output',type=Path,required=True)
    args=ap.parse_args();root=Path(__file__).resolve().parents[2]
    args.output.mkdir(parents=True,exist_ok=False)
    commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
    counts=Counter();statuses=Counter()
    with sqlite3.connect(args.database.resolve().as_uri()+'?mode=ro',uri=True) as db,(args.output/'knowledge_candidates.jsonl').open('w') as stream:
        db.row_factory=sqlite3.Row
        if db.execute('PRAGMA quick_check').fetchone()[0]!='ok':raise ValueError('Knowledge database integrity failure')
        for table,query in [
            ('tools','SELECT tool_id,name,version,parameters,inputs,outputs,help_text FROM tools ORDER BY tool_id'),
            ('workflows','SELECT id,name,workflow_hash,format,real_exec_status,real_exec_produced,real_exec_err FROM workflows ORDER BY id')]:
            for raw in db.execute(query):
                item=dict(raw);identifier=str(item.get('tool_id',item.get('id')))
                name=item.get('name') or identifier
                if re.search(r'\b(ind|regulatory|nda|ich)\b',name,re.I):counts['excluded_by_scope_name']+=1;continue
                groups=[f'knowledge:{table}:'+ (tool_family(identifier) if table=='tools' else family(name))]
                if item.get('workflow_hash'):groups.append('workflow-content:'+item['workflow_hash'])
                record={'candidate_id':f'knowledge:{table}:{identifier}','source_kind':table,'source_locator':{'database_manifest':'manifest.json','table':table,'id':identifier},
                    'source_groups':groups,'source_record_sha256':sha(json.dumps(item,sort_keys=True,default=str).encode()),
                    'name':name,'suggested_tasks':['T05','T06','T07'] if table=='tools' else ['T07','T09','T18','T20'],
                    'review_status':'unreviewed','training_rights':'unreviewed','eligible_for_training':False,
                    'target_status':'no assistant target; requires a grounded task and verified trajectory'}
                if table=='tools':record['available_fields']=[k for k in ('parameters','inputs','outputs','help_text') if item.get(k)]
                else:
                    status=item.get('real_exec_status') or 'unrecorded';statuses[status]+=1
                    record['recorded_execution_status']=status
                    record['has_artifact_reference']=bool(item.get('real_exec_produced'))
                    record['has_error_reference']=bool(item.get('real_exec_err'))
                    record['execution_verified_by_this_inventory']=False
                stream.write(json.dumps(record,ensure_ascii=False)+'\n');counts[table]+=1
    # Only inspect BioMate assistant/transport history, avoiding unrelated IND code.
    paths=['frontend/server/galaxy-assistant.ts','frontend/server/llm-client.ts','backend/lib/galaxy/ai/local_inference.py']
    history=subprocess.check_output(['git','log','-150','--format=%H%x09%s','--',*paths],cwd=root,text=True)
    repairs=[]
    for line in history.splitlines():
        revision,title=line.split('\t',1)
        if re.search(r'fix|correct|repair|regress|error|timeout',title,re.I):
            repairs.append({'candidate_id':'commit:'+revision,'commit':revision,'title':title,'source_groups':['repair:'+revision],
                'review_status':'unreviewed','eligible_for_training':False,
                'required_linkage':['original failing request and context','before/after execution IDs','verifier and artifact evidence','related incident and augmentation family IDs']})
    (args.output/'repair_candidates.jsonl').write_text(''.join(json.dumps(r)+'\n' for r in repairs))
    # Hash the snapshot after read-only extraction. Callers must keep DB quiescent for a consistent export.
    h=hashlib.sha256()
    with args.database.open('rb') as f:
        for chunk in iter(lambda:f.read(8*1024*1024),b''):h.update(chunk)
    manifest={'scope':'BioMate core; IND excluded; candidate inventory only','application_commit':commit,
        'database':str(args.database),'database_sha256':h.hexdigest(),'counts':dict(counts),'workflow_status_counts':dict(statuses),
        'repair_candidates':len(repairs),'approved_training_examples':0,'frozen_test_examples':0,
        'limitations':['Name-based scope exclusion needs review of actual content.','Recorded success is not verified execution.','No private conversations exported.','Source groups must be extended with study/session/incident/augmentation ancestry before splitting.'],
        'files':{p.name:sha(p.read_bytes()) for p in args.output.iterdir() if p.is_file()}}
    (args.output/'manifest.json').write_text(json.dumps(manifest,indent=2));print(json.dumps(manifest,indent=2))

if __name__=='__main__':main()
