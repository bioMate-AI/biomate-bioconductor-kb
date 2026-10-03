"""Grounded workflow decision diagnostic; execution is a separate required gate.

Run once with the original --base and once with CPT --base plus --adapter.
Both arms use the same --facts. Output decisions can drive BioMate execution;
contract_pass never means that a workflow has actually run.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import time
from backend_bakeoff import ADMET_PATH, TASKS, prompt_for, resolved_for


def check_decision(raw, task, facts):
    errors = []
    try:
        decision = json.loads(raw.strip())
        if not isinstance(decision, dict):
            raise ValueError('not an object')
    except (ValueError, TypeError):
        return {}, ['output is not a single JSON object']
    if decision.get('nextflow_path') != ADMET_PATH:
        errors.append('wrong workflow')
    params = decision.get('params')
    if not isinstance(params, dict):
        return decision, errors + ['params is not an object']
    if set(params) - {'smiles_list', 'ADMET_model_type', 'admet_shard_size'}:
        errors.append('unknown parameter')
    try:
        smiles = json.loads(params['smiles_list'])
        expected = [row['smiles'] for row in resolved_for(task, facts)]
        if not isinstance(smiles, list) or Counter(smiles) != Counter(expected):
            errors.append('compound evidence mismatch')
    except (KeyError, ValueError, TypeError):
        errors.append('smiles_list is not a JSON-array string')
    model = params.get('ADMET_model_type', 'MPNN')
    if model not in ('MPNN', 'CNN', 'Morgan'):
        errors.append('invalid ADMET model')
    if task['id'] == 'admet_imatinib_mpnn' and model != 'MPNN':
        errors.append('requested MPNN not selected')
    shard = params.get('admet_shard_size', 1)
    if type(shard) is not int or shard < 1:
        errors.append('invalid shard size')
    return decision, errors


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--base', required=True)
    ap.add_argument('--adapter')
    ap.add_argument('--facts', required=True)
    ap.add_argument('--out', required=True)
    args = ap.parse_args()
    facts_bytes = Path(args.facts).read_bytes()
    facts = json.loads(facts_bytes)
    prompts = [prompt_for(task, facts) for task in TASKS]
    import torch
    from transformers import AutoTokenizer
    from model_loading import load_text_model
    model = load_text_model(args.base, torch_dtype=torch.bfloat16, device_map='auto', attn_implementation='sdpa')
    if args.adapter:
        from peft import PeftModel
        model = PeftModel.from_pretrained(model, args.adapter)
    model.eval()
    tokenizer = AutoTokenizer.from_pretrained(args.base)
    with open(args.out, 'w') as stream:
        for task, prompt in zip(TASKS, prompts):
            chat = tokenizer.apply_chat_template([{'role': 'user', 'content': prompt}], tokenize=False,
                                                 add_generation_prompt=True, enable_thinking=False)
            encoded = tokenizer(chat, return_tensors='pt').to(model.device)
            start = time.monotonic()
            with torch.inference_mode():
                output = model.generate(**encoded, max_new_tokens=700, do_sample=False,
                                        pad_token_id=tokenizer.eos_token_id)
            raw = tokenizer.decode(output[0, encoded.input_ids.shape[1]:], skip_special_tokens=True)
            decision, errors = check_decision(raw, task, facts)
            record = {'task_id': task['id'], 'base': args.base, 'adapter': args.adapter,
                      'facts_sha256': hashlib.sha256(facts_bytes).hexdigest(),
                      'prompt_sha256': hashlib.sha256(prompt.encode()).hexdigest(),
                      'resolved_compounds': resolved_for(task, facts), 'raw': raw,
                      'nextflow_path': decision.get('nextflow_path'), 'params': decision.get('params'),
                      'expect_compounds': task['expect_compounds'],
                      'expect_mw': [float(facts[name]['molecular_weight']) for name in task['compound_names']],
                      'contract_pass': not errors, 'errors': errors, 'seconds': time.monotonic() - start,
                      'execution_status': 'NOT_RUN', 'scope': 'Two grounded ADMET decisions only; not client acceptance.'}
            stream.write(json.dumps(record) + '\n')
            stream.flush()
            print(f"{task['id']}: contract_pass={not errors}, execution=NOT_RUN", flush=True)


if __name__ == '__main__':
    main()
