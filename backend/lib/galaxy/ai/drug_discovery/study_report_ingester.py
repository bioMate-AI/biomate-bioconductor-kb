"""
BioMate Study Report Ingester — Phase 1 (prose extraction)

Extracts structured nonclinical study parameters from GLP study report PDFs.
Strategy: extract from the study's conclusion/results prose paragraphs, which
are reliable text in every GLP study report, rather than the tabular data
(which varies by CRO format and has unreliable table structure).

Extracted fields per study:
  study_type       str   e.g. "28-day repeat dose", "Ames test", "hERG patch clamp"
  species          str   e.g. "rat", "dog", "mouse"
  route            str   e.g. "oral", "intravenous", "inhalation"
  noael            float NOAEL in mg/kg/day (or None if not determinable)
  noael_unit       str   e.g. "mg/kg/day", "µg/kg", "mg/m²"
  duration         str   e.g. "28 days", "13 weeks", "2 years"
  key_findings     str   plain-text summary of main findings
  ames_result      bool  True=positive/mutagenic, False=negative; None=not an Ames study
  herg_ic50_um     float hERG IC50 in µM; None if not an hERG study
  glp              bool  True if GLP-compliant
  study_id         str   study report identifier from the document
"""
from __future__ import annotations

import logging
import re
from pathlib import Path
from typing import Optional

log = logging.getLogger(__name__)

# ── Study type patterns ────────────────────────────────────────────────────

_STUDY_TYPE_PATTERNS: list[tuple[re.Pattern, str]] = [
    (re.compile(r"\bames\b|\bbacterial reverse mutation\b", re.I), "ames"),
    (re.compile(r"\bmicronucleus\b", re.I), "micronucleus"),
    (re.compile(r"\bchromosomal aberration\b", re.I), "chromosomal_aberration"),
    (re.compile(r"\bherg\b|hERG|ikr\b|\bcardiac ion channel\b|\bpatch.?clamp\b", re.I), "herg"),
    (re.compile(r"\bsingle.dose\b|\bacute.*toxic\b|\bld50\b|\blethal dose\b", re.I), "single_dose"),
    (re.compile(r"\b28.day\b|\b4.week\b|\bsubacute\b", re.I), "repeat_dose_28d"),
    (re.compile(r"\b90.day\b|\b13.week\b|\b3.month\b|\bsubchronic\b", re.I), "repeat_dose_90d"),
    (re.compile(r"\b26.week\b|\b6.month\b|\bchronic\b", re.I), "repeat_dose_26w"),
    (re.compile(r"\b2.year\b|\b104.week\b|\bcarcinogen", re.I), "carcinogenicity"),
    (re.compile(r"\bembryofetal\b|\bembryo.fetal\b|\bteratolog\b", re.I), "reproductive"),
    (re.compile(r"\bfertility\b|\bsegment i\b", re.I), "fertility"),
    (re.compile(r"\bpharmacokinetic\b|\bpk\b|\babsorption.*distribution\b", re.I), "pharmacokinetics"),
    (re.compile(r"\bsafety pharmacology\b|\bfob\b|\bfunctional observational\b", re.I), "safety_pharmacology"),
]

_SPECIES_PATTERN = re.compile(
    r"\b(sprague.?dawley|wistar|fischer|cd.?1|balb/c|c57|beagle|cynomolgus|"
    r"rat|mouse|mice|dog|monkey|rabbit|hamster|guinea pig|minipig|pig)\b",
    re.I,
)
_ROUTE_PATTERN = re.compile(
    # Abbreviations like i.v./s.c./i.m. end with '.' — no trailing \b (non-word boundary)
    r"\b(oral(?:ly)?|gavage|intravenous(?:ly)?|i\.v\.|subcutaneous(?:ly)?|"
    r"s\.c\.|inhalation|dermal|topical|intramuscular|i\.m\.)",
    re.I,
)
_NOAEL_PATTERN = re.compile(
    r"(?:NOAEL|no.?observed.?adverse.?effect.?level)[^.]{0,150}"
    r"(\d[\d,]*(?:\.\d+)?)\s*(mg/kg(?:/day)?|µg/kg|g/kg|mg/m[²2]|mmol/kg)",
    re.I,
)
_LOAEL_PATTERN = re.compile(
    r"(?:LOAEL|lowest.?observed.?adverse.?effect.?level)[^.]{0,150}"
    r"(\d[\d,]*(?:\.\d+)?)\s*(mg/kg(?:/day)?|µg/kg|g/kg)",
    re.I,
)
_LD50_PATTERN = re.compile(
    r"(?:LD50|LD-50|lethal dose[^.]{0,30}?50|approximate lethal dose|"
    r"MTD|maximum tolerated dose|MLD|minimum lethal dose)[^.]{0,100}?"
    r"(\d[\d,]*(?:\.\d+)?)\s*(mg/kg(?:/day)?|µg/kg|g/kg|mg/m[²2])",
    re.I,
)
_MICRONUCLEUS_RESULT_PATTERN = re.compile(
    r"(?:micronucleus|MN)[^.]{0,200}(negative|positive|no.?increase|"
    r"significant.?increase|clastogenic|genotoxic)",
    re.I,
)
_HERG_PATTERN = re.compile(
    r"(?:hERG|IKr)[^.]{0,100}IC50[^.]{0,50}(\d[\d.]+)\s*(µM|μM|nM|uM)",
    re.I,
)
_DURATION_PATTERN = re.compile(
    r"\b(\d+(?:\.\d+)?)\s*(day|week|month|year)s?\b",
    re.I,
)
_GLP_PATTERN = re.compile(r"\bGLP.?compliant\b|\bconducted.{0,20}GLP\b|"
                           r"\bGood Laboratory Practice\b", re.I)
_STUDY_ID_PATTERN = re.compile(
    r"(?:study\s+(?:no|number|id|report)[.\s:]+|report\s+no[.\s:]+)"
    r"([A-Z0-9][A-Z0-9/_\-]{2,30})",
    re.I,
)
_AMES_RESULT_PATTERN = re.compile(
    r"(?:ames|bacterial reverse mutation)[^.]{0,200}"
    r"(negative|positive|non.mutagenic|mutagenic)",
    re.I,
)


def _classify_study_type(text: str) -> str:
    """Return the primary study type label from the document text."""
    for pattern, label in _STUDY_TYPE_PATTERNS:
        if pattern.search(text):
            return label
    return "general_toxicology"


def _extract_conclusion_pages(full_text: str) -> str:
    """
    Return the text most likely to contain NOAEL and study conclusions.
    Looks for section headers: 'Conclusion', 'Results', 'Summary'.
    Falls back to the last 2,000 characters if nothing found.
    """
    # Find the conclusion/results section
    m = re.search(
        r"(?:^|\n)\s*(?:4\.|5\.|6\.|\d\.?\d?\.?\s+)?(?:conclusion|results and discussion|summary)[:\s]*\n",
        full_text, re.I | re.M,
    )
    if m:
        start = m.start()
        return full_text[start:start + 3000]

    # Fall back to last portion of document
    return full_text[-3000:]


def extract_from_pdf(pdf_bytes: bytes) -> dict:
    """
    Extract structured study parameters from a GLP study report PDF.

    Returns a dict with fields: study_type, species, route, noael, noael_unit,
    duration, key_findings, ames_result, herg_ic50_um, glp, study_id.
    Missing/uncertain fields are None.
    """
    try:
        import fitz  # PyMuPDF
    except ImportError:
        log.error("PyMuPDF (fitz) not installed — cannot extract from PDF")
        return {"error": "PyMuPDF not available"}

    try:
        doc = fitz.open(stream=pdf_bytes, filetype="pdf")
    except Exception as e:
        return {"error": f"Failed to open PDF: {e}"}

    # Extract text from all pages
    pages_text = []
    for page in doc:
        pages_text.append(page.get_text())
    full_text = "\n".join(pages_text)
    doc.close()

    if len(full_text) < 100:
        return {"error": "PDF appears to be scanned/image-only — text extraction not possible"}

    # Classification from full text
    study_type = _classify_study_type(full_text)

    # Focus extraction on the conclusion section for NOAEL/findings
    conclusion_text = _extract_conclusion_pages(full_text)

    # Species (from full text — usually in study design sections)
    species_m = _SPECIES_PATTERN.search(full_text[:5000])  # study design near top
    species = _normalise_species(species_m.group(1)) if species_m else None

    # Route
    route_m = _ROUTE_PATTERN.search(full_text[:5000])
    route = _normalise_route(route_m.group(1)) if route_m else None

    # NOAEL — prefer conclusion section
    noael, noael_unit = None, None
    noael_m = _NOAEL_PATTERN.search(conclusion_text) or _NOAEL_PATTERN.search(full_text)
    if noael_m:
        raw = noael_m.group(1).replace(",", "")
        try:
            noael = float(raw)
        except ValueError:
            pass
        noael_unit = noael_m.group(2)

    # Duration
    duration = None
    dur_m = _DURATION_PATTERN.search(full_text[:3000])
    if dur_m:
        duration = f"{dur_m.group(1)} {dur_m.group(2)}s"

    # hERG IC50 (if this is a cardiac study)
    herg_ic50_um = None
    if study_type == "herg":
        herg_m = _HERG_PATTERN.search(full_text)
        if herg_m:
            raw_val = float(herg_m.group(1))
            unit = herg_m.group(2).lower()
            # Convert nM → µM
            herg_ic50_um = raw_val / 1000.0 if "nm" in unit else raw_val

    # Ames result
    ames_result = None
    if study_type == "ames":
        ames_m = _AMES_RESULT_PATTERN.search(conclusion_text) or _AMES_RESULT_PATTERN.search(full_text)
        if ames_m:
            verdict = ames_m.group(1).lower()
            ames_result = ("positive" in verdict) or ("mutagenic" in verdict and "non" not in verdict)

    # Micronucleus result (separate from Ames — different biology)
    micronucleus_result = None
    if study_type == "micronucleus":
        mn_m = _MICRONUCLEUS_RESULT_PATTERN.search(conclusion_text) or _MICRONUCLEUS_RESULT_PATTERN.search(full_text)
        if mn_m:
            verdict = mn_m.group(1).lower()
            micronucleus_result = "negative" if ("negative" in verdict or "no" in verdict) else "positive"
        else:
            # Fallback: infer from key_findings keywords
            kf = conclusion_text.lower()
            if "no clastogenic" in kf or "not genotoxic" in kf or "negative" in kf:
                micronucleus_result = "negative"
            elif "clastogenic" in kf or "genotoxic" in kf or "positive" in kf:
                micronucleus_result = "positive"

    # LD50 / MTD for single-dose studies
    ld50, ld50_unit = None, None
    if study_type == "single_dose":
        ld50_m = _LD50_PATTERN.search(conclusion_text) or _LD50_PATTERN.search(full_text)
        if ld50_m:
            raw_ld = ld50_m.group(1).replace(",", "")
            try:
                ld50 = float(raw_ld)
            except ValueError:
                pass
            ld50_unit = ld50_m.group(2)

    # GLP compliance
    glp = bool(_GLP_PATTERN.search(full_text[:3000]))

    # Study ID
    study_id = None
    id_m = _STUDY_ID_PATTERN.search(full_text[:2000])
    if id_m:
        study_id = id_m.group(1).strip()

    # Key findings: first meaningful sentence from conclusion section
    sentences = re.split(r"(?<=[.!?])\s+", conclusion_text)
    key_sentences = [s.strip() for s in sentences if len(s.strip()) > 40][:3]
    key_findings = " ".join(key_sentences)[:600] if key_sentences else ""

    return {
        "study_type": study_type,
        "species": species,
        "route": route,
        "noael": noael,
        "noael_unit": noael_unit,
        "ld50": ld50,
        "ld50_unit": ld50_unit,
        "duration": duration,
        "key_findings": key_findings,
        "ames_result": ames_result,
        "micronucleus_result": micronucleus_result,
        "herg_ic50_um": herg_ic50_um,
        "glp": glp,
        "study_id": study_id,
        "text_length": len(full_text),
    }


def _normalise_species(raw: str) -> str:
    raw = raw.lower()
    mapping = {
        "sprague": "rat", "wistar": "rat", "fischer": "rat", "rat": "rat",
        "mouse": "mouse", "mice": "mouse", "balb": "mouse", "c57": "mouse", "cd-1": "mouse",
        "beagle": "dog", "dog": "dog",
        "cynomolgus": "monkey", "monkey": "monkey",
        "rabbit": "rabbit", "hamster": "hamster",
        "guinea": "guinea pig", "minipig": "minipig", "pig": "pig",
    }
    for key, norm in mapping.items():
        if key in raw:
            return norm
    return raw.strip()


def _normalise_route(raw: str) -> str:
    raw = raw.lower()
    if "oral" in raw or "gavage" in raw:
        return "oral"
    if "iv" in raw or "intravenous" in raw:
        return "intravenous"
    if "sc" in raw or "subcutaneous" in raw:
        return "subcutaneous"
    if "inhalation" in raw:
        return "inhalation"
    if "dermal" in raw or "topical" in raw:
        return "dermal"
    if "im" in raw or "intramuscular" in raw:
        return "intramuscular"
    return raw.strip()


# ── Wetlab data merger ─────────────────────────────────────────────────────

def merge_study_into_wetlab(
    existing_wetlab: dict,
    extracted: dict,
) -> dict:
    """
    Merge newly extracted study data into the existing wetlab_data dict.
    Routing by study_type: single_dose → single_dose_study,
    repeat_dose_* → repeat_dose_studies list, ames → ames_result, herg → herg_ic50_uM.
    """
    merged = dict(existing_wetlab)
    st = extracted.get("study_type", "")

    if st == "single_dose":
        merged["single_dose_study"] = extracted

    elif st.startswith("repeat_dose"):
        studies = list(merged.get("repeat_dose_studies", []))
        studies.append(extracted)
        merged["repeat_dose_studies"] = studies

    elif st == "ames":
        merged["ames_result"] = extracted.get("ames_result")

    elif st == "micronucleus":
        if extracted.get("micronucleus_result") is not None:
            merged["micronucleus_result"] = extracted["micronucleus_result"]

    elif st == "herg":
        if extracted.get("herg_ic50_um") is not None:
            merged["herg_ic50_uM"] = extracted["herg_ic50_um"]

    elif st == "carcinogenicity":
        merged["carcinogenicity_study"] = extracted

    elif st == "reproductive":
        merged["reproductive_tox_study"] = extracted

    elif st == "pharmacokinetics":
        # Merge PK parameters into pk_summary
        pk = dict(merged.get("pk_summary", {}))
        if extracted.get("noael"):
            pk["measured_dose_mgkg"] = extracted["noael"]
        merged["pk_summary"] = pk

    else:
        # Generic: store in other_studies list
        others = list(merged.get("other_studies", []))
        others.append(extracted)
        merged["other_studies"] = others

    return merged
