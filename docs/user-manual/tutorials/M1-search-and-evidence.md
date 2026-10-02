# Module 1 — Search & evidence: asking "what is known?"

> **Who this is for:** anyone — no coding, no bioinformatics background needed. By the end you'll know
> how to ask BioMate a knowledge question, read the cited answer it gives back, tell a strong answer from
> a thin one, and turn a finding into something your project can use later.
> **Time:** ~9 minutes to read; each answer itself returns in seconds.
> **Where it fits:** Tutorial 0 showed the single doorway. This is the first of the four function modules
> in depth — the one that reads the literature and databases and answers *without touching your own data*.
> Its sibling, **Data analysis** (Module 2), is the one that *does* run on your data.

---

## 1. The problem this solves

Before you run an experiment or an analysis, you usually need to know what is already known. *Is this
protein actually linked to the disease? Has anyone reported this side effect? What structures exist for
this target? Did my own team already test this and conclude something?* Answering those questions normally
means opening PubMed, a few databases, and your own old files in separate tabs, reading for an hour, and
hoping you didn't miss the paper that disagrees.

**Search & evidence** is the module that does this reading for you and hands back a short answer where
**every claim carries the source it came from** — so you can check the answer instead of trusting it. It
runs on *nothing of yours*: it reads no file you uploaded, starts no computation, and spends no pipeline
money. Its single promise is traceability.

> **In one sentence:** ask "what is known about X" in plain language, and get a seconds-fast answer whose
> every factual sentence is tied to a real, openable source — with an honest note on what the answer does
> *not* cover.

---

## 2. The ideas you need first (plain-language background)

**The Instant lane.** Every BioMate request falls into one of two lanes (Tutorial 0). Search & evidence is
always the **Instant** lane: a cited answer in seconds, no large computation, no bill. (The other lane,
**Cloud**, is for running a workflow on your data — that's Module 2 and Tutorial 3.)

**A cited answer is a small sourced report, not a chatbot paragraph.** The answer has a fixed shape, and
every part of it earns its place:
- **The claims** — the answer text, where each factual sentence carries a little numbered marker (`¹`, `²`)
  that ties it to a source below. A sentence *without* a marker is framing or context, and is written so it
  reads that way — it is not pretending to be a cited fact.
- **The source list** — one row per source, showing authors, year, venue (the journal), and — importantly —
  **the exact locus relied on**: the figure, table, or claim the sentence actually leaned on. Not a bare
  list of links. Each row has an **open** action.
- **The "Sources disagree" row** — if two sources genuinely conflict on the same point, BioMate shows *both*
  positions side by side with their sources, rather than quietly averaging them into one confident sentence.
  If there's no real conflict, this row simply doesn't appear.
- **The boundary block — always shown.** A short note stating *what the answer is NOT evidence for* — for a
  Search answer, that it synthesises published literature only and has **not** been checked against your own
  data. Read it before you act.

**The four tracks — the shape of an answer differs by where it comes from.** When you open the Search &
evidence card, you'll see four tabs (tracks). They exist because a patent answer, a database record, and a
literature synthesis are genuinely different shapes of answer. You do **not** have to pick a track before
asking — a question asked plainly is answered across whatever corpora fit it, and the answer tells you which
it used. The tracks are a way in and a source of examples, not a required setting.

| Track | What it reads | What an answer looks like |
|---|---|---|
| **Literature** | Peer-reviewed papers and preprints | A synthesis that keeps disagreement intact |
| **Databases** | Curated sequence, structure, pathway, assay and trial registries | Records, with the query that found them |
| **Patents** | Filings and grants | *(see the honest limit below — this is a doorway, not a patent search today)* |
| **Internal** | Your organisation's own reports and run history | "What we already did and concluded," under the same citation rules |

**Retrieval-coverage-bound — the most important honest idea.** BioMate can only cite what its search
actually *retrieves*. If the literature search finds the relevant papers, you get a well-grounded answer. If
it finds **nothing**, the honest behaviour is to say "nothing was found and here is what was searched" — not
to write a confident-sounding paragraph with invented references. BioMate has a guard built in against that
failure (and the always-present boundary block is part of it), but the right mental model is: **this is a
retrieval tool that cites its sources, not an oracle that always has the answer.** A thin or empty result is
information, not a bug.

---

## 3. When you'd use this

- You want to know whether a target, pathway, side effect, or mechanism is supported by the literature —
  *before* committing time or money to testing it.
- You need a quick, **sourced** answer you can paste into a lab meeting or a grant, with the references
  attached so a colleague can check them.
- You want to pull existing records — reported structures for a target, known off-targets for a chemotype,
  trials that hit a pathway and their endpoints.
- You want to ask your *own* organisation's record: "have we assayed this scaffold before, and what did we
  conclude?"

---

## 4. Step by step — asking an evidence question

We'll use a recognisable example that threads through the other tutorials: the link between the protein
**JAK1** and **rheumatoid arthritis** (RA, a common autoimmune disease). JAK1 is a real, well-studied drug
target, so it is a good test of a *strong* answer.

<!-- CAPTURE route=/ ; state=cold start, Search & evidence card expanded showing the four track tabs (Literature · Databases · Patents · Internal) and a few example-intent rows in quotes ; focus=cold-start Search & evidence module card ; note=show the trackbar + .exrow example intents; nothing sent yet -->
*(Figure to add: the Search & evidence card open on the cold start — the four tracks and the quoted example
intents that seed the composer.)*

1. **Open the Search & evidence card (optional).** On the cold start (a new, empty chat), click the
   **Search & evidence** card to see its four tracks and example questions. Clicking any example **seeds**
   the message box — it fills in a suggested question but does **not** send it. You can also skip the card
   entirely and just type your question.
2. **Type your question in plain language.** For example:
   *"What is the evidence linking JAK1 to rheumatoid arthritis, and how strong is it?"*
   As you type, BioMate reads your goal and is designed to show a short restatement — the **lane** it heard
   (here **Instant**) and a subject area. It does not show a menu of database names.
3. **Check the lane, then send.** For a "what is known" question you should see an **Instant** read. Edit the
   wording if you like, then press **Send**. *Only now does anything happen* — and because it's the Instant
   lane, nothing is charged as a pipeline run.
4. **Read the answer (next section).**

> **Pulling records instead of a synthesis.** If you ask a *Databases*-style question — e.g. *"Pull every
> reported structure for JAK1"* or *"Known off-targets for this chemotype?"* — BioMate fans the query out
> across curated biological databases and returns the matching records with the query that found them,
> rather than a prose synthesis. Same doorway, different answer shape.

---

## 5. How to read the answer

<!-- CAPTURE route=/ ; state=chat showing a completed Search answer: lane chip naming corpora used, body text with superscript anchors, the Citations panel expanded with per-source rows (authors · year · venue · "cited for" locus + open), and the amber Boundary block below ; focus=research answer + citation panel + boundary ; note=show a populated, real answer with sources and the always-present boundary block -->
*(Figure to add: a populated JAK1/RA answer — claims with numbered anchors, the source list with each row's
"cited for" locus and an **open** action, and the amber boundary block underneath.)*

- **Read the claims against their markers.** Each numbered marker ties a sentence to a source in the list.
  A sentence with no marker is context, not a cited fact — treat it as framing.
- **Open a source to audit it.** Each source row shows authors, year, venue, and the **"cited for"** locus —
  the specific figure, table, or claim relied on. The **open** action steps you through the sources one by
  one. (It links out to the publisher's page for the full text rather than pretending to reproduce the
  article body inside BioMate.) You can also copy a source's details, or its DOI / PubMed ID, into your
  reference manager.
- **Judge the strength.** Two honest signals help you weigh the answer:
  - **"How this was searched"** — when the search path reports it, a small panel shows, per source, how many
    records were found and how many were kept after filtering (e.g. "18 found · 4 kept"). This only appears
    when real counts exist; its absence is not a failure.
  - **"Sources disagree"** — an amber row that appears only when retrieved sources genuinely conflict.
    Expanding it shows both positions with their sources. BioMate never resolves the conflict silently by
    preferring the newer or the more-cited paper — that judgement is left to you.
- **Read the boundary block.** The amber note at the bottom is *always* there. For a Search answer it says,
  in effect: this synthesises retrieved literature only; it has not been validated against your own data;
  check against your data before relying on it. This is the honest frame for the whole answer.

> **Thin or empty is a real answer too.** If the base is thin — one source, or one lab — the answer says so,
> and does *not* dress a weak claim up in confident prose. If nothing was retrieved at all, BioMate tells
> you what it searched and offers to widen the search or rephrase, rather than inventing sources. When you
> see a short, hedged answer, that is the guard working, not the tool failing.

---

## 6. What to do with the answer

An evidence answer is a starting point, and BioMate gives you three sanctioned ways to carry it forward.
The first two need a **project** open (BioMate's folder for one piece of work — see Tutorial 4):

- **Save to project notes** — writes the answer *with its sources* into the project, so the provenance
  travels; a saved answer never loses its citations. (Disabled, with a tooltip, when no project is open —
  never a fake success.)
- **Make a project instruction** — promotes a finding into a short standing rule the assistant applies in
  that project's future chats — e.g. *"use GRCh38, Ensembl 110."* It's saved as a concise directive, not the
  whole answer.
- **Check against our data** — turns the same question into a real analysis on *your* data. This crosses from
  the Instant lane into the **Cloud** lane (Module 2 / Tutorial 3), so BioMate will confirm before it runs
  anything that costs compute.

---

## 7. Honest limits — what to expect

- **It is retrieval-bound, not an oracle.** The answer is only as good as what the search retrieves. A thin
  base gives a hedged answer; an empty retrieval gives an honest "nothing found," not a confident guess.
  BioMate has a guard against inventing references when retrieval comes back empty — but the correct
  expectation is a *cited retrieval tool*, not a guaranteed answer to every question.
- **The "Patents" track is a doorway, not a patent search (today).** A patent-worded question — "who holds
  composition-of-matter claims on this scaffold?", "freedom-to-operate for this series?" — still returns a
  **literature-grounded** answer. BioMate does **not** search a patent database today. Confirm any
  freedom-to-operate question with patent counsel.
- **"Internal" is only as complete as your record.** The Internal track reads your organisation's own reports
  and run history. It can only cite what has actually been saved into BioMate — it is not a search of email,
  shared drives, or a lab notebook that lives elsewhere.
- **Citation export is partial for literature.** You can copy a source's details and use its DOI / PubMed ID
  in your reference manager. Fully formatted BibTeX is currently populated for *workflow-tool* citations
  (Tutorial 3's reports), not yet for every literature source — so the "Export BibTeX" button is hidden on a
  plain literature answer rather than emitting an empty file.
- **An answer is literature, not a verdict on your data.** This is the whole point of the always-present
  boundary block. To test a claim on your own files, use **Check against our data** (a Cloud run).
- **Empty sections are honesty, not bugs.** The "How this was searched" panel and the "Sources disagree" row
  each appear *only* when real data backs them. An answer without them means there was nothing to show
  honestly — not that something broke.

---

## 8. Where to go next

| You want to… | Module | Lane | Tutorial |
|---|---|---|---|
| Ask "what is known" (cited answer) | Search & evidence | Instant | *this one* |
| Run an analysis on your own data | Data analysis | Instant → Cloud | **Module 2** / **Tutorial 3** |
| Bring a file in so you can analyse it | — | — | **Tutorial 4** |
| Design new candidate molecules | Design & generate | — | **Tutorial 1** |
| Learn from lab results, improve next round | Models | — | **Tutorial 2** |

The habit is always the same: **type a question → check the lane (Instant) → send → read the answer with its
sources → read the boundary → optionally save it or check it against your data.**

---

## 9. Key terms

| Term | What it means — and why you care |
|---|---|
| **Search & evidence** | The module that answers "what is known" over literature and databases. Runs on nothing of yours; always the Instant lane. |
| **Instant lane** | A cited answer in seconds, no computation, no pipeline cost. (Cloud is the other lane, for running on your data.) |
| **Cited answer** | A small sourced report: claims tied to sources, a source list with the locus relied on, and an always-present boundary block. |
| **Track (Literature / Databases / Patents / Internal)** | The four kinds of corpus. A way in and a source of examples — not a setting you must pick before asking. |
| **Locus ("cited for")** | The exact figure, table, or claim a source was used for — shown instead of a bare link, so you can check the specific evidence. |
| **Sources disagree** | An honest row shown only when retrieved sources genuinely conflict; it presents both positions rather than picking one. |
| **Boundary block** | The always-shown note saying what the answer is NOT evidence for (here: literature only, not your data). |
| **Retrieval-coverage-bound** | The answer is limited by what the search finds. Thin → hedged; empty → honest "nothing found," never an invented source. |
| **Save to notes / Make instruction / Check against our data** | The three exits: keep the answer in a project, turn it into a standing rule, or test it on your data (a Cloud run). |

---

> **Honest note on what you'll see today.** A JAK1/RA literature question returns a real, sourced answer
> with its boundary block, and the save/instruction/check-against-data exits are wired to the real
> project-knowledge endpoint (they need a project open). The transparency panel ("How this was searched")
> and the conflict row populate only when the retrieval path supplies real counts or a real conflict —
> otherwise an ordinary answer degrades cleanly to a plain source list. The Patents track routes a
> patent-worded question to a literature-grounded answer; there is no patent-database search behind it today.

_Companion technical reference (for power users / developers):
`docs/user-manual/modules/I03-search-and-evidence.md`._
