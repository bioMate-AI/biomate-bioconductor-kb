# Life science has been split for forty years. Agents are how we finally stitch it back together.

*The first post of Agentic Biology — a newsletter about what happens when AI orchestration meets the messy, validated, regulated reality of drug development and modern biology.*

---

Pick any modern biotech program and trace it end-to-end. A target hypothesis comes out of a single-cell RNA-seq experiment in a discovery lab. The validation cascade goes through a structural biology group running cryo-EM and AlphaFold. Hit identification runs through a chemistry team using docking and generative models. ADMET screening sits with a DMPK group on a different floor. Pharmacokinetic modeling lives in a clinical pharmacology team that may not even be in the same building. Phase 1 dose escalation runs through a biostatistics consultancy. Regulatory writing happens at a CRO. Manufacturing scale-up is a fourth vendor.

Eight specialties. Eight software stacks. Eight file formats. Eight queues of people waiting for the one person who knows how to run each pipeline.

This isn't because the science is fragmented. Biology is one system. It's because the *tools* are fragmented — forty years of specialized software, each excellent at one thing, almost none of it designed to compose with the rest. The integration layer is human, and the humans are expensive, slow, and disappearing into industry the moment they get good at it.

The estimates vary, but the consensus is consistent: **the majority of life science professionals lack the coding and pipeline skills to operate the tools their work depends on.** Forty years of biotech software development has produced an astonishing substrate — Galaxy's 8,000+ analyses, Bioconductor's 2,000+ packages, the full nf-core catalog (sarek, rnaseq, atacseq, chipseq, differentialabundance, proteomicslfq, raredisease, scrnaseq, scdownstream, and a hundred more), AutoDock, CryoSPARC, RELION, Nextflow, the entire Python and R scientific stacks — and the people who need them most can't use them without a translator.

This is the splintering problem. And I think we're finally in a position to solve it.

## Why the old answers didn't work

The standard response to "scientists can't use the tools" has been some variant of "build a better GUI." KNIME. Galaxy's web interface. Geneious. CLC. Schrödinger Maestro. Vendor software with point-and-click pipelines. SaaS dashboards that wrap a single workflow in a friendlier wrapper.

These helped. They didn't solve it.

The bottleneck was never the GUI. The bottleneck is **knowing what to do** — which workflow to pick from the hundreds that could theoretically apply, which parameters to set given your sample type and study design, how to interpret a quality control failure when the actual problem is upstream, how to debug a pipeline that completes successfully but produces biologically nonsensical output, and how to bridge from one specialist domain to the next when a target hypothesis from transcriptomics has to land in a docking campaign without losing context.

A GUI doesn't help with any of that. It only helps with the easiest part of the problem — clicking buttons — while leaving the hard part, the *intelligence layer*, on the scientist. And the intelligence layer is exactly where the cross-domain knowledge lives that lets a drug program actually move forward.

The dirty secret of life science software is that most validated workflow knowledge lives in three places: PhD theses, lab Slack channels, and the heads of senior bioinformaticians and computational chemists who learned it through five years of trial and error. None of these are queryable. None scale. None survive their owner leaving for industry.

## Why now is different

Three things have changed in the last 18 months that make this solvable in a way it wasn't before.

**First, the orchestration layer is real.** Tool-using LLM agents have crossed a quality threshold where they can reliably plan multi-step workflows, call external tools, interpret intermediate results, and recover from errors. Not perfectly, not yet, but well enough to handle the routine analytical work that consumes most of a computational biologist's day. Standards like the Model Context Protocol give agents a uniform way to discover and invoke specialized tools without bespoke integration for each one.

**Second, the knowledge is finally extractable.** Peer-reviewed literature, nf-core pipeline documentation, FDA guidance documents, ICH guidelines, vendor manuals, community troubleshooting threads — all of this is structured enough to embed, retrieve, and ground recommendations in citations. Done right, an agent recommending a Phase 1 starting dose for a small molecule can point to the FDA MABEL guidance, the relevant allometric scaling literature, and the actual NOAEL from the user's tox study. Done wrong, you get hallucinations. The difference is evidence grounding, and that's an engineering problem we now know how to solve. (More on this in a later post.)

**Third, the tools are commodities.** nf-core is open-source. Galaxy is open-source. Bioconductor is open-source. CryoSPARC is free for academics. AutoDock, Vina, GROMACS, OpenMM, ESMFold, ColabFold — open. The validated computational substrate of modern biology is largely free. What's missing isn't another tool. It's the intelligence layer that makes the existing tools accessible across the specialty boundaries that today require a different human translator at each step.

## What I mean by "agentic biology"

The phrase "AI for biology" usually means something narrow: protein structure prediction, generative chemistry, target identification. AlphaFold. Boltz. Chai. RFDiffusion. ESM. These are extraordinary models and they're already changing drug discovery.

That's not what this newsletter is about.

This newsletter is about the *other* AI for biology — the orchestration layer that connects a researcher's intent to the right workflow, parameter set, and interpretation, *across* the specialty boundaries that currently require human handoffs. The layer that turns "I have these 24 FASTQ files from a stability study and a candidate gene panel" into a validated nf-core/rnaseq + differentialabundance run with appropriate parameters, executed on appropriate compute, with results contextualized against the relevant pathways. The layer that turns "the cryo-EM 2D classes look blobby" into a diagnosis ("CTF estimation is drifting; here are the three most common causes given your defocus range") and a remediation that re-runs the affected step. The layer that turns "we have a hit series with these ADMET liabilities" into a Phase 1 starting-dose recommendation, a PBPK simulation, and a draft IND §2.6.1 narrative grounded in the actual study data.

Agentic biology is the proposition that the next major productivity unlock in life sciences won't come from a better individual tool — it'll come from intelligence that makes the existing tools usable *together*, across the specialty walls that currently fragment a drug program into eight disconnected handoffs.

## What this newsletter will cover

Practically, here's what to expect:

**Technical deep-dives** on how to actually build this. Multi-agent architectures for scientific workflows. RAG systems grounded in PubMed, UniProt, ChEMBL, and FDA guidance corpora. Domain-specific LLM strategies — including where we *did* train our own model (regulatory writing) and where we didn't (everything else). Evaluation frameworks for scientific accuracy, including the prediction-vs-reality tracking that I'll argue is the actual productivity ceiling in modern R&D.

**Industry analysis** on where this is heading. Which segments of drug development get re-shaped first — my bets, with reasoning. Where regulation moves faster or slower than the technology. What pharma R&D leaders are actually buying versus what the conference circuit says they're buying.

**Tool reviews** of the underlying substrate — nf-core, Galaxy, Bioconductor, CryoSPARC, AutoDock, GROMACS, ESMFold, the open clinical pharmacology stack — with an eye toward what's actually usable in production and what just exists in papers.

**Honest takes** on what's working and what isn't in our work at BioMate AI, the company I'm building to make this real. I'll share architecture decisions, things we got wrong, benchmarks against the alternatives, and the occasional contrarian view. Not press releases.

## What BioMate does — and doesn't

Since this is the first post, it's worth being concrete about scope. There's a lot of "AI for biology" out there, and "what we do" is usually clearer than "what we are."

**What BioMate does:**

- **Routes intent to validated workflows.** Type or speak a goal — "RNA-seq with batch correction on these samples," "ADMET screen this hit series," "cryo-EM SPA reconstruction on this dataset," "PBPK simulation for first-in-human dosing" — and the agent selects, parameterizes, and runs the right pipeline from the 2,000+ workflows we index. The user does not need to know that the right pipeline is `nf-core/rnaseq` followed by `nf-core/differentialabundance`, or that the right cryo-EM stack is `cryosparc_standard_spa` with these specific particle-import settings.
- **Executes on real compute.** Workflows run on AWS Batch with GPU or CPU queues as appropriate, not in a sandbox toy environment. Outputs are real files in S3, traceable to the exact pipeline version and parameters used.
- **Closes the QC loop automatically.** When a step's QC fails a configured gate — hERG flag in ADMET, low resolution in cryo-EM, AUC extrapolation > 20% in NCA-PK, RIN drop in RNA-seq — the agent diagnoses, proposes a remediation (parameter change, additional sample, alternative method), and offers to re-run. The user sees a was→now diff and approves or rejects.
- **Writes regulatory-grade narratives.** For drug programs that reach IND, the agent assembles §2.6.1.1–.5 in FDA-acceptable prose from the underlying study data, grounded in the actual numbers, with citations to the source records. The pharma writer reviews and edits; the agent does not invent.
- **Tracks predictions and outcomes.** Every model output the agent produces is logged with version, inputs, and confidence. When the experimental or clinical result lands, it's linked back. Over time, this becomes the queryable audit trail that pharma R&D has needed for thirty years and not had.

**What BioMate does not do:**

- **We don't build foundation models for structure prediction or generative chemistry.** AlphaFold, ESMFold, RFDiffusion, the diffusion-based generative chemistry models — we *use* these, often as steps inside a larger orchestrated workflow. We don't compete with them. That's a different game with different economics.
- **We don't replace the scientist's judgment.** The agent proposes, runs, summarizes, and flags. Decisions — does this hit move forward, does this trial design make sense, does this patient stratification hold up — sit with the human. The tagline is "agentic biology," not "autonomous biology," and that distinction is intentional.
- **We don't bypass regulation.** Outputs that feed into regulatory submissions are produced with full provenance. The agent doesn't ship to a sponsor without the audit trail that any GxP environment requires.
- **We're not yet a wet-lab automation layer.** Robotics integration is on the roadmap; today the integration is at the data and analysis layer, not the bench.

That's the actual scope, today. The newsletter will be specific about where we extend and where we don't.

## Who this is for

If you're a computational biologist, bioinformatician, computational chemist, or DMPK scientist building or using these workflows: you'll find the technical content useful and, I hope, occasionally surprising.

If you're a drug development leader, biotech executive, or pharma R&D director trying to understand where AI is actually going to change your operations versus where it's marketing: I'll try to write the analysis I wish I could read.

If you're a CRO, CDMO, or contract analytical lab figuring out how AI changes your service mix and your margin: the orchestration layer story matters more to your business model than the model layer does.

If you're an investor or builder in this space: I'll share what we're seeing on the ground in Texas Medical Center labs, China biopharma, and the academic-industry boundary in real time.

If you're a scientist who's tired of waiting in line for the bioinformatician — or the structural biologist, or the DMPK consultant, or the CRO regulatory writer — this is being built for you.

## A note on what this isn't

This isn't a vendor blog. BioMate AI is the company I'm building, and I'll write about it honestly when it's relevant — but if every post reads like a product pitch, I've failed and you should unsubscribe.

This isn't AI hype. I think the agentic capabilities are real and important; I also think most "AI for drug discovery" pitches are overstated, evidence-light, and confuse the hard problems with the easy ones. I'll try to be specific about which is which.

This isn't a substitute for primary research. The peer-reviewed literature is where the science is settled. This newsletter is where I think out loud about the engineering, the market, and the systems that translate that science into productive work.

---

Subscribe if any of this resonates. New posts every other Tuesday — occasionally weekly when something's worth saying sooner.

In two weeks: *Why drug development needs prediction-AND-simulation, not just better models — and the Merrimack lesson that nobody learned.*

— Yaoyun Wang
Founder & CEO, BioMate AI
Houston, Texas
