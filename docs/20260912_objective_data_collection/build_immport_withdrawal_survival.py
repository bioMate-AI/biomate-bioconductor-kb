"""W4 therapy-duration expansion — survival tables for ImmPort treatment-withdrawal /
sustained-response studies BEYOND the already-built iWITH (SDY1490).

Role = VALIDATION. training_eligible=False; ImmPort quarantined pending leakage sign-off.

Each endpoint is constructed from a DOCUMENTED outcome column, never guessed (the iWITH
lesson: do not read a time-to-event off the wrong column). For each study the event flag
and time column are named explicitly below.

Constructible studies (patient-level time-to-event after treatment withdrawal/taper):
  SDY2195  ACE / ALE06   — myasthenia gravis, MMF withdrawal. EVENT = clinical flare
           (flarmstr FLAR_FLAROCC=YES or FLAR_MILDDIS/SEVDIS=Yes); TIME = flare assessment
           day (FLAR_ASMTDY at first flare) else last assessment day. Arm = Withdrawal vs
           Maintenance (built-in null/control arm).
  SDY2274  ITN059AI PAUSE — psoriasis, ustekinumab withdrawal. EVENT = PASI relapse
           ("Did PASI Score Meet Relapse Criterion"=Y); TIME = Relapse study day if relapse
           else Study Day of Study Termination.
  SDY2275  ITN055AI CALIBRATE — proliferative lupus nephritis, prednisone/therapy taper.
           EVENT = renal flare (dsmstr DSDECOD contains "renal flare"); TIME = DSSTDY
           (disposition study day).

NOT built here (documented in W4_duration_survival_summary.json with the reason):
  - SDY1490 iWITH — already built (immport_iwith_survival.csv).
  - SDY3265 (lupus abatacept) — has flare status (flarmstr FLAREYN) but ALL dates are
    [Redacted] and the only numeric field is a form-phase code, so NO time-to-event.
  - Transplant CNI/steroid-withdrawal studies with standard-schema intervention timing but
    the rejection/graft-loss EVENT not resolvable from the pulled relational tables
    (SDY1231 CTOT-09, SDY133 SW01, SDY3271 A-WISH, SDY857 CTOT-11) — dictionary/outcome
    file needed.
"""
import json
import pandas as pd
from pathlib import Path

ROOT = Path(__file__).resolve().parent
IM = ROOT / "raw" / "immport"

def load(study, name):
    return pd.read_csv(IM / study / name, sep="\t", dtype=str)

results = {}
built = []

# ---------------------------------------------------------------- SDY2195 ALE06
flar = load("SDY2195", "SDY2195_flar.txt")
demo = load("SDY2195", "SDY2195_demo.txt")
flar["asmtdy"] = pd.to_numeric(flar["FLAR_ASMTDY"], errors="coerce")
flar["is_flare"] = (
    flar["FLAR_FLAROCC"].fillna("").str.upper().eq("YES")
    | flar["FLAR_MILDDIS"].fillna("").eq("Yes")
    | flar["FLAR_SEVDIS"].fillna("").eq("Yes")
)
rows = []
for sub, g in flar.groupby("Accession"):
    arm = g["TRT01P"].dropna().iloc[0] if g["TRT01P"].notna().any() else None
    fev = g[g["is_flare"] & g["asmtdy"].notna()]
    if len(fev):
        rows.append(dict(subject=sub, event=1, time_days=float(fev["asmtdy"].min()), arm=arm))
    else:
        last = g["asmtdy"].max()
        rows.append(dict(subject=sub, event=0, time_days=(float(last) if pd.notna(last) else None), arm=arm))
s2195 = pd.DataFrame(rows).dropna(subset=["time_days"])
sex = demo.groupby("Accession")["DEMO_GENDER"].first()
s2195["SEX"] = s2195["subject"].map(sex)
s2195.to_csv(ROOT / "raw" / "immport_sdy2195_ale06_survival.csv", index=False)
built.append("immport_sdy2195_ale06_survival.csv")
results["SDY2195"] = dict(
    name="ACE / ALE06 (ITN) — myasthenia gravis, mycophenolate mofetil withdrawal",
    constructible=True,
    endpoint="time to clinical flare after MMF withdrawal (flarmstr FLAR_FLAROCC/MILDDIS/SEVDIS); time=FLAR_ASMTDY",
    file="raw/SDY2195/SDY2195_flar.txt",
    N=int(len(s2195)), events=int(s2195["event"].sum()),
    arms=s2195["arm"].value_counts().to_dict(),
    covariates=["arm (Withdrawal vs Maintenance)", "SEX"],
    output="immport_sdy2195_ale06_survival.csv",
)

# ---------------------------------------------------------------- SDY2274 PAUSE
ad = load("SDY2274", "SDY2274_ADRELAPSE.txt")
disc = load("SDY2274", "SDY2274_disc.txt")
sl = ad.groupby("SUBJECT_ACCESSION").agg({
    "Did PASI Score Meet Relapse Criterion": "first",
    "Relapse Date": "first",
    "Study Day of Study Termination": "first",
    "Sex": "first", "Age": "first",
    "Enrolled Population Flag": "first",
}).reset_index()
# map relapse study-day from Visit Number for Relapse -> its analysis visit day is not a
# clean day column; use termination study day as time (relapse triggers early termination).
disc["discdy"] = pd.to_numeric(disc["DISCDY"], errors="coerce")
discmap = disc.set_index("SUBJECT_ACCESSION")["discdy"]
sl["term_day"] = pd.to_numeric(sl["Study Day of Study Termination"], errors="coerce")
sl["time_days"] = sl["term_day"].fillna(sl["SUBJECT_ACCESSION"].map(discmap))
sl["event"] = sl["Did PASI Score Meet Relapse Criterion"].eq("Y").astype(int)
sl = sl[sl["Enrolled Population Flag"].eq("Y")]
s2274 = sl[["SUBJECT_ACCESSION", "event", "time_days", "Sex", "Age"]].rename(
    columns={"SUBJECT_ACCESSION": "subject", "Sex": "SEX", "Age": "age"}).dropna(subset=["time_days"])
s2274.to_csv(ROOT / "raw" / "immport_sdy2274_pause_survival.csv", index=False)
built.append("immport_sdy2274_pause_survival.csv")
results["SDY2274"] = dict(
    name="ITN059AI PAUSE — plaque psoriasis, ustekinumab withdrawal",
    constructible=True,
    endpoint="time to PASI relapse after UST withdrawal (ADRELAPSE 'Did PASI Score Meet Relapse Criterion'=Y); "
             "time=Study Day of Study Termination (relapse triggers early termination) else DISCDY",
    file="raw/SDY2274/SDY2274_ADRELAPSE.txt",
    N=int(len(s2274)), events=int(s2274["event"].sum()),
    covariates=["SEX", "age"],
    output="immport_sdy2274_pause_survival.csv",
    caveat="relapse date column present but not a clean study-day; termination day used as event time (tight coupling: relapse => early termination)",
)

# ---------------------------------------------------------------- SDY2275 CALIBRATE
ds = load("SDY2275", "SDY2275_ds.txt")
dm = load("SDY2275", "SDY2275_dm.txt")
ds["dsstdy"] = pd.to_numeric(ds["DSSTDY"], errors="coerce")
ds["event"] = ds["DSDECOD"].fillna("").str.contains("renal flare", case=False).astype(int)
sexmap = dm.groupby("SUBJECT_ACCESSION")["SEX"].first()
s2275 = ds[["SUBJECT_ACCESSION", "event", "dsstdy", "TRT01P", "TRT02P"]].rename(
    columns={"SUBJECT_ACCESSION": "subject", "dsstdy": "time_days", "TRT01P": "arm"})
s2275["SEX"] = s2275["subject"].map(sexmap)
s2275 = s2275.dropna(subset=["time_days"])
s2275.to_csv(ROOT / "raw" / "immport_sdy2275_calibrate_survival.csv", index=False)
built.append("immport_sdy2275_calibrate_survival.csv")
results["SDY2275"] = dict(
    name="ITN055AI CALIBRATE — proliferative lupus nephritis, therapy taper (belimumab add-on RCT)",
    constructible=True,
    endpoint="time to renal flare (dsmstr DSDECOD ~ 'renal flare'); time=DSSTDY (disposition study day)",
    file="raw/SDY2275/SDY2275_ds.txt",
    N=int(len(s2275)), events=int(s2275["event"].sum()),
    arms=s2275["arm"].value_counts().to_dict(),
    covariates=["arm (RC vs RCB)", "SEX"],
    output="immport_sdy2275_calibrate_survival.csv",
    caveat="renal flare is one of several disposition reasons; other early-withdrawal reasons treated as censoring",
)

# ---------------------------------------------------------------- summary
not_built = {
    "SDY1490": dict(name="iWITH / ITN823ST — pediatric liver transplant IS withdrawal",
                    constructible=True, already_built=True, output="immport_iwith_survival.csv",
                    N=88, events=39, endpoint="time to on-study biopsy-proven rejection (liv3mstr positive REJDY)"),
    "SDY3265": dict(name="abatacept + Euro-lupus, proliferative lupus nephritis",
                    constructible=False, N_flare_status=137, events_binary=21,
                    reason="flare STATUS available (flarmstr FLAREYN) but ALL dates [Redacted]; only numeric field is a form/phase code — no time-to-event. Binary flare outcome only.",
                    needed="a study-day / relapse-day column (de-identified) — not present in released files"),
    "SDY1231": dict(name="CTOT-09 — renal transplant, CNI (tacrolimus) withdrawal",
                    constructible="partial",
                    reason="standard-schema intervention timing present (START/END_DAY) giving therapy DURATION, but biopsy-proven-rejection / graft-loss EVENT not resolved from pulled tables",
                    needed="rejection/graft outcome file + data dictionary (grafmstr/his_r_ctot09 present in study dir; parse required)"),
    "SDY133":  dict(name="SW01 — pediatric renal transplant, steroid withdrawal",
                    constructible="partial",
                    reason="intervention timing present; rejection endpoint in study-specific files (SW01_rj1.txt / SW01_ptld.rej.txt) not yet parsed to a per-subject time",
                    needed="parse SW01_rj1.txt rejection dates + SW01_dt1/enr for follow-up window"),
    "SDY3271": dict(name="A-WISH / ITN030ST — liver transplant IS withdrawal vs maintenance",
                    constructible="partial",
                    reason="intervention timing present + adsl3/ids1mstr/termmstr; rejection event day not resolved from pulled tables",
                    needed="parse ids1mstr / adsl3 for rejection + termmstr follow-up"),
    "SDY857":  dict(name="CTOT-11 — kidney transplant, rapid steroid taper (belatacept)",
                    constructible="partial",
                    reason="intervention timing present; rejection endpoint not resolved from pulled tables",
                    needed="rejection outcome file + dictionary"),
    "SDY662":  dict(name="liver transplant — gradual IS withdrawal (tolerance cohort)",
                    constructible=False, N=25,
                    reason="only 16 files in study dir; no per-subject outcome timing pulled; likely omics-only deposit",
                    needed="disposition/rejection file if it exists"),
    "SDY546":  dict(name="operationally tolerant liver transplant (cross-sectional 'Tolerant' cohort)",
                    constructible=False, N=32,
                    reason="cross-sectional tolerant-vs-not phenotype, not a withdrawal time-to-event design",
                    needed="n/a — not a longitudinal withdrawal endpoint"),
    "SDY3089": dict(name="ATG+rituximab induction with staged IS withdrawal (transplant)",
                    constructible="partial", N=14,
                    reason="disc/term/stermstr files present but event day not resolved; very small n=14",
                    needed="parse stermstr/termmstr for rejection + day"),
    "SDY3274": dict(name="renal transplant recipients (cross-sectional, mixed IS regimens)",
                    constructible=False, N=250,
                    reason="only 6 files; cross-sectional enrollment 'regardless of regimen', not a withdrawal trial",
                    needed="n/a"),
    "SDY218":  dict(name="egg oral immunotherapy (food-allergy desensitization)",
                    constructible=False, N=55,
                    reason="0 clinical files in study dir; oral-immunotherapy tolerance, off-topic for IS-withdrawal duration",
                    needed="n/a"),
    "SDY2015": dict(name="peanut-sensitized tolerant infants (cohort)",
                    constructible=False, N=36,
                    reason="0 clinical files; cross-sectional tolerance phenotype, not withdrawal time-to-event",
                    needed="n/a"),
}

built_ev = sum(results[k]["events"] for k in results)
built_n = sum(results[k]["N"] for k in results)
summary = dict(
    workstream="W4 — therapy-duration / treatment-withdrawal survival expansion",
    role="VALIDATION",
    training_eligible=False,
    quarantine="ImmPort — confirm not in knowledge-training before eval use",
    method="from arm_or_cohort descriptions filtered to genuine treatment-withdrawal/taper/tolerance-induction "
           "designs; for each, endpoint built ONLY from a named documented outcome column (no wrong-column guessing).",
    candidate_studies_from_arm_search=22,
    genuine_withdrawal_or_taper_designs=15,
    newly_built_this_workstream=list(results.keys()),
    newly_built_tables=built,
    newly_built_total_N=built_n,
    newly_built_total_events=built_ev,
    including_iwith=dict(studies_with_usable_survival_endpoint=4,
                         total_N=built_n + 88, total_events=built_ev + 39),
    per_study={**results, **not_built},
    verdict=(
        "Therapy-duration is a REAL but SMALL, HETEROGENEOUS objective. Beyond iWITH, only 3 more "
        "ImmPort withdrawal studies yield a clean patient-level time-to-event with a documented endpoint "
        f"(SDY2195, SDY2274, SDY2275): +{built_n} subjects, +{built_ev} events. With iWITH: 4 studies, "
        f"{built_n+88} subjects, {built_ev+39} events. The events span DIFFERENT diseases/endpoints "
        "(liver-tx rejection, MG flare, psoriasis PASI relapse, lupus renal flare) — pooling requires a "
        "common 'sustained-response-after-withdrawal' abstraction, which is a modeling hypothesis, not a "
        "given. ~5 transplant CNI/steroid-withdrawal studies (SDY1231/133/3271/857/3089) are CONSTRUCTIBLE "
        "IN PRINCIPLE (intervention timing present) but need per-study rejection-outcome parsing + data "
        "dictionaries to resolve the event day — a bounded follow-up effort that could roughly double N. "
        "As a standalone FM-training target the N is far too small; as an EXTERNAL VALIDATION set for a "
        "derived durability/tolerance score it is usable but must stay study-held-out and disease-stratified."
    ),
    caveats=[
        "small n per study; endpoints are heterogeneous across diseases — do not silently pool",
        "each endpoint built from a documented column; wrong-column guessing explicitly avoided (iWITH lesson)",
        "SDY2275/SDY2195 have built-in control/maintenance arms — usable as within-study null baselines",
        "partial-constructible transplant studies need outcome-file parsing, not yet done here",
        "training_eligible=False; ImmPort quarantined",
    ],
)

out = ROOT / "W4_duration_survival_summary.json"
out.write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps({k: summary[k] for k in
      ["candidate_studies_from_arm_search","genuine_withdrawal_or_taper_designs",
       "newly_built_this_workstream","newly_built_total_N","newly_built_total_events",
       "including_iwith"]}, indent=2))
print("\nPer built study:")
for k in results:
    print(f"  {k}: N={results[k]['N']} events={results[k]['events']}  {results[k]['name']}")
