# Talking to BioMate — the composer

> One-line promise: after this page you can drive BioMate from the message box —
> attach your data, point at existing files, apply standing instructions and expert packs,
> see (and override) whether your message will run Instant or Cloud, and send with confidence.
> For everyone (PI, bioinformatician, drug-discovery/regulatory, core admin).

<!--
Code-verified (tier C) from chat-input.tsx and its imports (galaxy-dataset-browser.tsx,
skills-selector.tsx, lane-preview.tsx) + the wiring in chat-interface.tsx / chat-with-artifacts.tsx /
App.tsx. Honesty rule (book plan §6): only real behaviour is documented as present; known gaps are
listed under "What's not covered" and were re-checked against the code. Cite file:line.
-->

## What this is for

The composer is the box at the bottom of every chat — where you actually talk to BioMate. It is more
than a text field: it lets you **attach your own files**, **reference data BioMate already holds**,
attach **standing instructions** and **expert packs** to the request, and shows a live **Instant vs
Cloud** verdict so you know the consequence of a message *before* you send it. Everything you set here
rides along with your message into the same conversation, so BioMate answers or runs in place.

Nothing in the composer runs anything on its own. Attaching a file, picking a dataset, typing
instructions, or toggling an expert only *prepares* the next message. The run (if any) happens after you
send, and — for anything Cloud — only after BioMate confirms with you (see I.6). The composer's job is
to make the request unambiguous and the consequence visible.

## The surfaces — where it lives

The composer is a single component, `ChatInput` (`chat-input.tsx:146`), rendered at the foot of the
chat on the home surface (`/`). You do not open it separately; it is always present under the message
thread. When a chat is empty, the cold-start dashboard sits above it and can **seed** the composer with
an example goal (see "Send behavior & the cold-start seed" below).

Structurally, from top to bottom, the composer stacks (only the rows that apply are shown):

1. **Attachment chips** — attached local files and referenced datasets (`chat-input.tsx:442-496`).
2. **Project-suggested row** — a quiet "this reads like *Project X* — file it there?" proposal, shown
   only when the chat has no home and a real project matches (`chat-input.tsx:565-613`).
3. **Instructions + Experts row** — the collapsible Instructions field and the Experts selector
   (`chat-input.tsx:623-681`).
4. **Lane preview** — the advisory Instant/Cloud verdict (`chat-input.tsx:687-711`).
5. **The input pill** — paperclip, Database icon, attachment-count indicator, the textarea, and the
   Send/Stop button (`chat-input.tsx:714-853`).

## How to use it — each affordance

### Attaching your own files (the paperclip)

The paperclip button opens your operating-system file picker (`chat-input.tsx:729-742`; it clicks a
hidden `<input type="file" multiple>`, `chat-input.tsx:432-439`). Pick one or more files and they appear
as chips above the input, each showing the file name and size (`chat-input.tsx:444-468`). You can also
**drag files onto the composer** — a "Drop files to attach" overlay appears while dragging
(`chat-input.tsx:337-342`, `543-556`). Each attached chip has an **eye** (preview) and an **X**
(remove).

The preview (the eye) opens a dialog that reads the file locally in your browser and shows the first
200 lines: CSV/TSV render as a table (first 50 rows), other text formats render as monospaced text, and
binary formats (BAM, h5ad, MRC, …) show name/size/type only (`chat-input.tsx:349-368`, `498-540`). This
preview is purely local — nothing is uploaded until you send.

> **Tip** — The paperclip is for files **on your computer**. To point at data BioMate already has
> (uploads from earlier, run outputs, project files, or data on the web), use the Database icon instead
> — it avoids re-uploading.

### Referencing data BioMate already holds (the Database icon)

The small **Database** icon next to the paperclip opens the **dataset browser** modal
(`GalaxyDatasetBrowser`, opened at `chat-input.tsx:744-757`, rendered at `856-871`). It has up to four
tabs (`galaxy-dataset-browser.tsx:581-586`):

- **This session** — files already in this conversation, plus an inline upload zone (click or
  drag-drop, up to 50 GB per file with chunked S3 multipart) (`galaxy-dataset-browser.tsx:70-235`).
- **Project files** — files belonging to the active project (only shown when a project is active)
  (`galaxy-dataset-browser.tsx:527-550`).
- **BioMate history** — your analysis histories and their datasets, including run outputs
  (`galaxy-dataset-browser.tsx:240-426`).
- **From URL** — import by pasting a public HTTP/HTTPS, FTP, S3 file, or **S3 folder prefix** URL;
  BioMate fetches it server-side with no size limit, and an S3 prefix counts as one reference for the
  whole collection (`galaxy-dataset-browser.tsx:428-525`).

Picking a dataset ("Use") adds it to the composer as a **dataset chip** and closes the modal
(`galaxy-dataset-browser.tsx:576-579`; `onSelect` handler at `chat-input.tsx:860-870`). The browser
prefers a durable identifier (S3 URI or the authoritative project-file id) so the reference survives
across restarts and is usable by AWS Batch.

> **Note** — The URL-import, public-repo browse, and 50 GB chunked upload live **inside this dataset
> browser modal**, not on the composer surface itself. On the composer you only ever see the paperclip
> (OS picker) and the Database icon (this modal). There is no URL box or public-repo browser directly on
> the composer.

### The dataset chip (a live reference)

A referenced dataset renders as a blue chip: a static **Database** icon plus the file **name**
(`chat-input.tsx:469-494`). The name is a **button** (`data-testid="composer-dataset-ref"`) that
deep-links to the same object in the data hub — clicking it navigates to `/files?file=<id>`
(`chat-input.tsx:479-486`: `onClick={() => setLocation(\`/files?file=${encodeURIComponent(ds.value)}\`)}`).
So a file referenced in chat is a single clickable handle to the underlying dataset object, not just a
label. This deep-link behaviour is locked by a unit test
(`chat-input.dataset-references.test.tsx:39-67`): each chip is a `<button>`, carries the object id in
its `title`, and clicking distinct chips navigates to distinct `file=` targets. The **X** on the chip
removes the reference (`chat-input.tsx:487-492`).

> **Tip** — Hover the chip: its tooltip shows the underlying id (`title` at `chat-input.tsx:482`). This
> is the fastest way to confirm you attached the exact file version you meant.

### Standing instructions (the collapsible field)

Click **Instructions** (the sliders icon) to expand a small text field
(`chat-input.tsx:625-665`). Instructions are a **reading lens** the assistant should apply to *every*
request you send from this composer — e.g. "report FDR<0.05, use GRCh38, prefer conservative
thresholds" (placeholder at `chat-input.tsx:652`). A green dot appears on the toggle when instructions
are present (`chat-input.tsx:639-645`). The value threads into the send payload as `composerInstructions`
(`chat-input.tsx:281`); empty instructions add nothing (honest-empty).

If your chat is filed into a project that carries standing instructions, the composer **inherits** them
into the field automatically, unless you have already typed your own (`chat-input.tsx:177`, seeding
effect at `186-192`). This is how a filed chat picks up its project's standing context.

### Expert / skill packs (the Experts selector)

Next to Instructions is **Experts** (`SkillsSelector`, `chat-input.tsx:674-680`; component in
`skills-selector.tsx`). It opens a popover of expert/skill packs, each with an on/off toggle and a
count chip ("N on") on the button (`skills-selector.tsx:129-291`). The catalogue is fetched from the
real `GET /api/skills` endpoint (`skills-selector.tsx:83-103`). Toggling packs on records which experts
were applied to the request: the selected ids thread into the send payload as `skillPackIds`
(`chat-input.tsx:274`, `286`). When the catalogue is empty, the popover honestly says **"No expert packs
available yet"** rather than showing fake toggles (`skills-selector.tsx:204-209`).

> **Tip** — Instructions and Experts are per-request settings that ride *with* the message. They do not
> silently persist a run behind your back — they are recorded on the answer/run so you (and an auditor)
> can see which lens and which experts were in effect.

### Forcing the lane (the lane preview + override)

As you type (debounced ~350 ms), an advisory **Instant / Cloud** verdict appears above the input pill
(`chat-input.tsx:687-711`, component `lane-preview.tsx`). It shows a coloured dot and label —
"Instant · cited answer" or "Cloud · validated workflow" — a one-line consequence sentence, a plain
"reads as …" read of your intent, a **"why this?"** toggle, and an **override** link
(`lane-preview.tsx:202-291`). The verdict is computed client-side first (`laneForText`,
`lane-preview.tsx:88-102`) and then upgraded to the real router's decision when the server answers via
`POST /api/route/classify` (`lane-preview.tsx:127-177`). It is **advisory only** — it never blocks send,
and it explicitly says "BioMate will confirm before running anything cloud" (`lane-preview.tsx:286-288`).

To **force a lane**, click the override link. On an Instant verdict it reads "run a validated pipeline
instead"; on a Cloud verdict, "answer it instantly instead" (`lane-preview.tsx:232-250`). Clicking it
sets `laneOverride`, and the strip switches to a "forced for this message" state with a "let BioMate
decide" link to undo it (`chat-input.tsx:688-707`). The override applies to the **next send only** and
resets afterward. On send it becomes an `intentOverride` the backend understands: `cloud` →
`workflow_generation` (forces workflow generation, skips ambiguity detection); `instant` →
`research_question` (forces a direct answer) (`chat-input.tsx:275-280`, and the comment at `258-261`).

### Sending (and stopping)

The **Send** button (paper-plane) submits the message (`chat-input.tsx:832-851`). It is disabled unless
there is typed text **or** at least one attached file **or** at least one referenced dataset
(`chat-input.tsx:836`, `839-843`). **Enter** sends; **Shift+Enter** inserts a newline
(`chat-input.tsx:300-305`). While BioMate is streaming a reply, the button becomes a red **Stop** square
that calls `onStop` (`chat-input.tsx:817-831`).

On send (`handleSend`, `chat-input.tsx:248-298`), the composer assembles the outgoing message and a
context override, then clears itself. Dataset references are appended to the message text invisibly as
`[BioMate dataset: <name> (id: <id>)]` lines so the backend can resolve them without you having to see
raw ids in the box (`chat-input.tsx:253-256`); they are **also** passed structurally as
`datasetReferences` (`chat-input.tsx:267-270`, `285`) so the server filters to exactly the files you
picked and reports any missing reference rather than silently choosing another. The full context object
carries `intentOverride`, `composerInstructions`, `datasetReferences`, and `skillPackIds` — each
included only when non-empty (`chat-input.tsx:275-288`). After send, the lane override, message text,
attached files, and dataset chips are all reset (`chat-input.tsx:290-296`).

### Send behavior & the cold-start seed

When a chat is empty, the cold-start dashboard's example cards **seed** the composer (and attach the example's prepared demo dataset) instead of sending.
Clicking an example calls the dashboard's `onSeed(text)` (`cold-start-dashboard.tsx:516`, wired in
`chat-interface.tsx:2134-2139`). That handler prefers `localSetDraftRef.current(text)` — the composer's
externally registered draft setter — and only falls back to sending if no setter is registered
(`chat-interface.tsx:2136-2137`). The setter is registered by the composer via `onRegisterSetDraft`
(`chat-input.tsx:224-232`): it calls `setMessage(draft)` and focuses the textarea, so the seeded text
lands **in the box for you to review and edit — it is not auto-sent**. The same registered setter is
used for the project "Analyze with BioMate" flow, which arrives as `?draft=…` in the URL and populates
(but does not submit) the composer (`App.tsx:161-168`, applied in `chat-with-artifacts.tsx:553-558`,
registered at `chat-with-artifacts.tsx:2275`).

> **Pitfall** — A seeded goal is a *starting point*, not a committed request. Read it, adjust it, attach
> your data, then send. (Note: a `?q=…` URL — used by other entry points — *does* auto-submit; the seed
> path via `?draft=` / cold-start examples does not.)

## What you control

Everything you set in the composer travels with the next message and nothing else:

| Control | Where | What it sends |
|---|---|---|
| Local files | Paperclip / drag-drop | `File[]` uploaded with the message (`chat-input.tsx:289`) |
| Dataset references | Database icon → browser | `datasetReferences` + invisible text refs (`chat-input.tsx:267-270`, `253-256`) |
| Standing instructions | Instructions field | `composerInstructions` (`chat-input.tsx:281`) |
| Expert packs | Experts selector | `skillPackIds` (`chat-input.tsx:274`, `286`) |
| Lane | Lane-preview override link | `intentOverride` = `workflow_generation` / `research_question` (`chat-input.tsx:277-279`) |
| Project home | Project-suggested row | files the chat into a project (`onFileToProject`, `chat-input.tsx:589`) |

## Reading what it shows

- **Lane dot & label** — green = Instant (a cited answer in seconds), blue/primary = Cloud (a validated
  workflow, minutes) (`lane-preview.tsx:191-227`). The "reads as …" line is BioMate's coarse read of
  your intent; "why this?" expands a plain-language reason with no jargon (`lane-preview.tsx:272-285`).
- **Attachment-count indicator** — once you have referenced any datasets in the conversation, an
  `X / 32` counter appears next to the attach buttons: muted below 75% of the cap, amber at 76–99%, red
  at the cap with a tooltip pointing you at S3 prefixes for bulk files (`chat-input.tsx:763-797`). The
  32-reference cap is enforced server-side (`frontend/server/dataset-cap.ts`, mirrored at
  `chat-input.tsx:144`).
- **Instructions "on" dot** — a green dot on the Instructions toggle means a standing instruction is
  active for this composer (`chat-input.tsx:639-645`).
- **Experts "N on" chip** — the count of currently applied expert packs (`skills-selector.tsx:150-167`).
- **Project-suggested row** — "This reads like *X* · filing it there brings its files and instructions
  into context. Nothing runs either way." with "File it there" / "Keep unfiled" (`chat-input.tsx:578-611`).

## Pitfalls & tips

> **Tip — paperclip vs Database.** Paperclip = a file on your machine (uploads on send). Database =
> point at data BioMate already holds (no re-upload). For anything already in the cloud or on the web,
> use the Database icon → *From URL* tab.

> **Pitfall — the dataset chip is a plain reference.** The composer's dataset chip shows only a Database
> icon and the file name. It does **not** show a quality dot, an `id@version`, or the data kind
> (`chat-input.tsx:469-494`). To confirm the exact file, hover for the id tooltip or click through to
> `/files` (the data hub), where the full dataset object lives (see I.5).

> **Pitfall — instructions are a lens, not a command.** Standing instructions shape how BioMate reads
> every request in this composer; they are not a separate action and they do not run anything. Empty
> instructions do nothing.

> **Tip — watch the counter before a bulk experiment.** If you are about to reference dozens of files,
> use an S3 folder prefix (From URL) — it counts as **one** reference for the whole collection and keeps
> you under the 32-reference cap (`chat-input.tsx:773`, `galaxy-dataset-browser.tsx:652-658`).

> **Pitfall — a seeded goal isn't sent.** Cold-start examples and the "Analyze with BioMate" draft only
> pre-fill the box. Review and press Send yourself.

## What's not covered

These are **not** present in the composer today (each re-checked against `chat-input.tsx` and its
imports). They belong in **Appendix E (Coverage & roadmap)**, not here:

- **No richer dataset chip.** The composer chip is a static Database icon + name only — **no quality
  dot, no `id@version`, no data-kind label** (`chat-input.tsx:469-494`). The richer dataset object
  (quality profile, versions, lineage) lives in the data hub at `/files`, which the chip deep-links to
  (see I.5).
- **No inline @-mention typeahead.** There is no `@`-driven autocomplete in the textarea for referencing
  files; attaching data is done through the **modal** (Database icon → `GalaxyDatasetBrowser`)
  (`chat-input.tsx:744-757`). The textarea is a plain auto-resizing input (`chat-input.tsx:799-814`).
- **No pre-attach quality card, and no URL-paste / public-repo browse *on the composer surface*.** The
  composer itself exposes only the paperclip and the Database icon; URL import, public-source fetch, and
  large-file upload all live **inside** the dataset browser modal, and there is no quality/QC card shown
  before you attach (`galaxy-dataset-browser.tsx:428-525`, `70-235`).
- **No project-inherited-vs-deviated distinction on experts.** The Experts selector shows each pack as a
  simple on/off toggle with a description; it does **not** mark packs as "project" (inherited from the
  project) vs "changed" (deviated from the project default) (`skills-selector.tsx:210-264`). It only
  tracks which ids are currently on for this request.

---
_Verification: this page depends on the coverage-ledger rows under **"## Talking to BioMate — the
composer"** — all tier C from `chat-input.tsx` and its imports (`galaxy-dataset-browser.tsx`,
`skills-selector.tsx`, `lane-preview.tsx`) plus the seed wiring in `chat-interface.tsx` /
`chat-with-artifacts.tsx` / `App.tsx`, and the deep-link unit test
`chat-input.dataset-references.test.tsx`. The four gap rows are tier C (verified-absent) → Appendix E._
</content>
</invoke>
