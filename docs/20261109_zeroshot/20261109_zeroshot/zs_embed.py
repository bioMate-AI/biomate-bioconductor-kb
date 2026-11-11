# envpin2: embed A (D534) and B (GSE239626) through the frozen FM -> shared space
import sys,numpy as np,torch,torch.nn as nn
WS="/home/yzhang/immune_fm_spark"; OUT=f"{WS}/ws_zs"; sys.path.insert(0,f"{WS}/code_20261004"); import immune_hybrid_llm as H
ck=torch.load(f"{WS}/fs_long/work/hybrid_model.pt",map_location="cpu",weights_only=False); sd,m=ck["trainable_state_dict"],ck["cfg_meta"]
cfg=H.default_cfg()
for k in ("n_genes","chan_dim","n_celltypes","n_studies","mod_dims","d","bottle","concept_perpath","n_programs"):
    if k in m: cfg[k]=m[k]
cfg["hvg_names"]=m["hvg_names"]; cfg["backbone"]=ck["backbone"]; cfg["bottleneck_mode"]=ck["bottleneck_mode"]
cfg["pep_dim"]=int(sd["pep_enc.0.weight"].shape[1]) if "pep_enc.0.weight" in sd else cfg["pep_dim"]
cfg["n_programs"]=int(sd["h_biomk.weight"].shape[0]) if "h_biomk.weight" in sd else cfg["n_programs"]
cfg["genetics_prior"]=torch.zeros(cfg["n_genes"]); cfg["mod_dropout"]=0.0
if "backbone.proto.weight" in sd: cfg["proto_init"]=torch.zeros_like(sd["backbone.proto.weight"])
torch.manual_seed(0); model=H.build_model(cfg,torch,nn); model.load_state_dict(sd,strict=False); model.cuda().eval()
def embed(X):
    out=[]
    with torch.no_grad():
        for i in range(0,len(X),1024):
            t=torch.from_numpy(X[i:i+1024]).cuda(); b=len(t)
            z=model(torch.zeros(b,cfg["seqlen"],dtype=torch.long,device="cuda"),{"rna":t},{"rna":torch.ones(b,1,device="cuda")},t)["z"]
            out.append(z.cpu().numpy())
    return np.concatenate(out)
np.save(f"{OUT}/fmA.npy",embed(np.load(f"{OUT}/HA_fm.npy")))
np.save(f"{OUT}/fmB.npy",embed(np.load(f"{OUT}/HB_fm.npy")))
print("ZS_EMBED_COMPLETE",flush=True)
