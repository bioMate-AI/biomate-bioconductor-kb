# T2 Models and the closed loop — narration (EN)

## Step 1 — Title · how BioMate gets smarter

In Tutorial 1, BioMate proposed and ranked candidate molecules. To rank them, it had to predict things about each one — how strongly it binds the target, whether it's likely to be toxic, how soluble it is. A model is the part that makes those predictions, instead of running a slow, expensive lab experiment every time. The Models area keeps these reusable predictors, and it's the home of the closed loop — the cycle that feeds your real laboratory results back in, so the next round of designs is better. Tutorial 1 showed where candidates come from; this one shows how BioMate learns from what happens to them next: design, make, test, learn, and design again.

---

## Step 2 — Why models matter · trust, and staying current

Relying on predictions instead of experiments raises two problems. First, trust: a prediction is only useful if you know how good the model is and where it can be trusted. A model that has never been tested may give wrong answers with high apparent confidence — and the risk is worse the further your molecule is from what it learned from. Second, staying current: your real lab results are the truth, and a model that never updates with your new measurements slowly drifts away from reality. The Models area addresses both — by treating every model as an inspectable object, and by feeding your results back in. One commercial note: your measurements stay private to your workspace, and are never used to train shared models. Today the loop learns from bench measurements; using clinical readouts to guide it is a direction we're building toward, not a current feature.

---

## Step 3 — The idea · a model is reusable learned expertise

A model takes an input — a molecule, a protein sequence — and returns a prediction, like a score or a three-dimensional structure. Think of it as reusable learned expertise: once it has learned a pattern from data, any project can ask it instead of running the experiment again. Some models are pre-trained by the research community on large public datasets. You'll see four by name: AlphaFold2 and OpenFold2 predict a protein's shape from its sequence; Boltz-2 predicts protein shapes and how a protein and a small molecule fit together; and Evo2 is a model of genome sequences. All four are open and community-built, and BioMate hosts them so you can use them directly. Others are custom — trained on your data to score your kind of molecule. Using a model to predict, without changing it, is called inference.

---

## Step 4 — A model is an object, not a scoreboard

Here is BioMate's guiding idea, and it matters for trust. Instead of ranking models on a scoreboard — which only tempts people to game it — BioMate shows each model like a documented object. Evidence: how well it did on a fair test, against a required quality floor. That floor is measured on a held-out test — data the model was not trained on — so the score can't be inflated by the model simply memorising its training examples. It's like grading an exam with questions the student hasn't seen. Lineage tells you what data and which run produced it; Used-by tells you which analyses depend on it; and every version is kept, never overwritten. Clearing the bar by more earns no higher rank — there's no scoreboard to climb. And if a model hasn't been measured, it reads "not evaluated", rather than showing a made-up score.

---

## Step 5 — Passing the floor isn't the whole story · applicability domain

A good floor score means the model is accurate on test data similar to what it learned from. Whether you can trust it for your specific molecule also depends on the applicability domain — the kind of inputs the model learned from. Ask a model trained on small-molecule kinase inhibitors to score a peptide, and it should report low confidence, because a peptide looks nothing like what it learned from — not pretend to know. Treating an out-of-domain prediction as reliable is a common cause of wet-lab experiments that were never going to work. So a low-confidence prediction usually means your input is unlike the training data — treat it as unproven, a bit like using a drug off-label.

---

## Step 6 — The Models screen · four things you do with a model

The Models screen has four tracks. Run a model does inference — use an existing public model to make a prediction now; it's live, and nothing of yours is trained. Train builds a custom model from your data. Adapt, or House style, gently tunes BioMate's written reports to match how your team works — each learned rule is shown and can be switched off; that's about the style of the writing, not the science. And Optimise, shown as Rounds, is the closed loop. One honest point of scope: Run and the Registry do live work, but Train and Rounds are monitoring views — they show jobs and the running loop, which are launched through a larger drug-discovery campaign. They have no start button on this screen, and show a clear empty state until something is running.

---

## Step 7 — Live · the model Registry

Here it is on dev. The Registry is the list of every model available to your account — each row a model, with its name, family, origin, and how many analyses use it. The community models sit alongside any custom models your team has registered, and a model trained in one project can be used from any other. Clicking a row opens its object view.

---

## Step 8 — Live · the model object

Opening a model shows it as an object. The Evidence tab shows the quality floor — the measured score, the required floor, and the verdict. Here it reads "not evaluated", which honestly means this layer has not measured it — not that a number is hidden. The on-screen note says it plainly: a floor, not a ranking. The other tabs — Lineage, Used by, and Versions — are how you decide whether to trust a model before you use it.

---

## Step 9 — Live · Run a model

To make a prediction now, use Run a model. Pick a domain — Structure, Genomic, or Chemical — paste an input, and run it. For a structure, that's a protein's one-letter sequence. This is inference: the model isn't changed. One caution on the development site: a structure prediction may come back as a clearly-labelled stub — a placeholder that shows the shape of an answer when the heavy model service isn't connected. Always check for that label before trusting any predicted structure.

---

## Step 10 — Live · the Rounds view, and the closed loop in practice

The Rounds view is the home of the closed loop. This is how it looks before any loop has run: it explains what will appear and states the loop's honesty rules — every proposal is accounted for, limit values stay as limits, so "greater than thirty micromolar" is never silently replaced by the number thirty, and rejected candidates stay visible with their reason. Once a design-make-test loop runs in a campaign, the rounds fill in here. Each turn is a round: the model is retrained on the combined data, then re-checked on data it wasn't trained on, so you see it keeping up — not a single score to climb. An illustrative example in rheumatoid arthritis: round one proposes JAK1 candidates, the safety check flags two for predicted hERG liability, the bench confirms it, and those results teach the model; by a later round the top candidate clears the cardiac-safety check while keeping its selectivity. That's an illustration of how the loop is meant to work — not a reported BioMate result.

---

## Step 11 — Closing · the habit at a glance

So the habit is: open a model as an object and read its evidence before you trust it; respect the applicability domain; run a pre-trained model for a quick prediction, watching for a stub; and feed your lab results back through a campaign so each round gets better. Run a model and the Registry are live today. Train and Rounds are monitoring views, driven by a campaign. A model shown as an object, with "not evaluated" said honestly, is the opposite of a scoreboard. And the benefit compounds — three or four rounds beat designing only once, because BioMate records each measurement so you can see the real improvement rather than trusting the system without proof.
