# Tutorial 6 — Connecting lab & hospital instruments

> **Who this is for:** anyone in a lab or hospital who wants data from their instruments — a sequencer, a
> plate reader, a liquid-handling robot — to flow into BioMate without manual uploads. No coding needed to
> *use* the registry; connecting an instrument usually needs one-time help from an admin (explained below).
> **Time:** ~8 minutes to read.
> **Where it fits:** Tutorial 4 showed how to bring a file in by hand. This tutorial is the step up: letting
> an instrument deliver its data to BioMate for you, and turning that into an analysis.

---

## 1. The problem this solves

A lab produces data on machines — a sequencer writes FASTQ files, a plate reader writes a results table, a
mass spectrometer writes spectra. Normally someone copies those files off the instrument, remembers which run
is which, and uploads them. That hand-off is slow and easy to get wrong.

BioMate lets you **register an instrument once** so that when it produces new data, BioMate is told about it
and offers to run the matching analysis — you just review and confirm. The instrument becomes a connected
**data source** (see Tutorial 4 for the dataset idea), not a pile of files you copy and upload by hand. It
saves the manual copy-and-upload after every run and keeps a clean record of which instrument produced which
data — useful for audits.

> **In one sentence:** register your instrument once; when it makes new data, BioMate shows it to you as a
> ready-to-run suggestion — nothing runs until you confirm.

---

## 2. The ideas you need first (plain-language background)

**Where it lives.** Instruments are managed in **Connectors → Instruments** (sidebar → **Connectors**, then
the **Instruments** tab). Connectors is where you see everything your workspace is attached to; an instrument
is one kind of connection. *(Why it's here: the question behind every connection is the same — what is this
workspace attached to, and is it working?)*

**The two parts of connecting an instrument.** This matters, so it's stated plainly:
1. **The registry entry** (what this tutorial covers) — you add the instrument in the UI: its name, type, and
   how to reach it. This is the point-and-click part.
2. **The connector that actually moves the data** — for most instruments, a small BioMate **connector/watcher**
   runs *on your lab's own network* (next to the instrument) and tells BioMate when new files appear. Setting
   that up is a **one-time admin/IT step**, not something you click in the app. *(Why: your instrument sits on
   the lab network, behind your firewall; BioMate in the cloud can't reach it unless something on your side
   forwards the data. Two exceptions below need no local watcher.)*

**Residency — does my data leave the building?** Every instrument row shows a **residency** badge, with no
exceptions:
- **on-prem** — the instrument and its data stay inside your network (all the local and file-watcher types).
- **cloud** — the service lives in the cloud and data leaves your organisation's own systems (Illumina BaseSpace, Benchling).
*(Why it matters: for patient or otherwise restricted data, residency is the thing you're accountable for —
it's shown on every row so you can check before connecting.)*

**Connectivity status.** Each registered instrument shows a status: **Online**, **Offline**, **Error**, or
**Not checked**. You can press **Check** to test the connection live. *(Why: it tells you whether BioMate can
actually reach the instrument right now, before you rely on it.)*

**New-data events.** When a connected instrument produces data, it appears in the **New data events** list as
a suggestion: what was produced, from which instrument, and which workflow it maps to. *(Why: this is the
hand-off made visible — you see the data arrive and decide what to do.)*

---

## 3. When you'd use this

- Your lab runs the same instrument regularly and you're tired of manually copying and uploading its output.
- You want new runs to show up in BioMate automatically as ready-to-run analyses.
- You want a clear record of which instrument produced which data (residency and provenance included).

---

## 4. Step by step — registering an instrument

<!-- CAPTURE route=/ ; state=Connectors dialog open on the Instruments tab, "My instruments" + "New data events" sections visible ; focus=instruments-section ; note=show the Instruments tab, an instrument row with a status + residency badge, and the Add-instrument button -->
*(Figure to add: the Instruments tab inside Connectors — the instruments list with status and residency badges, and the "Add instrument" button.)*

1. **Open Connectors → Instruments.** Sidebar → **Connectors** → the **Instruments** tab.
2. **Click "Add instrument"** and fill in the form:
   - **Name** — a label you'll recognise, e.g. *"Lab OT-2 (Bench 3)"*.
   - **Type** — pick from the ten supported types (see §5). The form then asks only for what that type needs.
   - **For a local instrument** (robot, sequencer, cryo-EM): its **host / IP** and **port** on your lab
     network (the form shows the usual port for that type as a hint — e.g. 31950 for Opentrons — which you
     type in or change).
   - **For a cloud service** (BaseSpace, Benchling): an **API key / token**.
   - **For a file-watcher type** (LC-MS, qPCR, flow cytometer, plate reader): the **watched output directory**
     the instrument writes to.
   The form shows the **residency** (on-prem or cloud) for the type you picked, before you save.
3. **Register.** The instrument appears in **My instruments** with a **Not checked** status.
4. **Check the connection.** Press **Check** on the row. BioMate tests it live and sets the status to
   **Online** (reachable) or **Offline / Error** (not reachable — the row shows the reason).

<!-- CAPTURE route=/ ; state=Add-instrument form open with a type selected (e.g. opentrons) showing host/port + residency line ; focus=add-instrument-form ; note=show the type dropdown, the host/port fields, and the "Residency: on-prem" line -->
*(Figure to add: the Add-instrument form — type dropdown, the fields that appear for that type, and the residency line.)*

> **The one-time setup (admin step).** Registering the instrument tells BioMate it *exists*. For most types,
> data only starts flowing once a BioMate **connector/watcher** is running on your lab network, pointed at the
> instrument (or its output folder). That's an IT/ops setup, done once per instrument — ask whoever administers
> your lab's BioMate deployment. **Illumina BaseSpace** and **Benchling** need no *on-network file-watcher*
> because they're cloud services reached with an API key — but even then, something on BioMate's side still has
> to poll the cloud service with your key before events appear; the key you enter here lets BioMate **check and
> store** the connection, not pull data by itself (ask your admin whether that poll is running). Separately,
> **Opentrons** robots can be driven directly from a connected assistant (via MCP) on the same network.

---

## 5. The instrument types you can register

| Type | What it is | How it connects |
|---|---|---|
| **Opentrons OT-2 / Flex** | Liquid-handling robot | Local (host + port); also drivable directly on the LAN |
| **Nanopore MinKNOW** | Nanopore sequencer | Local (host + port) |
| **Thermo EPU / cryo-EM** | Cryo-EM acquisition | Local (host + port) |
| **Illumina BaseSpace** | Cloud sequencing platform | Cloud (API key) — **data leaves your organisation's systems** |
| **LC-MS** | Mass spectrometry | File-watcher (watched output directory) |
| **qPCR** | Quantitative PCR | File-watcher (watched output directory) |
| **Flow cytometer** | Flow cytometry (FCS files) | File-watcher (watched output directory) |
| **Plate reader** | Plate-based assays | File-watcher (watched output directory) |
| **SiLA2 device** | Any SiLA2-standard lab device | Local (host + port, gRPC) |
| **Benchling ELN / LIMS** | Electronic lab notebook / sample tracking | Cloud (API key); automatic assay-result pulling for drug-discovery campaigns is set up separately (the CRO flow), not from this registry |

All the local and file-watcher types are **on-prem** (data stays inside your network). Only BaseSpace and
Benchling are **cloud**.

---

## 6. How to act on new data

When a connected instrument produces data, it shows up under **New data events** with a short description, the
source instrument, the experiment type, and the workflow it maps to. For each event you can:

- **Launch** — BioMate opens a chat with a **pre-filled draft** to run the matching workflow on that data. The
  draft is **not sent automatically**: you review it, adjust anything, and press Send yourself — exactly the
  "nothing runs until you confirm" rule from Tutorial 0. From there it's the normal run-and-read-the-report
  flow (Tutorial 3).
- **Dismiss** — clear the event if you don't want to act on it.

<!-- CAPTURE route=/ ; state=New data events list showing one event with Launch + Dismiss buttons ; focus=instrument-event ; note=show an event card: description, source/experiment/workflow badges, Launch + Dismiss -->
*(Figure to add: a New-data event — its description, the source/experiment/workflow tags, and the Launch and Dismiss buttons.)*

> **Who does what.** You register the instrument and act on events; an admin wires up the on-network connector
> once; BioMate watches for new data, surfaces it, and runs only what you confirm.

---

## 7. Honest limits — what to expect

- **Registering ≠ data flowing.** The in-app registry is new. Adding an instrument records it and lets you
  **Check** connectivity, but for most types the data pipeline only runs once a connector/watcher is deployed
  on your lab network (an admin step). BaseSpace and Benchling are cloud services, so they need no on-network
  file-watcher — but a cloud connector/poll still has to run with your key before events appear.
- **Local instruments must be reachable.** A **Check** can only succeed if BioMate can reach the instrument's
  host/port, or the connector runs where it can. A cloud-only deployment cannot see a bench instrument on your
  LAN.
- **Cloud services need a valid key.** BaseSpace and Benchling show **cloud** residency and require a working
  API key; without one, **Check** reports an error.
- **Launch opens a draft, it does not run.** The event's Launch action seeds a chat message for you to review
  and send — it never starts a run on its own.
- **For deeper setup** (the connector/watcher, supported file patterns, advanced per-type options), see the
  instrument module reference: `docs/user-manual/modules/I14-instruments-and-lab-connectivity.md`.

---

## 8. Where to go next

| You want to… | Where |
|---|---|
| Bring a single file in by hand | **Tutorial 4** |
| Run an analysis and read the report | **Tutorial 3** |
| Ask your first question | **Tutorial 0** |
| See what else your workspace connects to | **Connectors** (Databases, AI & Platforms tabs) |

The habit: **register the instrument → Check it → act on its New-data events (Launch → review → send).**

---

## 9. Key terms

| Term | What it means — and why you care |
|---|---|
| **Instruments (Connectors tab)** | Where you register and manage lab/hospital instruments. One place to see what's connected and whether it's reachable. |
| **Registry entry** | The instrument's record in BioMate (name, type, how to reach it). Registering it ≠ data flowing — most types also need an on-network connector. |
| **Connector / watcher** | The piece that runs on your lab network and tells BioMate when new data appears. A one-time admin/IT setup for most instruments. |
| **Residency (on-prem / cloud)** | Whether the instrument's data stays inside your network (on-prem) or leaves it (cloud). Shown on every row — check it before connecting restricted data. |
| **Status (Online / Offline / Error / Not checked)** | Whether BioMate can reach the instrument right now; press **Check** to test it live. |
| **New data event** | A suggestion that new instrument data has arrived, mapped to a workflow. **Launch** opens a reviewed draft; nothing runs until you send. |

---

_Companion technical reference (for admins / developers): `docs/user-manual/modules/I14-instruments-and-lab-connectivity.md`._
