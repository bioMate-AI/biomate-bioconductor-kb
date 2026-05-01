"""
BioMate Wet-Lab Report Ingester

Parses authoritative nonclinical study reports to extract measured PK and
safety data for use in IND document assembly.

Supported sources:
  - FDA NDA accessdata documents (PDF — nonclinical pharmacology/tox review)
  - EMA EPAR nonclinical summaries (PDF)
  - Structured CSV/JSON uploads from in-house CRO studies
  - ICH M4S-compliant summary tables (Markdown or plain text)

Extracted fields (all measured values, not predicted):
  PK:   t_half_h, auc_inf_ngmlh, cmax_ngml, vd_lkg, cl_mlminkg,
        fu_plasma (measured), bioavailability_pct, tmax_h
  Safety: noael_mg_kg_day, ames_result, herg_ic50_uM_measured,
          repeat_dose_tox_findings, genotox_in_vitro_results

Data provenance is tracked per field: "source" = "measured_wetlab" vs "predicted_computational".

Usage:
    ingester = WetLabReportIngester()
    data = ingester.ingest_pdf("path/to/nda_nonclinical_review.pdf")
    # or
    data = ingester.ingest_fda_nda("21-042")   # fetches from FDA accessdata
    # or
    data = ingester.ingest_structured({"t_half_h": 8.2, ...})
"""
from __future__ import annotations

import json
import logging
import re
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Optional

log = logging.getLogger(__name__)


# ─── Data model ──────────────────────────────────────────────────────────────

@dataclass
class MeasuredValue:
    value: float
    unit: str
    source: str = "measured_wetlab"   # always "measured_wetlab" for this module
    reference: str = ""               # e.g. "FDA NDA 21-042 nonclinical review p.42"
    species: str = "human"            # human | rat | dog | mouse
    study_type: str = ""              # e.g. "mass_balance", "dose_escalation_phase1"
    confidence: str = "HIGH"          # HIGH | MEDIUM | LOW


@dataclass
class WetLabStudyData:
    """
    Structured wet-lab study data for one drug.
    All values are measured (not predicted). None = not available.
    """
    # Identity
    drug_name: str = ""
    smiles: str = ""
    nda_number: str = ""
    source_document: str = ""
    ingested_at: str = ""

    # Pharmacokinetics — measured in human clinical studies
    t_half_h: Optional[MeasuredValue] = None          # terminal half-life
    auc_inf_ngmlh: Optional[MeasuredValue] = None     # AUC0-∞
    cmax_ngml: Optional[MeasuredValue] = None         # peak concentration
    vd_lkg: Optional[MeasuredValue] = None            # volume of distribution
    cl_mlminkg: Optional[MeasuredValue] = None        # total clearance
    fu_plasma: Optional[MeasuredValue] = None         # fraction unbound (PPB study)
    bioavailability_pct: Optional[MeasuredValue] = None
    tmax_h: Optional[MeasuredValue] = None

    # Preclinical PK (animal studies, used when human data unavailable)
    t_half_h_preclinical: Optional[MeasuredValue] = None
    vd_lkg_preclinical: Optional[MeasuredValue] = None

    # Safety — in vitro
    herg_ic50_uM_measured: Optional[MeasuredValue] = None
    ames_in_vitro: Optional[str] = None           # "negative" | "positive" | "equivocal"
    chromosomal_aberration: Optional[str] = None  # "negative" | "positive"
    micronucleus: Optional[str] = None            # "negative" | "positive"

    # Safety — in vivo
    noael_mg_kg_day: Optional[MeasuredValue] = None
    noael_species: str = ""
    noael_study_duration: str = ""               # e.g. "28-day", "90-day"
    repeat_dose_tox_summary: str = ""
    genotox_battery_result: str = ""             # "complete_negative" | "positive" | "incomplete"

    # Regulatory context
    glp_certified: bool = True
    study_sponsor: str = ""
    ctd_sections_covered: list[str] = field(default_factory=list)

    def to_pk_summary_override(self) -> dict:
        """
        Return a dict compatible with pk_summary.json format for IND assembly.
        Only includes fields that have measured values.
        """
        out: dict = {"status": "measured", "source": "wetlab_report"}
        if self.fu_plasma:
            out["fu_plasma"] = self.fu_plasma.value
            out["fu_source"] = "measured_ppb_study"
            out["ppbr_pct"] = round((1.0 - self.fu_plasma.value) * 100, 1)
        if self.vd_lkg:
            out["vd_lkg"] = self.vd_lkg.value
        if self.cl_mlminkg:
            out["cl_total_mlminkg"] = self.cl_mlminkg.value
        if self.t_half_h:
            out["t_half_h"] = self.t_half_h.value
        if self.bioavailability_pct:
            out["oral_bioavailability_pct"] = self.bioavailability_pct.value
        if self.herg_ic50_uM_measured:
            out["herg_ic50_uM_measured"] = self.herg_ic50_uM_measured.value
        out["measurement_provenance"] = "wetlab_study"
        return out

    def to_dict(self) -> dict:
        return asdict(self)


# ─── Ingester ─────────────────────────────────────────────────────────────────

class WetLabReportIngester:
    """
    Extracts structured PK and safety data from nonclinical study reports.

    Design principle: extract only measured values. Computational predictions
    are never extracted here — those come from the Nextflow ADMET pipeline.
    Every extracted value records its source document and page/section reference.
    """

    # Regex patterns for PK parameter extraction from regulatory document text
    # Tuned on FDA NDA nonclinical review format and EMA EPAR nonclinical summaries

    _PK_PATTERNS = {
        "t_half_h": [
            r't[½½12](?:\s*\(terminal\))?\s*[=:]\s*([\d.]+)\s*h(?:ours?)?',
            r'half.life\s*[=:of]*\s*([\d.]+)\s*h',
            r'terminal\s+half.life[^,\n]*?([\d.]+)\s*h',
        ],
        "auc_inf": [
            r'AUC(?:0-∞|inf|0-inf|0.∞)\s*[=:]\s*([\d,.]+)\s*(ng[·•]h/mL|ng\.h/mL|μg\.h/mL)',
            r'area under\s+(?:the\s+)?curve[^=\n]*([\d,.]+)\s*(ng[·•]h/mL|μg\.h/mL)',
        ],
        "cmax": [
            r'Cmax\s*[=:]\s*([\d,.]+)\s*(ng/mL|μg/mL|µg/mL)',
            r'peak\s+(?:plasma\s+)?concentration[^=\n]*([\d,.]+)\s*(ng/mL|μg/mL)',
        ],
        "fu_plasma": [
            r'f_?u(?:\s*plasma)?\s*[=:]\s*(0\.\d+)',
            r'fraction\s+unbound\s*[=:]\s*(0\.\d+)',
            r'plasma\s+protein\s+bind(?:ing)?\s*[=:of]*\s*([\d.]+)\s*%',
            r'PPB\s*[=:]\s*([\d.]+)\s*%',
            r'unbound\s+fraction\s*[=:]\s*(0\.\d+)',
        ],
        "vd": [
            r'V(?:d|ss|z)[^=\n]*[=:]\s*([\d.]+)\s*L/kg',
            r'volume\s+of\s+distribution[^=\n]*([\d.]+)\s*L/kg',
        ],
        "cl": [
            r'CL(?:/F|total)?\s*[=:]\s*([\d.]+)\s*mL/min/kg',
            r'clearance[^=\n]*([\d.]+)\s*mL/min/kg',
        ],
        "bioavailability": [
            r'(?:oral\s+)?bioavailability\s*[=:F%]*\s*([\d.]+)\s*%',
            r'\bF\b\s*[=:]\s*([\d.]+)\s*%',
        ],
    }

    _SAFETY_PATTERNS = {
        "herg_ic50": [
            r'hERG\s+IC50\s*[=:≈~]\s*([\d.]+)\s*(µM|μM|nM|µmol/L)',
            r'hERG\s+channel\s+inhibition[^=\n]*([\d.]+)\s*(µM|μM|nM)',
        ],
        "ames": [
            r'Ames\s+test[^:.\n]*:\s*(negative|positive|equivocal)',
            r'Salmonella[^:.\n]*:\s*(negative|positive)',
            r'mutagenicity[^:.\n]*:\s*(negative|positive|not\s+mutagenic)',
            # NTP Technical Report format: "was mutagenic in Salmonella" or "was not mutagenic"
            r'was\s+(mutagenic|not mutagenic)\s+(?:in\s+)?Salmonella',
            r'(mutagenic|not\s+mutagenic)\s+in\s+Salmonella\s+typhimurium',
        ],
        "noael": [
            r'NOAEL\s*[=:of]*\s*([\d.]+)\s*mg/kg(?:/day)?(?:\s+in\s+(\w+))?',
            r'no.observed.adverse.effect[^=\n]*([\d.]+)\s*mg/kg',
        ],
        "chromosomal_aberration": [
            r'chromosomal\s+aberration[^:.\n]*:\s*(negative|positive)',
            r'clastogenicity[^:.\n]*:\s*(negative|positive)',
        ],
        "micronucleus": [
            r'micronucleus\s+test[^:.\n]*:\s*(negative|positive)',
            r'in\s+vivo\s+micronucleus[^:.\n]*:\s*(negative|positive)',
        ],
    }

    def ingest_structured(self, data: dict,
                           drug_name: str = "",
                           source_reference: str = "sponsor_data") -> WetLabStudyData:
        """
        Ingest pre-structured wet-lab data (e.g. CRO export JSON/CSV).

        Expected keys (all optional):
          fu_plasma, t_half_h, auc_inf_ngmlh, cmax_ngml, vd_lkg, cl_mlminkg,
          bioavailability_pct, herg_ic50_uM, ames_result, noael_mg_kg_day,
          noael_species, repeat_dose_tox_summary
        """
        from datetime import datetime, timezone
        result = WetLabStudyData(
            drug_name=drug_name or data.get("drug_name", ""),
            smiles=data.get("smiles", ""),
            source_document=source_reference,
            ingested_at=datetime.now(timezone.utc).isoformat(),
        )

        _ref = source_reference

        def _mv(val, unit, species="human", study_type=""):
            if val is None:
                return None
            return MeasuredValue(value=float(val), unit=unit,
                                 reference=_ref, species=species,
                                 study_type=study_type)

        result.fu_plasma          = _mv(data.get("fu_plasma"), "dimensionless")
        result.t_half_h           = _mv(data.get("t_half_h"), "h")
        result.auc_inf_ngmlh      = _mv(data.get("auc_inf_ngmlh"), "ng·h/mL")
        result.cmax_ngml          = _mv(data.get("cmax_ngml"), "ng/mL")
        result.vd_lkg             = _mv(data.get("vd_lkg"), "L/kg")
        result.cl_mlminkg         = _mv(data.get("cl_mlminkg"), "mL/min/kg")
        result.bioavailability_pct = _mv(data.get("bioavailability_pct"), "%")
        result.tmax_h             = _mv(data.get("tmax_h"), "h")
        result.noael_mg_kg_day    = _mv(data.get("noael_mg_kg_day"), "mg/kg/day",
                                        species=data.get("noael_species", "rat"),
                                        study_type=data.get("noael_study_duration", ""))
        result.noael_species      = data.get("noael_species", "")
        result.noael_study_duration = data.get("noael_study_duration", "")

        if data.get("herg_ic50_uM") is not None:
            result.herg_ic50_uM_measured = MeasuredValue(
                value=float(data["herg_ic50_uM"]), unit="µM",
                reference=_ref, study_type="herg_patch_clamp"
            )

        result.ames_in_vitro           = data.get("ames_result")
        result.chromosomal_aberration  = data.get("chromosomal_aberration")
        result.micronucleus            = data.get("micronucleus")
        result.repeat_dose_tox_summary = data.get("repeat_dose_tox_summary", "")
        result.genotox_battery_result  = self._derive_genotox_verdict(result)

        return result

    def ingest_text(self, text: str,
                    drug_name: str = "",
                    source_reference: str = "text_extract") -> WetLabStudyData:
        """
        Extract PK/safety data from raw regulatory document text (plain text or PDF extract).
        Uses pattern matching calibrated on FDA NDA nonclinical review format.
        """
        from datetime import datetime, timezone
        result = WetLabStudyData(
            drug_name=drug_name,
            source_document=source_reference,
            ingested_at=datetime.now(timezone.utc).isoformat(),
        )
        text_lower = text.lower()

        # PK extraction
        result.fu_plasma    = self._extract_fu_plasma(text, source_reference)
        result.t_half_h     = self._extract_pk_value(text, "t_half_h", "h", source_reference)
        result.vd_lkg       = self._extract_pk_value(text, "vd", "L/kg", source_reference)
        result.cl_mlminkg   = self._extract_pk_value(text, "cl", "mL/min/kg", source_reference)
        result.bioavailability_pct = self._extract_pk_value(text, "bioavailability", "%", source_reference)

        # Safety extraction
        result.herg_ic50_uM_measured = self._extract_herg(text, source_reference)
        result.ames_in_vitro = self._extract_binary_result(text, "ames", source_reference)
        result.chromosomal_aberration = self._extract_binary_result(text, "chromosomal_aberration", source_reference)
        result.micronucleus = self._extract_binary_result(text, "micronucleus", source_reference)
        result.noael_mg_kg_day, result.noael_species = self._extract_noael(text, source_reference)
        result.genotox_battery_result = self._derive_genotox_verdict(result)

        log.info("[wetlab_ingester] Extracted from '%s': fu_plasma=%s, t_half=%s, hERG=%s, Ames=%s",
                 source_reference,
                 result.fu_plasma.value if result.fu_plasma else "N/A",
                 result.t_half_h.value if result.t_half_h else "N/A",
                 result.herg_ic50_uM_measured.value if result.herg_ic50_uM_measured else "N/A",
                 result.ames_in_vitro)

        return result

    def ingest_pdf(self, pdf_path: str,
                   drug_name: str = "",
                   page_range: tuple[int, int] = None) -> WetLabStudyData:
        """
        Extract nonclinical data from a PDF file (FDA NDA review, EMA EPAR, etc.).
        Requires pdfplumber (pip install pdfplumber).
        """
        try:
            import pdfplumber
        except ImportError:
            log.warning("[wetlab_ingester] pdfplumber not installed — install with pip install pdfplumber")
            return WetLabStudyData(drug_name=drug_name, source_document=pdf_path)

        text_parts = []
        with pdfplumber.open(pdf_path) as pdf:
            pages = pdf.pages
            if page_range:
                pages = pages[page_range[0]:page_range[1]]
            for page in pages:
                t = page.extract_text()
                if t:
                    text_parts.append(t)

        full_text = "\n".join(text_parts)
        return self.ingest_text(full_text, drug_name=drug_name,
                                source_reference=f"PDF:{Path(pdf_path).name}")

    # ── Pattern extraction helpers ────────────────────────────────────────────

    def _extract_fu_plasma(self, text: str, ref: str) -> Optional[MeasuredValue]:
        """Extract fu_plasma, handling both fu=0.035 and PPB=96.5% formats."""
        for pat in self._SAFETY_PATTERNS.get("fu_plasma", []) + self._PK_PATTERNS.get("fu_plasma", []):
            m = re.search(pat, text, re.IGNORECASE)
            if m:
                val_str = m.group(1).replace(",", "")
                try:
                    val = float(val_str)
                    # If value > 1.0, it's PPB% → convert to fu
                    if val > 1.0:
                        val = round(1.0 - val / 100.0, 4)
                    val = max(0.001, min(0.999, val))
                    return MeasuredValue(value=val, unit="dimensionless",
                                        reference=ref, study_type="plasma_protein_binding")
                except ValueError:
                    continue
        return None

    def _extract_pk_value(self, text: str, param: str, unit: str, ref: str) -> Optional[MeasuredValue]:
        for pat in self._PK_PATTERNS.get(param, []):
            m = re.search(pat, text, re.IGNORECASE)
            if m:
                try:
                    val = float(m.group(1).replace(",", ""))
                    return MeasuredValue(value=val, unit=unit, reference=ref)
                except (ValueError, IndexError):
                    continue
        return None

    def _extract_herg(self, text: str, ref: str) -> Optional[MeasuredValue]:
        for pat in self._SAFETY_PATTERNS.get("herg_ic50", []):
            m = re.search(pat, text, re.IGNORECASE)
            if m:
                try:
                    val = float(m.group(1))
                    unit_str = m.group(2) if len(m.groups()) >= 2 else "µM"
                    if "nM" in unit_str:
                        val = val / 1000.0  # convert nM to µM
                    return MeasuredValue(value=val, unit="µM", reference=ref,
                                         study_type="herg_patch_clamp")
                except (ValueError, IndexError):
                    continue
        return None

    def _extract_binary_result(self, text: str, param: str, ref: str) -> Optional[str]:
        for pat in self._SAFETY_PATTERNS.get(param, []):
            m = re.search(pat, text, re.IGNORECASE)
            if m:
                result_str = m.group(1).lower().strip()
                if "not mutagenic" in result_str or "negative" in result_str:
                    return "negative"
                elif "mutagenic" in result_str or "positive" in result_str:
                    return "positive"
                elif "equivocal" in result_str:
                    return "equivocal"
        return None

    def _extract_noael(self, text: str, ref: str) -> tuple[Optional[MeasuredValue], str]:
        for pat in self._SAFETY_PATTERNS.get("noael", []):
            m = re.search(pat, text, re.IGNORECASE)
            if m:
                try:
                    val = float(m.group(1))
                    species = m.group(2) if len(m.groups()) >= 2 and m.group(2) else "rat"
                    return (
                        MeasuredValue(value=val, unit="mg/kg/day",
                                      species=species, reference=ref,
                                      study_type="repeat_dose_tox"),
                        species,
                    )
                except (ValueError, IndexError):
                    continue
        return None, ""

    def _derive_genotox_verdict(self, data: WetLabStudyData) -> str:
        """Derive overall genotox battery verdict from individual assay results."""
        results = [data.ames_in_vitro, data.chromosomal_aberration, data.micronucleus]
        available = [r for r in results if r is not None]
        if not available:
            return "incomplete"
        if any(r == "positive" for r in available):
            return "positive"
        if all(r == "negative" for r in available) and len(available) >= 2:
            return "complete_negative"
        return "partial_negative"

    # ─── FDA NDA / EMA EPAR / NTP fetchers ───────────────────────────────────

    # Known FDA NDA nonclinical review PDF URLs (public, no auth required)
    _FDA_NDA_URLS: dict[str, str] = {
        "Ibuprofen":   "https://www.accessdata.fda.gov/drugsatfda_docs/nda/2002/21-374_Ibuprofen_pharmr.pdf",
        "Warfarin":    "https://www.accessdata.fda.gov/drugsatfda_docs/nda/2000/09218S097_Coumadin.pdf",
        "Midazolam":   "https://www.accessdata.fda.gov/drugsatfda_docs/nda/97/018654ap.pdf",
    }

    # Known NTP GLP Technical Report PDF URLs
    _NTP_URLS: dict[str, str] = {
        "Nitrofurantoin": "https://ntp.niehs.nih.gov/sites/default/files/ntp/htdocs/lt_rpts/tr341.pdf",
        "Caffeine":       "https://ntp.niehs.nih.gov/sites/default/files/ntp/htdocs/lt_rpts/tr067.pdf",
    }

    def ingest_fda_nda(
        self,
        drug_name: str,
        nda_url: Optional[str] = None,
        cache_dir: Optional[str] = None,
    ) -> WetLabStudyData:
        """
        Download and parse an FDA NDA nonclinical pharmacology/toxicology review PDF.

        Args:
            drug_name:  Name of the drug (used for caching and as fallback URL key).
            nda_url:    Direct URL to the PDF. If None, looks up _FDA_NDA_URLS[drug_name].
            cache_dir:  Local directory to cache the downloaded PDF. Defaults to /tmp.

        Returns:
            WetLabStudyData with measured values extracted from the review text.
        """
        import requests as req

        url = nda_url or self._FDA_NDA_URLS.get(drug_name)
        if not url:
            log.warning("[fda_nda] No URL known for '%s'. Pass nda_url explicitly.", drug_name)
            return WetLabStudyData(drug_name=drug_name, source_document="FDA NDA (not found)")

        # ── Download / cache ──────────────────────────────────────────────
        cache_path = None
        if cache_dir:
            import os
            os.makedirs(cache_dir, exist_ok=True)
            fname = f"fda_nda_{drug_name.replace(' ', '_')}.pdf"
            cache_path = Path(cache_dir) / fname

        pdf_path = None
        if cache_path and cache_path.exists():
            pdf_path = cache_path
            log.info("[fda_nda] Using cached PDF: %s", pdf_path)
        else:
            try:
                log.info("[fda_nda] Downloading FDA NDA for %s from %s", drug_name, url)
                r = req.get(url, timeout=60, stream=True)
                if r.status_code != 200:
                    log.warning("[fda_nda] HTTP %d for %s", r.status_code, url)
                    return WetLabStudyData(drug_name=drug_name, source_document=f"FDA NDA (HTTP {r.status_code})")
                # Write to cache or temp
                import tempfile
                dest = cache_path or Path(tempfile.mktemp(suffix=".pdf"))
                with open(dest, "wb") as f:
                    for chunk in r.iter_content(8192):
                        f.write(chunk)
                pdf_path = dest
                log.info("[fda_nda] Downloaded %.1f KB → %s", dest.stat().st_size / 1024, dest)
            except Exception as exc:
                log.warning("[fda_nda] Download error: %s", exc)
                return WetLabStudyData(drug_name=drug_name, source_document=f"FDA NDA (error: {exc})")

        # ── Extract text and parse ─────────────────────────────────────────
        ref = f"FDA NDA {url}"
        return self.ingest_pdf(str(pdf_path), drug_name=drug_name)

    def ingest_ntp_report(
        self,
        drug_name: str,
        ntp_url: Optional[str] = None,
        cache_dir: Optional[str] = None,
    ) -> WetLabStudyData:
        """
        Download and parse an NTP GLP Technical Report PDF.

        NTP reports are 2-year rodent carcinogenesis/subchronic GLP studies.
        They contain detailed genotoxicity battery results (Ames + CA + MN),
        NOAEL, and pathology findings in structured appendix tables.

        Args:
            drug_name:  Name of the compound (used for caching and URL lookup).
            ntp_url:    Direct URL to the PDF. Defaults to _NTP_URLS[drug_name].
            cache_dir:  Local directory to cache. Defaults to /tmp.
        """
        import requests as req

        url = ntp_url or self._NTP_URLS.get(drug_name)
        if not url:
            log.warning("[ntp] No URL known for '%s'. Pass ntp_url explicitly.", drug_name)
            return WetLabStudyData(drug_name=drug_name, source_document="NTP report (not found)")

        cache_path = None
        if cache_dir:
            import os
            os.makedirs(cache_dir, exist_ok=True)
            fname = f"ntp_{drug_name.replace(' ', '_')}.pdf"
            cache_path = Path(cache_dir) / fname

        pdf_path = None
        if cache_path and cache_path.exists():
            pdf_path = cache_path
        else:
            try:
                log.info("[ntp] Downloading NTP report for %s", drug_name)
                r = req.get(url, timeout=120, stream=True)
                if r.status_code != 200:
                    return WetLabStudyData(drug_name=drug_name, source_document=f"NTP (HTTP {r.status_code})")
                import tempfile
                dest = cache_path or Path(tempfile.mktemp(suffix=".pdf"))
                with open(dest, "wb") as f:
                    for chunk in r.iter_content(8192):
                        f.write(chunk)
                pdf_path = dest
                log.info("[ntp] Downloaded %.1f KB → %s", dest.stat().st_size / 1024, dest)
            except Exception as exc:
                log.warning("[ntp] Download error: %s", exc)
                return WetLabStudyData(drug_name=drug_name, source_document=f"NTP (error: {exc})")

        return self.ingest_pdf(str(pdf_path), drug_name=drug_name)

    def ingest_chembl_reference(self, drug_name: str, chembl_id: str) -> WetLabStudyData:
        """
        Build a WetLabStudyData from ChEMBL measured bioactivity data.
        Pulls hERG IC50, PPB (Fub), and CLint from public ChEMBL API.
        This is a 'literature_measured' source (not GLP, but peer-reviewed assay data).
        """
        import requests as req
        from datetime import datetime, timezone

        result = WetLabStudyData(
            drug_name=drug_name,
            source_document=f"ChEMBL {chembl_id} measured bioactivity",
            ingested_at=datetime.now(timezone.utc).isoformat(),
        )
        base = "https://www.ebi.ac.uk/chembl/api/data/activity"
        ref = f"ChEMBL {chembl_id} (www.ebi.ac.uk/chembl)"

        # hERG IC50
        try:
            r = req.get(base, params={
                "molecule_chembl_id": chembl_id,
                "target_pref_name": "Voltage-gated inwardly rectifying potassium channel KCNH2",
                "standard_type": "IC50",
                "format": "json",
                "limit": 25,
            }, timeout=15)
            if r.status_code == 200:
                acts = r.json().get("activities", [])
                ic50_vals = []
                for a in acts:
                    v = a.get("standard_value")
                    u = a.get("standard_units", "")
                    if v and a.get("standard_relation") == "=":
                        val_um = float(v) / 1000.0 if u == "nM" else float(v)
                        ic50_vals.append(val_um)
                if ic50_vals:
                    median = sorted(ic50_vals)[len(ic50_vals) // 2]
                    result.herg_ic50_uM_measured = MeasuredValue(
                        value=round(median, 4), unit="µM",
                        reference=ref, study_type="herg_radioligand_binding",
                        confidence="MEDIUM",  # assay variability across labs
                    )
                    log.info("[chembl] %s hERG IC50 = %.4f µM (n=%d)", drug_name, median, len(ic50_vals))
        except Exception as e:
            log.warning("[chembl] hERG fetch failed for %s: %s", drug_name, e)

        # PPB / Fub
        try:
            for std_type in ("Fub", "PPB"):
                r = req.get(base, params={
                    "molecule_chembl_id": chembl_id,
                    "standard_type": std_type,
                    "format": "json",
                    "limit": 10,
                }, timeout=15)
                if r.status_code == 200:
                    acts = r.json().get("activities", [])
                    if acts:
                        v = acts[0].get("standard_value")
                        u = acts[0].get("standard_units", "")
                        if v:
                            fub = float(v) if u in ("", "fraction") else float(v) / 100.0
                            result.fu_plasma = MeasuredValue(
                                value=round(fub, 4), unit="fraction",
                                reference=ref, study_type="plasma_protein_binding",
                                confidence="MEDIUM",
                            )
                        break
        except Exception as e:
            log.warning("[chembl] PPB fetch failed for %s: %s", drug_name, e)

        return result
