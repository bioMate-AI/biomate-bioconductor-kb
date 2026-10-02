# Instrument tutorial — Opentrons OT-2 / Flex (liquid-handling robot)

> **Who this is for:** anyone with an Opentrons OT-2 or Flex pipetting robot on the bench who wants to know
> what BioMate actually does with it. No coding needed to read this.
> **Time:** ~8 minutes.
> **Where it fits:** Tutorial 6 showed how to *register* an instrument so BioMate can see it. This tutorial
> answers the next question for one specific machine: *"I have an Opentrons robot — what does BioMate do with
> it, and how do I read the result?"*

---

## 1. The honest starting point — this is a sample-prep robot, not a data instrument

Read this first, because it changes what the rest of the tutorial promises. An Opentrons OT-2 or Flex is a
**liquid-handling robot**: it moves precise volumes of liquid between wells on a plate — diluting samples,
laying out a plate of compounds, setting up an assay. **It does not measure anything.** It produces *prepared
plates*, not a dataset you analyse.

So, unlike a sequencer or a microscope, the Opentrons robot has **no "result file" for BioMate to interpret on
its own.** This is confirmed in the connector code itself: every other instrument connector maps its output to
a BioMate analysis workflow, but the Opentrons connector has **no workflow mapping** — it only *runs
protocols* on the robot (upload a protocol, start it, check its status). That is the truth, and this tutorial
will not invent an analysis the robot cannot produce.

What BioMate genuinely does for an Opentrons robot is therefore two things:

1. **Protocol execution** — send a pipetting protocol to the robot and drive the run (start, monitor, stop).
2. **Set up the downstream assay** — the plate the robot prepares is the *input* to a real analysis later
   (for example a plate-reader assay, or a compound panel that feeds an ADMET screen). That later analysis is
   where the BioMate workflow lives — not on the robot.

> **In one sentence:** BioMate can *drive* your Opentrons robot to prepare a plate, but the robot's job ends
> at a prepared plate — the analysis happens on whatever instrument *measures* that plate afterwards.

---

## 2. What this instrument produces

- **A physical prepared plate** — e.g. a 96-well plate with samples diluted to set concentrations, or a plate
  laid out with one compound per well. This is the real product; it is hardware output, not a file.
- **A run record on the robot** — the robot keeps a log of every pipetting step it performed, its status
  (`idle` / `running` / `succeeded` / `failed` / `stopped`), and timestamps. BioMate can read this record.
- **Occasional small data files** — some custom protocols write a CSV plate-map or a JSON summary (which well
  holds what). These are bookkeeping files describing the layout, not measurements.

---

## 3. The BioMate "workflow" it drives (and why)

For the Opentrons robot the "workflow" is **protocol execution**, done through BioMate's instrument-protocol
path (available to a connected assistant over the lab network via MCP, the mechanism Tutorial 6 mentions for
driving an Opentrons robot directly). The cycle is:

1. **A protocol is prepared** — a short Python protocol that lists the labware (plates, tip racks), the
   pipette, and the transfers (which volume goes from which well to which well). BioMate can generate a simple
   well-to-well transfer protocol for you, or you upload one your lab already uses.
2. **BioMate uploads it to the robot** and starts the run.
3. **BioMate monitors the run** until it reaches a terminal state (`succeeded`, `failed`, or `stopped`).
4. **The prepared plate is then measured** on another instrument, and *that* measurement is what feeds a
   BioMate analysis workflow (see §6).

**Why it works this way:** keeping the design and the execution in one place means the plate layout you
intend is exactly the plate the robot makes, and the record of what it did is captured automatically — useful
when you later need to explain which well held which sample.

<!-- CAPTURE route=/ ; state=Connectors dialog open on Instruments tab, an Opentrons row (type=opentrons) showing host/port + on-prem residency badge + Online status ; focus=instrument-row ; note=show a registered Opentrons robot row with Online status and on-prem residency -->
*(Figure to add: a registered Opentrons robot in Connectors → Instruments — its host/port, the on-prem
residency badge, and an Online status after pressing Check.)*

---

## 4. Before you start — getting the robot connected

This tutorial assumes the robot is already reachable by BioMate. If it is not, do Tutorial 6 first
(*Connecting lab & hospital instruments*):

- Register the robot under **Connectors → Instruments**, type **Opentrons OT-2 / Flex**, with its **host/IP**
  and **port** on your lab network (the form suggests the usual Opentrons port, **31950**, as a hint).
- Press **Check** to confirm BioMate can reach it (status turns **Online**).
- Residency is **on-prem** — the robot and its run records stay inside your network.
- Driving the robot to *run* a protocol (not just see it) is set up by whoever administers your lab's BioMate
  deployment, because the robot sits on your lab network behind your firewall. Ask your admin whether
  protocol execution is enabled for your robot.

You will also need a **protocol** — either one BioMate generates (a simple transfer) or a `.py` protocol file
your lab already validated on this robot.

---

## 5. Step by step — run a protocol

1. **Describe the liquid-handling task** to BioMate in plain English, e.g. *"On the OT-2 at bench 3, transfer
   50 µL from each well of the source plate to the matching well of the destination plate."* BioMate can turn
   a simple, well-to-well transfer like this into a protocol for you, or you can attach your own `.py`
   protocol.
2. **Review the protocol before anything moves.** Check the labware names, the pipette, and the list of
   transfers. This is your chance to catch a wrong volume or a swapped well *before* the robot runs — nothing
   is sent to the robot until you confirm.
3. **Confirm and run.** BioMate uploads the protocol to the robot and starts it. The robot begins pipetting.
4. **Watch the run.** BioMate reports the live status — `running`, then a terminal `succeeded`, `failed`, or
   `stopped`. If a step errors (e.g. a missing tip rack), the run goes to `failed` and the robot's error
   message is shown; fix the deck and run again.
5. **Collect the prepared plate** from the robot when the run succeeds. It is now ready to be measured.

<!-- CAPTURE route=/ ; state=chat showing an Opentrons protocol-run draft (labware, pipette, transfer list) before confirm ; focus=protocol-review ; note=show the pre-run protocol summary a user reviews before the robot moves -->
*(Figure to add: the protocol review before a run — labware, pipette, and the transfer list, with a
Confirm & run action; nothing moves until confirmed.)*

---

## 6. Reading the result — and where the real analysis begins

Because the robot does not measure anything, "reading the result" has two parts:

**On the robot run itself:**
- **Status** — `succeeded` means every pipetting step completed; `failed` / `stopped` means it did not, with
  the robot's own error text.
- **The record** — the list of steps the robot performed, and timestamps. If your protocol wrote a plate-map
  CSV or JSON, that tells you which well holds which sample — keep it, because it is how you will label the
  measurements later.

**On the downstream analysis (the part that produces science):**
The prepared plate is now an *input* to a measuring instrument, and that measurement feeds a real BioMate
workflow. Common hand-offs:

| What you prepared | What measures it next | The BioMate analysis it then feeds |
|---|---|---|
| A dilution series / dose plate | Plate reader (absorbance/fluorescence) | A plate-based assay analysis (e.g. dose–response) |
| A compound panel (one compound per well) | Downstream assay or in-silico screen | ADMET / drug-discovery screening (see the Benchling tutorial) |
| Normalised nucleic-acid samples | Sequencer (Illumina / Nanopore) | RNA-seq or variant calling (see the Nanopore tutorial) |

So the Opentrons robot is the **first link in a chain**: prepare → measure → analyse. BioMate drives the first
link and runs the last one; the middle (the measurement) happens on the measuring instrument.

---

## 7. Honest limits — what to expect

- **No analysis workflow is produced by the robot.** This is by design, confirmed in the connector: the
  Opentrons connector runs protocols and reports status; it does **not** map to any BioMate analysis workflow.
  Anyone who tells you "point BioMate at your OT-2 and get an analysis" is wrong about this machine.
- **Protocol execution depends on admin setup.** Registering the robot lets BioMate *see* and *Check* it.
  Actually *driving* it to run a protocol over your lab network is an admin-enabled capability — confirm it is
  turned on for your robot before relying on it.
- **BioMate does not validate your chemistry.** It will faithfully run the protocol you confirm. It does not
  know whether 50 µL is the right volume for your assay — you do. Review the protocol carefully.
- **The record describes layout, not measurement.** A plate-map CSV says *where* each sample is, not *what the
  assay measured*. The measurement comes from the next instrument.
- **Status is honest.** A `failed` run is reported as failed, with the robot's error — BioMate does not pretend
  a run succeeded.

---

## 8. Where to go next

| You want to… | Where |
|---|---|
| Register the robot / check connectivity | **Tutorial 6 — Connecting instruments** |
| Analyse a compound panel you prepared | **Benchling instrument tutorial** (drug-discovery / ADMET) |
| Analyse sequencing of samples you prepared | **Nanopore instrument tutorial** |
| Run and read any analysis workflow | **Tutorial 3 — Running a workflow and reading the report** |

The habit for this instrument: **design the protocol → review it → run it on the robot → measure the plate
elsewhere → analyse that measurement in BioMate.**

---

## 9. Key terms

| Term | What it means — and why you care |
|---|---|
| **Liquid-handling robot** | A machine that moves precise liquid volumes between wells. It prepares plates; it does not measure them. |
| **Protocol** | The instruction list the robot runs (labware, pipette, transfers). You review it before the robot moves. |
| **Protocol execution** | BioMate's actual job for this robot: upload a protocol and drive the run. Not an analysis. |
| **Run status** | `idle` / `running` / `succeeded` / `failed` / `stopped` — the robot's own honest report of how the run went. |
| **Plate-map (CSV/JSON)** | An optional file saying which well holds which sample — bookkeeping, not a measurement. |
| **Downstream assay** | The measurement step (plate reader, sequencer, etc.) that turns your prepared plate into data a BioMate workflow can analyse. |

---

> **Honesty verdict for this instrument:** *Not a data-analysis instrument — by design.* BioMate's real
> capability here is **protocol execution** (drive the robot, report status), which the connector supports. The
> robot maps to **no** analysis workflow; the science happens on the instrument that *measures* the plate it
> prepared. This tutorial deliberately does not promise an analysis the Opentrons cannot produce.

_Companion references: `docs/user-manual/tutorials/T6-connecting-instruments.md` (registering the robot);
`docs/user-manual/modules/I14-instruments-and-lab-connectivity.md` (admin setup)._
