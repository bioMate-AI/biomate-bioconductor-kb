# LinkedIn feed post — Post 11 (Plan A vaccine / epitope)

**Recommended hero image:** Samplesheet → epitopeprediction DAG → MHCnuggets TSV strip (1200×627 PNG).

**Character count:** ~2,550 / 3,000 limit.

---

“Run nf-core for MHC epitopes” is not one workflow.

**mhcquant** = LC-MS immunopeptidomics.
**epitopeprediction** = computational class I binding on FASTA + samplesheet.

Route wrong → green checkmark, wrong science.

We built BioMate **Plan A** for ANDV vaccine informatics with **two agents**:

🧠 **Agent A — Research Planner**
→ Intent: Plan A / class I epitope binding
→ Match **nf-core/epitopeprediction** (Galaxy id 12700)
→ Extract S3 samplesheet, tools=mhcnuggets, genome_reference, peptide lengths
→ Respect “NOT mhcquant” in **search**, not only in chat prompts

⚙️ **Agent B — Execution Coach**
→ Workflow card + prereq checklist
→ Run on **AWS Batch** (docker profile + awsbatch executor)
→ Terminal status, MultiQC + MHCnuggets paths, downloads

What we validated in silico:
✅ Batch run succeeded (frozen mirror ~810 peptide–allele rows)
✅ UI E2E PA-1…PA-5: routing, card, execute, completion UX
✅ generate_workflow API returns epitopeprediction in seconds when LLM keys resolve

What we do NOT claim:
❌ In vivo immunogenicity
❌ Vaccine efficacy or correlates of protection

Boring details that matter:
• Samplesheet rows need absolute s3:// FASTA paths
• No generic nf-core “aws” profile—use docker + Batch
• Poll with run_id if HTTP blips mid-job—don’t double-submit

Pair this with our inhibitor-track post: same deposited structure, two discovery forks—small molecule vs immunogen.

Try the orchestration layer:

👉 biomate.ai/try

Full essay (two-agent flow + routing fix): [Substack link]

#VaccineDesign #Immunoinformatics #nfcore #ANDV #Bioinformatics #AgenticAI #AWS
