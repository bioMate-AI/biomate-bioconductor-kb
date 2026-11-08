# Train a custom model on your own data — narration (EN)

One narration block per scene, in order, for edge-tts. Episode B1. Grounded in BioMate's real `run_code` capability — the LLM-callable Python/R/bash executor (`frontend/server/galaxy-assistant.ts` run_code tool; `frontend/server/code-runner.ts`) whose default sandbox image ships pandas, NumPy, SciPy, scikit-learn, and statsmodels (`frontend/Dockerfile.biotools`). B1 is NOT a fixed Nextflow pipeline; it is the last-resort direct-execution path from the CLAUDE.md "Execution priority order" and the `docs/20261004_DL_ML_MODULE_TUTORIAL_PLAN.md` Track 3 plan. Honesty: a model is an estimate shaped by the user's data; small data overfits; a held-out test set and cross-validation are required; run_code is for ad-hoc, short training jobs.

---

## Step 1 — Title · train a custom model on your own data

You have measurements in a spreadsheet and a column you'd like to predict — whether a compound is active, a concentration, a yield. Normally, acting on that means finding someone who writes machine-learning code. In BioMate, you describe the goal and upload the table, and it runs standard Python machine learning on your data — scikit-learn, and the gradient-boosting or deep-learning libraries when the task needs them — then hands back a trained model with honest, held-out performance. In this walkthrough we'll follow that path from a labeled table to a model you can actually reason about.

---

## Step 2 — The problem this solves

"Can I predict this column from the others?" is one of the most common questions in a lab, and one of the hardest to act on without a dedicated analyst. The gap isn't the idea — it's the plumbing. You have to load the table, split it correctly, pick a model, cross-validate it, score it on data it never saw, and read out which features mattered. Every one of those steps is easy to get subtly wrong. And the most dangerous mistake is the quiet one: score a model on the same data you trained it on, and almost anything looks brilliant. What you actually want is a defensible answer — a model with performance and drivers you could show a reviewer.

---

## Step 3 — The ideas you need first

Four plain words describe the whole task. First, features and label: the features are the columns you measure, and the label is the one column you want to predict — the model learns the link between them. Second, the train-test split: you hold part of the data back, train on the rest, and score on the part the model never saw, because that's the only honest test. Third, the model family: a random forest, gradient-boosted trees, or a small neural network — classification when the answer is a category, regression when it's a number. And fourth, the metric: accuracy or AUC for categories, RMSE or R-squared for numbers — one clear score you can quote. That's the whole vocabulary: features and label, split, model, metric.

---

## Step 4 — How it works · describe and upload, then run

This isn't a fixed pipeline with fixed buttons. It's BioMate's run_code path. You say what you want to predict and attach your table, and BioMate writes and executes standard Python machine-learning code on it, in a sandboxed backend — then reports what it found. The same path that filters a file or runs a statistical test is what trains and evaluates the model here. The environment ships the standard scientific-Python stack — pandas, NumPy, scikit-learn, statsmodels — and runs heavier gradient-boosting or deep-learning libraries in the matching container. It's the same real execution that powers the rest of BioMate, applied to your table.

---

## Step 5 — The input · one labeled table

The only thing you have to prepare is a clean table. Every row is one sample — a compound, a patient, a batch, a cell, whatever you measured. Most columns are the features: the numbers or categories you recorded. And one column is the target — the answer you want to predict. If that answer is a category, like active versus inactive, it's a classification problem; if it's a number, like an IC50 or a yield, it's regression. You tell BioMate which column is the target and which kind of answer you want. It reads the file with pandas and reports the shape, the column types, and any missing values before it trains a thing. If you can export a labeled spreadsheet, you can train a model.

---

## Step 6 — Training · split, cross-validate, fit

With the table loaded, BioMate does the disciplined part automatically. It holds out a test set up front — rows reserved purely to score the finished model. Then, on the training data, it uses cross-validation: splitting into folds and scoring repeatedly, so the performance reflects the data rather than one lucky shuffle. A standard model is fitted on the training rows only — a random forest or gradient-boosted trees for most tabular data, a small neural network where that fits better. And for a small or imbalanced table, it uses stratified folds and simple class balancing to keep the split representative — exactly the kind of detail that's easy to forget by hand. The methodology is built in: train on one part, judge on another.

---

## Step 7 — Evaluation · scored on data it never saw

This is the number that matters, and it's reported honestly — on the test rows the model never trained on, not on the data it memorized. For a category, you get accuracy, AUC, and F1 — each shown as a training score beside the held-out score, so you can see where the mistakes fall. For a number, you get RMSE and mean absolute error in the target's own units, plus R-squared — how much of the variation the model actually explains. And crucially, the training score and the held-out score are shown side by side. A large gap between them means the model memorized rather than learned — the clearest sign of overfitting — and BioMate shows it to you plainly rather than hiding it. That transparency is the entire point of keeping a test set apart.

---

## Step 8 — Feature importance · what drives the prediction

A score on its own is still a black box. So BioMate also reports feature importance — which measurements the model relied on most — and turns the result into something you can reason about scientifically. Often that's where the real insight lives: the model confirming a driver you already suspected, or flagging one you hadn't weighted. One honest caution: importance tells you what the model used, not what causes the outcome. A feature at the top of the ranking is a hypothesis to test, not a mechanism confirmed. Read it as direction — and then verify it in the lab.

---

## Step 9 — Three habits that make it trustworthy

Three habits get the most out of a trained model, so you trust the number for the right reasons. First, start with good data: quality and quantity decide everything, so a clean, well-sized table is the single biggest lever you have on how well the model generalizes. Second, cross-validate on small data — with few rows a single split can mislead, and scoring across folds makes the number reflect the data rather than one lucky shuffle. And third, validate before you rely on it: read the held-out score as a careful estimate, then confirm it on fresh data before you act. A model is an estimate from your data — and used this way, it's one you can genuinely trust.

---

## Step 10 — The value at a glance

The whole point is one sentence: a question you could answer with your own data shouldn't require hiring a machine-learning engineer. You prepare a labeled CSV — feature columns plus one target column. You describe the prediction — classify a category, or estimate a number. BioMate splits the data, cross-validates, and fits a standard model, then gives you the performance on held-out data, the features that drive it, and the honest caveats. From a spreadsheet and a question to a trained, honestly-evaluated, explainable model — run inside BioMate, on your own data. An estimate you can reason about, not a black box.
