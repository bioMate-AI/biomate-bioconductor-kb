import json, sys
sys.path.insert(0, __file__.rsplit("/",1)[0])
from routing_prompt import build_messages
REPO="/Users/kky/biomate-review"
src=f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/routing_episodes.jsonl"
eps=[json.loads(l) for l in open(src) if l.strip()]
out_tr=f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/routing_sft_train.jsonl"
out_dev=f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/routing_sft_dev.jsonl"
ntr=ndev=0
ftr=open(out_tr,"w"); fdev=open(out_dev,"w")
for e in eps:
    msgs=build_messages(e["query"], e["candidates"], in_format=True, few_shot=True)
    msgs.append({"role":"assistant","content":e["correct_workflow"]})
    rec={"messages":msgs}
    if e["split"]=="train": ftr.write(json.dumps(rec)+"\n"); ntr+=1
    elif e["split"]=="dev": fdev.write(json.dumps(rec)+"\n"); ndev+=1
ftr.close(); fdev.close()
print(f"SFT train={ntr} dev={ndev} (dbtest kept for eval)")
