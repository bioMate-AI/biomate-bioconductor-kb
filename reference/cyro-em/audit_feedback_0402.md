We've completed our Round 5 review and are returning the updated materials. Links to the three files are below — please load these into your system before re-running.

CO Vocabulary v1.79

Vocab Audit 040126

CO Vocab Conventions Guide v1.17


## What we did

We worked through the Concept Synonym Candidates tab and the Proposed New Concepts tab in full. A summary of changes to the vocabulary:

- Added 13 new concepts (CF, DX, DB, DD, LV, PR prefixes)
- Added synonyms to several existing concepts
- Created a new Reference List for Secondary neutropenia (7 SNOMED-grounded entries)
- Removed "Acute Myocarditis" from the synonyms of DX-C0000262 (Myocarditis) — it is now its own concept, DX-C0000509
- Corrected the grounding code for DX-C0000430 (Drug-induced neutropenia)
- Flagged DD-C0000068 (PCWP/CO Ratio) for removal — SNOMED grounding was marked UNSURE and is not valid
- Updated LOINC code for DD-C0000016 (Pulmonary Vascular Resistance) to 8828-6

Our decisions and rationale are in the Round 5 Decision and Round 5 Comment columns of the Proposed New Concepts tab, and in the Check/Decision/Comment columns of the Concept Synonym Candidates tab.


## Conventions guide updates (v1.17)

Several new sections were added this round that should affect extraction behavior. Please review before re-running:

- §2.3 — New: prefix assignment from SNOMED semantic tag (disorder → DX, finding → CF, etc.), with the CF/LV boundary clarified: raw numeric measurement → LV/VT/DD; clinical interpretation of that measurement → CF
- §3.5 — New: subjective symptom clusters (e.g. "gastrointestinal complaints") route to SI layer, not vocabulary
- §5.17 — Strengthened the New Entity Lookup Protocol with three explicit sub-checks before any ColI/J/L population: (a) synonym match — search the Synonyms column across all concepts; (b) antonym match — also search the Antonyms column; a match means no new concept is needed; (c) most-specific match — a hierarchical parent or child match is insufficient; keep searching for a non-hierarchical match at the same level of specificity
- §5.20a — New: overly broad category terms (e.g. "Congenital Abnormality") should be excluded entirely from all columns
- §5.63 — Revised: the DD/LV creation threshold is now framed around terminological representability and discrete-field availability, not derivation method. Catheter-derived values with valid LOINC/SNOMED grounding that appear as discrete structured EHR fields are permitted.


## Pipeline observations from this round

We noticed several systematic patterns we'd like you to address:

**1. Existing synonyms proposed as new ColI entries (§5.17 step 1 failures)**
In four cases, ColI proposed synonyms that already exist in the Synonyms column of the concept being audited (DX-C0000071, DX-C0000054, SF-C0000001, DB-C0000271). Before populating ColI, please retrieve all existing synonyms for that concept and cross-check each candidate. If a match is found, route to K: "already-in-syns-tab-§5.17 step 1."

**2. New concept proposals duplicating existing concepts (ColJ)**
Three ColJ entries proposed concepts that already exist in the vocabulary (DX-C0000483, DX-C0000205 synonyms, DD-C0000015). Before populating ColJ, search the full Concepts tab by name and synonym to confirm the proposed concept doesn't already exist. Also check the current row's own synonyms.

**3. ColL incorrectly populated**
In two rows (DX-C0000054, DX-C0000055), ColL flagged terms as antonyms that are actually synonyms of existing CF-prefix concepts. ColL ("Antonym needed") should only be populated when (a) an antonymic expression is present in the source text and (b) no antonym concept already exists in the vocabulary.

**4. ColJ and ColK simultaneously populated**
In three rows (DX-C0000048, DX-C0000120, LV-C0000026), the same term appeared in both ColJ and ColK — a direct contradiction. These columns are mutually exclusive. Please enforce this: if a term is routed to K, it must not appear in ColJ, ColI, or ColL.

**5. K-only rows should be suppressed from the audit output**
Rows where all candidates route to ColK only — with ColI, ColJ, and ColL all empty — are fully resolved internally and add noise to our review. Please suppress these rows. Only pass rows where at least one of ColI, ColJ, or ColL has an entry.

**6. Epistemic qualifier stripping (§5.13) not applied before ColI population**
One row proposed "Established Cardiovascular Disease" in ColI. Per §5.13, "Established" is a vacuous epistemic qualifier that must be stripped before any routing decision — the residual "cardiovascular disease" maps to the concept already. This is the §5.13 worked example. Please apply the §5.13 strip as a pre-ColI filter, not just a ColK routing step.

**7. SNOMED code verification**
Caught some old errors. We’ll need to implement robust terminology code lookups soon. Let’s think about the best approach on this, as IMO is very expensive.


## What we're looking for in Round 6

After incorporating the updated guide and vocabulary, please re-run all 160 care options and send results.

For the next round's Proposed New Concepts tab: please exclude grey (already in vocab), red (denied), and blue (approved, not yet added) rows — these are fully handled and add no value to the review. Do include orange (needs reviewer confirmation) rows if any exist, and of course any new white/blank rows. At this point we should be seeing very few, if any, new synonym or concept proposals. Once we reach that point, we'll shift focus to rules review — we're aiming for 2–3 cycles over the next 7 days.

one more thing...

We've added a new tab called Rejections to the CO Vocabulary workbook (same link). It's a running list of every candidate expression we've reviewed and decided not to add to the vocabulary — 81 entries from this round to start.

Please add the following check to your pre-audit pipeline: before populating any row in the audit workbook (Concept Synonyms or the PNC tab), look up the candidate expression in the Rejections tab. Matching should be case-insensitive and exact. If a match is found, suppress the proposal entirely — don't include it in the audit output at all.

We'll add to this list each round as new rejections come in, so it should grow into an effective filter over time.

Now that the Rejections tab is in place, I'd like to suggest a formal process for your system to follow whenever it identifies a candidate concept or synonym during extraction. The goal is to reduce noise in the audit output and strengthen the guide over time.

For each candidate expression, please apply the following steps in order:

1. **Identify the required concept.** Extract the candidate expression from the source text.

2. **Check the vocabulary.** Look up the expression in the CO Vocabulary Concepts tab (concept names, synonyms, and antonyms) and the Global Synonyms tab. If found anywhere, no action needed — the entity is already covered.

3. **Check the guide.** If not in the vocabulary, apply the full conventions guide decision tree (§5.17 and related sections) to determine whether a structural rule prevents it from becoming a concept or synonym — e.g. relationship operator, qualifier, scope mismatch, too broad, subordinate measure, SI layer, etc.

4. **Check the Rejections tab.** If the guide check passes, look up the expression in the Rejections tab (case-insensitive). If found, suppress the proposal — it has already been reviewed and rejected.

5. **If found on the Rejections tab: reinforce the guide.** Look at the Reason column to identify which guide section led to the rejection. Then trace back through your step 3 logic to find why that rule didn't catch the expression during the guide check. If there's a gap, strengthen your application of that section so the same expression wouldn't pass step 3 in future. The Rejections tab should shrink over time as the guide check becomes more robust.

6. **If not found anywhere: propose.** If the expression passes all of the above, include it in the audit output as a new synonym or concept proposal.

The intent is that step 3 does the heavy lifting, and steps 4–5 serve as a catch-and-learn mechanism for cases where the guide check isn't yet strong enough. Over successive rounds, the Rejections tab should become largely redundant as those gaps are closed.


 "Build pharmacophore model then screen library" IS semantically sequential. Isn't it very common that multiple     
sequential steps are in an entire complete workflow? there are many long workflows with multiple steps. It is a      
disaster if they are all considered as a chain. In another word, they are chained internally, probably for a         
complete task. However, biomate has no ability to disambiguite it clearly now. Biomate should constrain the chain to 
 only the several chains already defined in it, and aim for a single workflow to finish the entire work in other     
cases. If a single workflow can not handle the entire process, then it comes to dynamic workflow/tool chains. Do you 
 think the fields describing the workflow, or steps in the workflow can help llm make the determination? For the     
dynamic workflow/tool chain, should it still be step by step? find the first most suitable workflow/tool to start    
first, and see how many steps it covers, then process to find the next workflow/tool for the rest step(s)? What is   
the approach currently doing


1. Review-UX query - is it too hard coded? are you trying to provide a general context instruction to avoid clarification? 8.  
can you double check and document how each status is handled and the information flow of each? Most importantly, is the problem   
of mixing context across different test programs resoved? does this indicate more general severe issues for the context/memory    
management in biomate, among multiple users, among multiple tasks of the same user, among multiple dialogues of the same user?    
Some times, the user may interrupt with another short dialogue, then go back to the previous one right after. Can biomate handle  
this?      
