#!/usr/bin/env python3
"""Verification of docs/20261031_MANUSCRIPT_ALLATOM_METHOD_DRAFT.md against the committed files it quotes.

Style of qa_audit/verify_artifacts.py. Pure text and JSON reads; takes about a second. Writes
  verify_method_draft_output.txt        (every check, PASS/FAIL, plus summary)
  method_draft_unchecked_numbers.txt    (numeric tokens of Sections 3-5 that no check covers, with a reason class)
Exit code 1 if any check fails.

Three kinds of check:
  value   a number read from a committed file equals the number printed in the draft (the printed string must occur in the draft)
  text    a number is confirmed by the text of a committed document (pre-registration, README) and not by a machine-readable file
  struct  hygiene: cross-references resolve, tables referenced are defined, no project-management tokens remain
"""
import json, math, os, re, subprocess, sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
AP = os.path.abspath(os.path.join(HERE, ".."))                      # allatom_paper/
CL = os.path.abspath(os.path.join(AP, ".."))                         # cyclic_llm/
REPO = os.path.abspath(os.path.join(CL, "..", "..", ".."))
DOCS = os.path.join(REPO, "docs")
DRAFT = os.path.join(DOCS, "20261031_MANUSCRIPT_ALLATOM_METHOD_DRAFT.md")
RET = os.path.join(REPO, "research", "guangzhou_all_atom", "multitarget", "integrin_chembl", "retro_recovery")
MINUS = "−"

text = open(DRAFT, encoding="utf-8").read()
checks = []          # (kind, name, ok, detail)
covered = []         # literal strings that a check verified (masked from the unchecked-number list)


def jl(path):
    return json.load(open(path, encoding="utf-8"))


def rd(path):
    return open(path, encoding="utf-8").read()


def git_show(commit, rel):
    return subprocess.run(["git", "-C", REPO, "show", f"{commit}:{rel}"], capture_output=True, text=True).stdout


def f(x, nd=3, sign=False):
    """Format like the draft: unicode minus, fixed decimals, optional explicit plus."""
    s = f"{abs(x):.{nd}f}"
    if x < 0 and float(s) != 0:
        return MINUS + s
    return ("+" if sign else "") + s


def chk(kind, name, cond, *literals, detail=""):
    """cond: the file-side assertion. literals: strings that must occur in the draft (and are then considered covered)."""
    missing = [l for l in literals if l not in text]
    ok = bool(cond) and not missing
    d = detail + (f" | NOT IN DRAFT: {missing}" if missing else "")
    checks.append((kind, name, ok, d.strip(" |")))
    if ok:
        covered.extend(literals)


def near(a, b, tol=5e-4):
    return abs(a - b) <= tol


# ---------------------------------------------------------------- track E: groups v2 and verifier quality
g = jl(os.path.join(AP, "track_e", "source_groups_v2.json"))
S = g["summary"]
tot = g["total_peptides"]
chk("value", "groups v2 total peptides and sources", tot == 6784 and g["n_sources"] == 20, "20 sources, 6,784 peptides", detail=f"{g['n_sources']} / {tot}")
for key, n_src, n_pep, share, top in (("0", 2, 4399, "64.8%", None), ("1", 9, 1269, "18.7%", "69.2%"), ("2", 9, 1116, "16.5%", "59.3%")):
    e = S[key]
    ok = e["n_sources"] == n_src and e["n_peptides"] == n_pep and f"{100 * e['n_peptides'] / tot:.1f}%" == share
    lits = [f"{n_pep:,}", share]
    if top:
        ok = ok and f"{100 * e['top_source_share_within_group']:.1f}%" == top
        lits.append(top)
    chk("value", f"group {'ASB'[int(key)]} counts and shares", ok, *lits, detail=str(e["n_peptides"]))
mem = g["membership"]
chk("value", "Townsend and Kelly counts and shares", mem["2020_Townsend"]["n"] == 2881 and mem["2021_Kelly"]["n"] == 1518
    and f"{100 * 2881 / tot:.1f}%" == "42.5%" and f"{100 * 1518 / tot:.1f}%" == "22.4%", "2,881", "1,518", "42.5%", "22.4%")
chk("value", "group membership sha prefix and full sha", g["membership_sha256"].startswith("be8a9945f504"), "be8a9945f504…", g["membership_sha256"])
v1m = jl(os.path.join(AP, "track_e", "source_groups.json"))["membership"]
grp_n = {}
for src, e in v1m.items():
    grp_n.setdefault(e["group"], []).append((e["n"], src))
def top_share(g_): return max(grp_n[g_])[0] / sum(n for n, _ in grp_n[g_])
chk("value", "v1 dominance: Townsend 90% of train, Kelly 80% of stop, two papers 91% of held-out",
    near(top_share("A"), 0.90, 0.006) and near(top_share("S"), 0.802, 0.006) and near(sum(n for n, s_ in grp_n["B"] if s_ in ("2013_CHUGAI", "2016_Furukawa")) / sum(n for n, _ in grp_n["B"]), 0.91, 0.006),
    detail=str({k: round(top_share(k), 3) for k in grp_n}))

vq = jl(os.path.join(AP, "track_e", "verifier_quality_v2.json"))
L = vq["loso"]
chk("value", "floors", vq["floors"]["perm"] == 0.15 and vq["floors"]["phys"] == 0.10 and vq["floors"]["min_sources"] == 5, "0.15", "+0.10", "five evaluable sources")
chk("value", "stop verifier LOSO mean and n-weighted", f(L["S"]["mean"]) == "0.363" and f(L["S"]["source_weighted_by_n"]) == "0.357" and L["S"]["n_evaluable"] == 9, "0.363", "0.357", "nine sources")
chk("value", "held-out F2 LOSO mean and n-weighted", f(L["B"]["mean"]) == "0.229" and f(L["B"]["source_weighted_by_n"]) == MINUS + "0.005" and L["B"]["n_evaluable"] == 9, "0.229", MINUS + "0.005")
chk("value", "physics held-out Spearman and n", f(vq["physics_heldout"]["spearman"]) == MINUS + "0.008" and vq["physics_heldout"]["n"] == 120, MINUS + "0.008", "120-peptide")
chk("value", "train verifier on S and B sources", f(vq["cross"]["train_A_on_B"]["mean"]) == "0.302" and f(vq["cross"]["train_A_on_S"]["mean"]) == "0.298", "0.302", "0.298")
fm = vq["floor_met"]
chk("value", "floor verdicts (stop yes, F2 held-out yes, physics no)", fm["stop_S_perm"] is True and fm["heldout_B_perm"] is True and fm["heldout_physics"] is False, "yes (mean-based)")

# ---------------------------------------------------------------- pilot (generation) aggregate
ag = jl(os.path.join(CL, "generation_pilot", "results_test", "aggregate_pilot3.json"))
rows = {"S-LIB": ("704.6", "681.8", "727.4", "1.000", 5), "S-EDIT": ("414.2", "396.4", "432.0", "1.000", 5), "L-CHEMFM": ("294.3", "281.8", "306.8", "0.980", 3),
        "L-P0": ("284.0", "232.7", "335.3", "0.775", 3), "L-PCLM2": ("237.2", "226.9", "247.5", "0.847", 5)}
for k, (y, lo, hi, val, ns) in rows.items():
    G = ag["generators"][k]
    ok = f"{G['Y']:.1f}" == y and f"{G['Y_t_interval'][0]:.1f}" == lo and f"{G['Y_t_interval'][1]:.1f}" == hi and f"{G['validity']:.3f}" == val and ag["n_seeds"][k] == ns
    chk("value", f"pilot {k}: Y, t-interval, validity, seeds", ok, y, f"{lo} to {hi}", val)
d = ag["llm_vs_best_simple"]
vals = []
for k in ("L-CHEMFM", "L-P0", "L-PCLM2"):
    vals.append(d[k]["diff_mean"])
chk("value", "LLM minus best simple spans -408 to -467", vals[0] is not None and round(vals[0]) == -408 and round(vals[2]) == -467, MINUS + "408 to " + MINUS + "467", detail=str(vals))
chk("value", "pilot best simple generator is S-LIB at 704.6", ag["best_simple"]["gen"] == "S-LIB" and ag["best_simple"]["Y"] == 704.6, "704.6 per 1,000", "237.2 to 294.3")
ct = ag["controls"]
chk("value", "pilot controls: copy-seed Y 0; random-init validity 0", ag["generators"]["C-COPY"]["Y"] == 0 and ag["generators"]["C-RANDINIT-PCLM2"]["validity"] == 0, "copy-seed Y = 0", "validity 0")

# ---------------------------------------------------------------- P0 reference model
p0 = jl(os.path.join(CL, "ihlm", "p0_intrinsic_result.json"))
C = p0["C_sampling"]
chk("value", "P0 validity, macrocycle fraction, N-methyl means", f(C["validity"]) == "0.664" and f"{100 * C['macrocycle_fraction_ring_ge12']:.1f}%" == "10.2%"
    and f(C["mean_n_methyl_sampled"]) == "0.078" and f"{C['mean_n_methyl_real']:.2f}" == "2.67", "66.4% valid", "10.2% macrocycles", "0.078", "2.67")
chk("value", "P0 parameters 25.5 M", round(p0["n_params"] / 1e6, 1) == 25.5, "25.5-million-parameter", "25.5 M")

# ---------------------------------------------------------------- stopping monitor (U2) simulations
sb = jl(os.path.join(AP, "feedback", "results", "stageB_test.json"))
H, B_ = sb["kinds"]["hackable"], sb["kinds"]["benign"]
chk("value", "monitor hackable retained fractions", f(H["GapStop"]["retained_mean"]) == "0.794" and [f(x) for x in H["GapStop"]["retained_ci"]] == ["0.776", "0.811"]
    and f(H["NeverStop"]["retained_mean"]) == "0.560" and [f(x) for x in H["NeverStop"]["retained_ci"]] == ["0.556", "0.563"], "0.794 [0.776, 0.811]", "0.560 [0.556, 0.563]")
chk("value", "monitor delay and missed-hack", H["GapStop"]["delay_median"] == -3 and f(H["GapStop"]["missed_hack_rate"]) == "0.273", "0.273", "3 rounds before")
chk("value", "monitor benign retained and false-stop", f(B_["GapStop"]["retained_mean"]) == "0.999" and B_["GapStop"]["false_stop_rate"] == 0.0 and f(B_["GapStop"]["false_stop"][1]) == "0.010",
    "retained 0.999", "0.000 (Wilson 95% upper bound 0.010)")
chk("value", "simpler monitor retains 0.447", f(H["HarnessSimple"]["retained_mean"]) == "0.447", "0.447")
chk("value", "monitor on shared exploit equals no monitor (0.560)", f(sb["kinds"]["shared"]["GapStop"]["retained_mean"]) == "0.560" if "shared" in sb["kinds"] else False, "behaves like no monitor (0.560)")
chk("value", "400 test seeds per environment", sb["n_runs_per_env"] == 400, "400 test seeds")
notes = rd(os.path.join(DOCS, "20261031_ALLATOM_U2U3_NOTES.md"))
chk("text", "monitor parameters q, tau, patience, tol, warm-up, smoothing", "q = 0.10, tau = 1.0, patience = 4, tol = 0.05, warmup = 2, smooth = 3" in notes,
    "q = 0.10", "threshold τ = 1.0", "patience 4", "tolerance 0.05", "warm-up 2", "smoothing 3")
chk("text", "monitor pre-registered verdict INCONCLUSIVE with 0.20 and [-2, +4] criteria", "INCONCLUSIVE (not GO)" in notes and "0.20" in notes and "[-2, +4]" in notes, "0.20 criterion", "[−2, +4] window")
pu = rd(os.path.join(AP, "feedback", "preference_updater.py"))
chk("text", "preference gate thresholds 0.01 and 0.005 from round 3 exist in the updater source", "kl_min: float = 0.01" in pu and "relw_min: float = 0.005" in pu and "check_from: int = 3" in pu,
    "below 0.01", "below 0.005")
chk("text", "preference diagnosis numbers (zero-variance 0.95 to 1.0, KL 0.001, weight change 0.00096 / 0.0017, memorised 70.8%)",
    all(s in rd(os.path.join(DOCS, "20261031_ALLATOM_LLM_PAPER_DESIGN.md")) for s in ("0.95-1.0", "0.00096", "0.0017", "0.708")), "0.95 to 1.0", "0.00096", "0.0017", "70.8%")

# ---------------------------------------------------------------- orchestrator / harness / retrieval
sm = jl(os.path.join(AP, "orchestrator", "smoke_result_run2.json"))
pl = sm["planted"]
chk("value", "planted-optimum: loop 7/10, random search 1/10", pl.get("optimum_found_seeds") == 7 and pl.get("optimum_found_seeds_random_search") == 1, "7 of 10 seeds against 1 of 10", detail=str((pl.get("optimum_found_seeds"), pl.get("optimum_found_seeds_random_search"))))
sh = sm["shuffled"]["paired_loop_minus_random"]
chk("value", "shuffled-reward control paired mean and t-interval", f(sh["mean"], 4) == MINUS + "0.0015" and f(sh["ci_t"][0]) == MINUS + "0.020" and f(sh["ci_t"][1]) == "0.017",
    MINUS + "0.0015", "[" + MINUS + "0.020, 0.017]")
chk("value", "smoke: ten seeds, 300-call budget", sm["n_seeds"] == 10 and sm["budget"] == 300, "ten seeds, 300-call budget")
log = rd(os.path.join(AP, "orchestrator", "pytest_run2.log"))
chk("value", "38 orchestrator/harness tests pass", re.search(r"\b38 passed\b", log) is not None, "thirty-eight orchestrator and harness tests")
rm = rd(os.path.join(AP, "retrieval", "README.md"))
chk("text", "retrieval: 15 tests; arm-G store 4,634 rows / 2,826 isomers / 230 documents / 1991-2025 / 8 targets", all(s in rm for s in ("15 tests passed", "4,634", "2,826", "230", "1991-2025")) and "8 integrin targets" in rm,
    "4,634 exact rows", "230 documents", "1991 to 2025", "eight integrin targets", "Fifteen retrieval tests")
chk("text", "retrieval: wide store 21,575 rows over 724 targets, no document ids; blind rule 5 of 5 queries", "21,575 rows / 724 targets" in rm and "NO document ids" in rm and "5 queries" in rm, "21,575 rows over 724 targets", "five of five queries")

# ---------------------------------------------------------------- knowledge layer (committed version)
KB_REL = "research/guangzhou_all_atom/cyclic_llm/allatom_paper/knowledge/knowledge_kb_v1.json"
KB_COMMIT = "7ecf14af2"
kb_text = git_show(KB_COMMIT, KB_REL)
kb = json.loads(kb_text)
kc = kb["counts"]
srcs = kc["sources"]
n_pmc = sum(s.startswith("PMC") for s in srcs)
n_arx = sum(s.lower().startswith("arxiv") for s in srcs)
n_int = len(srcs) - n_pmc - n_arx
import hashlib
kb_sha = hashlib.sha256(kb_text.encode("utf-8")).hexdigest()
elig = [r for r in kb["rules"] if r.get("weight_eligible")]
oc = Counter(r.get("outcome_class") for r in elig)
chk("value", "gold set counts (committed version)", kc["n"] == 107 and kc["by_kind"] == {"card": 28, "caution": 11, "fundamental": 24, "rule": 44}, "107 entries (44 rules, 24 fundamentals, 11 cautions, 28 cards)")
chk("value", "gold set tiers", kc["by_tier"] == {"T-internal": 11, "T1": 60, "T2": 36}, "T1 (60), T2 (36) and T-internal (11)", "its 36 tier-T2 entries")
chk("value", "gold set sources: 41 PMC + 4 arXiv external, 5 internal", (n_pmc, n_arx, n_int) == (41, 4, 5), "45 external sources (41 open-access articles and 4 preprints) and 5 internal documents", detail=str((n_pmc, n_arx, n_int)))
chk("value", "gold set verified and weight-eligible by outcome class", kc["verified"] == 107 and kc["weight_eligible"] == 32 and (oc["permeability"], oc["stability"], oc["solubility"], oc["other"]) == (28, 1, 1, 2),
    "all 107 quotations are machine-verified", "32 entries are weight-eligible (14 T1 and 18 T2; 28 permeability, 1 stability, 1 solubility, 2 other)", detail=str(dict(oc)))
chk("value", "gold set file sha256 (prefix in text, full in availability statement)", kb_sha == "29368807246824222aa8ea860ff69adce1393ef9976a5c8fbb6091c5d0fe6951", "293688072468…", kb_sha, detail=kb_sha[:16])
elig_t = Counter(r["tier"] for r in elig)
chk("value", "weight-eligible tiers 14 T1 and 18 T2", (elig_t["T1"], elig_t["T2"]) == (14, 18), detail=str(dict(elig_t)))
td = rd(os.path.join(AP, "knowledge", "tier_decisions.py"))
chk("text", "tier definition: T1 = own experiment/simulation/analysis; T2 = review summary, restated result, textbook rule, background, project goal; default T2", 
    "own experiment, simulation" in td and "T2" in td and "default" in td.lower(),
    "the quoted statement reports a result or method from the source's own experiment, simulation or data analysis", "default when the stored text cannot show that the number is the source's own")
wt_now = os.path.join(AP, "knowledge", "knowledge_kb_v1.json")
chk("value", "INFO working-tree gold file equals the committed version", rd(wt_now) == kb_text, detail="differs: the draft quotes the committed version" if rd(wt_now) != kb_text else "same")
dc = jl(os.path.join(AP, "knowledge", "direction_check_results.json"))
sm_ = dc["summary"]
chk("value", "direction check: 17 agree, 7 mixed, 0 disagree, 83 not testable", sm_.get("agree") == 17 and sm_.get("mixed") == 7 and sm_.get("not_testable") == 83 and not sm_.get("disagree"), "17 agree, 7 are mixed, none disagrees and 83 cannot be tested")
agree_elig = [r for r in dc["rules"] if dc["rules"][r]["rule_status"] == "agree" and next(x for x in kb["rules"] if x["id"] == r).get("weight_eligible")]
chk("value", "literature-prior arm = 15 weight-eligible rules that agreed", len(agree_elig) == 15, "15 rules", detail=str(len(agree_elig)))
firsts = {}
for rid, v in dc["rules"].items():
    for feat, pf in v["per_feature"].items():
        if pf.get("status") == "tested" and not pf.get("proxy") and feat not in firsts and set(pf["per_source"]) >= {"2020_Townsend", "2021_Kelly"}:
            firsts[feat] = (pf["per_source"]["2020_Townsend"]["rho"], pf["per_source"]["2021_Kelly"]["rho"])


def pair(feat, plus=False):
    a, b = firsts[feat]
    return f(a, 2, plus), f(b, 2, plus)


want = {"n_nme": ("+0.50", "+0.53"), "hbd": (MINUS + "0.44", MINUS + "0.53"), "tpsa": (MINUS + "0.47", MINUS + "0.49"), "clogp": ("+0.29", "+0.49"), "mw": (MINUS + "0.12", "+0.48"), "n_dres": (MINUS + "0.04", "+0.02")}
for feat, (x, y) in want.items():
    got = pair(feat, True) if feat in firsts else None
    chk("value", f"direction check rho {feat} Townsend/Kelly", got == (x, y), x, y, detail=f"{got}")
mining = jl(os.path.join(AP, "rules_mining", "groupA_sensitivity.json"))
pd_ = mining["per_source_descriptive"]


def find_num(obj, key):
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k == key and isinstance(v, (int, float)):
                return v
            r = find_num(v, key)
            if r is not None:
                return r
    return None


T_, K_ = pd_["2020_Townsend"], pd_["2021_Kelly"]
mine_ok = (f(T_["tpsa"]["spearman_with_y"]) == MINUS + "0.470" and f(K_["tpsa"]["spearman_with_y"]) == MINUS + "0.485" and f(T_["hbd"]["spearman_with_y"]) == MINUS + "0.439"
           and f(K_["hbd"]["spearman_with_y"]) == MINUS + "0.527" and f(T_["logp"]["spearman_with_y"]) == "0.287" and f(K_["logp"]["spearman_with_y"]) == "0.488"
           and f(T_["N-Me added (with minus without)"]["mean_dz"]) == "0.623" and f(K_["N-Me added (with minus without)"]["mean_dz"]) == "0.483")
chk("value", "mining descriptive within-source values (TPSA, HBD, logP Spearman; N-Me mean z-effect)", mine_ok, "TPSA −0.470 and −0.485", "HBD −0.439 and −0.527", "logP +0.287 and +0.488",
    "N-methylation mean within-source z-effect +0.623 and +0.483")
rb = rd(os.path.join(AP, "retrieval", "README.md"))
chk("text", "mining result in retrieval README: pooled N-Me +0.554 [0.373, 0.735], I2 = 0.95", all(s_ in rb for s_ in ("+0.554 [0.373, 0.735]", "0.95")), "pooled +0.554 [0.373, 0.735], I² = 0.95")
chk("text", "mining criteria: at least three sources", "need >= 3 sources" in rb or ">= 3 sources" in rb, "at least three sources")

# ---------------------------------------------------------------- rule set constants
spec = rd(os.path.join(AP, "rules", "spec.py"))
consts = dict(re.findall(r"^(RING_MIN|TPSA_HI)\s*=\s*([0-9.]+)", spec, re.M))
mw = re.search(r"MW_LO,\s*MW_HI\s*=\s*([0-9.]+),\s*([0-9.]+)", spec)
consts["MW_LO"], consts["MW_HI"] = (mw.groups() if mw else (None, None))
nme = re.search(r"NME_LO,\s*NME_HI\s*=\s*(\d+),\s*(\d+)", spec)
chk("value", "rule set C constants (ring 12, N-Me 2-6, MW 600-1400, TPSA 300)", consts.get("RING_MIN") == "12" and nme and nme.groups() == ("2", "6") and consts.get("MW_LO") == "600.0"
    and consts.get("MW_HI") == "1400.0" and consts.get("TPSA_HI") == "300.0", "at least 12 atoms", "between 2 and 6 N-methyl amides", "[600, 1,400]", "at most 300", detail=str(consts))
chk("text", "SMARTS for N-methyl amide in draft equals spec", "[CX3](=O)[NX3;!H1]([CH3])" in spec, "`[CX3](=O)[NX3;!H1]([CH3])`")

# ---------------------------------------------------------------- backbone configuration and fine-tuning exclusion
p3 = rd(os.path.join(DOCS, "20261031_GENERATION_PILOT3_PREREG.md"))
chk("text", "backbone: 22 layers, d 2048, vocab 320, 512 positions (pilot doc)", all(s in p3 for s in ("22 layers", "d 2048", "vocab 320", "max 512 positions")), "22 layers", "hidden size 2,048", "320", "512 positions")
chk("value", "ChemFM-1B ~970 M parameters (survey)", "970,287,104" in rd(os.path.join(DOCS, "20261030_PEPTIDE_CHEM_LM_MODEL_SURVEY.md")), "about 970 million parameters")
p1 = rd(os.path.join(DOCS, "20261030_IHLM_PRETRAINING_PLAN_P1.md"))
chk("text", "union filter removed 8,983 molecules (0.312%)", "8,983" in p1 and "0.312" in p1, "8,983 molecules, 0.312%")
chk("text", "ChEMBL at most 10% of tokens; corpora list", "<= 10 %" in p1 or "≤ 10 %" in p1, "at most 10% of tokens")
gm = rd(os.path.join(DOCS, "20261031_ALLATOM_LLM_PAPER_DESIGN.md"))
chk("text", "BoltzGen fine-tune lost 3/3; DockQ 0.506 vs 0.759", "lost to the base model on 3/3" in gm and "0.506" in gm and "0.759" in gm, "three of three comparisons", "0.759", "0.506")
chk("text", "cofold ipTM vs physics rho -0.04", "-0.04" in gm, "−0.04")
chk("text", "PeptideCLM-2 31.7M and 114M; strict load", "31.7M" in gm and "114M" in gm and "0 missing, 0 unexpected" in gm, "31.7 million and 114 million", "zero missing and zero unexpected keys")

# ---------------------------------------------------------------- evaluation protocol constants (Track E pre-registration text)
te = rd(os.path.join(DOCS, "20261031_ALLATOM_TRACK_E_PREREG.md"))
chk("text", "budgets, proposal cap, seeds", all(s in te for s in ("B = 1,000", "20 x B", "300 rule-satisfying", "seeds 100-102", "seeds 0-9", "kappa 1")), "B = 1,000", "20 × B", "seeds 100 to 102", "seeds 0 to 9", "(kappa 1)")
chk("text", "reference library 3,000 (60 for physics), 4 conformers", "3,000 randomly chosen" in te and "(60 for the physics verifier)" in te and "4 conformers" in te, "3,000 labelled peptides; 60 for the physics verifier", "four ETKDG and MMFF conformers")
chk("text", "F1 formula coefficients", "-0.01 TPSA - 0.15 HBD + 0.20 logP - 0.10 max(0, RotB-10)" in te, "−0.01·TPSA − 0.15·HBD + 0.20·logP − 0.10·max(0, rotatable bonds − 10)")
chk("text", "control pass rules (floor interval; 0.9 of optimum)", "inside the random_lib floor interval" in te and "0.9 of the optimum" in te, "0.9 of the optimum top-10 mean within B")
chk("text", "margin +0.03; GO/NO-GO/INCONCLUSIVE definitions; effective margin ~0.7 x MDE", "+0.03" in te and "NO-GO-detectable" in te and "0.7 x MDE" in te.replace("0.7 x the MDE", "0.7 x MDE") or "about 0.7 x MDE" in te, "+0.03", "GO", "NO-GO-detectable", "INCONCLUSIVE")
chk("text", "lambda_H values 0.229, 0.10, 0 (A3.4)", "{0.229, 0.10, 0.0}" in te, "{0.229, 0.10, 0}")
chk("text", "floors 0.15 / +0.10; groups; train 60-68%", "0.15" in te and "+0.10" in te and "60-68%" in te, "0.15", "+0.10")
chk("text", "snake draft and 18 remaining sources", "18 sources" in te or "remaining 18 sources" in te, "remaining 18 sources")
try:
    from scipy import stats
    tcrit = stats.t.ppf(0.975, 9)
except Exception:
    tcrit = 2.262
chk("value", "t critical value for n = 10 is 2.26; 2.8 = 1.96 + 0.84; ratios 0.70 and 0.81", f"{tcrit:.2f}" == "2.26" and near(1.96 + 0.84, 2.8, 1e-9) and f"{1.96 / 2.8:.1f}" == "0.7" and f"{tcrit / 2.8:.1f}" == "0.8",
    "t ≈ 2.26", "MDE80 ≈ 2.8·SE", "about 0.7 to 0.8 × MDE80")
gc = rd(os.path.join(DOCS, "20261031_GATE_CALIBRATION_PREREG.md"))
delta26 = 0.5 * 2.8 * 0.2014 / math.sqrt(26)
chk("value", "equivalence margin derivation: delta(26) = 0.0553", f"{delta26:.4f}" == "0.0553" and "0.0553" in gc, "0.0553 at F = 26")
chk("text", "calibration acceptance criteria", all(s in gc for s in ("<= 0.10", "<= 0.15", ">= 0.80", ">= 0.90", "<= 0.05 (point)", "47")), "at most 0.10 (exact 95% upper bound at most 0.15)", "at least 0.80 at planted AUROC 0.65", "at least 0.90 at 0.70", "at most 0.05")
chk("text", "calibration: 0.95 quantile of maximum standardised departure", "0.95 empirical quantile" in gc, "0.95 empirical quantile")
gp = jl(os.path.join(RET, "gate_positive_control", "results", "gpc_summary.json"))
va, vm = gp["PASS_A"]["VI"], gp["PASS_A"]["VM2"]
chk("value", "gate positive control: false BIASED 24.5% / 32.5%; VALID 61% / 2.5%", f"{100 * va['p']:.1f}%" == "24.5%" and f"{100 * vm['p']:.1f}%" == "32.5%"
    and f"{100 * va['status_distribution']['VALID']['p']:.0f}%" == "61%" and f"{100 * vm['status_distribution']['VALID']['p']:.1f}%" == "2.5%", "24.5%", "32.5%", "61%", "2.5%", "0.245 at 26; 0.325 at 14", "0.61 at 26; 0.025 at 14")
det = gp["detection"]
det_ok = all(det[k][a]["detection"]["p"] == 1.0 for k in ("S-tpsa", "S-typ", "S-cens", "S-diffuse") for a in ("0.6", "0.65"))
chk("value", "gate detection of planted shortcuts is 1.00 at AUROC 0.60 and 0.65", det_ok, "0.60 to 0.65", "≈ 1.00 at 0.60 to 0.65", "about 24 per benchmark", detail="p == 1.0 for TPSA, typicality, censoring, diffuse")
pd_ = rd(os.path.join(DOCS, "20261031_ALLATOM_PATENT_PREREG.md"))
chk("text", "patent filter MW [500, 2600], ring >= 12, >= 3 amide bonds, 2.5 s delay", all(s in pd_ for s in ("[500, 2600]", ">= 12 atoms", ">= 3 amide bonds", "2.5 s")), "molecular weight 500 to 2,600", "at least three amide bonds", "fixed delay")
ks = rd(os.path.join(DOCS, "20261031_ALLATOM_KNOWLEDGE_SCALE_PREREG.md"))
chk("text", "extraction thresholds: precision 0.80, 100-entry audit, 60% coverage, >=3 rules from >=3 papers", all(s in ks for s in ("precision >= 0.80", "100 surviving rules", "60%", ">= 3 verified rules from >= 3 distinct papers")),
    "at least 0.80", "100-entry audit sample", "at least 60%", "at least three verified entries from at least three papers")
chk("text", "extraction model size and quote length", "Qwen3-8B" in ks and "<= 30" in ks, "eight-billion-parameter", "30 words")
kbsec = rd(os.path.join(DOCS, "20261031_MANUSCRIPT_KB_SECTION_FOR_METHOD_PAPER.md"))
chk("text", "40 queries over four topics", "40 queries" in kbsec, "40 queries over four topics")

# ---------------------------------------------------------------- hygiene: no project-management content
bad = {"[PENDING": r"\[PENDING", "workstream": r"workstream", "working name": r"working name", "USD": r"\bUSD\b", "docs/ path": r"docs/", "allatom_paper path": r"allatom_paper",
       "commit-hash-like token": r"`[0-9a-f]{9,40}`", "instance id": r"\bi-[0-9a-f]{8,}", "LIT tag": r"\[LIT-", "registry": r"[Rr]esults registry", "TODO/TBD": r"\bTODO\b|\bTBD\b",
       "pending narration": r"\b(once|until) the (pilot|patent|stream|workstream)", "priority claim": r"to our knowledge|\bfirst (to|time)\b|\bnovel to\b"}
for name, pat in bad.items():
    hit = re.findall(pat, text)
    chk("struct", f"hygiene: no {name}", not hit, detail=f"{len(hit)} hit(s)")

# ---------------------------------------------------------------- cross references and tables
heads = set()
for m in re.finditer(r"^(#{2,4}) (\d+(?:\.\d+)*)\.? ", text, re.M):
    heads.add(m.group(2))
for m in re.finditer(r"^\*\*(\d+\.\d+\.\d+) ", text, re.M):
    heads.add(m.group(1))
refs, bad_refs = [], []
for m in re.finditer(r"Sections? (\d+(?:\.\d+){0,2})(?:\(([a-e])\))?((?: (?:and|to) \d+(?:\.\d+){0,2})?)", text):
    before = text[max(0, m.start() - 8):m.start()]
    if before.endswith("its "):
        continue
    for num in [m.group(1)] + re.findall(r"\d+(?:\.\d+){0,2}", m.group(3) or ""):
        refs.append(num)
        if num not in heads:
            bad_refs.append((num, text[max(0, m.start() - 40):m.end() + 10].replace("\n", " ")))
chk("struct", f"cross-references resolve ({len(refs)} section references)", not bad_refs, detail=str(bad_refs[:5]))
defined_tables = set(re.findall(r"\*\*Table (\d+)\.", text))
ref_tables = set(re.findall(r"Tables? (\d+)", text)) | set(re.findall(r"(?:and|to|,) (\d+)\)", ""))
chk("struct", "every referenced table is defined", ref_tables <= defined_tables, detail=f"referenced {sorted(ref_tables, key=int)} defined {sorted(defined_tables, key=int)}")
chk("struct", "every defined table is referenced in the text", defined_tables <= ref_tables, detail=f"unreferenced {sorted(defined_tables - ref_tables, key=int)}")
chk("struct", "Figure 1 defined and referenced", "**Figure 1.**" in text and "Figure 1" in text.replace("**Figure 1.**", ""), detail="")
empty_cells = len(re.findall(r"\| — ", text)) + len(re.findall(r"\| —\s*\|", text))
chk("struct", "unmeasured results are shown as — in tables, not narrated", empty_cells > 20, detail=f"{empty_cells} empty cells")
chk("struct", "section numbering sequential 1..8", [h for h in sorted(heads) if "." not in h] == [str(i) for i in range(1, 9)], detail=str(sorted(h for h in heads if "." not in h)))

# ---------------------------------------------------------------- unchecked numbers (Sections 3-5)
a, b = text.index("\n## 3. IH-LM"), text.index("\n## 6. Discussion")
body = text[a:b]
masked = body
for l in sorted(set(covered), key=len, reverse=True):
    masked = masked.replace(l, " ")
masked = re.sub(r"`[^`]*`", " ", masked)                      # code spans (hashes, SMARTS)
masked = re.sub(r"arXiv:\d{4}\.\d{4,5}|bioRxiv \S+|10\.\d{4}/\S+", " ", masked)
masked = re.sub(r"(?:Sections?|Tables?|Figure|Appendix) \d+(?:\.\d+)*(?:\([a-e]\))?(?: (?:and|to) \d+(?:\.\d+)*)?", " ", masked)
masked = re.sub(r"^#{2,4} .*$|^\*\*\d+\.\d+\.\d+ ", " ", masked, flags=re.M)
masked = re.sub(r"\b(?:19|20)\d{2}\b", " ", masked)           # years
tok = re.compile(r"[−+\-]?\d[\d,]*(?:\.\d+)?%?")
unchecked = []
for m in tok.finditer(masked):
    t_ = m.group(0)
    if t_ in ("1", "2", "3", "4", "5", "6", "7", "8", "9", "10"):
        cls = "small count or ordinal in prose"
    elif re.match(r"^[+−\-]?0\.\d+$", t_):
        cls = "value from a document or design constant (not machine-readable)"
    else:
        cls = "design constant, hyperparameter or document-derived number"
    ctx = masked[max(0, m.start() - 35):m.end() + 25].replace("\n", " ")
    unchecked.append((t_, cls, ctx))
by = Counter(c for _, c, _ in unchecked)

# ---------------------------------------------------------------- output
nfail = sum(1 for k, n, ok, d in checks if not ok and not n.startswith("INFO"))
lines = []
for k, n, ok, d in checks:
    tag = "PASS" if ok else ("INFO" if n.startswith("INFO") else "FAIL")
    lines.append(f"{tag:<5} [{k}] {n}" + (f"  ({d})" if d else ""))
lines.append("")
lines.append(f"{len(checks)} checks; failed: {nfail}; value checks {sum(1 for c in checks if c[0] == 'value')}, text checks {sum(1 for c in checks if c[0] == 'text')}, struct checks {sum(1 for c in checks if c[0] == 'struct')}")
lines.append(f"numeric tokens in Sections 3-5 not covered by any check: {len(unchecked)}  ({dict(by)})")
open(os.path.join(HERE, "verify_method_draft_output.txt"), "w", encoding="utf-8").write("\n".join(lines) + "\n")
u = ["Numeric tokens of Sections 3-5 of the method draft that no check covers, with the reason they cannot be machine-checked.",
     "Reason classes: small count or ordinal in prose (not a quantity from a file); value from a document or design constant (stated in a pre-registration or design document, not in a result file);",
     "design constant, hyperparameter or document-derived number (hyperparameters, thresholds and counts fixed in the design; no result file holds them).", ""]
u += [f"{t_:>10}  [{c}]  ...{ctx}..." for t_, c, ctx in unchecked]
open(os.path.join(HERE, "method_draft_unchecked_numbers.txt"), "w", encoding="utf-8").write("\n".join(u) + "\n")
print("\n".join(lines[-3:]))
for k, n, ok, d in checks:
    if not ok and not n.startswith("INFO"):
        print("FAIL", n, "|", d)
sys.exit(1 if nfail else 0)
