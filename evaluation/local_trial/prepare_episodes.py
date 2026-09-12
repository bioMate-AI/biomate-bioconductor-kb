#!/usr/bin/env python3
"""Validate reviewed episodes and split connected source families before SFT export.

Consumes reviewed JSONL, not raw logs. No teacher calls. Does not infer scientific
correctness: verifier evidence and review must already exist. See README.md.
"""
import argparse
import hashlib
import json
from pathlib import Path


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()).hexdigest()


def prepare(records):
    parent = {}
    def root(x):
        parent.setdefault(x, x)
        if parent[x] != x: parent[x] = root(parent[x])
        return parent[x]
    def join(a, b):
        a, b = root(a), root(b)
        parent[max(a,b)] = min(a,b)
    for r in records:
        if not isinstance(r.get('record_id'), str) or not r['record_id']:
            raise ValueError('Every record requires record_id')
        if not r.get('source_groups') or not all(isinstance(g, str) and g for g in r['source_groups']):
            raise ValueError('Every record requires nonempty source_groups')
        keys = ['source:'+g for g in r['source_groups']] + ['content:'+digest(r.get('messages'))]
        for key in keys: join(keys[0], key)
    pools = {'train': [], 'dev': [], 'test': []}; rejected = []; seen = set(); ids = set()
    components = {}
    for r in records:
        if r['record_id'] in ids: raise ValueError('Duplicate record_id')
        ids.add(r['record_id'])
        component = root('source:'+r['source_groups'][0])
        if r.get('split'):
            if r['split'] not in pools: raise ValueError('Invalid split')
            if component in components and components[component] != r['split']:
                raise ValueError('Source or exact-content leakage across assigned splits')
            components[component] = r['split']
    for r in records:
        reason = None; messages = r.get('messages', [])
        if r.get('task_id') not in {f'T{i:02}' for i in range(1, 29) if i not in (22, 23)}: reason = 'missing or out-of-scope BioMate task; IND excluded'
        elif r.get('training_rights') != 'approved': reason = 'unapproved rights'
        elif r.get('review_status') != 'accepted': reason = 'not reviewed'
        elif not r.get('verifier_evidence') or not all(v.get('passed') is True and v.get('evidence_ref') for v in r['verifier_evidence']): reason = 'missing passing verifier evidence'
        elif not r.get('prompt_sha256') or not r.get('application_commit'): reason = 'missing provenance'
        elif not messages or messages[-1].get('role') != 'assistant': reason = 'no final assistant target'
        elif r.get('context_complete') is not True: reason = 'incomplete context'
        if reason: rejected.append({'record_id':r['record_id'],'reason':reason}); continue
        h = digest(messages)
        if h in seen: rejected.append({'record_id':r['record_id'],'reason':'exact duplicate'}); continue
        seen.add(h)
        component = root('source:'+r['source_groups'][0])
        # Stable family allocation; frozen split assignments should be retained in future batches.
        bucket = int(digest(component)[:8],16) % 100
        split = components.get(component, 'train' if bucket < 80 else 'dev' if bucket < 90 else 'test')
        components[component] = split
        pools[split].append({**r, 'split':split, 'component':component, 'messages_sha256':h})
    return pools, rejected


def main():
    ap=argparse.ArgumentParser();ap.add_argument('input',type=Path);ap.add_argument('output',type=Path);args=ap.parse_args()
    records=[json.loads(line) for line in args.input.read_text().splitlines() if line.strip()]
    pools,rejected=prepare(records)
    args.output.mkdir(parents=True,exist_ok=False)
    for split,rows in pools.items():
        (args.output/(split+'.jsonl')).write_text(''.join(json.dumps(r,ensure_ascii=False)+'\n' for r in rows))
    (args.output/'rejected.json').write_text(json.dumps(rejected,indent=2))
    manifest={'input_sha256':hashlib.sha256(args.input.read_bytes()).hexdigest(),'counts':{k:len(v) for k,v in pools.items()},'rejected':len(rejected),'scope':'review/provenance and exact-duplicate/source-group gates; semantic leakage and scientific correctness require independent review'}
    (args.output/'manifest.json').write_text(json.dumps(manifest,indent=2));print(json.dumps(manifest,indent=2))
if __name__=='__main__':main()
