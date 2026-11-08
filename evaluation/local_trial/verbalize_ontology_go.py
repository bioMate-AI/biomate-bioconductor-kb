"""Verbalize GO (go-basic.obo) into mid-training text: term name + namespace + definition + is_a parents."""
import json,re,sys
SRC=sys.argv[1] if len(sys.argv)>1 else "/tmp/go-basic.obo"
OUT="/Users/kky/biomate-review/docs/20260912_onprem_llm/midtrain_corpus/go_corpus.jsonl"
terms=[]; cur=None
for line in open(SRC):
    line=line.rstrip("\n")
    if line=="[Term]": cur={"is_a":[]}; terms.append(cur); continue
    if cur is None: continue
    if line.startswith("id: "): cur["id"]=line[4:]
    elif line.startswith("name: "): cur["name"]=line[6:]
    elif line.startswith("namespace: "): cur["ns"]=line[11:].replace("_"," ")
    elif line.startswith("def: "):
        m=re.search(r'"([^"]+)"',line); cur["def"]=m.group(1) if m else ""
    elif line.startswith("is_a: "): cur["is_a"].append(line[6:].split("!")[-1].strip() if "!" in line else line[6:].strip())
    elif line.startswith("is_obsolete: true"): cur["obs"]=True
name={t.get("id"):t.get("name") for t in terms if t.get("id")}
n=0
with open(OUT,"w") as f:
    for t in terms:
        if t.get("obs") or not t.get("name") or len(t.get("def",""))<15: continue
        parents=[p for p in t["is_a"]]
        txt=f"GO {t.get('ns','')}: {t['name']} — {t['def']}"
        if parents: txt+=f" It is a kind of {', '.join(parents[:3])}."
        f.write(json.dumps({"text":txt,"source":"go","id":t.get("id")})+"\n"); n+=1
chars=sum(len(json.loads(l)['text']) for l in open(OUT))
print(f"GO corpus: {n} terms, ~{chars//4/1e6:.1f}M tokens")
