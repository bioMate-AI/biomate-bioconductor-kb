import requests, json
S="https://search.rcsb.org/rcsbsearch/v2/query"
def term(a,o,v): return {"type":"terminal","service":"text","parameters":{"attribute":a,"operator":o,"value":v}}
def run(nodes, rt="polymer_entity", count=True):
    q={"query":{"type":"group","logical_operator":"and","nodes":nodes},"return_type":rt,"request_options":{"return_all_hits":True}}
    r=requests.post(S,json=q,timeout=120); 
    if r.status_code!=200: print(r.status_code,r.text[:300]); return None
    return [h["identifier"] for h in r.json()["result_set"]]
base=[term("entity_poly.rcsb_entity_polymer_type","exact_match","Protein"),
      term("entity_poly.rcsb_sample_sequence_length","range",{"from":5,"to":25,"include_lower":True,"include_upper":True}),
      term("rcsb_assembly_info.polymer_entity_count_protein","greater_or_equal",2)]
ents=run(base)
print(len(ents), len({e.split('_')[0] for e in ents}))
json.dump(ents,open("pool_entities.json","w"))
ents2=run(base+[term("rcsb_entry_info.resolution_combined","less_or_equal",3.5)])
print("res<=3.5",len(ents2), len({e.split('_')[0] for e in ents2}))
json.dump(ents2,open("pool_entities_res.json","w"))
