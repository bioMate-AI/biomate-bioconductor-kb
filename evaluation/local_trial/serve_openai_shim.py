"""Minimal OpenAI-compatible shim for RealBio harness. Serves base 27B (4-bit) and, if an adapter
is given, base+LoRA — selected by the request 'model' field ('base' vs 'sft'). Endpoints:
/v1/models, /v1/chat/completions."""
import argparse, time, torch
from fastapi import FastAPI, Request
import uvicorn
ap=argparse.ArgumentParser(); ap.add_argument("--base",required=True); ap.add_argument("--adapter",default=None); ap.add_argument("--port",type=int,default=8000)
a=ap.parse_args()
from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig
tok=AutoTokenizer.from_pretrained(a.base, trust_remote_code=True)
if tok.pad_token is None: tok.pad_token=tok.eos_token
bnb=BitsAndBytesConfig(load_in_4bit=True,bnb_4bit_quant_type="nf4",bnb_4bit_use_double_quant=True,bnb_4bit_compute_dtype=torch.bfloat16)
model=AutoModelForCausalLM.from_pretrained(a.base,quantization_config=bnb,device_map="auto",torch_dtype=torch.bfloat16,trust_remote_code=True,low_cpu_mem_usage=True)
HAS_LORA=False
if a.adapter:
    from peft import PeftModel; model=PeftModel.from_pretrained(model,a.adapter); HAS_LORA=True
model.eval()
app=FastAPI()
@app.get("/v1/models")
def models(): return {"data":[{"id":"base","object":"model"}]+([{"id":"sft","object":"model"}] if HAS_LORA else [])}
@app.post("/v1/chat/completions")
async def chat(req: Request):
    b=await req.json(); msgs=b.get("messages",[]); mx=int(b.get("max_tokens",256)); want=b.get("model","base")
    try: enc=tok.apply_chat_template(msgs,add_generation_prompt=True,return_tensors="pt",return_dict=True,enable_thinking=False)
    except TypeError: enc=tok.apply_chat_template(msgs,add_generation_prompt=True,return_tensors="pt",return_dict=True)
    enc={k:v.to(model.device) for k,v in enc.items()}; il=enc["input_ids"].shape[1]
    def run():
        with torch.no_grad(): o=model.generate(**enc,max_new_tokens=mx,do_sample=False,pad_token_id=tok.pad_token_id)
        return tok.decode(o[0][il:],skip_special_tokens=True)
    if HAS_LORA and want=="base":
        with model.disable_adapter(): out=run()
    else: out=run()
    return {"id":"c","object":"chat.completion","created":int(time.time()),"model":want,
            "choices":[{"index":0,"message":{"role":"assistant","content":out},"finish_reason":"stop"}],
            "usage":{"prompt_tokens":il,"completion_tokens":0,"total_tokens":il}}
uvicorn.run(app,host="0.0.0.0",port=a.port,log_level="warning")
