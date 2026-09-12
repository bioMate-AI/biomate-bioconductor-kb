"""Explicit bounded real-data integration check, never full training coverage."""
from pathlib import Path
import json,hashlib
import numpy as np
import pandas as pd
import torch
from shared_multimodal_trainer import SharedMultimodalEncoder,reconstruction
from knowledge_tasks import load_knowledge,KnowledgeTasks

root=Path(__file__).parent
out=root/'real_joint_preflight';out.mkdir(exist_ok=True)
torch.manual_seed(19);torch.set_num_threads(2)
paired=json.loads((root/'paired_preflight_tokens/manifest.json').read_text())
vocab=list(paired['vocab']);prepared=[]
for kind,mid in [('ribosome',3),('proteome',4),('presentation',5)]:
    path=root/'real_omics'/f'{kind}_prepared'
    schema=json.loads((path/'schema.json').read_text())
    features=[f'{kind}:{schema["feature_namespace"]}:{g}' for g in schema['features']]
    known=set(vocab);vocab.extend(g for g in features if g not in known)
    prepared.append((path,schema,features,mid))
lookup={g:i for i,g in enumerate(vocab)}
batches=[]
seen=set()
for entry in paired['batches']:
    if entry['source_id'] in seen:continue
    seen.add(entry['source_id'])
    with np.load(entry['path'],allow_pickle=False) as d:
        batches.append((entry['source_id'],{k:torch.from_numpy(d[k]) for k in ['ids','values','valid','modality']}))
for path,schema,features,mid in prepared:
    with np.load(path/'values.npz',allow_pickle=False) as d:
        values=d['values'][:4,:128];valid=d['observed'][:4,:128]
        keep=valid.any(1);values=values[keep];valid=valid[keep]
        ids=np.broadcast_to(np.array([lookup[g] for g in features[:128]]),values.shape).copy()
        batches.append((schema['source_uri'],{'ids':torch.tensor(ids),'values':torch.tensor(values),
            'valid':torch.tensor(valid),'modality':torch.full(values.shape,mid,dtype=torch.long)}))
knowledge=root/'real_joint_preflight/knowledge_fixture';knowledge.mkdir(exist_ok=True)
full=Path('/Users/kky/biomate-review/docs/20260912_knowledge_vnext/current_prepared')
source_hashes={}
for p in sorted(full.glob('*.parquet')):
    d=pd.read_parquet(p);sample=d.sample(min(32,len(d)),random_state=19)
    sample.to_parquet(knowledge/p.name,index=False)
    source_hashes[p.name]=hashlib.sha256(p.read_bytes()).hexdigest()
facts=load_knowledge(knowledge)
model=SharedMultimodalEncoder(len(vocab),dim=32,layers=2,heads=4,n_modalities=6)
gene_map={g[4:]:i for i,g in enumerate(vocab) if g.startswith('RNA:')}
km=KnowledgeTasks(facts,model.genes,gene_to_index=gene_map)
container=torch.nn.ModuleDict({'encoder':model,'knowledge':km})
opt=torch.optim.AdamW(container.parameters(),lr=1e-4)
events=[];assays=set()
for source,batch in batches:
    opt.zero_grad();loss,z,terms=reconstruction(model,batch)
    kl,parts,counters=km(facts,heldout_groups=set())
    total=loss+.1*kl
    if not torch.isfinite(total):raise ValueError('Nonfinite real-data preflight')
    total.backward()
    if model.genes.weight.grad is None or not torch.isfinite(model.genes.weight.grad).all():raise ValueError('Invalid shared gradient')
    torch.nn.utils.clip_grad_norm_(container.parameters(),1.,error_if_nonfinite=True);opt.step();km.record_optimizer_step(counters)
    assays.update(terms)
    events.append({'source':source,'rows':len(batch['ids']),'observed_input_tokens':int(batch['valid'].sum()),
        'loss':float(total.detach()),'assay_losses':{str(k):float(v.detach()) for k,v in terms.items()},'knowledge':parts,'knowledge_exposure':counters})
assert assays==set(range(6)),assays
report={'status':'real_joint_integration_preflight_pass','full_training':False,'optimizer_steps':len(events),
    'modality_ids_with_loss':sorted(assays),'knowledge_optimizer_exposure':km.exposure,'events':events,
    'source_artifact_sha256':source_hashes,'limits':['Explicit preflight cap: first paired feature window, four dense samples and 128 dense features',
        'Knowledge sampled 32 rows per artifact solely for integration testing','No held-out scientific evaluation',
        'No H1-H4 or text biological supervision claim; their interfaces have separate implementation tests']}
(out/'result.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k not in ['events','source_artifact_sha256']},indent=2))
