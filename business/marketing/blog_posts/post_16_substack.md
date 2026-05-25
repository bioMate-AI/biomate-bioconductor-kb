# Memory corruption + traceability + governance — what a long-running pharma agent actually needs

*Fifth in the ChatInvent series. The AstraZeneca Molecular AI team (Jiazhen He, Ola Engkvist, Samuel Genheden et al.) named **memory corruption** as the fifth engineering problem agentic AI hits in pharma R&D, in their *Drug Discovery Today* paper ["Democratising real-world drug discovery through agentic AI"](https://doi.org/10.1016/j.drudis.2026.104605) (doi: 10.1016/j.drudis.2026.104605), and pointed at the six capability pillars the Agent era requires: tool orchestration, evaluation, **traceability**, **governance**, **human-in-the-loop**, and **memory**. This post is about the last four — the ones that make an agent deployable in a regulated, multi-month drug program instead of a 10-turn demo.*

---

## What "memory corruption" actually means

A drug program runs for months. The agent that helps it should accumulate context over that time:

- Which workflows the team has run, on which inputs, with which results
- Which parameter choices the team standardized after a tox surprise
- Which findings the user accepted, and which they corrected
- Which predictions the team made, and which played out in the lab

A naive chat-style agent has none of this. Every session starts blank. The user re-types the standing constraints every morning. The corrections from last Tuesday are forgotten by Wednesday. The audit question "why did the agent recommend dose X six weeks ago?" has no answer.

The opposite extreme is worse. An agent that drags every prior turn into every new prompt poisons the new task with stale assumptions. This is **memory corruption** — past context interfering with present judgment instead of informing it.

The job is to keep the right memory at the right granularity, surface it at the right moments, and make every recall and every recommendation queryable after the fact.

---

## What we built

> 📊 **Figure 1 — Memory + prediction registry + HITL stack.** Source: `figures/post_16_memory_governance.drawio.xml`. Open in [diagrams.net](https://app.diagrams.net), export PNG at 1200×800.

Four layers, each addressing one of the four pillars.

### 1. Episode memory (the *what happened* layer)

When a workflow run completes, we distill it into an **episode**: a structured record of inputs, parameters, outputs, QC outcome, and any user corrections during the run. The raw chat log gets archived; the episode is what feeds the next session.

On the user's next session, the most-recent N episodes are injected into the context as a small block (typically <1K tokens), so the agent knows what's been tried without rereading thousands of lines of chat.

### 2. Correction memory (the *what the user fixed* layer)

When a user corrects the agent — "no, for our program we always use paired-end reads when ambiguous," "no, we cap MW at 480 in this series" — the correction is extracted, stored as a standing user/team rule, and injected into every future routing call until the user retracts it.

This is the layer that makes the agent stop making the same mistake twice.

### 3. Prediction registry (the *traceability* layer)

Every model output the agent emits — ADMET score, PBPK Cmax, docking pose rank, patient stratification percentile, IND narrative claim — is logged with version, inputs, output, confidence, and the citations that supported it. (Post 5 of this series went deep on why this matters; this is its operational home.)

The registry is queryable. Six weeks later, when the user (or a regulator, or a QA auditor) asks "why was that hit advanced?", the answer is a row, not a PowerPoint.

### 4. Governance + HITL surface

For decisions that touch a regulated record — parameter overrides that change a study report, narrative claims that go into §2.6.1, dose recommendations that feed a trial protocol — the agent **proposes** and the user **approves**. The approval is logged with timestamp, user ID, and a snapshot of the supporting evidence.

This is the surface that makes the agent deployable in GxP. The agent does the work; the human owns the call; the record is defensible.

---

## What the benchmarks say

| Benchmark                                                     | Result                                              |
|---------------------------------------------------------------|-----------------------------------------------------|
| **Memory benchmark** (20 scenarios across recall / correction / temporal / synthesis / adversarial) | **20/20 pass, 100% weighted**                       |
| Versus GPT-4o no-injection baseline                           | **+45% improvement**                                |
| Alignment with public benchmarks                              | LongMemEval + LoCoMo design                          |
| **Session 8 P1+P2 (episode + correction injection)**          | Live in production; 4/4 E2E passing                  |
| Endpoints                                                     | `GET /api/memory/user/episodes`, `GET /api/memory/user/corrections` |
| **Auto-loop benchmark** (cross-domain stability proxy)        | 96.4% convergence ≤ 3 iterations                     |

The headline: **20/20 memory scenarios pass at 100% weighted score, +45% over a GPT-4o baseline without memory injection.** The benchmark was deliberately designed against LongMemEval and LoCoMo so the result is comparable to the public memory literature, not a custom-flattering eval.

---

## Why the four pillars belong together

Each pillar in isolation is weak.

- **Memory without traceability** is the agent that "remembers" wrong things confidently.
- **Traceability without HITL** is an audit trail of decisions nobody ever signed off on.
- **Governance without memory** is signed-off decisions that the system promptly forgets and contradicts the next morning.
- **HITL without traceability** is a human approving things in a chat window that no one can reconstruct later.

The four work as a single system, or they don't work. This is the part of the ChatInvent paper that I think industry mostly hasn't internalized yet — the pillars are not a menu.

---

## What this means for users

If your team uses BioMate for two months on a program, the agent on day 60 doesn't behave like a fresh ChatGPT instance.

- It knows you've standardized on paired-end reads for ambiguous transcriptomics jobs (correction memory).
- It knows the three ADMET workflows you've run on this series and the hERG remediation that landed (episode memory).
- It can answer "why did we drop compound CMP-014?" with a registry row that says "predicted hERG IC50 0.8 µM by model v2.1 [Aronov 2008 threshold cited], measured at 0.5 µM in CRO study X — confirmed flag, dropped by user-approved decision on date Y" (prediction registry + HITL log).

That's a different agent than a chatbot. It's also a different agent than most "AI for drug discovery" demos.

---

## The honest limitations

- **Episode compaction is lossy.** A summary is not the chat. The prediction registry recovers the *facts*; the *conversational nuance* is gone. We think this is the right trade-off; some users disagree.
- **Correction memory can drift.** A correction the user made six months ago in a different program context may not apply to the current one. The agent surfaces standing corrections explicitly so the user can retract stale ones.
- **GxP-level audit trails require sign-off discipline.** If the user clicks "approve" on everything without reading, the trail exists but the science doesn't get the human check it deserves. We design the UX to make review easier than skipping; we can't make the human do the right thing.

---

## Closing the series

This is post 5 of 5 in the ChatInvent-mapped series. Across the five posts we covered the five engineering problems AstraZeneca named:

1. **Context explosion** — domain-gated rules, hybrid retrieval, lazy step fetch
2. **Tool hallucination** — registry-bounded selection, disambiguation gate, citation discipline, independent judge
3. **Schema mismatch** — rule-first / LLM-fallback / schema guardrail
4. **Workflow instability** — auto-loop QC remediation with HITL approval
5. **Memory corruption + traceability + governance** — episode + correction memory + prediction registry + audit trail

The thesis under all five: the value in agentic AI for pharma is not in the model. It's in the system stability layer around the model. That's where the productivity unlock lives, and that's where we're betting BioMate.

If you've read all five, I'd love to hear what we got wrong. Reply or DM — I read everything.

---

> 🧪 **Try the stability stack.** Open trial — bring a multi-week program and see the memory, registry, and governance layers compound across sessions: [**biomate.ai**](https://biomate.ai)

---

— Yaoyun Wang
Founder & CEO, BioMate AI
Houston, Texas
