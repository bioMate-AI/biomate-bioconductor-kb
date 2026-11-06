import json, gzip, urllib.request, gemmi, collections, sys, os, time
from concurrent.futures import ThreadPoolExecutor
hits=json.load(open("closure_hits.json"))
gq={e["rcsb_id"]:e for e in json.load(open("pool_graphql.json"))}
by_entry=collections.defaultdict(list)
for h in hits: by_entry[h["entity"].split("_")[0]].append(h)
MIN_REC=40  # receptor must be a >=40-residue protein entity (judgment call)
STD={"ALA","ARG","ASN","ASP","CYS","GLN","GLU","GLY","HIS","ILE","LEU","LYS","MET","PHE","PRO","SER","THR","TRP","TYR","VAL"}
os.makedirs("cache",exist_ok=True)
def one(pdb):
    fn=f"cache/{pdb}.json"
    if os.path.exists(fn): return json.load(open(fn))
    for k in range(4):
        try:
            raw=urllib.request.urlopen(f"https://files.rcsb.org/download/{pdb}.cif.gz",timeout=120).read()
            break
        except Exception as e: err=e; time.sleep(3)
    else: return {"pdb":pdb,"error":str(err)}
    st=gemmi.read_structure_from_string(gzip.decompress(raw).decode(),format=gemmi.CoorFormat.Mmcif) if False else gemmi.make_structure_from_block(gemmi.cif.read_string(gzip.decompress(raw).decode()).sole_block())
    st.setup_entities(); st.remove_hydrogens()
    m=st[0]
    ent_by_chain={}
    for ch in m:
        for r in ch:
            if r.entity_id: ent_by_chain[ch.name]=r.entity_id; break
    ents={e.name:e for e in st.entities}
    def seq3(e): return list(e.full_sequence)
    ns=gemmi.NeighborSearch(m,gemmi.UnitCell(),6).populate()
    res=[]
    for h in by_entry[pdb]:
        auth=h["auth"]; pc=m.find_chain(auth)
        if pc is None: continue
        contacts=collections.Counter(); pres=set(); rent={} 
        # receptor protein chains: entity polymer protein with length>25
        for r in pc:
            for a in r:
                for mk in ns.find_atoms(a.pos,'\0',radius=5.0):
                    cra=mk.to_cra(m)
                    cn=cra.chain.name
                    if cn==auth: continue
                    eid=cra.residue.entity_id; en=ents.get(eid)
                    if en is None or en.polymer_type!=gemmi.PolymerType.PeptideL: continue
                    if len(en.full_sequence)<MIN_REC: continue
                    if cra.atom.pos.dist(a.pos)>5.0: continue
                    contacts[cn]+=1; rent[cn]=eid; pres.add(r.seqid.num)
        # peptide composition
        pe=ents.get(pc[0].entity_id)
        comps=seq3(pe) if pe else []
        res.append(dict(h, pdb=pdb, n_iface_res=len(pres), rec_chain_contacts=dict(contacts),
            pep_comps=comps,
            rec_seqs={cn:[gemmi.find_tabulated_residue(x).one_letter_code.upper() if gemmi.find_tabulated_residue(x) else 'X' for x in seq3(ents[rent[cn]])] for cn in contacts}, 
            rec_entity=rent,
            rec_desc={}))
    out={"pdb":pdb,"res":res}
    json.dump(out,open(fn,"w"))
    return out
if __name__=="__main__":
    ids=sorted(by_entry)
    if len(sys.argv)>1: ids=ids[:int(sys.argv[1])]
    with ThreadPoolExecutor(8) as ex:
        out=list(ex.map(one,ids))
    errs=[o for o in out if "error" in o]; print("done",len(out),"errors",len(errs),errs[:3])
