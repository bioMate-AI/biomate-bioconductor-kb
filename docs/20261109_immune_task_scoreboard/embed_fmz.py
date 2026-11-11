# envpin2 (torch): load xs_stim.npy, build pretrained encoder, embed RNA-only -> z_fm.npy
import sys, numpy as np, torch, torch.nn as nn
WS="/home/yzhang/immune_fm_spark"; OUT=f"{WS}/ws_bench"
sys.path.insert(0,f"{WS}/code_20261004"); sys.path.insert(0,f"{WS}/eval_repair_20261107")
import immune_hybrid_llm as H
from eval_protocols import validate_checkpoint_parameters
ck=torch.load(f"{WS}/fs_long/work/hybrid_model.pt", map_location="cpu", weights_only=False)
def build(ck,pretrained,seed):
    sd,m=ck["trainable_state_dict"],ck["cfg_meta"]; cfg=H.default_cfg()
    for k in ("n_genes","chan_dim","n_celltypes","n_studies","mod_dims","d","bottle","concept_perpath","n_programs"):
        if k in m: cfg[k]=m[k]
    cfg["hvg_names"]=m["hvg_names"]; cfg["backbone"]=ck["backbone"]; cfg["bottleneck_mode"]=ck["bottleneck_mode"]
    cfg["pep_dim"]=int(sd["pep_enc.0.weight"].shape[1]) if "pep_enc.0.weight" in sd else cfg["pep_dim"]
    cfg["n_programs"]=int(sd["h_biomk.weight"].shape[0]) if "h_biomk.weight" in sd else cfg["n_programs"]
    cfg["genetics_prior"]=torch.zeros(cfg["n_genes"]); cfg["mod_dropout"]=0.0
    if "backbone.proto.weight" in sd: cfg["proto_init"]=torch.zeros_like(sd["backbone.proto.weight"])
    torch.manual_seed(seed); model=H.build_model(cfg,torch,nn)
    if pretrained:
        validate_checkpoint_parameters(model,sd); r=model.load_state_dict(sd,strict=False)
        if r.unexpected_keys: raise ValueError(f"unexpected {r.unexpected_keys[:10]}")
    return model,cfg
model,cfg=build(ck,True,0); dev="cuda" if torch.cuda.is_available() else "cpu"; model.to(dev).eval()
xs=np.load(f"{OUT}/xs_stim.npy"); N=len(xs); z=[]
with torch.no_grad():
    for i in range(0,N,512):
        t=torch.from_numpy(xs[i:i+512]).to(dev); b=len(t)
        mods={"rna":t}; masks={"rna":torch.ones(b,1,device=dev)}
        out=model(torch.zeros(b,cfg["seqlen"],dtype=torch.long,device=dev),mods,masks,t)
        z.append(out["z"].detach().cpu().numpy())
z=np.concatenate(z).astype(np.float32); np.save(f"{OUT}/z_fm_stim.npy", z)
print("z_fm saved", z.shape, "dev", dev, "bottle", cfg["bottle"])
