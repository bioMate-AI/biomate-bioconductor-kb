import json, re, time, random, urllib.parse, urllib.request
random.seed(11)
REPO="/Users/kky/biomate-review"
EUTILS="https://eutils.ncbi.nlm.nih.gov/entrez/eutils"
def get(url, params):
    u=url+"?"+urllib.parse.urlencode(params)
    for _ in range(4):
        try: return urllib.request.urlopen(u,timeout=40).read().decode()
        except Exception: time.sleep(1.0)
    return ""
# curated: pipeline -> GEO search term (DataSet Type + keywords). Real assay -> real pipeline.
ASSAYS = {
 "nf-core/rnaseq":     'expression profiling by high throughput sequencing[DataSet Type] AND gse[Entry Type] NOT single cell[All Fields]',
 "nf-core/scrnaseq":   'expression profiling by high throughput sequencing[DataSet Type] AND gse[Entry Type] AND (single cell RNA[All Fields] OR scRNA-seq[All Fields])',
 "nf-core/chipseq":    'genome binding/occupancy profiling by high throughput sequencing[DataSet Type] AND gse[Entry Type] AND ChIP-Seq[All Fields] NOT ATAC[All Fields]',
 "nf-core/atacseq":    'genome binding/occupancy profiling by high throughput sequencing[DataSet Type] AND gse[Entry Type] AND ATAC-Seq[All Fields]',
 "nf-core/cutandrun":  'gse[Entry Type] AND (CUT&RUN[All Fields] OR CUT&Tag[All Fields])',
 "nf-core/methylseq":  'methylation profiling by high throughput sequencing[DataSet Type] AND gse[Entry Type] AND (bisulfite[All Fields] OR WGBS[All Fields] OR RRBS[All Fields])',
 "nf-core/sarek":      'gse[Entry Type] AND high throughput sequencing[All Fields] AND (whole genome sequencing[All Fields] OR whole exome sequencing[All Fields] OR somatic mutation[All Fields] OR variant calling[All Fields])',
 "nf-core/smrnaseq":   'non coding rna profiling by high throughput sequencing[DataSet Type] AND gse[Entry Type] AND (microRNA[All Fields] OR small RNA[All Fields] OR miRNA[All Fields])',
 "nf-core/ampliseq":   'gse[Entry Type] AND (16S rRNA[All Fields] OR amplicon[All Fields] OR microbiome[All Fields]) AND high throughput sequencing[All Fields]',
 "nf-core/taxprofiler":'gse[Entry Type] AND (metagenomic[All Fields] OR shotgun metagenom[All Fields]) AND high throughput sequencing[All Fields]',
 "nf-core/hic":        'gse[Entry Type] AND (Hi-C[All Fields] OR chromosome conformation[All Fields])',
 "nf-core/spatialvi":  'gse[Entry Type] AND (spatial transcriptom[All Fields] OR Visium[All Fields])',
 "nf-core/rnafusion":  'gse[Entry Type] AND (gene fusion[All Fields] OR fusion transcript[All Fields]) AND RNA[All Fields]',
 "nf-core/mag":        'gse[Entry Type] AND (metagenome assembled[All Fields] OR metagenome assembly[All Fields])',
 "nf-core/nanoseq":    'gse[Entry Type] AND (nanopore[All Fields] OR oxford nanopore[All Fields])',
}
PER=500
episodes=[]
for wf,term in ASSAYS.items():
    r=get(EUTILS+"/esearch.fcgi", {"db":"gds","term":term,"retmax":PER,"retmode":"json"})
    try: ids=json.loads(r)["esearchresult"].get("idlist",[])
    except Exception: ids=[]
    time.sleep(0.4)
    # esummary in batches of 100
    recs={}
    for i in range(0,len(ids),100):
        s=get(EUTILS+"/esummary.fcgi", {"db":"gds","id":",".join(ids[i:i+100]),"retmode":"json"})
        try: recs.update(json.loads(s).get("result",{})); 
        except Exception: pass
        time.sleep(0.4)
    cnt=0
    for uid in recs.get("uids",[]):
        x=recs[uid]; title=(x.get("title") or "").strip(); summ=(x.get("summary") or "").strip(); tax=(x.get("taxon") or "").strip()
        if len(summ)<60: continue
        query=f"{title}. Organism: {tax}. {summ}"[:900]
        episodes.append({"query":query,"correct_workflow":wf,"assay_term":wf,"taxon":tax,"geo_uid":uid})
        cnt+=1
    print(f"{wf}: {cnt} real studies")
print("total real episodes:", len(episodes))
# save raw labeled studies
out=f"{REPO}/docs/20260912_onprem_llm/routing_data_v1"
import os; os.makedirs(out,exist_ok=True)
open(f"{out}/real_studies_labeled.jsonl","w").write("\n".join(json.dumps(e) for e in episodes))
print("wrote real_studies_labeled.jsonl")
