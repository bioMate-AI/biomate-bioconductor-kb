# Non-compartmental PK analysis (NCA) — narration (EN)

One narration block per scene, in order, for edge-tts. Episode S1. Grounded in BioMate's real Nca Pknca workflow (PKNCA R package; `nextflow_nfcore/subworkflows/drug_discovery/nca_pknca/main.nf`) and the Dose Response / Exposure Response companion workflows. No result values are invented; staged example input is `test-data/pk_concentration_time.csv`.

---

## Step 1 — Title · a concentration-time curve becomes defensible exposure numbers

You dosed an animal or a subject, and you sampled the blood over time — so you have a table of concentration against time. The questions that matter are simple: how much drug was there, and for how long? Non-compartmental analysis — NCA — answers them directly from the observed curve, with no model fitted and no mechanism assumed. BioMate runs the standard NCA pipeline, built on the PKNCA R package, on cloud compute. You give it a concentration-time CSV and the dose, and it returns the area under the curve, the peak, the half-life, the clearance and the volume — with a report you can hand to a regulator. In this walkthrough we'll follow that real workflow end to end.

---

## Step 2 — The problem this solves

Every pharmacokinetic study starts with the same ask: summarise how much drug the body saw, and how long it stayed. The numbers that answer it are standard — the area under the curve, the maximum concentration, the half-life, the clearance. But they are easy to get subtly wrong. Which trapezoidal rule do you use? How do you fit the terminal slope for the half-life? How much of the tail did you extrapolate to reach total exposure? Get those conventions wrong and the exposure estimate drifts — and a study you can't defend is a study you can't submit. What you actually want is the standard parameters, computed by the accepted conventions, reproducibly, every time.

---

## Step 3 — The ideas you need first

Four plain ideas are the whole of NCA, and none of them needs a differential equation. First, the curve itself: drug concentration at each sampling time, for each subject — everything else is derived from it. Second, the area under that curve, the AUC: total exposure. AUClast is the area out to your last sample; AUCinf is extrapolated to infinity. Third, the peak: Cmax, the highest concentration you observed, and Tmax, when it happened — the absorption phase in two numbers. And fourth, the tail: from the terminal slope come the half-life, and the clearance and volume that follow from it. The key word is model-independent. NCA summarises the observed data by established conventions, rather than fitting a mechanistic model. That's its strength — and its boundary, which we'll return to at the end.

---

## Step 4 — In BioMate · goal plus a CSV becomes a run

In BioMate you state the goal in plain language — run non-compartmental PK on this concentration-time table — and you attach the CSV. BioMate routes it to the Nca Pknca workflow, the one built on the PKNCA R package, fills in the dose and route, and runs a three-step pipeline on cloud compute. The steps are named plainly: validate the input, compute the parameters with PKNCA, and render an HTML report. The only required input is the concentration-time CSV itself; the dose, the route, and the unit labels are parameters with sensible defaults you can override. And there's staged example data to try it against — a concentration-time table at test-data slash pk-concentration-time dot csv.

---

## Step 5 — The input · the concentration-time table

NCA needs the observed curve in a defined shape, and the first step checks that before any computation runs. Each row of the table is one sample, and it carries five columns: a subject identifier, the time, the concentration, the dose, and the route. The validation step confirms those columns are present and the values are plausible — it floors negative concentrations to zero and rejects negative times, so a malformed table fails fast and surfaces the problem rather than producing a quiet, wrong answer. Alongside the table you set the study design: the dose, and the route — oral or intravenous, which maps internally to extravascular or intravascular and governs which parameters are even defined. And you label the units — hours and nanograms per millilitre by default — so the derived AUC, clearance and volume units in the report are stated, not guessed.

---

## Step 6 — The computation · PKNCA, per subject

The core step runs R slash PKNCA over the validated curve and computes the standard NCA parameter set for each subject, using the linear-up, log-down trapezoidal method. These are the numbers a PK report is built from. AUClast — the area out to the last measured sample, exposure you observed directly. AUCinf — that area extrapolated to infinity using the terminal slope, total exposure. Cmax and Tmax — the peak and when it occurred. The terminal half-life, from the log-linear tail. And the apparent clearance and apparent volume of distribution, CL over F and Vd over F. The per-subject results land in a results CSV, and the population statistics — mean, standard deviation, and coefficient of variation — in a summary JSON. The method and the software version are recorded with them. Every parameter is a summary of the observed curve; nothing is fit to a compartment model. And note the word apparent: for extravascular dosing, absolute bioavailability needs an intravenous reference.

---

## Step 7 — In context · from exposure to effect

NCA tells you how much drug was present. To close the loop, you ask how that exposure translates into an effect — and BioMate has companion workflows for exactly that step. The Dose Response workflow fits a four- or five-parameter log-logistic curve to concentration-effect data, estimating the IC50 or EC50 and the Hill slope. The Exposure Response workflows fit sigmoid Emax models, linking an exposure metric — like the AUC that NCA just produced — to a measured outcome. Put the links together and you have a chain: the observed curve gives you exposure, exposure-response gives you the exposure that produces the effect, and that points you to a dose. Each link is a real BioMate workflow. NCA is the exposure anchor at the front of that chain — it produces the inputs the later steps consume; it does not itself model the effect.

---

## Step 8 — Interpretation · what each number means for dosing

The report lays the parameters out with a log-linear concentration-time plot, a per-subject table, and a stated assumptions section. Here is how to read the headline numbers. The AUC answers whether exposure is adequate — too low and the drug under-exposes, too high and you risk toxicity — and across dose levels it tests dose-proportionality. Cmax and Tmax describe how fast and how high: a sharp early peak means rapid absorption, relevant to peak-driven effects; a late Tmax suggests slow or extended-release absorption. The terminal half-life sets the dosing interval and how long until steady state. And clearance and volume scale the dose — clearance drives the maintenance dose for a target exposure, and the apparent volume relates a dose to the concentration it produces. Each parameter reads straight back to a dosing decision.

---

## Step 9 — What NCA is for · the conventions that make it defensible

NCA is trustworthy precisely because its scope is explicit and its conventions are fixed — and the pipeline states its own assumptions and runs quality gates on every run. First, it is sampling-dependent. Tmax can only ever be a time point you actually sampled, and the half-life needs at least three terminal points to fit the slope; the pipeline flags any subject with no terminal slope. Second, extrapolation is a watched quantity — AUCinf relies on extrapolating the tail, so a QC gate checks the extrapolated fraction stays within twenty percent, the FDA bioavailability convention, because a large extrapolation makes total exposure unreliable. And third, the handoff: NCA summarizes the exposure in the data you have; when you need to predict a new dose, a drug interaction, or a special population, a PBPK model — which BioMate also runs — carries it forward. NCA's stated assumptions are linear pharmacokinetics, a single-dose design, adequate terminal sampling, and terminal log-linearity, and it does not detect flip-flop kinetics. It is a focused, rigorous tool: the standard exposure summary, computed by the accepted conventions.

---

## Step 10 — The value at a glance

The whole point is one sentence: exposure should be computed the standard way, from your observed data, with the conventions and the assumptions written down. You attach a concentration-time CSV, you set the dose, route and unit labels or take the defaults, you confirm the routed Nca Pknca workflow, and BioMate validates the curve, computes the area under the curve, the peak and its timing, the half-life, the clearance and the volume with PKNCA, runs its quality gates, and renders a report — on cloud compute, with a record you can defend. You get per-subject parameters, a population summary, and an HTML report. From an observed concentration-time curve to the standard exposure parameters, computed by convention and reproducibly — model-independent, rigorously bounded, and ready to anchor the dose-selection chain.
