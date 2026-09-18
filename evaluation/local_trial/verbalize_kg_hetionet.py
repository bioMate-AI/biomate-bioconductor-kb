"""Verbalize Hetionet (CC0) edges into mid-training sentences. High-value metaedges only (skip GO-dup
Gene-participates and huge Anatomy-expression). Node IDs -> names via nodes.tsv. Capped."""
import gzip,json,csv,sys
NODES=sys.argv[1] if len(sys.argv)>1 else "/tmp/het_nodes.tsv"
EDGES=sys.argv[2] if len(sys.argv)>2 else "/tmp/het_edges.sif.gz"
OUT="/Users/kky/biomate-review/docs/20260912_onprem_llm/midtrain_corpus/hetionet_corpus.jsonl"
PER=14000  # per-metaedge cap for relation-type balance
name={}
for r in csv.DictReader(open(NODES),delimiter="\t"): name[r["id"]]=(r["name"],r["kind"])
VERB={  # metaedge -> readable relation
 "CtD":"treats","CpD":"palliates","CbG":"binds","CuG":"upregulates","CdG":"downregulates",
 "CrC":"resembles","DaG":"is associated with gene","DuG":"upregulates","DdG":"downregulates",
 "DrD":"resembles","DlA":"localizes to","GiG":"interacts with","Gr>G":"regulates","GcG":"covaries with",
 "GpPW":"participates in pathway","PCiC":"includes compound"}
import collections; per=collections.Counter(); n=0
with open(OUT,"w") as fo:
    for line in gzip.open(EDGES,"rt"):
        parts=line.rstrip("\n").split("\t")
        if len(parts)!=3: continue
        src,me,t=parts
        if me=="metaedge": continue
        v=VERB.get(me)
        if not v or per[me]>=PER: continue
        sn=name.get(src); tn=name.get(t)
        if not sn or not tn: continue
        per[me]+=1
        fo.write(json.dumps({"text":f"{sn[1]} {sn[0]} {v} {tn[1]} {tn[0]}.","source":"hetionet","id":f"{src}|{me}|{t}"})+"\n"); n+=1
print("per-metaedge:",dict(per))
print(f"Hetionet corpus: {n} verbalized edges (balanced)")
