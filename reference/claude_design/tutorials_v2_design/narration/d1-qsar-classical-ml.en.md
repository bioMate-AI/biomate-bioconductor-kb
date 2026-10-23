# QSAR — classical machine learning — narration (EN)

One narration block per slide, in order, for edge-tts. Episode D1. Grounded in two real BioMate workflows: `Qsar Rf Model` (pharmacology/qsar_rf_model) and `herg_cardiac_safety_qsar` (pharmacology/herg_cardiac_safety_qsar).

---

## Step 1 — Title · predicting activity and toxicity from structure

QSAR stands for Quantitative Structure–Activity Relationship. The idea is to take a molecule's chemical structure and predict a number from it: how strongly it will hit a target, or how likely it is to be toxic — before the molecule is ever synthesised. This episode teaches the classical machine-learning way to do that: a random forest built on molecular fingerprints. Everything here is grounded in two workflows that run on BioMate today. The first, Qsar Rf Model, predicts activity with a random forest. The second, the hERG cardiac-safety QSAR, screens for cardiac toxicity. Every parameter, output, and quality gate we name is read from those workflows, not invented.

---

## Step 2 — The task · why QSAR exists

The whole field rests on one assumption: molecules that look chemically alike tend to behave alike. If two structures are similar, they usually bind similarly and break down similarly. QSAR makes that assumption quantitative. From molecules you have already measured, you learn a function that maps structure to a number — a potency such as pIC50, or a toxicity such as a hERG IC50 — and then you apply it to molecules you have only drawn on a screen. The input is a structure with nothing yet synthesised; the output is a predicted number with a confidence caveat. The point is triage: score thousands of candidates in minutes, keep the promising ones, and fail the rest cheaply. A QSAR is a filter, not a verdict. It decides what to make and test next; it never replaces the wet-lab assay.

---

## Step 3 — Turning a molecule into numbers · features and the applicability domain

A machine-learning model cannot read a chemical drawing — it needs numbers. So the first step is always to turn a molecule into features, and two families dominate. The first is descriptors: human-readable physicochemical properties like molecular weight, logP, hydrogen-bond donors and acceptors, ring count, and rotatable bonds. These form a short, meaningful vector, and the hERG cardiac-safety model is built on exactly these. The second family is fingerprints: Morgan, or ECFP, fingerprints, where each bit records whether a small circular substructure is present. The Qsar Rf Model uses a 1024-bit Morgan fingerprint at radius two — high-dimensional and sparse. Whichever features you choose, the model is only trustworthy inside its applicability domain: the region of chemistry its training set actually covered. A prediction for a molecule unlike anything the model has seen is extrapolation, however confident the number looks.

---

## Step 4 — Classical ML in depth · the random forest

Now the model itself. A single decision tree splits the feature space with a chain of yes-or-no questions until it reaches a prediction — but one tree overfits its training data badly. A random forest fixes this by growing hundreds of trees, each trained on a bootstrap resample of the compounds and on a random subset of the features. Their individual predictions are then averaged. The disagreement between trees cancels out, and the real signal survives. This is why a random forest suits QSAR fingerprints so well. It handles a thousand sparse binary bits with no feature scaling and no selection. It captures the nonlinear structure–activity relationships that a linear model would miss. Bagging makes it resistant to overfitting, so it stays strong even on a few dozen compounds. And it is almost tuning-free: the real workflow simply uses two hundred trees and a fixed random seed, and it works.

---

## Step 5 — Train, validate, and read the model

Training a model is easy; knowing whether to believe it is the real work. The standard is k-fold cross-validation. You split the compounds into k parts, train on all but one, test on the held-out part, then rotate through until every part has been the test set once, and you average the results. The Qsar Rf Model uses five folds and reports two numbers: the cross-validated R-squared and the cross-validated RMSE. R-squared near one means predictions track reality on data the model never trained on; the quality gate blocks anything below zero point five, following the Golbraikh and Tropsha validation criteria. RMSE is the typical error in the target's own units — read it alongside R-squared. The random forest also gives you feature importance for free: a ranking of which substructures drive the prediction, which turns the model into interpretable structure–activity insight. One caution: with few compounds, cross-validation can look optimistic, so below fifty compounds the workflow raises a bronze advisory.

---

## Step 6 — Classical random forest versus deep-learning ADMET

Deep learning is not automatically better, and it is worth being clear about when each approach wins. A random forest is often the right answer. Choose it when your data is small to medium — tens to a few thousand measured compounds; when your features are tabular or fingerprint-shaped and already informative; when you need interpretability, like feature importance and a defensible record; and when speed and reproducibility matter, since it runs in minutes on a CPU with a fixed seed. A graph neural network earns its extra cost in a different regime. Reach for it when labelled data is large, in the many thousands or more; when the molecular graph itself is the right representation and a fixed fingerprint loses signal; when you want to learn features end to end and exploit pre-training or transfer; and when the extra compute is acceptable for a possible accuracy gain. Start with the random forest; move to the graph network only when the data and the need justify it.

---

## Step 7 — In BioMate · chat, route, run

In BioMate you do not install RDKit or scikit-learn. You describe the analysis in plain language, review the parameters it shows you, confirm, and it runs on hosted compute. Two real workflows cover the two sides of QSAR. For activity, the Qsar Rf Model takes a CSV with a smiles column and a target column — pIC50 by default — and runs a random forest with five cross-validation folds, two hundred trees, and a 1024-bit Morgan fingerprint at radius two; it needs at least ten compounds. For toxicity, the hERG cardiac-safety QSAR takes a list of SMILES, plus an optional measured hERG IC50, a dose in milligrams, and a plasma free fraction; it applies a published physicochemical model over molecular weight, logP, pKa, and cationic density. Both are classical QSAR: one learns a random forest from your measured activities, the other applies a published model together with Nav1.5 structural alerts. No software to license.

---

## Step 8 — In BioMate · interpret the output and the quality gate

Each run writes structured outputs you read directly. The Qsar Rf Model produces a results JSON carrying the cross-validated R-squared, the RMSE, the compound count, and the featurizer that was used, alongside a readable model report. The hERG workflow produces a risk JSON with the predicted hERG IC50, the safety margin, and an ICH E14 risk tier — high, medium, low, or minimal — plus a CSV of any Nav1.5 structural alerts. The quality gate is deliberate: an R-squared below zero point five is a silver, blocking failure, because the model is not fit to trust; fewer than fifty compounds raises a bronze advisory. The gate never passes a weak model silently. And note that the hERG IC50 carries roughly a one log-unit uncertainty by design — it is there to drive the risk tier, not to report a precise potency. Read the tier and the gate together, and do not over-read a single number.

---

## Step 9 — Reading a QSAR with confidence · the applicability domain

Classical QSAR is powerful because it is simple, interpretable, and testable, and reading it well comes down to keeping five things in front of you as you read each prediction. First, the applicability domain: a prediction for chemistry unlike the training set is extrapolation, and unreliable however confident it appears. Second, descriptor choice: change the fingerprint or the descriptor set and the model changes, because there is no single universally best choice. Third, small data: on few compounds even cross-validation can look optimistic, so an external test set is the real check. Fourth, the model itself: the cardiac model is a physicochemical proxy with about one log-unit of error — a risk tier, not a measured IC50. And fifth, provenance: if RDKit is missing, the random forest falls back to mock features, and the featurizer field tells you which, so always verify it reads morgan fingerprint, radius two, 1024 bits. The discipline is always the same — validate before you trust, read the applicability domain, and treat the prediction as a filter that sends the right molecules to the assay, never as a substitute for it.

---

## Step 10 — QSAR at a glance

The habit is short. Bring measured compounds — SMILES paired with a target value. Featurize them, with descriptors or Morgan fingerprints. Train a random forest with five-fold cross-validation. Then read the R-squared, the RMSE, and the risk tier, always within the model's applicability domain. Classical machine learning turns a structure into a defensible prediction: a random forest on fingerprints for activity, a physicochemical descriptor model for cardiac toxicity, both cross-validated and gated. It is the interpretable, data-efficient default. When your data and your question grow, a graph neural network takes the same task further. A QSAR is a filter, not a verdict — the value is in making the right molecules sooner, not in skipping the lab.

---
