# Team workspace implementation plan

**Date:** 2026-10-03  
**Status:** planning baseline — not a claim that the listed features are shipped.  
**Companion evidence:** `docs/20261003_SCIENTIFIC_VALIDATION_AND_TEAMWORK_FOLLOWUP.md`.

## 1. Outcome and boundary

The first team-workspace release should let a small scientific team safely work in a shared **project**: share its inputs and runs, understand who changed what, invite a collaborator deliberately, and, when chosen by the author, share a conversation that contains the reasoning behind an analysis. It must preserve the existing owner/editor/viewer model and never turn a private chat into a shared one by accident.

This is deliberately not an organization/department platform yet. There will be no organization hierarchy, group/SCIM provisioning, broad workspace search, or always-on real-time co-editing in this release. Those are separate product decisions once partner usage demonstrates the need.

## 2. Verified starting point

Already present in the dev product and verified on 2026-10-03:

- Owner, editor, and viewer access control is enforced by the server for projects, members, shared files, and runs.
- Owners can add an already-registered account by email, change a member's role, remove a member, transfer ownership, and create/revoke a project share link.
- Project files can be cited into chat through an exact server-authorized file reference; a client-supplied project ID alone cannot grant context access.
- The deployed dev authorization, member-management, and sharing suites passed **46/46** cases. The authorization suite deletes its temporary project after completion.

Important current limitations:

- The existing “invite by email” endpoint immediately adds an account that already exists. It is not a pending email invitation and cannot invite an unregistered person.
- Project session listing is user-scoped. A project member cannot see another member's private chat merely because both belong to the project.
- No immutable project activity trail or user-notification mechanism exists.
- A share-token expiry field exists, but normal link creation does not let the owner choose an expiry.

## 3. Product decisions required before implementation

These decisions are intentionally explicit so implementation does not make policy by accident.

| Decision | Recommended first-release policy | Why |
|---|---|---|
| Conversation visibility | Private by default. An author or project owner explicitly publishes a conversation to the project. | Sharing a project does not imply consent to share exploratory reasoning or unrelated data. |
| Shared-chat mutability | Shared transcript is append-only after publication; author may add a correction or unpublish if no run/report depends on it. | Keeps scientific provenance intelligible and prevents silent history rewriting. |
| Cited data after access changes | A shared chat shows only references to project files/runs that the viewer can still access; revoked material is shown as “access removed,” not rehydrated from chat text. | Prevents a transcript from bypassing later revocation. |
| Editor abilities | Editors may create project files/runs and publish their own conversations; they cannot change members, links, ownership, or another person's visibility. | Matches least privilege and the existing owner-controlled sharing model. |
| Viewer abilities | View project assets and published conversations, add no data/run/membership changes. | Clear read-only scientific review role. |
| Invite delivery | Build pending invitations first. Send email only through an approved production mail provider; until then, owner can copy a signed invite URL. | Avoids pretending an email was delivered when no mail system exists. |
| Share links | Default 7-day expiration, role selected by owner, revocable at any time; one active link initially. | Limits accidental long-lived access while retaining a simple mental model. |
| Activity retention | Append-only event records retained with the project; no raw file content, secrets, prompt text, or model logs in event payloads. | Provides accountability without creating a second sensitive-data store. |

If product leadership wants a materially different policy, revise this table before coding. In particular, do not change the sessions query to project-wide visibility without the explicit-publication design below.

## 4. Delivery plan

### Phase 0 — protect the verified baseline (complete, keep running)

**Scope**

- Retain the current project RBAC, direct registered-user addition, share-link revocation, file/run authorization, and exact project-file citation safeguards.
- Run the existing dev suites against disposable test identities after every relevant server/schema release.

**Required evidence**

- `project-authz.e2e.ts`, `project-team.e2e.ts`, and `project-sharing.e2e.ts` pass on dev.
- Existing server/unit tests and TypeScript check pass.
- Test cleanup leaves no temporary project after the authorization suite.

**Exit condition**

Existing collaboration behavior is unchanged or intentionally migrated with equivalent authorization tests.

### Phase 1 — project activity ledger

**Goal:** give project participants a reliable, human-readable provenance trail before notifications or shared chat introduce more collaboration state.

**Data model**

Create a `project_activity_events` table with immutable rows:

| Field | Notes |
|---|---|
| `id` | Server-generated UUID. |
| `project_id` | Foreign key; indexed with `created_at DESC`. |
| `actor_user_id` | Nullable only for system/automation events; never taken from client input. |
| `event_type` | Closed server-side enum, e.g. `member_added`, `role_changed`, `member_removed`, `share_link_created`, `share_link_revoked`, `file_added`, `file_removed`, `run_requested`, `run_started`, `run_completed`, `run_failed`, `conversation_published`. |
| `subject_type`, `subject_id` | Stable reference to the affected membership/file/run/conversation, not a duplicated mutable object. |
| `summary` | Server-generated concise display text; no raw logs or input contents. |
| `metadata` | Allowlisted JSON only: role change, file version ID, workflow/run ID, status code. Exclude signed URLs, credentials, prompts, model output, or file text. |
| `created_at` | Server time; clients cannot override it. |

**Implementation tasks**

1. Add an idempotent migration and indexes; decide deletion/retention behavior for deleted projects before deploying.
2. Implement one server-side `recordProjectActivity()` helper. Route handlers and run-state transitions call it only after their primary transaction succeeds.
3. Backfill nothing initially. The feed begins at release; do not fabricate historical precision.
4. Add a paginated `GET /api/projects/:id/activity` endpoint, owner/member readable, with opaque cursor and a fixed maximum page size.
5. Add a project Activity panel with event type, actor, subject summary, and timestamp. It must not expose private chat content or raw workflow logs.
6. Log activity for membership, links, project-file lifecycle, run terminal state, and future conversation publication. Do not log mere page views or every chat token.

**Authorization and failure rules**

- A non-member receives the same no-disclosure response used for other project resources.
- A failed activity insert must not silently convert a successful access/membership mutation into an unknown state. Use an outbox/transactional approach if the current database path cannot atomically persist both.
- Event text is server-rendered from known entities; clients can never submit arbitrary event summaries.

**Acceptance tests**

- Owner/member can paginate the project feed; outsider cannot enumerate it.
- Adding/removing a member, changing a role, creating/revoking a link, adding/removing a file, and terminal run status produce one correctly attributed event each.
- Repeated/retried server operation does not duplicate the event.
- Event metadata contains no signed URL, credential-shaped value, file body, prompt, or literal worker log.
- Dev E2E verifies a complete sequence with two test users.

**Exit condition**

An authorized collaborator can identify the actor, action, target, and time for important project changes without reading application logs.

### Phase 2 — governed invitations and link expiry

**Goal:** replace the misleading direct-add “email invite” label with a real pending invitation lifecycle, while retaining a simple direct-add path only if it is explicitly named as such.

**Data model**

Create `project_invitations` with `id`, `project_id`, normalized `email`, proposed `role`, `token_hash` (never plaintext token), `invited_by`, `status` (`pending`, `accepted`, `declined`, `revoked`, `expired`), `expires_at`, `accepted_by`, and timestamps. Enforce at most one pending invite per normalized email/project.

**Implementation tasks**

1. Rename the present UI/API behavior to “Add registered member” unless Phase 2 is live.
2. Add create/list/revoke invitation endpoints; owner-only for management, recipient-only for acceptance/decline.
3. On acceptance, validate token status/expiry and account email match in one transaction; insert membership with the invited role; consume invitation; record activity.
4. For an unknown email, create a pending invite but do not imply a mail was sent. When delivery is enabled, record delivery provider message ID separately and show “sent” only after provider acceptance.
5. Add owner-controlled share-link TTL creation/update. Existing links migrate to an explicit “no expiry” or a documented default only after product approval; do not silently invalidate existing links.
6. Keep one active share link per project for this release. Rotation revokes the prior token and writes an activity event.

**Acceptance tests**

- An unregistered email can have a pending invitation without membership access.
- A registered account with another email cannot accept it.
- Expired/revoked/previously-consumed tokens cannot join; a token race creates only one membership.
- Owner can see status without seeing a plaintext token; non-owner cannot inspect or revoke invitations.
- Share link is denied after expiry/revocation and retains the selected role before expiry.
- Dev E2E covers pending, accept, decline, expiry, revoke, link rotation, and existing direct registered-member addition/migration behavior.

**Exit condition**

The UI's wording, visible state, and server authorization accurately distinguish member addition, invitation pending state, and share-link access.

### Phase 3 — explicit shared conversations

**Goal:** let a project team review a selected scientific conversation and its evidence without exposing every chat attached to that project.

**Data model and policy**

Add a `project_conversation_publications` record rather than altering `chat_sessions` visibility globally. It references one session and project, includes `published_by`, `published_at`, `visibility` (`project_members` only in v1), `state` (`published`, `unpublished`), and a revision/provenance marker.

Use a distinct share/read route for published sessions. The existing personal session list remains user-scoped. A session can be published only when it belongs to the project and the publisher is its author or the project owner. Publishing must snapshot or version the visible message set so later private drafts are not automatically added to a published scientific record.

**Implementation tasks**

1. Write an API contract for publication, read, append-correction, and unpublish; obtain review before coding.
2. Resolve session ownership/project attachment and references exclusively server-side.
3. Create a published transcript view with author labels, creation/published time, cited asset cards, and a visible “shared with this project” marker.
4. Apply current per-asset authorization when rendering cited file/run links. If access later changes, render the neutral “access removed” placeholder—never source content embedded in the transcript.
5. Do not allow in-place edits/deletes of published messages. Corrections are a new attributed entry linked to the original message.
6. Unpublishing removes project visibility prospectively, records activity, and leaves the underlying private session intact. For runs/reports already linked to publication, require owner confirmation and preserve a provenance note.
7. Do not add simultaneous multi-user editing, presence indicators, or automatic AI summarization in this phase.

**Acceptance tests**

- Creating a project does not make any private conversation visible to another member.
- Author and owner can publish an eligible session; editor cannot publish someone else's session; viewer cannot publish.
- A project member can read a published transcript but cannot mutate its historical content.
- An outsider and a removed member cannot retrieve it by guessed ID or old URL.
- File/run citation access honors current permissions after publication and after removal/revocation.
- Unpublish immediately removes visibility; correction has a distinct author/time record.
- Dev E2E includes two members, one owner, one viewer, removal, and asset-revocation cases.

**Exit condition**

The team can use a deliberately shared conversation as scientific context while private exploration remains private and all access decisions are server-enforced.

### Phase 4 — notifications from activity, not a parallel audit system

**Goal:** surface only actionable collaboration changes after the activity ledger has proven reliable.

**Implementation tasks**

1. Define subscriptions by event type and project role. Start with in-product inbox/badges; email is optional and requires the approved delivery provider.
2. Create notification rows from activity events with a unique `(event_id, recipient_id, channel)` constraint for idempotency.
3. Provide read/unread and user-level opt-out controls. Never notify a user about an asset they no longer may access.
4. Add digest/rate limiting; do not send one message for every run progress update.

**Acceptance tests**

- One event produces at most one notification per authorized recipient/channel.
- Removed users stop receiving future notifications and cannot open old deep links.
- Notification summaries do not leak sensitive metadata or raw logs.

**Exit condition**

Notifications are derived from the authoritative activity ledger, are deduplicated, and obey current authorization.

### Phase 5 — evaluate organization scope, do not pre-build it

**Decision gate**

Only start this phase after at least one partner cohort needs repeated cross-project membership management and Phase 1–3 have stable usage/evidence. Collect evidence: number of active multi-project collaborators, owner membership-management burden, invitation failure rate, and requested administrative controls.

If justified, design organization, groups, project ownership, audit retention, billing, and offboarding as one coherent authorization model. Do not bolt groups onto project membership without a migration and revocation plan.

## 5. Cross-cutting engineering checklist

For every phase:

- Add a schema migration with reversible/forward-safe deployment notes and indexes for access paths.
- Centralize authorization in server helpers; UI visibility is never the access control.
- Validate and normalize IDs/emails at API boundaries; use opaque, sufficiently random hashed tokens for externally held invitation/link secrets.
- Avoid raw provider/model/worker logs in user UI, events, notifications, or API error messages. Return an actionable safe status and retain technical detail in protected observability systems.
- Produce unit tests for policy branches, integration tests for transaction/race behavior, and dev E2E for real authenticated flows.
- Test role downgrade, member removal, ownership transfer, token revocation/expiry, and stale browser URLs in every affected feature.
- Add accessibility checks for role/status text, keyboard operations, and an understandable empty/error state.
- Record exact deployed revision, test target, fixture identity type, and outcome in the release evidence. Never call a local static pass a deployed validation.

## 6. Release gates and ownership

| Gate | Required reviewer/evidence | Blocks release if absent |
|---|---|---|
| Policy review | Product + scientific lead approve the Phase 3 visibility, correction, and unpublish rules. | Shared conversations. |
| Security review | Threat model covers guessed IDs, removed members, token theft/replay, stale links, and event/notification data leakage. | Any new external token or visibility endpoint. |
| Data migration review | Migration, rollback/forward plan, index impact, and retention decision reviewed. | Schema deployment. |
| Dev verification | Focused server tests, TypeScript check, and named dev E2E suite pass against disposable identities. | Promotion beyond dev. |
| UX review | Wording accurately separates private, published, pending, expired, revoked, and access-removed states. | User-facing rollout. |
| Scientific provenance review | Published chat/run/file linkage is traceable and cannot silently change historical evidence. | Shared scientific transcript release. |

## 7. Priority order

1. Preserve and continuously verify existing project collaboration.
2. Build the activity ledger.
3. Build governed invitations and expiring links.
4. Approve the shared-chat policy, then implement explicit publication.
5. Add restrained notifications.
6. Evaluate—not assume—organization/groups.

This order minimizes risk: it first creates an auditable source of truth, then introduces external access, then introduces shared scientific reasoning. It does not delay existing project collaboration and it avoids turning generic collaboration complexity into a prerequisite for users' current work.
