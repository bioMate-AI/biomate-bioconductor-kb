import json
R = json.load(open("results.json"))
print("CLAIMS"); 
for t, c in R["claims"].items():
    print(t, "best(S2)=", c["best_model_selected_on_S2"], "VERDICT", c["verdict"], c.get("note", ""))
    for s in ["S0", "S1", "S2", "S2b", "S3", "S3b"]:
        if s in c: d = c[s]; print(f"   {s:4s} vs {d['null']:4s} diff {d['point']:+.3f} [{d['ci'][0]:+.3f},{d['ci'][1]:+.3f}] {d['verdict']} (groups {d['n_groups']})")
for t in ["T1", "T2", "T3", "T2_avb6", "T3_avb6"]:
    print("\n##", t)
    for s in ["S0", "S1", "S2", "S2b", "S3", "S3b"]:
        if s in R and t in R[s]:
            o = R[s][t]; print(f" {s} n={o.get('n_rows', o.get('n_pairs', o.get('n_pairs_oriented')))} groups={o['n_groups']} strongest_null={o['strongest_null']}")
            print("    models:", {k: round(v["value"], 3) for k, v in o["models"].items()}); print("    nulls :", {k: round(v["value"], 3) for k, v in o["nulls"].items()})
