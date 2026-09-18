#!/usr/bin/env python3
"""Back up explicitly scoped BioMate work; excludes credentials and unrelated workspace edits."""
import argparse,json,shutil,subprocess,tempfile
from pathlib import Path
from checkpoint_store import seal,publish

root=Path(__file__).resolve().parents[2]
changed=['frontend/server/index.ts','frontend/package.json','frontend/package-lock.json','frontend/server/galaxy-assistant.ts','frontend/server/gemini-flash.ts','frontend/server/llm-client.ts','frontend/server/routes.ts','frontend/server/context-compressor.ts','frontend/server/iterative-workflow-generator.ts','frontend/server/workflow-prerequisites-validator.ts','frontend/server/galaxy-assistant-prototype.ts','frontend/server/model-test-harness.ts','backend/lib/galaxy/ai/config.py','backend/lib/galaxy/ai/llm_client.py','backend/lib/galaxy/ai/llm_client_fallback_implementation.py','backend/lib/galaxy/webapps/galaxy/api/llm_internal.py','evaluation/training_data_extractor.py']
new=['frontend/server/local-response-prompt.ts','frontend/server/local-intent-prompt.ts','frontend/migrations/0000_base_workflow_tables.sql','backend/lib/galaxy/ai/local_knowledge_query.py','backend/lib/galaxy/webapps/galaxy/api/knowledge_query.py','backend/tests/test_local_knowledge_query.py','frontend/server/local-llm.ts','frontend/server/__tests__/local-llm.test.ts','frontend/server/galaxy-assistant-local.test.ts','frontend/server/galaxy-assistant-local-live.test.ts','backend/lib/galaxy/ai/local_inference.py','backend/tests/test_local_inference.py']

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--receipt',type=Path);ap.add_argument('--local-bundle',type=Path,help='Seal a new local directory without AWS access');a=ap.parse_args()
    if not a.receipt and not a.local_bundle:ap.error('Specify --receipt or --local-bundle')
    if a.local_bundle and a.local_bundle.exists():ap.error('Local bundle destination already exists')
    base=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
    with tempfile.TemporaryDirectory(prefix='biomate-workspace-') as d:
        stage=Path(d);files=[root/p for p in new]
        for folder in ['infra/local-trial','evaluation/local_trial','docs/20260912_onprem_llm']:
            files += [p for p in (root/folder).rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.suffix in {'.py','.sh','.md','.json','.jsonl','.txt','.example','.service','.timer','.cjs','.xml','.conf','.sql'}]
        for src in files:
            if src.is_symlink():raise ValueError('Refusing symlink in workspace backup')
            out=stage/src.relative_to(root);out.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,out)
        (stage/'implementation.patch').write_bytes(subprocess.check_output(['git','diff','--binary',base,'--',*changed],cwd=root))
        if subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()!=base:raise ValueError('Git base changed during backup; retry')
        seal(stage,{'kind':'artifact_bundle','scope':'BioMate core implementation and audit; IND implementation excluded','git_base':base,'contains_trained_model':False})
        if a.local_bundle:
            shutil.copytree(stage,a.local_bundle)
            print(json.dumps({'local_bundle':str(a.local_bundle),'s3_published':False}))
            return
        import boto3
        receipt=publish(stage,'biomate-models-399683337364','biomate-core-local-trial/20260912/workspace',boto3.client('s3'))
    a.receipt.parent.mkdir(parents=True,exist_ok=True);a.receipt.write_text(json.dumps(receipt,indent=2));print(json.dumps(receipt,indent=2))
if __name__=='__main__':main()
