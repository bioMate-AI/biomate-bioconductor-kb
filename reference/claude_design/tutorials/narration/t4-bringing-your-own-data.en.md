# T4 Bringing your own data — narration (EN)

## Step 1 — Title · your data is the centre

Most real work starts the same way: I have these files — now what? When you bring a file into BioMate, it doesn't just store a copy. It becomes an auditable dataset object — a single named thing that carries its type, a quality check, and its provenance, the record of where it came from and what has used it. Every later step — an analysis, a result, a report — points back to that same object, so you can always answer "what exactly did this come from?" — defensible data, with no manual tracking. We'll follow one example assay file the whole way: into the Data hub, opened as an object, checked for quality, and then used in a question.

---

## Step 2 — The problem · where mistakes creep in

An analysis is only as good as the data going into it. Done by hand, getting data ready means tracking which file is which, checking it is readable and not obviously broken, and remembering later where a result came from. That manual tracking is exactly where mistakes creep in: the wrong file is an easy and expensive error; an unreadable or badly skewed file wastes time and money if you only discover it mid-analysis; and months later you still have to say where a number came from. BioMate's answer is to treat your data as the centre everything connects to — so identity, readiness, and provenance are kept for you, not in your head.

---

## Step 3 — The Data hub · project-scoped

The place your data lives is the Data hub — in the sidebar under Data. It has two panes: a file tree on the left, your files grouped, and a detail pane on the right, the one file you clicked opened as an object. Your uploads sit under an inputs folder; a run's results appear in their own per-run folder, labelled with the workflow and date, so you can tell different runs apart. One thing to know up front: data is project-scoped. A file belongs to a project and is not visible in another, so each team's data stays separate. If you can't find a file, check you're in the right project.

---

## Step 4 — The dataset object · a file is not just a file

This is the core idea. When you click a file, it opens as a dataset object, with everything BioMate knows about it in one place. Preview shows the first rows of the real data as a table, without downloading — the fastest way to catch a wrong file or a bad column separator. Quality is a one-word verdict. Lineage is what produced it; for an uploaded file it plainly shows that it came from an upload, with no upstream workflow. Consumers are the analyses that have read it, so you always know what depends on it. Versions is a change log, and Origin is the plain facts of where it came from. Because the file is an object, a later result can point back to exactly the input it was computed from.

---

## Step 5 — Quality · four verdicts, and grey is not bad

Is this file clean enough to run on? BioMate runs a quick profiler on readable files and gives a one-word verdict. Good, in green, means readable and nothing obviously wrong — proceed. Watch, in amber, means usable but read the notes first. Blocked, in red, means BioMate could not read the file properly — fix it before routing it to an analysis. And grey means not profiled: the profiler doesn't read this file type, so it makes no claim. Grey means "no check was run", never "bad". The profiler reads delimited tables, VCF, and FASTQ; other file types are accepted as well and show grey. One more term: effective N is the usable sample size, which can be smaller than the raw row count when data is correlated or imbalanced. And remember this is an ingest check — separate from the quality gates that run during an analysis.

---

## Step 6 — Provenance and versions · a record you can stand behind

In science you must be able to say how a number was produced. Provenance is the record of where a dataset came from and what has read it, and BioMate keeps it for you, so a result is defensible in a paper or a review. Lineage shows which run produced a file and which analyses have read it. And Versions is a clear log: adding a version records that the data changed and why, so you can see how a dataset evolved. The payoff is that the whole chain, from your upload to the final result, can be read and explained.

---

## Step 7 — Live · the Data hub

Here is the real Data hub. You pick the project the data belongs to, and its data opens in two panes. The file tree on the left lists your uploads under the inputs folder and each run's outputs in their own folder, with every row carrying a small quality dot that appears once BioMate has read the file. The pane on the right is where a file opens as an object. This is the two-pane layout, captured from the live product — project-scoped, with every file a dataset object.

---

## Step 8 — Live · the dataset object

Opening a file shows its header — the name, the content type, the size, and once the profiler finishes, a quality pill and a version count, so you can see its status at a glance. Below the header are the tabs: Preview, Quality, Lineage, Consumers, Versions, and Origin. The habit to build is simple — read Preview before you run, because it's the fastest way to catch a wrong file, a wrong separator, or a header row that isn't really a header. One file, opened as a first-class object, with every tab a different view of it.

---

## Step 9 — Live · the Quality tab

The Quality tab shows the detail behind the pill. For a table, it shows how many rows and columns, the effective N, class balance, and any notes. For sequencing reads, it shows reads, read length, and average base quality — the Phred score — instead, with a note like "below twenty, consider trimming". The important thing is that the verdict comes from BioMate actually reading your data, not from a guess. And again, this is the ingest check — the file as it arrives — separate from the in-run QC gates covered in Tutorial 3.

---

## Step 10 — Live · two ways in, then an analysis

You don't always open the Data hub first. In the chat composer you have two ways to bring data into a question. The paperclip attaches a file from your computer — a quick upload for a one-off. The database icon points at data BioMate already holds, so you don't re-upload a file that's already in your project. Both end up as the same kind of dataset object. From there you describe the analysis you want, BioMate shows the settings with your file filled in, and it runs only after you confirm — exactly the flow in Tutorial 3. The result files come back as new dataset objects, each with its own lineage pointing back to the run that produced it.

---

## Step 11 — Closing · the habit

So the habit is: bring the file in once, check its quality, reference it in a plain-English question, confirm, and get results that trace back to it. Open Data and pick the project that owns the file; drag it in, or use the composer's paperclip or database icon; read the quality dot and the Preview before you run; then reference it in a question and let the results come back as traceable objects. Every file becomes an auditable dataset object; ingest quality is measured for tables, VCF, and FASTQ, with grey meaning "not profiled"; provenance is kept so a result can be explained; versions give a clear change log; and each project sees only its own data. Your data is the centre everything connects to.
