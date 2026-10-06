# T1 Designing new drug molecules (Design & Generate) — narration (EN)

## Step 1 — Title · design new drug candidates from a seed molecule

A new medicine usually begins as a single molecule — a specific arrangement of atoms that sticks to a disease-related target, usually a protein, and changes what it does. Design and Generate is the BioMate tool that proposes brand-new candidate molecules, scores them, sets aside the clearly unsafe ones, and hands back a short, ranked list — in minutes, not months. It's the very first step of drug discovery, before you spend money making or testing anything. We'll go from the form, to the ranked candidates, to the trade-off view, and then see how real lab results feed the next round.

---

## Step 2 — Why this is hard · the problem it solves

Here's the squeeze. The number of drug-like molecules is about ten to the sixtieth — more than the stars in the observable universe. No chemist can draw and test even a fraction by hand. And a useful drug has to satisfy four demands at the same time: it must bind the target strongly enough to work; it must be safe, not damaging the heart or the liver; it must be makeable in a lab at reasonable cost; and it must behave well in the body — absorbed, and not cleared away too quickly. Narrowing that space to a first testable shortlist normally takes a chemistry team many months. This tool does that first filtering automatically.

---

## Step 3 — The ideas you need first · generate, seed, SMILES

A few plain words make everything on screen make sense. Screening tests molecules you already have; generating — this tool — creates new ones. The generator doesn't start from nothing: you give it a seed, one known molecule to build variations around, like handing a composer a melody. A seed is entered as a SMILES string — a standard text code for a structure; aspirin, for instance, is C-C, parenthesis O, and so on. You don't type these by hand — you copy the canonical SMILES from a free database like PubChem or ChEMBL. And keep target and seed separate: your target is a protein, like JAK1; the seed is a small molecule. If you only have the target, look up a known binder and use its code. And here's how it generates: BioMate systematically enumerates chemically sensible variations around the seed you supply, then screens and ranks them — so every candidate is a deliberate, inspectable variation on a structure you chose, not a black-box guess.

---

## Step 4 — How adventurous to be · the scaffold policy

The scaffold is a molecule's core skeleton — the part that gives it its basic shape. You tell BioMate how far from the seed to roam, with one setting. Stay keeps the same core and varies only the decorations around it — conservative, and the safe default. Hop moves to a different core that should still fit the target; chemists do this to avoid a competitor's patent, or to escape a core that causes toxicity. And Grow starts from a small fragment and builds it up into a full drug-sized molecule. One control, three levels of ambition.

---

## Step 5 — The property window · a preference, not a rule

Decades of data show that molecules which get absorbed tend to fall within certain ranges of three measurable properties: molecular weight, which is roughly size; logP, how oily versus water-loving it is; and TPSA, how much of its surface is polar. Together, these predict whether a molecule can be an oral pill, how easily it crosses cell membranes, and whether it can reach targets inside the cell or the brain. BioMate lets you set a target window for these — but it's a soft preference used for ranking, not a strict cut-off. A promising molecule just outside the window isn't removed; it simply scores a little lower.

---

## Step 6 — Multi-objective scoring · goals kept separate, safety visible

You want a molecule that is potent and safe and makeable — and these goals pull against each other. So BioMate shows each goal separately, in its own units, and never blends them into one overall number, because a single blended score could let an unsafe molecule hide behind a good average. You decide how to weigh them. Safety is handled as a visible gate: known-risky substructures, called structural alerts, are flagged with the reason and set aside — but still shown, never hidden. What each candidate is scored on is clear: its drug-likeness, how well it fits your property window, and that visible safety gate. And every candidate is shown next to its nearest known real molecule, so each score stays grounded in something real.

---

## Step 7 — Step by step · the Design and Generate form

Here's the real Design and Generate form in the live product. It's a set of constraints, not a chat box. You pick the modality — start with Small molecule — then give a seed SMILES in the target-slash-seed box. You choose the scaffold policy, Stay, Hop, or Grow, and set the property window: molecular weight, logP, and TPSA, with sensible defaults already filled in. Exclusions and a seed series are optional, safe to skip on a first run. Then you set how many candidates to keep and press Generate and rank — it finishes in under a minute, and the results appear in the same panel.

---

## Step 8 — Reading the results · the multi-objective view

Now the results. Each row is one proposed molecule — BM-0001, BM-0002, and so on. Each goal keeps its own column, so you see the trade-off directly, side by side — nothing blended into a single number. The column labelled "score-star" is only a ranking key, not a quality verdict; the on-screen footnote says so on purpose. The Verdict column shows Accepted or Rejected — and rejected molecules stay visible, with their reason, so you learn why nothing is hidden. And "why?" on each row explains how that molecule was scored, including the nearest real, known molecule it resembles.

---

## Step 9 — The trade-off chart · Pareto and rejections

The results page also shows a trade-off chart — a Pareto view. Read it like this: each dot is a candidate, and the dots along the front boundary are the best available compromises. To make one of them better on one goal, you'd have to accept it being worse on another; you pick from that boundary based on what matters most to you. Alongside it, a rejection summary tells you why candidates were dropped. A high rejection rate is the clearest signal that your seed or your constraints need adjusting — a useful diagnostic, not a failure. And if you get no results, BioMate tells you which kind of empty it is: something you can act on, or a problem on our side.

---

## Step 10 — What happens next · the closed loop

A shortlist is a starting point, not a finished drug — these candidates are still a long way from the clinic, and the value is starting smart. From the results you can export an order sheet: a file pairing each candidate with a lab ID, so chemists can actually make and test the top molecules. When the lab results come back, they feed BioMate's Models module, Tutorial 2, which learns from the real measurements and proposes a better next round. Design, make, test, learn, design again — that's the closed loop, and it's how BioMate gets more accurate every round. And the small-molecule generator runs end-to-end today — seed in, a ranked and grounded shortlist out, ready to hand to the lab.

---

## Step 11 — Closing · the habit at a glance

So the habit is simple. Pick a modality and give one seed molecule — looked up, not hand-typed. Choose how far to roam and set the property window. Generate and rank, then read each goal in its own column, follow the "why?", and pick from the trade-off front. Export the order sheet, and let real lab data close the loop. Small-molecule generation, multi-objective ranking, and the visible safety gate all run today, and every candidate is grounded against its nearest known real molecule. A shortlist is in-silico triage, not a finished drug: the point is to start smart.

---
