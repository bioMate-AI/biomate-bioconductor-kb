"""Step 1: pull ChEMBL activities/assays/documents for human RGD-binding integrin heterodimers.
Raw JSON is cached OUTSIDE the repo (scratchpad). Outputs compact raw-ish tables in data/."""
import json, os, sys, csv
import chembl_fetch as c
TARGETS = {  # chembl id -> short label
 "CHEMBL1907598":"avb3","CHEMBL2096675":"avb5","CHEMBL2111416":"avb6","CHEMBL3430892":"avb8",
 "CHEMBL2111407":"avb1","CHEMBL2095226":"a5b1","CHEMBL2093869":"aIIbb3","CHEMBL6066586":"a8b1",
}
# ambiguous / mixed targets: counted for the record, NOT used
EXCLUDED = {"CHEMBL4106150":"avb3/avb5 mixed","CHEMBL2111425":"a5b1+avb3 group","CHEMBL2111443":"avb3 and aIIbb3 selectivity group",
 "CHEMBL3430893":"aV/a5","CHEMBL6066570":"a5/b6","CHEMBL6066571":"a5/b6/b8","CHEMBL6066568":"a5/b8","CHEMBL3660":"alpha-V single chain",
 "CHEMBL207":"beta-3 single chain","CHEMBL4876":"beta-6 single chain","CHEMBL1905":"beta-1 single chain","CHEMBL2600":"beta-5 single chain","CHEMBL212":"aIIb single chain","CHEMBL3955":"alpha-5 single chain"}
rows = []; counts = {}
for tid, lab in {**TARGETS, **{k: "EXCL:"+v for k, v in EXCLUDED.items()}}.items():
    acts = c.paged(f"/chembl/api/data/activity.json?target_chembl_id={tid}&standard_type__in=IC50,Ki,Kd&limit=1000", "activities")
    counts[tid] = (lab, len(acts)); print(tid, lab, len(acts), flush=True)
    if True:
        for a in acts:
            rows.append({k: a.get(k) for k in ["activity_id","molecule_chembl_id","canonical_smiles","standard_type","standard_relation","standard_value","standard_units","pchembl_value","assay_chembl_id","assay_type","assay_description","document_chembl_id","document_year","document_journal","target_chembl_id","data_validity_comment","potential_duplicate","standard_flag"]} | {"target": lab, "in_scope": tid in TARGETS})
json.dump(counts, open("data/target_activity_counts_raw.json", "w"), indent=1)
docs = sorted({r["document_chembl_id"] for r in rows})
dd = {}
for i in range(0, len(docs), 50):
    d = c.get("/chembl/api/data/document.json?limit=100&document_chembl_id__in=" + ",".join(docs[i:i+50]))
    for x in d["documents"]: dd[x["document_chembl_id"]] = {k: x.get(k) for k in ["doi","pubmed_id","year","journal","title","first_page"]}
json.dump(dd, open("data/documents.json", "w"))
# NOTE: /assay endpoint returned HTTP 500 for batched id__in queries; assay_type/description are taken from the activity records instead.
import pandas as pd
pd.DataFrame(rows).to_pickle(os.environ.get("INTEGRIN_CACHE","/tmp")+"/raw_acts.pkl")
print("done", len(rows), len(docs), len(assays))
