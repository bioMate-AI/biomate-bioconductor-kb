# Tutorial 2 — Models and the closed loop (how BioMate gets smarter)

> **Who this is for:** anyone — no coding or machine-learning background needed. By the end you'll
> understand what a "model" is here, the four things you can do with one, and — most importantly — the
> **closed loop**: how real laboratory results teach BioMate to design better molecules each round.
> **Time:** ~10 minutes to read.
> **Before this:** Tutorial 1 (Design & Generate) shows where the candidate molecules come from. This
> tutorial shows how BioMate *learns* from what happens to them next.

---

## 1. The problem this solves (why models matter)

In Tutorial 1, BioMate proposed and ranked candidate molecules. To rank them well, it has to *predict*
things about each one — for example, "how strongly will this bind our target?", "is this likely to be
toxic to the heart or liver?", "how soluble is it?". A **model** is the part that makes those predictions.
Think of it as reusable, learned expertise: once a model has learned a pattern from data, any project can
ask it for a prediction instead of running a slow, expensive laboratory experiment every time.

Two problems follow from relying on predictions:

1. **Trust.** A prediction is only useful if you know *how good* the model is and *where* it can be
   trusted. A model that has never been tested may give wrong answers with high apparent confidence. The
   risk is even greater if you ask it about molecules very different from those it learned from.
2. **Staying current.** Your real laboratory results are the truth. A model that never updates with your
   new measurements slowly drifts away from reality.

The **Models** area addresses both. It treats every model as an inspectable **object** (you can see who
made it, how good it is, and what it has been used for), and it is the home of the **closed loop** — the
cycle that feeds your real laboratory results back in so the next round of designs is better. Continuing
the rheumatoid-arthritis example from Tutorial 1: if you test a batch of JAK1 candidates at the bench,
those measurements can teach the model, so its *next* set of proposals is more accurate.

> **In one sentence:** Models is where BioMate keeps its reusable predictors and learns from your real
> laboratory results — so the platform gets more accurate every round instead of staying frozen.

> **Why this matters (two ways).**
> - **For a drug program / commercially:** the model learns from *your* measurements, which stay private
>   to your workspace and are never used to train shared models. Each round adds to your team's own
>   knowledge base, which stays with you.
> - **For patients / translation:** better, safer candidate molecules are the starting point for better
>   medicines. Today the loop learns from **laboratory (bench) measurements**; using patient-derived or
>   clinical readouts to guide it is a direction BioMate is building toward, not a current feature.

---

## 2. The ideas you need first (plain-language background)

**A model = reusable learned expertise.** It takes an input (a molecule, a protein sequence) and returns a
prediction (a score, a 3-D structure). Some models are **pre-trained** — built by the research community on
large public datasets. Others are **custom** — trained on *your* data to score *your* kind of molecule.

Four pre-trained models you'll see by name (all open, community-built; BioMate hosts them so you can use
them directly):
- **AlphaFold2** and **OpenFold2** — predict a protein's 3-D shape from its sequence.
- **Boltz-2** — predicts protein 3-D shapes *and* how a protein and a small molecule fit together.
- **Evo2** — a model of DNA/genome sequences.

**A model is an object, not a scoreboard.** This is BioMate's guiding idea, and it matters for trust.
Instead of ranking models on a scoreboard (which tempts people to manipulate it), BioMate shows each model
like a documented object with:
- **Evidence** — how well it did on a fair test, versus a required quality **floor** (see below);
- **Lineage** — what data and which run produced it;
- **Used by** — which analyses rely on it (so you can see the effect of changing it);
- **Versions** — every version is kept, not overwritten.

**A quality "floor", tested fairly.** A model must clear a minimum quality bar before it is trusted. That
bar is measured on a **held-out test** — data the model was *not* trained on, so the score cannot be
inflated by the model simply memorising its training examples. (It is like grading an exam with questions
the student has not seen before, rather than letting them recite the textbook.) Clearing the bar by more
does not earn a higher rank — there is no scoreboard to climb. And if a model has not been measured yet,
BioMate says **"not evaluated"** rather than showing a made-up score.

**Passing the floor is not the whole story.** A good floor score means the model is accurate on test data
*similar to what it learned from*. Whether it can be trusted for *your specific* molecule also depends on
the **applicability domain** — the kind of inputs the model learned from. Ask a model about something far
outside that, and it should lower its confidence instead of pretending to know. (For example: a model
trained on small-molecule kinase inhibitors would report low confidence if asked to score a peptide,
because peptides look nothing like what it learned from.) Treating an out-of-domain prediction as reliable is
a common cause of wet-lab experiments that were never going to work.

**The four things you do with models** (the four "tracks" on the Models screen):
- **Run a pre-trained model** — use an existing public model to make a prediction now. This is called
  **inference** (making a prediction with an already-trained model, without changing it). Nothing of yours
  is trained.
- **Train** — build a new custom model from your data (for example, a scorer for your target).
- **Adapt ("House style")** — gently tune BioMate's written outputs to match how *your* team works, by
  learning from the corrections you make. Nothing changes silently — each learned rule is shown and can be
  switched off. *(This is about the style of BioMate's reports, not the science of a molecule.)*
- **Optimise ("Rounds")** — the **closed loop**, shown as rounds (see §3 and §6).

**The closed loop (the heart of this tutorial).** Drug discovery cannot be done in a single attempt. The
reliable way to improve is to repeat a cycle: **design → make → test → learn → design again.** BioMate
proposes molecules (design), you make and test the best ones at the bench (make and test), the
measurements are fed back to update the model (learn), and the improved model proposes a better next round.
Each turn of this cycle is a **round**.

> **An honest note on what is live today.** Two tracks do live work: **Run a model** (inference) and the
> **Registry** (browse and reuse models). **Train** and **Rounds** are *monitoring views* — they show you
> training jobs and the running loop, which are launched through a larger drug-discovery campaign, and they
> have no "start" button on this screen. On the development site, predicting a protein structure may return
> a clearly-labelled **placeholder** (marked `stub`) when the heavy structure-prediction service is not
> connected — so always check for that label before trusting a predicted structure.

---

## 3. When you'd use this

- **Reuse a model** the community (or another project) already built — e.g., predict a protein's 3-D shape
  before designing against it.
- **Feed lab results back** so the next round of designs is better (the closed loop).
- **Check how far to trust a prediction** before relying on it (open the model object and read its
  evidence and applicability domain).

---

## 4. Step by step — browsing and reusing a model

The most useful first thing to do is inspect a model, so you understand what you are trusting.

![The Models screen](../assets/i10-1-models.png)
*The Models screen, with its tracks across the top and the model families it covers.*

1. **Open Models** (from the home screen, or the `/models` page).
2. **Go to the Registry tab** — the list of every model available to your account (the community models
   named in §2, plus any custom models your team has registered).

![A model shown as an object](../assets/i10-3-model-object.png)
*Opening a model (here Boltz-2) shows it as an object: Evidence, Lineage, Used by, Interface, Versions.*

3. **Open a model** to see its object view. The **Evidence** tab shows the quality floor — the measured
   score, the required floor, and the verdict. (Here it reads "not evaluated", which honestly means this
   layer has not measured it — not that a number is hidden.) The on-screen note says it plainly: *a floor,
   not a ranking.*
4. **Read the other tabs** — **Lineage** (what produced it), **Used by** (what depends on it), and
   **Versions** (its full history). This is how you decide whether to trust a model before you use it.
5. **Reuse it** with **"Use in a run"**, which brings the model into an analysis.

To make a prediction now, use **Run a model**: pick a domain (Structure, Genomic, or Chemical), paste an
input (for Structure, a protein's one-letter sequence), and run it.

---

## 5. How to read the results

- **The quality floor** (on the model object): a model that *passes* is accurate enough on test data
  similar to what it learned from. A model marked **"not evaluated"** has not been measured here — treat
  its predictions with extra caution.
- **Trust for *your* molecule** depends on the applicability domain, not just the floor. If a prediction
  is reported with low confidence, it usually means your input is unlike the model's training data — treat
  that prediction as unproven (similar to using a drug off-label: outside what it was tested for).
- **A limit value stays a limit.** If an assay can only report "activity greater than 30 µM" (because the
  compound was too insoluble to measure higher), BioMate keeps it as "greater than 30", and never silently
  replaces it with the number 30. Preserving these honest limits keeps the model from learning a false
  exact value.
- **Rejected proposals stay visible.** In the closed-loop view, a candidate the safety check rejected is
  still shown, with its reason — so you can always see what the loop wanted to do and why it was stopped.

> **Reminder:** a `stub`/placeholder result is a demonstration of the *shape* of an answer, not a real
> prediction. Check for the label before reading any number. (This appears only on environments where the
> heavy model service is not connected.)

---

## 6. The closed loop in practice (tying it together)

Here is the whole cycle, connecting Tutorial 1 and this one:

1. **Design** — Design & Generate (Tutorial 1) proposes and ranks candidate molecules.
2. **Make and test** — you export the shortlist as an order sheet; chemists make the top molecules and the
   laboratory measures them.
3. **Learn** — the real measurements are fed back and the model is **retrained** on the combined data (what
   it already knew plus the new results). BioMate then re-checks it on data it was *not* trained on. Because
   each round deliberately explores new chemistry, this check shows the model is *keeping up* with the new
   data — it is not a single score to climb.

   *How the hand-back works, in practice:* for each molecule, the lab records its identifier and its measured
   **assay value** with units. (An assay is simply a lab test of activity — for example an IC50, a binding
   strength, or a percent inhibition.) If the test could only report a limit — say "greater than 30 µM"
   because the compound was too insoluble to measure higher — that limit is kept as-is, never replaced by the
   number 30. These results are returned through a **drug-discovery campaign** (the larger cloud workflow),
   not through a button on the Models screen — so in a real project a campaign manager or a cheminformatics
   colleague usually performs this step.
4. **Design again** — the improved model scores the next round of candidates more accurately.

Each loop is a **round**, and the Rounds view is where you monitor it — it shows the rounds so far and each
round's proposed candidates with their verdicts. The benefit grows with
each round: a team that runs three or four rounds ends up with much better candidates than a team that
designs only once — and BioMate records each measurement, so you can see the real improvement rather than
trusting the system without proof.

**An illustrative clinical example (rheumatoid arthritis).** Suppose you want a JAK1 inhibitor that avoids
the heart-rhythm risk (QT prolongation, linked to the hERG channel) and the class-wide infection risks
seen with existing JAK drugs. Round 1 proposes candidates, but the safety check flags two for predicted
hERG liability; the bench confirms it, and those results teach the model. By a later round, the top
candidate clears the cardiac-safety check while keeping its JAK1 selectivity. *(This is an illustrative
example of how the loop is meant to work, not a reported BioMate result.)*

> **Who does what:** a **scientist** decides the shortlist and reads the evidence; the **laboratory** makes
> and measures the molecules; a clinician or biologist often contributes the validated target and the
> real-world safety problems to avoid. BioMate's job is to propose, learn, and show its work.

---

## 7. Key terms

| Term | What it means — and why you care |
|---|---|
| **Model** | Reusable learned expertise that predicts something (a score, a structure) instead of running a lab experiment each time. |
| **Pre-trained model** | A model built by the community on public data (AlphaFold2, Boltz-2, Evo2) that you can use right away. |
| **Custom model** | A model trained on *your* data to score *your* kind of molecule. |
| **Inference** | Using a model to make a prediction, without changing the model. ("Run a model" does inference.) |
| **Retraining** | Updating an existing model with new results — it keeps what it knew and adds the new data. |
| **Model object** | A model shown as inspectable facts — evidence, lineage, what uses it, versions — instead of a scoreboard entry. |
| **Held-out test / floor** | A quality bar measured on data the model was *not* trained on, so the score can't be inflated. A pass means "accurate enough on similar data", not a rank. |
| **"Not evaluated"** | Honest label meaning the quality has not been measured here — not a hidden number. |
| **Applicability domain** | The kind of inputs a model learned from; outside it, predictions come with low confidence (treat as unproven). |
| **Closed loop / round** | The design → make → test → learn → design cycle; each turn is a round, and the model improves each time. |
| **Stub / placeholder** | A clearly-labelled demonstration result returned when a heavy model service is not connected — not a real prediction. |

---

_Companion technical reference (for power users / developers): `docs/user-manual/modules/I10-models.md`._
