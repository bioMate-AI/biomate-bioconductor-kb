"""Detection of macrocyclic peptides from RCSB rcsb_polymer_struct_conn records."""
import json, collections
MIN_SEP=3
def classify_edge(ct, a1, a2, c1, c2):
    if "disulfide" in ct: return "disulfide"
    at={a1,a2}
    if at=={"C","N"}: return "head_to_tail_amide"   # refined in caller (terminal check)
    if "S" in a1[:1] and "S" in a2[:1]: return "disulfide"
    if a1.startswith("S") or a2.startswith("S"): return "thioether"
    if a1.startswith("N") or a2.startswith("N") or a1.startswith("O") or a2.startswith("O"): return "lactam_isopeptide_ester"
    return "carbon_carbon_staple"
def instance_closures(conns, asym, L):
    edges={}
    for c in conns or []:
        ct=c["connect_type"]
        if not ("disulfide" in ct or ct=="covalent bond"): continue
        t,p=c["connect_target"],c["connect_partner"]
        if t["label_asym_id"]!=asym or p["label_asym_id"]!=asym: continue
        if t.get("symmetry") not in (None,"1_555") or p.get("symmetry") not in (None,"1_555"): continue
        i,j=t["label_seq_id"],p["label_seq_id"]
        if i is None or j is None or i==j: continue
        a,b=sorted((i,j))
        if b-a<MIN_SEP: continue
        a1,a2=(t["label_atom_id"],p["label_atom_id"]) if i<j else (p["label_atom_id"],t["label_atom_id"])
        edges[(a,b)]=(classify_edge(ct,a1,a2,t["label_comp_id"],p["label_comp_id"]),a1,a2,
                      t["label_comp_id"] if i<j else p["label_comp_id"], p["label_comp_id"] if i<j else t["label_comp_id"], c.get("dist_value"))
    return edges
def interchain_covalent(conns, asym):
    """True if this peptide chain is covalently tied (disulfide/covalent bond) to a DIFFERENT polymer chain
    (e.g. insulin A chain-B chain). Such chains are subunits of a covalent protein, not bound ligands."""
    for c in conns or []:
        ct=c["connect_type"]
        if not ("disulfide" in ct or ct=="covalent bond"): continue
        t,p=c["connect_target"],c["connect_partner"]
        if (t["label_asym_id"]==asym) != (p["label_asym_id"]==asym): return True
    return False
def summarize(edges,L):
    if not edges: return None
    kinds=[]
    for (a,b),(k,*_) in edges.items():
        if k=="head_to_tail_amide" and not (a<=2 and b>=L-1): k="lactam_isopeptide_ester"
        kinds.append(k)
    n=len(kinds); s="+".join(sorted(set(kinds)))
    ring=("monocyclic" if n==1 else "bicyclic" if n==2 else "polycyclic")
    return {"n_closures":n,"closure_types":s,"ring_class":ring,"closures":[[a,b,*v[:5]] for (a,b),v in edges.items()]}
if __name__=="__main__":
    d=json.load(open("pool_graphql.json"))
    hits=[]; 
    for e in d:
        L=e["entity_poly"]["rcsb_sample_sequence_length"]
        for inst in e["polymer_entity_instances"]:
            ids=inst["rcsb_polymer_entity_instance_container_identifiers"]
            ed=instance_closures(inst["rcsb_polymer_struct_conn"],ids["asym_id"],L)
            s=summarize(ed,L)
            if s:
                hits.append(dict(entity=e["rcsb_id"],asym=ids["asym_id"],auth=ids["auth_asym_id"],L=L,interchain_cov=interchain_covalent(inst["rcsb_polymer_struct_conn"],ids["asym_id"]),**s))
    print("instances w/ closure",len(hits),"entries",len({h['entity'].split('_')[0] for h in hits}))
    print(collections.Counter(h["closure_types"] for h in hits).most_common(12))
    print(collections.Counter(h["ring_class"] for h in hits))
    json.dump(hits,open("closure_hits.json","w"))
