# Projects, instructions & collaboration

> One-line promise: after this page you know how to give BioMate lasting context for a body of work
> (standing instructions, plans, notes) and how to share that work with a team at the right level of
> access. For PIs, bioinformaticians, and anyone running a multi-step project.

<!-- Every claim here is code-verified (tier C); see coverage-ledger.md "## I.4 Projects, instructions & collaboration". -->

## What this is for

A **project** is the container for a line of research: its files, its chat sessions, its runs, and the
context BioMate should keep in mind every time you talk to it. Where a single chat is a conversation,
a project is the **standing memory** around many conversations. You open one when work spans more than
one sitting — a manuscript's worth of analyses, a screening campaign, a collaboration with a colleague.

A project gives you three things a bare chat doesn't:

1. **Standing instructions** the assistant reads on *every* chat scoped to the project (organism,
   experimental design, house conventions), so you stop re-typing context.
2. **Plans, hypotheses and notes** that live as first-class objects next to the data, not buried in
   old chat scrollback.
3. **Collaboration** — invite teammates as viewers or editors, with the platform enforcing who can
   read, run, and manage.

Everything is user-owned and access-scoped: you can only see or touch a project you own or were
invited to, and BioMate returns a plain **404 "not found"** for anyone else's project rather than a
403 — it never even confirms the project exists (`project-routes.ts:11-13, :278`).

## Use cases

| Goal (researcher's words) | How BioMate does it | Where | Lane |
|---|---|---|---|
| "Stop making me repeat that this is mouse liver, paired-end, dUTP stranded" | Save it once as **Standing instructions**; it's injected into every project chat | Project detail → Standing instructions card | Instant |
| "Record the hypothesis this run is testing so the report can cite it" | Create a **Plan / hypothesis** object a run can reference | Project detail → Plan / hypothesis card | Instant |
| "Keep a private to-do that the AI should NOT act on" | Add a **Note** (human-only, never read by the assistant) | Project detail → Notes card | Instant |
| "Let my postdoc run analyses but not delete the project" | Invite them as **Editor**; keep member/lifecycle control as **Owner** | Project detail → Members & roles | Instant |
| "Send a colleague a link to view results" | Generate a **share link** (viewer or editor) | Project detail → Invite link | Instant |
| "Hand the project off before I leave the lab" | **Transfer ownership** to a current member | API `PATCH /api/projects/:id/owner` (see *What's not covered*) | Instant |

None of these are Cloud runs — they configure context and access. The Cloud runs happen *inside* the
project once it's set up (see I.6).

## How a project scopes a chat

A chat becomes project-scoped when an **active project id** is set. The active project is held in the
`ActiveProjectProvider` context and persisted to `localStorage` under `biomate-active-project-id`
(`active-project-context.tsx:39, :56-64`), so a page refresh keeps your selection. Opening a chat from
a project's detail page sets it for you (`project-detail.tsx:464`); you can also pick a project from
the app chrome.

When you send a message, the composer threads that id into the request:
`projectId: activeProjectId || undefined` (`chat-with-artifacts.tsx:1183, :601`). The server resolves
it (`_resolvedProjectId`, `routes.ts:6033`) and, if a project is active, **injects the project's
context into the model prompt** before your message — its name, description, **research goal (the
Standing instructions)**, and background instructions (`routes.ts:6061-6081`). A null active project is
the normal, valid default — standalone chats stay project-less (`active-project-context.tsx` header
comment).

> **Tip — you don't have to open the project page to work in it.** Once a project is the active
> project, every new chat inherits its standing instructions automatically. Set it once; forget it.

## Standing instructions vs Notes — the trust boundary

This is the most important distinction on the project page, and BioMate keeps the two **physically
separate** so there's no ambiguity about what the AI can act on.

**Standing instructions** are the assistant-read directives. In the UI they're the *Standing
instructions* card — "Read by the assistant on every chat in this project"
(`project-detail.tsx:907-921`). They persist to the project's **`researchGoal`** field via
`PATCH /api/projects/:id` (`project-detail.tsx:366-380`; `project-routes.ts:316`), and that field is
exactly what the server injects as "Research goal" into the prompt (`routes.ts:6074`;
`memory-integration.ts:444`). Use them for durable context: organism and genome build, study design,
comparison of interest, naming conventions, "always use GRCh38", "we prefer edgeR to DESeq2."

**Notes** are human-only free text — "Private to you — **not read by the assistant**"
(`project-detail.tsx:956-961`). They persist as `project_knowledge` rows with
`knowledgeType='user_notes'`, saved and listed through the dedicated
`GET`/`POST /api/projects/:id/notes-list` endpoints (`project-routes.ts:931-983`). Critically, the
chat-stream prompt injection reads only `research_goal` and the promoted-instruction rows
(`routes.ts:6066-6099`) — it **never** reads `user_notes`. A note is a sticky-note for you, not an
instruction for the AI.

**Promote to instruction ↑** bridges the two on purpose. Clicking it on a note (or on new note text)
appends that line to the Standing instructions and re-saves `researchGoal`
(`handlePromoteNote`, `project-detail.tsx:443-461, :981-990, :1008-1017`). This is the *only* way a
note's content reaches the assistant — an explicit, deliberate action, never automatic.

> **Pitfall — a Note will never change how BioMate behaves.** If you jot "use the new reference" as a
> Note and expect the assistant to pick it up, it won't. Put behavioral guidance in **Standing
> instructions**, or promote the note.

## Plans & hypotheses

A **plan** captures the goal (and optional hypothesis) motivating a piece of work, as a first-class
object — not chat metadata that scrolls away. It exists so a run can *cite* the hypothesis it tested
(the plan is stored so an execution can reference it via `basedOnPlanId`,
`project-routes.ts:165-166, :867-869`).

On the project page, the **Plan / hypothesis** card lists existing plans newest-first and offers a
create form: a required **Goal** and an optional **Hypothesis** (`project-detail.tsx:1025-1075`). The
backing endpoints are `GET /api/projects/:id/plans` (list), `POST /api/projects/:id/plans` (create),
and `GET /api/projects/:id/plans/:planId` (fetch one) (`project-routes.ts:870-929`). A plan can also
carry referenced dataset and evidence ids, so it ties a hypothesis to the specific data behind it
(`project-routes.ts:172-179, :878-879`).

Creating a plan requires **owner or editor** rights; the server returns 403 to a viewer who tries
(`project-routes.ts:874`). Listing and reading plans are open to any member and 404 to non-members
(`project-routes.ts:900, :917`).

## Collaboration & roles

BioMate has exactly **three roles**, ranked owner ⊃ editor ⊃ viewer (`project-detail.tsx:73-77`):

| Role | Can do | Cannot do |
|---|---|---|
| **Owner** | Everything: edit content, run, manage members & roles, change status, archive/delete, transfer ownership, create/revoke share links | — |
| **Editor** | Edit project content (instructions, tags, files), upload/delete files, create plans, add notes | Manage members, change status, archive/delete, share links (owner-only) |
| **Viewer** | Read the project, download files, read plans | Any write (edits, uploads, plan creation) |

The server enforces this at the row level. Content edits (`PATCH /api/projects/:id`) require owner or
editor; **lifecycle** (status → active/archived/completed) stays owner-only even for editors
(`project-routes.ts:301-309`). Member management, share links, and ownership transfer are all
strictly owner-only (`project-routes.ts:673, :724, :745, :771, :801, :826, :858`). Uploads and file
deletes require owner-or-editor (`project-routes.ts:551, :588`). Across the board, a caller with no
access gets **404, not 403**, so project existence is never leaked (`project-routes.ts:278, :304`).

The capability card on the project page (`RolesCard`, fed by your real server-assigned role) shows the
full capability list with owner-only rows **disabled, not hidden** — a viewer or editor sees what
each locked action requires rather than a blank space (`project-detail.tsx:86-101, :1237-1247`).

**Two ways to add people:**

- **Invite by email** — `POST /api/projects/:id/members` with a role of viewer or editor. The invitee
  must already be a BioMate user (the server 404s "No user found with that email" otherwise)
  (`project-routes.ts:663-689`; UI `project-detail.tsx:294-311`).
- **Share link** — `POST /api/projects/:id/share-link` mints a URL-safe token; anyone who opens
  `/join/<token>` and accepts is added at the link's role (`project-routes.ts:817-848, :1011-1042`).
  The link's role can be changed in place, and it can be revoked to kill it
  (`project-routes.ts:833-834, :852-865`). The public preview endpoint `GET /api/join/:token` needs no
  auth so a recipient can see what they're joining before signing in (`project-routes.ts:987-1007`).

Owners can **change a member's role** (`PATCH /api/projects/:id/members/:memberId`) or **remove** them
(`DELETE .../:memberId`); any non-owner member can **leave** via `DELETE .../members/me`, but the
owner cannot leave — they must transfer or delete first (`project-routes.ts:694-756`). The member list
(with role dropdowns for the owner) and the invite/share-link controls all live in the **Members &
roles** panel on the project page (`project-detail.tsx:1078-1248`).

**Ownership transfer** demotes the old owner to editor and promotes a current member to owner
(`PATCH /api/projects/:id/owner`; `project-routes.ts:762-791`).

> **License / Pitfall — collaboration is a Team-plan feature.** When tier enforcement is on, inviting
> members, changing roles, sharing links, and transferring ownership return **402 TEAM_REQUIRED** for
> plans below Team (`blockedByCollaborationTier`, `project-routes.ts:151-163, :670, :721, :768, :823`).
> Reading and single-user project work are unaffected. See I.13 for the tier model.

## Project lifecycle

- **Create** — `POST /api/projects` (name required). Free tier is capped at a fixed number of active
  projects when enforcement is on (402 `PROJECT_LIMIT_REACHED`) (`project-routes.ts:211-257`).
- **Rename / edit / set status** — `PATCH /api/projects/:id` (`project-routes.ts:293-328`; UI
  dropdown, `project-detail.tsx:648-671`).
- **Archive** — soft delete (`status='archived'`); reversible by changing status
  (`project-routes.ts:330-347`).
- **Delete** — hard delete; **CASCADEs** to the project's episodes, procedures and knowledge, while
  linked chat sessions survive with their `project_id` set to NULL (`project-routes.ts:14-15, :349-367`).

> **Tip — deleting a project doesn't destroy your chats.** The sessions detach and live on as
> standalone chats. Archiving is the safe, reversible option when you just want it out of the way.

## What's not covered

- **Ownership-transfer UI.** The transfer is fully implemented server-side
  (`PATCH /api/projects/:id/owner`, `project-routes.ts:762-791`) but **project-detail.tsx exposes no
  button for it** — there is no transfer control in the Members & roles panel. Today it's reachable
  only via the API. This is a real UI gap, not a design choice → Appendix E.
- **A "member" role.** The product has only owner / editor / viewer; there is no separate "member"
  role despite the panel being labelled "Members." Any doc or request referring to a distinct member
  role is describing something that doesn't exist.
- **Cross-project standing instructions.** Standing instructions are per-project (`researchGoal`);
  there is no global/account-wide instruction that applies to every project. → Appendix E.
- **Share-link expiry UI.** The token schema supports `expires_at` (`project-routes.ts:56, :999`) and
  the join endpoints honor it (410 when expired), but the create UI always mints a non-expiring link
  — there's no way to set an expiry from the page. → Appendix E.
- **Two instruction channels.** Besides the project `researchGoal`, the chat-stream also injects
  separate `project_instruction` knowledge rows promoted from *Search & evidence* answers
  ("Make instruction", `routes.ts:6083-6105`). Those are documented in I.3; the project page's
  "Promote to instruction ↑" writes to `researchGoal`, a different store — don't conflate the two.

---
_Verification: coverage-ledger.md "## I.4 Projects, instructions & collaboration" — all tier C
(source-read: project-detail.tsx, project-routes.ts, routes.ts, active-project-context.tsx,
chat-with-artifacts.tsx, memory-integration.ts); no Batch runs fired._
