# BioMate context architecture and Alibaba UModel comparison

**Date:** 2026-10-03  
**Decision:** retain and strengthen BioMate's existing multi-layer context architecture. Do not integrate Alibaba UnifiedModel (UModel) now. Revisit it only for a proven cross-system semantic-graph need.

## 1. Why this decision exists

BioMate already has a context architecture designed for a scientific assistant operating on a current user request. Alibaba's [UModel](https://github.com/alibaba/UnifiedModel) is a related but different system: a semantic runtime that models enterprise entities and their relations as a workspace-scoped object graph, queryable through SPL, REST, and MCP.

The systems overlap in the broad word “context,” but they solve different problems. Treating UModel as a replacement would add a second persistence/query/runtime layer while weakening the clear ownership BioMate already has for permissions, input binding, workflow execution, and scientific provenance.

## 2. BioMate's current context model

For each chat turn, BioMate assembles bounded context for the active authenticated user and project. Its layers have different purpose and authority:

| Layer | Current purpose | Authority / safety rule |
|---|---|---|
| Request instructions | A temporary per-composer instruction that changes this request only. | Bounded and normalized server-side; it is not silently saved as a project edit. |
| Exact selected file/dataset references | Tell the assistant which concrete files are intended for this operation or comparison. | Resolve only server-authorized IDs; do not infer a “latest” file or substitute a similarly named file. |
| Project context | Project name, description, research goal, and standing project instructions. | The client project ID is only a candidate; server owner/member authorization is required before reading it. |
| Standing instructions | User-promoted concise directives from evidence/research work. | Stored as discrete `project_instruction` entries; capped and injected selectively rather than as an ever-growing prompt blob. |
| Session context | Current conversation and operation state. | The current conversation takes precedence over long-term preference. |
| Long-term memory | Past preferences, corrections, and episodes useful for personalization. | Supplemental context, not evidence that can override the current request or exact records. |
| Skills/domain/tool context | Domain guidance, active expert skills, tool/workflow constraints, and resolved research facts. | Tools and actual server records remain authoritative; prompt text does not grant tool or data access. |

The implementation injects long-term and project context as distinct prompt blocks, and the route builds project context only after authorization. The project-file flow likewise requires an exact authorized reference before preview or workflow staging. These are not generic RAG claims; they are product safety properties.

Relevant implementation anchors:

- `frontend/server/routes.ts`: authenticated project resolution; bounded standing/composer instructions; exact project-file reference resolution.
- `frontend/server/galaxy-assistant.ts`: distinct long-term-memory, project-context, dataset, skill, and domain prompt blocks.
- `frontend/client/src/components/citation-panel.tsx`: user action that promotes a concise answer-derived directive into a standing project instruction.

## 3. What UModel is

UModel is a vendor-neutral semantic runtime for enterprise AI. It defines model packs for entity types, datasets, links, storage and topology, stores instances and relations in a workspace object graph, and exposes queries through SPL, REST, CLI, SDK, and MCP. Its public repository includes a local service, UI, MCP server, example packs, and graph-store providers.

It is not a general “better prompt panel,” a conversation-memory product, an access-control system for BioMate, or a scientific workflow engine. Its public scope explicitly excludes the cloud-hosted control plane and multi-tenant authorization; BioMate cannot delegate its security model to it.

## 4. Precise comparison

| Question | BioMate multi-layer context | UModel semantic runtime | Decision |
|---|---|---|---|
| Primary job | Prepare trustworthy, task-relevant context for a user/assistant turn and operate scientific workflows safely. | Give an enterprise a typed, queryable object graph across systems/domains. | Complementary at most, not substitutes. |
| Unit of organization | User, session, project, explicit file/dataset reference, workflow/run. | Workspace, model pack, entity set/entity, relation/topology. | BioMate remains the application source of truth. |
| User instructions | Explicit, bounded request and standing-project directives visible in product workflows. | Can model instructions as entities, but does not provide BioMate's instruction UX/policy. | Keep BioMate instruction panel. |
| File comparison | Exact selected file IDs/versions can be cited for a concrete operation. | Could express file/artifact relations, but does not select user intent for a turn. | Use BioMate's exact-selection flow. |
| Scientific provenance | BioMate binds file/run/model context, user request and workflow lifecycle. | Can represent relationships and query them; cannot establish that a BioMate run was scientifically accepted. | BioMate governs run provenance and acceptance. |
| Access control | Server owner/member checks and project-scoped resource authorization. | Public core is not BioMate multi-tenant authorization. | Never make UModel the authorization boundary. |
| Team workspace | Project roles, links, shared files/runs; planned activity, invitation and deliberately shared-chat layers. | May model enterprise objects but does not replace team policy or activity governance. | Continue the BioMate workspace plan independently. |
| Cross-system relationship questions | Strong within BioMate records, less complete when LIMS/ELN/registry/data-lake relationships live elsewhere. | Designed for typed cross-domain relations and bounded graph traversal. | Potential future pilot, only after a concrete integration need. |
| Agent interface | BioMate decides what authorized, relevant context enters a task and which tools can execute. | Provides MCP/REST/SPL retrieval over a modeled graph. | If adopted, expose read-only graph retrieval behind BioMate policy. |

## 5. Architecture decision

### Keep as BioMate-owned

BioMate is authoritative for:

- User identity, project membership, share links, invitations, activity and notification policy.
- Exact file/version/dataset selection, storage authorization, staging and preview rules.
- Conversation visibility, request instructions, standing instructions, and long-term-memory policy.
- Workflow validation, explicit approval, run launch/cancellation, output linkage, scientific acceptance, and audit evidence.
- The visible user experience for citations, source attribution, failures, and recovery guidance.

No UModel query or MCP response can override these records or policies. A semantic result is contextual evidence, not permission and not a launch instruction.

### Possible future UModel role

If evidence supports it, UModel can be a read-only **semantic index** behind a BioMate adapter. Its job would be to answer a narrow class of relationship questions that span systems, for example:

```text
BioMate project
  └── candidate molecule
        ├── target / target family
        ├── assay and assay version
        ├── wet-lab result artifact
        ├── BioMate workflow run and pinned model version
        └── literature / database evidence
```

The assistant would first authorize the BioMate project and assets, then issue a bounded read-only query to the semantic index, then return cited BioMate records. It would not expose a generic graph browser to the model or permit model-supplied write queries.

## 6. Current plan: no integration

For the current roadmap, the correct investment is in BioMate's existing architecture:

1. Preserve exact selected-file and run binding across chat, preview, workflow launch, and reports.
2. Complete the team-workspace plan: immutable activity ledger, governed invitations/expiring links, explicit shared-conversation publication, then restrained notifications.
3. Make the context surface understandable: users should be able to see the active project, standing instructions, explicitly selected files, and the difference between request-only and project-wide direction.
4. Add evidence tests for context isolation: unauthorized project IDs, removed members, stale asset links, instruction bounds, competing file versions, and multi-file comparison requests.
5. Continue scientific validation so domain claims derive from demonstrated workflow/output/metric/provenance chains rather than context sophistication alone.

No work in this plan requires UModel or another graph platform.

## 7. Future evaluation gate

Open a UModel evaluation only when all of the following are true:

- A partner has at least two external systems (for example LIMS, ELN, compound registry, assay system, data lake) whose relationships cannot be answered reliably from BioMate records alone.
- There are 3–5 concrete user questions that currently require manual reconciliation, such as linking a compound to a specific assay version, result artifact, model version, and external evidence.
- The partner can provide a non-sensitive, representative data slice and entity-identity mapping for a pilot.
- The required relations, ownership, refresh cadence, deletion rules, and source-system authority are documented.
- BioMate access policy can filter every query/result before it reaches an assistant or user.
- The pilot has an explicit success metric, e.g. correct provenance traversal on a held-out set, median retrieval latency, access-control denial tests, and zero mismatch between graph references and source-of-truth records.

Absence of any condition means do not start integration merely because the technology is available.

## 8. Contained pilot design, if the gate is met

### Scope

- One partner, one synthetic or approved de-identified project slice.
- Read-only relationship retrieval only.
- Five initial entity types: `Project`, `DatasetVersion`, `WorkflowRun`, `ResultArtifact`, `Citation`.
- Optional later drug-development entities only after data ownership is clear: `Compound`, `Target`, `Assay`, `AssayVersion`, `ModelVersion`.
- No autonomous workflow launch, graph writes by an LLM, user permission decisions, or general enterprise search.

### Integration boundary

1. BioMate authenticates the user and resolves permitted project/resource IDs.
2. A BioMate server adapter constructs a narrow parameterized query from allowed IDs and a fixed query template.
3. UModel returns entity IDs and relations, not presigned data URLs, raw file bodies, credentials, prompts, or workflow logs.
4. BioMate rechecks each returned entity against its own authorization/source record.
5. BioMate renders an answer with source IDs, versions, timestamps, and links to its own project/run/file pages.

The model must not call a broad UModel query endpoint directly. The adapter owns allowlists, result-size limits, timeout, trace ID, and safe error mapping.

### Evaluation

| Test | Passing evidence |
|---|---|
| Relationship accuracy | Held-out questions return the correct source record/version and no invented edge. |
| Authorization | A non-member, removed member, and stale share-link user cannot enumerate or infer restricted nodes. |
| Provenance | Every graph answer contains a source-system ID/version and resolves back to a BioMate or partner-source record. |
| Freshness | Updates/deletions follow an agreed sync time and are detectable in the answer. |
| Reliability | Bounded timeout/failure returns a safe “relationship lookup unavailable” state; BioMate's core chat/workflow behavior continues. |
| Value | Users complete the predeclared cross-system questions faster and with fewer manual record checks than the BioMate-only baseline. |

### Stop conditions

Stop the pilot if it duplicates existing BioMate records without improving a user task; cannot maintain source identity/version correctness; cannot enforce authorization through the adapter; requires unrestricted LLM graph access; or creates material operational burden relative to the partner's demonstrated need.

## 9. Reassessment checkpoint

Review this decision after the team-workspace activity/invitation/shared-conversation phases have production evidence, or when a partner presents an approved multi-system provenance use case. The review must compare the pilot's measured value with simpler alternatives: adding explicit BioMate relations, improving existing PostgreSQL queries, or importing a narrow external read model.

Until then, “multi-layer context” refers to BioMate's own user-visible, authorization-aware task context—not an external semantic graph dependency.
