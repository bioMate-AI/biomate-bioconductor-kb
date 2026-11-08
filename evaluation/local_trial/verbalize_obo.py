"""Generic OBO ontology verbalizer (SO, HPO, ChEBI, etc.): term name+def+is_a -> sentences."""
import json,re,sys
src_url, label, outname = sys.argv[1], sys.argv[2], sys.argv[3]
import urllib.request
tmp=f"/tmp/{outname}.obo"
urllib.request.urlretrieve(src_url, tmp)
OUT=f"/Users/kky/biomate-review/docs/20260912_onprem_llm/midtrain_corpus/{outname}_corpus.jsonl"
terms=[]; cur=None
for line in open(tmp,errors="ignore"):
    line=line.rstrip("\n")
    if line=="[Term]": cur={"is_a":[]}; terms.append(cur); continue
    if cur is None: continue
    if line.startswith("id: "): cur["id"]=line[4:]
    elif line.startswith("name: "): cur["name"]=line[6:]
    elif line.startswith("def: "):
        m=re.search(r'"([^"]+)"',line); cur["def"]=m.group(1) if m else ""
    elif line.startswith("is_a: "): cur["is_a"].append(line[6:].split("!")[-1].strip() if "!" in line else line[6:].strip())
    elif line.startswith("is_obsolete: true"): cur["obs"]=True
n=0
with open(OUT,"w") as f:
    for t in terms:
        if t.get("obs") or not t.get("name") or len(t.get("def",""))<15: continue
        txt=f"{label}: {t['name']} — {t['def']}"
        if t["is_a"]: txt+=f" It is a kind of {', '.join(t['is_a'][:3])}."
        f.write(json.dumps({"text":txt,"source":outname,"id":t.get("id")})+"\n"); n+=1
print(f"{outname}: {n} terms")
