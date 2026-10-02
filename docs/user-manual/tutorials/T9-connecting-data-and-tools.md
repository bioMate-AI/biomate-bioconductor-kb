# Tutorial 9 — Connecting data sources & tools

> **Who this is for:** anyone who wants BioMate to reach *beyond* the files they upload — a public
> scientific database, their lab's *own* private database, or an outside tool server — and who wants to
> know, before any data moves, where that data goes. No coding needed to browse what's already
> reachable; connecting your own database or tool server is a short form you fill in (a read-only
> database login or a server address). Lab and hospital **instruments** are a separate kind of
> connection with their own tutorial — see **Tutorial 6**; this one covers everything else.
> **Time:** ~10 minutes to read.
> **Where it fits:** Tutorial 4 showed how to bring a single file in by hand. This tutorial is the wider
> picture: the **Connectors** dialog, where you see every outside source your workspace is attached to,
> and where you attach your own.

---

## 1. The problem this solves

Real research questions rarely sit inside one uploaded file. To answer *"is this variant known to be
pathogenic?"* BioMate needs ClinVar; for *"what's the bioactivity of this compound?"* it needs ChEMBL;
and sometimes the answer lives in **your own** systems — a Postgres database of clinical results behind
your firewall, or a tool server your team built. Wiring each of those up by hand, for every question,
would be slow and error-prone — and worse, you could lose track of **whether your data left the
building**.

BioMate solves this with one place — the **Connectors** dialog — that answers a single question for
every outside source: *what is this workspace attached to, and does my data leave the estate?* The
public scientific databases are **already reachable** (you don't switch them on); your own database or
tool server you attach with a short form; and **every row states where it runs**, so you can check
residency *before* you point sensitive data at it.

> **In one sentence:** Connectors is the one screen that shows everything BioMate can reach — the public
> databases it already queries for you, plus your own database and tool servers you attach — with a
> plain "does my data leave?" badge on every row.

---

## 2. The ideas you need first (plain-language background)

**Where it lives.** Open it from the **Connectors** button in the app sidebar. It opens a full-screen
dialog titled **"Connectors reference."** *(Why it's one screen: the question behind every connection —
a database, a tool server, an instrument — is the same: what are we attached to, and is it working?)*

**Two kinds of tab: read-only reference vs. writable.** This is the single most important thing to
understand, because it stops a common confusion ("I clicked a database — did I connect it?").

- **Read-only reference tabs** — *Public Databases* and *AI & Platforms*. These are a **catalogue** of
  what BioMate can already reach from chat. There is **nothing to connect or switch on** here. You ask a
  question in chat, and BioMate queries the sources your question needs, automatically.
- **The writable tab** — *Your connections*. This is the **one place you actually attach something**:
  your own private database, or your own tool (MCP) server.
- **Instruments** — a fourth tab, covered entirely by **Tutorial 6** (sequencers, plate readers, cloud
  lab platforms). This tutorial does not repeat it.

**Residency — does my data leave the building?** Every row carries a **residency** badge, with no
exceptions. There are five values, shown in a legend at the top of the dialog:
- **cloud** — a query leaves your organisation's own systems (all the public databases are cloud; a
  hosted LLM is cloud).
- **on-prem** — stays inside your network (your own private database).
- **mounted** — read in place, never copied.
- **this machine** — never leaves the host (e.g. a self-hosted Ollama model).
- **prompt only** — it's just instruction text; no data moves.

*(Why it matters: for patient data or any restricted data, residency is the thing you're accountable
for. It's on every row so you can check before you attach — a blank badge would be worse than a wrong
one, so BioMate shows "unspecified" rather than guessing.)*

**Declared facts, not a guess.** Instead of forcing every connector into a category, each row simply
states a few **facts**: what it **needs** (e.g. "API key"), what it **produces**, and **where it runs**.
Where a source hasn't declared a fact, the cell honestly reads **"not declared"** in italics rather than
inventing one.

**Read-only means read-only.** When you connect your own database, BioMate only ever runs **read-only**
queries against it (it reads; it never writes or changes your data). You supply a **read-only login** so
this is enforced on your side too. *(Why it matters: you can attach a live production database without
fear BioMate will modify it.)*

**Preview before attach.** A connection should never surprise you with what it pulled in. The design
rule is that you **see what was found before anything is attached** — for a tool server, its tools are
**listed for you to review** before BioMate will use them. *(Why it matters: attaching first and
explaining later isn't a connection — it's a mess with a receipt.)*

---

## 3. When you'd use this

- You want to understand **which public databases** BioMate draws on when it answers (and confirm a
  source you rely on is covered).
- Your answer depends on **your own** data that lives in a database (clinical results, an internal
  compound registry) and you want BioMate to query it in chat.
- Your team runs a **tool server** (an MCP server) whose tools you want BioMate's assistant to be able
  to call.
- You need to **check residency** before pointing restricted data at any source.

---

## 4. Step by step — by the kind of connection

### 4a. Browsing the public databases (read-only — nothing to switch on)

<!-- CAPTURE route=/ ; state=Connectors dialog open on the "Public Databases" tab, residency legend visible, several database rows with cloud badges and the Scope column ; focus=databases-tab ; note=show the four top tabs, the residency legend, a few rows (UniProt / ClinVar / ChEMBL) with their cloud badge, and the "Scope (preview)" column -->
*(Figure to add: the Public Databases tab — the residency legend, rows like UniProt / ClinVar / ChEMBL each with a cloud badge, and the Scope-preview column.)*

1. **Open Connectors → Public Databases.** Sidebar → **Connectors**; the dialog opens on this tab.
2. **Read the catalogue.** You'll see dozens of sources grouped by sub-tab (Protein & Structure,
   Genomics & Variants, Omics Archives, Chemical & Drug, Pathways & Ontology, Disease & Clinical,
   Literature, and more). Each row gives a one-line description and a **cloud** badge — because every
   one is a remote public service, so a query leaves your organisation's systems to reach it.
3. **That's all you need to do — there's nothing to connect.** BioMate already queries whichever of
   these your chat question needs. You do **not** turn them on one by one.

**About the checkboxes and the "Scope" column — read this, it prevents a real misunderstanding.**
Clicking a row **stars it for your own reference only**. That star is a **personal view filter saved in
your browser** — it does **not** enable, disable, or restrict what BioMate queries. Likewise the
**Scope (preview)** control (Account / Project / Request) is **informational only today**: it records a
preference but **nothing enforces it** — BioMate still queries whichever public sources your request
needs. The footer says this plainly ("does not change what BioMate queries"). *(Why we spell this out:
a checkbox usually means "on/off." Here it doesn't, and assuming it does would give you a false sense of
having locked a source in or out.)*

### 4b. AI & Platforms (also read-only reference)

<!-- CAPTURE route=/ ; state=Connectors dialog on the "AI & Platforms" tab, rows for Anthropic Claude / Ollama / Slack with per-row residency badges and "needs" facts ; focus=ai-tab ; note=show Claude (cloud, needs API key), Ollama (this machine), and a messaging row, with the Declared-facts column -->
*(Figure to add: the AI & Platforms tab — Claude (cloud, needs API key), Ollama (this machine), and a messaging row, with the Declared-facts column.)*

This tab lists the **LLM providers** BioMate can use (Anthropic Claude, Google Gemini, OpenAI GPT, and
self-hosted **Ollama**), plus platform and messaging surfaces (ChatGPT actions, Cursor, Coze, Slack,
Telegram, WeChat/Feishu). Residency here is **per-row**: a hosted model is **cloud**, while Ollama is
**this machine** (never leaves the host).

**It is reference only — you do not configure these here.** The footer says so: messaging bots, IDE
(MCP) access, and GPT-action access are set up from their own tools or the BioMate MCP install flow, not
from this panel. Use this tab to **read** what BioMate exposes and where each option runs.

### 4c. Your connections → Connect a private database (a real, working flow)

This is the first of the **two things you can actually attach**. Use it when the answer lives in your
own database — for example an internal Postgres database of assay results — and you want BioMate to read
from it in chat.

<!-- CAPTURE route=/ ; state=Connectors dialog on "Your connections" tab, "Private databases" sub-tab, the "Add a private database" form filled with example values and the on-prem badge visible ; focus=private-db-form ; note=show the form fields (name, driver=PostgreSQL, host, port 5432, database, read-only user, password), the on-prem badge on the card title, and the "Test connection" + "Save connection" buttons -->
*(Figure to add: the "Add a private database" form — name, driver, host, port, database, read-only user, password, with the on-prem badge and the Test / Save buttons.)*

1. **Open Connectors → Your connections → Private databases.**
2. **Fill in the connection form.** Each field, and where to get its value:
   - **Connection name** — a label you'll recognise, e.g. *"Clinical results DB."*
   - **Driver** — **PostgreSQL** (the supported database type today).
   - **Host** — the database server's address, e.g. `db.internal.example.org` (ask whoever runs your
     database).
   - **Port** — the network port; the box suggests **5432** (Postgres's usual port), which you keep or
     change.
   - **Database** — the database name on that server, e.g. `clinical`.
   - **User (read-only role)** — a login that can **only read**. *Create or ask for a read-only role*
     (e.g. `biomate_readonly`); this is the **read scope** — it decides which tables BioMate may see.
   - **Password** — the read-only role's password. It is **encrypted at rest and never shown back to
     you** here (the saved connection shows only "password set," never the secret).
3. **Test connection.** Press **Test connection**. BioMate opens a short-lived read-only connection and
   runs a harmless `SELECT 1`. Green = it reached the database and could read; red = it couldn't, with
   the reason shown. *(Fix the reason — wrong host, blocked port, bad password — before saving.)*
4. **Save connection.** The connection is saved and now **available to BioMate chat**; it appears in
   **Your database connections** below, which you can delete at any time.

**Read scope — what BioMate can and can't do with it.** Because you supplied a **read-only** role,
every query BioMate runs is read-only; it cannot change your data. The role's grants are the boundary —
BioMate can only query the tables that role is allowed to see. Keep the role narrow and you keep BioMate
narrow.

**How queries and the time they ran matter (reproducibility).** A private database is usually **live** —
its contents change over time. When BioMate pulls an answer from it, that answer reflects the database
**at the moment the query ran**. The design intent is that such a pull is recorded as a dataset object
whose origin notes **the query and the time it ran**, so a later reader can tell *exactly which snapshot*
produced a number — and can see whether re-running today would give the same answer or not. *(Why it
matters: a result taken from a moving database is only defensible if you can say when it was taken; two
runs a week apart may legitimately differ.)*

### 4d. Your connections → Add an MCP server (a real, working flow)

The second thing you can attach. An **MCP server** is a standard way to expose a set of **tools** that
an AI assistant can call. If your team runs one, add it here so BioMate's assistant can use its tools in
chat.

<!-- CAPTURE route=/ ; state=Connectors dialog on "Your connections" tab, "MCP servers" sub-tab, the "Add an MCP server" form with name / transport / URL / auth header, and below it a registered server row showing discovered tool badges ; focus=mcp-form ; note=show the form (transport SSE/HTTP dropdown, URL, optional auth header) and a saved server row listing its discovered tools as small badges -->
*(Figure to add: the "Add an MCP server" form — name, transport, URL, optional auth header — and a saved server row listing its discovered tools as badges.)*

1. **Open Connectors → Your connections → MCP servers.**
2. **Fill in the form:**
   - **Server name** — a label, e.g. *"Lab tools MCP."*
   - **Transport** — **SSE** or **HTTP (streamable)**. *(Only **remote** servers are supported;
     local "stdio" command servers are deliberately **not** allowed, because launching an arbitrary
     command on the host would be a security hole.)*
   - **Server URL** — the server's address, e.g. `https://mcp.example.org/sse`.
   - **Auth header (optional)** — e.g. `Authorization: Bearer …` if the server needs one. It is
     **encrypted at rest** and never shown back.
3. **Add server — and review its capabilities.** When you add it, BioMate performs the MCP handshake and
   **discovers the server's tools**, listing their names on the saved row. This is the
   **preview-before-attach** step for a tool server: **you see exactly which tools it contributes before
   relying on them.** If the handshake finds none, the row honestly says **"no tools discovered"** rather
   than implying it added something.
4. **Manage it.** The server appears under **Your MCP servers**; delete it any time. Its tools are then
   callable by the BioMate assistant in chat.

### 4e. Adding a data source as a directory (index-in-place vs. copy) — concept, not yet in this dialog

This is a **concept worth knowing**, but be clear on its status: **the Connectors dialog does not have a
"add a directory" flow today.** Bringing files or a folder of data in is currently done through the
**Data hub** (upload), which **Tutorial 4** covers end-to-end. The index-in-place-vs-copy model below is
the **designed** behaviour for attaching a large local directory; it is described here so you recognise
the idea, not as a button you'll find right now.

The idea: when you attach a **directory** of data, there are two modes —
- **Index in place (the intended default)** — a large directory (say a 4 TB run folder) is **read where
  it lies** and turned into dataset objects that **point at it**, without copying the bulk of the data.
  This is the **mounted** residency idea: read in place, never copied.
- **Copy in** — for **small** sets you want **versioned inside the project**. Each scan is a version, so
  changed files are tracked rather than silently overwritten.

The same **preview-before-attach** rule applies: a scan would report the file **types and counts** it
found, and what each will become, **before** creating a single dataset object.

> **Honest status:** index-in-place vs. copy is a **design concept**, not a shipped Connectors feature.
> For bringing your own files in **today**, use **Tutorial 4 (Bringing your own data)**.

### 4f. Adding a skill / expert — what actually works today

A **skill / expert** is a reusable **reasoning pack** that sharpens *how* BioMate reads your request
(for example, "read these results for regulatory risk"). It does **not** pick a workflow and **cannot
change a run's parameters** — that's a separate, written project instruction.

**Honest, verified status — read this before looking for an "add a skill" button:**

- **There is no "add a skill/expert" flow in the Connectors dialog.** A "Skills" tab was scaffolded and
  then **deliberately removed** from this dialog, because nothing in the backend read what you selected —
  it would have advertised a capability that didn't exist. It was **not** replaced with another add-flow.
  (The design spec *describes* a skill/expert add mode — "you describe it; declare what it needs and
  produces" — but **that is design, not shipped**.)
- **The only working skill/expert surface is in the chat composer**, not here. Next to the message box
  there's an **Experts** control: a popover that lists the expert packs the backend offers and lets you
  **toggle existing ones on or off for a single request** (the run then records which were applied).
- **It toggles existing packs; it does not let you create, upload, or add a new one.** And if the
  backend catalogue has no packs, the popover honestly says **"No expert packs available yet"** rather
  than showing toggles that do nothing.

So, in plain terms: **you can switch existing experts on per question (in the composer); you cannot add
a new skill or expert through the UI today.**

<!-- CAPTURE route=/ ; state=main chat view, the composer "Experts" popover open showing either a list of expert-pack toggles or the "No expert packs available yet" empty state ; focus=composer-experts ; note=show the Experts control next to the message box and the popover contents (packs with on/off checks, or the honest-empty message) -->
*(Figure to add: the composer's Experts popover — existing packs with on/off toggles, or the honest "No expert packs available yet" empty state.)*

---

## 5. Honest limits — what to expect

- **Adding a skill/expert is not wired in the UI.** There is **no add-flow** for skills/experts anywhere
  in the shipped product; the Connectors "Skills" tab was removed on purpose. The **only** skill/expert
  action you can take is **toggling existing packs per request** in the composer's Experts popover — and
  that list is **honest-empty** when the backend has none. Do not expect to create or upload one.
- **The Public Databases and AI & Platforms tabs are reference only.** Nothing is connected or switched
  on there. The row **checkboxes are a personal star/filter saved in your browser**, and the **Scope
  control is an informational preview that nothing enforces** — neither one changes what BioMate queries.
- **Private database = PostgreSQL + read-only.** The supported driver is PostgreSQL, and queries are
  always read-only — supply a read-only role. BioMate never writes to your database.
- **MCP servers are remote only.** SSE or HTTP; local "stdio" command servers are intentionally not
  allowed for security. If the handshake finds no tools, the row says so honestly.
- **The directory "index-in-place vs. copy" add-flow is a design concept, not a shipped feature.** Bring
  your files/folders in via the **Data hub** today (Tutorial 4).
- **Residency "unspecified" means not declared, not unsafe.** A dashed/unspecified badge means the
  source didn't declare where it runs — treat it as "unknown, check before attaching restricted data,"
  not as a verdict.
- **Instruments are a separate tutorial.** Sequencers, plate readers, and cloud lab platforms are in
  **Tutorial 6** — don't look for them here beyond the Instruments tab.

---

## 6. Where to go next

| You want to… | Where |
|---|---|
| Bring a single file or folder of data in | **Tutorial 4 (Bringing your own data)** |
| Connect a lab or hospital **instrument** | **Tutorial 6 (Connecting instruments)** |
| Run an analysis and read the report | **Tutorial 3** |
| Switch an expert pack on for one question | The composer's **Experts** control (per request) |
| See what public databases BioMate can reach | **Connectors → Public Databases** |

The habit: **browse what's already reachable (Public Databases, read-only) → attach your own in *Your
connections* (database or MCP server) → check the residency badge before you point restricted data at
anything.**

---

## 7. Key terms

| Term | What it means — and why you care |
|---|---|
| **Connectors dialog** | The one screen (sidebar → **Connectors**) showing every outside source your workspace is attached to. Four tabs: Public Databases, AI & Platforms, Your connections, Instruments. |
| **Read-only reference tab** | *Public Databases* and *AI & Platforms* — a catalogue of what BioMate already reaches. Nothing to connect; you can't "switch a source on" here. |
| **Your connections** | The one **writable** tab — where you attach your **own** private database or MCP server. |
| **Residency (cloud / on-prem / mounted / this machine / prompt only)** | Where a source runs and whether your data leaves. Shown on every row; "unspecified" means not declared, not unsafe. Check it before attaching restricted data. |
| **Declared facts** | The plain facts a row states — what it **needs**, **produces**, and **where it runs** — instead of a forced category. "Not declared" is shown honestly when a fact is absent. |
| **Read scope (private database)** | The read-only role and the tables it may see — the boundary of what BioMate can query. Keep it narrow. |
| **Read-only query** | BioMate only reads from your database; it never writes or changes it. |
| **MCP server** | A remote server that exposes a set of **tools** an AI assistant can call. Add it by URL (+ optional auth); its tools are **listed for review before** they're used. |
| **Preview-before-attach** | The rule that you see what a connection found (a server's tools; a directory's file types/counts) **before** anything is attached. |
| **Index in place vs. copy (directory)** | *Design concept:* a big directory is read where it lies (index/mounted, not copied); small sets can be copied in and versioned. Not a shipped Connectors flow — use the Data hub today. |
| **Skill / expert pack** | A reasoning pack that changes *how* BioMate reads a request (never a workflow or a parameter). **Toggled per request in the composer; there is no add-flow in the UI today.** |
| **Scope (preview)** | An **informational** Account/Project/Request preference on reference rows. Not enforced — it does not change what BioMate queries. |

---

_Companion technical reference (for power users / developers):
`docs/user-manual/modules/I12-connectors-and-skills.md`. Instruments: Tutorial 6 +
`docs/user-manual/modules/I14-instruments-and-lab-connectivity.md`. Bringing your own data: Tutorial 4._
