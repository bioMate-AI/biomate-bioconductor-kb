# T2 Models and the closed loop — narration (EN)

## Step 1 — Title · how BioMate gets smarter

In Tutorial 1, BioMate proposed and ranked candidate molecules. To rank them, it had to predict things about each one — how strongly it binds the target, whether it's likely to be toxic, how soluble it is. A model is the part that makes those predictions, instead of running a slow, expensive lab experiment every time. The Models area keeps these reusable predictors, and it's the home of the closed loop — the cycle that feeds your real laboratory results back in, so the next round of designs is better. Tutorial 1 showed where candidates come from; this one shows how BioMate learns from what happens to them next: design, make, test, learn, and design again.

---

## Step 2 — Why models matter · trust, and staying current

Relying on predictions instead of experiments raises two problems. First, trust: a prediction is only useful if you know how good the model is and where it can be trusted. A model that has never been tested may give wrong answers with high apparent confidence — and the risk is worse the further your molecule is from what it learned from. Second, staying current: your real lab results are the truth, and a model that never updates with your new measurements slowly drifts away from reality. The Models area addresses both — by treating every model as an inspectable object, and by feeding your results back in. And one point that matters for a drug program: your models and your measurements stay private to your workspace, and are never used to train shared models. The loop learns from your own real laboratory measurements and feeds them straight back into the next round of designs.

---

## Step 3 — The idea · a model is reusable learned expertise

A model takes an input — a molecule, a protein sequence — and returns a prediction, like a score or a three-dimensional structure. Think of it as reusable learned expertise: once it has learned a pattern from data, any project can ask it instead of running the experiment again. Some models are pre-trained by the research community on large public datasets. You'll see four by name: AlphaFold2 and OpenFold2 predict a protein's shape from its sequence; Boltz-2 predicts protein shapes and how a protein and a small molecule fit together; and Evo2 is a model of genome sequences. All four are open and community-built, and BioMate hosts them so you can use them directly. Others are custom — trained on your data to score your kind of molecule. Using a model to predict, without changing it, is called inference.

---

## Step 4 — A model is an object, not a scoreboard

Here is BioMate's guiding idea, and it matters for trust. Instead of ranking models on a scoreboard — which only tempts people to game it — BioMate shows each model like a documented object. Evidence: how well it did on a fair test, against a required quality floor. That floor is measured on a held-out test — data the model was not trained on — so the score can't be inflated by the model simply memorising its training examples. It's like grading an exam with questions the student hasn't seen. Lineage tells you what data and which run produced it; Used-by tells you which analyses depend on it; and every version is kept, never overwritten. Clearing the bar by more earns no higher rank — there's no scoreboard to climb. And where a model has not been scored, it reads "not evaluated" rather than inventing a number — so you never stake a wet-lab program on a confident-looking guess. That honesty is the point: the model tells you what it has proven, and what it has not.

---

## Step 5 — Passing the floor isn't the whole story · applicability domain

A good floor score means the model is accurate on test data similar to what it learned from. Whether you can trust it for your specific molecule also depends on the applicability domain — the kind of inputs the model learned from. Ask a model trained on small-molecule kinase inhibitors to score a peptide, and it should report low confidence, because a peptide looks nothing like what it learned from — not pretend to know. Treating an out-of-domain prediction as reliable is a common cause of wet-lab experiments that were never going to work. So a low-confidence prediction usually means your input is unlike the training data — treat it as unproven, a bit like using a drug off-label.

---

## Step 6 — The Models screen · four things you do with a model

The Models screen gives you four ways to put a model to work. Run a model does inference — use a community model to make a prediction straight away; nothing of yours is trained. Train builds a custom model on your own data — a scorer tuned to your target and your chemistry. Adapt, or House style, gently tunes BioMate's written reports to match how your team works — each learned rule is shown and can be switched off; that's about the style of the writing, not the science. And Optimise, shown as Rounds, is the closed loop, where real lab results compound into better designs. From a single prediction to a custom scorer to the full closed loop, the same inspectable, versioned models underpin all four.

---

## Step 7 — Live · the model Registry

This is the live product. The Registry is the list of every model available to your account — each row a model, with its name, family, origin, and how many analyses use it. The community models sit alongside any custom models your team has registered, and a model trained in one project can be used from any other. Clicking a row opens its object view.

---

## Step 8 — Live · the model object

Opening a model shows it as an object. The Evidence tab shows the quality floor — the measured score, the required floor, and the verdict. Here it reads "not evaluated" — the model stating honestly that it has not yet been scored, rather than showing a confident-looking number it cannot back up. The other tabs — Lineage, which data and run built it; Used by, what depends on it; and Versions, where nothing is overwritten — are how you decide whether to trust a model before you use it. You read the full evidence before you trust a prediction, not after.

---

## Step 9 — Live · Run a model

To make a prediction now, use Run a model. Pick a domain — Structure, Genomic, or Chemical — paste an input, and run it. For a structure, that's a protein's one-letter sequence. This is inference: the model isn't changed, and the result is attributed to the exact model and version that produced it, so you always know what made the prediction.

---

## Step 10 — Live · the Rounds view, and the closed loop in practice

The Rounds view is the home of the closed loop, and here is the working behaviour behind it. As a round runs, a safety and QC gate checks every candidate against its threshold. When one crosses the line — say, a predicted hERG liability past the cardiac-safety limit — the gate halts that candidate and suggests an advisory fix, such as a tighter limit, which you confirm; it does not re-run on its own. Then your real bench results feed the next round: the model is retrained on the combined data and re-checked on data it wasn't trained on, so each round builds on measured ground truth rather than a single score to chase. The view keeps every proposal accounted for, holds limit values as limits — so "greater than thirty micromolar" is never silently replaced by the number thirty — and keeps rejected candidates visible with their reason. As a general illustration: a candidate predicted to carry hERG liability is flagged at the gate, a tighter limit is suggested, and a later round clears the cardiac-safety check while keeping selectivity — that is how the loop works, round after round.

---

## Step 11 — Closing · the habit at a glance

So the habit is: open a model as an object and read its evidence before you trust it; respect the applicability domain; run a community model for a quick prediction, with no training needed; and feed your real lab results back in, where the safety gate guards each round. Your models and your data stay private to your workspace. A model shown as an object — with "not evaluated" said honestly where it hasn't been scored — is the opposite of a scoreboard, and it answers a real pharma concern: you know exactly what you are trusting. And the value compounds, because the closed loop is built to make each round more accurate than the last, grounded in your own measurements.
