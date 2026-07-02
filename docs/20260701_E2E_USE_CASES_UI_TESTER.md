# BioMate — Manual UI Test Cases
**Date:** 2026-07-01  
**Audience:** QA tester; no coding required  
**App URL:** http://localhost:5000  
**Login:** lifeifei163361@163.com / WpmFixture!2026

---

## How to use this document

Each test case is a numbered sequence of steps. For each step:

- **Do** → what you click or type
- **Expect** → what you should see on screen
- **Screenshot** → take a screenshot and name it as shown

A test **passes** when every "Expect" is met.  
A test **fails** when any "Expect" is not met — note the step number and what you actually saw instead.

**Before starting any test:** log in with the credentials above. You can reuse the same browser session across all tests — you do not need to log out between them.

---

## Test 1 — Research question gets a text answer, no workflow

**What this checks:** Asking a plain science question gives a text reply only. No pipeline or workflow card should appear.

| # | Do | Expect |
|---|-----|--------|
| 1 | Click **New Chat** in the left sidebar | A blank chat screen opens |
| 2 | Type in the message box: `What does a p-value of 0.05 mean in RNA-seq differential expression?` and press Enter | The message appears in the chat. A typing indicator (animated dots or "Thinking…") appears below it |
| 3 | Wait up to 90 seconds for the reply | A text reply appears explaining p-values. The text should be several sentences long and mention statistics or significance |
| 4 | Look at the area below the AI reply | **No** blue workflow card or panel appears. Only the text answer |
| 5 | Look at the right side of the screen | The right panel is **empty or closed**. No workflow panel slides in |

**Screenshot:** `T1_response.png` — capture the full chat showing question + text answer

**Pass if:** Text reply appears, no workflow card, no right panel.

---

## Test 2 — AI response renders formatted text correctly

**What this checks:** The AI can produce bold text, headers, bullet lists, and code snippets, and they all render visually.

| # | Do | Expect |
|---|-----|--------|
| 1 | Click **New Chat** | Blank chat screen |
| 2 | Type: `Explain the steps of DESeq2 differential expression analysis. Use headers and a code example.` and press Enter | Message sent; typing indicator appears |
| 3 | Wait up to 90 seconds | A reply appears with visible formatting: at least one bold word, at least one bullet point or numbered list, and a grey code box |
| 4 | Look at the bold text | It should appear **visually bold** (darker, heavier font), not as raw `**word**` with asterisks |
| 5 | Look at the code box | It should have a grey or dark background with monospace font. It should not be plain text |

**Screenshot:** `T2_formatted_response.png` — capture the reply showing bold, list, and code box

**Pass if:** Bold, list, and code block all render as styled elements.

---

## Test 3 — Action buttons appear after an AI reply

**What this checks:** After receiving any AI text reply, three buttons appear: Copy, Regenerate, and Save.

| # | Do | Expect |
|---|-----|--------|
| 1 | In the same session as Test 2 (or start a new chat and send any question), look at the area just below the AI reply | Three small buttons are visible: a **Copy** icon, a **Regenerate** icon, and a **Save** icon |
| 2 | Hover over the Copy button | A tooltip appears (e.g., "Copy") |
| 3 | Click the Copy button | The button briefly changes appearance (checkmark or flash). No error dialog appears |
| 4 | Look for a Regenerate button | It is visible near the Copy button |

**Screenshot:** `T3_action_buttons.png` — capture the bottom of the AI reply showing the three buttons

**Pass if:** All three buttons visible; Copy click produces no error.

---

## Test 4 — Follow-up question in same chat uses context

**What this checks:** The AI remembers what was said earlier in the conversation.

| # | Do | Expect |
|---|-----|--------|
| 1 | Click **New Chat** | Blank chat |
| 2 | Type: `What is DESeq2 used for in bioinformatics?` and press Enter | AI replies explaining DESeq2 (RNA-seq differential expression tool) |
| 3 | Wait for the reply to finish | Reply complete |
| 4 | In the same chat, type: `What statistical test does it use internally?` and press Enter | AI replies mentioning the **Wald test** or **likelihood ratio test** — it knows you're still talking about DESeq2 without you repeating the name |
| 5 | Check that there are now **two** AI replies visible in the chat | Both the first and second answers are visible, stacked below each other |

**Screenshot:** `T4_multiturn.png` — capture the full chat showing both turns

**Pass if:** Second reply mentions DESeq2's statistical method without needing to be told what tool you're asking about.

---

## Test 5 — Pasting a count matrix triggers a workflow suggestion

**What this checks:** When you paste a gene expression table into the chat, BioMate recognises it as data and suggests a DESeq2 or differential-expression workflow instead of just answering with text.

| # | Do | Expect |
|---|-----|--------|
| 1 | Click **New Chat** | Blank chat |
| 2 | Copy and paste the following message exactly (including the table), then press Enter: | |

```
Run DESeq2 differential expression on this count matrix — 3 ctrl replicates vs 3 treated replicates:
gene,ctrl1,ctrl2,ctrl3,treat1,treat2,treat3
GENE1,100,120,110,200,210,195
GENE2,50,55,48,52,49,51
GENE3,30,28,32,90,88,95
GENE4,200,210,195,205,198,202
GENE5,15,18,16,45,50,48
```

| # | Do | Expect |
|---|-----|--------|
| 3 | Wait up to 2 minutes | AI reply appears. **A blue workflow card appears below the text**, showing a workflow name containing "differentialabundance" or "DESeq2" |
| 4 | Look at the right side of the screen | A **workflow panel** slides in on the right. It shows the workflow name, parameter fields, and a **Run** button at the bottom |
| 5 | Look at the workflow card in the chat | A small badge or chip near the card says **"In panel"** |

**Screenshot T5a:** `T5_workflow_card.png` — capture the chat showing the AI reply + blue workflow card  
**Screenshot T5b:** `T5_panel_open.png` — capture the right panel open with Run button visible

**Pass if:** Workflow card appears in chat AND right panel opens automatically with a Run button.

---

## Test 6 — Session history saves and reloads

**What this checks:** If you navigate away and come back to a previous chat, the messages are still there.

| # | Do | Expect |
|---|-----|--------|
| 1 | In a new chat, type: `Explain FASTQ format briefly.` and press Enter | AI replies |
| 2 | Wait for the reply to finish | Reply visible |
| 3 | Look at the left sidebar | Your new chat session appears in the history list, usually near the top, with a snippet of your message |
| 4 | Click **New Chat** to start a different session | Blank chat opens. The previous session disappears from view but should still be in the sidebar list |
| 5 | In the sidebar, find and click the earlier session (with "FASTQ") | The chat reloads showing your original question and the AI's reply, exactly as before |

**Screenshot:** `T6_session_reload.png` — capture the reloaded chat session with original messages visible

**Pass if:** Both the user message and AI reply are visible after navigating back.

---

## Test 7 — Empty message is rejected

**What this checks:** Pressing Enter with nothing typed does not send a request or show a new AI reply.

| # | Do | Expect |
|---|-----|--------|
| 1 | Open any chat session | Chat visible |
| 2 | Click the message input box to make sure it's focused | Cursor blinks in the box |
| 3 | Without typing anything, press Enter | **Nothing happens** — no typing indicator, no new message in the chat |
| 4 | Try clicking the Send button (if visible) with an empty box | Same — nothing is sent |

**Pass if:** No new message or typing indicator appears after sending empty input.

---

## Test 8 — Single-cell RNA data triggers a cell-clustering workflow

**What this checks:** Pasting a cell × gene count matrix (single-cell format) routes to a single-cell analysis workflow — NOT a bulk RNA-seq pipeline.

| # | Do | Expect |
|---|-----|--------|
| 1 | Click **New Chat** | Blank chat |
| 2 | Paste the following message and press Enter: | |

```
Cluster these single-cell RNA-seq counts and generate a UMAP:
barcode,CD3D,CD4,CD8A,MS4A1,CD19,GNLY
AAACCTGAGAAGGCCT,45,32,0,0,0,1
AAACCTGAGACAGACC,0,0,38,0,0,0
AAACCTGAGACTTTCG,0,0,0,87,91,0
AAACCTGAGATCACGG,12,8,0,0,0,0
AAACCTGAGCGATAGC,0,0,0,0,0,112
AAACCTGAGCGCTTAT,22,18,0,0,0,0
AAACCTGAGGCTAGCA,0,0,0,74,82,0
AAACCTGAGTCACGAA,1,0,44,0,0,2
```

| # | Do | Expect |
|---|-----|--------|
| 3 | Wait up to 2 minutes | AI reply appears with a workflow card |
| 4 | Read the workflow name on the card | It should say something like **scrnaseq**, **Seurat**, **scanpy**, or **single-cell** — NOT "differentialabundance" or "bulk" |
| 5 | Read the AI text reply | It mentions clustering, cell types, UMAP, or dimensionality reduction |

**Screenshot:** `T8_scrna_card.png` — capture the workflow card showing a single-cell workflow name

**Pass if:** Workflow card names a single-cell pipeline; text mentions clustering or UMAP.

---

## Test 9 — Variant data triggers a variant analysis workflow

**What this checks:** Pasting VCF-style variant rows routes to a variant annotation or GWAS workflow.

> ⚠️ **Copy warning:** The data below uses TAB characters between columns (not spaces). Copy it from this document using the copy button or select carefully. If tabs are lost, the columns will run together and the system may not recognise the format.

| # | Do | Expect |
|---|-----|--------|
| 1 | Click **New Chat** | Blank chat |
| 2 | Paste the following and press Enter (each column is separated by a TAB): | |

```
Annotate and filter these germline variants for a population study:
#CHROM	POS	ID	REF	ALT	QUAL	AF
1	752566	rs3094315	G	A	60	0.42
1	776546	rs12124819	A	G	55	0.31
1	798959	rs11240777	G	A	71	0.18
1	800007	rs6681049	C	T	80	0.09
1	838555	rs4970383	C	T	63	0.24
1	846808	rs4475691	C	T	58	0.37
```

| # | Do | Expect |
|---|-----|--------|
| 3 | Wait up to 2 minutes | AI reply appears with a workflow card |
| 4 | Read the workflow name | It should include words like **sarek**, **gatk**, **variant**, **plink**, **annotate**, or **GWAS** |
| 5 | Check the AI reply text | It should NOT ask you to provide the variant data again (since you already pasted it) |
| 6 | Open the right panel (if not already open) | Parameter fields may show a genome build field (e.g., GRCh38, hg38) |

**Screenshot:** `T9_variant_card.png` — capture the workflow card with variant pipeline name

**Pass if:** Variant-related workflow name; AI does not ask for data that was already provided.

---

## Test 10 — SMILES drug candidates trigger ADMET screen

**What this checks:** Pasting SMILES strings routes to a drug-property / ADMET screening workflow.

| # | Do | Expect |
|---|-----|--------|
| 1 | Click **New Chat** | Blank chat |
| 2 | Paste the following and press Enter: | |

```
Run full ADMET profiling on these five drug candidates and flag any hERG or CYP3A4 liabilities:
CC(=O)Oc1ccccc1C(=O)O
CN1CCC[C@H]1c2cccnc2
CC12CCC3C(C1CCC2O)CCC4=CC(=O)CCC34C
c1ccc2c(c1)cc1ccccc1n2
COc1cc2c(cc1OC)C(=O)c1ccccc1C2=O
```

| # | Do | Expect |
|---|-----|--------|
| 3 | Wait up to 2 minutes | AI reply with a workflow card appears |
| 4 | Read the workflow name | Should include **admet**, **drug**, **pkpd**, **toxicity**, or **property** |
| 5 | Open the right panel | One of the parameter fields should show one of the pasted SMILES strings — you should not have to enter it again |
| 6 | Read the AI text | It should mention ADMET, hERG, CYP, absorption, or toxicity |

**Screenshot T10a:** `T10_admet_card.png` — the workflow card  
**Screenshot T10b:** `T10_panel_smiles.png` — the right panel showing a SMILES value in a parameter field

**Pass if:** ADMET/drug workflow name; SMILES visible in panel without re-entry.

---

## Test 11 — Literature search returns cited answer (no workflow)

**What this checks:** A question asking for a research summary returns a detailed text answer with citation numbers like `[1]`, `[2]`. No workflow card appears.

| # | Do | Expect |
|---|-----|--------|
| 1 | Click **New Chat** | Blank chat |
| 2 | Paste the following and press Enter: | |

```
Summarise the current evidence on KRAS G12C inhibitors in non-small cell 
lung cancer: mechanism of action, clinical trial outcomes, and resistance 
mechanisms. Cite at least 3 primary papers.
```

| # | Do | Expect |
|---|-----|--------|
| 3 | Wait up to 2 minutes | A long text reply appears (several paragraphs) |
| 4 | Look for citation markers in the text | Numbers like **[1]**, **[2]**, **[3]** appear in the text, or a references section appears at the bottom |
| 5 | Count the citations | At least 2 citation markers are visible |
| 6 | Look for a workflow card below the reply | **No** workflow card. This is a text-only answer |
| 7 | Check the right panel | It should be **empty or closed** |

**Screenshot:** `T11_literature_citations.png` — capture the response showing paragraphs + citation markers

**Pass if:** Long reply (multiple paragraphs), at least 2 citation markers visible, no workflow card.

---

## Test 12 — Research follow-up in same chat uses prior context

**What this checks:** Two-turn conversation about a protocol. The second question references the first answer without repeating context.

| # | Do | Expect |
|---|-----|--------|
| 1 | Click **New Chat** | Blank chat |
| 2 | Type and send: `What is the recommended protocol for preparing a stranded total RNA-seq library from FFPE tissue samples?` | AI replies with a protocol description |
| 3 | Wait for reply to finish | Complete reply visible |
| 4 | In the same chat, type and send: `In step 3 of that protocol, what is the purpose of the rRNA depletion step and what reagents are typically used?` | AI replies about rRNA depletion |
| 5 | Read the second reply | It should mention **rRNA**, **ribosomal RNA**, and specific reagents like **RiboZero**, **RNase H**, **RiboCop**, or **probes** — without you repeating what tool or protocol you are asking about |
| 6 | Look for a workflow card in either reply | **No** workflow cards in either turn — both are text-only |

**Screenshot:** `T12_protocol_multiturn.png` — full chat view showing both questions and both answers

**Pass if:** Second reply mentions rRNA depletion reagents; no workflow cards; both replies text-only.

---

## Test 13 — Workflow runs from start to finish (full lifecycle)

**What this checks:** After a workflow is suggested, clicking Run takes it through the running state and finishes.

**Setup:** You need the workflow panel open with a **Run** button visible.

- **If you completed Test 5** in the same browser session, the panel may still be open — proceed to step 1.
- **If the panel is not open**, start a new chat, paste the message below, and wait up to 2 minutes for the workflow panel to appear:

```
Run DESeq2 differential expression on this count matrix — 3 ctrl replicates vs 3 treated replicates:
gene,ctrl1,ctrl2,ctrl3,treat1,treat2,treat3
GENE1,100,120,110,200,210,195
GENE2,50,55,48,52,49,51
GENE3,30,28,32,90,88,95
GENE4,200,210,195,205,198,202
GENE5,15,18,16,45,50,48
```

| # | Do | Expect |
|---|-----|--------|
| 1 | Look at the right panel | Workflow name, parameter fields, and a **Run** button are visible at the bottom. The panel header shows no status badge yet (or shows "Idle") |
| 2 | Take a screenshot now | `T13_00_panel_idle.png` |
| 3 | Click the **Run** button | The button changes to **"Running…"** and becomes greyed-out. A spinner appears |
| 4 | Wait up to 30 seconds | The **Phases** tab in the panel is now selected automatically. You can see a list of steps/phases. At least one shows a spinning blue indicator |
| 5 | Take a screenshot | `T13_01_panel_running.png` — show the phases list with at least one step in "running" state |
| 6 | Look at the panel header area | A status badge or indicator shows **Running** |
| 7 | Look at the bottom action bar of the panel | **Pause** and **Stop** buttons are visible |
| 8 | Wait up to 10 minutes for the run to finish | All phases turn green (completed) or one turns red (failed) |
| 9 | Take a screenshot | `T13_02_panel_terminal.png` — show the final state |
| 10 | If completed: click the **After Run** tab in the panel | You see a completion banner, a metrics strip (Duration, Started, Completed), and a **Download all outputs** button |
| 11 | Take a screenshot | `T13_03_after_run_tab.png` — show the After Run tab contents |

**Pass if:** Button changes to "Running…" after click; at least one step observed in spinning state; panel reaches a terminal state (completed or failed); after-run tab appears on completion.

---

## Test 14 — Failed run shows error and Restart button

**What this checks:** If a workflow fails, the panel shows the failure clearly and offers a Restart option.

**Note:** To reliably cause a failure, the tester can edit a required parameter (like the input file path) to a value that does not exist before clicking Run.

| # | Do | Expect |
|---|-----|--------|
| 0 | Check the panel state. If it shows **"Completed"** or **"Failed"** (from Test 13), click the **Run again** or **Restart** button at the bottom of the panel and wait until the **Run** button is active again | Panel returns to idle state with an active **Run** button |
| 1 | With the workflow panel open (from Test 5 or Test 13 setup), click the **Settings** toggle (gear/chevron icon inside the panel) to expand the parameter editor | Parameter fields appear |
| 2 | Find a field labelled **Input**, **Samplesheet**, or **Input paths** | A text field with a file path or S3 URL |
| 3 | Clear that field and type: `s3://nonexistent-bucket/fake.csv` | The field now shows the fake path |
| 4 | Click **Run** | Run begins. Step indicator starts |
| 5 | Wait up to 3 minutes | One of the phase cards turns **red** (failed). The overall status badge changes to **Failed** or shows a red indicator |
| 6 | Take a screenshot | `T14_01_panel_failed.png` — red phase card and failed badge |
| 7 | Look for an error or triage section inside the panel | A red alert box appears explaining the failure. A **"Fix in chat"** or **"Get help"** button may appear |
| 8 | Look at the top-right of the panel header | A **Restart** button (circular arrow icon) is now visible |
| 9 | Click the **Restart** button | The panel resets: all phase cards return to grey/pending, status badge clears, and the **Run** button is enabled again |
| 10 | Take a screenshot | `T14_02_after_restart.png` — clean idle state |

**Pass if:** At least one red phase card visible on failure; Restart button present; clicking Restart resets the panel to idle.

---

## Test 15 — QC gate fires and shows measured vs threshold values

**What this checks:** After an ADMET run, if a compound exceeds the hERG toxicity threshold, the panel shows a yellow/red warning with the measured value and the threshold value side by side.

**Note:** This test requires a completed ADMET run that triggers a QC gate. Use the following SMILES (astemizole, a known hERG blocker) in the chat first:

```
Run ADMET profiling on this compound:
O=C(Nc1ccc(N2CCC(Cc3ccc(OC)cc3)CC2)cc1)c1ccc(F)cc1
```

After pasting that message and getting a workflow card with the right panel open:

**Before clicking Run**, click the **Settings** tab (or gear icon at the top of the panel) and scroll down to the **QC Settings** section. Find the row labelled **hERG** or **hERG IC50**. If the value is blank or greater than 10, type **10** and press Enter to save. This ensures the gate fires because astemizole (the compound above) typically blocks hERG above that level.

Once the threshold is confirmed, click the **Run** button at the bottom of the panel and wait up to 10 minutes. After the run finishes:

| # | Do | Expect |
|---|-----|--------|
| 1 | After the run finishes, click the **Settings** tab in the panel | Panel switches back to the settings view |
| 2 | Look for a yellow or orange alert box near the top of the settings area | A warning box appears, mentioning **hERG** or a safety metric |
| 3 | Look inside the alert | Two numbers side by side: one in **red** (the measured value) and one in **green** (the allowed threshold). The red number is larger |
| 4 | Take a screenshot | `T15_01_qc_gate.png` — show the alert with both values |
| 5 | Look for buttons inside the alert | Three buttons should appear: **Apply fixes**, **Keep current**, and **Cancel run** |
| 6 | Look for an autoloop toggle somewhere in the phase section | A toggle labelled "Auto-loop" or "Auto-retry" is visible |

**Pass if:** Yellow/red alert visible; two numeric values (one red, one green); three action buttons present.

---

## Test 16 — Research tangent between workflow turns does not lose workflow

**What this checks:** If you ask a casual research question while a workflow card is already in the chat, the workflow card stays and the right panel remains accessible. No second workflow card appears.

**Setup:** You need a workflow card already in the chat before starting. If you completed Test 5 in this browser session, continue in that same chat window — do not start a new chat. If not, start a new chat, paste the message below, and wait for the panel to open:

```
Run DESeq2 differential expression on this count matrix — 3 ctrl replicates vs 3 treated replicates:
gene,ctrl1,ctrl2,ctrl3,treat1,treat2,treat3
GENE1,100,120,110,200,210,195
GENE2,50,55,48,52,49,51
GENE3,30,28,32,90,88,95
GENE4,200,210,195,205,198,202
GENE5,15,18,16,45,50,48
```

| # | Do | Expect |
|---|-----|--------|
| 1 | Confirm that one workflow card is visible in the chat and the right panel is open | One workflow card in chat; panel shows workflow name and Run button |
| 2 | Without clicking New Chat, type in the same chat: `What statistical test does DESeq2 use internally?` and press Enter | A text-only reply appears. It answers the question about Wald test or likelihood ratio test |
| 3 | Count the workflow cards in the chat | Still **only 1** workflow card (from the first message). No second card appeared for this question |
| 4 | Look at the small chip embedded in the first message | It still says **"In panel"** or shows the workflow chip — the panel connection is still alive |
| 5 | Type: `OK, I'm ready to run the DESeq2 analysis now.` and press Enter | The AI acknowledges and the Run button in the right panel is still active |

**Screenshot:** `T16_tangent_one_card.png` — full chat showing 2 user messages, 2 AI replies, but only 1 workflow card

**Pass if:** Exactly 1 workflow card after 3 turns; second reply is text-only; panel remains accessible.

---

## Test 17 — Changing a parameter is reflected in the panel

**What this checks:** When you edit a parameter in the panel editor and apply it, the change is visible in the panel without re-sending the chat message.

| # | Do | Expect |
|---|-----|--------|
| 1 | With the workflow panel open (from Test 5 or similar), click the **Settings** toggle or gear icon in the panel | Parameter fields expand |
| 2 | Scan the parameter fields for any **text input** or **dropdown** that already shows a value (avoid any field marked as required with a red border or asterisk) | At least one field with a current value is visible |
| 3 | Click the field. If it is a text box: note the current value, clear it, and type a different value (e.g. add `-test` to the end). If it is a dropdown: select a different option from the list | The field shows your new value |
| 4 | Click **Apply** or **Save** if a button appears; otherwise press Tab or click elsewhere to confirm | The change is accepted |
| 5 | Look at the panel settings area | Your new value is visible in the parameter field |
| 6 | Take a screenshot | `T17_param_changed.png` — panel showing the updated parameter value |

**Pass if:** Field accepts a new value; updated value visible in panel after apply.

---

## Test 18 — Reloading the page restores the chat and workflow card

**What this checks:** Your conversation is saved. After a page reload, everything is still there.

**Setup:** You need a chat session with a DESeq2 workflow card and an open right panel. If you completed Test 5 in this session, that is the session to reload — do not start a new chat. If not, start a new chat, paste the message below, wait for the panel to open, and then continue with step 1:

```
Run DESeq2 differential expression on this count matrix — 3 ctrl replicates vs 3 treated replicates:
gene,ctrl1,ctrl2,ctrl3,treat1,treat2,treat3
GENE1,100,120,110,200,210,195
GENE2,50,55,48,52,49,51
GENE3,30,28,32,90,88,95
GENE4,200,210,195,205,198,202
GENE5,15,18,16,45,50,48
```

| # | Do | Expect |
|---|-----|--------|
| 1 | Confirm the chat shows your count matrix message, the AI reply, and a blue workflow card. The right panel is open | Chat visible with "In panel" badge; panel shows Run button |
| 2 | Take a screenshot | `T18_00_before_reload.png` |
| 3 | Press **F5** or **Cmd+R** / **Ctrl+R** to reload the page | Page reloads |
| 4 | Wait for the page to finish loading (up to 10 seconds) | The same chat session re-appears. Your pasted count matrix message and the AI reply are both visible |
| 5 | Look for the workflow card in the AI reply | The blue workflow card is still present |
| 6 | Click the workflow card or the chip to open the panel | The right panel opens showing the same workflow name and parameters |
| 7 | Take a screenshot | `T18_01_after_reload.png` — chat + panel both restored |

**Pass if:** Messages persist after reload; workflow card clickable; panel opens to same workflow.

---

## Test 19 — Download all outputs after a completed run

**What this checks:** After a run completes, "Download all outputs" downloads a zip file containing result files.

**Requires:** A completed run (finish Test 13 first). **If Test 13 did not complete** (the pipeline failed, was cancelled, or was not available in your environment), skip this test and record: "T13 incomplete — T19 skipped."

| # | Do | Expect |
|---|-----|--------|
| 1 | With the panel showing a completed run, click the **After Run** tab | After-run view opens |
| 2 | Look for a **Download all outputs** button | It is visible in the after-run panel |
| 3 | Click **Download all outputs** | The browser starts downloading a file. The filename should end in `.zip` |
| 4 | Wait for the download to complete (usually a few seconds) | The zip file is saved to your downloads folder |
| 5 | Open the zip file | It contains multiple files. At least 3 files with extensions like `.csv`, `.tsv`, `.html`, `.png`, or `.pdf` |
| 6 | Take a screenshot of the zip contents | `T19_zip_contents.png` — file manager or unzip window showing the file list |

**Pass if:** Zip downloads; at least 3 biological output files inside.

---

## Test 20 — Step output files show correct previews

**What this checks:** Clicking on individual output files in the panel shows the right viewer for each file type — images display as images, CSV data shows as a table, and text files show as code.

**Requires:** A completed run (finish Test 13 first). **If Test 13 did not complete**, skip this test and record: "T13 incomplete — T20 skipped."

**Note on file availability:** The output files present depend on which steps completed. If a particular file type is not available (e.g. no `.png` files were produced), skip those sub-steps and note which types were available instead.

| # | Do | Expect |
|---|-----|--------|
| 1 | With the panel showing a completed run, click the **Phases** tab | List of phases/steps visible |
| 2 | Click on the first phase to expand it | A list of output files for that phase appears |
| 3 | **If a `.png` or `.jpg` file is present:** find it and click the **Preview** button next to it. **If none are present:** skip steps 3–4 and note "No image files in output" | An image renders directly in the panel. You can see the actual plot or figure |
| 4 | Take a screenshot | `T20_01_image_preview.png` — the plot rendered inside the panel |
| 5 | **If a `.csv` or `.tsv` file is present:** find it and click **Preview**. **If none are present:** skip steps 5–6 and note "No table files in output" | A table appears with rows and columns. Column headers are visible |
| 6 | Take a screenshot | `T20_02_table_preview.png` — the data table |
| 7 | **If a `.txt`, `.log`, or `.fa` file is present:** find it and click **Preview**. **If none are present:** skip steps 7–8 and note "No text files in output" | A grey code-style box appears with the file's raw text content |
| 8 | Take a screenshot | `T20_03_text_preview.png` — the code/text box |

**Pass if:** Image renders as a visible picture; CSV renders as a table with rows; text renders in a code box.

---

## Logging your results

After completing each test, fill in the table below:

| Test | Pass / Fail | Notes (what you saw if failed) | Screenshots taken |
|------|-------------|--------------------------------|-------------------|
| T1 — Research question | | | |
| T2 — Formatted text | | | |
| T3 — Action buttons | | | |
| T4 — Multi-turn context | | | |
| T5 — Count matrix → workflow | | | |
| T6 — Session history | | | |
| T7 — Empty message rejected | | | |
| T8 — scRNA-seq clustering | | | |
| T9 — VCF variants | | | |
| T10 — SMILES ADMET | | | |
| T11 — Literature citations | | | |
| T12 — Protocol follow-up | | | |
| T13 — Full run lifecycle | | | |
| T14 — Failed run + Restart | | | |
| T15 — QC gate values | | | |
| T16 — Research tangent | | | |
| T17 — Parameter change | | | |
| T18 — Reload restores chat | | | |
| T19 — Download zip | | | |
| T20 — File previews | | | |

**When filing a bug:** include the test number, the step number where it failed, what you expected to see, and what you actually saw. Attach the screenshot from that step.
