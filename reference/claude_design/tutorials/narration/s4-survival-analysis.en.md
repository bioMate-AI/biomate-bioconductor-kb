# Survival analysis — Kaplan–Meier and Cox — narration (EN)

One narration block per scene, in order, for edge-tts. Episode S4. Grounded in BioMate's real survival workflows: the Bioconductor `survival` subworkflow (Kaplan–Meier `survfit` + `coxph` + `cox.zph`), the `rlassocox` regularized Lasso-Cox subworkflow, and the `survival_analysis_km` drug-discovery trial-design workflow (captured 2026-10-05).

---

## Step 1 — Title · survival analysis, done correctly

"How long until relapse?" "Does this marker shorten survival?" These are time-to-event questions, and ordinary statistics get them wrong — because real follow-up is almost always incomplete. Some patients are still alive at the last visit; others are lost before the study ends. BioMate routes these questions to the proper methods — Kaplan–Meier curves and Cox regression — starting from just a goal and a survival table, and runs them on cloud compute with a reproducible record. In this walkthrough we'll follow the real survival workflows the whole way through, from the table you provide to the hazard ratios you read.

---

## Step 2 — The problem this solves

In time-to-event data, you rarely observe the event for everyone. A study ends; a patient moves away; some are simply still alive at the final visit. Those observations are censored — you know the subject survived at least that long, but not their full time. And censoring is the rule, not the exception. Treat the data as if the numbers were complete and you'll go wrong two ways. Average the survival times with a t-test, and censored patients have no final time to average — so the mean is biased. Collapse everything to "dead by now, yes or no" and run a logistic regression, and you throw away when things happened and lean on an arbitrary cut-off. Survival methods exist precisely for this: a patient contributes information right up to their last known time, and no further.

---

## Step 3 — The ideas you need first

Four plain ideas carry the whole analysis. First, time and censoring: each subject has a time — how long they were observed — and a status, which is one if the event happened and zero if the subject was censored. That pair is the entire input. Second, the Kaplan–Meier curve: a step curve that estimates the probability of surviving past each point in time, using the censored subjects correctly up to their last visit. Third, the log-rank test: a formal check of whether two or more survival curves — say treated versus control — differ by more than chance. And fourth, the hazard ratio, from a Cox model: the relative rate of the event per unit of a covariate, where below one is protective and above one is harmful. The arc is simple: describe survival, compare groups, then quantify and adjust for covariates.

---

## Step 4 — Stage one · goal to workflow

You don't assemble an R environment or wire up packages. You describe the question, and you hand over a table with a time column and an event-status column. BioMate routes that to a real, indexed survival workflow — Kaplan–Meier estimation, or Cox regression — with the analysis mapped to your columns and run on cloud compute. Under the hood it runs the R survival package — the Surv, survfit, and coxph functions a statistician would reach for — packaged as reproducible Nextflow workflows. And if your question is about trial design rather than data you already have — how many patients, what power — it routes instead to the clinical-trial survival workflow, which does log-rank power and sample-size calculations.

---

## Step 5 — Stage one, the input · what a survival table needs

The input is an ordinary table, one row per subject. What makes it a survival table is three kinds of column. A time column — months, days, or years until the event or the last contact. A status column, coded one for the event, like death or relapse, and zero for censored; BioMate maps common labels such as "dead" and "alive" onto that coding for you. And a grouping or covariate column — a treatment arm for Kaplan–Meier, or any mix of clinical covariates like age, stage, and markers for Cox. This is grounded in the real workflow: the Kaplan–Meier step fits survfit of Surv time and status by your group, and the Cox step fits coxph of Surv time and status against the covariate columns.

---

## Step 6 — Stage two · Kaplan–Meier and the log-rank test

The Kaplan–Meier workflow estimates the survival curve for each group and reports the numbers behind it. The survfit function produces the step curve per group and saves it — a Kaplan–Meier plot, plus a summary table of time, number still at risk, and survival probability with confidence bounds. From each curve you read the median survival — the time by which half the group has had the event — directly comparable across groups. And the log-rank test asks the key question: is the separation between the curves more than sampling noise? A small p-value says the groups' survival genuinely differs. But keep this in mind — Kaplan–Meier is descriptive. It shows the shape of survival and compares groups; it does not, on its own, establish a cause.

---

## Step 7 — Stage three · Cox regression and Lasso-Cox

Kaplan–Meier compares groups; Cox regression puts a number on the effect. The Cox proportional-hazards model fits all your covariates jointly and reports a hazard ratio, with a confidence interval and significance, for each one — the adjusted effect of a single factor while holding the others fixed. But when the covariates are many — a gene-expression signature with hundreds of features — ordinary Cox breaks down. That's where the regularized Lasso-Cox workflow comes in: it applies an L1 penalty, cross-validates to find the optimal lambda, and extracts the non-zero, active prognostic features and their coefficients — a sparse signature instead of a sprawling model. And crucially it validates: it splits the data into training and test sets, fits on the training set, and predicts risk on the held-out set — because feature selection on high-dimensional data is dangerously easy to overfit.

---

## Step 8 — Reading the result

The output is only as good as your reading of it, and two numbers carry most of the meaning: the hazard ratio and its confidence interval, together with the test's p-value. Start with direction. A hazard ratio of one means no effect on the event rate; below one means a lower hazard, which is protective; above one means a higher hazard, which is harmful. A hazard ratio of zero-point-seven is roughly a thirty percent lower rate. Then the uncertainty: a ninety-five percent confidence interval that crosses one means the effect can't be distinguished from "no effect" at this sample size — the point estimate alone can mislead. And finally, significance. A small p-value says the difference is unlikely if there were truly no difference. It does not measure the size of the effect, it does not prove causation, and it does not guarantee the result will replicate.

---

## Step 9 — The honest edges

These methods are standard and trustworthy — within their assumptions. BioMate runs the diagnostics; interpreting them is yours. Four edges matter. First, the proportional-hazards assumption: Cox assumes a covariate's effect is constant over time, so the workflow runs the cox-dot-zph test and diagnostic plots — check them, because if the assumption fails, the hazard ratio is hard to interpret. Second, censoring must be fair: the results assume censoring is unrelated to prognosis, and if sicker patients systematically drop out, the estimates are biased, and no method repairs that. Third, Lasso selection is tentative — it's data-dependent, so a different sample can select different genes; treat the signature as a hypothesis to validate, not a verdict. And fourth, association is not causation: a hazard ratio describes association, adjusted only for the covariates you included, and unmeasured confounders remain. This is a specific, honest capability — standard methods with their assumptions on the table, not hidden.

---

## Step 10 — The value at a glance

The whole point is one sentence: time-to-event questions deserve time-to-event methods, and BioMate runs them properly, with the assumptions on the table. You provide a survival table — a time column and an event status coded one or zero — and you state your goal. BioMate estimates the Kaplan–Meier curves and the median survival, compares groups with the log-rank test, fits Cox hazard ratios, and, when the covariates are high-dimensional, selects a validated Lasso-Cox signature — all on cloud compute, with a reproducible record. Then you read the hazard ratio, its interval, and the proportional-hazards diagnostics, honestly. From a survival table to curves, a test, and interpretable hazard ratios — the proper statistics for time-to-event data, run on the cloud and checked, not assumed.
