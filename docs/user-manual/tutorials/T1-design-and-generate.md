# Tutorial 1 — Designing new drug molecules (Design & Generate)

> **Who this is for:** anyone — no coding, no cheminformatics background needed. By the end you'll
> understand *what* molecular design is, *why* it's hard, and *how* to run it in BioMate and read the
> results with confidence.
> **Time:** ~10 minutes to read; ~2 minutes to run.

---

## 1. The problem this solves (why you'd ever do this)

A new medicine usually starts as a single **molecule** — a specific arrangement of atoms that sticks to a
disease-related **target** (often a protein) and changes what it does. The hard part is that a useful drug
molecule has to satisfy *several demands at once*:

- it must **bind the target** strongly enough to work (potency),
- it must be **safe** (not hit the heart, the liver, etc.),
- it must be **makeable** in a lab at reasonable cost (synthesizability),
- and it must behave well in the body — get absorbed, not get cleared too fast.

There are more possible drug-like molecules than there are atoms in the solar system. A chemist cannot
draw and test them by hand. **Design & Generate** is BioMate's tool for proposing brand-new candidate
molecules automatically, predicting their properties, throwing out the obviously bad ones, and handing
you a short, ranked list worth looking at. It is the very first step of drug discovery — *before* you
commit any money to making or testing anything.

> **In one sentence:** instead of *you* inventing molecules, BioMate proposes them, scores them, and
> ranks the best — so you start from a shortlist, not a blank page.

---

## 2. The ideas you need first (plain-language background)

You don't need chemistry training, but five concepts will make everything on screen make sense.

**Generate vs. screen.** "Screening" means testing molecules you *already have*. "Generating" (this tool)
means creating *new* molecules that didn't exist before. This tutorial is about generating.

**Seed molecule.** The generator doesn't start from nothing — you give it a **seed**: a known molecule to
build variations around. Think of it like giving a composer a melody to riff on. (In the example below we
use aspirin as the seed, simply because everyone knows it.)

**Scaffold, and "stay / hop / grow."** The **scaffold** is a molecule's core skeleton — the part that
usually gives it its shape and function. You tell BioMate how adventurous to be:
- **Stay** — keep the same core, vary the decorations around it (safe, conservative).
- **Hop** — jump to a *different* core that should still fit the target ("scaffold hopping" — useful to
  get around a competitor's patent, or to escape a toxic core).
- **Grow** — start from a small fragment and build it up into a full drug-sized molecule.

**The property "envelope" (a window, not a hard rule).** Decades of data show drugs that get absorbed
tend to fall in certain ranges of size and oiliness — e.g. molecular weight (**MW**), fat-vs-water
balance (**logP**), and surface polarity (**TPSA**). BioMate lets you set a *target window* for these.
It's a soft preference used for ranking, **not** a hard cut-off — a promising molecule just outside the
window isn't thrown away, it's scored slightly lower. (Note: large molecules like **peptides** live
*outside* the classic small-molecule window — which is exactly why they're a distinct modality.)

**Multi-objective (why there's no single magic score).** You want potency *and* safety *and*
makeability — and these fight each other (the most potent molecule is often the least safe). So BioMate
shows each objective **separately, in its own units**, and never blends them into one fake "overall"
number that hides the trade-off. *You* decide how to weigh them. This honesty is deliberate: a single
blended score would let a dangerous molecule look good.

**The safety gate.** Some chemical sub-structures are known troublemakers (reactive or toxic groups). Any
candidate containing one is **flagged and set aside — but still shown to you, with the reason**. BioMate
never silently hides a result; safety is a gate you can see, not a secret filter.

---

## 3. When you'd use this

- You have a validated target and want a first batch of candidate molecules to consider.
- You have a promising molecule but need **safer or more makeable** variations around it.
- You need to **design around** an existing patent (scaffold-hop to a new core).
- You're building a **cyclic-peptide / macrocycle** program (BioMate's focus area) and want candidates
  for a hard-to-drug target. *(See the honesty note at the end on what runs today.)*

---

## 4. Step by step

![The Design & Generate form](../assets/i11-1-design.png)
*The Design & Generate screen. You fill in a few constraints, then click "Generate & rank."*

1. **Open Design & Generate.** From the home screen choose "Design & generate," or go to the `/design`
   page. You'll see the form above — a set of constraints, not a chat box.
2. **Choose the modality** — *Small molecule*, *Peptide*, or *Protein / biologic*. This tells BioMate what
   kind of molecule to build. (Start with Small molecule; see the note at the end on peptides.)
3. **Give a seed** in the "Target / seed" box — the molecule to build around. In our walk-through we use
   aspirin (`CC(=O)Oc1ccccc1C(=O)O`, a text code for its structure).
4. **Pick the scaffold policy** — Stay, Hop, or Grow (see §2). "Stay" is the safe default.
5. **Set the property window** — Molecular weight, logP, TPSA. The defaults are sensible drug-like values;
   leave them unless you have a reason.
6. **(Optional) exclusions and seed series** — chemical groups to ban, or a few known molecules for the
   tool to learn from.
7. **Set how many candidates to keep** and click **Generate & rank.** It runs in seconds and the results
   appear in the same panel.

---

## 5. How to read the results

![Ranked candidates, scored on each objective separately](../assets/i11-3-multi-objective.png)
*Every candidate gets its own row. Each objective keeps its own column and units — nothing is blended.*

- **Each row is one proposed molecule** (BM-0001, BM-0002, …).
- **Each objective has its own column** — here `drug_like` (a 0–1 quality score) and `property_envelope`
  (how well it fits your window). You see the trade-off directly.
- **"score\*" is only a ranking key**, not a quality verdict — it just orders the list. The asterisk and
  footnote say so on screen, on purpose.
- **Verdict** — *Accepted* passed the gates; *Rejected* tripped the safety gate. **Rejected molecules stay
  visible with their reason** — so you learn *why*, and nothing is hidden.
- **"why?"** on each row explains how that molecule was scored (and the nearest real molecule it
  resembles), so a result is never a black box.
- A healthy run also shows a **trade-off (Pareto) plot** — a picture of "you can't improve one objective
  without sacrificing another" — and a **rejection profile** telling you *why* candidates were dropped (a
  high rejection rate is the fastest signal your seed or constraints need adjusting).

> **If you get no results:** BioMate tells you *which kind* of empty it is. "All candidates were gated
> out" means tighten/loosen your constraints (something you can act on). "Temporarily unavailable" means
> it's a problem on our side, not your inputs — nothing for you to change.

---

## 6. What happens next — the closed loop

A shortlist is only the beginning. From the results you can **export an order sheet** — a file that pairs
each candidate with a lab ID so chemists can actually make and test the top molecules. When the lab
results come back, they feed into BioMate's **Models** module (Tutorial 2), which *learns* from the real
measurements and proposes a better next round. That cycle — **design → make → test → learn → design
again** — is the "closed loop," and it's the heart of how BioMate gets sharper with every round.

---

## 7. Key terms

| Term | Plain meaning |
|---|---|
| **Target** | The protein (or other molecule) in the body a drug is meant to act on. |
| **Seed** | A known molecule you ask BioMate to build variations around. |
| **Scaffold** | A molecule's core skeleton; "hopping" means switching to a different core. |
| **MW / logP / TPSA** | Size, oiliness, and surface polarity — rough predictors of how well a molecule is absorbed. |
| **Multi-objective** | Optimising several competing goals (potency, safety, makeability) at once, shown separately. |
| **Safety gate** | An automatic check that flags molecules containing known-toxic sub-structures. |
| **Pareto / trade-off** | The set of candidates where you can't improve one goal without hurting another. |
| **Closed loop** | Feeding real lab results back in so the next round of designs is better. |

---

> **Honest note on what runs today.** Right now the **small-molecule** generator is live end-to-end;
> **peptide and protein** modalities show the form and capture your settings but don't yet produce
> candidates (a notice says so on screen). BioMate also never invents a potency or toxicity *number* it
> can't stand behind — where it has no trustworthy predictor, it says "not available" rather than guess.

_Companion technical reference (for power users / developers): `docs/user-manual/modules/I11-design-and-generate.md`._
