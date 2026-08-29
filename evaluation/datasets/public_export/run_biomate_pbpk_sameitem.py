import json, urllib.request, urllib.error, time
DEV="https://dev-public.biomate.ai"; TOK="biomate-e2e-bypass-token-dev-only"
BASE="/Users/kky/biomate/evaluation/datasets/public_export/pbpk_benchmark/data.jsonl"
def req(m,p,b=None,t=90):
    d=json.dumps(b).encode() if b is not None else None
    r=urllib.request.Request(f"{DEV}{p}",data=d,method=m,headers={"Content-Type":"application/json","x-e2e-test-token":TOK})
    try:
        with urllib.request.urlopen(r,timeout=t) as x: return x.status,json.loads(x.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        try: return e.code,json.loads(e.read().decode())
        except: return e.code,{"_err":"http"}
    except Exception as e: return 0,{"_err":str(e)[:120]}
def geturl(u):
    try:
        with urllib.request.urlopen(u,timeout=60) as r: return r.read().decode()
    except: return None
_,sr=req("POST","/api/workflows/search",{"query":"pbpk_simulation","limit":1,"defer_param_prefill":True})
wf=sr.get("workflow_ga") or sr.get("workflow")
rows=[json.loads(l) for l in open(BASE)]
runs={}
for r in rows:
    inp=r["inputs"]; auc=round(r["reference"]["AUC_uM_h"]*inp["MW"]/1000.0,4)
    params={"SMILES":r["smiles"],"MW":str(inp["MW"]),"logP":str(inp["logP"]),"pKa":str(inp["pKa"]),
      "fu_plasma":str(inp["fu_plasma"]),"CLint_uL_min_mg":str(inp["CLint_uL_min_mg"]),
      "renal_CL_mL_min":str(inp["renal_CL_mL_min"]),"dose_mg":str(r["dose_mg"]),"dose_route":r["route"],
      "auc_observed_ug_h_mL":str(auc)}
    wf2=dict(wf); wf2["parameters"]={**(wf.get("parameters") or {}),**params}
    st,er=req("POST","/api/workflows/execute",{"workflowDefinition":wf2,"params":params})
    rid=er.get("runId") or er.get("run_id") or er.get("id")
    runs[r["id"]]={"rid":rid,"ref":r["reference"]["Cmax_uM"],"mw":inp["MW"],"name":r["name"]}
    print(f"submit {r['id']} {r['name']}: run_id={rid} status={er.get('status')} {'' if rid else ('ERR '+str(er)[:90])}",flush=True)
pending={i:d for i,d in runs.items() if d["rid"]}; t0=time.time()
TERM={"completed","succeeded","failed","error","timed_out","cancelled"}
while pending and time.time()-t0<2400:
    time.sleep=__import__("time").sleep; time.sleep(20)
    for i,d in list(pending.items()):
        _,stt=req("GET",f"/api/workflows/runs/{d['rid']}/status")
        s=(stt.get("status") or stt.get("state") or "").lower()
        if s in TERM:
            d["status"]=s
            if s in ("completed","succeeded"):
                import subprocess as _sp
                _,of=req("GET",f"/api/workflows/runs/{d['rid']}/outputs")
                nca=next((o for o in of if o.get("name")=="nca_parameters.json"),None) if isinstance(of,list) else None
                if nca:
                    txt=_sp.run(["rclone","cat","biomate_s3:"+nca["s3_uri"].replace("s3://","")],capture_output=True,text=True,timeout=60).stdout
                    try: j=json.loads(txt); d["nca"]=j; d["nca_keys"]=list(j.keys())
                    except: d["nca_txt"]=str(txt)[:150]
            print(f"  DONE {i}: {s} nca_keys={d.get('nca_keys')}",flush=True); del pending[i]
    print(f"  ...{len(pending)} pending ({int(time.time()-t0)}s)",flush=True)
json.dump(runs,open("/private/tmp/claude-501/-Users-kky-biomate/a28478f2-270d-4a8e-ae0c-56859df23dc6/scratchpad/pbpk_runs.json","w"),indent=1,default=str)
print("WROTE pbpk_runs.json",flush=True)
