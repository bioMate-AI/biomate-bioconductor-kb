# RNA-seq · Differential expression — which genes change between your groups — narration (EN)

## Step 1 — Title · which genes change between my conditions?

You ran the experiment — treated against control, disease against healthy — and now you have the real question: which genes changed? BioMate answers it directly. Which genes went up, which went down, and which ones you can actually trust. There's no code to write and no software to install; you describe the comparison in plain English, and you get back a results table and a volcano plot you can drop straight into a figure. We'll follow a real public example the whole way through — GSE52778, airway smooth-muscle cells treated with dexamethasone versus untreated controls — the kind of two-group comparison you run all the time.

---

## Step 2 — The problem this solves

A single RNA-seq run measures tens of thousands of genes across every sample. Trying to find what changed by eye, in a spreadsheet, doesn't scale — and it quietly invites mistakes. It's easy to compare the wrong groups, or to forget that when you test twenty thousand genes at once, some will look significant purely by chance. And even when you get it right, a one-off script leaves nothing behind: when a reviewer asks how you produced the list, you've no trail to point to. What you actually need is the right statistics, run correctly, with a record you can defend — and no code to write.

---

## Step 3 — The ideas you need first

Four plain ideas make the whole result readable; you don't need the maths. First, the count matrix: a table with one row per gene and one column per sample, each cell counting how many reads landed on that gene — your measured expression. Second, the groups, or design: the labels that say which samples are treated and which are control, which is simply the comparison you want tested. Third, differential expression itself: for every gene, how much it changed between the groups — the log2 fold-change — and whether that change is real. And fourth, multiple-testing correction: test twenty thousand genes and some look significant by luck, so the adjusted p-value corrects for that. Remember two things — a fold-change of plus one means doubled, minus one means halved; and a smaller adjusted p-value is stronger, with 0.05 the usual bar.

---

## Step 4 — Step 1 · what you bring

You start from whatever you already have; BioMate meets your data where it is. If you already hold a gene-count table — from a core facility, a collaborator, or a public dataset like GSE52778 — you bring it straight in, and the analysis starts right there. If all you have is raw sequencing reads, that's fine too: the nf-core/rnaseq pipeline turns them into a clean count matrix first, handling quality control, alignment, and quantification, chained correctly. Either way, the one thing you always provide is your group labels — which samples are treated and which are control. That single piece of context is what defines the comparison.

---

## Step 5 — Step 2 · how a run works

There's no pipeline to assemble and nothing to install. You state the goal in plain English — "differential expression, dexamethasone versus control" — and BioMate picks the validated analysis and shows you the set-up. You review it, and nothing is spent until you confirm: you always see the chosen method and its settings before any compute runs. When you confirm, the work runs on cloud computers while you carry on with something else. The statistics themselves use DESeq2 — the established, published method for differential expression — so your result rests on a standard that other scientists already trust, not on something improvised for the occasion.

---

## Step 6 — Step 3 · the results table

The run returns a results table, and this is your answer in its most direct form: one row per gene, each with its log2 fold-change and its adjusted p-value, side by side. The fold-change tells you the direction and the size of the change; the adjusted p-value tells you how confident to be. Because it's sortable, you can order by fold-change to see the biggest movers, or by adjusted p-value to bring your surest hits to the top. The sign carries the biology — a positive fold-change means the gene is up in the treated group, a negative one means it's down. And every number here comes straight from the run, nothing typed in by hand.

---

## Step 7 — Step 4 · the volcano plot

The volcano plot puts the whole result into a single picture. Left to right is the fold-change — far to the right means strongly up in the treated group, far to the left means strongly down. Bottom to top is confidence — the higher a gene sits, the smaller its adjusted p-value, and the less likely the result is to be luck. So the genes that matter are pushed into the top corners: a big change and high confidence at once, up-regulated on the right, down-regulated on the left. It's a figure-ready image, drawn from the very same results — download it and it's ready for your paper.

---

## Step 8 — Step 5 · reading it with confidence

Read the two numbers together, and the result is hard to misread. The fold-change tells you how much a gene moved — plus one is doubled, minus one is halved — and a large change is biologically interesting, but only if it's real. The adjusted p-value tells you how sure to be; it's already corrected for testing every gene at once, and below 0.05 is the usual bar, with smaller meaning stronger evidence. Put them together: a big change and a small adjusted p-value is a solid hit, while a big change with a weak p-value may just be noise. And one honest point — a volcano with almost nothing in its top corners can be a genuine "no change," or a study with too few replicates to detect one. The statistics won't invent a hit that isn't there.

---

## Step 9 — Step 6 · from result to a result you can defend

The table and the plot are the answer; what makes it defensible is everything kept alongside them. The Outputs give you every file — the full results table, the volcano plot, the count matrix, and a run-quality report — to download one by one or all together. The reproducibility record is the audit trail: the exact comparison you ran, the parameters, the tool versions, and the outputs with verifiable checksums — the whole run, pinned down. That's what you attach to a manuscript or a submission, so that when someone asks "how did you get this gene list?", the answer is complete and anyone can reproduce it.

---

## Step 10 — Closing · the value at a glance

It all comes back to one sentence: which genes change between my conditions, and which can I trust? You bring your counts and your group labels; BioMate runs the validated DESeq2 analysis on cloud compute and hands back a ranked table, a volcano plot, and a complete record — all without a line of code. Bring a count matrix or raw reads and say which group is which; describe the comparison and confirm; read the table and the plot with change and confidence side by side; then download the outputs and the reproducibility record. A wet-lab biologist's question, answered the same day — the right statistics, figures ready for publication, and a record you can defend. Differential expression is a measurement, not a conclusion, so confirm your key genes at the bench.

---
