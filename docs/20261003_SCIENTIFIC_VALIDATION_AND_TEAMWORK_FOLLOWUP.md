# Scientific validation and team-workspace follow-up

**Date:** 2026-10-03  
**Purpose:** turn BioMate capability and collaboration claims into evidence-backed release work. This document does not authorize cloud compute or claim that a planned validation has passed.

## 1. Scientific validation: release standard

A workflow is not scientifically validated merely because it routes, starts a container, or emits a file. A promoted workflow needs all six records below:

1. **Intent and routing:** a natural-language request selects the intended workflow and rejects incompatible inputs.
2. **Exact input binding:** the selected input IDs/versions are recorded; no filename/latest-file substitution is possible.
3. **Execution evidence:** a real representative input completes through the same launch path available to users.
4. **Output evidence:** expected result artifacts exist, are readable, and have the declared schema.
5. **Scientific acceptance:** a predeclared, domain-appropriate comparison to a reference/annotation/control passes. A process exit code is never the metric.
6. **Reproducibility record:** workflow/container/model version, parameters, input identifiers, QC outcome, and known limitations are attached to the run.

### Current evidence and required next validations

| Area | Current evidence | Truthful status | Next acceptance evidence |
|---|---|---|---|
| Drug discovery / peptide closed loop | Active code and research work exist; their own test and assay-validation evidence must remain tied to the exact model/data revision. | Per-workflow, not a blanket drug-design claim. | Holdout/assay-linked metric, provenance, and a failure case for each promoted model. |
| Transcriptomics | Established workflow surface and earlier validation work. | Requires per-workflow evidence review; no global “omics validated” inference. | Representative counts/FASTQ run with known DE/QC expectation and output-schema check. |
| Proteomics, metabolomics, epigenomics, single-cell, spatial | `docs/20260923_DOMAIN_VALIDATION_PLAN.md` documents missing or blocked Batch evidence. `docs/20260923_DOMAIN_VALIDATION_RESULTS.md` records real metabolomics failures rather than a false pass. | Not fully validated end to end. | Resolve the named blocker first, stage a licensed public input, run one cheap representative case, and score the predeclared scientific metric. |
| Pathology / WSI | Small-image heuristics and IMC-adjacent prototypes exist. | Not a WSI pathology capability. | Follow the narrow WSI pathway in `docs/20261003_PATHOLOGY_WSI_CAPABILITY_AUDIT.md`. |

### Execution order

1. Close known failures before launching more compute. In particular, the metabolomics record identifies a concrete API-drift failure; spatial has a documented missing-container dependency; historical ChIP-seq launches did not reach peak calling.
2. Validate one representative workflow per scientific modality, starting with the lowest-risk input already available locally or in the approved test store.
3. Publish each outcome as **passed**, **failed with cause**, or **blocked**. Do not convert a failure into “partial success” without a separate acceptance result.
4. Only after a modality has one full evidence chain should it appear as a demonstrated capability in external materials.

No cloud run should be dispatched by this plan without explicit approval for that run and its input data. This is separate from product development and avoids spending on known-broken paths.

## 2. Team workspace: verified current capability

BioMate already supports meaningful **project-level collaboration**:

- Server-enforced owner/editor/viewer roles, with non-members denied access; the project routes use owner/member checks rather than cosmetic client gating.
- Owner-controlled member management, role changes, transfer of ownership, and revocable share links.
- Shared project files and runs for project members, including project-file exact-reference binding in chat.
- Role-aware project UI, a join-by-link screen, and Team-tier gates which are feature-flagged rather than currently enforced.
- Local verification on 2026-10-03: 52 focused project-role, tier, project-file, chat-context, and UI tests passed.

This is strong project sharing. It is not yet an organization workspace.

## 3. Team workspace: precise gaps

| Gap | Evidence | Consequence | Correct next scope |
|---|---|---|---|
| Shared conversations | Project-session listing is scoped to `chat_sessions.user_id`; members see their own chats, not a shared transcript. | A colleague can see shared files/runs but cannot follow reasoning or decisions in the original chat. | Add an explicit shared-conversation object/visibility policy. Do not silently expose private chats by changing a query. |
| Pending invitations | `POST /members` finds an existing user by email and immediately inserts membership. | “Email invite” is an imprecise label; there is no accept/decline/pending state, and no invitation for an unregistered email. | Introduce invitation records, expiry, delivery, accept/decline, and audit events. |
| Organization/group access | Membership is project-by-project. | Repeating member setup across many projects is inefficient; no organization administrator or group policy exists. | Add an organization/team entity only after shared-project use is stable. |
| Activity and notifications | No project activity feed or collaborator notification surface was found. | No visible accountability trail for joins, edits, launches, or results. | Create immutable project events first; notifications can subscribe to those events later. |
| Share-link governance | One active token per project is supported; expiry exists in schema but normal creation does not expose a configurable expiry. | Links are less governable than enterprise collaboration requires. | Add owner-selectable expiration and optional one-time/member-limited links, with audit events. |
| Live integration evidence | E2E suites exist for team/share/authz flows, but local static tests are not a substitute for a current deployed API run. | A code-only pass cannot establish dev-environment migration/configuration correctness. | Run the non-production E2E authorization suite on dev, inspect results, and record its exact revision. |

## 4. Safe next implementation sequence

1. Run the existing dev team E2E authorization/share/member tests against test identities; do not use customer projects or data.
2. Fix only failures reproduced by that run. Preserve current project-level sharing while doing so.
3. Design a shared-chat policy before implementation: visibility, authorship, editing/deletion, citations, project transfer, and whether historical private chats stay private.
4. Add immutable project activity events (membership, file upload/delete, run launch/terminal state, plan creation) before building notification UI.
5. Decide whether organization work is actually needed for the first partner cohort; do not add a complex org hierarchy merely because it is common SaaS functionality.

## 5. Claims permitted today

> BioMate supports secure project collaboration: owners can share a project with editors or viewers, control access, share project files and runs, and retain project-level provenance.

Do **not** yet claim organization workspaces, shared real-time scientific conversations, pending email invitations, team activity feeds, or collaborative notifications.
