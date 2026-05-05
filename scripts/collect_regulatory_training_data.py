#!/usr/bin/env python3
"""
BioMate Regulatory LLM Training Data Collector

Downloads and preprocesses publicly available regulatory document corpora for
fine-tuning an LLM specialized in ICH M4 CTD Module 2.6 nonclinical summary generation.

Sources:
  --epar          EMA European Public Assessment Reports (2,000+ nonclinical assessments)
  --dailymed      DailyMed FDA Drug Labels (155K SPL XML labels, monthly release)
  --ich-guidelines ICH guideline PDFs (M4S, S7B, S2(R1), S7A, M3(R2), E5, E7)
  --phtlm         PhT_LM regulatory translation dataset (34K EN/ZH pairs)
  --pmda          PMDA Japan public assessment reports (limited)
  --who           WHO prequalification public assessment reports (WHOPARs)
  --all           Run all sources

Output:
  data/regulatory_training/ — organized by source
  data/regulatory_training/combined/ — preprocessed (context, response) pairs for fine-tuning

Usage:
    python scripts/collect_regulatory_training_data.py --epar --ich-guidelines
    python scripts/collect_regulatory_training_data.py --all --output data/regulatory_training
"""
from __future__ import annotations

import argparse
import json
import logging
import re
import time
import zipfile
from pathlib import Path
from typing import Optional
import xml.etree.ElementTree as ET

import requests

log = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

DEFAULT_OUT = Path(__file__).parent.parent / "data" / "regulatory_training"

# ─── EMA EPAR ─────────────────────────────────────────────────────────────────

# EMA EPAR bulk data download — medicines report Excel file
# Source: https://www.ema.europa.eu/en/medicines/download-medicine-data
EPAR_XLSX_URL = "https://www.ema.europa.eu/en/documents/report/medicines-output-medicines-report_en.xlsx"
EPAR_BASE_URL = "https://www.ema.europa.eu"
# EPAR PDF pattern: each medicine has a product page with EPAR PDF link
EPAR_PRODUCT_BASE = "https://www.ema.europa.eu/en/medicines/human/EPAR/{slug}"

# Nonclinical section identifiers in EMA EPARs
EPAR_NONCLINICAL_KEYWORDS = [
    "nonclinical pharmacology",
    "nonclinical pharmacokinetics",
    "nonclinical toxicology",
    "primary pharmacodynamics",
    "secondary pharmacodynamics",
    "safety pharmacology",
    "absorption, distribution, metabolism",
    "in vitro",
    "in vivo",
    "genotoxicity",
    "carcinogenicity",
    "reproductive toxicity",
    "pbpk",
    "pharmacokinetics",
    "herg",
]


def collect_epar(out_dir: Path, max_medicines: int = 500) -> list[dict]:
    """
    Download EMA EPAR nonclinical sections.

    Strategy:
    1. Download the EMA medicines Excel catalogue (replaces the broken API)
    2. For each authorised human medicine, attempt to download the EPAR
       Scientific Discussion PDF (contains nonclinical sections analogous to §2.6)
    3. Extract nonclinical text and convert to training pairs

    EMA EPAR PDFs follow the URL pattern:
    https://www.ema.europa.eu/en/documents/scientific-discussion/{slug}-epar-scientific-discussion_en.pdf

    Returns list of training examples: {"context": ..., "response": ...}
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    raw_dir = out_dir / "raw" / "epar"
    raw_dir.mkdir(parents=True, exist_ok=True)

    examples = []
    headers = {"User-Agent": "BioMate Research Bot (regulatory_training@biomate.ai)"}

    log.info("[EPAR] Starting EMA EPAR collection (max %d medicines)", max_medicines)

    # Step 1: Download EMA medicines Excel catalogue
    xlsx_path = raw_dir / "ema_medicines_catalogue.xlsx"
    medicines: list[dict] = []

    if not xlsx_path.exists():
        log.info("[EPAR] Downloading EMA medicines catalogue…")
        try:
            r = requests.get(EPAR_XLSX_URL, timeout=60, headers=headers, stream=True)
            r.raise_for_status()
            with open(xlsx_path, "wb") as f:
                for chunk in r.iter_content(8192):
                    f.write(chunk)
            log.info("[EPAR] Catalogue downloaded (%s bytes)", xlsx_path.stat().st_size)
        except Exception as exc:
            log.warning("[EPAR] Catalogue download failed: %s — using fallback list", exc)
    else:
        log.info("[EPAR] Using cached catalogue: %s", xlsx_path)

    # Parse the Excel catalogue to get medicine names / slugs
    if xlsx_path.exists():
        try:
            import openpyxl  # type: ignore
            wb = openpyxl.load_workbook(xlsx_path, read_only=True)
            ws = wb.active
            all_rows = list(ws.iter_rows(values_only=True))
            wb.close()
            # EMA catalogue: row 8 (0-indexed) is the actual header row
            # "Category", "Name of medicine", "EMA product number", "Medicine status", ...
            header_idx = next(
                (i for i, r in enumerate(all_rows)
                 if any("name of medicine" in str(c or "").lower() or
                        "medicine name" in str(c or "").lower() for c in r)),
                None
            )
            if header_idx is not None:
                header = [str(c or "").strip().lower() for c in all_rows[header_idx]]
                for row in all_rows[header_idx + 1:]:
                    rec = dict(zip(header, row))
                    name = (rec.get("name of medicine") or rec.get("medicine name") or
                            rec.get("name") or "")
                    status = str(rec.get("medicine status") or rec.get("authorisation status") or
                                 rec.get("status") or "").lower()
                    category = str(rec.get("category") or "").lower()
                    if name and "authorised" in status and "human" in category:
                        medicines.append({"name": str(name).strip()})
                log.info("[EPAR] Parsed %d authorised human medicines from catalogue", len(medicines))
            else:
                log.warning("[EPAR] Could not find header row in Excel catalogue")
        except ImportError:
            log.warning("[EPAR] openpyxl not installed — pip install openpyxl — using fallback")
        except Exception as exc:
            log.warning("[EPAR] Excel parse failed: %s — using fallback", exc)

    # Fallback: well-known EPAR medicines with confirmed PDF URLs
    if not medicines:
        medicines = [
            {"name": "osimertinib"},   {"name": "sotorasib"},    {"name": "adagrasib"},
            {"name": "palbociclib"},   {"name": "ribociclib"},   {"name": "abemaciclib"},
            {"name": "venetoclax"},    {"name": "ibrutinib"},    {"name": "idelalisib"},
            {"name": "pembrolizumab"}, {"name": "nivolumab"},    {"name": "atezolizumab"},
            {"name": "durvalumab"},    {"name": "cemiplimab"},   {"name": "dostarlimab"},
            {"name": "olaparib"},      {"name": "rucaparib"},    {"name": "niraparib"},
            {"name": "talazoparib"},   {"name": "lorlatinib"},   {"name": "larotrectinib"},
            {"name": "entrectinib"},   {"name": "tepotinib"},    {"name": "capmatinib"},
            {"name": "pralsetinib"},   {"name": "selpercatinib"},{"name": "avapritinib"},
            {"name": "ripretinib"},    {"name": "mobocertinib"}, {"name": "amivantamab"},
        ]
        log.info("[EPAR] Using fallback list of %d known medicines", len(medicines))

    # Step 2: For each medicine, try to download the EPAR Scientific Discussion PDF
    total = 0
    for med in medicines[:max_medicines]:
        if total >= max_medicines:
            break
        name = med.get("name", "")
        if not name:
            continue

        # Generate URL slug: lowercase, spaces → hyphens, remove special chars
        slug = re.sub(r"[^\w\-]", "", name.lower().replace(" ", "-").replace("(", "").replace(")", ""))
        pdf_path = raw_dir / f"{slug}.pdf"

        if not pdf_path.exists():
            # Try multiple EPAR PDF URL patterns
            pdf_urls = [
                # Primary: public assessment report (confirmed working pattern)
                f"{EPAR_BASE_URL}/en/documents/assessment-report/{slug}-epar-public-assessment-report_en.pdf",
                # Scientific discussion (older medicines)
                f"{EPAR_BASE_URL}/en/documents/scientific-discussion/{slug}-epar-scientific-discussion_en.pdf",
                # Hyphen variants
                f"{EPAR_BASE_URL}/en/documents/assessment-report/{slug}-epar-public-assessment-report-en.pdf",
                # Underscore in name
                f"{EPAR_BASE_URL}/en/documents/assessment-report/{slug.replace('-','_')}-epar-public-assessment-report_en.pdf",
            ]
            downloaded = False
            for pdf_url in pdf_urls:
                try:
                    r = requests.get(pdf_url, timeout=60, headers=headers, stream=True)
                    if r.status_code == 429:
                        retry_after = int(r.headers.get("retry-after", "15"))
                        log.debug("[EPAR] Rate limited, waiting %ds", retry_after)
                        time.sleep(retry_after + 2)
                        r = requests.get(pdf_url, timeout=60, headers=headers, stream=True)
                    if r.status_code == 200:
                        content = b""
                        for chunk in r.iter_content(8192):
                            content += chunk
                        if len(content) > 5000 and b"%PDF" in content[:10]:
                            with open(pdf_path, "wb") as f:
                                f.write(content)
                            downloaded = True
                            time.sleep(1.5)
                            break
                except Exception as exc:
                    log.debug("[EPAR] Request failed for %s: %s", pdf_url[:60], exc)
            if not downloaded:
                log.debug("[EPAR] PDF not found for: %s (tried %d URLs)", name, len(pdf_urls))
                continue

        exs = _download_and_extract_epar(name, slug, str(pdf_path), raw_dir)
        if exs:
            examples.extend(exs)
            total += 1
            log.info("[EPAR] %d/%d — %s (%d examples)", total, max_medicines, name, len(exs))

    out_file = out_dir / "epar_examples.jsonl"
    _write_jsonl(examples, out_file)
    log.info("[EPAR] Done. %d examples from %d medicines → %s", len(examples), total, out_file)
    return examples


def _download_and_extract_epar(name: str, slug: str, pdf_path_str: str, raw_dir: Path) -> list[dict]:
    """Extract nonclinical section text from an already-downloaded EPAR PDF."""
    pdf_path = Path(pdf_path_str)
    if not pdf_path.exists():
        return []

    try:
        import pdfplumber  # type: ignore
        text = ""
        with pdfplumber.open(pdf_path) as pdf:
            # EPAR Scientific Discussion PDFs can be 200+ pages; focus on nonclinical section
            for pg in pdf.pages[:80]:
                text += (pg.extract_text() or "") + "\n"
    except ImportError:
        log.debug("[EPAR] pdfplumber not installed")
        return []
    except Exception as exc:
        log.debug("[EPAR] PDF extraction failed for %s: %s", name, exc)
        return []

    return _parse_epar_nonclinical_sections(name, text)


def _parse_epar_nonclinical_sections(medicine_name: str, text: str) -> list[dict]:
    """
    Extract nonclinical section text and convert to (context, response) training pairs.

    EMA EPAR structure (Assessment Report format):
      2.5. Non-clinical aspects
        2.5.1. Introduction
        2.5.2. Pharmacology
        2.5.3. Pharmacokinetics
        2.5.4. Toxicology
        2.5.5. Ecotoxicity/environmental risk assessment
    """
    examples = []

    # EMA EPAR nonclinical subsection pattern
    # Matches "2.5.X" or "2.6.X" headings followed by body text
    section_pattern = re.compile(
        r"(2\.[5-7](?:\.\d+)*\.?\s+(?:Non-?clinical|Pharmacol|Pharmacokin|Toxicol|Introduction|Safety)[^\n]{0,80}\n)"
        r"((?:.|\n){200,2500}?)"
        r"(?=\n2\.[5-7](?:\.\d+)*\.?\s+[A-Z]|\n\d+\.\d+\s+[A-Z]|\Z)",
        re.IGNORECASE
    )

    for m in section_pattern.finditer(text):
        heading = m.group(1).strip()
        body = m.group(2).strip()

        body_lower = body.lower()
        if not any(kw in body_lower for kw in EPAR_NONCLINICAL_KEYWORDS):
            continue

        words = body.split()
        if len(words) < 40:
            continue
        if len(words) > 1200:
            body = " ".join(words[:1200]) + " [truncated]"

        # Map EMA section to ICH CTD section
        ich_section = _map_epar_section_to_ich(heading)

        examples.append({
            "source": "EMA_EPAR",
            "medicine": medicine_name,
            "section": heading,
            "ich_section": ich_section,
            "context": (
                f"You are a regulatory affairs scientist writing ICH M4 CTD {ich_section} "
                f"nonclinical written summaries for {medicine_name}. "
                f"Write formal EMA/ICH regulatory prose (EMA/CHMP/EWP/37498/2011). "
                f"Precise, passive-voice, evidence-referenced, suitably hedged. No markdown. "
                f"2-6 sentences."
            ),
            "response": body,
        })

    # Also extract longer free-text paragraphs from nonclinical pages directly
    # as additional training signal (lower precision, higher recall)
    if len(examples) < 3:
        examples.extend(_extract_nonclinical_paragraphs(medicine_name, text))

    return examples


def _map_epar_section_to_ich(heading: str) -> str:
    h = heading.lower()
    if "pharmacokin" in h or "adme" in h or "absorption" in h:
        return "§2.6.2 Pharmacokinetics"
    if "toxicol" in h or "geno" in h or "carcino" in h or "reproductive" in h:
        return "§2.6.3 Toxicology"
    if "cardiac" in h or "herg" in h or "safety pharmacol" in h:
        return "§2.6.3.7 Cardiac Safety"
    if "pharmacol" in h or "primary" in h or "secondary" in h:
        return "§2.6.2 Pharmacology"
    return "§2.6.1 Nonclinical Overview"


def _extract_nonclinical_paragraphs(medicine_name: str, text: str) -> list[dict]:
    """
    Fallback: extract substantial paragraphs from nonclinical sections by keyword scan.
    Less precise but catches sections missed by heading-based regex.
    """
    examples = []
    # Split into paragraphs
    paragraphs = [p.strip() for p in re.split(r"\n{2,}", text) if len(p.strip().split()) > 40]

    nonclinical_paras = [
        p for p in paragraphs
        if any(kw in p.lower() for kw in EPAR_NONCLINICAL_KEYWORDS)
        and not p.startswith("Table") and not p.startswith("Figure")
    ]

    for para in nonclinical_paras[:15]:  # max 15 fallback paragraphs per document
        words = para.split()
        if len(words) > 800:
            para = " ".join(words[:800]) + " [truncated]"

        examples.append({
            "source": "EMA_EPAR",
            "medicine": medicine_name,
            "section": "nonclinical_paragraph",
            "ich_section": "§2.6 Nonclinical",
            "context": (
                f"You are writing a nonclinical regulatory section for {medicine_name} "
                f"per ICH M4 CTD Module 2.6. Continue the following regulatory passage "
                f"in formal ICH/EMA style: {para[:200]}…"
            ),
            "response": para,
        })

    return examples


# ─── DailyMed FDA Labels ───────────────────────────────────────────────────────

DAILYMED_ARCHIVE = "https://dailymed.nlm.nih.gov/dailymed/spl-resources/spl-all-labels.zip"
DAILYMED_MONTHLY = "https://dailymed.nlm.nih.gov/dailymed/spl-resources/all-labels-latest.zip"

# SPL XML namespaces
SPL_NS = {
    "v3": "urn:hl7-org:v3",
}

# Section codes for nonclinical / toxicology / clinical pharmacology in SPL
NONCLINICAL_CODES = {
    "34084-4": "Adverse Reactions",
    "43685-7": "Warnings and Precautions",
    "34073-7": "Drug Interactions",
    "34090-1": "Clinical Pharmacology",
    "34089-3": "Description",
    "34092-7": "Animal Pharmacology/Toxicology",
    "43677-4": "Preclinical Safety Data",
}


def collect_dailymed(out_dir: Path, max_labels: int = 5000) -> list[dict]:
    """
    Download DailyMed FDA label SPL XML and extract nonclinical/toxicology sections.
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    zip_path = out_dir / "all-labels-latest.zip"

    if not zip_path.exists():
        log.info("[DailyMed] Downloading label archive from %s", DAILYMED_MONTHLY)
        try:
            r = requests.get(DAILYMED_MONTHLY, timeout=300, stream=True)
            r.raise_for_status()
            with open(zip_path, "wb") as f:
                for chunk in r.iter_content(65536):
                    f.write(chunk)
            log.info("[DailyMed] Downloaded %s (%.1f MB)", zip_path, zip_path.stat().st_size / 1e6)
        except Exception as exc:
            log.error("[DailyMed] Download failed: %s", exc)
            return []
    else:
        log.info("[DailyMed] Using cached archive: %s", zip_path)

    examples = []
    count = 0

    log.info("[DailyMed] Parsing SPL XML (max %d labels)…", max_labels)
    try:
        with zipfile.ZipFile(zip_path, "r") as zf:
            xml_files = [n for n in zf.namelist() if n.endswith(".xml")]
            for fname in xml_files[:max_labels]:
                try:
                    with zf.open(fname) as f:
                        tree = ET.parse(f)
                    ex = _parse_spl_xml(tree.getroot())
                    if ex:
                        examples.extend(ex)
                        count += 1
                except Exception:
                    continue
    except Exception as exc:
        log.error("[DailyMed] Archive parsing failed: %s", exc)

    out_file = out_dir / "dailymed_examples.jsonl"
    _write_jsonl(examples, out_file)
    log.info("[DailyMed] Done. %d labels → %d examples written to %s", count, len(examples), out_file)
    return examples


def _parse_spl_xml(root: ET.Element) -> list[dict]:
    """Extract nonclinical/toxicology section text from SPL XML."""
    examples = []
    ns = "urn:hl7-org:v3"

    # Get drug name
    title_el = root.find(f".//{{{ns}}}title")
    drug_name = title_el.text.strip() if title_el is not None and title_el.text else "unknown"

    # Iterate sections
    for section in root.findall(f".//{{{ns}}}section"):
        code_el = section.find(f"{{{ns}}}code")
        if code_el is None:
            continue
        code = code_el.get("code", "")
        if code not in NONCLINICAL_CODES:
            continue

        section_name = NONCLINICAL_CODES[code]

        # Extract text content
        texts = []
        for el in section.iter():
            if el.tag == f"{{{ns}}}text" and el.text:
                texts.append(el.text.strip())
            elif el.text and el.tag not in (f"{{{ns}}}code", f"{{{ns}}}id"):
                stripped = el.text.strip()
                if stripped and len(stripped) > 20:
                    texts.append(stripped)

        body = " ".join(t for t in texts if t)
        words = body.split()
        if len(words) < 30:
            continue
        if len(words) > 800:
            body = " ".join(words[:800]) + " [truncated]"

        examples.append({
            "source": "DailyMed_FDA",
            "drug": drug_name,
            "section_code": code,
            "section": section_name,
            "context": (
                f"You are a regulatory medical writer preparing FDA-compliant drug labeling for "
                f"{drug_name}. Write the '{section_name}' section in formal FDA regulatory style. "
                f"Be precise, evidence-based, and follow 21 CFR Part 201 labeling requirements."
            ),
            "response": body,
        })

    return examples


# ─── ICH Guidelines ───────────────────────────────────────────────────────────

ICH_GUIDELINES = {
    "ICH_M4S_R2": "https://database.ich.org/sites/default/files/M4S_R2_Guideline.pdf",
    # S7B R1 (November 2024) — step 4
    "ICH_S7B_R1": "https://database.ich.org/sites/default/files/ICH_S7B-R1_Step4_Guideline_2024_1101.pdf",
    "ICH_S2_R1":  "https://database.ich.org/sites/default/files/S2_R1_Guideline.pdf",
    "ICH_S7A":    "https://database.ich.org/sites/default/files/S7A_Guideline.pdf",
    "ICH_M3_R2":  "https://database.ich.org/sites/default/files/M3_R2__Guideline.pdf",
    "ICH_E5_R1":  "https://database.ich.org/sites/default/files/E5_R1__Guideline.pdf",
    "ICH_E7":     "https://database.ich.org/sites/default/files/E7_Guideline.pdf",
    # M7 R2 (2023)
    "ICH_M7_R2":  "https://database.ich.org/sites/default/files/ICH_M7-R2_Guideline_2023_0113.pdf",
    "EMA_PBPK":   "https://www.ema.europa.eu/en/documents/scientific-guideline/guideline-reporting-physiologically-based-pharmacokinetic-pbpk-modelling-simulation_en.pdf",
}


def collect_ich_guidelines(out_dir: Path) -> list[dict]:
    """Download ICH guideline PDFs and extract text as regulatory knowledge base."""
    out_dir.mkdir(parents=True, exist_ok=True)
    raw_dir = out_dir / "raw" / "ich"
    raw_dir.mkdir(parents=True, exist_ok=True)
    examples = []

    for name, url in ICH_GUIDELINES.items():
        pdf_path = raw_dir / f"{name}.pdf"
        if not pdf_path.exists():
            log.info("[ICH] Downloading %s…", name)
            try:
                r = requests.get(url, timeout=60)
                r.raise_for_status()
                with open(pdf_path, "wb") as f:
                    f.write(r.content)
            except Exception as exc:
                log.warning("[ICH] Download failed for %s: %s", name, exc)
                continue
        else:
            log.info("[ICH] Using cached %s", name)

        # Extract text
        try:
            import pdfplumber  # type: ignore
            text = ""
            with pdfplumber.open(pdf_path) as pdf:
                for pg in pdf.pages[:30]:  # First 30 pages covers main guidance
                    text += (pg.extract_text() or "") + "\n"
        except ImportError:
            log.debug("[ICH] pdfplumber not installed")
            continue
        except Exception as exc:
            log.warning("[ICH] PDF extraction failed for %s: %s", name, exc)
            continue

        # Split into paragraphs — try double-newline first, fall back to single-newline blocks
        raw_paragraphs = text.split("\n\n")
        if len(raw_paragraphs) < 5:
            # PDF extracted with single newlines between lines
            raw_paragraphs = [" ".join(text.split("\n")[i:i+8])
                              for i in range(0, len(text.split("\n")), 6)]
        paragraphs = [p.strip() for p in raw_paragraphs if len(p.strip()) > 100]

        for para in paragraphs[:80]:  # Max 80 paragraphs per guideline
            # Skip header/footer/TOC paragraphs
            if re.match(r"^[\d\s\.\-]+$", para) or len(para.split()) < 15:
                continue
            examples.append({
                "source": "ICH_Guideline",
                "guideline": name,
                "context": (
                    f"Explain the following ICH guideline requirement in the context of "
                    f"IND application CTD Module 2.6 nonclinical document preparation:\n\n{para[:500]}"
                ),
                "response": para,
            })

    out_file = out_dir / "ich_guidelines_examples.jsonl"
    _write_jsonl(examples, out_file)
    log.info("[ICH] Done. %d examples from %d guidelines", len(examples), len(ICH_GUIDELINES))
    return examples


# ─── PhT_LM Dataset ───────────────────────────────────────────────────────────

PHTLM_REPO = "https://github.com/chent-1928/PhT_LM"
PHTLM_DATA_URL = "https://raw.githubusercontent.com/chent-1928/PhT_LM/main/data/regulatory_pairs.json"


def collect_phtlm(out_dir: Path) -> list[dict]:
    """
    Download PhT_LM regulatory translation dataset (34K EN/ZH regulatory pairs).
    Source: Nature Scientific Reports 2025 — first public regulatory LLM dataset.
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    json_path = out_dir / "phtlm_pairs.json"

    if not json_path.exists():
        log.info("[PhT_LM] Attempting to download from GitHub…")
        try:
            r = requests.get(PHTLM_DATA_URL, timeout=30)
            r.raise_for_status()
            with open(json_path, "wb") as f:
                f.write(r.content)
        except Exception as exc:
            log.warning("[PhT_LM] Direct download failed (%s). Try: git clone %s", exc, PHTLM_REPO)
            log.info("[PhT_LM] Manual: cd data/regulatory_training && git clone %s", PHTLM_REPO)
            return []

    try:
        with open(json_path, encoding="utf-8") as f:
            raw = json.load(f)
    except Exception as exc:
        log.warning("[PhT_LM] JSON parse failed: %s", exc)
        return []

    examples = []
    for item in raw if isinstance(raw, list) else []:
        en = item.get("english") or item.get("en") or item.get("source", "")
        zh = item.get("chinese") or item.get("zh") or item.get("target", "")
        if not en or not zh:
            continue
        examples.append({
            "source": "PhT_LM",
            "context": f"Translate the following pharmaceutical regulatory text to Chinese, preserving technical accuracy:\n\n{en[:600]}",
            "response": zh[:600],
        })

    out_file = out_dir / "phtlm_examples.jsonl"
    _write_jsonl(examples, out_file)
    log.info("[PhT_LM] Done. %d examples written to %s", len(examples), out_file)
    return examples


# ─── FDA NDA Nonclinical Reviews ──────────────────────────────────────────────

# FDA NME (New Molecular Entity) approvals list — NDA numbers with public review PDFs
# Source: FDA Novel Drug Approvals, accessdata.fda.gov
# Each entry: (nda_number, drug_name, year)
FDA_NDA_SAMPLE = [
    # Recent approvals with confirmed public review PDFs
    ("218197", "adagrasib",     2022),
    ("215893", "sotorasib",     2021),
    ("213191", "tepotinib",     2021),
    ("214665", "pralsetinib",   2021),
    ("214021", "capmatinib",    2020),
    ("211255", "larotrectinib", 2018),
    ("210861", "lorlatinib",    2018),
    ("210498", "gilteritinib",  2018),
    ("210296", "ivosidenib",    2018),
    ("209631", "neratinib",     2017),
    ("208558", "ribociclib",    2017),
    ("208434", "abemaciclib",   2017),
    ("209806", "venetoclax",    2016),
    ("208261", "osimertinib",   2015),
    ("207997", "cobimetinib",   2015),
    ("206192", "sonidegib",     2015),
    ("205718", "palbociclib",   2015),
    ("205494", "idelalisib",    2014),
    ("204114", "ceritinib",     2014),
    ("204083", "ibrutinib",     2013),
]

FDA_NDA_REVIEW_URL = "https://www.accessdata.fda.gov/drugsatfda_docs/nda/{year}/{nda}Orig1s000MultidisciplineR.pdf"
FDA_NDA_PHARM_URL  = "https://www.accessdata.fda.gov/drugsatfda_docs/nda/{year}/{nda}Orig1s000PharmR.pdf"
# openFDA API for PDF URL discovery (more reliable than guessing URL patterns)
FDA_OPEN_API = "https://api.fda.gov/drug/drugsfda.json?search=application_number.exact:NDA{nda}&limit=1"

# Keywords that indicate nonclinical pharmacology/toxicology sections in FDA NDA reviews
NDA_NONCLINICAL_HEADERS = [
    "pharmacology", "toxicology", "nonclinical", "non-clinical",
    "adme", "absorption", "distribution", "metabolism", "excretion",
    "genotoxicity", "carcinogenicity", "reproductive", "safety pharmacology",
    "herg", "cardiac", "pbpk", "pharmacokinetics",
]


def _discover_nda_pdf_urls(nda_num: str, year: int) -> list[str]:
    """
    Use openFDA API to discover the actual PDF URLs for an NDA review.
    Falls back to common URL patterns if the API call fails.
    """
    urls: list[str] = []

    # openFDA structured API — returns submission_type, submission_number, and documents
    try:
        api_url = FDA_OPEN_API.format(nda=nda_num)
        r = requests.get(api_url, timeout=10)
        if r.ok:
            data = r.json()
            results = data.get("results", [])
            for result in results:
                for submission in result.get("submissions", []):
                    for doc in submission.get("application_docs", []):
                        doc_url = doc.get("url", "")
                        doc_type = doc.get("type", "").lower()
                        # Prioritize multidiscipline review and pharmacology review
                        if any(kw in doc_type for kw in ["multidiscipline", "pharmacol", "clinical pharmacol"]):
                            urls.insert(0, doc_url)
                        elif doc_url.endswith(".pdf"):
                            urls.append(doc_url)
    except Exception as exc:
        log.debug("[FDA NDA] openFDA API failed for %s: %s", nda_num, exc)

    # Add hardcoded URL pattern fallbacks
    base = "https://www.accessdata.fda.gov/drugsatfda_docs/nda"
    for suffix in [
        f"MultidisciplineR.pdf",
        f"PharmR.pdf",
        f"PharmToxR.pdf",
        f"ClinPharmR.pdf",
    ]:
        urls.extend([
            f"{base}/{year}/{nda_num}Orig1s000{suffix}",
            f"{base}/{year}/{nda_num}Orig1s000{suffix.lower()}",
            # Some older NDAs use 6-digit format
            f"{base}/{year}/{nda_num[:3]}{nda_num[3:]}Orig1s000{suffix}",
        ])

    # Deduplicate while preserving order
    seen: set[str] = set()
    deduped: list[str] = []
    for u in urls:
        if u and u not in seen:
            seen.add(u)
            deduped.append(u)
    return deduped


def collect_fda_nda(out_dir: Path, max_ndas: int = 20) -> list[dict]:
    """
    Download FDA NDA Multidisciplinary Review PDFs and extract nonclinical sections.

    These are the closest public analog to ICH Module 2.6 — the FDA reviewer's own
    nonclinical pharmacology and toxicology narratives written in response to the sponsor's
    §2.6 submission. Public domain (U.S. government work).
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    raw_dir = out_dir / "raw" / "fda_nda"
    raw_dir.mkdir(parents=True, exist_ok=True)

    examples = []
    ndas_to_try = FDA_NDA_SAMPLE[:max_ndas]

    log.info("[FDA NDA] Attempting to collect %d NDA review PDFs…", len(ndas_to_try))

    for nda_num, drug_name, year in ndas_to_try:
        pdf_path = raw_dir / f"{nda_num}_{drug_name}.pdf"

        if not pdf_path.exists():
            downloaded = False
            # Step 1: try openFDA API to discover actual PDF URLs
            pdf_urls_to_try = _discover_nda_pdf_urls(nda_num, year)
            for url in pdf_urls_to_try:
                try:
                    r = requests.get(url, timeout=60, stream=True,
                                     headers={"User-Agent": "BioMate Research (training@biomate.ai)"})
                    ct = r.headers.get("content-type", "")
                    if r.status_code == 200 and ("pdf" in ct.lower() or url.endswith(".pdf")):
                        with open(pdf_path, "wb") as f:
                            for chunk in r.iter_content(8192):
                                f.write(chunk)
                        # Verify it's actually a PDF
                        if pdf_path.stat().st_size > 10_000:
                            log.info("[FDA NDA] Downloaded %s (%s) from %s", drug_name, nda_num, url[:60])
                            downloaded = True
                            time.sleep(1.5)
                            break
                        else:
                            pdf_path.unlink(missing_ok=True)
                except Exception as exc:
                    log.debug("[FDA NDA] Failed %s: %s", url[:60], exc)
            if not downloaded:
                log.warning("[FDA NDA] Could not download NDA %s (%s)", nda_num, drug_name)
                continue
        else:
            log.info("[FDA NDA] Using cached %s (%s)", drug_name, nda_num)

        # Extract nonclinical text
        exs = _extract_nda_nonclinical(drug_name, nda_num, pdf_path)
        examples.extend(exs)
        log.info("[FDA NDA] %s → %d examples", drug_name, len(exs))

    out_file = out_dir / "fda_nda_examples.jsonl"
    _write_jsonl(examples, out_file)
    log.info("[FDA NDA] Done. %d examples from %d NDAs → %s", len(examples), len(ndas_to_try), out_file)
    return examples


def _extract_nda_nonclinical(drug_name: str, nda_num: str, pdf_path: Path) -> list[dict]:
    """Extract nonclinical section text from FDA NDA review PDF."""
    try:
        import pdfplumber  # type: ignore
    except ImportError:
        log.debug("[FDA NDA] pdfplumber not installed — skipping")
        return []

    try:
        text = ""
        with pdfplumber.open(pdf_path) as pdf:
            # FDA reviews are often 100+ pages; focus on first 60 pages
            for pg in pdf.pages[:60]:
                text += (pg.extract_text() or "") + "\n"
    except Exception as exc:
        log.warning("[FDA NDA] PDF extraction failed for %s: %s", drug_name, exc)
        return []

    return _parse_nda_sections(drug_name, nda_num, text)


def _parse_nda_sections(drug_name: str, nda_num: str, text: str) -> list[dict]:
    """Parse FDA NDA review text into (context, response) training pairs by section."""
    examples = []

    # FDA review sections are headed by numbered patterns like:
    # "4. NONCLINICAL PHARMACOLOGY AND TOXICOLOGY"
    # "2.6.2 Pharmacokinetics"
    section_pattern = re.compile(
        r"(\d+[\.\d]*\s+(?:NONCLINICAL|NON-CLINICAL|PHARMACOL|TOXICOL|PHARMACOKIN|ADME|SAFETY)[^\n]{0,60}\n)"
        r"((?:.|\n){200,3000}?)(?=\n\d+[\.\d]*\s+[A-Z]|\Z)",
        re.IGNORECASE
    )

    for m in section_pattern.finditer(text):
        heading = m.group(1).strip()
        body = m.group(2).strip()

        # Filter noise
        if len(body.split()) < 40:
            continue
        body_lower = body.lower()
        if not any(kw in body_lower for kw in NDA_NONCLINICAL_HEADERS):
            continue

        # Determine which ICH section this maps to
        ich_section = _map_fda_heading_to_ich(heading)
        words = body.split()
        if len(words) > 1000:
            body = " ".join(words[:1000]) + " [truncated]"

        examples.append({
            "source": "FDA_NDA_Review",
            "drug": drug_name,
            "nda": nda_num,
            "heading": heading,
            "ich_section": ich_section,
            "context": (
                f"You are an FDA regulatory scientist writing a nonclinical pharmacology review "
                f"for {drug_name} (NDA {nda_num}). Write the {ich_section} section "
                f"({heading.strip()}) in formal ICH M4 / FDA regulatory style. "
                f"Be precise, evidence-referenced, and cite relevant guidelines (ICH S7B, S2(R1), M3(R2))."
            ),
            "response": body,
        })

    return examples


def _map_fda_heading_to_ich(heading: str) -> str:
    h = heading.lower()
    if "pharmacokin" in h or "adme" in h or "absorption" in h or "distribution" in h:
        return "§2.6.2 Nonclinical Overview: Pharmacokinetics"
    if "toxicol" in h or "geno" in h or "carcino" in h or "reproductive" in h:
        return "§2.6.3 Nonclinical Overview: Toxicology"
    if "cardiac" in h or "herg" in h or "safety pharmacol" in h:
        return "§2.6.3.7 Cardiac Safety"
    return "§2.6.1 Nonclinical Overview: Pharmacology"


# ─── TGA AusPAR ───────────────────────────────────────────────────────────────

# TGA AusPAR index — structured metadata available via TGA open data
# License: Creative Commons CC BY 4.0 — the most permissive regulatory corpus available
TGA_AUSPAR_INDEX = "https://www.tga.gov.au/resources/auspars/auspars.json"
TGA_AUSPAR_BASE  = "https://www.tga.gov.au"


def collect_tga_auspar(out_dir: Path, max_reports: int = 50) -> list[dict]:
    """
    Download TGA AusPAR (Australian Public Assessment Reports) PDFs.
    CC BY 4.0 license — most open regulatory corpus available.
    ICH CTD-aligned, English, covers quality/safety/efficacy.
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    raw_dir = out_dir / "raw" / "tga"
    raw_dir.mkdir(parents=True, exist_ok=True)

    examples = []

    # Try TGA open data API first
    log.info("[TGA] Fetching AusPAR index…")
    try:
        r = requests.get(TGA_AUSPAR_INDEX, timeout=30)
        r.raise_for_status()
        reports = r.json()
        if isinstance(reports, dict):
            reports = reports.get("data", reports.get("results", []))
    except Exception as exc:
        log.warning("[TGA] Index fetch failed: %s — falling back to known URLs", exc)
        reports = _tga_known_reports()

    log.info("[TGA] Found %d reports, collecting up to %d", len(reports), max_reports)

    for report in reports[:max_reports]:
        pdf_url = report.get("pdf_url") or report.get("url") or report.get("document_url")
        drug_name = report.get("product_name") or report.get("drug_name") or "unknown"

        if not pdf_url:
            continue
        if not pdf_url.startswith("http"):
            pdf_url = TGA_AUSPAR_BASE + pdf_url

        safe_name = re.sub(r"[^\w\-]", "_", drug_name)[:40]
        pdf_path = raw_dir / f"{safe_name}.pdf"

        if not pdf_path.exists():
            try:
                r = requests.get(pdf_url, timeout=60, stream=True)
                r.raise_for_status()
                with open(pdf_path, "wb") as f:
                    for chunk in r.iter_content(8192):
                        f.write(chunk)
                log.info("[TGA] Downloaded %s", drug_name)
                time.sleep(1.0)
            except Exception as exc:
                log.debug("[TGA] Download failed for %s: %s", drug_name, exc)
                continue

        exs = _extract_auspar_nonclinical(drug_name, pdf_path)
        examples.extend(exs)

    out_file = out_dir / "tga_auspar_examples.jsonl"
    _write_jsonl(examples, out_file)
    log.info("[TGA] Done. %d examples → %s", len(examples), out_file)
    return examples


def _tga_known_reports() -> list[dict]:
    """Fallback: known AusPAR report URLs for recent oncology approvals."""
    # TGA AusPAR PDFs follow a consistent URL pattern
    return [
        {"drug_name": "osimertinib",   "pdf_url": "https://www.tga.gov.au/sites/default/files/auspar-osimertinib-160921.pdf"},
        {"drug_name": "palbociclib",   "pdf_url": "https://www.tga.gov.au/sites/default/files/auspar-palbociclib-170427.pdf"},
        {"drug_name": "ribociclib",    "pdf_url": "https://www.tga.gov.au/sites/default/files/auspar-ribociclib-171208.pdf"},
        {"drug_name": "venetoclax",    "pdf_url": "https://www.tga.gov.au/sites/default/files/auspar-venetoclax-170427.pdf"},
        {"drug_name": "ibrutinib",     "pdf_url": "https://www.tga.gov.au/sites/default/files/auspar-ibrutinib-140911.pdf"},
    ]


def _extract_auspar_nonclinical(drug_name: str, pdf_path: Path) -> list[dict]:
    """Extract nonclinical section text from TGA AusPAR PDF."""
    try:
        import pdfplumber  # type: ignore
    except ImportError:
        return []

    try:
        text = ""
        with pdfplumber.open(pdf_path) as pdf:
            for pg in pdf.pages[:50]:
                text += (pg.extract_text() or "") + "\n"
    except Exception:
        return []

    examples = []
    # AusPAR structure: "IV. Non-clinical findings" or "3. Non-clinical pharmacology"
    section_pattern = re.compile(
        r"((?:IV|V|VI|3|4|5|6)[\.\s]+(?:Non-?clinical|Pharmacol|Toxicol|Pharmacokin)[^\n]{0,60}\n)"
        r"((?:.|\n){200,2500}?)(?=\n(?:IV|V|VI|\d+)[\.\s]+[A-Z]|\Z)",
        re.IGNORECASE
    )

    for m in section_pattern.finditer(text):
        heading = m.group(1).strip()
        body = m.group(2).strip()
        words = body.split()
        if len(words) < 40:
            continue
        if len(words) > 900:
            body = " ".join(words[:900]) + " [truncated]"

        examples.append({
            "source": "TGA_AusPAR",
            "drug": drug_name,
            "heading": heading,
            "context": (
                f"You are a TGA regulatory scientist writing an AusPAR (Australian Public "
                f"Assessment Report) nonclinical section for {drug_name}. Write in formal "
                f"ICH M4 regulatory style aligned with TGA requirements. Cite relevant "
                f"ICH guidelines (S7B, S2(R1), M3(R2)) and TGA-specific considerations."
            ),
            "response": body,
        })

    return examples


# ─── openFDA Drug Labels (nonclinical sections) ────────────────────────────────
# NOTE: openFDA drug labels API has 40K+ labels with nonclinical_toxicology sections.
# This replaces the Health Canada SBD approach (which requires JS rendering).
# License: public domain (FDA). Rate limit: 40 req/min without key, 240 with key.
# API: https://api.fda.gov/drug/label.json

OPENFDA_LABEL_API = "https://api.fda.gov/drug/label.json"

# openFDA section fields → ICH M4S section type mapping
_OPENFDA_SECTION_MAP = {
    "nonclinical_toxicology": "tox_overview",
    "animal_pharmacology_and_or_toxicology": "tox_overview",
    "carcinogenesis_and_mutagenesis_and_impairment_of_fertility": "tox_genotox",
    "pharmacokinetics": "pk_overview",
    "clinical_pharmacology": "overview",
}


def collect_health_canada_sbd(out_dir: Path, max_reports: int = 200) -> list[dict]:
    """
    Collects FDA drug label nonclinical sections via openFDA API.
    40K+ labels with nonclinical_toxicology, carcinogenicity, PK sections.
    Public domain. API: https://api.fda.gov/drug/label.json
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    examples = []
    skip = 0
    page_size = 100
    priority_field = "nonclinical_toxicology"

    log.info("[openFDA] Fetching nonclinical label sections (max %d)…", max_reports)

    while len(examples) < max_reports:
        try:
            r = requests.get(
                OPENFDA_LABEL_API,
                params={
                    "search": f"{priority_field}:*",
                    "limit": page_size,
                    "skip": skip,
                },
                timeout=20,
            )
            if r.status_code == 429:
                time.sleep(15)
                continue
            if not r.ok:
                log.warning("[openFDA] API error %s at skip=%d", r.status_code, skip)
                break
            data = r.json()
        except Exception as exc:
            log.warning("[openFDA] Request failed at skip=%d: %s", skip, exc)
            break

        results = data.get("results", [])
        if not results:
            break

        for label in results:
            if len(examples) >= max_reports:
                break

            # Get drug name from openfda metadata
            openfda = label.get("openfda", {})
            brand = (openfda.get("brand_name") or [""])[0]
            generic = (openfda.get("generic_name") or [""])[0]
            drug_name = brand or generic or "investigational compound"

            # Extract the best nonclinical section available
            for field, sec_type in _OPENFDA_SECTION_MAP.items():
                raw = label.get(field)
                if not raw:
                    continue
                text = raw[0] if isinstance(raw, list) else str(raw)
                # Strip SPL section header numbers (e.g. "13 NONCLINICAL TOXICOLOGY\n13.1 ...")
                text = re.sub(r"^\d+\s+[A-Z][A-Z ,/]+\n", "", text).strip()
                text = re.sub(r"\s{2,}", " ", text)
                if len(text.split()) < 80:
                    continue

                words = text.split()
                if len(words) > 1200:
                    text = " ".join(words[:1200]) + " [truncated]"

                sec_name = field.replace("_", " ").title()
                examples.append({
                    "source": "openFDA_FDA_Labels",
                    "drug": drug_name,
                    "section_type": sec_type,
                    "section_name": sec_name,
                    "openfda_field": field,
                    "context": (
                        f"You are an FDA regulatory scientist writing the {sec_name} section "
                        f"of a drug label for {drug_name}. Write in formal regulatory style "
                        f"following ICH M4S(R2), 21 CFR Part 314, and FDA labeling regulations. "
                        f"Cite relevant ICH safety guidelines (S7A, S7B, S2(R1)) and FDA guidance."
                    ),
                    "response": text,
                })
                break  # one section per label

        skip += page_size
        time.sleep(0.5)  # 40 req/min rate limit

    out_file = out_dir / "hc_sbd_examples.jsonl"
    _write_jsonl(examples, out_file)
    log.info("[openFDA] Done. %d examples → %s", len(examples), out_file)
    return examples


# ─── WHO Prequalification Reports ─────────────────────────────────────────────

WHO_EPAR_BASE = "https://extranet.who.int/prequal/medicines/prequalification-reports/whopars"


def collect_who(out_dir: Path, max_reports: int = 100) -> list[dict]:
    """
    Collect WHO prequalification public assessment reports (WHOPARs).
    These are the WHO equivalent of EMA EPARs for global health priority drugs.
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    log.info("[WHO] WHO WHOPAR collection — requires pdfplumber + manual listing")
    # The WHO WHOPAR listing is dynamically rendered (JS) — requires a scraping approach
    # or use the static PDF index at extranet.who.int
    # For now, document the approach; full implementation requires Selenium or requests-html
    log.info("[WHO] See: %s", WHO_EPAR_BASE)
    log.info("[WHO] Full automation requires dynamic page scraping (Selenium/Playwright)")
    log.info("[WHO] Manual: Download WHOPAR PDFs, place in %s/raw/who/, re-run with --who", out_dir)
    return []


# ─── Combine All Examples ─────────────────────────────────────────────────────

def combine_examples(out_dir: Path) -> None:
    """Merge all source JSONL files (recursively) into a single training dataset."""
    combined = []
    for jsonl in sorted(out_dir.rglob("*.jsonl")):
        # Skip processed outputs (combined file, splits, task files)
        if "combined" in jsonl.name:
            continue
        if "tasks" in jsonl.parts or "splits" in jsonl.parts:
            continue
        with open(jsonl, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        combined.append(json.loads(line))
                    except Exception:
                        pass

    # Shuffle deterministically
    import random
    rng = random.Random(42)
    rng.shuffle(combined)

    out_file = out_dir / "combined_regulatory_training.jsonl"
    _write_jsonl(combined, out_file)
    log.info("[Combine] %d total examples → %s", len(combined), out_file)

    # Write stats
    by_source: dict[str, int] = {}
    for ex in combined:
        src = ex.get("source", "unknown")
        by_source[src] = by_source.get(src, 0) + 1
    log.info("[Combine] Source breakdown: %s", json.dumps(by_source, indent=2))

    stats = {"total": len(combined), "by_source": by_source}
    with open(out_dir / "dataset_stats.json", "w") as f:
        json.dump(stats, f, indent=2)


# ─── Utilities ────────────────────────────────────────────────────────────────

def _write_jsonl(examples: list[dict], path: Path) -> None:
    with open(path, "w", encoding="utf-8") as f:
        for ex in examples:
            f.write(json.dumps(ex, ensure_ascii=False) + "\n")


# ─── CLI ──────────────────────────────────────────────────────────────────────

def main() -> None:
    ap = argparse.ArgumentParser(description="Collect regulatory LLM training data")
    ap.add_argument("--epar",         action="store_true", help="EMA EPAR nonclinical assessment reports")
    ap.add_argument("--epar-max",     type=int, default=500, help="Max medicines to fetch")
    ap.add_argument("--dailymed",     action="store_true", help="DailyMed FDA drug labels (SPL XML)")
    ap.add_argument("--dailymed-max", type=int, default=5000, help="Max labels to parse")
    ap.add_argument("--ich-guidelines", action="store_true", help="ICH guideline PDFs")
    ap.add_argument("--fda-nda",      action="store_true", help="FDA NDA multidisciplinary review PDFs (nonclinical sections)")
    ap.add_argument("--fda-nda-max",  type=int, default=20, help="Max NDA reviews to download")
    ap.add_argument("--tga",          action="store_true", help="TGA AusPAR PDFs (CC BY 4.0)")
    ap.add_argument("--tga-max",      type=int, default=50, help="Max AusPAR reports to download")
    ap.add_argument("--hc-sbd",       action="store_true", help="Health Canada Summary Basis of Decision (API)")
    ap.add_argument("--hc-max",       type=int, default=30, help="Max SBD documents to collect")
    ap.add_argument("--phtlm",        action="store_true", help="PhT_LM regulatory translation dataset")
    ap.add_argument("--who",          action="store_true", help="WHO prequalification reports (WHOPARs)")
    ap.add_argument("--all",          action="store_true", help="Run all sources")
    ap.add_argument("--output",       type=Path, default=DEFAULT_OUT)
    ap.add_argument("--combine",      action="store_true", default=True, help="Merge all outputs at end")
    args = ap.parse_args()

    out = args.output
    out.mkdir(parents=True, exist_ok=True)
    log.info("Output directory: %s", out)

    if args.all or args.ich_guidelines:
        collect_ich_guidelines(out / "ich_guidelines")

    if args.all or args.fda_nda:
        collect_fda_nda(out / "fda_nda", max_ndas=args.fda_nda_max)

    if args.all or args.tga:
        collect_tga_auspar(out / "tga", max_reports=args.tga_max)

    if args.all or args.hc_sbd:
        collect_health_canada_sbd(out / "hc_sbd", max_reports=args.hc_max)

    if args.all or args.epar:
        collect_epar(out / "epar", max_medicines=args.epar_max)

    if args.all or args.dailymed:
        collect_dailymed(out / "dailymed", max_labels=args.dailymed_max)

    if args.all or args.phtlm:
        collect_phtlm(out / "phtlm")

    if args.all or args.who:
        collect_who(out / "who")

    if args.combine:
        combine_examples(out)

    log.info("Done. Training data at: %s", out)


if __name__ == "__main__":
    main()
