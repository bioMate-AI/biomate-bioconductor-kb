"""Per-deployment tool-scope manifest (local-deploy topic #4). Given the ENABLED domains (or an explicit
workflow list), compute the exact set of workflows + required tools (union of workflows.tools_used) that a
customer install needs -> the tool ALLOW-LIST to enforce at run time + the container MIRROR-LIST to seed
into their private registry. Avoids shipping all 2,600 workflows / all biocontainers.

  python export_deployment_manifest.py --domains transcriptomics,drug_discovery --out manifest.json

Note: tools.container_info.image is empty in the DB today -> we emit tool NAMES; image-URI resolution
(quay.io/biocontainers or the nf-core module `container` directive) is a documented follow-up."""
import sqlite3, os, json, argparse, collections
REPO="/Users/kky/biomate-review"; DB=f"{REPO}/backend/database/galaxy_ai_tools.db"
# tools that typically require a per-user/site license (gate separately)
LICENSE_TOOLS={"amber","pmemd","schrodinger","glide","gaussian","matlab","dnastar","clcbio","geneious"}

def parse_json_list(s):
    try:
        v=json.loads(s)
        return [str(x).strip() for x in v if str(x).strip()] if isinstance(v,list) else []
    except Exception: return []

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--domains",default="",help="comma list of enabled domains")
    ap.add_argument("--workflows",default="",help="comma list of explicit workflow names (overrides domains)")
    ap.add_argument("--out",default=f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/deployment_manifest.json")
    a=ap.parse_args()
    c=sqlite3.connect(f"file:{DB}?mode=ro",uri=True); c.row_factory=sqlite3.Row
    domains=set(d.strip() for d in a.domains.split(",") if d.strip())
    wf_filter=set(w.strip() for w in a.workflows.split(",") if w.strip())

    wfs=[]; tools=collections.Counter()
    for r in c.execute("select name,domain,tools_used from workflows"):
        if wf_filter:
            if r["name"] not in wf_filter: continue
        elif domains and r["domain"] not in domains: continue
        wfs.append(r["name"])
        for t in parse_json_list(r["tools_used"] or "[]"): tools[t.lower()]+=1
    # resolve container images where available
    img={}
    for r in c.execute("select name,container_info from tools where container_info is not null"):
        try: ci=json.loads(r["container_info"])
        except: continue
        if isinstance(ci,dict) and ci.get("image"): img[(r["name"] or "").lower()]=ci["image"]

    tool_list=sorted(tools)
    resolved={t:img[t] for t in tool_list if t in img}
    unresolved=[t for t in tool_list if t not in img]           # need image-URI resolution (nf-core/biocontainers)
    licensed=[t for t in tool_list if any(k in t for k in LICENSE_TOOLS)]
    manifest={"scope":{"domains":sorted(domains) or "ALL","explicit_workflows":sorted(wf_filter) or None},
              "n_workflows":len(wfs),"n_tools":len(tool_list),
              "tool_allowlist":tool_list,
              "container_mirror_resolved":resolved,
              "tools_needing_image_resolution":unresolved,
              "license_gated_tools":licensed,
              "workflows":sorted(wfs)[:2000]}
    os.makedirs(os.path.dirname(a.out),exist_ok=True); json.dump(manifest,open(a.out,"w"),indent=1)
    print(f"DEPLOYMENT MANIFEST: domains={sorted(domains) or 'ALL'} -> {len(wfs)} workflows, {len(tool_list)} tools")
    print(f"  container images resolved: {len(resolved)} | need resolution: {len(unresolved)} | license-gated: {licensed}")
    print(f"  -> {a.out}")

if __name__=="__main__": raise SystemExit(main())
