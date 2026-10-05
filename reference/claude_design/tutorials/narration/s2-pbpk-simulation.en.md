# S2 — PBPK simulation walkthrough narration (EN)

> Statistical series, Episode S2 — PBPK, a mechanistic statistical model.
> One block per slide, for edge-tts. Keep spoken-plain: expand symbols,
> spell risky abbreviations on first use. Timings live in the HTML `data-seconds`.

## Step 1 — Title · predict a drug's concentration over time

A binding score tells you whether a molecule grabs its target. It tells you nothing about the question a clinician actually asks: once a patient takes a dose, how high does the drug go, how long does it stay, and where in the body does it end up? That is pharmacokinetics, and the mechanistic way to predict it is a model called P-B-P-K — physiologically-based pharmacokinetics. In this episode we build that idea from the ground up, and then show how BioMate runs it. We use three familiar drugs — aspirin, caffeine, and ibuprofen — purely to make the mechanics concrete. Everything here is a mechanistic projection for reasoning and triage, not a clinical dose recommendation. And the one claim to hold onto from the start is this: BioMate runs the real, published solver — it never asks a language model to guess a concentration.

---

## Step 2 — Idea · the concentration–time curve

Start with what we are trying to predict: a single curve. After a dose, the drug's concentration in plasma rises as it is absorbed, reaches a peak, and then falls as the body distributes, breaks down, and excretes it. Almost every dosing decision rests on four numbers read off that one curve. Cmax is the peak concentration. Tmax is the time at which that peak occurs. A-U-C, the area under the curve, is the total exposure over time. And the half-life is how quickly the drug clears, read from the downward slope. Too low a peak and the drug never works; too high and it risks toxicity. The same curve, computed for different tissues and different populations, is what turns a molecule into a dosing plan.

---

## Step 3 — Idea · why PBPK is hard

Here is the honest difficulty. A PBPK model is a system of coupled differential equations — one mass-balance equation for each organ — driven by physiology, like blood flows and organ volumes, and by the molecule's own properties. Those molecular properties are the hard part. You need physicochemical inputs: molecular weight, lipophilicity, and the acid-base constant, which together set how the drug partitions into tissue. You need A-D-M-E inputs: intrinsic clearance, the unbound fraction in plasma, and renal clearance — and these are themselves usually measured estimates or predictions, rarely exact. The equations are standard and well established. Choosing and justifying the parameters is the real work — and because errors in the inputs propagate straight through to the curve, a wrong clearance or binding value shifts the whole prediction. That is why BioMate exposes every input for you to check and override before the solver runs.

---

## Step 4 — Idea · the NCA baseline

Before the model, the baseline. If you already have measured concentrations from an actual study, you do not need a model at all. Non-compartmental analysis — N-C-A — makes no assumption about organs. Given an observed concentration–time table, it reads the numbers straight off the data: the area by the trapezoidal rule, the observed peak, the terminal slope for half-life. It is the honest, model-free yardstick that PBPK is measured against, and BioMate ships it as the Nca Pknca workflow, built on the R PKNCA package. The contrast is the whole point of this episode. NCA describes data you already have — it cannot tell you what happens at a new dose, in a child, or in a patient with kidney disease. PBPK predicts forward from physiology into exactly those scenarios you have no data for. That forward step is what NCA cannot take.

---

## Step 5 — Idea · mechanistic PBPK, organ compartments

Now the model itself. BioMate's native engine represents the body as eight linked compartments: the gut lumen and gut wall, the central blood pool, the liver — where first-pass metabolism happens — the lung, the kidney, and a lumped peripheral tissue. Blood flow links the compartments; tissue partition coefficients set how far the drug spreads into each organ; and a well-stirred clearance model governs how the liver and kidney remove it. The whole system is integrated over time by a SciPy LSODA differential-equation solver. None of this is invented for the demo: the tissue partitioning follows Poulin and Theil and Rodgers and Rowland; the physiology database follows Willmann; the hepatic clearance follows the well-stirred model of Wilkinson — the same published methods that sit behind commercial tools. You give it the molecule and the dose; it returns the full concentration–time profile and the standard PK parameters. And the licensed engines — Simcyp, and the open-source, EMA-accepted PK-Sim — are wired in too, with automatic fallback to this native engine when no licence is present.

---

## Step 6 — Idea · special populations

This is the real reason to go mechanistic rather than empirical. Because the model is built on physiology, a child, a pregnant patient, or a patient with organ impairment is not a brand-new model — it is the same equations with different physiological parameters. BioMate ships a dedicated workflow for each, grounded in regulatory guidance. The pediatric model applies enzyme-maturation functions for the major drug-metabolising enzymes, from Bjorkman and Johnson, with age-scaled organ volumes from WHO growth data. The pregnancy model adds trimester-by-trimester changes — plasma-volume expansion, a rise in kidney filtration, enzyme induction, and a fetal compartment, following Jeong. The disease-state model carries renal submodels staged by kidney function per FDA 2010 and I-C-H E7, and hepatic submodels staged by Child-Pugh class per FDA 2003. The disease-state workflow even emits exposure ratios versus normal, a dose-adjustment suggestion, and draft label text for the "Use in Specific Populations" section of a regulatory submission — a projection for a pharmacologist to review, never something auto-submitted.

---

## Step 7 — In BioMate · chat, route, run the real solver

Here is how you actually use it. You describe the scenario in plain English — for example, simulate oral aspirin, five hundred milligrams, P-B-P-K, in a healthy adult. BioMate routes that to the pbpk_simulation workflow, opens its panel, and shows every parameter — dose, route, clearance, unbound fraction, population — editable before anything runs. You confirm, and the ODE model executes on managed cloud compute. Then the key honesty step: the PK parameters reported back are read straight from the solver's output files, not written by a language model. What comes back is a concentration–time profile for blood, liver, and kidney, and a parameters file with Cmax, total exposure, time-to-peak, half-life, clearance, the steady-state volume of distribution, and oral bioavailability. The language model's job here is routing and explanation. The numbers come from the solver.

---

## Step 8 — In BioMate · reading the result, with gates on the physics

A PBPK result is only trustworthy if the simulation itself was physically sound, so BioMate runs four quality gates on every run. The mass-balance gate checks that all the drug is accounted for — the sum of what is in the compartments plus what has been excreted must recover to the dose, confirming the equations conserved mass. The Tmax-fraction gate checks the peak actually falls inside the simulated window, so the curve was not clipped by too short a run. The clearance-floor gate checks that the implied clearance is physiologically plausible. And the fold-error gate — when you supply an observed AUC — reports how far the prediction lands from reality and whether it is within two-fold, the standard the FDA uses. But be precise about what these gates mean: they check the internal consistency of the simulation — that the maths held. They do not, on their own, certify that the prediction matches a real patient; only the observed-AUC comparison does that. So read Cmax, AUC, and half-life as a mechanistically-consistent projection to reason with, and anchor it to in-vivo data whenever you have any.

---

## Step 9 — Honest limits · PBPK is hard, and the benchmark says so

Now the caveat we put front and centre rather than hide. PBPK prediction is genuinely difficult. BioMate measures it with a RealBio benchmark — fifteen reference compounds with published human pharmacokinetics, taken from FDA drug labels, DrugBank, and the peer-reviewed literature, scored objectively, with no language-model judge, on the fraction of predictions whose Cmax and AUC land within two-fold of the clinical value. Even strong systems struggle to clear the target. That is not a weakness we are embarrassed by; it is precisely why a guessed number is worthless. Three things to take away. First, inputs rule — accuracy depends on good physicochemical and ADME inputs, so supply measured values whenever you have them rather than leaning on defaults. Second, these are estimates, not guarantees — the absolute numbers are projections, and the benchmark's difficulty proves it. And third, the real advantage: BioMate runs a validated, published differential-equation solver, with full provenance behind every number — not a language model emitting a plausible-looking value.

---

## Step 10 — Closing · the habit

So, the shape of a PBPK run in BioMate. You describe the scenario, BioMate runs the real ODE model on managed compute, and you read a projection you can defend. PBPK turns a molecule's properties and the body's physiology into a concentration–time curve you can reason about — including for children, pregnancy, and organ impairment, where no trial data yet exists. Remember the division of labour: NCA describes the data you already have; PBPK predicts the scenarios you don't. What BioMate adds is to run the real, validated solver, gate the physics, and keep a full reproducibility record behind every result — never to let a language model invent a pharmacokinetic number. A mechanistic projection for triage and dose reasoning, reviewed by a pharmacologist — not a clinical dose decision on its own.
