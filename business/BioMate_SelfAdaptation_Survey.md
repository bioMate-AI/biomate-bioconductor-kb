# Self-Adaptation in AI Scientific Assistants
## Memory, Context Management, and Continuous Learning — A Survey for BioMate

*March 2026 · Internal research brief*

---

## Why This Matters for BioMate

A bioinformatics or drug discovery platform used over weeks or months faces a problem that a single-session tool does not: the analyst has preferences, history, and project context that should inform every new session, but conventional platforms treat each session as stateless. A scientist running the tenth screening batch in a campaign should not need to re-explain the project's compound class, the target family, the QC thresholds the team has settled on, or which analogues failed last time. An adaptive platform accumulates that context and applies it proactively.

This survey covers the current state of research on how AI systems achieve this — the mechanisms, the evidence that they work, the failure modes, and the open questions most relevant to BioMate's design.

---

## 1. The Problem: Stateless AI in Long-Horizon Scientific Work

Most deployed AI assistants are stateless within and across sessions. Each query is answered from model weights alone; nothing the analyst said or did in prior sessions influences the response. For short tasks, this is fine. For extended scientific campaigns — a drug screening program spanning months, a rare disease patient cohort analysed iteratively, a neurogenomics study with dozens of samples — statelessness is a fundamental mismatch with how the work actually runs.

The consequences are concrete:
- Analysts re-enter project context manually at the start of every session
- QC override decisions made in week 2 are invisible to the system in week 6
- Scaffold directions that proved dead ends must be rediscovered
- Preferences learned informally by experienced team members are not transmitted to the platform

The research question is whether a structured, persistent memory layer can close this gap — and, if so, what architecture is needed and what claims of improvement are actually supported by evidence.

---

## 2. Memory Architectures in LLM Agents

The most comprehensive recent treatment of this topic is Jiang et al., "Adaptation of Agentic AI: A Survey of Post-Training, Memory, and Skills" (arXiv:2512.16301, December 2025, revised March 2026). The survey organizes adaptation into four paradigms: two that improve the agent itself (supervised fine-tuning, RL with verifiable rewards) and two that improve the tools the agent uses (pre-trained external modules, agent-supervised memory and skill libraries). For a scientific platform like BioMate, the most directly applicable are the latter two — specifically, agent-supervised memory systems that are updated and retrieved based on what the agent has done, rather than by retraining model weights.

### 2.1 Parametric vs. Contextual Memory

Memory in LLM agents falls into two broad categories:

**Parametric memory** — encoded in model weights through training or fine-tuning. Updating it requires gradient steps. This is powerful for encoding broad domain knowledge but expensive to update per-user or per-project, and it generalises across users rather than personalising to one.

**Contextual memory** — explicit external storage retrieved at inference time. Includes the active context window (short-term), session summaries (medium-term), and persistent databases (long-term). Updating it requires only a write operation. This is the mechanism that enables per-project adaptation without model retraining.

For BioMate, contextual memory is the right design choice: projects differ substantially, teams have different conventions, and per-project adaptation should not interfere with general platform behaviour for other users.

### 2.2 MemGPT and Hierarchical Memory Management

MemGPT (Packer et al., UC Berkeley, 2023; deployed as the Letta platform) introduced the key architectural idea: applying operating-system-style virtual memory management to LLM context windows. A fixed-size working context (the LLM's active window) is managed by the agent itself, which decides what to load from a large external store and what to evict — analogous to how an OS manages RAM and disk.

For scientific use, this means: a long compound screening campaign can be stored in full fidelity in an external database, while each session loads only the most relevant prior results into the active context. The agent decides relevance based on the current query.

The primary limitation: MemGPT's retrieval is content-based (what is semantically similar to the current query). It does not natively handle temporal reasoning — knowing that the team's preferences changed between week 2 and week 6, or that a compound that failed in batch 3 was retested and passed in batch 7.

### 2.3 Zep and Temporal Knowledge Graphs

Zep (Gusev et al., arXiv:2501.13956, January 2025) addresses the temporal limitation with a knowledge graph architecture. Rather than storing memory as a flat retrieval index, Zep's Graphiti engine maintains entities (compounds, targets, analysts, projects), relationships (compound X was tested against target Y in session Z, outcome W), and time-stamped edges (the team's hERG threshold changed from X to Y at time T).

Zep outperforms MemGPT on the Deep Memory Retrieval benchmark (94.8% vs. 93.4%). More importantly for scientific use, it correctly handles the question "what has changed since the last session?" — which a flat semantic index cannot answer. For drug screening, where campaign logic evolves over weeks, temporal memory is not optional.

**Implication for BioMate:** A Zep-style temporal knowledge graph per project is a better fit than a simple vector store for campaign memory. Compound outcomes, override decisions, and preference patterns should be stored as timestamped graph edges, not flat embeddings.

### 2.4 Memoria and Session-Level Summarization

Memoria (arXiv:2512.12686, December 2025) combines dynamic session-level summarization with a weighted knowledge graph for user modeling. Within each session, a lightweight summarizer identifies user traits, preferences, and behavioral patterns and writes them to the graph. Across sessions, those traits are retrieved and applied to personalise responses.

On long-term personalization benchmarks, Memoria achieves 55% accuracy in implicit preference inference while using 16× fewer input tokens than naive full-history retrieval. The efficiency gain matters in production: full conversation replay across dozens of sessions is computationally prohibitive; structured summarization makes long-term memory tractable.

**Implication for BioMate:** Session-end summarization should be a standard pipeline step — not optional. Each BioMate session should produce a structured summary: which analyses ran, which gates fired, which compounds were advanced or rejected, any override decisions with the recorded justification, and any stated analyst preferences. This summary feeds the campaign knowledge graph.

---

## 3. Continuous and Preference Learning

Memory tells the system what happened. Preference learning tells it what the user actually wants — which is not always what they said explicitly.

### 3.1 RLHF and Its Limitations for Continual Adaptation

Reinforcement Learning from Human Feedback (RLHF) is the dominant paradigm for aligning LLMs with human preferences. It works well for encoding broad population preferences at training time. It struggles with two things relevant to BioMate:

1. **Per-user adaptation** — RLHF produces a single model that reflects aggregate preferences. It cannot produce a model that reflects one specific lab's conventions without fine-tuning on that lab's data, which is expensive and raises data governance concerns.

2. **Continual learning** — Standard RLHF is offline. When preferences change (a team switches from one QC threshold convention to another mid-campaign), the model trained on earlier preferences cannot adapt without catastrophic forgetting of what it previously learned.

### 3.2 COPR: Continual Optimal Policy Regularization

COPR (ACL Findings 2025) addresses the catastrophic forgetting problem in continual preference learning. When learning new preferences, COPR converts historical optimal policies into optimization constraints — so the model can shift toward new preferences without abandoning what it previously learned. It also maintains generation diversity through a moderate reward function based on pairwise ranking loss, preventing mode collapse onto a single response style.

For BioMate, the direct application is limited — BioMate does not fine-tune its underlying model on per-user data. But the principle is relevant for the preference pattern detection layer: when the system detects that a team's apparent preferences have shifted (they started rejecting a compound class that was previously acceptable), it should update the active preference model without discarding the prior pattern entirely, since the shift may be temporary or context-dependent.

### 3.3 Pref-GUIDE: Real-Time Preference Signals

Pref-GUIDE (arXiv:2508.07126, 2025) enables continual adaptation from real-time scalar feedback — a thumbs up/down or a 1–5 rating — by converting scalar signals into preference pair data. Rather than requiring explicit pairwise comparisons, which are burdensome to collect in a scientific workflow, Pref-GUIDE infers preferences from comparisons within short behavioral windows.

For BioMate's drug screening context: when an analyst accepts BioMate's top-ranked compound without comment but overrides its third-ranked compound, that implicit signal is a preference pair. Pref-GUIDE's approach would formalise this into a preference update without requiring the analyst to fill out a survey after each session.

**Implication for BioMate:** Override decisions, acceptance without comment, and explicit QC threshold adjustments are all implicit preference signals. A lightweight preference inference layer should convert these into structured updates to the user's preference model — accumulated per-project, visible to the analyst, and correctable if wrong.

---

## 4. Multi-Agent Memory in Drug Discovery

### 4.1 OrchestRA: Closed-Loop Compound Optimization

OrchestRA (arXiv:2512.21623, December 2025) is the most directly relevant system to BioMate's drug screening use case. It integrates biology, chemistry, and pharmacology through specialised agents with a shared memory layer. The Biologist Agent identifies targets; the Chemist Agent designs molecules; the Pharmacologist Agent evaluates via PBPK simulation. Critically, the evaluation output — toxicity flags, PK profiles — directly triggers structural reoptimization, creating a closed-loop Design-Make-Test-Analyze (DMTA) cycle.

The shared memory in OrchestRA stores which molecular features correlated with which outcomes across DMTA iterations, so the chemist agent's next-round suggestions are informed by what the pharmacologist found in the previous round. This is the multi-agent version of what BioMate's campaign memory achieves in a single-agent setting.

**What BioMate does differently:** OrchestRA is a fully autonomous multi-agent system — it does not have a human analyst in the loop making final decisions. BioMate is explicitly human-in-the-loop: the analyst makes prioritisation decisions, BioMate provides ranked suggestions and QC-gated outputs, and the analyst's decisions feed back into memory. This distinction matters for scientific validity — the analyst retains scientific accountability, which most drug discovery organisations require.

### 4.2 PharmaSwarm: Shared Memory and Self-Improvement

PharmaSwarm (arXiv:2504.17967) implements a competitive multi-agent framework with a shared memory bank that captures validated insights across agents and fine-tunes underlying models over time. A central Evaluator LLM ranks proposals by biological plausibility, novelty, and safety continuously.

The relevant insight is the shared memory pattern: when one agent discovers that a particular scaffold modification reliably improves DILI scores, that insight is written to shared memory and is immediately available to all other agents in the next iteration. For BioMate — a single-agent system — the equivalent is campaign memory that surfaces validated insights from prior sessions without the analyst re-entering them: "compounds in this scaffold class with logP > 4.5 consistently failed the DILI gate in batches 2 and 3."

---

## 5. What the Evidence Actually Supports (and What It Does Not)

This section is the most important for BioMate's study design and claims.

### What is well-supported:

- **Long-term memory retrieval improves response relevance** in general-purpose conversational AI benchmarks (MemGPT, Zep, Memoria results). The improvement is consistent and measurable.
- **Temporal knowledge graphs outperform flat semantic retrieval** for queries that require understanding change over time (Zep vs. MemGPT on DMR benchmark).
- **Implicit preference signals can be converted into useful preference updates** without requiring explicit rating systems, if the behavioral signal (override, acceptance, threshold adjustment) is captured reliably (Pref-GUIDE).
- **Closed-loop DMTA with shared memory improves compound quality** in fully autonomous settings (OrchestRA, PharmaSwarm) — but these results are from simulation benchmarks, not real medicinal chemistry campaigns.

### What is not yet well-supported:

- **Whether memory-augmented AI improves outcomes in real human-in-the-loop scientific campaigns.** The OrchestRA and PharmaSwarm results are from controlled benchmarks with simulated feedback. No published study has measured the effect of campaign memory on compound prioritisation quality in a real drug discovery team over multiple weeks.
- **Whether proactive filtering from detected preferences helps or annoys analysts.** If the system incorrectly infers a preference and acts on it, it may be harder to correct than a system that asks explicitly. The right balance between proactive and reactive adaptation is an open research question.
- **Whether session summarization captures the right information.** What an analyst said and did in a session may not capture what they actually learned or what changed their thinking. The gap between behavioral signal and intent is not addressed in current memory systems.

**Implication for BioMate's study proposal:** Arm D should be framed as measuring whether campaign memory *helps*, not as demonstrating a known benefit. The null result — memory accumulates but suggestion concordance does not improve over time — is a valid and publishable finding. The honest framing is: "we built this mechanism, here is how we measured it, here is what we found."

---

## 6. Open Questions Directly Relevant to BioMate

1. **What should be stored?** Not all session content is equally useful to remember. Compound outcomes and override decisions are high-signal. Analyst phrasing and exploratory questions may be low-signal noise that degrades retrieval quality. The right memory schema for a drug screening campaign has not been empirically determined.

2. **How should preference drift be detected?** A team that consistently rejected low-solubility compounds in weeks 1–3 but started accepting them in week 5 (perhaps because the indication changed) requires the system to detect the shift, attribute it, and update the preference model without erasing the prior pattern. Current approaches (COPR, Pref-GUIDE) address this for single-user dialogue; multi-member teams in a shared campaign add further complexity.

3. **How should conflicting preferences across team members be handled?** In a campaign with multiple analysts, one may prefer aggressive hERG filtering and another may override it routinely. Whose preference should the system apply when both are active? PersonaMem-v2 shows promise for per-user modeling; the multi-user synthesis problem is open.

4. **How should memory accuracy failures be surfaced to analysts?** If BioMate references a prior compound outcome incorrectly — citing a failed compound as passed — the consequence in a drug campaign is a bad prioritisation decision. Memory audit trails and explicit provenance for every retrieved fact are necessary but not sufficient; the analyst also needs a low-friction way to correct the system.

5. **What is the right evaluation benchmark?** The Deep Memory Retrieval benchmark (DMR) used to compare MemGPT and Zep is a conversational retrieval task, not a scientific campaign task. A drug screening-specific benchmark — where the ground truth is whether the system's campaign-context-informed suggestions improve on context-free suggestions, measured against analyst decisions — does not yet exist. Arm D of the BioMate drug screening study would be among the first attempts to construct one.

---

## 7. Summary: What BioMate Should Build and How to Evaluate It

| Mechanism | Research basis | What to build | How to measure |
|---|---|---|---|
| Per-session structured memory | Memoria (2025), MemGPT (2023) | Session-end summarizer: compound outcomes, gate results, override decisions, analyst notes | Memory accuracy audit; retrieval relevance per session |
| Temporal campaign knowledge graph | Zep / Graphiti (2025) | Per-project graph: compounds, outcomes, timestamps, preference shifts | Suggestion concordance over time (Arm D); temporal query accuracy |
| Implicit preference inference | Pref-GUIDE (2025) | Override and acceptance pattern detector; per-analyst preference model | Proactive filter accuracy; analyst-rated usefulness |
| Proactive context application | OrchestRA / PharmaSwarm (2025) | Context-informed session opening; campaign-aware compound ranking | Concordance of context-informed vs. context-free suggestions |
| Memory audit trail | General best practice | Full provenance for every retrieved fact | Analyst correction rate; false memory rate |

**What is not yet justified by evidence:** Full autonomous DMTA loops, model retraining on per-campaign data, or any claim that memory improves compound quality in real campaigns. These are empirical questions the drug screening study is designed to answer.

---

*Internal research brief — BioMate AI · March 2026*  
*Key references: Jiang et al. arXiv:2512.16301 (2025); Zep arXiv:2501.13956 (2025); Memoria arXiv:2512.12686 (2025); OrchestRA arXiv:2512.21623 (2025); PharmaSwarm arXiv:2504.17967 (2025); COPR ACL 2025; Pref-GUIDE arXiv:2508.07126 (2025)*
