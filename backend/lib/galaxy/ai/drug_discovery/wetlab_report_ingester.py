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
Values the source labels as predictions are kept out of the measured fields and
recorded in ``predicted_values``. Species and GLP status are taken only from
the input; when it does not state them they are "unspecified" / None.

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
import math
import re
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Optional

from .evidence_provenance import (
    UNSPECIFIED_SPECIES,
    detect_glp_status,
    has_measurement_language,
    has_prediction_language,
    is_prediction_only,
    line_at,
    normalise_species,
    parse_glp_flag,
    resolve_species,
    species_mentioned,
)

log = logging.getLogger(__name__)

MEASURED = "measured_wetlab"
PREDICTED = "predicted_computational"


# ─── Data model ──────────────────────────────────────────────────────────────

@dataclass
class MeasuredValue:
    value: float
    unit: str
    source: str = MEASURED            # measured_wetlab | predicted_computational
    reference: str = ""               # e.g. "FDA NDA 21-042 nonclinical review p.42"
    species: str = UNSPECIFIED_SPECIES  # human | rat | dog | mouse | ... | unspecified
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

    # Pharmacokinetics — measured; each value's species is on MeasuredValue.species
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

    # Regulatory context — None means the source does not state GLP status.
    glp_certified: Optional[bool] = None
    study_sponsor: str = ""
    ctd_sections_covered: list[str] = field(default_factory=list)

    # Values the source labels as predictions; never merged as measurements.
    predicted_values: dict[str, dict] = field(default_factory=dict)
    provenance_warnings: list[str] = field(default_factory=list)

    def to_pk_summary_override(self) -> dict:
        """
        Return a dict compatible with pk_summary.json format for IND assembly.
        Only includes fields that have measured values.
        """
        out: dict = {"status": "measured", "source": "wetlab_report"}
        species = {
            name: mv.species
            for name, mv in (("fu_plasma", self.fu_plasma), ("vd_lkg", self.vd_lkg),
                             ("cl_total_mlminkg", self.cl_mlminkg), ("t_half_h", self.t_half_h),
                             ("oral_bioavailability_pct", self.bioavailability_pct))
            if mv is not None
        }
        if species:
            out["measured_species"] = species
        out["glp_certified"] = self.glp_certified
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

    Design principle: only values the source presents as measurements populate
    the measured fields. Values on lines that use prediction language, or in a
    document that declares itself prediction-only, go to ``predicted_values``.
    Every extracted value records its source document, species and confidence.
    """

    # Regex patterns for PK parameter extraction from regulatory document text
    # Tuned on FDA NDA nonclinical review format and EMA EPAR nonclinical summaries.
    # Numbers are captured with _NUM; prefixes before the number are non-greedy so
    # the whole number is captured (a greedy prefix keeps only its last digit).

    _NUM = r'(\d[\d,]*(?:\.\d+)?)'
    _AUC_UNIT = r'((?:ng|[µμu]g)\s*[·•.*×]?\s*h(?:r)?\s*/\s*mL)'
    _CONC_UNIT = r'(ng/mL|[µμu]g/mL)'

    _PK_PATTERNS = {
        "t_half_h": [
            r't[½½12](?:\s*\(terminal\))?\s*[=:]\s*' + _NUM + r'\s*h(?:ours?|rs?)?\b',
            r'half.life\s*[=:of]*\s*' + _NUM + r'\s*h(?:ours?|rs?)?\b',
            r'terminal\s+half.life[^,\n]*?' + _NUM + r'\s*h(?:ours?|rs?)?\b',
        ],
        "auc_inf": [
            r'AUC\s*[_(]?\s*(?:0\s*[-–]\s*)?(?:∞|inf(?:inity)?)\)?\s*[=:]\s*' + _NUM + r'\s*' + _AUC_UNIT,
            r'area under\s+(?:the\s+)?curve[^=\n]*?' + _NUM + r'\s*' + _AUC_UNIT,
        ],
        "cmax": [
            r'C\s?max\s*[=:]\s*' + _NUM + r'\s*' + _CONC_UNIT,
            r'peak\s+(?:plasma\s+)?concentration[^=\n]*?' + _NUM + r'\s*' + _CONC_UNIT,
        ],
        "fu_plasma": [
            r'f_?u(?:\s*plasma)?\s*[=:]\s*(0\.\d+)',
            r'fraction\s+unbound\s*[=:]\s*(0\.\d+)',
            r'plasma\s+protein\s+bind(?:ing)?\s*[=:of]*\s*' + _NUM + r'\s*%',
            r'PPB\s*[=:]\s*' + _NUM + r'\s*%',
            r'unbound\s+fraction\s*[=:]\s*(0\.\d+)',
        ],
        "vd": [
            r'V(?:d|ss|z)[^=\n]*?[=:]\s*' + _NUM + r'\s*L/kg',
            r'volume\s+of\s+distribution[^=\n]*?' + _NUM + r'\s*L/kg',
        ],
        "cl": [
            r'CL(?:/F|total)?\s*[=:]\s*' + _NUM + r'\s*mL/min/kg',
            r'clearance[^=\n]*?' + _NUM + r'\s*mL/min/kg',
        ],
        "bioavailability": [
            r'(?:oral\s+)?bioavailability\s*[=:F%]*\s*' + _NUM + r'\s*%',
            r'\bF\b\s*[=:]\s*' + _NUM + r'\s*%',
        ],
    }

    _SAFETY_PATTERNS = {
        "herg_ic50": [
            r'hERG\s+IC50\s*[=:≈~]\s*' + _NUM + r'\s*(µM|μM|uM|nM|µmol/L)',
            r'hERG\s+channel\s+inhibition[^=\n]*?' + _NUM + r'\s*(µM|μM|uM|nM)',
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
            r'NOAEL\s*[=:of]*\s*' + _NUM + r'\s*mg/kg(?:/day)?(?:\s+in\s+([\w-]+))?',
            r'no.observed.adverse.effect[^=\n]*?' + _NUM + r'\s*mg/kg',
        ],
        "chromosomal_aberration": [
            r'chromosomal\s+aberration[^:.\n]*:\s*(negative|positive)',
            r'clastogenicity[^:.\n]*:\s*(negative|positive)',
            # NTP format: "induced increased numbers of chromosomal aberrations" → positive
            r'induced[^.]*chromosomal\s+aberrations',
            # EMA/FDA format: "chromosomal aberration test was (positive|negative)"
            r'chromosomal\s+aberration\s+(?:test\s+)?was\s+(positive|negative)',
            # Negative: "no chromosomal aberrations were observed"
            r'no\s+(?:increase[^.]*)?chromosomal\s+aberrations?\s+were\s+(?:observed|induced)',
        ],
        "micronucleus": [
            r'micronucleus(?:\s+(?:test|assay))?[^:.\n]*:\s*(negative|positive)',
            r'in\s+vivo\s+micronucleus[^:.\n]*:\s*(negative|positive)',
        ],
    }

    # Physical bounds on measured values: (lower, lower_inclusive, upper).
    _PHYSICAL_BOUNDS = {
        "t_half_h": (0.0, False, None),
        "auc_inf_ngmlh": (0.0, False, None),
        "cmax_ngml": (0.0, False, None),
        "vd_lkg": (0.0, False, None),
        "cl_mlminkg": (0.0, False, None),
        "fu_plasma": (0.0, False, 1.0),
        "bioavailability_pct": (0.0, True, 150.0),   # >100% occurs with nonlinear PK
        "tmax_h": (0.0, True, None),
        "t_half_h_preclinical": (0.0, False, None),
        "vd_lkg_preclinical": (0.0, False, None),
        "herg_ic50_uM_measured": (0.0, False, None),
        "noael_mg_kg_day": (0.0, False, None),
    }

    @classmethod
    def _physical_error(cls, name: str, value: float) -> Optional[str]:
        if not math.isfinite(value):
            return f"{name} must be finite (got {value})."
        lower, lower_inclusive, upper = cls._PHYSICAL_BOUNDS.get(name, (None, True, None))
        if lower is not None and (value < lower or (value == lower and not lower_inclusive)):
            op = ">=" if lower_inclusive else ">"
            return f"{name} must be {op} {lower:g} (got {value:g})."
        if upper is not None and value > upper:
            return f"{name} must be <= {upper:g} (got {value:g})."
        return None

    def ingest_structured(self, data: dict,
                           drug_name: str = "",
                           source_reference: str = "sponsor_data") -> WetLabStudyData:
        """
        Ingest pre-structured wet-lab data (e.g. CRO export JSON/CSV).

        Expected keys (all optional):
          fu_plasma, t_half_h, auc_inf_ngmlh, cmax_ngml, vd_lkg, cl_mlminkg,
          bioavailability_pct, tmax_h, herg_ic50_uM, ames_result, noael_mg_kg_day,
          noael_species, noael_study_duration, repeat_dose_tox_summary,
          species (applies to every in vivo value without its own species),
          glp_certified / glp (True/False; absent = unknown).

        Values may be scalars or MeasuredValue dicts (as produced by
        ``WetLabStudyData.to_dict()``); dicts keep their own species, unit,
        reference and confidence, and dicts whose ``source`` is not
        ``measured_wetlab`` are kept in ``predicted_values``.

        Raises ValueError when a measured value is non-finite or physically
        impossible (e.g. a negative half-life).
        """
        from datetime import datetime, timezone
        glp_raw = data.get("glp_certified", data.get("glp"))
        result = WetLabStudyData(
            drug_name=drug_name or data.get("drug_name", ""),
            smiles=data.get("smiles", ""),
            source_document=source_reference,
            ingested_at=datetime.now(timezone.utc).isoformat(),
            glp_certified=parse_glp_flag(glp_raw),
        )
        result.predicted_values.update(data.get("predicted_values") or {})

        _ref = source_reference
        default_species = (
            normalise_species(str(data["species"])) if data.get("species") else UNSPECIFIED_SPECIES
        )

        def _mv(key, name, unit, species=None, study_type=""):
            raw = data.get(key)
            if raw is None:
                return None
            if isinstance(raw, dict):
                if raw.get("value") is None:
                    return None
                if raw.get("source", MEASURED) != MEASURED:
                    result.predicted_values[name] = dict(raw)
                    return None
                mv = MeasuredValue(
                    value=float(raw["value"]), unit=raw.get("unit") or unit,
                    reference=raw.get("reference") or _ref,
                    species=raw.get("species") or species or default_species,
                    study_type=raw.get("study_type") or study_type,
                    confidence=raw.get("confidence") or "HIGH",
                )
            else:
                mv = MeasuredValue(value=float(raw), unit=unit, reference=_ref,
                                   species=species or default_species,
                                   study_type=study_type)
            err = self._physical_error(name, mv.value)
            if err:
                raise ValueError(f"{_ref}: {err}")
            return mv

        result.fu_plasma          = _mv("fu_plasma", "fu_plasma", "dimensionless")
        result.t_half_h           = _mv("t_half_h", "t_half_h", "h")
        result.auc_inf_ngmlh      = _mv("auc_inf_ngmlh", "auc_inf_ngmlh", "ng·h/mL")
        result.cmax_ngml          = _mv("cmax_ngml", "cmax_ngml", "ng/mL")
        result.vd_lkg             = _mv("vd_lkg", "vd_lkg", "L/kg")
        result.cl_mlminkg         = _mv("cl_mlminkg", "cl_mlminkg", "mL/min/kg")
        result.bioavailability_pct = _mv("bioavailability_pct", "bioavailability_pct", "%")
        result.tmax_h             = _mv("tmax_h", "tmax_h", "h")
        result.t_half_h_preclinical = _mv("t_half_h_preclinical", "t_half_h_preclinical", "h")
        result.vd_lkg_preclinical = _mv("vd_lkg_preclinical", "vd_lkg_preclinical", "L/kg")
        noael_species = data.get("noael_species") or None
        result.noael_mg_kg_day    = _mv("noael_mg_kg_day", "noael_mg_kg_day", "mg/kg/day",
                                        species=noael_species,
                                        study_type=data.get("noael_study_duration", ""))
        result.noael_species      = data.get("noael_species") or (
            result.noael_mg_kg_day.species
            if result.noael_mg_kg_day and result.noael_mg_kg_day.species != UNSPECIFIED_SPECIES
            else ""
        )
        result.noael_study_duration = data.get("noael_study_duration", "")

        # hERG is an in vitro assay: the study species does not apply to it.
        herg_key = "herg_ic50_uM" if data.get("herg_ic50_uM") is not None else "herg_ic50_uM_measured"
        result.herg_ic50_uM_measured = _mv(herg_key, "herg_ic50_uM_measured", "µM",
                                           species=UNSPECIFIED_SPECIES,
                                           study_type="herg_patch_clamp")

        result.ames_in_vitro           = self._binary_label(
            data.get("ames_result", data.get("ames_in_vitro")))
        result.chromosomal_aberration  = self._binary_label(data.get("chromosomal_aberration"))
        result.micronucleus            = self._binary_label(
            data.get("micronucleus", data.get("micronucleus_result")))
        result.repeat_dose_tox_summary = data.get("repeat_dose_tox_summary", "")
        result.genotox_battery_result  = self._derive_genotox_verdict(result)

        return result

    @staticmethod
    def _binary_label(value) -> Optional[str]:
        """Normalise a genotox result; the PDF extractor stores Ames as a bool."""
        if value is None:
            return None
        if isinstance(value, bool):
            return "positive" if value else "negative"
        return str(value)

    def ingest_text(self, text: str,
                    drug_name: str = "",
                    source_reference: str = "text_extract") -> WetLabStudyData:
        """
        Extract PK/safety data from raw regulatory document text (plain text or PDF extract).
        Uses pattern matching calibrated on FDA NDA nonclinical review format.

        Provenance rules:
          - species comes from the value's line, else from the document when it
            names exactly one species, else "unspecified";
          - a value on a line with prediction language, or any value in a
            document that declares itself prediction-only, is recorded in
            ``predicted_values`` (confidence LOW), never as a measurement;
          - measured confidence is HIGH when the line says the value was
            measured/observed, MEDIUM otherwise;
          - GLP status is True/False only when the text states it, else None.
        """
        from datetime import datetime, timezone
        result = WetLabStudyData(
            drug_name=drug_name,
            source_document=source_reference,
            ingested_at=datetime.now(timezone.utc).isoformat(),
            glp_certified=detect_glp_status(text),
        )
        prediction_only = is_prediction_only(text)
        if prediction_only:
            result.provenance_warnings.append(
                "Source states it contains computational predictions only; "
                "no value was recorded as a measurement."
            )
        if len(species_mentioned(text)) > 1:
            result.provenance_warnings.append(
                f"Source names several species ({', '.join(sorted(species_mentioned(text)))}); "
                "values without a species on their own line are 'unspecified'."
            )

        def place(name: str, value: float, unit: str, m: re.Match, study_type: str = "",
                  species: Optional[str] = None, in_vitro: bool = False) -> None:
            line = line_at(text, m.start(), m.end())
            err = self._physical_error(name, value)
            if err:
                result.provenance_warnings.append(f"Ignored '{line.strip()}': {err}")
                return
            if species is None:
                species = resolve_species(line, "" if in_vitro else text)
            predicted = prediction_only or has_prediction_language(line)
            mv = MeasuredValue(
                value=value, unit=unit, reference=source_reference, species=species,
                study_type=study_type,
                source=PREDICTED if predicted else MEASURED,
                confidence="LOW" if predicted else ("HIGH" if has_measurement_language(line) else "MEDIUM"),
            )
            if predicted:
                result.predicted_values[name] = asdict(mv)
            else:
                setattr(result, name, mv)

        # PK extraction
        hit = self._extract_fu_plasma(text)
        if hit:
            place("fu_plasma", hit[0], "dimensionless", hit[1], study_type="plasma_protein_binding")
        for name, param, unit in (("t_half_h", "t_half_h", "h"), ("vd_lkg", "vd", "L/kg"),
                                  ("cl_mlminkg", "cl", "mL/min/kg"),
                                  ("bioavailability_pct", "bioavailability", "%")):
            hit = self._extract_pk_value(text, param)
            if hit:
                place(name, hit[0], unit, hit[2])
        for name, param, unit in (("cmax_ngml", "cmax", "ng/mL"),
                                  ("auc_inf_ngmlh", "auc_inf", "ng·h/mL")):
            hit = self._extract_pk_value(text, param)
            if hit:
                value, raw_unit, m = hit
                if raw_unit[:1].lower() in ("µ", "μ", "u"):
                    value *= 1000.0   # µg → ng; stored in the field's ng-based unit
                place(name, value, unit, m)

        # Safety extraction
        hit = self._extract_herg(text)
        if hit:
            place("herg_ic50_uM_measured", hit[0], "µM", hit[1],
                  study_type="herg_patch_clamp", in_vitro=True)
        hit = self._extract_noael(text)
        if hit:
            value, captured_species, m = hit
            place("noael_mg_kg_day", value, "mg/kg/day", m,
                  study_type="repeat_dose_tox", species=captured_species)
            if result.noael_mg_kg_day and result.noael_mg_kg_day.species != UNSPECIFIED_SPECIES:
                result.noael_species = result.noael_mg_kg_day.species

        for name, param in (("ames_in_vitro", "ames"),
                            ("chromosomal_aberration", "chromosomal_aberration"),
                            ("micronucleus", "micronucleus")):
            hit = self._extract_binary_result(text, param)
            if not hit:
                continue
            label, m = hit
            line = line_at(text, m.start(), m.end())
            if prediction_only or has_prediction_language(line):
                result.predicted_values[name] = {
                    "result": label, "source": PREDICTED,
                    "reference": source_reference, "confidence": "LOW",
                }
            else:
                setattr(result, name, label)
        result.genotox_battery_result = self._derive_genotox_verdict(result)

        log.info("[wetlab_ingester] Extracted from '%s': fu_plasma=%s, t_half=%s, hERG=%s, Ames=%s, "
                 "predicted=%s, glp=%s",
                 source_reference,
                 result.fu_plasma.value if result.fu_plasma else "N/A",
                 result.t_half_h.value if result.t_half_h else "N/A",
                 result.herg_ic50_uM_measured.value if result.herg_ic50_uM_measured else "N/A",
                 result.ames_in_vitro, sorted(result.predicted_values), result.glp_certified)

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
    # Each returns the parsed value(s) plus the regex match so the caller can
    # read the surrounding line for species and measured/predicted language.

    def _extract_fu_plasma(self, text: str) -> Optional[tuple[float, re.Match]]:
        """Extract fu_plasma, handling both fu=0.035 and PPB=96.5% formats."""
        for pat in self._PK_PATTERNS["fu_plasma"]:
            m = re.search(pat, text, re.IGNORECASE)
            if m:
                try:
                    val = float(m.group(1).replace(",", ""))
                except ValueError:
                    continue
                # If value > 1.0, it's PPB% → convert to fu
                if val > 1.0:
                    if val > 100.0:
                        continue
                    val = round(1.0 - val / 100.0, 4)
                return val, m
        return None

    def _extract_pk_value(self, text: str, param: str) -> Optional[tuple[float, str, re.Match]]:
        for pat in self._PK_PATTERNS.get(param, []):
            m = re.search(pat, text, re.IGNORECASE)
            if m:
                try:
                    val = float(m.group(1).replace(",", ""))
                except (ValueError, IndexError):
                    continue
                unit = m.group(2) if m.lastindex and m.lastindex >= 2 else ""
                return val, unit, m
        return None

    def _extract_herg(self, text: str) -> Optional[tuple[float, re.Match]]:
        for pat in self._SAFETY_PATTERNS.get("herg_ic50", []):
            m = re.search(pat, text, re.IGNORECASE)
            if m:
                try:
                    val = float(m.group(1).replace(",", ""))
                except (ValueError, IndexError):
                    continue
                unit_str = m.group(2) if m.lastindex and m.lastindex >= 2 else "µM"
                if "nM" in unit_str:
                    val = val / 1000.0  # convert nM to µM
                return val, m
        return None

    def _extract_binary_result(self, text: str, param: str) -> Optional[tuple[str, re.Match]]:
        for pat in self._SAFETY_PATTERNS.get(param, []):
            m = re.search(pat, text, re.IGNORECASE)
            if not m:
                continue
            # Patterns that imply result from full match (no capture group)
            if m.lastindex is None or m.lastindex == 0:
                matched = m.group(0).lower()
                if "no " in matched and ("aberration" in matched or "mutagenic" in matched):
                    return "negative", m
                if "induced" in matched or "positive" in matched or "mutagenic" in matched:
                    return "positive", m
                continue
            result_str = m.group(1).lower().strip()
            if "not mutagenic" in result_str or "negative" in result_str:
                return "negative", m
            elif "mutagenic" in result_str or "positive" in result_str:
                return "positive", m
            elif "equivocal" in result_str:
                return "equivocal", m
        return None

    def _extract_noael(self, text: str) -> Optional[tuple[float, Optional[str], re.Match]]:
        """Return (value, species named right after the value or None, match)."""
        for pat in self._SAFETY_PATTERNS.get("noael", []):
            m = re.search(pat, text, re.IGNORECASE)
            if m:
                try:
                    val = float(m.group(1).replace(",", ""))
                except (ValueError, IndexError):
                    continue
                captured = m.group(2) if m.lastindex and m.lastindex >= 2 else None
                named = species_mentioned(captured) if captured else set()
                return val, (next(iter(named)) if len(named) == 1 else None), m
        return None

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
