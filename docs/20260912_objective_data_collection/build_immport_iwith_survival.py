"""Therapy-duration survival table from ImmPort SDY1490 (iWITH / ITN823ST).

iWITH = immunosuppression WITHDRAWAL in stable pediatric liver-transplant recipients.
The tolerance endpoint = time to biopsy-proven acute rejection AFTER starting
immunosuppression withdrawal (i.e., how long the patient sustains reduced/withdrawn
therapy). This is genuine patient-level time-to-event for the therapy-duration objective.

Endpoint construction (documented, not guessed):
  - cohort   = enrolled subjects (exclude TERMRSN "did not meet eligibility" screen-fails)
  - EVENT    = subject appears in liv3mstr with on-study rejection; time = min REJDY (>0)
  - CENSORED = enrolled, no on-study rejection; time = DISPDY (disposition/last day)
  - NOTE: rjynmstr REJDY is NEGATIVE (pre-study rejection HISTORY) and is used only as a
    baseline COVARIATE, never as the on-study endpoint. (This distinction was verified.)
Small n (single study) — proof-of-concept for the objective, not broad validation.
Training-eligible False; quarantined.
"""
import json
import pandas as pd
from pathlib import Path

ROOT = Path(__file__).resolve().parent
S = ROOT / "raw" / "immport" / "SDY1490"

def load(f): return pd.read_csv(S / f, sep="\t", dtype=str)

disp = load("dispmstr_r_iwith.txt")
liv3 = load("liv3mstr_r_iwith.txt")
demo = load("demomstr_r_iwith.txt")
rjhx = load("rjynmstr_r_iwith.txt")

SCREEN_FAIL = "Subject did not meet eligibility requirements"
disp["enrolled"] = disp["TERMRSN"] != SCREEN_FAIL

# on-study rejection events: min positive REJDY per subject
liv3["rejdy"] = pd.to_numeric(liv3["REJDY"], errors="coerce")
events = (liv3[liv3["rejdy"] > 0].groupby("Accession")["rejdy"].min().rename("event_day").reset_index())
event_subjects = set(events["Accession"])

# baseline covariate: prior rejection history (rjynmstr RJHXYN=Yes) — NOT the endpoint
prior_rej = (rjhx.assign(hx=rjhx["RJHXYN"].eq("Yes")).groupby("Accession")["hx"].max().rename("prior_rejection_history"))

disp["dispdy"] = pd.to_numeric(disp["DISPDY"], errors="coerce")
disp["termdy"] = pd.to_numeric(disp["TERMDY"], errors="coerce")

rows = []
for _, r in disp[disp["enrolled"]].iterrows():
    sub = r["Accession"]
    is_event = sub in event_subjects
    if is_event:
        t = float(events.loc[events["Accession"] == sub, "event_day"].iloc[0])
    else:
        t = r["dispdy"] if pd.notna(r["dispdy"]) else r["termdy"]
    rows.append(dict(
        subject=sub, event=int(is_event), time_days=(float(t) if pd.notna(t) else None),
        completed=r["COMPYN"], term_reason=(None if r["enrolled"] and r["COMPYN"] == "Yes" else r["TERMRSN"]),
        prior_rejection_history=bool(prior_rej.get(sub, False)),
    ))
surv = pd.DataFrame(rows).merge(demo[["Accession", "SEX", "age"]], left_on="subject", right_on="Accession", how="left").drop(columns=["Accession"])
surv = surv.dropna(subset=["time_days"])
surv.to_csv(ROOT / "raw" / "immport_iwith_survival.csv", index=False)

n = len(surv); n_ev = int(surv["event"].sum())
ev_times = surv[surv["event"] == 1]["time_days"]
summary = dict(
    source="ImmPort SDY1490 iWITH / ITN823ST (pediatric liver transplant, immunosuppression withdrawal)",
    objective="therapy duration / sustained response — time to biopsy-proven rejection after withdrawal",
    n_screened=int(disp["Accession"].nunique()),
    n_screen_failures_excluded=int((~disp["enrolled"]).sum()),
    n_enrolled_with_followup=n,
    n_rejection_events=n_ev,
    event_rate=round(n_ev / n, 3) if n else None,
    median_followup_days=round(float(surv["time_days"].median()), 1),
    max_followup_days=float(surv["time_days"].max()),
    median_time_to_rejection_days=round(float(ev_times.median()), 1) if n_ev else None,
    covariates=["prior_rejection_history", "age", "SEX"],
    role="external-test (single study, small n) — proof-of-concept patient-level time-to-event",
    caveats=[
        "single study; small n — not broad duration validation",
        "endpoint = on-study biopsy rejection (liv3mstr, positive REJDY); rjynmstr negative REJDY is pre-study history, used only as covariate",
        "pediatric liver transplant tolerance — transfer to autoimmune/other duration questions is a hypothesis, not given",
        "ImmPort quarantined; confirm not in knowledge-training before eval use",
    ],
    training_eligible=False,
)
(ROOT / "immport_iwith_survival_summary.json").write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps(summary, indent=2))
print("\nsample rows:")
print(surv.head(8).to_string(index=False))
