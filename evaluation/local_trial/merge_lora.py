"""Merge a LoRA/QLoRA adapter into its base -> a standalone fp16 model.

Two uses in the pipeline: (1) after mid-training, merge so SFT continues from the domain-adapted
weights (stacking QLoRA adapters is fragile; merging is clean); (2) after SFT, merge so the model
serves in vLLM as a plain model -> the eval compares base-server vs merged-server with NO
adapter-toggle ambiguity (the root cause of the 20260914 zero-delta artifact). Loads the base in
fp16 (NOT 4-bit) so the merge is lossless."""
import argparse, torch
from transformers import AutoModelForCausalLM, AutoTokenizer
from peft import PeftModel

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--base",required=True); ap.add_argument("--adapter",required=True)
    ap.add_argument("--out",required=True)
    a=ap.parse_args()
    tok=AutoTokenizer.from_pretrained(a.base, trust_remote_code=True)
    from model_loading import load_text_model
    model=load_text_model(a.base, torch_dtype=torch.bfloat16,
        device_map="cpu", trust_remote_code=True, low_cpu_mem_usage=True)
    model=PeftModel.from_pretrained(model, a.adapter)
    model=model.merge_and_unload()          # fold LoRA deltas into base weights
    model.save_pretrained(a.out, safe_serialization=True)
    tok.save_pretrained(a.out)
    print("MERGED ->", a.out)

if __name__=="__main__": raise SystemExit(main())
