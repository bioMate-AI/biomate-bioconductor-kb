"""Batched sampling with explicit token cap and identical temperature/soft policy.

Unlike the standalone U1 pilot helper this has no module-global length cap.
Both decoding and training use logits/temperature + soft-potential, then mask.
"""
import time
import numpy as np
import torch


@torch.no_grad()
def sample_group(model,device,constraint,items,temperature,masked,rng,stats,max_tokens):
    if temperature<=0 or max_tokens<1:
        raise ValueError('positive temperature and token cap required')
    batch=len(items); prompts=[p for _,p in items]
    if not prompts or len({len(p) for p in prompts})!=1:
        raise ValueError('sampling batch needs equal-length nonempty prompts')
    length=len(prompts[0]); generated=[[] for _ in items]
    done=[False]*batch; finished=[False]*batch; why=['length_cap']*batch
    states=[]
    for i,prompt in enumerate(prompts):
        try: states.append(constraint.init_state(prompt) if masked else None)
        except ValueError: states.append(None);done[i]=True;why[i]='prompt_illegal'
    if length>=max_tokens:
        return {row:([],False,0.0,prompt,'length_cap') for row,prompt in items}
    x=torch.tensor(prompts,device=device)
    output=model(input_ids=x,use_cache=True);past=output.past_key_values
    logits=output.logits[:,-1].float().cpu().numpy()
    for _ in range(min(300,max_tokens-length)):
        nxt=np.full(batch,constraint.eos,dtype=np.int64);started=time.perf_counter()
        for i in range(batch):
            if done[i]:continue
            lg=logits[i].astype(np.float64)/temperature
            if masked:
                feasible=constraint.mask(states[i])
                if not feasible.any():done[i]=True;why[i]='dead_end';continue
                lg=lg+constraint.soft_logits(states[i]);lg=np.where(feasible,lg,-np.inf)
            if not np.isfinite(lg).any():raise FloatingPointError('no finite sampling logits')
            q=np.exp(lg-np.max(lg));q/=q.sum()
            token=int(rng.choice(len(q),p=q));nxt[i]=token
            stats['row_steps']+=1
            if token==constraint.eos:done[i]=True;finished[i]=True;why[i]='ok'
            else:
                generated[i].append(token)
                if masked and not constraint.advance(states[i],token):
                    raise RuntimeError('mask admitted illegal tracker transition')
        stats['mask_seconds']+=time.perf_counter()-started
        if all(done):break
        output=model(input_ids=torch.tensor(nxt[:,None],device=device),past_key_values=past,use_cache=True)
        past=output.past_key_values;logits=output.logits[:,-1].float().cpu().numpy()
    return {items[i][0]:(generated[i],finished[i],0.0,items[i][1],why[i]) for i in range(batch)}
