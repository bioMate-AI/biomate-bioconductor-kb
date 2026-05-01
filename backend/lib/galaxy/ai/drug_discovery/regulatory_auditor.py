"""
BioMate Regulatory Auditor — Hybrid Compliance Checker

Audit architecture: two-tier hybrid

  TIER 1 — Regex/deterministic (structure, format, exact values):
    • Section presence / ordering (ICH M4 §2.6 structure)
    • Table count and syntax
    • Title page required fields
    • Exact numeric threshold values (hERG IC50, PBPK 67%)
    • Guideline citation strings (e.g. "S7B", "S2(R1)")
    • Flag count consistency (document vs safety_profile data)
    • Document length gate
    Regex is exact, zero-cost, reproducible. Right tool for binary structural checks.

  TIER 2 — LLM semantic judge (content adequacy, quality, nuance):
    • Is the mechanistic DILI discussion substantive (not just a keyword)?
    • Does the in silico disclaimer genuinely warn about limitations?
    • Is the ethnic bridging section adequate for the stated region?
    • Does the AI-disclosure satisfy FDA/EMA Jan 2026 guidance?
    • Does §2.6.1.2 provide a genuine PBPK interpretation, not boilerplate?
    LLM batches all semantic checks into ONE call (Haiku, structured JSON output).
    Regex cannot detect "No reactive metabolite assessment" as a failure — LLM can.

Returns a list of AuditFinding objects with severity levels:
  CRITICAL  — document cannot be submitted without this fix
  MAJOR     — required by guidelines; should be fixed before submission
  MINOR     — best practice; recommended but not mandatory
  INFO      — informational; no action required

Runs automatically as part of INDSectionAssembler.assemble().
Can also be run standalone: RegulatoryAuditor(region).audit(markdown, ctx)
"""

from __future__ import annotations

import json
import logging
import re
from dataclasses import dataclass, field
from typing import Optional, TypedDict

from .ind_assembly import _load_regulatory_kb, get_threshold

log = logging.getLogger(__name__)


# ─── Semantic check definition ────────────────────────────────────────────────

class SemanticCheck(TypedDict):
    code:         str   # machine-readable check code
    severity:     str   # CRITICAL | MAJOR | MINOR | INFO
    section:      str   # CTD section it applies to
    guideline_id: str
    region:       str   # ALL | FDA | EMA | NMPA | PMDA
    question:     str   # plain-English question for the LLM judge
    pass_criteria: str  # what a passing answer looks like (fed to LLM)
    suggestion:   str   # remediation guidance shown in the finding


# Checks that require semantic judgment — regex would produce false positives/negatives
_SEMANTIC_CHECKS: list[SemanticCheck] = [
    {
        "code": "EMA-DILI-MECH-001",
        "severity": "MAJOR",
        "section": "2.6.3.2",
        "guideline_id": "EMA_DILI_2021",
        "region": "EMA",
        "question": (
            "Does section 2.6.3.2 (Repeat-Dose Toxicity) contain a SUBSTANTIVE mechanistic DILI "
            "assessment? A substantive assessment must: (1) identify specific reactive metabolite "
            "structural alert classes (e.g. Michael acceptor, quinone precursor, acyl glucuronide, "
            "epoxide), (2) present results of a structural alert screen (per compound or for lead), "
            "and (3) cite EMA DILI Reflection Paper (EMA/CHMP/HMPC/700003/2012) or equivalent. "
            "A brief mention of 'DILI' or 'no reactive metabolite assessment' does NOT qualify."
        ),
        "pass_criteria": "Section contains a table or list of structural alert classes with per-compound results AND cites EMA DILI guidance.",
        "suggestion": "Add _mechanistic_dili_block() content: structural alert SMARTS screen table, alert class definitions, EMA/CHMP/HMPC/700003/2012 citation.",
    },
    {
        "code": "PK-DISC-QUALITY-001",
        "severity": "MAJOR",
        "section": "2.6.2",
        "guideline_id": "ICH_M4S_R2",
        "region": "ALL",
        "question": (
            "Does section 2.6.2 (Pharmacokinetics) contain a GENUINE disclaimer that in silico PK "
            "predictions require experimental confirmation? The disclaimer must explicitly state that "
            "computational predictions should be supplemented with wet-lab DMPK studies (e.g. microsomal "
            "stability, Caco-2, plasma protein binding) before IND filing or Phase I dose escalation. "
            "A section that only uses words like 'predicted' or 'model' without a genuine limitation "
            "statement does NOT pass."
        ),
        "pass_criteria": "Contains a clear statement that in silico values require experimental validation before clinical use.",
        "suggestion": "Add explicit disclaimer: 'In silico PK predictions should be supplemented with in vitro DMPK studies prior to IND filing.'",
    },
    {
        "code": "AI-DISC-QUALITY-001",
        "severity": "MINOR",
        "section": "title",
        "guideline_id": "FDA_AI_GUIDANCE_2026",
        "region": "ALL",
        "question": (
            "Does the document contain an adequate AI-disclosure statement per FDA/EMA Joint Guidance "
            "on Good AI Practice in Drug Development (January 2026)? The disclosure must: (1) state that "
            "the document was AI-assisted or generated by an automated system, (2) indicate that a human "
            "reviewed and approved it, and (3) either appear on the title page or as a standing disclaimer. "
            "A generic 'computational methods were used' statement is NOT sufficient."
        ),
        "pass_criteria": "Contains explicit 'AI-assisted' or 'automated draft' language plus 'human reviewed/approved'.",
        "suggestion": "Add to title page: 'AI-assisted draft — human reviewed and approved [DATE] by [NAME], per FDA/EMA Good AI Practice Guidance (Jan 2026).'",
    },
    {
        "code": "ETHNIC-BRIDGING-QUALITY-001",
        "severity": "MINOR",
        "section": "2.6.2",
        "guideline_id": "ICH_E5",
        "region": "ALL",
        "question": (
            "If the document contains an ethnic bridging section (§2.6.2.8 or equivalent), is the "
            "content substantive? A substantive section must: (1) name at least one specific CYP "
            "polymorphism (CYP2C19, CYP2D6, CYP3A4) with quantitative prevalence difference between "
            "populations, (2) specify which ethnic group(s) are relevant (East Asian, Japanese, etc.), "
            "and (3) state what follow-up study is recommended. If there is NO ethnic bridging section "
            "at all, return pass=true (absence is handled separately)."
        ),
        "pass_criteria": "Contains CYP polymorphism prevalences, named populations, and follow-up study recommendation.",
        "suggestion": "Add CYP2C19 poor metabolizer frequency comparison (14-22% East Asian vs 2-6% European) and recommended bridging PK study.",
    },
    {
        "code": "PBPK-INTERP-QUALITY-001",
        "severity": "MINOR",
        "section": "2.6.1.2",
        "guideline_id": "EMA_PBPK_2018",
        "region": "ALL",
        "question": (
            "Does section 2.6.1.2 (PBPK Model Qualification) contain a genuine scientific interpretation "
            "of the validation results — not just a table of numbers? A genuine interpretation must: "
            "(1) compare the metrics to the EMA criterion (≥67% within 2-fold), (2) explicitly state "
            "whether the criterion was met or not met with the exact percentage, and (3) draw a conclusion "
            "about model suitability for IND submission. A table of numbers without interpretive text fails."
        ),
        "pass_criteria": "Contains explicit pass/fail statement with percentage AND a conclusion sentence about IND suitability.",
        "suggestion": "Add a narrative sentence: 'The model [meets/does not meet] the EMA criterion with X% of predictions within 2-fold; this [supports/does not support] use of PBPK for IND filing.'",
    },
]

# ─── LLM semantic judge ───────────────────────────────────────────────────────

_JUDGE_SYSTEM = """\
You are a regulatory compliance expert reviewing IND §2.6 (Nonclinical Overview) documents.
You will be given a document and a list of semantic compliance checks to perform.
For each check, assess whether the document content passes or fails the stated criteria.
Be strict: keyword presence alone does not constitute a pass — evaluate substantive content quality.
Return ONLY valid JSON matching the schema provided. No prose outside the JSON."""

_JUDGE_PROMPT_TEMPLATE = """\
Document sections to review (truncated to relevant sections):
---
{sections}
---

Perform the following semantic compliance checks. For each check:
- Read the question carefully
- Evaluate the document content against the pass_criteria
- Return pass=true only if the document GENUINELY satisfies the criteria
- Include a short evidence quote (≤80 chars) from the document that supports your verdict

Checks:
{checks_json}

Return JSON in this exact format:
{{
  "results": [
    {{"code": "CHECK_CODE", "pass": true/false, "confidence": 0.0-1.0, "evidence": "brief quote or observation"}}
  ]
}}
"""

# ─── Finding data model ───────────────────────────────────────────────────────

CRITICAL = "CRITICAL"
MAJOR    = "MAJOR"
MINOR    = "MINOR"
INFO     = "INFO"

_SEVERITY_ORDER = {CRITICAL: 0, MAJOR: 1, MINOR: 2, INFO: 3}


@dataclass
class AuditFinding:
    severity:     str          # CRITICAL / MAJOR / MINOR / INFO
    section:      str          # e.g. "2.6.1.2"
    guideline_id: str          # e.g. "EMA_PBPK_2018"
    region:       str          # e.g. "EMA" or "ALL"
    code:         str          # machine-readable code, e.g. "EMA-PBPK-001"
    description:  str          # human-readable finding
    suggestion:   str          # how to fix
    evidence:     str = ""     # excerpt from document (if applicable)

    def __str__(self) -> str:
        return f"[{self.severity}] {self.code} §{self.section} ({self.region}): {self.description}"


# ─── Auditor ─────────────────────────────────────────────────────────────────

class RegulatoryAuditor:
    """
    Run after every IND assembly to produce structured compliance findings.

    Usage:
        auditor = RegulatoryAuditor(region="EMA")
        findings = auditor.audit(markdown_content, ctx)
        critical = [f for f in findings if f.severity == CRITICAL]
    """

    # ICH M4S(R2) required headings in §2.6.1–§2.6.3
    REQUIRED_HEADINGS = [
        ("2.6.1.1", "Overview of Computational Methods"),
        ("2.6.1.2", "PBPK Model Qualification"),
        ("2.6.1.3", "ADMET Screening Results"),
        ("2.6.1.4", "Compound Prioritization"),
        ("2.6.1.5", "Applicability Domain"),
        ("2.6.1.6", "Audit Trail"),
        ("2.6.2",   "Pharmacokinetics"),
        ("2.6.3",   "Toxicology"),
    ]

    # Required ICH guideline citations
    REQUIRED_CITATIONS = {
        "ICH_S7B":    (r"S7B", "2.6.3"),
        "ICH_S2_R1":  (r"S2\(R1\)", "2.6.3.3"),
        "EMA_PBPK":   (r"EMA|37498", "2.6.1.2"),
        "21CFR_P11":  (r"21 CFR Part 11|21 CFR 11\.10", "2.6.1.6"),
        "EMA_CRIT":   (r"67%|≥67|within.?2.fold", "2.6.1.2"),
    }

    # PBPK table required columns (patterns matched against PBPK section)
    PBPK_TABLE_COLS = ["AFE", "AAFE", r"R[²2²]", r"2.?fold"]

    def __init__(self, region: str = "ALL", semantic: bool = True):
        self.region = region
        self.semantic = semantic   # set False in unit tests to skip LLM calls
        self.kb = _load_regulatory_kb()
        self._findings: list[AuditFinding] = []

    # ── Public entry point ────────────────────────────────────────────────────

    def audit(self, markdown: str, ctx: dict) -> list[AuditFinding]:
        """
        Run all audit checks and return findings sorted by severity.

        Tier 1 (regex): structure, format, exact values — always runs.
        Tier 2 (LLM):   semantic adequacy checks — one batched call.

        Args:
            markdown: Full assembled document text.
            ctx:      Assembly context dict (molecule_name, validation_report, etc.)

        Returns:
            List of AuditFinding sorted CRITICAL → MAJOR → MINOR → INFO.
        """
        self._findings = []

        # ── Tier 1: deterministic/structural checks ───────────────────────
        self._check_structure(markdown)
        self._check_section_content(markdown, ctx)
        self._check_citations(markdown)
        self._check_pbpk_metrics(markdown, ctx)
        self._check_safety_gates(markdown, ctx)
        self._check_format(markdown)
        self._check_region_specific(markdown, ctx)
        self._check_thresholds(markdown)
        self._check_disclaimer(markdown)
        self._check_osp_benchmarks(markdown, ctx)

        # ── Tier 2: LLM semantic adequacy checks (batched, one call) ─────
        if self.semantic:
            self._check_semantic(markdown, ctx)

        return sorted(self._findings, key=lambda f: _SEVERITY_ORDER.get(f.severity, 9))

    # ── Tier 2: LLM semantic judge ────────────────────────────────────────────

    def _check_semantic(self, md: str, ctx: dict) -> None:
        """
        Run all semantic adequacy checks via a single batched LLM call.

        Active checks are filtered by region and by whether the relevant section
        exists (skips checks for sections not present in the document).
        """
        # Filter checks to those relevant for this region
        active = [
            c for c in _SEMANTIC_CHECKS
            if c["region"] in ("ALL", self.region)
        ]

        # Additional region filter: EMA-DILI-MECH-001 only when triggered
        sp = ctx.get("safety_profile", {})
        pk_sum = ctx.get("pk_summary", {}) or {}
        dili_flagged = sp.get("dili_flagged", 0)
        cl_h = pk_sum.get("cl_hepatic_fraction", 0) or 0

        if not (dili_flagged > 0 and cl_h >= 0.5):
            active = [c for c in active if c["code"] != "EMA-DILI-MECH-001"]

        if not active:
            return

        # Gather relevant section texts (truncated to keep prompt manageable)
        sections_text = self._build_sections_for_judge(md)

        checks_payload = [
            {"code": c["code"], "question": c["question"], "pass_criteria": c["pass_criteria"]}
            for c in active
        ]

        prompt = _JUDGE_PROMPT_TEMPLATE.format(
            sections=sections_text,
            checks_json=json.dumps(checks_payload, indent=2),
        )

        try:
            results = self._call_llm_judge(prompt)
        except Exception as exc:
            log.warning("[semantic_audit] LLM judge failed, skipping semantic checks: %s", exc)
            return

        # Map results back to findings
        check_map = {c["code"]: c for c in active}
        for r in results.get("results", []):
            code = r.get("code", "")
            if code not in check_map:
                continue
            passed = r.get("pass", True)
            confidence = r.get("confidence", 0.5)
            evidence = r.get("evidence", "")
            if not passed and confidence >= 0.6:
                c = check_map[code]
                self._add(c["severity"], c["section"], c["guideline_id"],
                          c["region"], code,
                          f"[Semantic judge] {c['question'][:120]}",
                          c["suggestion"], evidence=f"LLM evidence (conf={confidence:.0%}): {evidence}")

    def _build_sections_for_judge(self, md: str) -> str:
        """Extract relevant section text for the LLM judge, keeping prompt size small.

        Uses flexible heading matching (## or ###) to avoid missing sub-sections.
        """
        parts = []

        # Title page (first 600 chars)
        parts.append(f"[TITLE PAGE]\n{md[:600]}")

        # §2.6.1.2 PBPK (via ## heading)
        pbpk = self._extract_section(md, "2.6.1.2", "2.6.1.3")
        if pbpk:
            parts.append(f"[§2.6.1.2 PBPK]\n{pbpk[:800]}")

        # §2.6.2 full PK section
        pk = self._extract_section(md, "2.6.2", "2.6.3")
        if pk:
            parts.append(f"[§2.6.2 Pharmacokinetics]\n{pk[:800]}")

        # §2.6.3 full toxicology section (includes 2.6.3.2 sub-heading as ###)
        # Use regex to find ## 2.6.3 through end of document
        tox_m = re.search(r'^##\s+2\.6\.3\b', md, re.MULTILINE)
        if tox_m:
            tox_text = md[tox_m.start():]
            parts.append(f"[§2.6.3 Toxicology (incl. §2.6.3.2)]\n{tox_text[:1200]}")

        return "\n\n---\n\n".join(parts)

    def _call_llm_judge(self, prompt: str) -> dict:
        """Call Haiku (fast/cheap) for semantic audit judgment. Returns parsed JSON."""
        try:
            import anthropic
            client = anthropic.Anthropic()
            msg = client.messages.create(
                model="claude-haiku-4-5-20251001",
                max_tokens=1024,
                system=_JUDGE_SYSTEM,
                messages=[{"role": "user", "content": prompt}],
            )
            text = msg.content[0].text.strip()
            # Extract JSON even if model wraps in markdown code block
            if "```" in text:
                text = re.search(r"```(?:json)?\s*(.*?)```", text, re.DOTALL).group(1).strip()
            return json.loads(text)
        except Exception:
            # Fallback to Gemini Flash if Anthropic not available
            try:
                from galaxy.ai.gemini_flash import call_gemini_flash as _gemini
                resp = _gemini(
                    messages=[{"role": "user", "content": prompt}],
                    system=_JUDGE_SYSTEM,
                    max_tokens=1024,
                    temperature=0.1,
                )
                text = resp.strip()
                if "```" in text:
                    m = re.search(r"```(?:json)?\s*(.*?)```", text, re.DOTALL)
                    text = m.group(1).strip() if m else text
                return json.loads(text)
            except Exception as exc2:
                raise RuntimeError(f"Both LLM backends failed: {exc2}") from exc2

    # ── Structural checks (ICH M4S(R2)) ──────────────────────────────────────

    def _check_structure(self, md: str) -> None:
        """All 8 required section headings must be present."""
        for sec_id, keyword in self.REQUIRED_HEADINGS:
            if sec_id not in md:
                self._add(CRITICAL, sec_id, "ICH_M4S_R2", "ALL",
                          f"STRUCT-{sec_id.replace('.', '')}",
                          f"Section {sec_id} ({keyword}) is missing from the document.",
                          "Ensure INDSectionAssembler generates all required §2.6 sub-sections.")
            else:
                # Check section is not empty (at least 100 chars of content after heading)
                start = md.find(sec_id)
                next_sec = md.find("\n## ", start + 1)
                body = md[start:next_sec if next_sec > 0 else start + 2000]
                # Remove the heading line itself
                content_lines = [l for l in body.split("\n")[1:] if l.strip()]
                content_len = sum(len(l) for l in content_lines)
                if content_len < 80:
                    self._add(MAJOR, sec_id, "ICH_M4S_R2", "ALL",
                              f"EMPTY-{sec_id.replace('.', '')}",
                              f"Section {sec_id} body is too short ({content_len} chars). May appear empty to reviewers.",
                              "Ensure section body has substantive content per ICH M4S(R2).",
                              evidence=body[:200])

    # ── Section content checks ────────────────────────────────────────────────

    def _check_section_content(self, md: str, ctx: dict) -> None:
        """Content-level checks for each section."""

        # §2.6.1.2 PBPK: EMA criterion result must be stated explicitly
        pbpk_section = self._extract_section(md, "2.6.1.2", "2.6.1.3")
        if pbpk_section:
            if not re.search(r"EMA criterion.*(?:MET|NOT MET|✓|✗)", pbpk_section, re.IGNORECASE):
                self._add(MAJOR, "2.6.1.2", "EMA_PBPK_2018", "EMA",
                          "EMA-PBPK-001",
                          "EMA PBPK criterion pass/fail result not explicitly stated in §2.6.1.2.",
                          "Add 'EMA criterion (≥67% within 2-fold): MET ✓/NOT MET ✗' line.")

        # §2.6.1.3 ADMET: safety gate table must be present
        admet_section = self._extract_section(md, "2.6.1.3", "2.6.1.4")
        if admet_section:
            if "hERG" not in admet_section or "|" not in admet_section:
                self._add(MAJOR, "2.6.1.3", "ICH_S7B", "ALL",
                          "ADMET-TABLE-001",
                          "§2.6.1.3 is missing the safety gate table (hERG, DILI, Ames).",
                          "Ensure _section_admet() generates the safety gates table.")

        # §2.6.1.6 Audit trail: hash chain integrity must be stated
        audit_section = self._extract_section(md, "2.6.1.6", "2.6.2")
        if audit_section:
            if "VALID" not in audit_section and "chain integrity" not in audit_section.lower():
                self._add(MINOR, "2.6.1.6", "FDA_21CFR_PART11", "FDA",
                          "AUDIT-CHAIN-001",
                          "Hash chain integrity status not stated in §2.6.1.6.",
                          "Ensure audit_summary includes chain_valid field and it is shown in document.")

        # §2.6.2: disclaimer for in silico predictions required
        pk_section = self._extract_section(md, "2.6.2", "2.6.3")
        if pk_section:
            if not re.search(
                r"experimental confirmation|supplemented with|in vitro DMPK|in silico.*predict|predict.*supplement|computational.*prediction",
                pk_section, re.IGNORECASE
            ):
                self._add(MAJOR, "2.6.2", "ICH_M4S_R2", "ALL",
                          "PK-DISC-001",
                          "§2.6.2 does not contain a disclaimer that in silico PK predictions require experimental confirmation.",
                          "Add: 'In silico PK predictions should be supplemented with in vitro DMPK studies prior to IND filing.'")

        # §2.6.3.3 Genotoxicity: ICH S2(R1) in vitro follow-up note required
        geno_section = self._extract_section(md, "2.6.3.3", "2.6.3.4")
        if geno_section:
            strains = ["TA98", "TA100", "TA1535"]
            if not any(s in geno_section for s in strains):
                self._add(MAJOR, "2.6.3.3", "ICH_S2_R1", "ALL",
                          "GENO-STRAIN-001",
                          "§2.6.3.3 does not cite required Ames test strains (TA98, TA100, TA1535).",
                          "Add: 'Salmonella typhimurium strains TA98, TA100, TA102, TA1535 ± S9 per ICH S2(R1).'",
                          evidence=geno_section[:300])

        # §2.6.3.7 Cardiac: ICH S7B threshold cited
        cardiac_section = self._extract_section(md, "2.6.3.7", None)
        if cardiac_section:
            threshold = get_threshold("hERG", "value_uM", 10.0)
            if str(int(threshold)) not in cardiac_section:
                self._add(MAJOR, "2.6.3.7", "ICH_S7B", "ALL",
                          "CARD-THRESH-001",
                          f"§2.6.3.7 does not cite the ICH S7B hERG IC50 threshold ({threshold} µM).",
                          f"Add: 'hERG IC50 threshold for concern: {threshold} µM (ICH S7B).'")

    # ── Citation checks ───────────────────────────────────────────────────────

    def _check_citations(self, md: str) -> None:
        """Required guideline citations must appear in the document."""
        for name, (pattern, expected_section) in self.REQUIRED_CITATIONS.items():
            if not re.search(pattern, md):
                sev = MAJOR if name.startswith("ICH") or name.startswith("EMA") else MINOR
                self._add(sev, expected_section, name, "ALL",
                          f"CITE-{name.replace('_', '-')}",
                          f"Required citation '{name}' ({pattern}) not found in document.",
                          f"Ensure LLM narrative or template text cites {name} in §{expected_section}.")

    # ── PBPK metric completeness ──────────────────────────────────────────────

    def _check_pbpk_metrics(self, md: str, ctx: dict) -> None:
        """PBPK table must contain all EMA-required metrics."""
        pbpk = self._extract_section(md, "2.6.1.2", "2.6.1.3")
        if not pbpk:
            return  # already caught by structure check

        for col in self.PBPK_TABLE_COLS:
            if not re.search(col, pbpk):
                self._add(MAJOR, "2.6.1.2", "EMA_PBPK_2018", "EMA",
                          f"PBPK-COL-{col.replace('[', '').replace(']', '').replace('²2', 'R2')}",
                          f"PBPK table missing '{col}' column — required by EMA/CHMP/EWP/37498/2011 Rev1.",
                          "Add column to PBPK aggregate metrics table.")

        # EMA: within-3-fold also required per Rev1
        if "3-fold" not in pbpk and "3fold" not in pbpk.lower():
            self._add(MINOR, "2.6.1.2", "EMA_PBPK_2018", "EMA",
                      "PBPK-3FOLD-001",
                      "PBPK table missing within-3-fold row (EMA Rev1 recommends both 2-fold and 3-fold).",
                      "Add 'Within 3-fold' row to PBPK metrics table.")

        # FDA: Model Assumptions & Limitations
        if self.region in ("FDA", "ALL"):
            if "assumption" not in md.lower() and "limitation" not in md.lower():
                self._add(MAJOR, "2.6.2", "FDA_PBPK_2018", "FDA",
                          "FDA-PBPK-ASSUMP-001",
                          "§2.6.2 missing 'Model Assumptions and Limitations' table required by FDA PBPK Guidance (Sep 2018, Table 2).",
                          "Add _section_pbpk_assumptions() generating: Model type, Assumptions, Limitations, Sensitivity analysis note.",
                          evidence="FDA PBPK Guidance (Sep 2018) Table 2 requires this content for all PBPK submissions.")

    # ── Safety gate completeness ──────────────────────────────────────────────

    def _check_safety_gates(self, md: str, ctx: dict) -> None:
        """Safety flag counts must be internally consistent."""
        sp = ctx.get("safety_profile", {})
        if not sp or sp.get("total_compounds", 0) == 0:
            return

        total = sp.get("total_compounds", 0)

        # Check that flag counts appear in document
        for gate, key in [("hERG", "herg_flagged"), ("DILI", "dili_flagged"), ("Ames", "ames_flagged")]:
            expected = sp.get(key, 0)
            # Look for the flag count in document
            pattern = rf'{gate}-flagged[^\n]*?\*\*(\d+)\*\*'
            m = re.search(pattern, md)
            if m:
                doc_count = int(m.group(1))
                if doc_count != expected:
                    self._add(CRITICAL, "2.6.1.3", "ICH_M4S_R2", "ALL",
                              f"GATE-COUNT-{gate.upper()}",
                              f"§2.6.1.3 reports {gate}-flagged={doc_count} but safety_profile has {expected}. Data inconsistency.",
                              "Re-generate document; check _load_safety_profile() calculation.",
                              evidence=f"Document: {doc_count}, Safety profile: {expected}")
            else:
                self._add(MINOR, "2.6.1.3", "ICH_M4S_R2", "ALL",
                          f"GATE-MISSING-{gate.upper()}",
                          f"§2.6.1.3 does not display {gate}-flagged count explicitly.",
                          f"Add '{gate}-flagged (IC50 < 10 µM): **N**' line to ADMET Results.")

    # ── Format checks ─────────────────────────────────────────────────────────

    def _check_format(self, md: str) -> None:
        """ICH M4S(R2) format requirements."""

        # Title page: required fields
        for field_name, pattern in [
            ("Molecule", r"\*\*Molecule:\*\*"),
            ("Sponsor",  r"\*\*Sponsor:\*\*"),
            ("Campaign ID", r"\*\*Campaign ID:\*\*"),
            ("Generation date", r"\*\*Generation date:\*\*"),
        ]:
            if not re.search(pattern, md):
                self._add(MINOR, "title", "ICH_M4S_R2", "ALL",
                          f"FORMAT-TITLE-{field_name.replace(' ', '')}",
                          f"Title page missing '{field_name}' field.",
                          f"Add '**{field_name}:** ...' to title page.")

        # Section numbering: must be sequential
        sec_nums = re.findall(r'## (2\.6\.\d+(?:\.\d+)?)', md)
        expected_order = ["2.6.1.1","2.6.1.2","2.6.1.3","2.6.1.4","2.6.1.5","2.6.1.6","2.6.2","2.6.3"]
        found = [s for s in expected_order if s in sec_nums]
        if found != expected_order[:len(found)]:
            self._add(MAJOR, "2.6", "ICH_M4S_R2", "ALL",
                      "FORMAT-ORDER-001",
                      "Section headings are not in correct ICH M4 order.",
                      "Check that sections are appended in the correct §2.6.1.1→...→§2.6.3 order.",
                      evidence=f"Found order: {found}")

        # Tables: markdown table syntax check
        tables = re.findall(r'\|[^\n]+\|\n\|[-: |]+\|\n', md)
        if len(tables) < 3:
            self._add(MINOR, "2.6", "ICH_M4S_R2", "ALL",
                      "FORMAT-TABLE-001",
                      f"Only {len(tables)} properly formatted markdown tables found. Expected ≥3 (PBPK, ADMET, audit).",
                      "Ensure PBPK metrics, safety gate, and audit trail tables use proper markdown syntax.")

        # Document length: minimum for a credible §2.6.1–2.6.3 package
        if len(md) < 12_000:
            self._add(MAJOR, "2.6", "ICH_M4S_R2", "ALL",
                      "FORMAT-LENGTH-001",
                      f"Document is only {len(md)} chars. A complete §2.6.1–2.6.3 package should be ≥12,000 chars.",
                      "Check that all sections are generating content and LLM narratives are not failing silently.")

    # ── Region-specific checks ────────────────────────────────────────────────

    def _check_region_specific(self, md: str, ctx: dict) -> None:
        """Apply region-specific requirements from KB."""

        if self.region in ("NMPA", "ALL"):
            self._check_nmpa(md, ctx)

        if self.region in ("EMA", "ALL"):
            self._check_ema(md, ctx)

        if self.region in ("FDA", "ALL"):
            self._check_fda(md, ctx)

        if self.region in ("PMDA", "ALL"):
            self._check_pmda(md, ctx)

    def _check_nmpa(self, md: str, ctx: dict) -> None:
        """NMPA/CDE-specific checks."""
        # GLP declaration
        if not re.search(r"GLP|Good Laboratory Practice|NMPA.*recognition", md, re.IGNORECASE):
            self._add(MAJOR, "2.6.1", "NMPA_ANNOUNCEMENT_35", "NMPA",
                      "NMPA-GLP-001",
                      "Missing GLP facility origin declaration required by NMPA Announcement No. 35 (2019).",
                      "Add glp_facility and glp_recognition to INDAssemblyRequest; include in §2.6.1 overview.",
                      evidence="NMPA Announcement No. 35 (2019): GLP declaration required for all CTA nonclinical data")

        # Ethnic bridging (required for CYP2C19/2D6-metabolized drugs)
        if not re.search(r"ethnic|East Asian|CYP2C19|ICH E5|bridging study", md, re.IGNORECASE):
            # Only flag as MAJOR if compound is known to be CYP2C19/2D6 substrate
            self._add(MINOR, "2.6.2", "CDE_NONCLIN_2021", "NMPA",
                      "NMPA-ETHNIC-001",
                      "§2.6.2 does not address ethnic bridging (ICH E5) for East Asian populations.",
                      "Add ethnic_bridging_note to INDAssemblyRequest; include ICH E5 statement for NMPA CTA.",
                      evidence="CDE Nonclinical CTA Guideline (Aug 2021): ethnic bridging required if PK may differ")

    def _check_ema(self, md: str, ctx: dict) -> None:
        """EMA-specific structural checks.

        Content-adequacy checks (DILI mechanistic, PBPK interpretation quality)
        are handled by the LLM semantic tier — see _check_semantic().
        """
        # EMA PBPK: 67% criterion pass/fail must be stated (structural — exact "67" required)
        pbpk_section = self._extract_section(md, "2.6.1.2", "2.6.1.3")
        if pbpk_section and "67" not in pbpk_section:
            self._add(MINOR, "2.6.1.2", "EMA_PBPK_2018", "EMA",
                      "EMA-PBPK-67-001",
                      "§2.6.1.2 does not explicitly state the 67% threshold from EMA/CHMP/EWP/37498/2011 Rev1.",
                      "Add '≥67% of predictions within 2-fold of observed Cmax AND AUC (EMA criterion)'.")

    def _check_fda(self, md: str, ctx: dict) -> None:
        """FDA-specific checks."""
        # Model Assumptions & Limitations table
        if not re.search(r"assumption|limitation", md, re.IGNORECASE):
            self._add(MAJOR, "2.6.2", "FDA_PBPK_2018", "FDA",
                      "FDA-PBPK-TABLE2-001",
                      "§2.6.2 missing Model Assumptions & Limitations content required by FDA PBPK Guidance (Sep 2018, Table 2).",
                      "Add structured table: [Model type | Assumption | Justification/Impact].")

        # FDA: ICH S9 / M3(R2) exemption note for oncology
        # (INFO only — not required for all submissions)
        if re.search(r"oncol|cancer|tumor|neoplasm", md, re.IGNORECASE):
            if "S9" not in md and "M3(R2)" not in md:
                self._add(INFO, "2.6", "ICH_M3_R2", "FDA",
                          "FDA-S9-INFO-001",
                          "Indication appears oncology-related. Consider whether ICH S9 exemptions apply to the nonclinical package.",
                          "Review ICH S9 (2010) for genotoxicity/tox study exemptions in oncology INDs.")

    def _check_pmda(self, md: str, ctx: dict) -> None:
        """PMDA-specific checks."""
        if not re.search(r"ethnic|Japanese|ICH E5|E7|Asian", md, re.IGNORECASE):
            self._add(MINOR, "2.6.2", "ICH_E5", "PMDA",
                      "PMDA-ETHNIC-001",
                      "§2.6.2 does not address Japanese population ethnic sensitivity (ICH E5/E7, PMDA requirement).",
                      "Add ICH E5 bridging statement addressing expected PK differences in Japanese population.")

    # ── Threshold citations ───────────────────────────────────────────────────

    def _check_thresholds(self, md: str) -> None:
        """All cited threshold values must match KB values."""
        # hERG threshold: document should cite the KB value
        kb_herg = get_threshold("hERG", "value_uM", 10.0)
        doc_herg_match = re.search(r'hERG.*?IC50.*?(\d+(?:\.\d+)?)\s*µM', md)
        if doc_herg_match:
            doc_val = float(doc_herg_match.group(1))
            if abs(doc_val - kb_herg) > 0.01:
                self._add(CRITICAL, "2.6.3.7", "ICH_S7B", "ALL",
                          "THRESH-HERG-MISMATCH",
                          f"Document cites hERG threshold {doc_val} µM but regulatory_knowledge.yaml specifies {kb_herg} µM.",
                          f"Update threshold to {kb_herg} µM per ICH S7B and regulatory_knowledge.yaml.",
                          evidence=doc_herg_match.group(0))

        # PBPK 67% criterion value
        pbpk_frac = get_threshold("PBPK_within_2fold", "value", 0.67)
        doc_pct_match = re.search(r'≥?(\d+)%.*within.{0,10}2.fold', md, re.IGNORECASE)
        if doc_pct_match:
            doc_pct = int(doc_pct_match.group(1))
            expected_pct = int(pbpk_frac * 100)
            if doc_pct != expected_pct:
                self._add(MAJOR, "2.6.1.2", "EMA_PBPK_2018", "EMA",
                          "THRESH-PBPK-PCT-MISMATCH",
                          f"Document cites {doc_pct}% within-2-fold criterion but KB specifies {expected_pct}%.",
                          f"Update to ≥{expected_pct}% per EMA/CHMP/EWP/37498/2011 Rev1.",
                          evidence=doc_pct_match.group(0))

    # ── Disclaimer checks — structural only (quality handled by semantic tier) ──

    def _check_disclaimer(self, md: str) -> None:
        """Structural disclaimer presence check.

        Only verifies that the title page contains SOME in silico disclaimer text.
        Content quality (whether it is genuinely cautionary) is assessed by the
        LLM semantic tier (PK-DISC-QUALITY-001 check).
        """
        if not re.search(r"in silico|computational prediction", md[:2000], re.IGNORECASE):
            self._add(MAJOR, "title", "ICH_M4S_R2", "ALL",
                      "DISC-INSILICO-001",
                      "Title page missing 'in silico predictions' disclaimer text.",
                      "Add disclaimer to title page per ICH M4 good practice.")

    # ── Helpers ───────────────────────────────────────────────────────────────

    def _extract_section(self, md: str, start_sec: str, end_sec: Optional[str]) -> str:
        """Extract text of a section between two ## heading markers.

        Searches for '## {start_sec}' as a heading (not just a substring match)
        to avoid false matches against title page references.
        """
        heading_pat = re.compile(r'^##\s+' + re.escape(start_sec), re.MULTILINE)
        m = heading_pat.search(md)
        if not m:
            return ""
        start = m.start()

        if end_sec:
            end_pat = re.compile(r'^##\s+' + re.escape(end_sec), re.MULTILINE)
            em = end_pat.search(md, start + 1)
            if em:
                return md[start:em.start()]

        # Fall back: next ## heading of any kind
        next_h = re.search(r'^##\s', md[start + 1:], re.MULTILINE)
        offset = next_h.start() + start + 1 if next_h else len(md)
        return md[start:offset]

    # ── OSP benchmark comparison (from regulatory_skills_db) ─────────────────

    def _check_osp_benchmarks(self, md: str, ctx: dict) -> None:
        """
        Compare BioMate PBPK metrics against approved OSP Qualification Report ranges.

        Requires regulatory_skills_db to have been ingested at least once.
        No-ops silently if DB not yet populated.
        """
        vr = ctx.get("validation_report") or {}
        within_2fold = vr.get("within_2fold_fraction")
        afe = vr.get("afe")
        aafe = vr.get("aafe")

        if within_2fold is None:
            return  # no PBPK metrics available

        try:
            from .regulatory_skills_db import RegulatorySkillsDB
            db = RegulatorySkillsDB()
            result = db.compare_metrics(
                afe=afe or 1.0,
                aafe=aafe or 1.0,
                within_2fold=within_2fold,
                region=self.region,
            )
            n_reports = result.get("osp_benchmark", {}).get("n_reports", 0)
            if n_reports == 0:
                return  # DB not yet ingested — skip silently

            verdict = result.get("verdict")
            note = result.get("note", "")
            margin = result.get("ema_criterion", {}).get("margin", 0)
            osp_range = result.get("osp_benchmark", {}).get("within_2fold_range_pct", (None, None))
            in_range = result.get("osp_benchmark", {}).get("biomate_within_osp_range", False)

            if verdict == "FAIL":
                self._add(MAJOR, "2.6.1.2", "EMA_PBPK_2018", "EMA",
                          "OSP-BENCH-001",
                          f"BioMate within-2-fold ({within_2fold:.1%}) is below EMA 67% criterion (margin={margin:+.1%}).",
                          "Improve PBPK model or add more validated compounds to meet EMA criterion.",
                          evidence=note)
            elif not in_range and osp_range[0] is not None:
                self._add(INFO, "2.6.1.2", "EMA_PBPK_2018", "EMA",
                          "OSP-BENCH-002",
                          f"BioMate within-2-fold ({within_2fold:.1%}) passes EMA criterion but is outside OSP-approved range "
                          f"({osp_range[0]:.1f}–{osp_range[1]:.1f}%).",
                          "Consider additional PBPK validation with OSP reference compounds (Midazolam, Rifampicin).",
                          evidence=note)
            else:
                self._add(INFO, "2.6.1.2", "EMA_PBPK_2018", "EMA",
                          "OSP-BENCH-PASS",
                          f"BioMate PBPK within-2-fold ({within_2fold:.1%}) meets EMA criterion and is within OSP-approved range.",
                          "",
                          evidence=note)
        except Exception as exc:
            log.debug("[regulatory_auditor] OSP benchmark check failed: %s", exc)

    def _add(self, severity: str, section: str, guideline: str, region: str,
             code: str, description: str, suggestion: str, evidence: str = "") -> None:
        self._findings.append(AuditFinding(
            severity=severity, section=section, guideline_id=guideline,
            region=region, code=code, description=description,
            suggestion=suggestion, evidence=evidence[:300],
        ))
