# Instrument tutorial — Thermo EPU / cryo-EM microscope → 3-D reconstruction

> **Who this is for:** anyone collecting single-particle cryo-EM data on a Thermo Fisher microscope (Titan
> Krios, Talos Arctica, Glacios) running EPU. No coding needed to read this.
> **Time:** ~10 minutes.
> **Where it fits:** Tutorial 6 showed how to *register* an instrument. This tutorial answers: *"My microscope
> finished a session — what analysis does BioMate run on it, how do I start it, and how do I read the 3-D map
> it produces?"*

---

## 1. The problem this solves

A cryo-electron microscope does not hand you a picture of your protein. It records **thousands of noisy
movies** — short clips of frozen particles scattered at random angles in a thin layer of ice. Each movie is
almost pure noise; the structure is hidden in the *average* of tens of thousands of particle views combined at
the correct relative angles. Turning that pile of movies into a single sharp **3-D density map** — the thing
you can actually fit a protein model into — is a long, multi-step computational job called **single-particle
analysis (SPA)**.

Done by hand, SPA means running a dozen specialist tools in order (motion correction → CTF estimation →
particle picking → 2-D classification → 3-D refinement → sharpening), each with its own settings and quality
checks, over many GPU-hours. BioMate packages this whole pipeline so you point it at your EPU session folder
and get the map back, with a record of every step.

> **In one sentence:** BioMate takes the raw movie frames your microscope collected and runs the full
> single-particle reconstruction pipeline for you, returning a 3-D density map plus a resolution estimate and
> an audit trail.

---

## 2. What this instrument produces

EPU (the acquisition software on Thermo microscopes) writes, into a dated session folder:

- **Movie frames** — many `.mrc`, `.tif`, or `.eer` files, each a short movie of one field of frozen particles
  (often thousands of files per session). This is the raw data.
- **Session metadata** — small `.xml` files recording the **acceleration voltage** (e.g. 300 kV), the **pixel
  size** (how many ångströms one image pixel spans — the microscope's effective "ruler"), magnification, and
  defocus range. BioMate reads these so you do not have to type them in.

A typical EPU folder looks like `…/<date>_<sample>/Images-Disc1/GridSquare_*/Data/*.mrc` for the movies, with
a `Metadata/` folder alongside.

---

## 3. The BioMate analysis it drives (and why)

The cryo-EM connector maps a completed EPU session to one workflow, confirmed in the connector code and in the
BioMate catalog:

- **Workflow:** `cryosparc_standard_spa` — *"CryoSPARC Standard Single Particle Analysis"*
- **Key input parameter:** `movies_path` (the folder of movie frames), plus `voltage` and `pixel_size`, which
  BioMate fills in from the EPU metadata.
- **What it is:** the standard ~23-step CryoSPARC single-particle workflow (BioMate's version runs it as a
  multi-step pipeline): import movies → patch motion correction → CTF estimation → particle picking → 2-D
  classification → template picking → 3-D refinement → post-processing/sharpening.

**Why this workflow:** it is the established, published route from raw movies to a 3-D map, the same sequence
cryo-EM facilities use. Each stage removes a different kind of error — motion correction fixes blurring from
beam-induced movement, CTF estimation corrects the microscope's optical distortion, classification throws out
junk particles, and refinement aligns the good ones into one high-resolution average.

A few scientific rules the workflow follows (so you can trust the numbers it reports):
- **Resolution is reported at FSC = 0.143** — the gold-standard criterion (Henderson et al. 2012). A smaller
  number of ångströms means higher resolution (more detail); 3 Å is excellent, 8 Å is low.
- **Micrographs with poor CTF quality are discarded**, so bad images do not pollute the average.

<!-- CAPTURE route=/ ; state=New data events list showing a cryo-EM event (source=epu_session_watcher, workflow=cryosparc_standard_spa, movie count) with Launch + Dismiss ; focus=cryoem-event ; note=show the cryo-EM new-data event card mapping an EPU session to the CryoSPARC SPA workflow -->
*(Figure to add: a cryo-EM New-data event — "session complete, N movies", mapped to the CryoSPARC Standard SPA
workflow, with Launch and Dismiss.)*

---

## 4. Before you start — getting the movies to BioMate

Do Tutorial 6 (*Connecting instruments*) first if the microscope is not yet connected:

- Register it under **Connectors → Instruments**, type **Thermo EPU / cryo-EM**, with the microscope PC's
  **host/IP** and **port**.
- Residency is **on-prem** — the movies stay inside your facility network.
- Because cryo-EM datasets are enormous, in most facilities a BioMate **watcher runs on the analysis server**
  that has the EPU output folder mounted (over NFS). It notices when a session has finished — specifically,
  when enough movies have appeared (by default at least ~50) and then **no new movies arrive for several
  minutes** (the acquisition has settled). This is an admin/IT setup, done once. Ask your admin whether the
  EPU session watcher is running.
- When a session completes, it appears under **New data events** mapped to the CryoSPARC SPA workflow — or you
  can start the analysis yourself by pointing BioMate at the session folder.

---

## 5. Step by step — run the reconstruction

1. **Start from the New-data event** (if the watcher is set up): find the completed session under **New data
   events** and press **Launch**. BioMate opens a chat with a pre-filled draft to run `cryosparc_standard_spa`
   on that session's `movies_path`. *Or* ask in plain English: *"Run single-particle reconstruction on my
   cryo-EM session in folder X."*
2. **Check the auto-filled settings.** BioMate pre-fills `movies_path`, `voltage`, and `pixel_size` from the
   EPU metadata. Confirm the pixel size and voltage match your microscope — these two values are critical; a
   wrong pixel size makes every downstream size and resolution wrong.
3. **Confirm and run.** The pipeline runs on cloud GPU computers. Single-particle reconstruction is
   compute-heavy and can take **hours**, depending on how many particles you have.
4. **Watch the phases.** Each stage (motion correction → CTF → picking → 2-D → refinement → post-processing)
   moves from *pending* → *running* → *completed* in real time.
5. **Read the report** when it finishes (see §6).

> **Nothing runs until you confirm.** The Launch action only opens a reviewed draft — you press Send.

---

## 6. Reading the result — the map and the numbers

Open the **After run** report (the same two-tab report as any BioMate workflow — see Tutorial 3). For
single-particle cryo-EM, look for:

- **The 3-D density map** — usually an `.mrc` volume file. This is the headline output: the reconstructed
  shape of your molecule. You download it and open it in a structure viewer (e.g. ChimeraX) to see and
  interpret it.
- **The resolution estimate** — reported at **FSC = 0.143**, in ångströms. This is the single number that says
  how much detail the map holds. Lower = better: roughly, below 3 Å you can often see individual side chains;
  4–6 Å shows secondary structure (helices as tubes); worse than ~8 Å shows only an overall blob. Read this
  number together with the FSC curve, not alone.
- **2-D class averages** — picture-like images of your particle seen from different angles, produced mid-run.
  Clean, detailed class averages are a good sign the particles are real and well-aligned; smeary ones warn of
  junk or heterogeneity.
- **The Results tab** — a plain-language account built **from the real output files**. If BioMate cannot read
  an output, it withholds that finding rather than inventing a number (the honesty behaviour from Tutorial 3).
- **The Reproducibility record** — every parameter, tool version, and output file, downloadable as one file
  for a paper's methods section or a deposition record.

<!-- CAPTURE route=/ ; state=After-run report for a cryosparc_standard_spa run: Outputs section listing the .mrc map + 2D class averages + FSC/resolution report ; focus=cryoem-outputs ; note=show the reconstruction outputs grouped by phase (map volume, class averages, resolution report) -->
*(Figure to add: the After-run Outputs section for a reconstruction — the 3-D map volume, 2-D class averages, and
the resolution/FSC report, grouped by phase.)*

---

## 7. Honest limits — what to expect

- **This workflow has real run evidence.** Of all the instruments in this series, cryo-EM single-particle
  reconstruction is the one BioMate has actually run end-to-end on real microscope data (the team's cryo-EM
  test data on S3), with a documented E2E pipeline. So the map-from-movies path here is **validated**, not just
  wired up. (That said, "validated" means the pipeline runs and produces a map on real data — the scientific
  quality of *your* map still depends on *your* sample and data.)
- **The map is only as good as the data.** Thin, well-distributed ice and enough good particles drive
  resolution. A workflow cannot rescue a badly behaved sample; a low-resolution map usually means the data, not
  the pipeline.
- **Pixel size and voltage must be correct.** BioMate reads them from EPU metadata, but EPU versions store
  units differently (metres vs ångströms). Sanity-check the pixel size the panel shows before running.
- **Tomography is a different job.** This workflow is for *single-particle* SPA. Cryo-electron *tomography*
  (tilt series of whole cells) is a separate pipeline — don't point this one at tomography data.
- **It is compute-heavy.** Expect hours and real GPU cost. Confirm the settings carefully before launching, so
  you don't pay for a run with the wrong pixel size.

---

## 8. Where to go next

| You want to… | Where |
|---|---|
| Register the microscope / check connectivity | **Tutorial 6 — Connecting instruments** |
| Understand the two-tab report in depth | **Tutorial 3 — Running a workflow and reading the report** |
| View and interpret output files | **Tutorial 5 — Viewing your results** |
| Act on a New-data event | **Tutorial 6 §6** |

The habit for this instrument: **let the watcher notice the finished session → Launch the reviewed draft →
confirm pixel size/voltage → run → read the map at FSC = 0.143.**

---

## 9. Key terms

| Term | What it means — and why you care |
|---|---|
| **Single-particle analysis (SPA)** | The pipeline that combines tens of thousands of noisy particle views into one 3-D map. |
| **Movie frames (.mrc/.tif/.eer)** | The raw files the microscope records — short clips of frozen particles. Thousands per session. |
| **Pixel size (ångströms)** | How much real distance one image pixel covers — the microscope's ruler. A wrong value makes every size/resolution wrong. |
| **Motion correction** | Removes blur from beam-induced movement during each movie. |
| **CTF estimation** | Measures and corrects the microscope's optical distortion so images can be combined correctly. |
| **2-D class averages** | Picture-like averages of the particle from different angles; clean ones mean good data. |
| **3-D density map** | The headline output — the reconstructed shape you fit a protein model into. |
| **Resolution at FSC = 0.143** | The gold-standard detail measure, in ångströms. Lower = more detail (3 Å excellent, 8 Å low). |

---

> **Honesty verdict for this instrument:** *Validated on real data.* The connector maps an EPU session to
> `cryosparc_standard_spa`, which exists in the catalog (a ~33-step CryoSPARC SPA pipeline) and has documented
> end-to-end run evidence on real cryo-EM data. This is the strongest-grounded instrument tutorial in the set.

_Companion references: `docs/user-manual/tutorials/T6-connecting-instruments.md`;
`docs/user-manual/tutorials/T3-running-a-workflow-and-reading-the-report.md`._
