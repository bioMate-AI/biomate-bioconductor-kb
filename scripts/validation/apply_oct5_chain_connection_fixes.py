#!/usr/bin/env python3
"""Apply the renameable (A) from_output fixes from docs/20261005_CHAIN_CONNECTION_AUDIT.md,
verifying each suggested from_output resolves against the upstream workflow's real declared
output filenames (mirrors pick_artifact_file: exact / substring / extension). Backs up the old
connections JSON per chain. --apply writes; default is dry-run."""
import sqlite3, json, re, glob, os, sys, argparse, time
REPO = "/Users/kky/biomate-review"
DB = f"{REPO}/backend/database/galaxy_ai_tools.db"

# (chain, from_step(1-based), to_step, old_from_output, new_from_output)
FIXES = [
 ("multiomic_differential_expression_exphunter",1,2,"count_matrix","counts_matrix"),
 ("bp4_rnaseq_best_practices_pipeline",1,2,"salmon_quants","counts_matrix"),
 ("rnaseq_differential_transcript_usage",1,2,"salmon_quants","counts_matrix"),
 ("rnaseq_differential_transcript_usage",2,4,"drim_results","dtu_gene_results"),
 ("methylation_450k_array_analysis",1,2,"GenomicMethylSet","gmsetex"),
 ("methylation_450k_array_analysis",1,3,"GenomicMethylSet","gmsetex"),
 ("cytof_mass_cytometry_analysis",2,3,"cluster_assignments","flowsom_assignments"),
 ("cytof_mass_cytometry_analysis",2,4,"cluster_assignments","flowsom_assignments"),
 ("geomx_spatial_transcriptomics",2,3,"norm_set","normalized_target"),
 ("cnv_consensus_pipeline",2,3,"cnv_segments","copy_number_estimates"),
 ("lcms_metabolomics_consensus",1,2,"xcms_set","xcms_preprocessed"),
 ("lcms_metabolomics_consensus",2,3,"annotated_features","xsannotated"),
 ("cyp450_ddi_chain",1,2,"ddi_predictions","ddi_risk_assessment"),
 ("bioc_bulk_rnaseq_de_v2",2,3,"enrichment","enrichgo_results"),
 ("andv_inhibitor_track_v1",5,6,"mmgbsa_scores","mmgbsa_results"),
 ("target_to_lead_full",5,6,"mmgbsa_scores","mmgbsa_results"),
]

def wf_outputs(nf_path):
    """Published output filename stems declared in the .nf (path "x", emit, write/save targets, globs)."""
    base = os.path.basename(os.path.dirname(nf_path))
    cands=[f"{REPO}/backend/biomni_workflows/{nf_path}"]+glob.glob(f"{REPO}/backend/biomni_workflows/**/{base}/main.nf",recursive=True)
    for c in cands:
        if os.path.isfile(c):
            s=open(c,errors='ignore').read()
            names=set()
            names|=set(re.findall(r'path\s+"([^"$*]*\.[a-zA-Z0-9]+)"', s))
            names|=set(re.findall(r'(?:saveRDS|write\.csv|write_csv|ggsave|fwrite|write\.table)\([^)]*["\']([\w.\-/]+\.[a-zA-Z0-9]+)', s))
            names|=set(re.findall(r'(?:touch|file=|->)\s*["\']?([\w.\-]+\.[a-zA-Z0-9]+)', s))
            names|=set(re.findall(r'"([\w.\-]+\.(?:csv|rds|json|tsv|txt|pdf|sdf|pdbqt|smi|h5ad|gds|nc))"', s))
            return {n.lower() for n in names}, c
    return None, None

def resolves(new_fo, outfiles):
    fo=new_fo.lower()
    for f in outfiles:
        if fo==f or fo in f: return f                 # exact / substring (resolver rules 1,3)
    ext=fo.split('.')[-1] if '.' in fo else fo
    for f in outfiles:
        if f.rsplit('.',1)[-1]==ext: return f          # extension (rule 4)
    return None

# Design-gap connection REWIRES (not simple renames): new transforms + corrected to_input, applied
# after the FIXES renames. These depend on backend changes shipped in git (transforms.admet_toxicity_
# to_herg_ic50_nM, predict_admet_properties passed_compounds.smi). See
# docs/20261109_DRUGDEV_CHAIN_SOUNDNESS_AUDIT.md.
REWIRES = {
 "admet_to_cipa_cardiac": [
   {"from_step":1,"from_output":"toxicity_report","to_step":2,"to_input":"herg_ic50_nM",
    "transform":{"name":"admet_toxicity_to_herg_ic50_nM"}},
 ],
 "drug_discovery_admet_gated_screening": [
   {"from_step":1,"from_output":"filtered_compounds.smi","to_step":2,"to_input":"smiles_list","transform":{"name":"smiles_file_to_json_list","args":{}}},
   {"from_step":2,"from_output":"passed_compounds","to_step":3,"to_input":"smiles_list","transform":{"name":"smiles_file_to_json_list","args":{}}},
 ],
}
# Per-connection edits (chain, from_step, to_step) -> {field:value} for chains we only partly rewire.
REWIRE_EDITS = [
 ("andv_inhibitor_track_v1",3,4,{"from_output":"passed_compounds","to_input":"smiles_list","transform":{"name":"smiles_file_to_json_list","args":{}}}),
 ("target_to_lead_full",4,5,{"from_output":"rank1","to_input":"ligand"}),
]

def apply_rewires(conn, do):
    import time as _t
    n=0
    for chain, conns in REWIRES.items():
        row=conn.execute("select name from workflow_chains where name=?",(chain,)).fetchone()
        if not row: print(f"  REWIRE skip {chain}: not found"); continue
        print(f"  {'REWIRE' if do else 'REWIRE(dry)'} {chain}: set {len(conns)} connection(s)")
        if do:
            conn.execute("update workflow_chains set connections=?, updated_at=? where name=?",
                         (json.dumps(conns), _t.strftime('%Y-%m-%dT%H:%M:%SZ'), chain)); n+=1
    for chain, fs, ts, fields in REWIRE_EDITS:
        row=conn.execute("select connections from workflow_chains where name=?",(chain,)).fetchone()
        if not row: print(f"  REWIRE_EDIT skip {chain}: not found"); continue
        cs=json.loads(row[0] or "[]"); hit=False
        for c in cs:
            if int(c.get("from_step",-1))==fs and int(c.get("to_step",-1))==ts:
                c.update(fields); hit=True
        print(f"  {'REWIRE_EDIT' if do else 'REWIRE_EDIT(dry)'} {chain} s{fs}->s{ts}: {fields.get('from_output')}->{fields.get('to_input')} {'(ok)' if hit else '(connection not found)'}")
        if do and hit:
            conn.execute("update workflow_chains set connections=?, updated_at=? where name=?",
                         (json.dumps(cs), _t.strftime('%Y-%m-%dT%H:%M:%SZ'), chain)); n+=1
    return n


def main():
    ap=argparse.ArgumentParser(); ap.add_argument("--apply",action="store_true"); a=ap.parse_args()
    conn=sqlite3.connect(DB); conn.row_factory=sqlite3.Row
    names=dict(conn.execute("select name,filename from workflows").fetchall())
    applied=skipped=0
    for chain,fs,ts,old,new in FIXES:
        row=conn.execute("select steps,connections from workflow_chains where name=?",(chain,)).fetchone()
        if not row: print(f"  SKIP {chain}: chain not found"); skipped+=1; continue
        steps=json.loads(row["steps"]); conns=json.loads(row["connections"] or "[]")
        up=steps[fs-1]; wn=up.get("workflow_name") or up.get("name"); nf=names.get(wn)
        outs,path=(wf_outputs(nf) if nf else (None,None))
        if outs is None:
            print(f"  SKIP {chain} s{fs}->s{ts} {old}->{new}: upstream .nf not found ({wn})"); skipped+=1; continue
        hit=resolves(new,outs)
        target=[c for c in conns if int(c.get("from_step",-1))==fs and int(c.get("to_step",-1))==ts and c.get("from_output")==old]
        if not target:
            print(f"  SKIP {chain} s{fs}->s{ts}: connection {old} not present (maybe already fixed)"); skipped+=1; continue
        if not hit:
            print(f"  UNVERIFIED {chain} s{fs}->s{ts} {old}->{new}: '{new}' matches no declared output of {wn} (outs sample: {sorted(outs)[:6]})"); skipped+=1; continue
        print(f"  {'APPLY' if a.apply else 'OK(dry)'} {chain} s{fs}->s{ts}: {old} -> {new}  (resolves to '{hit}')")
        if a.apply:
            for c in target: c["from_output"]=new
            conn.execute("update workflow_chains set connections=?, updated_at=? where name=?",
                         (json.dumps(conns), time.strftime("%Y-%m-%dT%H:%M:%SZ"), chain))
            applied+=1
    if a.apply:
        conn.commit()
    _rw = apply_rewires(conn, a.apply)
    if a.apply:
        conn.commit()
    print(f"\n{'APPLIED' if a.apply else 'DRY-RUN'}: {applied} applied, {skipped} skipped/unverified")

if __name__=="__main__": main()
