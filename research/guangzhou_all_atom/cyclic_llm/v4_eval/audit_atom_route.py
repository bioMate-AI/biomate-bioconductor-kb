"""C6 atom-route audit: topology agreement with CycPeptMPDB Molecule_Shape, tokenizer round-trip/UNK/length coverage on the frozen benchmark compounds.
usage: python3 audit_atom_route.py VOCAB_JSON OUT_JSON  (run from v4_eval/)"""
import sys, csv, json, collections, numpy as np, pandas as pd
sys.path.insert(0,"."); sys.path.insert(0,"../allatom")
import v5_atom_tokens as V, atom_lm as A
itos=json.load(open(sys.argv[1])); vocab=A.Vocab(itos[4:]) if itos[:4]==["<pad>","<bos>","<eos>","<unk>"] else A.Vocab(itos)
res={"atom_vocab_size":len(vocab),"topology_tokens_in_vocab":[t for t in V.TOPO_TOKENS if t in vocab.stoi]}
rows=[r for r in csv.DictReader(open("../../data/raw/CycPeptMPDB_Peptide_All.csv",encoding="utf-8-sig",errors="replace")) if r.get("SMILES")]
conf=collections.Counter((r["Molecule_Shape"],V.topology(r["SMILES"])[0]) for r in rows)
circ=sum(v for (s,t),v in conf.items() if s=="Circle"); lar=sum(v for (s,t),v in conf.items() if s=="Lariat")
res["topology_vs_CycPeptMPDB_shape"]={"confusion":{f"{a}->{b}":v for (a,b),v in conf.items()},"circle_to_h2t":round(conf[("Circle","<topo_h2t>")]/circ,3),"lariat_to_lariat":round(conf[("Lariat","<topo_lariat>")]/lar,3),"n":len(rows)}
C=pd.read_csv("../../multitarget/integrin_chembl/retro_recovery/data/compounds.csv.gz"); n=len(C)
st=collections.Counter(); unk=[]; lens=[]; topo=collections.Counter(); rt=0; stereo=0; fails=[]
for s in C.iso_smiles:
    try: toks=A.tokenize(s); rt+=1
    except AssertionError: toks=None; fails.append(s)
    ids,status=V.encode(s,vocab,10**9); st[status if toks is not None else "tokenizer_fail"]+=1
    if toks is None: continue
    nt=len(V.topology(s)); body=ids[1+nt:-1]; lens.append(len(ids)); unk.append(sum(i==A.UNK for i in body)); topo["+".join(V.topology(s))]+=1; stereo+=("@" in s)
unk=np.array(unk); lens=np.array(lens)
res["benchmark_compounds"]={"n":n,"tokenizer_round_trip_exact":round(rt/n,4),"with_stereo_marks":round(stereo/n,3),"frac_with_UNK_in_smiles_tokens":round(float(np.mean(unk>0)),4),"mean_UNK_per_seq":round(float(unk.mean()),3),
  "length_median":int(np.median(lens)),"length_p90":int(np.percentile(lens,90)),"length_max":int(lens.max()),"frac_gt_256":round(float(np.mean(lens>256)),3),"frac_gt_384":round(float(np.mean(lens>384)),3),"frac_gt_512":round(float(np.mean(lens>512)),3),
  "tokenizer_fail":len(fails),"tokenizer_fail_examples":[f[:80] for f in fails[:3]],"topology_distribution":dict(topo.most_common())}
json.dump(res,open(sys.argv[2],"w"),indent=1); print(json.dumps(res,indent=1))
