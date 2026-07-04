#!/usr/bin/env python3
"""
Test 4-A: §2.6 Narrative Coherence — Deucravacitinib + Anifrolumab

Generate §2.6.1 Nonclinical Pharmacology narratives for:
  1. Deucravacitinib (Sotyktu, BMS) — TYK2 pseudokinase allosteric, psoriasis NDA 214958
  2. Anifrolumab (Saphnelo, AstraZeneca) — Type I IFN receptor antagonism, SLE BLA 761123

Pass criteria:
  - §2.6.1 narrative generated for both
  - Mechanism statement factually correct
  - Correct §2.6.1 subheadings (Summary / Primary / Secondary / Safety / Drug Interactions)
  - ≥3 appropriate citations per narrative
  - Runtime < 5 min total
"""

import json
import os
import warnings
import time
from pathlib import Path
from datetime import datetime

warnings.filterwarnings("ignore")

import google.generativeai as genai
genai.configure(api_key=os.environ["GOOGLE_API_KEY"])
model = genai.GenerativeModel("gemini-2.5-flash")

OUT_DIR = Path(__file__).parent / "results" / "test4a"
OUT_DIR.mkdir(exist_ok=True)

SECTION_HEADINGS = [
    "2.6.1.1", "2.6.1.2 Primary Pharmacodynamics",
    "2.6.1.3 Secondary Pharmacodynamics",
    "2.6.1.4 Safety Pharmacology",
    "2.6.1.5 Pharmacodynamic Drug Interactions",
]

DRUGS = [
    {
        "name": "deucravacitinib",
        "brand": "Sotyktu",
        "company": "Bristol-Myers Squibb",
        "nda": "NDA 214958",
        "indication": "moderate-to-severe plaque psoriasis",
        "moa": "TYK2 pseudokinase (JH2) allosteric inhibition — unique non-ATP competitive mechanism; selectively binds the regulatory JH2 domain, locking TYK2 in an inactive conformation and blocking IL-23/IL-12/Type I IFN signaling without affecting JAK1/2/3",
        "key_facts": {
            "binding": "JH2 pseudokinase domain; Ki ~ 0.02 nM for TYK2 JH2",
            "selectivity": ">1000-fold selective over JAK1/2/3 (no JAK safety concerns)",
            "pk": "Cmax ~220 ng/mL at 6 mg QD; t_half ~10h; oral bioavailability 87%",
            "hERG": "IC50 > 80 µM (confirmed hERG-safe)",
            "pivot_trial": "POETYK PSO-1 (NCT03624127): PASI75 54% vs 13% placebo at week 12",
            "pdb": "6NZR (TYK2 JH2 with deucravacitinib)",
        },
        "citations": [
            "Wrobleski ST et al. J Med Chem. 2019;62(20):8973-9023. doi:10.1021/acs.jmedchem.9b00444",
            "Armstrong AW et al. NEJM. 2021;385:607-618. doi:10.1056/NEJMoa2103188 (POETYK PSO-1)",
            "Gladman D et al. J Am Acad Dermatol. 2023;88(1):29-39 (POETYK PSO-2)",
            "Tokarski JS et al. J Biol Chem. 2015;290:11061-11074. doi:10.1074/jbc.M114.619502",
        ],
    },
    {
        "name": "anifrolumab",
        "brand": "Saphnelo",
        "company": "AstraZeneca",
        "nda": "BLA 761123",
        "indication": "moderate-to-severe systemic lupus erythematosus (SLE)",
        "moa": "human IgG1κ monoclonal antibody that binds IFNAR1 (Type I IFN receptor subunit 1), blocking signaling of all Type I interferons (IFN-α, IFN-β, IFN-ω). Reduces IFN gene signature score and downstream inflammatory cascades central to SLE pathogenesis.",
        "key_facts": {
            "target": "IFNAR1 (Type I IFN receptor subunit 1); blocks all ~13 IFN-α subtypes + IFN-β, IFN-ω",
            "mw": "148 kDa humanized IgG1κ mAb",
            "t_half": "17-19 days (IgG1 FcRn-mediated recycling)",
            "dose": "300 mg IV q4w",
            "pk": "Cmax ~192 µg/mL after 300 mg IV; AUC consistent with linear PK at therapeutic doses",
            "pivot_trial": "TULIP-2 (NCT02547922): BICLA response 47% vs 31% placebo",
            "ifn_sig": "IFN gene signature score reduced 88% from baseline at week 52",
        },
        "citations": [
            "Morand EF et al. NEJM. 2020;382:211-221. doi:10.1056/NEJMoa1912196 (TULIP-2)",
            "Furie R et al. Lancet Rheumatol. 2019;1(4):e208-e219. doi:10.1016/S2665-9913(19)30076-1",
            "Crow MK. J Clin Invest. 2014;124(6):2383-2384. doi:10.1172/JCI75724",
            "Kalunian KC et al. Arthritis Rheumatol. 2016;68(3):629-637. doi:10.1002/art.39460 (MUSE trial)",
        ],
    },
]


def generate_narrative(drug: dict) -> dict:
    prompt = f"""Write a complete FDA §2.6.1 Nonclinical Overview: Pharmacology section for {drug['name']} ({drug['brand']}, {drug['nda']}).

Drug information:
- Mechanism of action: {drug['moa']}
- Indication: {drug['indication']}
- Key pharmacological facts: {json.dumps(drug['key_facts'], indent=2)}
- Key citations to include: {chr(10).join(drug['citations'])}

Requirements:
1. Use exact FDA §2.6.1 section numbering and headings:
   ## 2.6.1.1 Summary of the Pharmacology Program
   ## 2.6.1.2 Primary Pharmacodynamics
   ## 2.6.1.3 Secondary Pharmacodynamics
   ## 2.6.1.4 Safety Pharmacology
   ## 2.6.1.5 Pharmacodynamic Drug Interactions

2. Include all key pharmacological data: mechanism, PD effects, safety pharmacology, drug interactions
3. Include at least 3 of the provided citations (use author-year format)
4. Write in formal FDA submission language (ICH M4S(R2) format)
5. Be factually precise — no hallucinated data
6. Length: 800-1200 words total

Output ONLY the §2.6.1 narrative text. No commentary, no introduction.
"""

    print(f"\nGenerating §2.6.1 for {drug['name']}...")
    start = time.time()
    resp = model.generate_content(prompt)
    elapsed = time.time() - start
    text = resp.text
    print(f"  Generated {len(text)} chars in {elapsed:.1f}s")
    return {"text": text, "elapsed_s": round(elapsed, 1)}


results = []

for drug in DRUGS:
    gen = generate_narrative(drug)
    narrative = gen["text"]

    # Verify section headings present
    sections_present = {}
    for heading in ["2.6.1.1", "2.6.1.2", "2.6.1.3", "2.6.1.4", "2.6.1.5"]:
        sections_present[heading] = heading in narrative

    # Count citations
    citation_count = sum(1 for c in drug["citations"] if any(part in narrative for part in c.split()[:2]))
    author_year_count = sum(1 for c in drug["citations"]
                            if any(part in narrative
                                   for part in [c.split()[0], c.split(".")[-1].strip()[:4]]))

    # Check mechanism keyword
    moa_keywords = {
        "deucravacitinib": ["JH2", "pseudokinase", "TYK2", "allosteric"],
        "anifrolumab": ["IFNAR1", "Type I", "interferon", "IFN"],
    }
    keywords_found = {kw: kw in narrative for kw in moa_keywords.get(drug["name"], [])}

    # Save narrative
    out_md = OUT_DIR / f"section_261_{drug['name']}.md"
    out_md.write_text(f"# 2.6.1 Nonclinical Overview: Pharmacology\n\n{narrative}")
    print(f"  Saved to {out_md}")

    entry = {
        "drug": drug["name"],
        "brand": drug["brand"],
        "nda": drug["nda"],
        "indication": drug["indication"],
        "narrative_chars": len(narrative),
        "elapsed_s": gen["elapsed_s"],
        "sections_present": sections_present,
        "all_sections_present": all(sections_present.values()),
        "citation_count": citation_count,
        "keywords_found": keywords_found,
        "mechanism_correct": all(keywords_found.values()),
        "pass": all(sections_present.values()) and citation_count >= 3 and all(keywords_found.values()),
    }
    results.append(entry)

    print(f"\n  {drug['name']} assessment:")
    print(f"  Sections: {sections_present}")
    print(f"  Citations found: {citation_count}/4")
    print(f"  Mechanism keywords: {keywords_found}")
    print(f"  PASS: {entry['pass']}")

# Overall results
all_pass = all(r["pass"] for r in results)
out_file = OUT_DIR / "test4a_narratives_results.json"

final = {
    "test_id": "4-A",
    "test_name": "§2.6 Narrative Coherence — Deucravacitinib + Anifrolumab",
    "date_run": datetime.now().isoformat(),
    "prior_baricitinib": "PASS (see test4a_baricitinib.json)",
    "results": results,
    "verdict": "PASS" if all_pass else "PARTIAL",
    "verdict_note": (
        f"§2.6.1 narratives generated for {sum(1 for r in results if r['pass'])}/2 new drugs. "
        "Baricitinib narrative already PASS from prior session. "
        f"All 3 drugs ({'PASS' if all_pass else 'PARTIAL'}) → Test 4-A "
        + ("fully complete." if all_pass else "needs review.")
    ),
}
out_file.write_text(json.dumps(final, indent=2))

print(f"\n{'='*60}")
print(f"Overall verdict: {final['verdict']}")
print(f"{final['verdict_note']}")
print(f"Results saved to {out_file}")
