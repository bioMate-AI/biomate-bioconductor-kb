import requests, json, sys, time
from concurrent.futures import ThreadPoolExecutor
G="https://data.rcsb.org/graphql"
Q="""query($ids:[String!]!){polymer_entities(entity_ids:$ids){rcsb_id
 entity_poly{pdbx_seq_one_letter_code pdbx_seq_one_letter_code_can rcsb_sample_sequence_length type}
 rcsb_polymer_entity{pdbx_description}
 rcsb_polymer_entity_container_identifiers{entry_id entity_id asym_ids auth_asym_ids}
 polymer_entity_instances{rcsb_polymer_entity_instance_container_identifiers{asym_id auth_asym_id}
  rcsb_polymer_struct_conn{connect_type dist_value id
   connect_target{label_asym_id label_atom_id label_comp_id label_seq_id symmetry}
   connect_partner{label_asym_id label_atom_id label_comp_id label_seq_id symmetry}}}
 entry{rcsb_accession_info{deposit_date initial_release_date} rcsb_entry_info{resolution_combined experimental_method polymer_entity_count_protein} }}}"""
def fetch(ids):
    for k in range(4):
        try:
            r=requests.post(G,json={"query":Q,"variables":{"ids":ids}},timeout=180)
            r.raise_for_status(); j=r.json()
            if "errors" in j: raise RuntimeError(str(j["errors"])[:300])
            return j["data"]["polymer_entities"]
        except Exception as e:
            err=e; time.sleep(3)
    print("FAIL",ids[:2],err,file=sys.stderr); return []
if __name__=="__main__":
    ents=json.load(open("pool_entities_res.json"))
    ents=ents if len(sys.argv)<2 else ents[:int(sys.argv[1])]
    chunks=[ents[i:i+60] for i in range(0,len(ents),60)]
    out=[]
    with ThreadPoolExecutor(6) as ex:
        for i,r in enumerate(ex.map(fetch,chunks)):
            out+=r
            if i%20==0: print(i,len(chunks),len(out),flush=True)
    json.dump(out,open("pool_graphql.json","w"))
    print(len(out), len(ents))
