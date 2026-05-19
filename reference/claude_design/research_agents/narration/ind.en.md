# ind narration (EN)

## Step 1 — Welcome, centered

Welcome to the BioMate IND Report. We'll walk through the five-step pipeline that builds an IND-quality §2.6 nonclinical dossier, the live document panel on the right, and the twenty-one C-F-R Part eleven sign-and-freeze at the end. About two minutes.

---

## Step 2 — Project list

Each program is its own project. The coloured dot on the left of each row is the status — green means signed, blue means in progress, amber means blocked on a gate. Click any project to switch — your work is preserved per project.

---

## Step 3 — New project

Two ways to start an IND. *New Project* here in the rail, or — much more common — from the BioMate chat. When you run an ADMET workflow there, a *Generate IND* chip drops under the result and lands you here with steps one and two already filled.

---

## Step 4 — Step 1 · Project Setup

Step one is the project header. Molecule, target, indication, sponsor, and which agencies you're filing with. Each region you add flips on its region-specific paragraphs in the document — N-M-P-A adds a G-L-P declaration, P-M-D-A adds an ethnic bridging block.

---

## Step 5 — Multi-region toggle

F-D-A, E-M-A, N-M-P-A, P-M-D-A — any combination. The document panel re-renders region-specific paragraphs inline; the body that applies to every region stays put. One source of truth, four agency outputs.

---

## Step 6 — Step 2 · ADMET screening

Step two runs the BioMate *predict admet properties* workflow on the cloud. Forty-one endpoints across H-erg, D-I-L-I, AYMS, P-P-B-R, Caco-two, B-B-B, the CYPs, and P-g-p. These results feed sections two-point-six-point-one-point-three and two-point-six-point-four of the dossier.

---

## Step 7 — Per-compound triage

Click *View ADMET table* for the per-compound view. Every column header tooltips to its guideline citation — H-erg, for example, cites Redfern 2003 and ICH S7B, with the under-ten-micromolar liability threshold. Green check, amber tilde, red cross — the same colour key that travels through the document.

---

## Step 8 — Bring in wet-lab data

Computational predictions get you partial coverage. To upgrade to full, upload your wet-lab data — an NTP G-L-P report PDF or an F-D-A N-D-A review. BioMate auto-extracts measured values, and the measured values take precedence over predictions wherever they overlap.

---

## Step 9 — Step 3 · PBPK qualification

Step three qualifies the P-B-P-K model against a thirty-drug reference set, per E-M-A's qualification guideline. C-max and A-U-C within two-fold for at least sixty-seven percent of the reference set — that's the regulatory gate.

---

## Step 10 — The gateway badge

This badge is the most important pixel in the whole pipeline. If P-B-P-K qualification fails, downstream IND assembly is blocked until you re-qualify. *Re-run with new params* lets you adjust clearance, volume of distribution, or absorption and re-try without leaving the page.

---

## Step 11 — Step 4 · Lead selection

Step four ranks the candidate set. A Gaussian Process model with E-H-V-I acquisition over Morgan fingerprints scores every candidate on a five-axis surrogate — H-erg, D-I-L-I, AYMS, potency, and applicability domain.

---

## Step 12 — Read the ranking

Filled circles encode potency — four out of five filled means strong. *O-O-D* means out of applicability domain — the candidate is still ranked, but flagged in section two-point-six-point-one-point-five with a limitation statement, so reviewers see the caveat.

---

## Step 13 — Step 5 · IND document

Step five assembles the dossier — section two-point-six-point-one-point-one through two-point-six-point-six — once steps one through four are complete. The right-hand panel renders the document live as each pipeline step finishes.

---

## Step 14 — Section coverage

Section coverage at a glance. Filled circle is full — computational plus measured, ready for submission. Half circle is partial — computational only, flagged for wet-lab enrichment. Empty is not yet generated. Sections two-point-six-point-five and two-point-six-point-six always need G-L-P data to reach full.

---

## Step 15 — Live document viewer

The document panel is always visible on the right. As each pipeline step completes, the matching section populates in place — no page reload, no separate preview, no copy-paste from a temporary doc.

---

## Step 16 — Jump to any section

The tab strip jumps you to any section directly. The dot next to each tab encodes coverage at a glance — green for full, amber for partial — so you can spot the gaps without scrolling.

---

## Step 17 — Per-region view

Switch the rendered region right here. N-M-P-A adds the G-L-P declaration paragraph; P-M-D-A adds the ethnic bridging assumption table. The *all regions combined* view is what gets shipped to each agency.

---

## Step 18 — Edit any paragraph

Every paragraph is editable. Change one, and a small *edited — saved for model improvement* note appears beside it. Behind the scenes that edit becomes a training pair — your version as chosen, ours as rejected. That's how the BioMate regulatory model improves with every customer's expertise.

---

## Step 19 — Suggest a citation

See the plus icon at the end of a paragraph? Click it to suggest a missing guideline — especially useful for N-M-P-A or C-D-E technical guidelines we haven't indexed yet. Approved suggestions roll into the shared corpus on the next refresh.

---

## Step 20 — Regulatory audit

The audit bar at the top of section two-point-six is the compliance lens. Zero critical, zero major, two minor, four info — that means the document is signable. Critical blocks signing outright. Major shows an amber warning but lets the regulatory scientist proceed on judgment.

---

## Step 21 — Each finding has a fix

Open the audit drawer. Every finding shows what triggered it, the recommended fix, and a *jump to section* link. *Dismiss* with a reason — for example, *not applicable to this topical product* — and that reason refines the checker rule for every customer, automatically.

---

## Step 22 — Sign & freeze

Sign and freeze. Twenty-one C-F-R Part eleven, section eleven-point-two-hundred. Reviewer credentials, a six-digit T-O-T-P, and the meaning-of-signature statement are permanently recorded inside the frozen document.

---

## Step 23 — Immutable versions

Signed versions are frozen by SHA-two-five-six. Creating version three supersedes version two — but the version-two signature record stays in the audit trail forever. You can always render any prior version, byte-for-byte.

---

## Step 24 — Wrap-up, centered

That's the IND Report end to end. Five-step pipeline, live document, audit overlay, signature freeze. Three things worth trying on your own — open the sign overlay to see the full T-O-T-P flow, edit a paragraph and watch the training-pair note appear, and dismiss an audit finding to close the feedback loop. Happy filing.

---
