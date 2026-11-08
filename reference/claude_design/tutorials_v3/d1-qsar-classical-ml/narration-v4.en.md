# D1 · QSAR with classical ML · narration v4 (EN)

There are 8 blocks, one per scene, in scene order. Each `·` marks a beat, the point where the matching numbered item lights up on screen. The target pace is about 2.4 words per second. Next to each scene is its `data-seconds`. Every number comes from the Qsar Rf Model workflow, except the values the deck tags as illustrative.

---

## 01 · The question (30 s)
You have measured a few dozen compounds, and your chemists have drawn many more. Which of the drawn ones are worth making? QSAR answers that from structure alone. · A structure is written as a SMILES string. · It becomes a fingerprint, a thousand and twenty-four bits. · A model turns that into a predicted potency. In this episode you bring the data, run the workflow, read the results, and take home a report.

## 02 · Why it works, and which model (36 s)
Similar structures tend to behave similarly. Two molecules that differ by one atom usually have close potencies, so a model learned from measured molecules can put a number on new ones. · You learn from what you measured: SMILES paired with pIC50. · You score what you have only drawn, thousands in minutes. · And you start with a random forest. It suits tens to a few thousand compounds and fingerprint features, it shows which features matter, and it runs in minutes. A graph network, episode D2, earns its cost only on much larger data.

## 03 · Data in (40 s)
In BioMate, you attach both files in chat and ask the question in your own words. · BioMate reads the columns. It finds the structure column, smiles, and the target, pIC50, so you don't map anything by hand. · Before anything runs, you see what was read: the first rows and the distribution of potencies. · Then the checks. Forty-two compounds is enough to train, since the minimum is ten. But fewer than fifty is small, so an advisory is recorded and carried through to the report.

## 04 · The workflow, explained in place (44 s)
The workflow has three phases, and every parameter shows where it came from. · First, featurize. Each molecule becomes a Morgan fingerprint of radius two and a thousand and twenty-four bits, where each bit marks one small substructure. · Then train. A random forest grows two hundred trees on resampled data. The trees disagree a little, and their average is the prediction. · Then validate with five-fold cross-validation, and gate. Phase B, which scores your analogues, starts only if the cross-validated R squared reaches zero point five. If the model is weak, no analogue gets a number from it. · Nothing runs until you confirm.

## 05 · Run, validate, gate (34 s)
It runs on hosted compute, with nothing to install, and the steps complete in order. · During cross-validation, each fold holds out one fifth of the compounds. The model trains on the other four fifths and is tested on the fifth it never saw, and the split rotates five times. · The mean across folds is the score you report: a cross-validated R squared of zero point seven two. That meets the criterion, so the gate releases Phase B and the scoring starts.

## 06 · The answer (40 s)
When it finishes, the answer comes first. · Three analogues are worth making: A-07, A-12 and A-03. · They are ranked by predicted pIC50, from seven point four to seven point nine, each named, with its structure and its domain check. · A-30 is different. It is unlike anything in the training set, so it is flagged as out of domain and not ranked. Its number would be an extrapolation. · The same answer appears in chat, concise in the thread and complete in the panel.

## 07 · Can you trust it? (44 s)
Before you make anything, check the evidence under the answer. · The model passed its criterion: a cross-validated R squared of zero point seven two, against zero point five. · On held-out data, the predictions track the measured values along the diagonal. · The shortlisted analogues sit inside the applicability domain, and the points outside it are extrapolations. · One advisory is recorded: with forty-two compounds, cross-validation can look optimistic, and an external test set is the stronger check. · Finally, check the featurizer. The results file should read morgan fingerprint, radius two, one thousand and twenty-four bits, not the mock fallback.

## 08 · Report and close (40 s)
Everything lands in one report, written from the run. · It has the same sections for every run: the question you asked, the answer, the data, and the method. · Then the results, the quality checks and the caveats. These are the same blocks you saw in the panel, not retyped. · You can edit it, by hand or by asking. Your edit is saved as a new version, and the run keeps its original. · Three habits to keep: validate before you trust, read inside the domain, and treat a QSAR as a filter, not a verdict.
