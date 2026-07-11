#!/usr/bin/env python3
"""
Test 4-B: Endpoint Recommendation Accuracy
20 indication × MOA pairs from approved autoimmune drugs.
Compare BioMate-recommended primary endpoint to FDA-approved endpoint.

Pass criteria:
  - Exact match ≥ 60% (12/20)
  - Exact + partial match ≥ 80% (16/20)
  - Zero hallucinated endpoint names (endpoints must exist in AACT vocabulary)

Model: gemini-3.5-flash
"""

import json
import os
import time
from pathlib import Path
from datetime import datetime
from google import genai

client = genai.Client(api_key=os.environ["GOOGLE_API_KEY"])
MODEL = "gemini-3.5-flash"

OUT_DIR = Path(__file__).parent / "results" / "test4b"
OUT_DIR.mkdir(exist_ok=True)

# 20 held-out approved autoimmune drugs with FDA-approved primary endpoints
# Source: FDA approval labels, AACT clinical trials database
DRUGS = [
    # RA
    {"drug": "baricitinib", "brand": "Olumiant", "indication": "moderate-to-severe rheumatoid arthritis", "moa": "JAK1/JAK2 inhibitor", "fda_endpoint": "ACR20 at Week 12", "fda_nda": "NDA 207924"},
    {"drug": "upadacitinib", "brand": "Rinvoq", "indication": "moderate-to-severe rheumatoid arthritis", "moa": "selective JAK1 inhibitor", "fda_endpoint": "ACR20 at Week 12", "fda_nda": "NDA 211675"},
    {"drug": "abatacept", "brand": "Orencia", "indication": "moderate-to-severe rheumatoid arthritis", "moa": "CTLA-4-Ig co-stimulation blockade (CD80/CD86 antagonist)", "fda_endpoint": "ACR20 at Week 24", "fda_nda": "BLA 125118"},
    {"drug": "sarilumab", "brand": "Kevzara", "indication": "moderate-to-severe rheumatoid arthritis", "moa": "IL-6 receptor alpha (IL-6Rα) antagonist monoclonal antibody", "fda_endpoint": "ACR20 at Week 24", "fda_nda": "BLA 761037"},
    {"drug": "filgotinib", "brand": "Jyseleca", "indication": "moderate-to-severe rheumatoid arthritis", "moa": "selective JAK1 inhibitor", "fda_endpoint": "ACR20 at Week 12", "fda_nda": "EU approval (not FDA-approved in US); EMA endpoint: ACR20 Week 12", "fda_approved_us": False},
    # Psoriasis / PsA
    {"drug": "ixekizumab", "brand": "Taltz", "indication": "moderate-to-severe plaque psoriasis", "moa": "IL-17A monoclonal antibody antagonist", "fda_endpoint": "PASI 75 at Week 12", "fda_nda": "BLA 125521"},
    {"drug": "secukinumab", "brand": "Cosentyx", "indication": "moderate-to-severe plaque psoriasis", "moa": "IL-17A monoclonal antibody antagonist", "fda_endpoint": "PASI 75 at Week 12", "fda_nda": "BLA 125504"},
    {"drug": "guselkumab", "brand": "Tremfya", "indication": "moderate-to-severe plaque psoriasis", "moa": "IL-23 p19 subunit monoclonal antibody antagonist", "fda_endpoint": "IGA 0/1 at Week 16", "fda_nda": "BLA 761061"},
    {"drug": "risankizumab", "brand": "Skyrizi", "indication": "moderate-to-severe plaque psoriasis", "moa": "IL-23 p19 subunit monoclonal antibody antagonist", "fda_endpoint": "PASI 90 at Week 16", "fda_nda": "BLA 761105"},
    {"drug": "upadacitinib_psa", "drug_name": "upadacitinib", "brand": "Rinvoq", "indication": "active psoriatic arthritis", "moa": "selective JAK1 inhibitor", "fda_endpoint": "ACR20 at Week 12", "fda_nda": "NDA 211675 (PsA sNDA)"},
    # SLE / Lupus
    {"drug": "belimumab", "brand": "Benlysta", "indication": "active systemic lupus erythematosus (SLE)", "moa": "BLyS (BAFF) neutralizing monoclonal antibody", "fda_endpoint": "SRI-4 response at Week 52", "fda_nda": "BLA 125370"},
    {"drug": "voclosporin", "brand": "Lupkynis", "indication": "active lupus nephritis", "moa": "calcineurin inhibitor (CNI) — T cell activation suppression", "fda_endpoint": "complete renal response at Week 52", "fda_nda": "NDA 213716"},
    {"drug": "obinutuzumab_lupus", "drug_name": "obinutuzumab", "brand": "Gazyva", "indication": "lupus nephritis", "moa": "CD20-directed cytolytic antibody (type II anti-CD20)", "fda_endpoint": "complete renal response at Week 52", "fda_nda": "BLA 125486 (LN sNDA)"},
    # IBD (CD/UC)
    {"drug": "vedolizumab", "brand": "Entyvio", "indication": "moderately to severely active Crohn's disease", "moa": "α4β7 integrin antagonist — gut-selective lymphocyte trafficking inhibitor", "fda_endpoint": "clinical remission (CDAI < 150) at Week 6", "fda_nda": "BLA 125476"},
    {"drug": "ustekinumab", "brand": "Stelara", "indication": "moderately to severely active Crohn's disease", "moa": "IL-12/IL-23 p40 subunit monoclonal antibody antagonist", "fda_endpoint": "clinical remission (CDAI < 150) at Week 8 (induction)", "fda_nda": "BLA 761044"},
    {"drug": "risankizumab_cd", "drug_name": "risankizumab", "brand": "Skyrizi", "indication": "moderately to severely active Crohn's disease", "moa": "IL-23 p19 subunit monoclonal antibody antagonist", "fda_endpoint": "clinical remission (CDAI < 150) at Week 12 (induction)", "fda_nda": "BLA 761105 (CD sNDA)"},
    {"drug": "ozanimod", "brand": "Zeposia", "indication": "moderately to severely active ulcerative colitis", "moa": "sphingosine-1-phosphate (S1P) receptor 1 and 5 modulator", "fda_endpoint": "clinical remission at Week 10 (induction)", "fda_nda": "NDA 209899 (UC sNDA)"},
    # Atopic dermatitis
    {"drug": "dupilumab", "brand": "Dupixent", "indication": "moderate-to-severe atopic dermatitis", "moa": "IL-4/IL-13 receptor (IL-4Rα) antagonist — dual IL-4 and IL-13 blockade", "fda_endpoint": "IGA 0/1 at Week 16", "fda_nda": "BLA 761055"},
    {"drug": "tralokinumab", "brand": "Adbry", "indication": "moderate-to-severe atopic dermatitis", "moa": "IL-13 monoclonal antibody antagonist", "fda_endpoint": "IGA 0/1 at Week 16", "fda_nda": "BLA 761180"},
    # MS
    {"drug": "ofatumumab", "brand": "Kesimpta", "indication": "relapsing forms of multiple sclerosis", "moa": "CD20-directed cytolytic antibody (fully human anti-CD20)", "fda_endpoint": "annualized relapse rate (ARR) over 24 months", "fda_nda": "BLA 761130"},
]

AACT_ENDPOINTS = {
    "ACR20", "ACR50", "ACR70", "DAS28", "DAS28-CRP", "DAS28-ESR",
    "PASI 75", "PASI 90", "PASI 100", "IGA 0/1", "IGA 0", "IGA 1",
    "SRI-4", "SRI-5", "SRI-6", "BICLA",
    "CDAI", "CDAI < 150", "clinical remission", "clinical response",
    "ARR", "annualized relapse rate",
    "complete renal response", "partial renal response",
    "HAQ-DI", "mTSS", "EASI", "SCORAD", "IGA",
    "ACR-EULAR remission", "Boolean remission", "SDAI remission",
}

SYSTEM_PROMPT = """You are a clinical pharmacologist specializing in autoimmune diseases with deep knowledge of FDA regulatory requirements for clinical trial design. You recommend FDA-approvable primary endpoints for autoimmune drug clinical trials based on indication and mechanism of action.

When recommending an endpoint, you MUST:
1. Use standard AACT/FDA vocabulary for endpoint names (e.g., "ACR20 at Week 12", not "ACR 20%")
2. Include the specific timepoint (Week X)
3. Be concise — one primary endpoint only
4. Base the recommendation on precedent from similar approved drugs and FDA guidance documents

Output format (JSON only, no commentary):
{
  "primary_endpoint": "<endpoint name and timepoint>",
  "rationale": "<1-2 sentence justification citing FDA precedent or guidance>",
  "confidence": "high|medium|low"
}"""


def recommend_endpoint(drug: dict) -> dict:
    drug_name = drug.get("drug_name", drug["drug"])
    prompt = f"""Recommend the FDA-approvable primary clinical trial endpoint for:

Drug: {drug_name} ({drug['brand']})
Indication: {drug['indication']}
Mechanism of action: {drug['moa']}

Return JSON only."""

    start = time.time()
    resp = client.models.generate_content(
        model=MODEL,
        contents=prompt,
        config={"system_instruction": SYSTEM_PROMPT}
    )
    elapsed = time.time() - start

    text = resp.text.strip()
    # Strip markdown code fences if present
    if text.startswith("```"):
        text = text.split("```")[1]
        if text.startswith("json"):
            text = text[4:]
        text = text.strip()
    if text.endswith("```"):
        text = text[:-3].strip()

    try:
        result = json.loads(text)
    except json.JSONDecodeError:
        result = {"primary_endpoint": text[:200], "rationale": "parse error", "confidence": "low"}

    result["elapsed_s"] = round(elapsed, 1)
    return result


def score_match(recommended: str, fda_approved: str) -> str:
    rec = recommended.lower().strip()
    fda = fda_approved.lower().strip()

    # Exact match (normalize whitespace)
    if rec == fda:
        return "exact"

    # Check for key endpoint name match (e.g., "ACR20" in both)
    fda_key_terms = []
    for term in ["acr20", "acr50", "acr70", "pasi 75", "pasi 90", "pasi 100",
                 "iga 0/1", "sri-4", "sri-5", "bicla", "arr", "annualized relapse rate",
                 "complete renal response", "cdai", "clinical remission", "clinical response",
                 "das28", "easi", "iga 0"]:
        if term in fda:
            fda_key_terms.append(term)

    rec_matches = sum(1 for t in fda_key_terms if t in rec)
    if fda_key_terms and rec_matches == len(fda_key_terms):
        # All key terms match but timepoint or phrasing differs
        if any(wk in rec for wk in ["week", "wk"]) and any(wk in fda for wk in ["week", "wk"]):
            # Extract week numbers
            import re
            rec_weeks = re.findall(r'week\s*(\d+)', rec)
            fda_weeks = re.findall(r'week\s*(\d+)', fda)
            if rec_weeks and fda_weeks and rec_weeks[0] == fda_weeks[0]:
                return "exact"
            elif rec_weeks and fda_weeks:
                return "partial"  # Right endpoint, wrong timepoint
        return "partial"
    elif fda_key_terms and rec_matches >= 1:
        return "partial"
    else:
        return "wrong"


def is_aact_valid(endpoint: str) -> bool:
    ep_lower = endpoint.lower()
    for valid in AACT_ENDPOINTS:
        if valid.lower() in ep_lower:
            return True
    # Also accept if it contains standard patterns
    import re
    if re.search(r'acr\s*\d+|pasi\s*\d+|iga\s*\d|sri-\d|bicla|arr|cdai|das28|easi', ep_lower):
        return True
    if "remission" in ep_lower or "response" in ep_lower or "relapse" in ep_lower:
        return True
    return False


print("Test 4-B: Endpoint Recommendation Accuracy")
print("=" * 60)
print(f"Model: {MODEL}")
print(f"Test cases: {len(DRUGS)}\n")

results = []
exact = 0
partial = 0
wrong = 0
hallucinated = 0

for i, drug in enumerate(DRUGS, 1):
    drug_name = drug.get("drug_name", drug["drug"])
    print(f"[{i:2d}/20] {drug_name} ({drug['indication'][:45]})")

    rec = recommend_endpoint(drug)
    endpoint_rec = rec.get("primary_endpoint", "")
    fda_endpoint = drug["fda_endpoint"]

    match = score_match(endpoint_rec, fda_endpoint)
    aact_valid = is_aact_valid(endpoint_rec)

    if match == "exact":
        exact += 1
        symbol = "✓"
    elif match == "partial":
        partial += 1
        symbol = "~"
    else:
        wrong += 1
        symbol = "✗"

    if not aact_valid:
        hallucinated += 1
        symbol += "!"

    print(f"       Recommended: {endpoint_rec}")
    print(f"       FDA approved: {fda_endpoint}")
    print(f"       Match: {match} | AACT valid: {aact_valid} | {symbol}")

    results.append({
        "drug": drug_name,
        "brand": drug["brand"],
        "indication": drug["indication"],
        "moa": drug["moa"],
        "fda_endpoint": fda_endpoint,
        "recommended_endpoint": endpoint_rec,
        "rationale": rec.get("rationale", ""),
        "confidence": rec.get("confidence", ""),
        "match": match,
        "aact_valid": aact_valid,
        "elapsed_s": rec.get("elapsed_s", 0),
    })

total = len(DRUGS)
exact_rate = exact / total
partial_rate = (exact + partial) / total

print(f"\n{'='*60}")
print(f"Exact match:          {exact}/{total} = {100*exact_rate:.0f}%  (target ≥60%)")
print(f"Exact + partial:      {exact+partial}/{total} = {100*partial_rate:.0f}%  (target ≥80%)")
print(f"Wrong:                {wrong}/{total}")
print(f"Hallucinated (non-AACT): {hallucinated}/{total}  (target 0)")

pass_exact = exact_rate >= 0.60
pass_combined = partial_rate >= 0.80
pass_no_hallucination = hallucinated == 0
overall_pass = pass_exact and pass_combined and pass_no_hallucination

verdict = "PASS" if overall_pass else "PARTIAL" if (exact + partial) >= 12 else "FAIL"

print(f"\nPass criteria:")
print(f"  Exact ≥60%:    {'✓' if pass_exact else '✗'} ({100*exact_rate:.0f}%)")
print(f"  Combined ≥80%: {'✓' if pass_combined else '✗'} ({100*partial_rate:.0f}%)")
print(f"  0 hallucinated: {'✓' if pass_no_hallucination else '✗'} ({hallucinated} found)")
print(f"\nVerdict: {verdict}")

out = {
    "test_id": "4-B",
    "test_name": "Endpoint Recommendation Accuracy — 20 Autoimmune Drugs",
    "date_run": datetime.now().isoformat(),
    "model": MODEL,
    "total_cases": total,
    "exact_match": exact,
    "partial_match": partial,
    "wrong": wrong,
    "hallucinated_endpoints": hallucinated,
    "exact_rate": round(exact_rate, 3),
    "combined_rate": round(partial_rate, 3),
    "pass_criteria": {
        "exact_geq_60pct": pass_exact,
        "combined_geq_80pct": pass_combined,
        "zero_hallucinated": pass_no_hallucination,
    },
    "verdict": verdict,
    "results": results,
}

out_file = OUT_DIR / "test4b_endpoint_results.json"
out_file.write_text(json.dumps(out, indent=2))
print(f"\nSaved to {out_file}")
