# envpin2 (torch+numpy): build FM, embed RNA-only and RNA+protein fusion -> npy
import sys,numpy as np,torch,torch.nn as nn
WS="/home/yzhang/immune_fm_spark"; OUT=f"{WS}/ws_mc"; sys.path.insert(0,f"{WS}/code_20261004")
import immune_hybrid_llm as H
xs=np.load(f"{WS}/ws_bench/xs_stim.npy").astype(np.float32)   # RNA corpus-scaled HVG (2000)
Xp=np.load(f"{OUT}/Xp35.npy").astype(np.float32)              # protein 35-slot CLR
ck=torch.load(f"{WS}/fs_long/work/hybrid_model.pt",map_location="cpu",weights_only=False)
sd,m=ck["trainable_state_dict"],ck["cfg_meta"]; cfg=H.default_cfg()
for k in ("n_genes","chan_dim","n_celltypes","n_studies","mod_dims","d","bottle","concept_perpath","n_programs"):
    if k in m: cfg[k]=m[k]
cfg["hvg_names"]=m["hvg_names"]; cfg["backbone"]=ck["backbone"]; cfg["bottleneck_mode"]=ck["bottleneck_mode"]
cfg["pep_dim"]=int(sd["pep_enc.0.weight"].shape[1]) if "pep_enc.0.weight" in sd else cfg["pep_dim"]
cfg["n_programs"]=int(sd["h_biomk.weight"].shape[0]) if "h_biomk.weight" in sd else cfg["n_programs"]
cfg["genetics_prior"]=torch.zeros(cfg["n_genes"]); cfg["mod_dropout"]=0.0
if "backbone.proto.weight" in sd: cfg["proto_init"]=torch.zeros_like(sd["backbone.proto.weight"])
torch.manual_seed(0); model=H.build_model(cfg,torch,nn); r=model.load_state_dict(sd,strict=False)
print("loaded; missing",len(r.missing_keys),"unexpected",len(r.unexpected_keys),"seqlen",cfg["seqlen"],flush=True)
model.cuda().eval()
def embed(use_prot):
    out=[]
    with torch.no_grad():
        for i in range(0,len(xs),512):
            t=torch.from_numpy(xs[i:i+512]).cuda(); b=len(t)
            mods={"rna":t}; masks={"rna":torch.ones(b,1,device="cuda")}
            if use_prot:
                p=torch.from_numpy(Xp[i:i+512]).cuda(); mods["protein"]=p; masks["protein"]=torch.ones(b,1,device="cuda")
            z=model(torch.zeros(b,cfg["seqlen"],dtype=torch.long,device="cuda"),mods,masks,t)["z"]
            out.append(z.cpu().numpy())
    return np.concatenate(out)
np.save(f"{OUT}/fm_rna.npy",embed(False)); np.save(f"{OUT}/fm_multi.npy",embed(True))
print("MC_EMBED_COMPLETE",flush=True)
