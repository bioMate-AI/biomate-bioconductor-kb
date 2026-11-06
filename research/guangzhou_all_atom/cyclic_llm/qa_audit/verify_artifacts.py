import json,subprocess
R="/Users/kky/biomate-review/research/guangzhou_all_atom/"
L=R+"cyclic_llm/loop_retro/results/"; B=R+"multitarget/integrin_chembl/retro_recovery/results/"
def close(a,b,t=0.051): return abs(a-b)<=t
l5=json.load(open(L+"l5_aggregate.json")); l7=json.load(open(L+"l7_aggregate.json")); au=json.load(open(L+"l5_label_audit.json"))
h=json.load(open(B+"h4b_baselines.json")); gI=json.load(open(B+"validity_gate_I.json")); gM2=json.load(open(B+"validity_gate_M2.json"))
chk=[]
def A(name,cond): chk.append((name,bool(cond))); 
x=l5["fp_minus_random_A"]; A("L5 A",close(x["mean"],186.3) and x["ci95"]==[158.5,209.0] and x["lower_gt0"])
x=l5["fp_minus_random_B"]; A("L5 B",close(x["mean"],22.2) and x["ci95"]==[-1.6,44.1] and not x["lower_gt0"])
x=l5["fp_minus_random_C"]; A("L5 C",close(x["mean"],163.4) and x["ci95"]==[128.1,196.3])
x=l5["SENSITIVITY_hit_within_group_top10"]["fp_minus_random_B"]; A("L5 B alt",close(x["mean"],41.7) and x["ci95"]==[23.4,61.6])
A("L5 claim false",l5["CLAIM_loop_beats_random_both_regimes"] is False)
A("rule z A",close(l5["fp_minus_rule_z_A"]["mean"],53.6) and l5["fp_minus_rule_z_A"]["ci95"]==[25.1,77.0])
A("rule z B",close(l5["fp_minus_rule_z_B"]["mean"],-0.5) and l5["fp_minus_rule_z_B"]["ci95"]==[-20.0,17.2])
A("rule nme A",close(l5["fp_minus_rule_nme_A"]["mean"],105.4)); A("rule nme B",l5["fp_minus_rule_nme_B"]["ci95"]==[10.7,47.8])
ka=[k for k in l5 if k.split("_")[0] in("kn","resid","fuse") and "d_total" in l5[k]]
A("15 kn arms",len(ka)==15 and not any(l5[k]["d_total"]["lower_gt0"] for k in ka))
alt=l5["SENSITIVITY_hit_within_group_top10"]; ka2=[k for k in alt if k.split("_")[0] in("kn","resid","fuse") and "d_total" in alt[k]]
A("alt: one lower>0",[k for k in ka2 if alt[k]["d_total"]["lower_gt0"]]==["kn_B"])
A("pick A",l5["PICK_SOURCE_MEANS"]["fp_A"]["townsend"]==346.1 and l5["PICK_SOURCE_MEANS"]["random_A"]["townsend"]==206.1)
A("audit",au["max_group_share"]==0.528 and au["top_groups_hits"][0][0]=="2020_Townsend")
g=l7["small"]["gbm_blind|L"]["contrasts"]
A("L loop-rand",g["loop - random_fb [yield]"]["mean"]==165.0 and g["loop - random_fb [yield]"]["ci"]==[156.0,175.7025])
A("L loop-frozen",g["loop - frozen [yield]"]["mean"]==13.2); A("L loop-shuf",g["loop - shuffled [yield]"]["mean"]==79.5)
A("L one-shot auroc",g["loop - one_shot [E_auroc_gain]"]["mean"]==0.003 and g["loop - random_fb [E_auroc_gain]"]["ci"]==[-0.114,-0.0129])
A("L kphys",g["loop_kphys_sub - loop_sub [yield]"]["mean"]==-0.1)
ga=l7["small"]["gbm_blind|A"]["contrasts"]; A("A kphys",ga["loop_kphys_sub - loop_sub [yield]"]["mean"]==2.4 and ga["loop_kphys_contra_sub - loop_sub [yield]"]["mean"]==-7.7)
pc=l7["small"]["gbm_physchem|A"]["contrasts"]; A("phys A",pc["loop - random_fb [yield]"]["mean"]==123.8)
pb=l7["small"]["gbm_physchem|B"]["contrasts"]; A("phys B",pb["loop - random_fb [yield]"]["mean"]==20.0)
hy=l7["llm"]["anthropic/claude-haiku-5.5|A"]["yield_cum"]; A("haiku A",hy["llm_loop"]["mean"]==28.25 and hy["subset_gbm"]["mean"]==44.75 and hy["llm_frozen"]["mean"]==28.5)
ge=l7["llm"]["google/gemini-3.1-flash-lite|L"]["yield_cum"]; A("gem L",ge["llm_loop"]["mean"]==31.75 and ge["subset_gbm"]["mean"]==62.5 and ge["subset_random"]["mean"]==34.5)
A("gate I C3",close(gI["primary"]["C3_morgan_fp_leave_fold_out"]["point"],0.584,0.001) and not gI["VALID"])
A("gate M2 C1",close(gM2["primary"]["C1_atomlm_typicality"]["point"],0.665,0.001) and not gM2["VALID"])
A("h4b",close(h["5"]["arms"]["NN"]["auc"]["point"],0.753,0.001) and close(h["10"]["arms"]["NN"]["auc"]["point"],0.822,0.001) and close(h["25"]["arms"]["NN"]["auc"]["point"],0.869,0.001) and close(h["0"]["arms"]["PT"]["auc"]["point"],0.539,0.001))

# ---- extension: parse the manuscript tables and compare with artifacts ----
import re, math
from scipy import stats
D="/Users/kky/biomate-review/docs/"
M=open(D+"20261029_MANUSCRIPT_LOOP_SMALL_LLM_DRAFT.md").read(); V=open(D+"20261030_MANUSCRIPT_EVAL_CONTROLS_DRAFT_v2.md").read()
PF=open(D+"20261031_PROGRESS_PAPER1.md").read()
def f3(x,sign=False):
    t=f"{abs(x):.3f}".replace("-","")
    if x<0: return "\u2212"+t
    return ("+" if sign else "")+t
def cell(m,lo,hi): return f"{f3(m,True)} ({f3(lo)} to {f3(hi)})"
# 1. cluster-boot table cells (main draft: all rows; v2: the four columns it shows)
cb={"loop - random_fb [E source-rho]":"rand","loop_sub - shuffled_sub [E source-rho]":"shuf","loop_sub - frozen_sub [E source-rho]":"froz","loop_kphys_sub - loop_kshuf_sub [E source-rho]":"kshuf","loop_kphys_sub - loop_sub [E source-rho]":"knone"}
nm=0
for arm,c in l7["small"].items():
    for k,v in c.get("contrasts_cluster",{}).items():
        if not arm.startswith(("gbm_physchem|","gbm_aware|","gbm_blind|")) or arm.split("|")[1] not in ("A","B","L"): continue      # regime M = L9 sensitivity (res7n, collected since 2026-10-31), not in the tables; only the three tabled learners; other groups (detK, confirm, chemberta, atom_lm) may have insufficient clusters (ci_cluster None)
        if cb[k]=="kshuf" and arm.startswith(("gbm_aware|","gbm_blind|","gbm_physchem|")):
            dk=l7["small"][arm.replace("|","_detK|")]["contrasts_cluster"][k]; v=dk
        cl=cell(v["mean"],*v["ci_cluster"])
        if arm.startswith(("gbm_physchem|","gbm_aware|","gbm_blind|")):
            # random-feedback cell is absent for plain GBM A,B in the tables
            if cb[k]=="rand" and arm.startswith(("gbm_aware|A","gbm_aware|B","gbm_blind|A","gbm_blind|B")): continue
            nm+=1; A(f"cluster cell {arm} {cb[k]} in main",cl in M)
            if cb[k] in ("shuf","froz","rand"): A(f"cluster cell {arm} {cb[k]} in v2",cl in V)
# 2. K_phys paired audit: 15/54 percentile-99, 9/54 paired-t 99, Holm
ka=json.load(open(R+"cyclic_llm/kb_audit/kshuf_paired_audit.json"))
n=p99=t99=0; ps=[]
for cfg,v in ka.items():
    for c,x in v.items():
        if isinstance(x,dict) and "mean" in x and "sd_per_seed" in x:
            n+=1; p99+= (x["ci99"][0]>0 or x["ci99"][1]<0); t99+=(x["t99"][0]>0 or x["t99"][1]<0)
            if x["sd_per_seed"]>0:
                t=x["mean"]/(x["sd_per_seed"]/x["n"]**.5); ps.append(2*stats.t.sf(abs(t),x["n"]-1))
ps.sort(); m=len(ps)
def holm(a):
    c=0
    for i,p in enumerate(ps):
        if p<=a/(m-i): c+=1
        else: break
    return c
A("K_phys family 54",n==54 and m==54); A("K_phys 15/54 percentile-99",p99==15); A("K_phys 9/54 paired-t",t99==9)
A("Holm 1 at .05 and 0 at .01",holm(.05)==1 and holm(.01)==0)
A("draft states 15 of 54 / 9 of 54 / Holm","15 of 54" in M and "9 of 54" in M and "1 of 54 at \u03b1 = 0.05" in M )
# 3. C2 numbers
c2=json.load(open(R+"cyclic_llm/c2_audit/results_A_aggregate.json"))
A("C2 rerun logged mismatch",c2["A_repro10"]["reproduces"] is False and "0.287 / 0.241 / 0.101" in M and "0.299 / 0.249 / 0.118" in M)
A("C2 learn-NN text","+0.002" in M and "\u22120.018 to 0.047" in M and "\u22120.018 to 0.047" in V)
# 4. T1/T1b rows against technique docs
t1=open(D+"20261030_TECHNIQUE_T1_FUSION.md").read(); t1b=open(D+"20261030_TECHNIQUE_T1B_FUSION.md").read()
A("T1 binding -0.056 [-0.086,-0.025] in doc and drafts","\u22120.056 [\u22120.086, \u22120.025]" in t1 and "\u22120.056, \u22120.086 to \u22120.025" in M)
A("T1b permeability -0.010 (-0.046 to 0.015) in main draft","\u22120.010 (\u22120.046 to 0.015)" in M and "\u22120.010 [\u22120.046, 0.015]" in t1b)
# 5. strata (-0.30 [-0.41,-0.12], n-methyl >=5)
st=open(D+"20261029_CYCLIC_PEPTIDE_STRATIFICATION_ANALYSIS.md").read()
A("strata n-methyl>=5 -0.33 [-0.44,-0.16] (post-fix rerun)","-0.33 [-0.44, -0.16]" in st and "\u22120.33 (\u22120.44 to \u22120.16)" in M)
# 6. regime L set sizes
rl=json.load(open(L+"regime_L_heldout_sets.json")); hs=rl["heldout_by_seed"]; cnt=[len(hs[str(i)]) for i in range(10)]
A("regime L 6-18 labs, all 18 in seeds 0,7,9",min(cnt)==6 and max(cnt)==18 and [i for i,c in enumerate(cnt) if c==18]==[0,7,9] and "6 to 18" in M and "25.2 % to 34.3 %" in M and "25.2 % to 34.3 %" in V)
# 7. gate sensitivity and denominators quoted in drafts
cg=json.load(open("/Users/kky/biomate-review/docs/committee_raw/20261030b/ext_check_gate.json"))
A("compound-disjoint C2/C3 quoted",abs(cg["compound_disjoint"]["C2"]["point"]-0.5658)<5e-5 and abs(cg["compound_disjoint"]["C3"]["point"]-0.5796)<5e-5 and "0.5658" in M and "0.5796" in M and "0.575 (0.524 to 0.628)" in V)

# ---- regenerated aggregate (ab35481bb): hash, learner keys, aware numbers quoted in the drafts ----
import hashlib
A("aggregate sha256 matches frozen file and drafts", hashlib.sha256(open(L+"l7_aggregate.json","rb").read()).hexdigest()=="ebc525090740249f50ec4e2d96cd809e6b6b802c0f42ad2f7815f2dbdb76387e" and open(L+"l7_aggregate.sha256").read().split()[0]=="ebc525090740249f50ec4e2d96cd809e6b6b802c0f42ad2f7815f2dbdb76387e" and "ebc525090740249f50ec4e2d96cd809e6b6b802c0f42ad2f7815f2dbdb76387e" in M and "ebc525090740249f50ec4e2d96cd809e6b6b802c0f42ad2f7815f2dbdb76387e" in PF)
A("learner keys", {"gbm_aware|A","gbm_aware|B","gbm_aware|L","gbm_blind|A","gbm_blind|B","gbm_blind|L","gbm_physchem|A","gbm_physchem|B","gbm_physchem|L","chemberta|A","chemberta|B"}<=set(l7["small"]) and not any(k.startswith("gbm|") for k in l7["small"]))
ga=l7["small"]["gbm_aware|L"]["contrasts"]
A("aware L yield contrasts",ga["loop - random_fb [yield]"]["mean"]==186.1 and ga["loop - random_fb [yield]"]["ci"]==[179.5,192.9] and ga["loop - frozen [yield]"]["mean"]==47.3 and ga["loop - shuffled [yield]"]["mean"]==117.7 and all(x in M for x in ("+186.1","(179.5 to 192.9)","+47.3","+117.7")))
A("aware L one-shot/random E-AUROC",ga["loop - one_shot [E_auroc_gain]"]["mean"]==-0.0059 and ga["loop - random_fb [E_auroc_gain]"]["ci"]==[-0.0877,0.0171] and "\u22120.006" in M)
A("aware K_phys-kshuf yield A/B/L",[l7["small"][f"gbm_aware|{r}"]["contrasts"]["loop_kphys_sub - loop_kshuf_sub [yield]"]["mean"] for r in "ABL"]==[5.9,2.3,1.8] and "+5.9, 2.9 to 8.8" in M)
A("aware zero-sibling nonzero, blind zero",l7["small"]["gbm_aware|A"]["stereo"]["loop_sub"]["zero_sibling"]["mean"]==0.1808 and l7["small"]["gbm_blind|A"]["stereo"]["loop_sub"]["zero_sibling"]["mean"]==0.0)
A("audit not affected: aware A K_phys-none yield equals aggregate",ka["res7f_gbm_aware|A"]["kphys - none [yield]"]["mean"]==l7["small"]["gbm_aware|A"]["contrasts"]["loop_kphys_sub - loop_sub [yield]"]["mean"]==4.7)
A("chemberta exploratory n=3",l7["small"]["chemberta|A"]["n_seeds"]==3 and l7["small"]["chemberta|B"]["n_seeds"]==3)

# ---- matched-pair effects (post-fix CSV) ----
import pandas as pd
mm=pd.read_csv(R+"cyclic_llm/stratification/data/mmp_effects_pampa.csv").set_index("transformation")
nm=mm.loc["N-Me added (with minus without)"]; dm=mm.loc["D flip (D minus L)"]
A("MMP N-Me post-fix",nm.n_pairs==4166 and nm.n_sources==15 and round(nm.pooled,2)==0.24 and round(nm.meta_lo,2)==0.14 and round(nm.meta_hi,2)==0.33 and "4,166 pairs, 15 sources" in M)
A("MMP D flip post-fix",dm.n_pairs==7467 and dm.n_sources==18 and round(dm.pooled,2)==-0.01 and "7,467 pairs, 18 sources" in M)

# ---- paper-1 draft (v2): loop-vs-frozen lead table and frozen-share statement ----
def cs(m,ci): return f"{m:+.1f} ({ci[0]:.1f} to {ci[1]:.1f})".replace("-","\u2212")
for L_,r in (("aware","A"),("aware","B"),("aware","L"),("blind","L"),("physchem","L")):
    c=l7["small"][f"gbm_{L_}|{r}"]["contrasts"]
    A(f"v2 loop-frozen sub {L_}|{r}", cs(c["loop_sub - frozen_sub [yield]"]["mean"],c["loop_sub - frozen_sub [yield]"]["ci"]).replace("+","+") in V)
ca=l7["small"]["gbm_aware|L"]["contrasts"]; ya=l7["small"]["gbm_aware|L"]["yield_total"]; yb=l7["small"]["gbm_blind|L"]["yield_total"]
A("v2 aware L full loop-frozen +47.3 and share 75%", cs(ca["loop - frozen [yield]"]["mean"],ca["loop - frozen [yield]"]["ci"]) in V and round((ya["frozen"]["mean"]-ya["random_fb"]["mean"])/(ya["loop"]["mean"]-ya["random_fb"]["mean"]),2)==0.75)
A("v2 blind share 92%", round((yb["frozen"]["mean"]-yb["random_fb"]["mean"])/(yb["loop"]["mean"]-yb["random_fb"]["mean"]),2)==0.92 and "92 %" in V)
fa=json.load(open(L+"frozen_ab_aggregate.json")) if __import__("os").path.exists(L+"frozen_ab_aggregate.json") else None
A("frozen A/B file present and appendix quotes regime L -16.4", fa is not None and "\u221216.4" in V)

# ---- L7q deterministic K_shuf (aggregate 9190e64c8) ----
dc=[l7["small"][f"gbm_aware_detK_confirm|{r}"]["contrasts"]["loop_kphys_sub - loop_kshuf_sub [yield]"]["mean"] for r in "ABL"]
A("L7q confirmatory K_phys - K_shuf yield +4.95/+4.85/+4.90",dc==[4.95,4.85,4.9] and "+4.95 (2.95 to 6.9; Holm 0.0055)" in M and "+4.95, +4.85, +4.90" in V)
A("L7q n_seeds confirmatory 20",all(l7["small"][f"gbm_aware_detK_confirm|{r}"]["n_seeds"]==20 for r in "ABL"))
A("L7q physchem B cluster K_phys worse than detK shuffled",l7["small"]["gbm_physchem_detK|B"]["contrasts_cluster"]["loop_kphys_sub - loop_kshuf_sub [E source-rho]"]["ci_cluster"][1]<0 and "\u22120.049" in V)

# ---- laboratory-cluster intervals (paper1_cluster.json) quoted in v2 ----
pc=json.load(open(R+"cyclic_llm/paper1_cluster/results/paper1_cluster.json"))["rows"]
def prow(**kw):
    for r in pc:
        if all(r.get(k)==v for k,v in kw.items()): return r
r=prow(analysis="ladder",contrast="R3-R2",regime="L",seeds="conf 10-19",metric="yield (hits/500)")
A("cluster M3 L conf yield [-4.0, 23.0], 49% Townsend",round(r["cluster_t"][0],1)==-4.0 and round(r["cluster_t"][1],1)==23.0 and r["top_lab"]=="2020_Townsend" and "\u22124.0 to 23.0" in PF)
r=[x for x in pc if x["analysis"]=="L7" and x["group"]=="gbm_aware" and x["regime"]=="L" and x["seeds"].startswith("seeds 0-9") and x["contrast"]=="loop-frozen" and x["metric"].startswith("yield")][0]
A("cluster aware L loop-frozen -53.0..147.6, 89% Townsend",round(r["cluster_t"][0],1)==-53.0 and round(r["cluster_t"][1],1)==147.6 and r["top_share"]==0.887 and "\u221253.0 to 147.6" in V)
r=prow(analysis="ladder",contrast="R3-R2",regime="L",seeds="conf 10-19",metric="E-AUROC per lab")
A("cluster M3 L conf ranking +0.092 [0.002,0.182]",round(r["estimate"],3)==0.092 and round(r["cluster_t"][0],3)==0.002 and "0.002 to 0.182" in PF)
exec(open(__file__.replace("verify_artifacts","verify_v2_numbers")).read())
bad=[n for n,ok in chk if not ok]; print(len(chk),"checks; failed:",bad)
def last(p): 
    return subprocess.run(["git","-C","/Users/kky/biomate-review","log","-1","--format=%h","--",p],capture_output=True,text=True).stdout.strip()
for p in ["research/guangzhou_all_atom/cyclic_llm/loop_retro/results/l5_aggregate.json","research/guangzhou_all_atom/cyclic_llm/loop_retro/results/l7_aggregate.json","research/guangzhou_all_atom/cyclic_llm/loop_retro/results/l5_label_audit.json","research/guangzhou_all_atom/multitarget/integrin_chembl/retro_recovery/results/validity_gate_I.json","research/guangzhou_all_atom/multitarget/integrin_chembl/retro_recovery/results/validity_gate_M2.json","research/guangzhou_all_atom/multitarget/integrin_chembl/retro_recovery/results/h4b_baselines.json","docs/20261029_CYCLIC_PEPTIDE_STRATIFICATION_ANALYSIS.md","docs/20261029_KB_AUDIT_AND_GAPS.md","docs/20261030_RETRO_RECOVERY_RESULTS_V3.md","docs/20261029_L7_RESULTS_LOG.md","docs/20261028_V4_LLM_AUDIT_AND_EVAL.md","docs/20261029_BASELINE_ERROR_ANALYSIS.md","docs/20261028_CODE_DATA_EVAL_AUDIT_LOG.md","docs/20261030_C2_RERUN_AND_ANCHOR_TEST.md","docs/20261030_TECHNIQUE_T1_FUSION.md","docs/20261030_TECHNIQUE_T2_ACQUISITION.md","docs/20261030_IHLM_PRETRAINING_PLAN_P1.md","docs/20261030_IHLM_ARCHITECTURE_SPEC.md","docs/20261030_PEPTIDE_CHEM_LM_MODEL_SURVEY.md","docs/20261029_RETRO_RECOVERY_RESULTS_V2.md","research/guangzhou_all_atom/cyclic_llm/loop_retro/PREREG_LOOP.md"]:
    print(p, last(p))
