"""Updated candidate sequences v2 — apply the flexible edit-guidelines to fix the v1 flags,
preserving the Tier-1 pharmacophore, then RE-GATE (liability + genus-FTO) to prove each fix."""
import json
from pathlib import Path
from cyclic_llm.knowledge_liability_flags import flag_candidate
import drug_novelty_fto as nf

AVB6_GENUS = {"Trivehexin": "YRGDLAYPK", "avebehexin": "FRGDLAFPK"}

# v2 = v1 with the documented edit applied. 'edit' names the Tier-2 guideline used.
AVB6_V2 = [
 {"id":"AVB6-K-01","helm":"cyclo(F-R-G-D-L-S-W-[dP]-[NMeA])","edit":"(unchanged — v1 PASS/FTO-clean)"},
 {"id":"AVB6-K-02","helm":"cyclo(W-R-G-D-L-T-F-[dP]-[NMeV])","edit":"(unchanged — v1 PASS)"},
 {"id":"AVB6-K-03","helm":"cyclo(Y-R-G-D-L-G-H-[dP]-[NMeL])","edit":"(unchanged — v1 PASS)"},
 {"id":"AVB6-K-04","helm":"cyclo(H-R-G-D-L-A-W-[dP]-[NMeE])","edit":"RENAL: cationic NMeLys -> anionic NMeGlu (lower kidney dose; net +1 -> -1)"},
 {"id":"AVB6-K-05","helm":"cyclo(F-R-G-D-L-I-F-[dP]-[NMeA])","edit":"(unchanged — v1 PASS + extended-affinity)"},
 {"id":"AVB6-K-06","helm":"cyclo(R-G-D-L-Q-F-[dP]-[NMeS]-G)","edit":"(unchanged — v1 PASS)"},
 {"id":"AVB6-K-07","helm":"cyclo([dL]-R-G-D-L-S-F-[dP]-[NMeT])","edit":"(unchanged — v1 PASS)"},
 {"id":"AVB6-K-08","helm":"cyclo(Y-R-G-D-L-I-W-[dP]-[NMeA])","edit":"(unchanged — LEAD: PASS + extended-affinity + FTO-clean)"},
 {"id":"AVB6-K-09","helm":"cyclo(W-R-G-D-L-T-H-[dP]-[NMeE])","edit":"FTO: diversify flanks away from avebehexin FRGDLAFPK (cap F->W, A->T, F->H, +NMeGlu); genus id 0.89 -> target <0.8"},
 {"id":"AVB6-K-10","helm":"cyclo(W-R-G-D-L-S-Y-[dP]-[NMeA])","edit":"RENAL: cationic Lys flank -> neutral Ser (net +1 -> 0); corrects the backwards v1 'Lys tunes clearance'"},
]
PDL1_V2 = [
 {"id":"PDL1-K-01","helm":"cyclo(F-W-L-[dP]-Y-S-[NMeF]-D-T-K)","edit":"(unchanged — v1 PASS)"},
 {"id":"PDL1-K-02","helm":"cyclo(W-L-F-[dP]-I-[NMeL]-S-E-K-G)","edit":"OXIDATION: Met -> Leu (non-oxidisable; prod = Nle isostere)"},
 {"id":"PDL1-K-03","helm":"cyclo(Y-F-[dP]-W-L-[NMeA]-S-D-R-T-G)","edit":"ISOMERISATION: swap Asp-Ser -> Ser-Asp (removes the D-S isoAsp hotspot)"},
 {"id":"PDL1-K-04","helm":"cyclo(F-L-W-[dP]-L-Y-[NMeS]-K-G-D)","edit":"HOLD-FIX: reorder tail K-D-G -> K-G-D (removes fastest Asp-Gly hotspot) + Met->Leu"},
 {"id":"PDL1-K-05","helm":"cyclo(W-Y-F-[dP]-L-[NMeI]-T-E-N-K-S-G)","edit":"(unchanged — v1 PASS)"},
 {"id":"PDL1-K-06","helm":"cyclo(F-W-L-Y-[dP]-L-S-D-K-T)","edit":"OXIDATION: Met -> Leu"},
 {"id":"PDL1-K-07","helm":"cyclo(F-W-[dP]-Y-I-L-[NMeF]-E-R-S)","edit":"(unchanged — v1 PASS)"},
 {"id":"PDL1-K-08","helm":"C-F-W-T-Y-[NMeF]-L-S-D-C (disulfide C1-C10)","edit":"OXIDATION Met->Leu + AGGREGATION: one aromatic Trp-adjacent L->T to lower hydrophobic fraction 0.80 -> 0.70"},
]

def regate(cands, target):
    out=[]
    for c in cands:
        r = flag_candidate(c, target)
        row = {"id":c["id"],"helm":c["helm"],"edit":c["edit"],"tier":r["tier"],
               "net_charge":r.get("net_charge"),"flags":[f"[{f['severity']}] {f['code']}" for f in r["flags"]]}
        if target=="avb6":
            seq="".join(nf_parse(c["helm"]))
            best=max(AVB6_GENUS.items(), key=lambda kv: nf.sequence_identity(seq, kv[1]))
            row["genus_id"]={"vs":best[0],"identity":round(nf.sequence_identity(seq,best[1]),3)}
            row["fto"]="clean" if row["genus_id"]["identity"]<nf.DEFAULT_SEQ_ID_CUTOFF else "OCCUPIED"
        out.append(row)
    return out

def nf_parse(helm):
    from cyclic_llm.knowledge_liability_flags import parse_helm
    res,_,_=parse_helm(helm); return res

for target, cands, outp in [("avb6",AVB6_V2,"results/knowledge_grounded_candidates_v2.json"),
                            ("pdl1",PDL1_V2,"results/knowledge_grounded_pdl1_v2.json")]:
    rows=regate(cands,target)
    print(f"\n===== {target} v2 =====")
    for r in rows:
        extra=f" genus={r['genus_id']['identity']}({r['fto']})" if 'genus_id' in r else ""
        edited = "" if r['edit'].startswith("(unchanged") else "  <EDITED>"
        print(f"  {r['tier']:5s} net{r.get('net_charge',0):+d} {r['id']:11s} {''.join(nf_parse(r['helm'])):12s}{extra}{edited}")
        if not r['edit'].startswith("(unchanged"): print(f"         edit: {r['edit']}")
    tiers={}; [tiers.__setitem__(r['tier'],tiers.get(r['tier'],0)+1) for r in rows]
    fto_occ=sum(1 for r in rows if r.get('fto')=='OCCUPIED')
    print(f"  tiers={tiers}" + (f"  FTO-occupied={fto_occ}" if target=='avb6' else ""))
    Path(outp).write_text(json.dumps({"document":f"Updated knowledge-grounded {target} candidates v2 (edit-guideline fixes of v1 flags)",
        "date":"2026-10-13","note":"Tier-1 pharmacophore preserved; each edit fixes a v1 liability/FTO flag; re-gated below. Design hypotheses — physics (MM-GBSA on 9xmm/5O45) + wet-lab still required.",
        "candidates":rows}, indent=2))
    print(f"  wrote {outp}")
