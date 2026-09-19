"""Domain-adaptive MID-training of the base 27B on the corpus (LoRA, packed, ALL-token loss = true
continued pretraining, not instruction SFT). Optionally mixes a general-replay file at --replay-frac
to bridge distributions (anti-forgetting). Run on a GPU box."""
import argparse
def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--base",required=True); ap.add_argument("--data",required=True)  # midtrain_all.jsonl
    ap.add_argument("--replay",default=None); ap.add_argument("--replay-frac",type=float,default=0.75)
    ap.add_argument("--out",required=True); ap.add_argument("--max-steps",type=int,default=1000)
    ap.add_argument("--seq-len",type=int,default=2048); ap.add_argument("--lora-r",type=int,default=32)
    ap.add_argument("--resume",default=None,help="checkpoint dir to resume from (spot-interruption safe)")
    a=ap.parse_args()
    import torch
    from datasets import load_dataset, concatenate_datasets
    from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig
    from peft import LoraConfig, prepare_model_for_kbit_training
    from trl import SFTTrainer, SFTConfig
    tok=AutoTokenizer.from_pretrained(a.base, trust_remote_code=True)
    if tok.pad_token is None: tok.pad_token=tok.eos_token
    dom=load_dataset("json", data_files=a.data, split="train")
    if a.replay:  # distributional bridge: mix general replay at replay-frac
        rep=load_dataset("json", data_files=a.replay, split="train")
        k=int(len(dom)*a.replay_frac/(1-a.replay_frac))
        rep=rep.select(range(min(k,len(rep)))); ds=concatenate_datasets([dom,rep]).shuffle(seed=13)
    else: ds=dom
    bnb=BitsAndBytesConfig(load_in_4bit=True,bnb_4bit_quant_type="nf4",bnb_4bit_use_double_quant=True,bnb_4bit_compute_dtype=torch.bfloat16)
    model=AutoModelForCausalLM.from_pretrained(a.base,quantization_config=bnb,device_map="auto",torch_dtype=torch.bfloat16,trust_remote_code=True,low_cpu_mem_usage=True,attn_implementation="eager")
    model.config.use_cache=False; model=prepare_model_for_kbit_training(model,use_gradient_checkpointing=True)
    lora=LoraConfig(r=a.lora_r,lora_alpha=2*a.lora_r,lora_dropout=0.05,bias="none",task_type="CAUSAL_LM",
                    target_modules=["q_proj","k_proj","v_proj","o_proj","gate_proj","up_proj","down_proj"])
    cfg=SFTConfig(output_dir=a.out,per_device_train_batch_size=1,gradient_accumulation_steps=16,
        max_steps=a.max_steps,learning_rate=1e-4,lr_scheduler_type="cosine",warmup_steps=20,logging_steps=5,
        save_steps=max(a.max_steps//3,50),save_total_limit=3,bf16=True,gradient_checkpointing=True,
        gradient_checkpointing_kwargs={"use_reentrant":False},optim="paged_adamw_8bit",max_length=a.seq_len,
        packing=True, dataset_text_field="text", report_to=[], seed=13)  # packing + text field = pretraining
    tr=SFTTrainer(model=model,args=cfg,train_dataset=ds,peft_config=lora,processing_class=tok)
    r=tr.train(resume_from_checkpoint=a.resume); tr.save_model(a.out); tok.save_pretrained(a.out)
    import json as J; J.dump({"train_loss":r.metrics.get("train_loss"),"steps":a.max_steps,"n_docs":ds.num_rows},open(a.out+"/midtrain_result.json","w"))
    print("MIDTRAIN_DONE loss=",r.metrics.get("train_loss"))
if __name__=="__main__": raise SystemExit(main())
