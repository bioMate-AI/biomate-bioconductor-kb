import argparse, json, re, time, urllib.parse, urllib.request, xml.etree.ElementTree as ET
E = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils"
def get(url, timeout=90):
    for a in range(5):
        try: return urllib.request.urlopen(url, timeout=timeout).read()
        except Exception: time.sleep(3*(a+1))
    return b""
def main():
    ap=argparse.ArgumentParser(); ap.add_argument("--out",required=True); ap.add_argument("--max-tokens",type=int,default=3_000_000_000); ap.add_argument("--batch",type=int,default=100)
    a=ap.parse_args(); toks=n=0
    with open(a.out,"w") as fo:
        retstart=0
        while toks < a.max_tokens:
            q=urllib.parse.urlencode({"db":"pmc","term":"open access[filter]","retmax":2000,"retstart":retstart})
            ids=re.findall(r"<Id>(\d+)</Id>", get(f"{E}/esearch.fcgi?{q}").decode("utf-8","ignore"))
            if not ids: break
            retstart+=len(ids)
            for i in range(0,len(ids),a.batch):
                xml=get(f"{E}/efetch.fcgi?db=pmc&id={','.join(ids[i:i+a.batch])}&rettype=xml").decode("utf-8","ignore")
                try:
                    for _,el in ET.iterparse(__import__("io").BytesIO(xml.encode()), events=("end",)):
                        if el.tag.endswith("article"):
                            body=" ".join(t for t in el.itertext()); body=re.sub(r"\s+"," ",body).strip()
                            if len(body)>500:
                                fo.write(json.dumps({"text":body[:20000],"source":"pmc_fulltext"})+"\n"); n+=1; toks+=len(body)//4
                            el.clear()
                except Exception: pass
                time.sleep(0.4)
                if toks>=a.max_tokens: break
            print(f"  pmc {n} articles ~{toks:,} tok",flush=True)
    print(f"PMC FULLTEXT DONE: {n} articles ~{toks:,} tok -> {a.out}",flush=True)
if __name__=="__main__": raise SystemExit(main())
