# LinkedIn feed post — Post 10 (ANDV inhibitor track)

**Recommended hero image:** Split panel — pocket surface + workflow DAG (export 1200×627 PNG; optional draw.io: inhibitor four-step strip).

**Character count:** ~2,450 / 3,000 limit.

---

Most “AI drug discovery” demos fail quietly.

Step 4 runs. Step 4 uses the wrong compounds — because nothing enforced that step 2’s output became step 3’s input.

We stress-tested BioMate on a real **ANDV glycoprotein inhibitor** triage stack (PDB 9P3I) using **two agents**, not one chatbot:

🧠 **Agent A — Research Planner**
→ Classifies inhibitor intent
→ Picks the right subworkflow (pocket → pharmacophore → ADMET → Vina)
→ Extracts PDB paths, S3 libraries, thresholds
→ Hands off a param map. Does NOT submit jobs.

⚙️ **Agent B — Execution Coach**
→ Workflow card + prereq checklist
→ Run on AWS Batch, capture run_id
→ Terminal status + artifact paths for the *next* chat turn

Four Nextflow steps. One thread. Separation of concerns: replan without re-docking.

Our own audit caught the uncomfortable case: all steps **green**, but ADMET/docking consumed a **fixed SMILES list** instead of pharmacophore-filtered hits. We fixed the orchestrator and re-ran a **chained** manifest for publication figures.

Lesson for platform builders: **chain-of-custody beats checkmarks.**

UI E2E today: pocket + pharmacophore through chat → card → Run (INH-1…INH-4). CLI manifest covers full four-step chain.

Try the orchestration layer on your structures:

👉 biomate.ai

Full essay (two-agent sequence + audit honesty): [Substack link]

Next in series: Plan A vaccine track — epitopeprediction vs mhcquant routing.

#DrugDiscovery #MedicinalChemistry #ANDV #Nextflow #AgenticAI #AWS #StructuralBiology
