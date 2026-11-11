# Instrument tutorial — SiLA2 devices (a standard, not one machine)

> **Who this is for:** anyone with a SiLA2-compliant lab device — a Hamilton or Tecan liquid handler, a
> centrifuge, an incubator, a plate reader — who wants to know what BioMate can and cannot do with it. No
> coding needed to read this.
> **Time:** ~8 minutes.
> **Where it fits:** Tutorial 6 showed how to *register* an instrument. This tutorial is the honest one:
> "SiLA2" is not a single instrument, so the answer to *"what analysis does it drive?"* is **"it depends on
> what the device is."** This tutorial explains how to tell.

---

## 1. The honest starting point — SiLA2 is a connection standard, not an instrument

Read this first. **SiLA2** is a *communication standard* (based on IEC 62832, using gRPC) that many different
lab devices speak. Registering "a SiLA2 device" tells BioMate *how to talk to it*, but not *what it is*. A
SiLA2 liquid handler and a SiLA2 plate reader both speak SiLA2, yet one prepares samples (no data) and the
other measures them (produces data). So there is **no single analysis workflow** that "a SiLA2 device" drives —
the right answer depends entirely on the device behind the standard.

This is confirmed in the connector code: the SiLA2 adapter is **generic**. It discovers a device, lists the
**features** (capabilities) the device advertises, runs **commands** on it, and reads **properties** — but it
has **no fixed experiment-type → workflow mapping** the way the cryo-EM or nanopore connectors do. What a SiLA2
device drives in BioMate is whatever its *type* drives.

> **In one sentence:** SiLA2 is a universal way to reach a device; what BioMate then does with it is decided by
> what the device actually is — so the useful question is "what kind of device is behind the SiLA2 port?"

---

## 2. What a SiLA2 device produces (it depends)

A SiLA2 device exposes its abilities as named **features**, each with **commands** (actions) and **properties**
(readable values). The adapter ships profiles for several common device families, which show the pattern:

| Device family (example) | Typical SiLA2 features / commands | What it produces | Is it a data instrument? |
|---|---|---|---|
| Hamilton STAR, Tecan Fluent | `LiquidHandlingService`: Aspirate, Dispense, Mix | A prepared plate | **No** — sample prep (like Opentrons) |
| Sartorius incubator | `IncubatorService`: SetCO2, SetTemperature, GetStatus | Controlled conditions | **No** — environment control |
| Plate reader (Synergy, SPARK) | `AbsorbanceReaderService`: ReadAbsorbance, ReadFluorescence | A plate of measurements | **Yes** — produces data |

So some SiLA2 devices (liquid handlers, incubators, centrifuges) are **preparation or environment-control**
machines with no analysis to drive — exactly like the Opentrons case. Others (plate readers) **do** produce a
measurement that can feed an analysis.

---

## 3. The BioMate "workflow" it drives — conditional by type

Because the mapping is not fixed, treat SiLA2 in two layers:

1. **Device control (always available).** Through the generic adapter, BioMate can connect to the device, see
   its features, run a command (e.g. tell a plate reader to read a plate, or a liquid handler to dispense), and
   read a property (e.g. an incubator's current temperature). This is the universal capability and it does not
   depend on the device type.
2. **Analysis (only if the device measures something).** If the device is a *measuring* instrument — a plate
   reader, for example — then the data it produces is what drives a BioMate analysis workflow, and that
   analysis is chosen by the **kind of measurement**, not by "SiLA2":
   - A plate reader's absorbance/fluorescence plate → a **plate-based assay analysis** (e.g. dose–response).
   - A liquid handler → **no analysis** (it is sample prep; its prepared plate feeds a measuring instrument
     next — see the Opentrons tutorial for that same pattern).

**Why it is structured this way:** forcing every SiLA2 device into one workflow would be wrong — most SiLA2
devices do not produce data at all. Keeping control generic and letting the *measurement type* pick the
analysis is the only honest design.

<!-- CAPTURE route=/ ; state=Add-instrument form with type=SiLA2 device selected, showing host/port (gRPC) fields + on-prem residency line ; focus=sila2-form ; note=show the SiLA2 registration form (host/port, gRPC) and the on-prem residency badge -->
*(Figure to add: the Add-instrument form for a SiLA2 device — host/port over gRPC, and the on-prem residency
line.)*

---

## 4. Before you start — getting the device connected

Do Tutorial 6 (*Connecting instruments*) first:

- Register it under **Connectors → Instruments**, type **SiLA2 device**, with the device's **host/IP** and
  **port** (SiLA2 uses gRPC; the default port is **50051**).
- Residency is **on-prem** — the device and its data stay inside your network.
- **A software prerequisite applies to SiLA2 specifically:** the connector needs the `sila2` Python library
  installed where the connector runs (`pip install sila2`). Without it, the adapter can only discover devices,
  not run commands — it operates in discovery-only mode. This is part of the admin/IT setup. Ask your admin
  whether full SiLA2 control is enabled, not just discovery.
- Optional: SiLA2 devices can be discovered automatically on the network (via mDNS) if the `zeroconf` library
  is installed — again an admin detail.

---

## 5. Step by step — work with a SiLA2 device

1. **Identify the device.** After registering and pressing **Check**, look at the device's advertised
   **features**. These tell you what it is — `LiquidHandlingService` means a liquid handler (prep);
   `AbsorbanceReaderService` means a plate reader (data). This step decides everything that follows.
2. **If it is a control/prep device** (liquid handler, incubator, centrifuge): use BioMate to run commands
   (dispense, set temperature, etc.) and read status. There is no analysis to run here — the device's output is
   a prepared plate or a controlled condition, which then goes to a measuring instrument.
3. **If it is a measuring device** (plate reader): run the read command to produce the measurement, then take
   that measurement into the matching BioMate analysis workflow — exactly the normal run-and-read-the-report
   flow (Tutorial 3), chosen by the measurement type.
4. **Confirm before anything acts.** As everywhere in BioMate, a command or a run is shown to you first;
   nothing executes on the device until you confirm.

---

## 6. Reading the result

- **For a control/prep device:** the "result" is the device's **status** and a confirmation the command ran
  (e.g. the incubator reached temperature, the plate was dispensed). There is no analysis report, because there
  is no measurement.
- **For a measuring device:** the measurement (e.g. the plate reader's absorbance values) feeds a BioMate
  analysis workflow, and you read **that** workflow's two-tab report (Results, Reproducibility
  record) as in Tutorial 3. The analysis — not the SiLA2 layer — is where the findings come from.

Because the analysis depends on the measurement type, there is no single "SiLA2 result screen." Match your
reading to the device: a status confirmation for control devices, a workflow report for measuring devices.

---

## 7. Honest limits — what to expect

- **"SiLA2" alone does not pick a workflow.** This is the central honest point: the connector has **no fixed
  experiment-type → workflow mapping** for SiLA2. The analysis is decided by what the device measures, or there
  is no analysis at all. Anyone promising "connect any SiLA2 device and get an analysis" is overstating it.
- **Full control needs the `sila2` library.** Without it, BioMate can discover a SiLA2 device but not command
  it — an admin must install the library where the connector runs. Confirm this before relying on device
  control.
- **Feature names vary by vendor.** Two plate readers may expose slightly different SiLA2 feature names. The
  adapter ships profiles for common families, but your specific device may differ — check its advertised
  features rather than assuming.
- **Many SiLA2 devices are not data instruments.** Liquid handlers, incubators, and centrifuges prepare or
  condition samples; they have no analysis to drive. That is expected, not a gap.
- **This path is conditional and type-dependent.** Treat SiLA2 as "it depends" until you have confirmed the
  specific device's features — do not assume a result the device cannot produce.

---

## 8. Where to go next

| You want to… | Where |
|---|---|
| Register the device / check connectivity | **Tutorial 6 — Connecting instruments** |
| Handle a liquid handler (prep pattern) | **Opentrons instrument tutorial** (same prep-then-measure chain) |
| Run and read an analysis once you have data | **Tutorial 3 — Running a workflow and reading the report** |
| View output files | **Tutorial 5 — Viewing your results** |

The habit for this instrument: **register → Check → read the device's features to learn what it is → control it
(prep) or measure with it (data) → analyse the measurement only if there is one.**

---

## 9. Key terms

| Term | What it means — and why you care |
|---|---|
| **SiLA2** | A standard way for lab devices to talk over the network (gRPC). It says *how to connect*, not *what the device is*. |
| **Feature** | A named capability a SiLA2 device advertises (e.g. `LiquidHandlingService`). Reading the features tells you the device type. |
| **Command / property** | An action you run on the device / a value you read from it. BioMate's generic control surface. |
| **Discovery-only mode** | What happens without the `sila2` library installed — BioMate can find the device but not command it. |
| **Measuring vs control device** | A measuring device (plate reader) produces data to analyse; a control device (liquid handler, incubator) does not. |
| **Conditional mapping** | Why there is no single "SiLA2 workflow" — the analysis depends on what the device measures. |

---

> **Honesty verdict for this instrument:** *Conditional / mapping-unresolved by design.* The SiLA2 adapter is
> generic: it connects, lists features, runs commands, and reads properties, but has **no fixed workflow
> mapping**. Whether any analysis runs depends entirely on the device type — a plate reader feeds an analysis;
> a liquid handler or incubator does not. Full device control additionally requires the `sila2` library to be
> installed by an admin.

_Companion references: `docs/user-manual/tutorials/T6-connecting-instruments.md`;
`docs/user-manual/tutorials/instruments/opentrons-liquid-handling.md` (the prep-then-measure pattern)._
