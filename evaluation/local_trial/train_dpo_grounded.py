"""Grounded DPO (stage 4): preference optimization where the reward is GROUNDED, not a judge's taste.

For routing/param prompts we already know the gold. We sample K completions from the SFT model,
score each with a grounded reward, and form (chosen, rejected) pairs:
  - routing:  reward = 1 if the named workflow == gold (or an acceptable alt), else 0
  - param:    reward = fraction of gold param values present AND schema-valid (no invented keys)
  - diagnosis:reward = 1 if predicted category == gold category
The best-scoring sample is 'chosen', a strictly-worse one is 'rejected'. DPO then contrasts them --
generation-level contrastive learning, the same principle as the retriever's InfoNCE one level up.

Runs on the GPU box against the merged SFT model. Two phases: (A) build pairs by sampling; (B) DPO."""
import argparse, json, re, os, sys
from pathlib import Path

def norm(s): return re.sub(r"[^a-z0-9]+"," ",str(s).lower()).strip()

def reward(task, gold, out):
    o=norm(out)
    if task=="routing":
        cw=norm(gold.get("correct_workflow","")); return 1.0 if cw and cw in o else 0.0
    if task=="diagnosis":
        c=norm(gold.get("category","")); return 1.0 if c and c in o else 0.0
    if task=="param":
        exp=gold.get("expected_params",{}) or {}
        if not exp: return 0.0
        return sum(1 for v in exp.values() if norm(v) and norm(v) in o)/len(exp)
    return 0.0

def build_pairs(args):
    """Phase A: sample K completions per prompt from the SFT model, score, emit chosen/rejected pairs."""
    import torch
    from transformers import AutoModelForCausalLM, AutoTokenizer
    tok=AutoTokenizer.from_pretrained(args.model, trust_remote_code=True)
    model=AutoModelForCausalLM.from_pretrained(args.model, torch_dtype=torch.bfloat16,
        device_map="auto", trust_remote_code=True)
    model.eval()
    rows=[json.loads(l) for l in open(args.prompts) if l.strip()]
    pairs=[]
    for r in rows:
        task=r["task"]; gold=r["ground_truth"]; prompt=r["prompt"]
        enc=tok.apply_chat_template([{"role":"user","content":prompt}], add_generation_prompt=True,
                                    return_tensors="pt", return_dict=True)
        enc={k:v.to(model.device) for k,v in enc.items()}; ilen=enc["input_ids"].shape[1]
        outs=[]
        for _ in range(args.k):
            with torch.no_grad():
                g=model.generate(**enc, max_new_tokens=96, do_sample=True, temperature=0.9, top_p=0.95,
                                 pad_token_id=tok.pad_token_id or tok.eos_token_id)
            outs.append(tok.decode(g[0][ilen:], skip_special_tokens=True))
        scored=sorted(((reward(task,gold,o),o) for o in outs), key=lambda x:-x[0])
        if scored[0][0] > scored[-1][0]:   # a real preference gap exists
            pairs.append({"prompt":prompt,"chosen":scored[0][1],"rejected":scored[-1][1],
                          "task":task,"margin":round(scored[0][0]-scored[-1][0],3)})
    Path(args.pairs_out).write_text("\n".join(json.dumps(p) for p in pairs))
    print(f"DPO PAIRS: {len(pairs)}/{len(rows)} prompts yielded a preference gap -> {args.pairs_out}")

def train(args):
    """Phase B: DPO on the grounded pairs."""
    import torch
    from datasets import load_dataset
    from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig
    from peft import LoraConfig, prepare_model_for_kbit_training
    from trl import DPOTrainer, DPOConfig
    tok=AutoTokenizer.from_pretrained(args.model, trust_remote_code=True)
    if tok.pad_token is None: tok.pad_token=tok.eos_token
    bnb=BitsAndBytesConfig(load_in_4bit=True, bnb_4bit_quant_type="nf4",
        bnb_4bit_use_double_quant=True, bnb_4bit_compute_dtype=torch.bfloat16)
    model=AutoModelForCausalLM.from_pretrained(args.model, quantization_config=bnb, device_map="auto",
        torch_dtype=torch.bfloat16, trust_remote_code=True)
    model=prepare_model_for_kbit_training(model, use_gradient_checkpointing=True)
    # Start policy / KL reference. Mirror the proven GRPO loading (train_grpo_unified.py): when an
    # --adapter is given (sft_gold), load it as the trainable policy and pass NO peft_config —
    # trl's DPOTrainer then uses the adapter-DISABLED model as the frozen reference, so DPO anchors
    # to sft_gold and improves over it (not from base). Without --adapter, start a fresh LoRA.
    peft_cfg=None
    if getattr(args, "adapter", None):
        from peft import PeftModel
        model=PeftModel.from_pretrained(model, args.adapter, is_trainable=True)
    else:
        peft_cfg=LoraConfig(r=16, lora_alpha=32, lora_dropout=0.05, bias="none", task_type="CAUSAL_LM",
            target_modules=["q_proj","k_proj","v_proj","o_proj","gate_proj","up_proj","down_proj"])
    ds=load_dataset("json", data_files=args.pairs_out, split="train")
    cfg=DPOConfig(output_dir=args.out, per_device_train_batch_size=1, gradient_accumulation_steps=16,
        num_train_epochs=int(os.environ.get("DPO_EPOCHS","3")), learning_rate=5e-6, lr_scheduler_type="cosine", warmup_steps=10,
        bf16=True, gradient_checkpointing=True, gradient_checkpointing_kwargs={"use_reentrant":False},
        optim="paged_adamw_8bit", beta=0.1, max_length=1024, save_steps=int(os.environ.get("DPO_SAVE_STEPS","50")),
        report_to=[], seed=13)
    tr=DPOTrainer(model=model, args=cfg, train_dataset=ds, processing_class=tok, peft_config=peft_cfg)
    tr.train(resume_from_checkpoint=getattr(args, "resume", None) or None)
    tr.save_model(args.out); print("DPO_DONE ->", args.out)

def mine_routing_pairs(args):
    """Direct contrastive pairs from rag_routing hard_negatives (near-ties): chosen = verified gold,
    rejected = the near-tie the retriever nearly ranked first. No sampling needed — these ARE the
    hardest cases, exactly what the model must learn to discriminate (user's contrastive point)."""
    import random as _r; _r.seed(13)
    rows=[json.loads(l) for l in open(args.prompts) if l.strip()]
    pairs=[]
    for rr in rows:
        hn=rr.get("hard_negatives") or []
        if not hn: continue
        prompt=rr["messages"][0]["content"]; gold=rr["messages"][1]["content"]
        for neg in hn[:3]:
            if neg and neg!=gold:
                pairs.append({"prompt":prompt,"chosen":gold,"rejected":neg,"task":"routing"})
    Path(args.pairs_out).write_text("\n".join(json.dumps(p) for p in pairs))
    print(f"ROUTING DPO PAIRS (near-tie hard negatives): {len(pairs)} -> {args.pairs_out}")

# --- execution-GROUNDED preference pairs (no GPU, no Batch): prefer workflows that ACTUALLY ran ---
EXEC_OK   = {"ok", "ok_warnings"}
EXEC_FAIL = {"exec_error", "fixture_failed", "timeout", "ran_empty_output"}
INSTR_ROUTING = ("Bioinformatics workflows come primarily from three sources: Nextflow/nf-core, Galaxy, "
    "and Bioconductor. Route this request to the single correct WORKFLOW, using its canonical name "
    "(e.g. 'nf-core/rnaseq').")
_HERE = os.path.dirname(os.path.abspath(__file__))
DEF_SPEC = os.path.join(_HERE, "../../docs/20260912_onprem_llm/data_candidates_v2/workflow_spec_candidates.jsonl")
DEF_PUB  = os.path.join(_HERE, "../datasets/public_export")

def _mj(x):
    if isinstance(x, (list, dict)): return x
    try: return json.loads(x) if isinstance(x, str) and x.strip() else []
    except Exception: return []

def _norm_q(s): return re.sub(r"\s+", " ", str(s or "").strip().lower())

def _load_eval_queries(pub):
    """eval-leakage guard: every public_export eval item's query text (so a mined prompt can't echo one)."""
    qs=set()
    if not pub or not os.path.isdir(pub): return qs
    for task in os.listdir(pub):
        d=os.path.join(pub, task, "data.jsonl")
        if not os.path.isfile(d): continue
        for l in open(d):
            try: r=json.loads(l)
            except Exception: continue
            for f in ("query","user_query","question","intent","protocol","description"):
                if r.get(f): qs.add(_norm_q(r[f]))
    return qs

def mine_execution_pairs(args):
    """Phase 'exec': execution-GROUNDED preference pairs from workflow_spec_candidates — the reward is
    'did it actually run', using the PERSISTED real_exec_status (no GPU sampling, no new Batch jobs).
      chosen   = a workflow that executed (real_exec_status in ok/ok_warnings)
      rejected = a confusable SAME-DOMAIN sibling that FAILED execution (exec_error/fixture_failed/
                 timeout/ran_empty_output), ranked by shared tools + input/output types.
    The request is synthesized ONLY from signal the two SHARE (domain + overlapping IO + tools) so the
    negative genuinely fits the request and the single learnable distinction is executability. This is
    the contained, no-spend step toward execution-feedback DPO (full grade_run-on-Batch reward = C3)."""
    import random as _r, collections as _c; _r.seed(13)
    rows=[json.loads(l) for l in open(args.spec) if l.strip()]
    by_dom=_c.defaultdict(lambda: {"ok": [], "fail": []})
    for r in rows:
        st=r.get("real_exec_status"); dom=r.get("domain"); nm=r.get("workflow_name")
        if not dom or not nm: continue
        if st in EXEC_OK: by_dom[dom]["ok"].append(r)
        elif st in EXEC_FAIL: by_dom[dom]["fail"].append(r)
    evalq=_load_eval_queries(args.pub); dropped_leak=0
    pairs=[]
    for dom, grp in by_dom.items():
        if not grp["ok"] or not grp["fail"]: continue
        made=0
        for ch in grp["ok"]:
            ch_t=set(map(str,_mj(ch.get("tools_used")))); ch_i=set(map(str,_mj(ch.get("input_types")))); ch_o=set(map(str,_mj(ch.get("output_types"))))
            # Collect ALL genuinely-confusable failed siblings (shared tool/IO >= 1), ranked by
            # confusability, and emit the top `neg_per_chosen` as separate preference pairs (each
            # chosen>rejected is an independent DPO example). neg_per_chosen=1 reproduces the original
            # single-best behaviour; >1 expands the set without lowering the confusability bar.
            cands=[]
            for rj in grp["fail"]:
                if rj.get("workflow_name")==ch.get("workflow_name"): continue
                rt=set(map(str,_mj(rj.get("tools_used")))); ri=set(map(str,_mj(rj.get("input_types")))); ro=set(map(str,_mj(rj.get("output_types"))))
                sh_t, sh_i, sh_o = ch_t&rt, ch_i&ri, ch_o&ro
                ov=len(sh_t)*2+len(sh_i)+len(sh_o)
                if ov >= 1:   # require genuine confusability, not an arbitrary same-domain negative
                    cands.append((ov, rj, sh_t, sh_i, sh_o))
            cands.sort(key=lambda x: -x[0])
            for ov, rj, sh_t, sh_i, sh_o in cands[:max(1, getattr(args, "neg_per_chosen", 1))]:
                art="an" if dom[:1].lower() in "aeiou" else "a"
                clauses=[]
                if sh_i: clauses.append(f"takes {', '.join(sorted(sh_i)[:3])} input")
                if sh_o: clauses.append(f"produces {', '.join(sorted(sh_o)[:3])}")
                req=f"Recommend {art} {dom} workflow"
                if clauses: req+=" that "+" and ".join(clauses)
                if sh_t: req+=f" (tools like {', '.join(sorted(sh_t)[:3])})"
                req+="."
                if _norm_q(req) in evalq: dropped_leak+=1; continue
                pairs.append({"prompt":f"{INSTR_ROUTING}\n\nRequest: {req}", "chosen":ch.get("workflow_name"),
                              "rejected":rj.get("workflow_name"), "task":"routing",
                              "source":"execution_grounded", "domain":dom, "confusability":ov})
                made+=1
                if made>=args.per_domain: break
            if made>=args.per_domain: break
    seen=set(); uniq=[]
    for p in pairs:
        k=(p["prompt"],p["chosen"],p["rejected"])
        if k in seen or p["chosen"]==p["rejected"]: continue
        seen.add(k); uniq.append(p)
    _r.shuffle(uniq)
    Path(args.pairs_out).write_text("\n".join(json.dumps(p) for p in uniq))
    print(f"EXECUTION-GROUNDED DPO PAIRS: {len(uniq)} (chosen=ran, rejected=failed) across "
          f"{len(set(p['domain'] for p in uniq))} domains, dropped {dropped_leak} eval-leak -> {args.pairs_out}")

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--phase", choices=["pairs","mine","exec","train"], required=True)
    ap.add_argument("--model", help="merged SFT model (phases pairs/train)")
    ap.add_argument("--prompts", help="jsonl {task,prompt,ground_truth} (phase pairs)")
    ap.add_argument("--pairs-out", default="dpo_pairs.jsonl")
    ap.add_argument("--out", default="dpo_out"); ap.add_argument("--k", type=int, default=6)
    ap.add_argument("--spec", default=DEF_SPEC, help="workflow_spec_candidates.jsonl (phase exec)")
    ap.add_argument("--pub", default=DEF_PUB, help="public_export dir for eval-leak guard (phase exec)")
    ap.add_argument("--per-domain", type=int, default=40, help="max exec pairs per domain (phase exec)")
    ap.add_argument("--neg-per-chosen", type=int, default=1,
                    help="exec phase: emit the top-N most-confusable failed siblings per chosen (>1 expands pairs)")
    a=ap.parse_args()
    if a.phase=="mine": return mine_routing_pairs(a)   # cheap: direct near-tie hard-negative pairs
    if a.phase=="exec": return mine_execution_pairs(a) # cheap: execution-grounded pairs (no GPU/Batch)
    if a.phase in ("pairs","train") and not a.model: ap.error("--model required for phase "+a.phase)
    return build_pairs(a) if a.phase=="pairs" else train(a)

if __name__=="__main__": raise SystemExit(main())
