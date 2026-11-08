"""T17 vision smoke: load the FULL multimodal model (vision tower on) + interpret a figure."""
import argparse, torch
ap=argparse.ArgumentParser(); ap.add_argument("--base",required=True); ap.add_argument("--image",required=True)
ap.add_argument("--prompt",default="You are BioMate. Describe this figure: which sample has the highest value and approximately what is it? Which is lowest?")
a=ap.parse_args()
from transformers import AutoProcessor, BitsAndBytesConfig
from PIL import Image
bnb=BitsAndBytesConfig(load_in_4bit=True,bnb_4bit_quant_type="nf4",bnb_4bit_use_double_quant=True,bnb_4bit_compute_dtype=torch.bfloat16)
try:
    from transformers import AutoModelForImageTextToText as MM
except Exception:
    from transformers import AutoModelForVision2Seq as MM
proc=AutoProcessor.from_pretrained(a.base, trust_remote_code=True)
model=MM.from_pretrained(a.base, quantization_config=bnb, device_map="auto", torch_dtype=torch.bfloat16, trust_remote_code=True, low_cpu_mem_usage=True)
model.eval()
img=Image.open(a.image).convert("RGB")
messages=[{"role":"user","content":[{"type":"image"},{"type":"text","text":a.prompt}]}]
text=proc.apply_chat_template(messages, add_generation_prompt=True, tokenize=False)
inputs=proc(text=[text], images=[img], return_tensors="pt")
inputs={k:(v.to(model.device) if hasattr(v,"to") else v) for k,v in inputs.items()}
il=inputs["input_ids"].shape[1]
with torch.no_grad():
    out=model.generate(**inputs, max_new_tokens=160, do_sample=False)
print("=== VISION OUTPUT ===")
print(proc.batch_decode(out[:,il:], skip_special_tokens=True)[0])
