"""Executable joint current-version stream; pending sources prevent completion.

Manifest: vocab:[namespaced IDs], batches:[{path,study_id,split,source_id}],
knowledge_edges:path(optional), source_ledger:[{source_id,status}]. Batch NPZ
ids/values/valid/modality tensors follow shared_multimodal_trainer. This runner
executes available reconstruction and knowledge; measured head adapters remain
explicit scheduled extensions, not inferred labels.
"""
import argparse,json,random,hashlib
from pathlib import Path
import numpy as np
import torch
from shared_multimodal_trainer import SharedMultimodalEncoder,reconstruction,knowledge_regularizer,CanonicalAdapter
from resumable_checkpoint import manifest_hash,save_checkpoint,load_checkpoint

def stream_records(manifest,root,split,window,batch_rows):
 lookup={g:i for i,g in enumerate(manifest['vocab'])};pad=len(lookup)
 for entry in manifest.get('batches',[]):
  if entry['split']!=split:continue
  with np.load(root/entry['path'],allow_pickle=False) as z:
   yield entry['source_id'],{k:torch.from_numpy(z[k]) for k in ('ids','values','valid','modality')}
 for entry in manifest.get('dense_sources',[]):
  schema=json.loads((root/entry['schema_path']).read_text());features=schema['features'];mapping=np.array([lookup[g] for g in features],dtype=np.int64)
  with np.load(root/entry['path'],allow_pickle=False) as z:
   values=z['values'];observed=z['observed']
   if values.shape!=observed.shape or observed.dtype!=bool or values.shape!=(len(schema['study_ids']),len(features)):raise ValueError('Dense assay/schema mismatch')
   if not np.isfinite(values[observed]).all():raise ValueError('Nonfinite observed dense assay')
   selected=[i for i,study in enumerate(schema['study_ids']) if entry['split_by_study'][study]==split]
   for lo in range(0,len(selected),batch_rows):
    rows=selected[lo:lo+batch_rows]
    for start in range(0,len(features),window):
     stop=min(start+window,len(features));valid=observed[rows,start:stop];nonempty=valid.any(1)
     if not nonempty.any():continue
     v=values[rows,start:stop][nonempty];valid=valid[nonempty];ids=np.broadcast_to(mapping[start:stop],v.shape).copy();mod=np.full(v.shape,entry['modality'],dtype=np.int64)
     yield entry['source_id'],{'ids':torch.from_numpy(ids),'values':torch.from_numpy(v.astype(np.float32)),'valid':torch.from_numpy(valid.copy()),'modality':torch.from_numpy(mod)}

def training_records(manifest,root,split,window,batch_rows):
 for source,batch in stream_records(manifest,root,split,window,batch_rows):yield source,batch,None
 for entry in manifest.get('measured_sources',[]):
  if entry['split']!=split:continue
  with np.load(root/entry['path'],allow_pickle=False) as z:
   tensors={k:torch.from_numpy(z[k]) for k in z.files}
  # Measured adapters own explicit per-batch feature/pairing schemas, no inferred labels.
  window=entry.get('token_window')
  if window is None:yield entry['source_id'],tensors,entry
  else:
   if type(window) is not int or window<=0:raise ValueError('Measured token window must be positive integer')
   length=tensors['ids'].shape[1]
   for start in range(0,length,window):
    stop=min(start+window,length);part=dict(tensors)
    for field in ('ids','values','valid','modality'):part[field]=tensors[field][:,start:stop]
    active=False
    for objective in entry.get('window_label_objectives',[]):
     fields=entry['labels'][objective];key=fields['observed'];mask=tensors[key]
     if mask.ndim!=2 or mask.shape[1]!=length:raise ValueError('Measured readout window requires matching all-gene order')
     selected=torch.zeros_like(mask);selected[:,start:stop]=mask[:,start:stop];part[key]=selected;active=active or bool(selected.any())
    if not entry.get('window_label_objectives') or active:yield entry['source_id'],part,entry

def measured_step(adapter,batch,entry):
 labels={}
 for name,fields in entry['labels'].items():
  labels[name]={field:batch[key] for field,key in fields.items()}
 context={field:batch[key] for field,key in entry.get('context',{}).items()}
 return adapter.measured_batch(batch,batch[entry.get('perturbation_key','perturbation')],labels,entry['objectives'],**context)

def text_specs(manifest,root):
 result=[]
 for entry in manifest.get('text_sources',[]):
  path=root/entry['manifest_path'];prepared=json.loads(path.read_text())
  revision=prepared['identity']['revision']
  if prepared['identity'].get('model')!='sentence-transformers/all-MiniLM-L6-v2':raise ValueError('Prepared text encoder identity must match approved frozen MiniLM model')
  for field in ('mapping_sha256','tokenizer_sha256'):
   digest=prepared['identity'].get(field,'')
   if len(digest)!=64 or any(c not in '0123456789abcdef' for c in digest):raise ValueError('Text preparation requires mapping/tokenizer SHA256 identities')
  if len(revision)!=40 or any(c not in '0123456789abcdef' for c in revision):raise ValueError('Frozen text encoder must be immutable revision')
  if not prepared['complete']:raise ValueError('Text prepared source incomplete')
  if 'heldout_article_ids' not in entry:raise ValueError('Explicit text held-out article IDs required')
  dimensions={c['dimension'] for c in prepared['chunks']}
  if dimensions!={384}:raise ValueError('Prepared frozen MiniLM encoder vectors must be 384dim')
  result.append((entry,path,prepared))
 return result

def content_bindings(manifest,root):
 paths=set()
 for entry in manifest.get('batches',[])+manifest.get('measured_sources',[]):paths.add((root/entry['path']).resolve())
 for entry in manifest.get('dense_sources',[]):
  paths.add((root/entry['path']).resolve());paths.add((root/entry['schema_path']).resolve())
 if manifest.get('knowledge_edges'):paths.add((root/manifest['knowledge_edges']).resolve())
 if manifest.get('knowledge'):
  k=manifest['knowledge'];paths.update((root/k['prepared_dir']).resolve().glob('*.parquet'))
  if k.get('mapkg'):paths.add((root/k['mapkg']).resolve())
 for entry,path,prepared in text_specs(manifest,root):
  paths.add(path.resolve());paths.update((path.parent/c['path']).resolve() for c in prepared['chunks'])
 result={}
 for path in sorted(paths):
  digest=hashlib.sha256()
  with path.open('rb') as f:
   for chunk in iter(lambda:f.read(8*1024*1024),b''):digest.update(chunk)
  result[str(path)]=digest.hexdigest()
 return result

def main():
 p=argparse.ArgumentParser();p.add_argument('--manifest',required=True);p.add_argument('--out',required=True);p.add_argument('--epochs',type=int,default=10);p.add_argument('--dim',type=int,default=128);p.add_argument('--layers',type=int,default=4);p.add_argument('--heads',type=int,default=4);p.add_argument('--device',default='cpu');p.add_argument('--seed',type=int,default=0);p.add_argument('--lr',type=float,default=3e-4);p.add_argument('--knowledge-weight',type=float,default=.1);p.add_argument('--resume',action='store_true');p.add_argument('--window',type=int,default=512);p.add_argument('--batch-rows',type=int,default=16);p.add_argument('--debug-steps',type=int,default=None);a=p.parse_args()
 if a.knowledge_weight<=0 or not np.isfinite(a.knowledge_weight):raise ValueError('Knowledge objective weight must be finite positive; do not report zero-weight optimization')
 root=Path(a.manifest).parent;m=json.loads(Path(a.manifest).read_text());vocab=m['vocab']
 if len(vocab)!=len(set(vocab)) or not vocab:raise ValueError('Unique stable vocab required')
 if not m.get('source_ledger'):raise ValueError('Mandatory complete source ledger required')
 ledger_ids={s['source_id'] for s in m['source_ledger']}
 if len(ledger_ids)!=len(m['source_ledger']):raise ValueError('Duplicate source ledger identifiers')
 for entry in m.get('batches',[])+m.get('dense_sources',[])+m.get('measured_sources',[]):
  if entry['source_id'] not in ledger_ids:raise ValueError('Training source absent from mandatory ledger')
 study={};study_units={}
 for b in m.get('batches',[])+m.get('measured_sources',[]):
  if b['split'] not in ('train','validation','test') or not b['study_id']:raise ValueError('Explicit study/split required')
  unit=b.get('split_unit','study')
  if unit not in ('study','donor'):raise ValueError('Unknown split unit')
  if b['study_id'] in study_units and study_units[b['study_id']]!=unit:raise ValueError('Study mixed split units')
  study_units[b['study_id']]=unit
  key=b['study_id'] if unit=='study' else (b['study_id'],b['donor_id'])
  if key in study and study[key]!=b['split']:raise ValueError('Declared study/donor split leakage')
  study[key]=b['split']
 for entry in m.get('dense_sources',[]):
  for st,split in entry['split_by_study'].items():
   if study_units.get(st,'study')!='study':raise ValueError('Dense source conflicts with within-study donor partition')
   if split not in ('train','validation','test') or (st in study and study[st]!=split):raise ValueError('Dense study split/leakage violation')
   study[st]=split
 if not m.get('batches') and not m.get('dense_sources') and not m.get('measured_sources'):raise ValueError('No eligible ready training sources')
 random.seed(a.seed);np.random.seed(a.seed);torch.manual_seed(a.seed);torch.use_deterministic_algorithms(True)
 modality_schema=m.get('modality_schema')
 modality_ids=([int(k) for k in modality_schema] if isinstance(modality_schema,dict) else [int(row['id']) for row in modality_schema]) if modality_schema is not None else list(range(5))
 if sorted(modality_ids)!=list(range(len(modality_ids))):raise ValueError('Modality schema IDs must be unique contiguous from zero')
 model=SharedMultimodalEncoder(len(vocab),a.dim,a.layers,a.heads,n_modalities=len(modality_ids)).to(a.device);km=None;facts=None;knowledge_filtered=0
 if m.get('knowledge'):
  from knowledge_tasks import load_knowledge,KnowledgeTasks
  k=m['knowledge']
  for symbol,index in k['gene_to_index'].items():
   expected=k.get('canonical_gene_mapping',{}).get(symbol,symbol)
   if type(index) is not int or index<0 or index>=len(vocab) or vocab[index]!='RNA:'+expected:raise ValueError('Knowledge shared gene map must match explicit RNA canonical token; wrong modality/padding forbidden')
  facts=load_knowledge(root/k['prepared_dir'],mapkg=(root/k['mapkg'] if k.get('mapkg') else None));facts=facts.loc[~facts['split_group'].isin(set(k.get('heldout_groups',[])))].reset_index(drop=True)
  before_provenance=len(facts)
  facts=facts.loc[((~facts['task'].isin(['sign','prior']))|facts['value_observed'])&(facts['confidence']>0)].reset_index(drop=True)
  knowledge_filtered=before_provenance-len(facts)
  if facts.empty:raise ValueError('No observed train knowledge facts after held-out/provenance filtering')
  km=KnowledgeTasks(facts,model.genes,gene_to_index=k['gene_to_index']).to(a.device)
 adapter=None
 if m.get('measured_sources'):
  if not m.get('head_config'):raise ValueError('Measured sources require explicit canonical head_config')
  adapter=CanonicalAdapter(model,m['head_config']).to(a.device)
 text_adapter=None;text_entries=text_specs(m,root)
 if text_entries:
  from prepared_text_tasks import iter_prepared_text,prepared_text_loss
  from text_knowledge_tasks import FrozenTextAlignment
  text_adapter=FrozenTextAlignment(model.genes,384).to(a.device)
 container=torch.nn.ModuleDict({'encoder':model,**({'text_alignment':text_adapter} if text_adapter is not None else {}),**({'knowledge':km} if km is not None else {}),**({'canonical_heads':adapter.heads} if adapter is not None else {})})
 opt=torch.optim.AdamW(container.parameters(),lr=a.lr);out=Path(a.out);out.mkdir(parents=True,exist_ok=True)
 cfg={k:v for k,v in vars(a).items() if k not in ('out','manifest','resume','debug_steps')};identity={'source_manifest_hash':manifest_hash({'manifest':m,'content_sha256':content_bindings(m,root)}),'schema_hash':manifest_hash(vocab),'config_hash':manifest_hash(cfg)}
 ep0=0;bi0=0;step=0;knowledge_offset=0;text_cursor={'source':0,'next_chunk':0,'next_row':0};exposure={};objective_exposure={}
 if a.resume:
  state=load_checkpoint(out/'checkpoint.pt',model=container,optimizer=opt,identity=identity);ep0=state['epoch'];bi0=state['next_batch'];step=state['sampler_state']['steps'];knowledge_offset=state['sampler_state'].get('knowledge_offset',0);exposure=state['sampler_state'].get('source_exposure',{});objective_exposure=state['sampler_state'].get('objective_exposure',{})
  if km is not None:km.exposure=state['sampler_state'].get('knowledge_exposure',{})
  text_cursor=state['sampler_state'].get('text_cursor',{'source':0,'next_chunk':0,'next_row':0})
  if text_adapter is not None:
   from collections import Counter
   text_adapter.exposure=Counter(state['sampler_state'].get('text_exposure',{}))
 edges=None
 if m.get('knowledge_edges'):edges=torch.as_tensor(np.load(root/m['knowledge_edges'],allow_pickle=False),dtype=torch.float32,device=a.device)
 with (out/'training.jsonl').open('a') as log:
  for epoch in range(ep0,a.epochs):
   next_bi=bi0 if epoch==ep0 else 0
   for bi,(source_id,batch,measured) in enumerate(training_records(m,root,'train',a.window,a.batch_rows)):
    if epoch==ep0 and bi<bi0:continue
    next_bi=bi+1
    batch={k:v.to(a.device) for k,v in batch.items()}
    container.train();opt.zero_grad()
    if measured is None:loss,_,terms=reconstruction(model,batch)
    else:loss,terms,_=measured_step(adapter,batch,measured)
    knowledge=knowledge_regularizer(model,edges) if edges is not None else loss.new_zeros(())
    counters=None
    if km is not None:
     # Cycle through every fact; final remaining facts consumed below this epoch.
     klo=(bi*1024)%len(facts);knowledge,kparts,counters=km(facts.iloc[klo:min(klo+1024,len(facts))],heldout_groups=set(m['knowledge'].get('heldout_groups',[])))
    total=loss+a.knowledge_weight*knowledge
    if not torch.isfinite(total):raise ValueError('Nonfinite joint loss')
    total.backward();torch.nn.utils.clip_grad_norm_(container.parameters(),1.,error_if_nonfinite=True);opt.step();step+=1
    exposure[source_id]=exposure.get(source_id,0)+int(batch['valid'].sum())
    if measured is not None:
     for name in measured['objectives']:
      fields=measured['labels'][name];observed=batch[fields['observed']];count=int(observed.sum())
      if 'censored' in fields:count+=int(batch[fields['censored']].sum())
      objective_exposure[name]=objective_exposure.get(name,0)+count
    if counters is not None:km.record_optimizer_step(counters)
    log.write(json.dumps({'step':step,'source_id':source_id,'epoch':epoch,'batch':bi,'objective_kind':('measured' if measured is not None else 'reconstruction'),'loss':float(loss.detach()),'assays':{str(k):float(v.detach()) for k,v in terms.items()},'knowledge':float(knowledge.detach())})+'\n');log.flush()
    save_checkpoint(out/'checkpoint.pt',model=container,optimizer=opt,identity=identity,epoch=epoch,next_batch=bi+1,sampler_state={'steps':step,'text_cursor':{'source':0,'next_chunk':0,'next_row':0},'text_exposure':(dict(text_adapter.exposure) if text_adapter is not None else {}),'knowledge_offset':0,'source_exposure':exposure,'objective_exposure':objective_exposure,'knowledge_exposure':(km.exposure if km is not None else {})})
    if a.debug_steps is not None and step>=a.debug_steps:break
   if a.debug_steps is not None and step>=a.debug_steps:break
   if km is not None:
    for offset in range(knowledge_offset if epoch==ep0 else 0,len(facts),1024):
     opt.zero_grad();kl,kparts,counters=km(facts.iloc[offset:offset+1024],heldout_groups=set(m['knowledge'].get('heldout_groups',[])))
     if not torch.isfinite(kl):raise ValueError('Nonfinite knowledge task')
     (a.knowledge_weight*kl).backward();torch.nn.utils.clip_grad_norm_(container.parameters(),1.,error_if_nonfinite=True);opt.step();km.record_optimizer_step(counters);step+=1
     save_checkpoint(out/'checkpoint.pt',model=container,optimizer=opt,identity=identity,epoch=epoch,next_batch=next_bi,sampler_state={'steps':step,'text_cursor':{'source':0,'next_chunk':0,'next_row':0},'text_exposure':(dict(text_adapter.exposure) if text_adapter is not None else {}),'knowledge_offset':offset+1024,'source_exposure':exposure,'objective_exposure':objective_exposure,'knowledge_exposure':km.exposure})
     if a.debug_steps is not None and step>=a.debug_steps:break
   if a.debug_steps is not None and step>=a.debug_steps:break
   text_stopped=False
   for ti,(entry,path,prepared) in enumerate(text_entries):
    if epoch==ep0 and ti<text_cursor['source']:continue
    chunk=text_cursor['next_chunk'] if epoch==ep0 and ti==text_cursor['source'] else 0
    row=text_cursor['next_row'] if epoch==ep0 and ti==text_cursor['source'] else 0
    for items,vectors,cursor in iter_prepared_text(path,start_chunk=chunk,start_row=row,batch_rows=entry.get('batch_rows',64),heldout_article_ids=set(entry['heldout_article_ids'])):
     if items:
      for item in items:
       if any(index<0 or index>=len(vocab) or not vocab[index].startswith('RNA:') for index in item['gene_indices']):raise ValueError('Prepared text must map to valid shared RNA token indices')
      opt.zero_grad();tl,counters=prepared_text_loss(text_adapter,items,vectors,heldout_article_ids=set(entry['heldout_article_ids']))
      if not torch.isfinite(tl):raise ValueError('Nonfinite prepared text loss')
      (a.knowledge_weight*tl).backward();torch.nn.utils.clip_grad_norm_(container.parameters(),1.,error_if_nonfinite=True);opt.step();text_adapter.record_optimizer_step(counters);step+=1
      log.write(json.dumps({'step':step,'objective_kind':'frozen_text_alignment','source_id':entry['source_id'],'loss':float(tl.detach()),'windows':len(items)})+'\n');log.flush()
     saved_cursor={'source':ti,'next_chunk':cursor['next_chunk'],'next_row':cursor['next_row']}
     save_checkpoint(out/'checkpoint.pt',model=container,optimizer=opt,identity=identity,epoch=epoch,next_batch=next_bi,sampler_state={'steps':step,'text_cursor':saved_cursor,'text_exposure':dict(text_adapter.exposure),'knowledge_offset':(len(facts) if facts is not None else 0),'source_exposure':exposure,'objective_exposure':objective_exposure,'knowledge_exposure':(km.exposure if km is not None else {})})
     if a.debug_steps is not None and step>=a.debug_steps:text_stopped=True;break
    if text_stopped:break
   if text_stopped:break
   save_checkpoint(out/'checkpoint.pt',model=container,optimizer=opt,identity=identity,epoch=epoch+1,next_batch=0,sampler_state={'steps':step,'text_cursor':{'source':0,'next_chunk':0,'next_row':0},'text_exposure':(dict(text_adapter.exposure) if text_adapter is not None else {}),'knowledge_offset':0,'source_exposure':exposure,'objective_exposure':objective_exposure,'knowledge_exposure':(km.exposure if km is not None else {})})
 # Stable held-out study validation without mutating training RNG state.
 validation=[]
 with torch.random.fork_rng(devices=([torch.device(a.device).index or 0] if a.device.startswith('cuda') else [])):
  torch.manual_seed(a.seed+731);container.eval()
  with torch.no_grad():
   for source_id,batch,measured in training_records(m,root,'validation',a.window,a.batch_rows):
    batch={k:v.to(a.device) for k,v in batch.items()}
    if measured is None:vl,_,terms=reconstruction(model,batch)
    else:vl,terms,_=measured_step(adapter,batch,measured)
    validation.append({'source_id':source_id,'loss':float(vl),'assays':{str(k):float(v) for k,v in terms.items()}})
 (out/'validation.json').write_text(json.dumps({'rows':validation,'split':'declared study or explicit within-study donor validation; test untouched'},indent=2))
 pending=[s['source_id'] for s in m['source_ledger'] if s['status']!='integrated' or (exposure.get(s['source_id'],0)==0 and (km is None or km.exposure.get(s['source_id'],0)==0) and (text_adapter is None or text_adapter.exposure.get(s['source_id'],0)==0))]
 (out/'status.json').write_text(json.dumps({'status':'ready_sources_trained_pending_integration' if pending else 'ready_sources_trained_pending_evaluation','steps':step,'knowledge_unobserved_or_zero_confidence_excluded':knowledge_filtered,'source_exposure':exposure,'objective_exposure':objective_exposure,'text_exposure':(dict(text_adapter.exposure) if text_adapter is not None else {}),'debug_only':a.debug_steps is not None,'knowledge_exposure':(km.exposure if km is not None else {}),'pending_sources':pending,'scope':'joint observed reconstruction + structural knowledge + explicitly scheduled measured objectives; only exposure documents which heads trained'},indent=2))
if __name__=='__main__':main()
