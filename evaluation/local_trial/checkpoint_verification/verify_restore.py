import hashlib, json, os, time, sys
from pathlib import Path
import torch
from safetensors.torch import load_file
from transformers import AutoModelForCausalLM, AutoTokenizer
from peft import PeftModel
root=Path(os.environ['SCRATCH'])/'restore'
out=root/'restore_report.json'
report={'scope':'S3 restore and synthetic-prompt numerical validation; not scientific quality evaluation','checks':{},'started':time.time(),'python':sys.version}
def sha256_file(path):
    digest=hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(8*1024*1024),b''):
            digest.update(chunk)
    return digest.hexdigest()
def check(name,value):
    report['checks'][name]=bool(value)
    if not value: raise RuntimeError(name)
try:
    check('cuda_available',torch.cuda.is_available())
    torch.manual_seed(0)
    base=root/'base_domain'; adapter=root/'sft'
    report['sha256']={str(p.relative_to(root)):sha256_file(p) for p in [base/'model.safetensors',adapter/'adapter_model.safetensors']}
    tok=AutoTokenizer.from_pretrained(base,local_files_only=True)
    messages=[{'role':'user','content':'Return only the word VERIFIED.'}]
    prompt=tok.apply_chat_template(messages,tokenize=False,add_generation_prompt=True,enable_thinking=False)
    encoded=tok(prompt,return_tensors='pt').to('cuda')
    check('tokenizer_round_trip',bool(tok.decode(encoded.input_ids[0])))
    model,info=AutoModelForCausalLM.from_pretrained(base,local_files_only=True,torch_dtype=torch.bfloat16,device_map={'':'cuda'},attn_implementation='eager',output_loading_info=True)
    report['loading_info']=info
    check('complete_base_load',not any(info.get(k) for k in ['missing_keys','unexpected_keys','mismatched_keys','error_msgs']))
    model.eval()
    with torch.inference_mode(): baseline=model(**encoded).logits.float().cpu()
    check('finite_base_logits',torch.isfinite(baseline).all().item())
    model=PeftModel.from_pretrained(model,adapter,local_files_only=True).eval()
    saved=load_file(str(adapter/'adapter_model.safetensors'))
    from peft import get_peft_model_state_dict
    live=get_peft_model_state_dict(model)
    check('adapter_tensor_parity',set(saved)==set(live) and all(torch.equal(saved[k].to(live[k].dtype),live[k].cpu()) for k in saved))
    check('finite_model_weights',all(torch.isfinite(p).all().item() for p in model.parameters()))
    with torch.inference_mode(): first=model(**encoded).logits.float().cpu()
    check('finite_adapted_logits',torch.isfinite(first).all().item())
    report['adapter_max_logit_delta']=(first-baseline).abs().max().item()
    check('adapter_affects_logits',report['adapter_max_logit_delta']>0)
    model=model.unload()
    model=PeftModel.from_pretrained(model,adapter,local_files_only=True).eval()
    with torch.inference_mode():
        second=model(**encoded).logits.float().cpu()
        generated=model.generate(**encoded,max_new_tokens=16,do_sample=False,pad_token_id=tok.eos_token_id)
    report['reload_max_logit_delta']=(first-second).abs().max().item()
    check('reload_logit_parity',torch.equal(first,second))
    newtokens=generated[0,encoded.input_ids.shape[1]:]
    check('generation_produces_tokens',len(newtokens)>0)
    report['synthetic_prompt_response']=tok.decode(newtokens,skip_special_tokens=True)
    report['complete']=True
except Exception as exc:
    report['complete']=False; report['error']=repr(exc)
    raise
finally:
    report['finished']=time.time(); out.write_text(json.dumps(report,indent=2)); print(json.dumps(report,indent=2),flush=True)
