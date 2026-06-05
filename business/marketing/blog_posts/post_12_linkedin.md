# LinkedIn feed post — Post 12 (600 = blog tier; professional HTS path)

**Recommended hero image:** Two-lane diagram — left “600 AAAC blog pilot”, right “2–5k multi-tranche publication HTS” (1200×627 PNG).

**Character count:** ~2,600 / 3,000 limit.

---

600 compounds docked is a great **demo**.

It is not a **paper**.

On our ANDV glycoprotein inhibitor track (PDB 9P3I) we learned to separate tiers:

📰 **Blog / methods (600)**
→ First 600 lines of ZINC20 tranche **AAAC** (~1k polar, fragment-like compounds)
→ Proves BioMate funnel: pocket → pharmacophore → ADMET → Vina on AWS Batch
→ Full provenance: ZINC substance IDs, manifest JSON, honest manuscript language
→ **Not** “representative ZINC20” or “ANDV-guided library”

🔬 **Publication HTS (next: 2,000–5,000)**
→ **Multi-tranche** union (ABAA, ABAB, ABAC, BBAA, BCAC — ~42k raw)
→ RDKit drug-like gate + **antiviral-reference pharmacophore** *before* docking
→ Reference actives + INH-01 always in deck
→ Same 9P3I box; ~100 Batch jobs at 50 SMILES/job

What the professional follow-on taught us:

✅ Pharmacophore filter on the 600 → **91 pass** → **91/91 docked**  
✅ Top Vina hits **unchanged** (same polar chemotypes)  
✅ INH-01 still rank 3 — score ≠ lead without pose QC  
✅ Ensemble: 4/5 “improved” but Δ ≤ 0.14 kcal/mol — sensitivity, not promotion  

**Professional ≠ bigger adjectives.** It is tiering, manifests, and not upgrading a methods pilot into a discovery claim.

Two-agent pattern (Post 10): Planner routes workflows; Coach runs Batch and returns **artifact paths**, not green checkmarks.

Full workflow diagrams + tranche survey:

[Substack link — Post 12]

Internal design doc: `PUBLICATION_ZINC_LIBRARY_DESIGN.md`

Try the stack on your structures:

👉 biomate.ai/try

`#drugdiscovery` `#virtualscreening` `#zinc` `#reproducibility` `#agenticAI` `#hantavirus`
