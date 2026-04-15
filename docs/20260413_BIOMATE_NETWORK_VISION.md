# BioMate Research Network — Vision, Status, Gaps, and Roadmap
# Business Team Document — 2026-04-13

---

## The Vision

BioMate's end state is not a hosted analysis tool. It is a **live research network** — an operating layer that connects research groups to each other, to their instruments, to their data, and to their collaborators, in the same way that GitHub connects software engineers or PubMed connects published science.

The defining characteristic of the network is that **value compounds with participation**. A lab that joins BioMate gains access to validated workflows, curated parameters, and AI-guided analysis. A network of labs additionally gains: shared workflow improvements, cross-lab benchmarks, structured upstream-to-downstream handoffs (sequencing core → analysis lab → CRO → clinical team), and a discovery layer that surfaces compatible collaborators. This is categorically different from being a better Galaxy or a smarter Seqera. Those are tools. BioMate's network is infrastructure.

### What the Network Looks Like at Maturity

```
                        ┌─────────────────────────────────┐
                        │       BioMate Network Layer      │
                        │  ┌──────────┐  ┌─────────────┐  │
                        │  │ Workflow  │  │  Discovery  │  │
                        │  │Marketplace│  │   Engine    │  │
                        │  └──────────┘  └─────────────┘  │
                        │  ┌──────────┐  ┌─────────────┐  │
                        │  │  Shared  │  │  Federated  │  │
                        │  │  Audit   │  │   Compute   │  │
                        │  └──────────┘  └─────────────┘  │
                        └──────────────┬──────────────────┘
           ┌─────────────┬─────────────┼─────────────┬──────────────┐
           ▼             ▼             ▼             ▼              ▼
    [University     [Pharma        [Core         [CRO /        [Hospital
     Research Lab]   R&D Team]      Facility]     Contract Lab]  Genomics]
           │             │             │             │              │
    Generates       Runs drug     Sequences      Provides       Receives
    WGS/RNA-seq     screens +     samples for    wet lab        clinical
    data            ADMET         20 PIs         execution      variant
                    analysis                                    reports
```

Each node contributes to the network and draws from it. Upstream labs (data generators) connect to downstream labs (analysis providers). Core facilities serve multiple PI labs. CROs receive structured data packages and return results. Hospitals receive clinical reports. All transactions are auditable, reproducible, and citable.

---

## Current Status — Stage 1 of 5

BioMate today is a high-quality **single-lab tool**. It has excellent AI-guided workflow execution, evidence-graded QC, and publishable audit trails. It does not yet have any of the connective tissue that makes a network.

### What Exists Today

| Capability | Status | Notes |
|-----------|--------|-------|
| AI workflow routing (NL → workflow) | ✅ Production | 94.6% accuracy, 60+ workflows |
| AWS Batch GPU execution | ✅ Production | CPU + GPU queues, ECR images |
| Evidence-graded QC (GOLD/SILVER/BRONZE) | ✅ Production | 32 QC profiles, protocol-aware |
| Full audit trail (parameter + QC provenance) | ✅ Production | Per-run, exportable |
| User authentication | ✅ Production | Email, password, organization (text), subscription tier, Galaxy API key |
| 5-tier memory hierarchy | ✅ Production | ltm_users / projects / sessions / episodes / procedures — full query + param + QC + outcome logging |
| Session memory (within conversation) | ✅ Production | `conversationMessages` table; `conversationState` JSONB flushed every turn |
| Execution parameter versioning | ✅ Production | `executionRuns.parameters` stores versioned JSON with changedFrom history |
| QC outcome logging | ✅ Production | `executionRuns.metrics.quality` inline with every run |
| Episode recording | ✅ Production | `projectEpisodes`: userQuery, workflowGenerated, parametersSet, whatWorked, whatFailed |
| CRO submission export workflow | ✅ Production | Structured package generation |
| MRC/EER file upload (cryo-EM) | ✅ Production | File type detection + param injection |
| Training data extraction pipeline | ❌ Not built | Data exists in DB; offline job to produce fine-tuning examples not yet written |
| Multi-user lab / team workspace | ❌ Not built | Organization is a text field only; no user grouping or shared projects |
| Project management | ❌ Not built | No shared projects across users |
| Data sharing between labs | ❌ Not built | No multi-party data access |
| Workflow marketplace | ❌ Not built | No publish/discover/fork |
| Instrument event listeners | ❌ Not built | Manual upload only |
| MCP server (external API access) | ❌ Not built | No programmatic access |
| HL7 FHIR output | ❌ Not built | No clinical system integration |
| Federated / private deployment | ❌ Not built | Shared cloud only |

---

## The Five Stages to Network

### Stage 1 — Single-Lab Tool (Current)

Each user operates independently. No shared identity, no shared data, no connections to other labs or to instruments. Value is entirely in the AI + execution layer.

**Current users**: Individual researchers, bioinformaticians, students running their own analyses.

---

### Stage 2 — Lab Identity and Project Collaboration

The lab becomes the atomic unit, not the individual user. Members of a lab share a workspace: they see each other's runs, annotate results, and contribute to shared projects. The PI has a dashboard view across all lab activity.

**What this unlocks**:
- PI oversight without being in the technical loop
- Students can build on each other's prior runs (reuse parameters, fork workflows)
- Personalized workflow ranking based on the lab's domain and history
- Customized greeting and starting configuration per user based on registration profile

**Key features to build**:
- Lab/organization entity with member roles (PI, postdoc, student, operator)
- Shared project workspace: runs grouped by project, annotatable, commentable
- Lab-level workflow preferences and parameter defaults
- Left sidebar: Projects / Common Workflows / Personal Notes (to-do item 11)
- Customized onboarding and greeting based on registration category and selected topics

**Who enters at this stage**: Core facility operators (serve many PI labs from one account), academic lab groups, biotech internal teams.

---

### Stage 3 — Bilateral Lab-to-Lab Connections

Two labs connect through BioMate: one provides data or samples, the other provides analysis or capacity. Both see the shared transaction — its inputs, workflow, QC, and outputs. Neither needs to manage a file transfer or write a report template.

**Concrete connections at this stage**:

| Upstream | Downstream | What BioMate handles |
|----------|-----------|---------------------|
| PI lab generates WGS data | Core facility runs analysis | Sample submission → analysis request → results delivery |
| Drug discovery lab runs screen | CRO provides follow-up assays | Structured compound package → CRO receives it live, not by email |
| Sequencing core completes run | Multiple PI labs receive results | Per-PI result delivery with individual QC reports |
| Hospital collects tumor biopsy | Clinical genomics lab runs WGS | Chain-of-custody tracking, HL7 FHIR report back to EHR |

The CRO submission workflow already exists as a one-way export. Making it bilateral (CRO sees the live job, confirms receipt, returns results through BioMate) is the Stage 3 step.

**Key features to build**:
- Lab-to-lab connection protocol with explicit data sharing consent
- Shared job view: both parties see the same run, QC, and outputs
- Structured result delivery (not email/file share — a live BioMate result record)
- Chain-of-custody tracking for sample provenance

---

### Stage 4 — Workflow Marketplace and Discovery

Labs publish workflows. Other labs discover, fork, and cite them. The network becomes a living repository of validated, community-maintained bioinformatics methods.

**What this looks like**:
- A lab publishes their validated ChIP-seq pipeline for plant genomes as "Zhang Lab ChIP-seq v2.1"
- Another lab finds it via semantic search ("find a ChIP-seq workflow validated on Arabidopsis")
- They fork it, adjust one parameter, run it, and publish their fork as a derived workflow
- The citation chain is automatic: the paper's methods section includes "adapted from Zhang Lab BioMate workflow #4291"

**Discovery engine**: "Find labs that have run WGS on Alzheimer's patient cohorts and have published results through BioMate" — surfaces potential collaborators by what they have actually done, not just their publication keywords.

**Key features to build**:
- Workflow versioning and attribution system
- Public/private/shared workflow visibility controls
- Semantic search over the workflow registry
- Auto-citation generation in methods sections
- Lab profile pages: domain focus, published workflows, active projects (opt-in)

**What makes this a moat**: The workflow registry is not replaceable. Every workflow published, forked, and cited on BioMate creates a citation graph that is uniquely valuable for discovery, benchmarking, and training data. No competitor can replicate it retroactively.

---

### Stage 5 — Federated Execution and Pre-Competitive Consortia

Data never leaves the institution. BioMate coordinates cross-institution analysis where Lab A provides data, Lab B provides the pipeline, and the result is jointly owned — without either party seeing the other's raw data.

**Use cases**:
- Rare disease consortium: 12 hospitals each contribute WGS data on 50 patients; BioMate runs federated variant analysis; each hospital sees only their patients' results plus consortium-level statistics
- Multi-site clinical trial: sequencing done at 5 sites; BioMate harmonizes QC thresholds across sites and produces a unified analysis report
- Pre-competitive pharma consortium: 3 companies share ADMET screening data on a shared target class without disclosing their proprietary compounds

**Technical model**: Federated compute — BioMate's orchestration runs in a neutral zone; each institution's data stays in their own S3 bucket or VPC; only aggregated results and statistics cross boundaries.

**What makes this achievable**: BioMate already runs on AWS Batch. Federated execution is architecturally the same model — each institution runs their own Batch jobs in their own AWS account, BioMate orchestrates the coordination. The data sharing protocol and consent layer are the missing pieces, not the compute infrastructure.

---

## Gaps — Ordered by Impact

### Gap 1: No Multi-User Lab / Team Workspace
**What exists**: Individual user identity is fully built — email, password, organization name (text field), Galaxy API key, subscription tier, invite code. Users authenticate and run workflows independently.
**What's missing**: Grouping multiple users under a shared lab or project. There is no PI role that sees all lab members' runs, no shared project workspace, no member invitation flow that creates a team, no role hierarchy (PI / postdoc / student / operator). The `organization` field is a freeform text string with no relational meaning — it does not link users together.
**Impact**: Every user is an island even if they work in the same physical lab. PI oversight, shared project history, and team-level workflow preferences are all impossible without this layer.
**What's needed**: Organization/lab entity that groups users; role model (PI / member / operator); shared project workspace where runs are visible to all members; member invitation flow.
**Dependencies**: None. This is the first layer to build toward the network.

### Gap 2: No MCP Server (No Programmatic Access)
**Impact**: Computational biologists, lab robot controllers, and external agents cannot call BioMate workflows programmatically. The instrument connection and lab robot segments are both blocked.
**What's needed**: MCP server exposing workflow catalog, parameter schemas, run submission, status polling, and output URLs as typed tool calls.
**Dependencies**: None. Independent of the network layer.

### Gap 3: No Instrument Event Listeners
**Impact**: Data from cryo-EM, sequencers, and mass spectrometers requires manual upload. The instrument connection segment generates the highest volume of runs per lab — this is the usage flywheel.
**What's needed**: EPU session completion watcher (cryo-EM), Illumina BaseSpace webhook handler, Oxford Nanopore MinKNOW API integration. Instrument metadata auto-populated as workflow parameters.
**Dependencies**: MCP server (Gap 2) is the right API surface for instrument-to-BioMate communication.

### Gap 4: No Cross-Session or Cross-User Memory
**Impact**: Every conversation starts cold. The AI does not know that this user always works on mouse RNA-seq, that their lab uses hg38, or that they ran this same workflow last month with slightly different parameters.
**What's needed**: LangGraph Memory Store (or equivalent) persisting domain, preferred workflows, parameter history, and project context across sessions. Cross-user memory within a lab workspace for shared context.
**Dependencies**: Lab identity (Gap 1) is required for cross-user memory.

### Gap 5: No HL7 FHIR Output
**Impact**: BioMate cannot deliver results to any hospital EHR system. The entire clinical segment is technically blocked — not by compliance, but by missing output format.
**What's needed**: VCF + annotation → HL7 FHIR R4 Genomic Report resource. SMART on FHIR API client to upload to Epic/Cerner.
**Dependencies**: None. Pure engineering. Independent of compliance certification.

### Gap 6: No Private / VPC Deployment
**Impact**: Any institution with data sovereignty requirements (hospitals, Chinese institutions, pharma) cannot use BioMate in its current cloud-only form. This blocks the HIS segment, the China segment, and enterprise pharma.
**What's needed**: Terraform/CloudFormation template for single-institution deployment in their own AWS account. BioMate's orchestration layer deployed in their VPC; data stays in their S3.
**Dependencies**: Architecture refactor to separate the orchestration layer (BioMate code) from the execution layer (customer's AWS Batch). The execution layer is already in the customer's account (AWS Batch job definitions in their region). The orchestration layer needs to be self-hostable.

### Gap 7: Training Pipeline Not Yet Built on Top of the Memory Hierarchy
**What exists**: BioMate has a comprehensive 5-tier memory hierarchy that already captures everything needed for LLM training:
- `conversationMessages` — verbatim user query text, every turn, every session
- `executionRuns.parameters` — versioned parameter JSON with `changedFrom` history per run
- `executionRuns.metrics.quality` — QC outcomes embedded in every execution record
- `projectEpisodes` — explicitly designed episodic memory recording `userQuery`, `workflowGenerated`, `parametersSet`, `outcomeSuccess`, `whatWorked`, `whatFailed`, `lessonsLearned`
- `auditLogs.reasoning` — AI decision reasoning on workflow generation
- `uxFeedback` — user acceptance/rejection of suggestions with scored dimensions
- `telemetryEvents` — LLM decision events per workflow routing action

**What's missing**: A pipeline that reads from these tables and generates structured training examples — (query, intent, selected workflow, parameters, outcome, user feedback) tuples in the format required for fine-tuning. The data is there; the extraction and formatting step is not.
**Impact**: The raw material for LLM fine-tuning is accumulating but not being harvested. Every week of delay on building the extraction pipeline is a week of training examples not being produced, even though the underlying data already exists.
**What's needed**: An offline batch job that joins `conversationMessages` + `projectEpisodes` + `executionRuns` + `uxFeedback` into fine-tuning examples. No new logging infrastructure required — the data is already captured.
**Dependencies**: None. Pure data engineering on existing tables.

### Gap 8: No Data Sharing Protocol Between Labs
**Impact**: Stage 3 bilateral connections are impossible without a formal consent and access control layer. Labs cannot share data through BioMate safely.
**What's needed**: Data sharing agreement model (which lab can see which runs), granular permission controls (share outputs only vs. share inputs + outputs), consent capture and audit log.
**Dependencies**: Lab identity (Gap 1) is required first.

---

## Roadmap

### Now (Next 2 Sprints)

| To-Do | Why Now |
|-------|---------|
| Lab identity + team model (Gap 1) | Foundation for everything else; also unblocks to-do items 2, 11 from the product list |
| Execution data logging (Gap 7) | Zero-risk; high long-term value; every day of delay is lost training data |
| MCP server stub — workflow catalog + run submission (Gap 2) | Unblocks computational biologist segment and instrument connections |
| Cross-session memory with LangGraph store (Gap 4) | Immediate user experience improvement; no network dependencies |

### 2–3 Months

| To-Do | Why This Phase |
|-------|---------------|
| HL7 FHIR R4 output (Gap 5) | Engineering-only; no compliance dependency; unlocks clinical entry |
| EPU cryo-EM event listener (Gap 3) | Highest data volume per instrument; cryo-EM workflows already production-ready |
| Private/VPC deployment option (Gap 6) | Unblocks China, hospital, and pharma segments without compliance certification |
| Audit trail + RBAC completeness | Prerequisite for both clinical use and eventual SOC 2 observation window |
| WeChat / Slack integration | China market; uncontested; messaging-native access |

### 3–6 Months

| To-Do | Why This Phase |
|-------|---------------|
| CRO submission bilateral connection (Stage 3 seed) | Bilateral view already technically feasible once lab identity exists |
| Illumina BaseSpace webhook handler (Gap 3) | Largest sequencer installed base |
| Lab-to-core-facility connection (Stage 3) | Second most common bilateral relationship after PI-to-CRO |
| Workflow fine-tuning: routing + QC interpretation | Reduces LLM non-determinism; uses logged data from Gap 7 |
| SOC 2 Type II observation window start | Parallel administrative track; 3-month clock starts once system capabilities are in place |

### 6–12 Months

| To-Do | Why This Phase |
|-------|---------------|
| Workflow marketplace v1 (Stage 4 entry) | Requires stable lab identity + versioning infrastructure |
| Discovery engine: find labs by workflow history | Compounding network value; requires critical mass of lab profiles |
| Federated execution prototype (Stage 5 entry) | Architecture proof-of-concept with 2–3 pilot institutions |
| ACMG variant classification integration | Unlocks production clinical genomics use cases |
| LLM fine-tuning: routing model v1 | Requires 6+ months of logged execution data |

---

## The Key Metric: Are We Building a Network or a Better Tool?

A tool's value scales linearly with features. A network's value scales with the square of participants (Metcalfe's Law). BioMate must track both:

**Tool metrics** (already tracked):
- Routing accuracy, QC pass rates, run success rates, E2E test coverage

**Network metrics** (not yet tracked — must start):
- Number of connected labs (distinct organizations, not users)
- Number of bilateral connections (lab-to-CRO, PI-to-core, etc.)
- Number of workflows published to the marketplace
- Number of workflow forks and citations
- Cross-lab run volume (runs initiated by one lab, consuming another lab's published workflow)
- Data shared between labs (TB transferred through the network)

When network metrics start growing faster than tool metrics, BioMate has crossed from product to platform.

---

*Related documents: `20260413_BIOMATE_STRATEGIC_POSITIONING.md` · `20260413_USER_SEGMENTATION_AND_COMPETITIVE_MOAT.md`*
