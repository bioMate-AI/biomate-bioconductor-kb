"""Step 1a: fetch Pfam cross-references + gene names for every UniProt accession in the cyclic rows of binding_affinity_v1 (UniProt REST).
Output data/uniprot_pfam.tsv (accession, pfam ids, gene names, organism id). Deterministic given UniProt release at fetch time; the fetch date is recorded in data/uniprot_fetch.json."""
import pandas as pd, requests, json, time, datetime, os, io, re
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "../../.."))
d = pd.read_csv(f"{ROOT}/data/raw/binding_affinity/binding_affinity_v1.csv", low_memory=False, usecols=["target_uniprot", "cyclic_bool"])
d = d[(d.cyclic_bool == True) & d.target_uniprot.notna()]
acc = sorted({a.strip() for s in d.target_uniprot.astype(str) for a in re.split(r"[,\s;]+", s) if a.strip()})
print("accessions", len(acc))
out = []
for i in range(0, len(acc), 60):
    q = "(" + " OR ".join(f"accession:{a}" for a in acc[i:i + 60]) + ")"
    for attempt in range(4):
        r = requests.get("https://rest.uniprot.org/uniprotkb/search", params=dict(query=q, fields="accession,xref_pfam,gene_names,organism_id,protein_name", format="tsv", size=100), timeout=60)
        if r.status_code == 200: break
        time.sleep(3)
    r.raise_for_status()
    out.append(pd.read_csv(io.StringIO(r.text), sep="\t"))
def fetch(ids):
    q = "(" + " OR ".join(f"accession:{a}" for a in ids) + ")"
    r = requests.get("https://rest.uniprot.org/uniprotkb/search", params=dict(query=q, fields="accession,xref_pfam,gene_names,organism_id,protein_name", format="tsv", size=100), timeout=60)
    r.raise_for_status(); return pd.read_csv(io.StringIO(r.text), sep="\t")
df = pd.concat(out).drop_duplicates("Entry")
for step in (10, 1):                      # a batch of 60 silently returns header-only for some accession sets: retry smaller until every accession is resolved or proven absent
    miss = sorted(set(acc) - set(df.Entry))
    for i in range(0, len(miss), step):
        try: df = pd.concat([df, fetch(miss[i:i + step])]).drop_duplicates("Entry")
        except Exception as e: print("fail", miss[i:i + step][:2], e)
df.to_csv(f"{HERE}/data/uniprot_pfam.tsv", sep="\t", index=False)
missing = sorted(set(acc) - set(df.Entry))
json.dump(dict(fetched_utc=datetime.datetime.now(datetime.timezone.utc).isoformat() + "Z", n_requested=len(acc), n_returned=int(len(df)), missing=missing), open(f"{HERE}/data/uniprot_fetch.json", "w"), indent=1)
print("returned", len(df), "missing", len(missing), missing[:10])
