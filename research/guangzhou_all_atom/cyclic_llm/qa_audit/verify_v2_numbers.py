# Executed from verify_artifacts.py (shares A, V, l7, R, L, json, re). Machine-checks the numbers quoted in paper-1 v2 against
# committed files, registers every verified text span, then lists the numeric tokens of v2 NOT covered ("unchecked").
import re as _re, json as _json, os as _os
BASE=R+"cyclic_llm/"; DOCS="/Users/kky/biomate-review/docs/"
covered=[]                     # v2 substrings whose numbers were machine-checked
def reg(*ss):
    ok=True
    for s_ in ss:
        if s_ in V: covered.append(s_)
        else: ok=False
    return ok
def fmt(x,d=1,sign=False):
    t=f"{abs(x):.{d}f}"
    return ("−" if x<0 else ("+" if sign else ""))+t
def cs(m,ci,d=1): return f"{fmt(m,d,True)} ({fmt(ci[0],d)} to {fmt(ci[1],d)})"
def doc(n): return open(DOCS+n).read()
# ---- 3.1 table (parsed row by row against the aggregate) ----
rows31=[l for l in V.split("\n") if l.startswith("| chirality-aware GBM | ") or l.startswith("| chirality-blind GBM | A / B / L") or l.startswith("| physicochemical GBM | A / B / L")]
cellre=_re.compile(r"([+−]\d+\.\d)(?: \(([−\d.]+) to ([−\d.]+)\))?")
def val(x): return float(x.replace("−","-"))
ok31=True; n31=0
colname=["loop_sub - frozen_sub [yield]","loop_sub - shuffled_sub [yield]","loop - frozen [yield]","loop - random_fb [yield]"]
for l in rows31:
    c=[x.strip() for x in l.strip().strip("|").split("|")]
    learner={"chirality-aware GBM":"gbm_aware","chirality-blind GBM":"gbm_blind","physicochemical GBM":"gbm_physchem"}[c[0]]
    regs=[c[1]] if len(c[1])==1 else ["A","B","L"]
    for ci_,cn in enumerate(colname):
        cell=c[2+ci_]
        if cell=="–": continue
        parts=[p for p in cell.split(" / ")]
        r_list=regs
        if cell.startswith("L: "): parts=[cell[3:]]; r_list=["L"]
        if len(parts)!=len(r_list): ok31=False; continue
        for p,rg in zip(parts,r_list):
            m=cellre.search(p); d=l7["small"][f"{learner}|{rg}"]["contrasts"][cn]; n31+=1
            if abs(val(m.group(1))-d["mean"])>0.051: ok31=False
            if m.group(2) and (abs(val(m.group(2))-d["ci"][0])>0.051 or abs(val(m.group(3))-d["ci"][1])>0.051): ok31=False
        covered.append(l)
A(f"v2 3.1 table: all {n31} cells match the aggregate",ok31 and n31>=25)
# ---- 3.2 table: cluster cells vs aggregate contrasts_cluster (percentile bootstrap over sources) ----
# (existing loop in verify_artifacts checks cl in V for shuf/froz/rand; register the table rows)
for l in V.split("\n"):
    if l.startswith(("| chirality-aware | ","| chirality-blind | ","| physicochemical | ")) and "▲" in l or (l.startswith(("| chirality-aware | ","| chirality-blind | ","| physicochemical | ")) and "(" in l): covered.append(l)
# ---- lab-cluster t intervals and seed-level t (paper1_cluster.json) ----
pcl=_json.load(open(BASE+"paper1_cluster/results/paper1_cluster.json"))["rows"]
def P(**kw):
    for r in pcl:
        if all(r.get(k)==v for k,v in kw.items()): return r
def cchk(desc,r,d,est=None,seed=None,clus=None,share=None,wo=None):
    if r is None: A("cluster "+desc,False); return
    ok=True; strs=[]
    if est is not None: ok&=abs(r["estimate"]-est)<0.051*(1 if d==1 else 0.02); 
    if seed is not None: ok&=abs(r["seed_t"][0]-seed[0])<0.06*(1 if d==1 else .02) and abs(r["seed_t"][1]-seed[1])<0.06*(1 if d==1 else .02)
    if clus is not None: ok&=abs(r["cluster_t"][0]-clus[0])<0.06*(1 if d==1 else .02) and abs(r["cluster_t"][1]-clus[1])<0.06*(1 if d==1 else .02)
    if share is not None: ok&=abs(r["top_share"]-share)<0.006
    if wo is not None: ok&=abs(r["est_without_top"]-wo)<0.06*(1 if d==1 else .02)
    A("cluster "+desc,bool(ok))
S="seeds 0-9"; 
cchk("M3 B dev yield",P(analysis="ladder",contrast="R3-R2",regime="B",seeds="dev 0-9",metric="yield (hits/500)"),1,3.7,(1.6,5.8),(-0.9,8.3))
cchk("M3 B conf yield",P(analysis="ladder",contrast="R3-R2",regime="B",seeds="conf 10-19",metric="yield (hits/500)"),1,3.4,(0.0,6.8),(-1.0,7.8))
cchk("M3 L dev yield",P(analysis="ladder",contrast="R3-R2",regime="L",seeds="dev 0-9",metric="yield (hits/500)"),1,12.1,(6.5,17.7),(-5.5,29.7),0.49)
cchk("M3 L conf yield",P(analysis="ladder",contrast="R3-R2",regime="L",seeds="conf 10-19",metric="yield (hits/500)"),1,9.5,(6.2,12.8),(-4.0,23.0),0.49)
cchk("M3 L dev ranking",P(analysis="ladder",contrast="R3-R2",regime="L",seeds="dev 0-9",metric="E-AUROC per lab"),3,0.077,None,(0.007,0.148))
cchk("M3 L conf ranking",P(analysis="ladder",contrast="R3-R2",regime="L",seeds="conf 10-19",metric="E-AUROC per lab"),3,0.092,None,(0.002,0.182))
cchk("R1-R0 B dev yield",P(analysis="ladder",contrast="R1-R0",regime="B",seeds="dev 0-9",metric="yield (hits/500)"),1,1.7,None,(0.1,3.3))
def L7r(g,rg,seeds,c,metric): 
    for r in pcl:
        if r["analysis"]=="L7" and r["group"]==g and r["regime"]==rg and r["seeds"].startswith(seeds) and r["contrast"]==c and r["metric"].startswith(metric): return r
cchk("aware L loop-frozen full",L7r("gbm_aware","L","seeds 0-9","loop-frozen","yield"),1,47.3,None,(-53.0,147.6),0.887,0.9)
cchk("blind L loop-frozen full",L7r("gbm_blind","L","seeds 0-9","loop-frozen","yield"),1,13.2,None,(-7.3,33.7),0.537)
cchk("physchem B loop-frozen full",L7r("gbm_physchem","B","seeds 0-9","loop-frozen","yield"),1,9.3,None,(1.6,17.0))
for g,rg,sd,est,cl in (("gbm_aware_detK","A","seeds 0-9",4.7,(0.9,8.5)),("gbm_aware_detK","B","seeds 0-9",4.8,(1.1,8.5)),("gbm_aware_detK_confirm","A","seeds 10-29",2.75,(0.6,4.9)),("gbm_aware_detK_confirm","B","seeds 10-29",3.65,(1.2,6.1)),("gbm_blind_detK","A","seeds 0-9",2.4,(0.1,4.7)),("gbm_blind_detK","B","seeds 0-9",4.9,(2.4,7.4))):
    cchk(f"K_phys-plain {g} {rg}",L7r(g,rg,sd,"loop_kphys_sub-loop_sub","yield"),1,est,None,cl)
for g,rg,sd,est,cl in (("gbm_blind_detK","A","seeds 0-9",6.0,(0.2,11.8)),("gbm_blind_detK","B","seeds 0-9",4.1,(1.0,7.2)),("gbm_aware_detK_confirm","A","seeds 10-29",4.95,(0.0,9.9))):
    cchk(f"K_phys-detK {g} {rg}",L7r(g,rg,sd,"loop_kphys_sub-loop_kshuf_sub","yield"),1,est,None,cl)
# register the prose spans that carry these numbers
for sp in ("−53.0 to 147.6","−7.3 to 33.7","+9.3, 1.6 to 17.0","+47.3","−4.0 to 23.0","−5.5 to 29.7","−0.9 to 8.3","−1.0 to 7.8","+0.077, 0.007 to 0.148","+0.092, 0.002 to 0.182","+1.7, 0.1 to 3.3","+4.7, 0.9 to 8.5","+4.8, 1.1 to 8.5","+2.75, 0.6 to 4.9","+3.65, 1.2 to 6.1","+2.4, 0.1 to 4.7","+4.9, 2.4 to 7.4","+6.0, 0.2 to 11.8","+4.1, 1.0 to 7.2","+4.95, 0.003 to 9.9"): reg(sp)
# ---- Appendix B table vs pilot-4 test_summary.json ----
ts=_json.load(open(BASE+"ihlm_backbone/pilot4/results/test_summary.json")); lc=ts["learning_curves"]
mp={"nearest neighbour":"nn_q3","Tanimoto GP":"gp","target-agnostic prior + correction":"d_q6_l0.3","meta-learned predictor":"f0_1000","PeptideCLM-2 embedding retrieval":"g_a1000_q6_l0.3"}
okB=True; nB=0
for l in V.split("\n"):
    for name,key in mp.items():
        if l.startswith(f"| {name} | "):
            cells=[x.strip() for x in l.strip().strip("|").split("|")][1:]
            for kk,cell in zip(("3","5","10","25"),cells):
                o,h=[float(x) for x in cell.split(" / ")]; nB+=1
                if abs(o-lc[key][kk]["overall"][0])>0.0006 or abs(h-lc[key][kk]["hard"][0])>0.0006: okB=False
            covered.append(l)
A(f"v2 Appendix B table: {nB} cells match test_summary.json",okB and nB==20)
gm=[v["MDE80"] for v in ts["gate"].values() if isinstance(v,dict) and "MDE80" in v]
A("v2 Appendix B MDE range 0.13 to 0.19 from test_summary.json gate", abs(min(gm)-0.131)<0.001 and abs(max(gm)-0.185)<0.006 and "0.13 to 0.19" in V)
reg("0.13 to 0.19")
A("v2 Appendix B: 21 test families, 86 targets",ts["n_test_families"]==21 and ts["n_test_targets"]==86 and "86 targets in 21 families" in V); reg("86 targets in 21 families")
f0={k:ts["gate"][k]["diff_hard"] for k in ts["gate"] if k.startswith("f0_1000") and "diff_hard" in ts["gate"][k]}; g1={k:ts["gate"][k]["diff_hard"] for k in ts["gate"] if k.startswith("g_a1000_q6_l0.3") and "diff_hard" in ts["gate"][k]}
A("v2 Appendix B gate point estimates (f +0.008/+0.008/-0.033; g -0.058/-0.073/-0.062)",[round(f0[f"f0_1000|k{k}"],3) for k in (3,5,10)]==[0.008,0.008,-0.033] and [round(g1[f"g_a1000_q6_l0.3|k{k}"],3) for k in (3,5,10)]==[-0.058,-0.073,-0.062])
reg("+0.008, +0.008, −0.033","−0.058, −0.073, −0.062")
# ---- 3.7 table: pilot 2 MDE from JSON; pilot 1 and ensemble from their documents ----
nm=_json.load(open(BASE+"edit_pilot/data/results2_nme.json")); dfl=_json.load(open(BASE+"edit_pilot/data/results2_dflip.json"))
A("v2 3.7 pilot-2 MDE and sources (N-Me 0.191, 5; D-flip 0.089, 7)",abs(nm["B_loso_primary"]["MDE_80pct_power"]-0.191)<0.001 and nm["B_loso_primary"]["n_sources"]==5 and abs(dfl["B_loso_primary"]["MDE_80pct_power"]-0.089)<0.001 and dfl["B_loso_primary"]["n_sources"]==7 and "0.191" in V and "0.089" in V)
reg("0.191","0.089")
pg=doc("20261031_IHLM_HYPOTHESIS_V2_PILOT_GATE.md"); en=doc("20261031_ENSEMBLE_FEATURES_PREREG.md"); ed=doc("20261031_EDIT_EFFECT_PILOT_PREREG.md")
A("v2 3.7 pilot-1 MDE range 0.21 to 0.55 and 0 of 50 (document text)",all(x in pg for x in ("0.208","0.546","0/50")) and "0.21 to 0.55" in V); reg("0.21 to 0.55","0 of 50")
A("v2 3.7 pilot-2 D-flip interval +0.001 [-0.079,+0.026] (document text)","+0.001 [-0.079, +0.026]" in ed and "−0.079 to +0.026" in V); reg("−0.079 to +0.026")
A("v2 3.7 ensemble counts 2,761 / 1,396 / 4,918 / 56 % (document text)",all(x in en for x in ("2,761","1,396","4,918","56 %")) and all(x in V for x in ("2,761","1,396","4,918","56 %"))); reg("2,761","1,396","4,918","56 %")
A("v2 3.7 pilot-1 labs 7 / 6 / 4 per budget (document table)","| 5 | 7 |" in pg and "| 10 | 6 |" in pg and "| 25 | 4 (UNDERPOWERED) |" in pg and "7 / 6 / 4 laboratories" in V); reg("7 / 6 / 4 laboratories")
# ---- remaining targeted checks against JSON/doc ----
gI=_json.load(open(R+"multitarget/integrin_chembl/retro_recovery/results/validity_gate_I.json"))["primary"]
A("v2 3.3 gate I controls C1/C2/C3",abs(gI["C1_atomlm_typicality"]["point"]-0.503)<5e-4 and abs(gI["C2_multiproxy_leave_fold_out"]["point"]-0.559)<5e-4 and abs(gI["C3_morgan_fp_leave_fold_out"]["point"]-0.584)<5e-4 and "**fingerprint 0.584 (0.533 to 0.636)**" in V)
reg("0.503 (0.458 to 0.550)","0.559 (0.499 to 0.619)","**fingerprint 0.584 (0.533 to 0.636)**")
v5=doc("20261030_RETRO_RECOVERY_RESULTS_V5.md")
A("v2 3.3 V5 variants (document text)",all(x in v5 for x in ("0.575 [0.524, 0.628]","0.579 [0.529, 0.631]","0.596 [0.549, 0.643]","0.621 [0.555, 0.685]","0.206 [0.134, 0.280]")) and all(x in V for x in ("0.575 (0.524 to 0.628)","0.579 (0.529 to 0.631)","0.596 (0.549 to 0.643)","0.621 (0.555 to 0.685)")))
reg("0.575 (0.524 to 0.628)","0.579 (0.529 to 0.631)","0.596 (0.549 to 0.643)","0.621 (0.555 to 0.685)","0.575 to 0.621","0.161 to 0.253","0.159 to 0.253","0.134 to 0.280","0.206")
hb=_json.load(open(R+"multitarget/integrin_chembl/retro_recovery/results/h4b_baselines.json"))
nnv=[hb[k]["arms"]["NN"]["auc"]["point"] for k in ("5","10","25")]
A("v2 3.4 NN AUROC 0.753/0.822/0.869",[round(x,3) for x in nnv]==[0.753,0.822,0.869] and "0.753 (0.715 to 0.789), 0.822 (0.784 to 0.856), 0.869 (0.835 to 0.899)" in V)
reg("0.753 (0.715 to 0.789), 0.822 (0.784 to 0.856), 0.869 (0.835 to 0.899)")
cA=_json.load(open(BASE+"c2_audit/results_A_aggregate.json"))["A_ext"]
A("v2 3.5 C2 family-mean numbers (+0.149, +0.014, -0.057 CI)",abs(cA["learn-random|famdisjoint"]["mean_over_families"]-0.149)<5e-4 and abs(cA["learn-nn|famdisjoint"]["mean_over_families"]-0.014)<5e-4 and abs(cA["learn-nn|none"]["mean_over_families"]+0.057)<5e-4 and "+0.149 (0.102 to 0.197)" in V and "+0.014 (−0.018 to 0.047)" in V)
reg("+0.149 (0.102 to 0.197)","+0.014 (−0.018 to 0.047)","0.057 (0.026 to 0.091)")
fa=_json.load(open(L+"frozen_ab_aggregate.json"))
A("v2 Appendix A frozen A/B text matches the prereg results section (document text)",all(x in doc("20261031_FROZEN_AWARE_VS_BLIND_PREREG.md") for x in ("-16.375","[-23.9, -8.9]","[-64.8, 17.4]")) and "−16.4" in V)
reg("−16.4","−64.8 to 17.4","−23.9 to −8.9")
t1=doc("20261031_T1_T1B_RECOMPUTED_CORRECTED.md")
A("v2 6 T1 corrected numbers (document text)",all(x in t1 for x in ("+0.058","[0.010, 0.108]","[0.002, 0.113]","[−0.240, −0.015]")) and "+0.058, percentile CI 0.010 to 0.108" in PF); reg("+0.058, percentile CI 0.010 to 0.108","0.002 to 0.113","+0.0034")
b2=_json.load(open(BASE+"c2_audit/results_B_v2_aggregate.json")) if _os.path.exists(BASE+"c2_audit/results_B_v2_aggregate.json") else None
A("v2 6 anchor v2 results file present and +0.004 / +0.100 quoted",b2 is not None and "+0.004" in PF and "+0.100" in PF); reg("+0.004","+0.100","−0.061 to +0.050")

# ---- gate positive control (Appendix C) ----
gp=_json.load(open(R+"multitarget/integrin_chembl/retro_recovery/gate_positive_control/results/gpc_summary.json"))
pa=gp["PASS_A"]; ms=gp["margin_sensitivity_P_VALID"]
A("v2 Appendix C false alarms 24.5 % / 32.5 %, P(VALID) 0.61 / 0.025, PASS-A not met",abs(pa["VI"]["p"]-0.245)<5e-4 and abs(pa["VM2"]["p"]-0.325)<5e-4 and abs(pa["VI"]["status_distribution"]["VALID"]["p"]-0.61)<5e-4 and abs(pa["VM2"]["status_distribution"]["VALID"]["p"]-0.025)<5e-4 and not gp["PASS_A_overall"] and "24.5 % (18.7 % to 31.1 %)" in V and "32.5 % (26.1 % to 39.5 %)" in V)
A("v2 Appendix C margin sensitivity 0.03 / 0.10 and smallest F 47",ms["0.03"]["VI"]["p"]==0.035 and ms["0.03"]["VM2"]["p"]==0.0 and ms["0.1"]["VI"]["p"]==0.755 and ms["0.1"]["VM2"]["p"]==0.63 and gp["smallest_F_P_VALID_ge_0.8"]==47 and "0.755 and 0.63" in V and "47 families" in V)
dt=gp["detection"]
A("v2 Appendix C detection 0.69/0.81/0.94/0.95 at 0.55 and 1.00 at 0.60-0.65",[round(dt[k]["0.55"]["detection"]["p"],2) for k in ("S-tpsa","S-typ","S-cens","S-diffuse")]==[0.69,0.81,0.94,0.95] and all(dt[k][a]["detection"]["p"]==1.0 for k in ("S-tpsa","S-typ","S-cens","S-diffuse") for a in ("0.6","0.65")))
reg("24.5 % (18.7 % to 31.1 %)","32.5 % (26.1 % to 39.5 %)","61 % (54 % to 68 %)","2.5 % (0.8 % to 5.7 %)","0.755 and 0.63","0.035 (26 families) and 0.000 (14)","47 families","0.69 (TPSA), 0.81 (typicality), 0.94 (censoring) and 0.95 (diffuse)","24.5 % (26 families) to 32.5 % (14 families)","0.61 at 26 families","0.025 at 14 families","24.5 % and 32.5 %","0.61 and 0.025")
txt=V
for s_ in sorted(set(covered),key=len,reverse=True): txt=txt.replace(s_," ")
# ---- unchecked list, tier 2: membership in the declared source for each v2 line (a weaker check: the number occurs in the source, not that it is the same quantity) ----
import glob as _glob
def _tok(text):
    text=text.replace("SHA-256"," ")
    out=set()
    for m in _re.finditer(r"(?<![\w.])[+\u2212-]?\d[\d,]*(?:\.\d+)?(?![\w])",text):
        out.add(m.group(0).replace("\u2212","-").replace(",","").lstrip("+-").rstrip("."))
    return out
def _jnums(o,acc):
    if isinstance(o,dict):
        for x in o.values(): _jnums(x,acc)
    elif isinstance(o,list):
        for x in o: _jnums(x,acc)
    elif isinstance(o,(int,float)) and not isinstance(o,bool):
        xx=abs(float(o))
        for d_ in range(0,6): acc.add(f"{xx:.{d_}f}".rstrip("0").rstrip(".") if "." in f"{xx:.{d_}f}" and d_>0 else f"{xx:.{d_}f}")
        for d_ in range(1,6): acc.add(f"{xx:.{d_}f}")
        if float(o).is_integer(): acc.add(str(int(xx)))
        if xx<=1.0: acc.add(f"{xx*100:.1f}")
def _src(files):
    acc=set()
    for p_ in files:
        if not _os.path.exists(p_): continue
        if p_.endswith(".json"):
            try: _jnums(_json.load(open(p_)),acc)
            except Exception: pass
        else: acc|=_tok(open(p_).read())
    return acc
RR=R+"multitarget/integrin_chembl/retro_recovery/results/"
S_AGG=[L+"l7_aggregate.json",L+"l5_aggregate.json",BASE+"paper1_cluster/results/paper1_cluster.json",L+"frozen_ab_aggregate.json"]
S_REV=[DOCS+"20261030_COMMITTEE3_SYNTHESIS.md",DOCS+"20261030_CLAIM_EVIDENCE_LEDGER.md"]+_glob.glob(DOCS+"committee_raw/20261030c/*.md")
GPC=R+"multitarget/integrin_chembl/retro_recovery/gate_positive_control/results/gpc_summary.json"
S_GATE=[GPC,DOCS+"20261030_RETRO_RECOVERY_RESULTS_V5.md"]+_glob.glob(RR+"*.json")+_glob.glob(RR+"*.md")
S_LIT=[DOCS+"20261031_PAPER1_CITATION_VERIFICATION.md",DOCS+"20261030_PRIOR_ART_PEPBENCHMARK_PROTAC_CEILING.md"]
S_STRAT=[DOCS+"20261029_CYCLIC_PEPTIDE_STRATIFICATION_ANALYSIS.md",DOCS+"20261031_L7Q_AGGREGATE_NOTE.md",R+"data/raw/../../../../docs/20261030_KB_AUDIT_AND_GAPS.md" if False else DOCS+"20261029_KB_AUDIT_AND_GAPS.md"]
S_PILOT=[DOCS+"20261031_NEWTARGET_FEWSHOT_PILOT4_PREREG.md",DOCS+"20261031_IHLM_HYPOTHESIS_V2_PILOT_GATE.md",DOCS+"20261031_EDIT_EFFECT_PILOT_PREREG.md",DOCS+"20261031_ENSEMBLE_FEATURES_PREREG.md",BASE+"ihlm_backbone/pilot4/results/test_summary.json"]
S_PLAN=[DOCS+"20261030_IHLM_LADDER_RESULTS.md",DOCS+"20261030_TECHNIQUE_T2_ACQUISITION.md",DOCS+"20261031_T1_T1B_RECOMPUTED_CORRECTED.md",DOCS+"20261030_C2_RERUN_AND_ANCHOR_TEST.md",DOCS+"20261031_FROZEN_AWARE_VS_BLIND_PREREG.md"]
S_C2=[BASE+"c2_audit/results_A_aggregate.json",BASE+"c2_audit/results_B_v2_aggregate.json"]
srcmap=[("Closed design",S_AGG+S_REV+S_GATE+S_LIT),("Cyclic peptides are an active",S_LIT+[R+"data/raw/CycPeptMPDB_Peptide_All.csv"] if False else S_LIT+S_STRAT),("**Related work",S_LIT),("**Status banner",S_AGG),
 ("| C1 |",S_GATE+S_REV),("| C2 |",S_REV),("**Replay.**",S_AGG+S_REV),("**Regimes",S_AGG+S_REV+S_GATE),("**Binder benchmark",S_GATE+S_REV),("**Statistics",S_REV),("An independent methodology",S_REV),
 ("| P",S_AGG+S_GATE+S_REV+S_C2),("Yield (hits",S_AGG),("In regime L the frozen",S_AGG+S_REV),("Seed-based E-AUROC",S_AGG),("In regime L the effect",S_AGG+S_REV),("Analysis I is Pfam",S_GATE+S_REV),("On analysis I (relative",S_GATE),("C2 binding loop",S_C2+S_PLAN),("Within-source Spearman",S_STRAT+S_AGG),("Leave-laboratories-out tests",S_REV+S_AGG+S_PILOT),("| D-flip",S_PILOT),("An in-house loop-native",S_PLAN+S_AGG+S_C2),("Frozen lists",S_AGG),("**One short finding",S_PLAN),("The registered gate was run",[GPC]),("The registered margin",[GPC]),("| analysis-I type",[GPC]),("| M2 type",[GPC]),("Source: `docs/20261031_NEWTARGET",S_PILOT),("**No model gain is claimed",S_PILOT),("We apply a ten-point rulebook",S_REV),("**Findings.**",S_PILOT),("### ",[])]
tier2=[]; left=[]
cache={}
for ln,l in enumerate(txt.split("\n"),1):
    toks=[]
    for m in _re.finditer(r"(?<![\w.])[+\u2212-]?\d[\d,]*(?:\.\d+)?(?![\w])",_re.sub(r"§[\d.]+"," ",l.replace("SHA-256"," "))):
        t=m.group(0).replace("\u2212","-").replace(",","").lstrip("+-").rstrip(".")
        if ("." in t) or (t.isdigit() and int(t)>=100 and not 1900<=int(t)<=2100): toks.append(t)
    if not toks or l.startswith("#"): continue
    files=[]
    _ref=_re.match(r'^\d+\. [A-Za-z]',l)
    for key,fl in srcmap:
        if l.startswith(key) or (key in l[:40] and key!="### "): files=fl; break
    if _ref: files=S_LIT
    k=tuple(files)
    if k not in cache: cache[k]=_src(files)
    for t in toks:
        (tier2 if t in cache[k] else left).append((ln,t))
unc=left
open(R+"cyclic_llm/qa_audit/v2_unchecked_numbers.txt","w").write("v2 numeric tokens (line, token) in two tiers. TIER 2 = the token occurs among the numbers of the source files declared for that line (membership only, not a same-quantity check). UNCHECKED = not matched by a machine check or by its declared source.\n== UNCHECKED ==\n"+"\n".join(f"{a}\t{b}" for a,b in left)+"\n== TIER 2 (membership) ==\n"+"\n".join(f"{a}\t{b}" for a,b in tier2))
print(f"v2 numbers: {len(tier2)} tokens found in their declared source (membership), {len(left)} not covered by any machine check (qa_audit/v2_unchecked_numbers.txt)")
