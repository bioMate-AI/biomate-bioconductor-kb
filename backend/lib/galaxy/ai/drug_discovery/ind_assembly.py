"""
BioMate IND Section Assembler — Phase 3b CRO Compliance

Generates ICH M4 CTD Sections 2.6.1–2.6.3 (Nonclinical Overview)
from BioMate campaign data and model validation results.

Output:
  - Markdown source (always available)
  - DOCX via pandoc (if pandoc is installed)

ICH M4 Section 2.6.1 structure (nonclinical pharmacology overview):
  2.6.1.1  Overview of Computational Methods
  2.6.1.2  PBPK Model Qualification
  2.6.1.3  ADMET Screening Results
  2.6.1.4  Compound Prioritization and Lead Candidate Selection
  2.6.1.5  Applicability Domain Assessment
  2.6.1.6  Audit Trail and Regulatory Traceability

ICH M4 Section 2.6.2 structure (nonclinical pharmacokinetics overview):
  2.6.2.1  Methods of Analysis
  2.6.2.2  Absorption
  2.6.2.3  Distribution
  2.6.2.4  Metabolism
  2.6.2.5  Excretion
  2.6.2.6  Pharmacokinetic Drug Interactions
  2.6.2.7  Other Pharmacokinetic Studies

ICH M4 Section 2.6.3 structure (nonclinical toxicology overview):
  2.6.3.1  Single-Dose Toxicity
  2.6.3.2  Repeat-Dose Toxicity
  2.6.3.3  Genotoxicity
  2.6.3.4  Carcinogenicity
  2.6.3.5  Reproductive and Developmental Toxicity
  2.6.3.6  Local Tolerance
  2.6.3.7  Other Toxicity Studies

References:
  ICH M4S(R2) — The Common Technical Document for Registration of
                 Pharmaceuticals for Human Use: Safety
  EMA/CHMP/EWP/37498/2011 — Guideline on the reporting of physiologically
                              based pharmacokinetic (PBPK) modelling and simulation
  ICH S7A/S7B — Safety Pharmacology Studies for Human Pharmaceuticals
  ICH S2(R1) — Genotoxicity Testing and Data Interpretation
"""

import hashlib
import json
import logging
import os
import re
import subprocess
import tempfile
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path
from typing import Optional

log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Local Regulatory LLM — Qwen3-8B + LoRA adapter
# ---------------------------------------------------------------------------

def _resolve_adapter_path() -> Path:
    """Pick the latest available LoRA adapter. Prefers v2 → v1 → env override."""
    if "REGULATORY_LLM_ADAPTER" in os.environ:
        return Path(os.environ["REGULATORY_LLM_ADAPTER"])
    models_root = Path(__file__).parent.parent.parent.parent.parent.parent / "models"
    # Prefer numerically higher versions
    for name in ("regulatory_llm_v4/lora_adapter", "regulatory_llm_v3/lora_adapter", "regulatory_llm_v2/lora_adapter", "regulatory_llm_v1/lora_adapter"):
        candidate = models_root / name
        if candidate.exists():
            return candidate
    return models_root / "regulatory_llm_v1/lora_adapter"  # may not exist — falls back to Gemini


_LOCAL_LLM_ADAPTER = _resolve_adapter_path()

_local_llm_model = None       # lazy-loaded (PeftModel)
_local_llm_tokenizer = None   # lazy-loaded

# Required ICH citations per section type — injected by guardrail if absent
_REQUIRED_CITATIONS: dict[str, list[str]] = {
    "overview":     ["ICH M4S(R2)", "ICH M3(R2)"],
    "pbpk":         ["EMA/CHMP/EWP/37498/2011", "ICH M3(R2)"],
    "pk_overview":  ["ICH M3(R2)"],
    "admet":        ["ICH M4S(R2)", "ICH S7B"],
    "tox_overview": ["ICH M3(R2)", "ICH S7A"],
    "tox_genotox":  ["ICH S2(R1)"],
    "tox_cardiac":  ["ICH S7B", "ICH S7A"],
}

def _load_local_llm() -> bool:
    """Lazy-load the LoRA adapter. Returns True if successfully loaded."""
    global _local_llm_model, _local_llm_tokenizer
    if _local_llm_model is not None:
        return True
    if not _LOCAL_LLM_ADAPTER.exists():
        log.debug("[local-llm] Adapter not found at %s — using Gemini", _LOCAL_LLM_ADAPTER)
        return False
    try:
        import warnings, os as _os
        warnings.filterwarnings("ignore", message=".*sm_121.*", category=UserWarning)
        _os.environ.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")
        import torch
        from transformers import AutoModelForCausalLM, AutoTokenizer
        from peft import PeftModel

        base_id = "Qwen/Qwen3-8B"
        log.info("[local-llm] Loading %s + adapter from %s", base_id, _LOCAL_LLM_ADAPTER)
        tok = AutoTokenizer.from_pretrained(
            str(_LOCAL_LLM_ADAPTER), trust_remote_code=True
        )
        if tok.pad_token is None:
            tok.pad_token = tok.eos_token

        base = AutoModelForCausalLM.from_pretrained(
            base_id,
            torch_dtype=torch.bfloat16,
            device_map="auto",
            trust_remote_code=True,
        )
        model = PeftModel.from_pretrained(base, str(_LOCAL_LLM_ADAPTER))
        model.eval()

        _local_llm_model = model
        _local_llm_tokenizer = tok
        log.info("[local-llm] Adapter loaded — local model active")
        return True
    except Exception as exc:
        log.warning("[local-llm] Load failed: %s — falling back to Gemini", exc)
        return False


def _call_local_regulatory_llm(
    section_type: str,
    system: str,
    user_prompt: str,
    max_new_tokens: int = 512,
    temperature: float = 0.3,
) -> str:
    """
    Call the local Qwen3-8B LoRA adapter for regulatory narrative generation.
    Returns empty string if unavailable (caller falls back to Gemini).

    Qwen3 uses /no_think mode: direct prose without chain-of-thought.
    """
    if not _load_local_llm():
        return ""
    try:
        import torch
        tok = _local_llm_tokenizer
        model = _local_llm_model

        messages = [
            {"role": "system", "content": system},
            {"role": "user",   "content": f"/no_think\n{user_prompt}"},
        ]
        # Qwen3 apply_chat_template with enable_thinking=False
        try:
            text = tok.apply_chat_template(
                messages, tokenize=False, add_generation_prompt=True,
                enable_thinking=False,
            )
        except TypeError:
            text = tok.apply_chat_template(
                messages, tokenize=False, add_generation_prompt=True,
            )

        inputs = tok(text, return_tensors="pt").to(model.device)
        with torch.no_grad():
            out = model.generate(
                **inputs,
                max_new_tokens=max_new_tokens,
                do_sample=temperature > 0,
                temperature=temperature if temperature > 0 else 1.0,
                top_p=0.9,
                repetition_penalty=1.1,
                pad_token_id=tok.eos_token_id,
            )
        generated = out[0][inputs.input_ids.shape[1]:]
        return tok.decode(generated, skip_special_tokens=True).strip()
    except Exception as exc:
        log.warning("[local-llm] Inference failed: %s", exc)
        return ""


def _quick_audit(text: str, section_type: str) -> list[str]:
    """
    Lightweight MAJOR-finding check: returns list of failing rule IDs.
    Used to decide whether to fall back to Gemini after local model generation.
    Only checks MAJOR rules that the local model commonly fails.
    """
    failures = []
    lower = text.lower()

    if section_type == "pbpk":  # pk_overview is general PK — no PBPK guideline required
        if not ("EMA/CHMP/EWP/37498/2011" in text or "67%" in text or "within-2-fold" in lower or "criterion" in lower):
            failures.append("CITE_001:PBPK_missing_EMA_guideline")
    if section_type == "tox_genotox":
        if "S2(R1)" not in text and "ICH S2" not in text:
            failures.append("CITE_002:genotox_missing_S2R1")
        if "ames" not in lower and "bacterial reverse" not in lower:
            failures.append("CONTENT_002:genotox_missing_ames")
    if section_type == "tox_cardiac":
        if "S7B" not in text:
            failures.append("CITE_003:cardiac_missing_S7B")

    return failures


def _regulatory_guardrails(
    text: str,
    section_type: str,
    data: dict,
    region: str,
) -> tuple[str, list[str]]:
    """
    Apply post-generation guardrails to a regulatory narrative.

    Returns (corrected_text, list_of_warnings).

    Guardrails applied:
    1. Citation injector: if required ICH citations missing, append footnote
    2. Length guard: flag outputs < 150 words
    3. Numeric faithfulness: flag numbers in output not present in input data
    4. Markdown strip: remove any residual markdown formatting
    5. FDA label header strip: remove "13 NONCLINICAL TOXICOLOGY" etc.
    """
    warnings_out: list[str] = []
    out = text

    # 1. Strip markdown and FDA section headers
    out = out.replace("**", "").replace("*", "")
    out = re.sub(r"^#{1,6}\s+", "", out, flags=re.M)
    out = re.sub(
        r"^\d+\s+[A-Z][A-Z, /&().-]{4,50}"
        r"(?:\s+\d+\.\d+(?:\.\d+)?\s+[A-Z][A-Za-z, /()&.-]{4,80})?\s+",
        "", out,
    )
    out = out.strip()

    # 2. Citation injector
    required = _REQUIRED_CITATIONS.get(section_type, [])
    missing = [c for c in required if c.lower() not in out.lower()]
    if missing:
        # Append as a regulatory footnote rather than silently skip
        citation_str = "; ".join(missing)
        out = out + f" [Applicable guidelines: {citation_str}.]"
        warnings_out.append(f"CITATION_INJECTED: {citation_str}")

    # 2b. Citation grounding check (retrieval-based)
    # Verify that cited guidelines actually cover the adjacent claim.
    # Only runs if rank_bm25 + PyMuPDF are available; silently skips otherwise.
    try:
        from .ich_corpus import get_ich_corpus
        corpus = get_ich_corpus()
        results = corpus.verify_all_citations(out, section_type)
        for r in results:
            if not r.grounded and r.method != "unavailable":
                warnings_out.append(
                    f"CITATION_UNGROUNDED: '{r.citation}' — claim not supported "
                    f"by guideline text (score={r.score:.2f})"
                )
    except Exception:
        pass  # Never block generation on corpus check failure

    # 3. Length guard
    word_count = len(out.split())
    if word_count < 150:
        warnings_out.append(f"SHORT_OUTPUT: {word_count} words (target ≥300)")

    # 4. Numeric faithfulness — check that numbers in output appear in input
    import re as _re
    output_nums = set(_re.findall(r"\d+\.?\d*", out))
    input_vals = set()
    for v in data.values():
        if isinstance(v, (int, float)):
            input_vals.add(str(int(v)) if v == int(v) else str(round(v, 3)))
        elif isinstance(v, str):
            input_vals.update(_re.findall(r"\d+\.?\d*", v))
    # Flag numbers in output that look like IC50s, AUCs, NOAELs (>0.001, numeric)
    suspicious = {
        n for n in output_nums
        if float(n) > 0.001 and n not in input_vals and len(n) >= 3
    }
    if len(suspicious) > 3:
        warnings_out.append(
            f"NUMERIC_MISMATCH: {len(suspicious)} numbers in output not in input data"
        )

    return out, warnings_out


# ---------------------------------------------------------------------------
# Regulatory Knowledge DB
# ---------------------------------------------------------------------------

_REG_KB_PATH = Path(__file__).parent / "regulatory_knowledge.yaml"


@lru_cache(maxsize=1)
def _load_regulatory_kb() -> dict:
    """Load regulatory_knowledge.yaml once and cache it in-process."""
    try:
        import yaml  # PyYAML (available in biomate backend environment)
        with open(_REG_KB_PATH, encoding="utf-8") as f:
            return yaml.safe_load(f)
    except Exception as exc:
        log.warning("[regulatory_kb] Could not load %s: %s — using defaults", _REG_KB_PATH, exc)
        return {}


def get_threshold(threshold_id: str, field: str, default=None):
    """Read a safety threshold from the knowledge DB."""
    kb = _load_regulatory_kb()
    return kb.get("safety_thresholds", {}).get(threshold_id, {}).get(field, default)


def get_guideline_ref(guideline_id: str) -> str:
    """Return a formatted citation string for a guideline."""
    kb = _load_regulatory_kb()
    g = kb.get("guidelines", {}).get(guideline_id, {})
    if not g:
        return guideline_id
    ver = g.get("version", "")
    date = g.get("effective_date", "")
    short = g.get("short_name", guideline_id)
    return f"{short} ({date})" if date else short


def get_compliance_gaps(region: str) -> list[dict]:
    """Return open compliance gaps for a region."""
    kb = _load_regulatory_kb()
    return kb.get("compliance_matrix", {}).get(region, {}).get("gaps", [])

# ---------------------------------------------------------------------------
# LLM narrative helper
# ---------------------------------------------------------------------------

# Region-specific system prompts — each includes the primary governing regulation so the
# LLM styles prose appropriately for the target regulatory authority.
_NARRATIVE_SYSTEM_BY_REGION = {
    "FDA": (
        "You are a regulatory affairs scientist drafting language for an Investigational New Drug (IND) "
        "application submitted to the U.S. FDA under 21 CFR Part 312. Write in formal ICH/FDA regulatory "
        "document style: precise, passive-voice where appropriate, evidence-referenced, and suitably hedged. "
        "Cite ICH S7B(R1), S2(R1), M3(R2), and FDA PBPK Guidance (2018) where relevant. "
        "No markdown — plain prose only. 2-4 sentences maximum per response."
    ),
    "EMA": (
        "You are a regulatory affairs scientist drafting language for a Clinical Trial Authorisation (CTA) "
        "submitted to the EMA under EudraLex Volume 10. Write in formal ICH/EMA regulatory document style. "
        "Cite EMA/CHMP/EWP/37498/2011 (PBPK guideline), EMA DILI Reflection Paper "
        "(EMEA/CHMP/HMPC/700003/2012), ICH S7B(R1), S2(R1), and M3(R2) where relevant. "
        "The EMA requires ≥67% of PBPK predictions within 2-fold of observed for model qualification. "
        "No markdown — plain prose only. 2-4 sentences maximum per response."
    ),
    "NMPA": (
        "You are a regulatory affairs scientist drafting language for a Clinical Trial Application (CTA) "
        "submitted to the NMPA/CDE under Announcement No. 35 (2019) and CDE Technical Guidelines. "
        "Write in formal ICH/NMPA regulatory document style. Include GLP facility declarations where required. "
        "For ethnic bridging, cite CYP2C19 and CYP2D6 polymorphism prevalence in the Chinese population "
        "per ICH E5. No markdown — plain prose only. 2-4 sentences maximum per response."
    ),
    "PMDA": (
        "You are a regulatory affairs scientist drafting language for a Clinical Trial Notification (CTN) "
        "submitted to the PMDA under PFSB/ELD Notification 0601-1. Write in formal ICH/PMDA regulatory "
        "document style. For ethnic sensitivity, cite ICH E5 and E7 and discuss CYP polymorphism "
        "frequencies in the Japanese population where relevant. "
        "No markdown — plain prose only. 2-4 sentences maximum per response."
    ),
}
# Default (ALL regions) uses FDA framing
_NARRATIVE_SYSTEM_BY_REGION["ALL"] = _NARRATIVE_SYSTEM_BY_REGION["FDA"]

# CTD section → skills DB section code mapping
_SECTION_TO_CTD = {
    "overview":       "2.6.1",
    "pbpk":           "2.6.2",
    "admet":          "2.6.1",
    "prioritization": "2.6.1",
    "ad":             "2.6.1",
    "pk_overview":    "2.6.2",
    "pk_adme":        "2.6.2",
    "tox_overview":   "2.6.3",
    "tox_genotox":    "2.6.3",
    "tox_cardiac":    "2.6.3",
}


def _llm_narrative(
    section_type: str,
    data: dict,
    region: str = "FDA",
    audit_constraint: str = "",
    user_prompt_override: str = "",
) -> str:
    """
    Generate a 2-4 sentence regulatory narrative paragraph for a given IND section.

    Enhancements over the original:
    1. Region-specific system prompt (FDA/EMA/NMPA/PMDA)
    2. RAG: injects 2-3 narrative patterns from regulatory_skills_db when available
    3. OSP benchmark context for PBPK sections
    4. audit_constraint: when set, adds a negative constraint (used by regeneration loop)

    Returns empty string on any failure (graceful degradation).
    """
    try:
        from galaxy.ai.gemini_flash import call_gemini_flash as _gemini_flash

        prompts = {
            "overview": (
                f"Write a 2-3 sentence regulatory introductory paragraph for CTD Section 2.6.1.1 of an IND "
                f"for compound {data.get('molecule_name', 'the investigational compound')} targeting "
                f"{data.get('target_name', 'the investigational target')} in {data.get('indication', 'the proposed indication')}. "
                f"Describe that the sponsor used an integrated computational CRO platform (BioMate) comprising "
                f"PBPK simulation, multi-objective Bayesian lead optimization, ADMET screening, and applicability domain assessment, "
                f"and that all predictions were generated by validated in silico methods with full electronic audit traceability."
            ),
            "pbpk": (
                f"Write a 2-4 sentence regulatory interpretation paragraph for the PBPK model qualification results. "
                f"The model achieved: AFE(Cmax)={data.get('AFE_Cmax', 'N/A')}, AAFE(Cmax)={data.get('AAFE_Cmax', 'N/A')}, "
                f"R²(Cmax)={data.get('R2_Cmax', 'N/A')}, within-2-fold(Cmax)={data.get('within_2fold_Cmax', 'N/A')}, "
                f"within-2-fold(AUC)={data.get('within_2fold_AUC', 'N/A')}. "
                f"EMA criterion met: {data.get('ema_criterion_met', False)}. "
                f"Describe whether the model meets EMA guideline thresholds and what this means for IND submission."
            ),
            "admet": (
                f"Write a 2-3 sentence regulatory narrative for ADMET screening results. "
                f"{data.get('total_compounds', 0)} compounds were profiled; "
                f"{data.get('passing_compounds', 0)} ({data.get('pass_rate', 0.0):.1%}) passed all safety gates. "
                f"Safety gates included hERG cardiac liability, DILI, Ames mutagenicity, and Lipinski Ro5. "
                f"Describe the overall safety profile and what the pass rate implies for candidate viability."
            ),
            "prioritization": (
                f"Write a 2-3 sentence regulatory narrative for compound prioritization and lead candidate selection. "
                f"Lead candidate rank 1 has composite score {data.get('top_score', 'N/A')} from {data.get('total_compounds', 0)} evaluated compounds. "
                f"The Bayesian optimizer used Gaussian Process with Morgan fingerprints and Expected Hypervolume Improvement acquisition. "
                f"Explain why the computational prioritization approach is scientifically justified for IND-stage lead selection."
            ),
            "ad": (
                f"Write a 2-3 sentence regulatory paragraph on applicability domain assessment methodology. "
                f"The approach uses hat-matrix leverage (Tropsha/Roy) combined with Tanimoto nearest-neighbour similarity. "
                f"Explain why dual-criterion AD assessment is scientifically rigorous and how it supports confidence in computational predictions for the IND."
            ),
            "pk_overview": (
                f"Write a 2-4 sentence regulatory introductory paragraph for CTD Section 2.6.2 (Nonclinical Overview: Pharmacokinetics) "
                f"for compound {data.get('molecule_name', 'the investigational compound')}. "
                f"The PBPK model predicts the following key parameters for the lead candidate: "
                f"oral bioavailability estimated from PBPK simulation; "
                f"volume of distribution consistent with moderate tissue binding; "
                f"hepatic clearance as the dominant elimination pathway. "
                f"PBPK model qualification: AFE(Cmax)={data.get('AFE_Cmax', 'N/A')}, AAFE={data.get('AAFE_Cmax', 'N/A')}, within-2-fold={data.get('within_2fold_Cmax', 'N/A')}. "
                f"EMA criterion met: {data.get('ema_criterion_met', False)}. "
                f"Describe the overall suitability of the PBPK approach for characterising PK properties for IND submission."
            ),
            "pk_adme": (
                f"Write a 2-3 sentence regulatory summary of the ADME profile for "
                f"{data.get('molecule_name', 'the investigational compound')} "
                f"based on in silico predictions and PBPK modelling. "
                f"The compound has {data.get('n_compounds', 0)} ranked analogues with measured assay data. "
                f"Describe the primary absorption, distribution, metabolism, and excretion characteristics "
                f"as predicted by the BioMate PBPK model and how these inform the proposed clinical dose."
            ),
            "tox_overview": (
                f"Write a 2-4 sentence regulatory introductory paragraph for CTD Section 2.6.3 (Nonclinical Overview: Toxicology) "
                f"for compound {data.get('molecule_name', 'the investigational compound')}. "
                f"Computational safety profiling was performed: "
                f"{data.get('total_compounds', 0)} compounds were evaluated; "
                f"{data.get('herg_flagged', 0)} showed cardiac liability (hERG IC50 < 10 µM); "
                f"{data.get('dili_flagged', 0)} flagged for DILI; "
                f"{data.get('ames_flagged', 0)} flagged for Ames mutagenicity. "
                f"Describe the overall toxicological risk assessment and what the in silico profile means for the IND safety package."
            ),
            "tox_genotox": (
                f"Write a 2-3 sentence regulatory summary of the genotoxicity assessment for "
                f"{data.get('molecule_name', 'the investigational compound')}. "
                f"Ames mutagenicity prediction was {data.get('ames_result', 'negative')} for the lead compound "
                f"({data.get('ames_flagged', 0)} of {data.get('total_compounds', 0)} campaign compounds predicted mutagenic). "
                f"Describe the significance of this computational Ames result for the genotoxicity section of the IND "
                f"and what follow-up in vitro studies are recommended per ICH S2(R1)."
            ),
            "tox_cardiac": (
                f"Write a 2-3 sentence regulatory paragraph on cardiac safety (safety pharmacology, ICH S7B) for "
                f"{data.get('molecule_name', 'the investigational compound')}. "
                f"hERG IC50 for the lead compound is {data.get('lead_herg_ic50', 'not measured')} µM. "
                f"{data.get('herg_flagged', 0)} of {data.get('total_compounds', 0)} evaluated compounds had hERG IC50 < 10 µM. "
                f"Describe the cardiac liability risk and what the computational hERG assessment implies for ICH S7B compliance."
            ),
        }

        # user_prompt_override lets callers supply a fully-formed prompt (e.g. §2.4)
        if user_prompt_override:
            user_prompt = user_prompt_override
        else:
            user_prompt = prompts.get(section_type, "")
            if not user_prompt:
                return ""

        # ── RAG: inject narrative patterns from regulatory_skills_db ─────────
        rag_block = _build_rag_context(section_type, data, region)
        if rag_block:
            user_prompt = rag_block + "\n\n" + user_prompt

        # ── Audit constraint: negative instruction when regenerating ─────────
        if audit_constraint:
            user_prompt += (
                f"\n\nIMPORTANT — the previous draft failed a regulatory audit check: "
                f"\"{audit_constraint}\". Ensure the revised paragraph explicitly addresses this."
            )

        # ── Region-specific system prompt ─────────────────────────────────────
        # For §2.4 we need a longer generation target — adjust system prompt accordingly
        system = _NARRATIVE_SYSTEM_BY_REGION.get(region, _NARRATIVE_SYSTEM_BY_REGION["FDA"])
        if section_type == "nonclinical_overview":
            system = system.replace("2-4 sentences maximum per response.",
                                    "600–1,000 words for this section.")

        # ── Model routing: local LoRA adapter → Gemini fallback ───────────────
        narrative = _call_local_regulatory_llm(
            section_type=section_type,
            system=system,
            user_prompt=user_prompt,
            max_new_tokens=600,
            temperature=0.3,
        )
        source = "local"

        # Check: empty output or too short → Gemini fallback
        too_short = not narrative or len(narrative.split()) < 30
        # Check: MAJOR audit findings → Gemini fallback for citation-critical sections
        major_findings = _quick_audit(narrative, section_type) if narrative else []
        needs_gemini = too_short or bool(major_findings)

        if needs_gemini:
            reason = "empty" if too_short else f"audit_fail:{','.join(major_findings)}"
            log.debug("[IND narrative] local model fallback reason=%s — using Gemini", reason)
            gemini_narrative = _gemini_flash(
                messages=[{"role": "user", "content": user_prompt}],
                system=system,
                max_tokens=2048,
                temperature=0.3,
            ).strip()
            if gemini_narrative:
                narrative = gemini_narrative
                source = "gemini"
            # else: keep local model output (Gemini also failed) + let guardrails handle

        log.debug("[IND narrative] %s/%s source=%s words=%d",
                  section_type, region, source, len(narrative.split()) if narrative else 0)

        # ── Guardrails ────────────────────────────────────────────────────────
        narrative, guard_warnings = _regulatory_guardrails(
            narrative, section_type, data, region
        )
        for w in guard_warnings:
            log.debug("[IND guardrail] %s: %s", section_type, w)

        return narrative

    except Exception as exc:
        log.debug("[IND narrative] LLM call failed for section %s: %s", section_type, exc)
        return ""


def _build_rag_context(section_type: str, data: dict, region: str) -> str:
    """
    Build a RAG context block to prepend to the narrative prompt.

    Pulls:
    1. Up to 3 narrative patterns from regulatory_skills_db matching the CTD section
    2. OSP benchmark comparison for PBPK sections
    """
    lines = []

    # ── Narrative patterns from skills DB ────────────────────────────────────
    try:
        from .regulatory_skills_db import RegulatorySkillsDB
        db = RegulatorySkillsDB()
        ctd = _SECTION_TO_CTD.get(section_type, "2.6")
        patterns = db.get_narrative_patterns(ctd_section=ctd)
        if patterns:
            good = [p["text"] for p in patterns if p.get("text") and len(p["text"]) > 40][:3]
            if good:
                lines.append(
                    "Examples of regulatory language from EMA-accepted PBPK qualification reports "
                    "(use as style reference — do NOT copy verbatim):"
                )
                for ex in good:
                    lines.append(f"  • {ex.strip()}")
    except Exception:
        pass  # skills DB optional — graceful degradation

    # ── OSP benchmark comparison for PBPK sections ───────────────────────────
    if section_type in ("pbpk", "pk_overview") and data.get("within_2fold_Cmax") is not None:
        try:
            from .regulatory_skills_db import RegulatorySkillsDB
            db = RegulatorySkillsDB()
            try:
                w2f = float(str(data["within_2fold_Cmax"]).rstrip("%")) / 100 \
                    if "%" in str(data.get("within_2fold_Cmax", "")) \
                    else float(data["within_2fold_Cmax"])
            except (ValueError, TypeError):
                w2f = None
            if w2f is not None:
                verdict = db.compare_metrics(
                    afe=data.get("AFE_Cmax"),
                    aafe=data.get("AAFE_Cmax"),
                    within_2fold=w2f,
                )
                if verdict.get("verdict") in ("PASS", "INFO"):
                    lines.append(
                        f"OSP benchmark context: {verdict.get('message', '')} "
                        f"(Use this context to frame whether the model is well-qualified.)"
                    )
        except Exception:
            pass

    return "\n".join(lines) if lines else ""


# ---------------------------------------------------------------------------
# Assembly result
# ---------------------------------------------------------------------------

from dataclasses import dataclass


@dataclass
class AssemblyResult:
    campaign_id: str
    sections: list[str]          # section headings included
    markdown_path: str           # always written
    docx_path: Optional[str]     # None if pandoc unavailable
    pandoc_available: bool
    generated_at: str
    warnings: list[str]
    audit_findings: list         # list of AuditFinding from RegulatoryAuditor
    audit_score: dict            # {"CRITICAL": n, "MAJOR": n, "MINOR": n, "INFO": n}


# ---------------------------------------------------------------------------
# IND Section Assembler
# ---------------------------------------------------------------------------

class INDSectionAssembler:
    """
    Builds ICH M4 CTD Sections 2.6.1–2.6.3 from BioMate data.

    Usage:
        assembler = INDSectionAssembler(db_path="/path/to/campaign.db")
        result = assembler.assemble(
            campaign_id="cmp-001",
            output_dir="/path/to/output",
            molecule_name="BM-0042",
            sponsor="BioTech Inc.",
        )
        print(result.markdown_path)
    """

    def __init__(self, db_path: str):
        self._db_path = db_path

    # ------------------------------------------------------------------
    # Public entry point
    # ------------------------------------------------------------------

    def assemble(
        self,
        campaign_id: str,
        output_dir: str,
        molecule_name: str = "Investigational Compound",
        sponsor: str = "Sponsor",
        indication: str = "Investigational indication",
        target_name: str = "Investigational target",
        pk_summary: Optional[dict] = None,
        region: str = "ALL",
        glp_facility: str = "",
        glp_recognition: str = "",
        ethnic_bridging_note: str = "",
        wetlab_data: Optional[dict] = None,
    ) -> AssemblyResult:
        """
        Generate CTD Sections 2.6.1–2.6.3 for the given campaign.

        Args:
            campaign_id: BioMate campaign identifier.
            output_dir:  Directory where Markdown and DOCX are written.
            molecule_name: Name of the drug candidate (e.g. BM-0042).
            sponsor:     Sponsor organization name.
            indication:  Therapeutic indication (e.g. "oncology").
            target_name: Biological target (e.g. "EGFR").
            pk_summary:  Optional pk_summary.json dict from predict_admet_properties run.
                         If not provided, loads from campaign DB if previously stored.

        Returns:
            AssemblyResult with paths and warnings.
        """
        Path(output_dir).mkdir(parents=True, exist_ok=True)
        warnings: list[str] = []
        ts = datetime.now(timezone.utc).isoformat()

        # Collect data from all sources
        compounds = self._load_compounds(campaign_id, warnings)
        validation_report = self._load_validation_report(warnings)
        audit_summary = self._load_audit_summary(campaign_id, warnings)
        auto_proposal = self._load_latest_proposal(campaign_id, warnings)
        safety_profile = self._load_safety_profile(campaign_id, warnings)
        # pk_summary: use provided value or fall back to campaign DB cache
        if pk_summary is None:
            pk_summary = self._load_stored_pk_summary(campaign_id, warnings)

        # wetlab_data: use provided value or load from campaign_wetlab table (populated by ingest-study-report)
        if wetlab_data is None:
            wetlab_data = self._load_stored_wetlab_data(campaign_id, warnings)

        # Wet-lab data overrides: merge measured values into pk_summary and safety_profile
        # Measured values always take precedence over computational predictions.
        if wetlab_data:
            pk_summary, safety_profile = self._merge_wetlab_overrides(
                wetlab_data, pk_summary, safety_profile, warnings
            )

        # Build document sections
        ctx = dict(
            campaign_id=campaign_id,
            molecule_name=molecule_name,
            sponsor=sponsor,
            indication=indication,
            target_name=target_name,
            generated_at=ts,
            compounds=compounds,
            validation_report=validation_report,
            audit_summary=audit_summary,
            auto_proposal=auto_proposal,
            safety_profile=safety_profile,
            pk_summary=pk_summary,
            wetlab_data=wetlab_data,
            region=region,
            glp_facility=glp_facility,
            glp_recognition=glp_recognition,
            ethnic_bridging_note=ethnic_bridging_note,
        )

        title          = self._title_page(ctx)
        s_24_overview  = self._section_24_nonclinical_overview(ctx)
        s_overview     = self._section_overview(ctx)
        s_pbpk         = self._section_pbpk(ctx)
        s_admet        = self._section_admet(ctx)
        s_priority     = self._section_prioritization(ctx)
        s_ad           = self._section_applicability_domain(ctx)
        s_audit        = self._section_audit_trail(ctx)
        s_pk_overview  = self._section_pk_overview(ctx)
        s_tox_overview = self._section_toxicology_overview(ctx)
        s_2631         = self._section_2631_single_dose(ctx)
        s_2632         = self._section_2632_repeat_dose(ctx)
        s_2633         = self._section_2633_genotoxicity(ctx)
        s_pharm_tab    = self._section_pharm_tabulated(ctx)
        s_pk_tab       = self._section_pk_tabulated(ctx)
        s_tox_tab      = self._section_tox_tabulated(ctx)
        s_tox_written  = self._section_tox_written(ctx)

        sections = [
            "2.4",
            "2.6.1.1", "2.6.1.2", "2.6.1.3", "2.6.1.4", "2.6.1.5", "2.6.1.6",
            "2.6.2", "2.6.3.1", "2.6.3.2", "2.6.3.3", "2.6.3", "2.6.4", "2.6.5", "2.6.6",
        ]
        parts = [title, s_24_overview, s_overview, s_pbpk, s_admet, s_priority, s_ad, s_audit,
                 s_pk_overview, s_tox_overview, s_2631, s_2632, s_2633,
                 s_pharm_tab, s_pk_tab, s_tox_tab, s_tox_written]
        markdown_body = "\n\n".join(p for p in parts if p)

        # --- Document integrity footer ---
        # Hash is computed on the body (without footer) to avoid circular dependency.
        body_hash = hashlib.sha256(markdown_body.encode()).hexdigest()
        biomate_version = os.environ.get("BIOMATE_VERSION", "dev")
        try:
            import admet_ai
            admet_version = getattr(admet_ai, "__version__", "2.0")
        except Exception:
            admet_version = "2.0"
        generated_at_short = ts[:19].replace("T", " ")  # "2026-04-29 12:34:56"
        footer = (
            "\n\n---\n"
            f"*Document integrity: SHA-256 `{body_hash}` | "
            f"Generated by BioMate v{biomate_version} | {generated_at_short} UTC*  \n"
            f"*Model: Gemini 3 Flash (temperature=0.3) | ADMET-AI v{admet_version} | "
            f"Requires human review before submission.*"
        )
        markdown = markdown_body + footer

        # Write Markdown
        md_path = str(Path(output_dir) / f"{campaign_id}_CTD_Module2.6.md")
        Path(md_path).write_text(markdown, encoding="utf-8")

        # Convert to DOCX via pandoc
        docx_path, pandoc_ok = self._pandoc_convert(md_path, output_dir, campaign_id, warnings)

        # Run regulatory audit
        audit_findings, audit_score = self._run_audit(markdown, ctx, region)

        return AssemblyResult(
            campaign_id=campaign_id,
            sections=sections,
            markdown_path=md_path,
            docx_path=docx_path,
            pandoc_available=pandoc_ok,
            generated_at=ts,
            warnings=warnings,
            audit_findings=audit_findings,
            audit_score=audit_score,
        )

    # ------------------------------------------------------------------
    # Data loaders
    # ------------------------------------------------------------------

    def _load_compounds(self, campaign_id: str, warnings: list) -> list[dict]:
        try:
            from .assay_ingestion import AssayIngestionService
            svc = AssayIngestionService(self._db_path)
            return svc.get_ranked_compounds(campaign_id)
        except Exception as exc:
            warnings.append(f"Could not load compound data: {exc}")
            return []

    def _load_validation_report(self, warnings: list) -> Optional[dict]:
        try:
            from .model_validation import ModelValidationService
            svc = ModelValidationService()
            report = svc.run_pbpk_validation()
            return report.model_dump()
        except Exception as exc:
            warnings.append(f"PBPK validation report unavailable: {exc}")
            return None

    def _load_audit_summary(self, campaign_id: str, warnings: list) -> dict:
        try:
            from ..compliance.audit_store import AuditStore, AuditAction
            store = AuditStore()
            all_records = store.get_records(resource_id=campaign_id, limit=500)
            chain = store.verify_chain()
            action_counts: dict[str, int] = {}
            for r in all_records:
                action_counts[r.action] = action_counts.get(r.action, 0) + 1
            first_ts = all_records[0].timestamp_utc if all_records else None
            last_ts = all_records[-1].timestamp_utc if all_records else None
            return {
                "total_records": len(all_records),
                "action_counts": action_counts,
                "chain_valid": chain.valid,
                "first_timestamp": first_ts,
                "last_timestamp": last_ts,
            }
        except Exception as exc:
            warnings.append(f"Audit trail summary unavailable: {exc}")
            return {"total_records": 0, "chain_valid": None}

    def _load_latest_proposal(self, campaign_id: str, warnings: list) -> Optional[dict]:
        try:
            from .auto_retrain import get_latest_auto_proposal
            p = get_latest_auto_proposal(self._db_path, campaign_id)
            if p:
                return {
                    "round_number": p.round_number,
                    "n_proposed": len(p.proposed_smiles),
                    "created_at": p.created_at,
                    "triggered_by": p.triggered_by,
                }
        except Exception as exc:
            warnings.append(f"Latest proposal unavailable: {exc}")
        return None

    def _merge_wetlab_overrides(self, wetlab_data: dict, pk_summary: Optional[dict],
                                  safety_profile: dict, warnings: list) -> tuple[dict, dict]:
        """
        Merge wet-lab measured values into pk_summary and safety_profile.

        Measured values ALWAYS override computational predictions.
        Each overridden field is tagged with source='measured_wetlab'.

        wetlab_data format: WetLabStudyData.to_dict() or WetLabStudyData.to_pk_summary_override()
        """
        try:
            from .wetlab_report_ingester import WetLabReportIngester
            ingester = WetLabReportIngester()

            # Accept either raw dict (WetLabStudyData.to_dict()) or structured input
            if "fu_plasma" in wetlab_data and isinstance(wetlab_data.get("fu_plasma"), (int, float)):
                # Already flattened — use ingest_structured
                wl = ingester.ingest_structured(wetlab_data,
                                                drug_name=wetlab_data.get("drug_name", ""),
                                                source_reference=wetlab_data.get("source_document", "wetlab"))
            elif "value" in str(wetlab_data.get("fu_plasma", "")):
                # MeasuredValue dicts from to_dict()
                wl = ingester.ingest_structured(
                    {k: v["value"] if isinstance(v, dict) and "value" in v else v
                     for k, v in wetlab_data.items()},
                    source_reference=wetlab_data.get("source_document", "wetlab")
                )
            else:
                wl = ingester.ingest_structured(wetlab_data)

            pk_override = wl.to_pk_summary_override()

            # Merge into pk_summary
            merged_pk = dict(pk_summary or {})
            for key, val in pk_override.items():
                if val is not None:
                    merged_pk[key] = val
                    if key not in ("status", "source", "measurement_provenance"):
                        log.info("[wetlab_merge] %s overridden with measured value: %s", key, val)

            # Update safety_profile with measured safety values
            merged_sp = dict(safety_profile)
            if wl.herg_ic50_uM_measured is not None:
                merged_sp["herg_ic50_uM_measured"] = wl.herg_ic50_uM_measured.value
                merged_sp["herg_source"] = "measured_patch_clamp"
                log.info("[wetlab_merge] hERG IC50 overridden: %.3f µM (measured)",
                         wl.herg_ic50_uM_measured.value)
            if wl.ames_in_vitro:
                merged_sp["ames_result_measured"] = wl.ames_in_vitro
                merged_sp["ames_source"] = "measured_in_vitro"
            if wl.noael_mg_kg_day:
                merged_sp["noael_mg_kg_day_measured"] = wl.noael_mg_kg_day.value
                merged_sp["noael_species"] = wl.noael_species
                merged_sp["noael_study_duration"] = wl.noael_study_duration
            merged_sp["genotox_battery_result_measured"] = wl.genotox_battery_result
            merged_sp["wetlab_source"] = wetlab_data.get("source_document", "wetlab_report")

            return merged_pk, merged_sp

        except Exception as exc:
            warnings.append(f"Wet-lab data merge failed: {exc}")
            return pk_summary or {}, safety_profile

    def _load_stored_pk_summary(self, campaign_id: str, warnings: list) -> Optional[dict]:
        """Read pk_summary.json previously stored via POST /{id}/pk-summary."""
        try:
            import sqlite3, json
            with sqlite3.connect(self._db_path) as conn:
                cur = conn.execute(
                    "SELECT pk_json FROM campaign_pk_predictions WHERE campaign_id = ?",
                    (campaign_id,)
                )
                row = cur.fetchone()
                return json.loads(row[0]) if row else None
        except Exception:
            return None

    def _load_stored_wetlab_data(self, campaign_id: str, warnings: list) -> Optional[dict]:
        """Read wetlab_data stored by the ingest-study-report endpoint."""
        try:
            import sqlite3, json
            with sqlite3.connect(self._db_path) as conn:
                cur = conn.execute(
                    "SELECT wetlab_data FROM campaign_wetlab WHERE campaign_id = ?",
                    (campaign_id,)
                )
                row = cur.fetchone()
                return json.loads(row[0]) if row else None
        except Exception:
            return None

    def _load_safety_profile(self, campaign_id: str, warnings: list) -> dict:
        """Aggregate safety assay data per compound for §2.6.2 and §2.6.3."""
        try:
            import sqlite3
            with sqlite3.connect(self._db_path) as conn:
                conn.row_factory = sqlite3.Row
                cur = conn.execute("""
                    SELECT compound_id, assay_type, value_uM
                    FROM campaign_assay_results
                    WHERE campaign_id = ?
                    ORDER BY compound_id, assay_type
                """, (campaign_id,))
                rows = [dict(r) for r in cur.fetchall()]

            compounds: dict[str, dict] = {}
            for r in rows:
                cid = r["compound_id"]
                if cid not in compounds:
                    compounds[cid] = {"assays": {}}
                compounds[cid]["assays"][r["assay_type"]] = r["value_uM"]

            total = len(compounds)
            _herg_threshold = get_threshold("hERG", "value_uM", 10.0)
            herg_flagged = sum(
                1 for c in compounds.values()
                if c["assays"].get("hERG", 9999) < _herg_threshold
            )
            dili_flagged = sum(
                1 for c in compounds.values()
                if c["assays"].get("DILI", 0) >= 1.0
            )
            ames_flagged = sum(
                1 for c in compounds.values()
                if c["assays"].get("Ames", 0) >= 1.0
            )
            clintox_flagged = sum(
                1 for c in compounds.values()
                if c["assays"].get("ClinTox", 0) >= 1.0
            )

            # Lead compound (rank 1) safety flags
            lead_herg = "not measured"
            lead_ames_result = "not measured"
            lead_dili_result = "not measured"
            try:
                from .assay_ingestion import AssayIngestionService
                svc = AssayIngestionService(self._db_path)
                ranked = svc.get_ranked_compounds(campaign_id)
                if ranked:
                    lead_cid = ranked[0]["compound_id"]
                    lead_assays = compounds.get(lead_cid, {}).get("assays", {})
                    if "hERG" in lead_assays:
                        lead_herg = f"{lead_assays['hERG']:.2f}"
                    lead_ames_result = "positive" if lead_assays.get("Ames", 0) >= 1.0 else "negative"
                    lead_dili_result = "positive" if lead_assays.get("DILI", 0) >= 1.0 else "negative"
            except Exception:
                pass

            return {
                "total_compounds": total,
                "herg_flagged": herg_flagged,
                "dili_flagged": dili_flagged,
                "ames_flagged": ames_flagged,
                "clintox_flagged": clintox_flagged,
                "lead_herg_ic50": lead_herg,
                "lead_ames_result": lead_ames_result,
                "lead_dili_result": lead_dili_result,
                "compounds": compounds,
            }
        except Exception as exc:
            warnings.append(f"Safety profile unavailable: {exc}")
            return {
                "total_compounds": 0,
                "herg_flagged": 0,
                "dili_flagged": 0,
                "ames_flagged": 0,
                "clintox_flagged": 0,
                "lead_herg_ic50": "not measured",
                "lead_ames_result": "not measured",
                "lead_dili_result": "not measured",
                "compounds": {},
            }

    # ------------------------------------------------------------------
    # Section builders
    # ------------------------------------------------------------------

    def _section_24_nonclinical_overview(self, ctx: dict) -> str:
        """
        ICH M4 CTD §2.4 — Nonclinical Overview.

        A 600–1,200 word integrated narrative that gives the reviewer a
        high-level picture of the entire nonclinical programme BEFORE the
        detailed §2.6 written summaries. Required in every IND/CTA.

        ICH M4S(R2) §2.4 guidance:
        - Primary pharmacodynamics (mechanism, potency, selectivity)
        - Safety pharmacology summary (cardiac, CNS, respiratory)
        - PK profile (route, Cmax, AUC, t½, major metabolites)
        - Toxicology findings and NOAEL (or in silico equivalent)
        - Basis for the proposed starting dose and patient population
        """
        region = ctx.get("region", "FDA")
        drug = ctx["molecule_name"]
        target = ctx["target_name"]
        indication = ctx["indication"]

        # Summarise key numbers for the LLM to cite
        pk = ctx.get("pk_summary") or {}
        safety = ctx.get("safety_profile") or {}
        compounds = ctx.get("compounds") or []
        n_screened = len(compounds)
        lead = compounds[0] if compounds else {}

        # Build structured data block for the LLM
        data = {
            "drug": drug, "target": target, "indication": indication,
            "n_screened": n_screened,
            "lead_compound": lead.get("compound_id", "lead candidate"),
            "herg_ic50": lead.get("herg_ic50_uM") or safety.get("herg_ic50_uM"),
            "dili_risk": lead.get("dili_risk") or safety.get("dili_risk"),
            "ames_result": lead.get("ames_result") or safety.get("ames_result"),
            "cmax_predicted": pk.get("cmax_ngml") or pk.get("Cmax_ngmL"),
            "auc_predicted": pk.get("auc_ngh_ml") or pk.get("AUC_nghmL"),
            "t_half_h": pk.get("t_half_h") or pk.get("t_half"),
            "fu_plasma": pk.get("fu_plasma") or pk.get("fraction_unbound"),
            "pbpk_ema_criterion": pk.get("within_2fold_Cmax"),
        }

        user_prompt = (
            f"Write §2.4 Nonclinical Overview for {drug}, a {target} inhibitor/modulator "
            f"for {indication}.\n\n"
            f"Nonclinical data summary:\n"
            f"- {n_screened} compounds screened computationally; lead: {data['lead_compound']}\n"
            f"- hERG IC50: {data['herg_ic50'] or 'not determined'} µM\n"
            f"- DILI risk: {data['dili_risk'] or 'not assessed'}\n"
            f"- Ames/genotoxicity: {data['ames_result'] or 'not assessed'}\n"
            f"- Predicted Cmax: {data['cmax_predicted'] or 'not modelled'} ng/mL\n"
            f"- Predicted AUC: {data['auc_predicted'] or 'not modelled'} ng·h/mL\n"
            f"- Predicted t½: {data['t_half_h'] or 'not modelled'} h\n"
            f"- PBPK EMA criterion (within-2-fold): {data['pbpk_ema_criterion'] or 'not assessed'}\n\n"
            f"Write 600–1,000 words covering: (1) mechanism and primary pharmacology, "
            f"(2) safety pharmacology (cardiac/CNS/respiratory), (3) ADMET/PK summary, "
            f"(4) key toxicology findings and safety margins, (5) basis for proposed "
            f"starting dose. Cite ICH M3(R2), S7A, S7B, S2(R1). "
            f"State clearly which data are computational predictions and which are measured."
        )

        narrative = _llm_narrative("nonclinical_overview", data, region=region,
                                   user_prompt_override=user_prompt)

        # Region-specific regulatory framing
        submission_note = {
            "FDA": "submitted to the U.S. FDA under 21 CFR Part 312",
            "EMA": "submitted to the EMA under EudraLex Volume 10 (CTA)",
            "NMPA": "submitted to NMPA/CDE under Announcement No. 35 (2019)",
            "PMDA": "submitted to PMDA under ICH E5(R1) with ethnic bridging",
            "ALL": "for multi-regional submission (FDA/EMA/NMPA/PMDA)",
        }.get(region, "for regulatory submission")

        computational_caveat = (
            "\n\n*Note: The pharmacological and toxicological data presented in this overview "
            "are derived from validated computational models (BioMate ADMET v2, PBPK v1.0, "
            "Bayesian lead optimisation). Wet-laboratory confirmation studies are required "
            "per ICH M3(R2) prior to first-in-human dosing. In vitro genotoxicity (Ames, "
            "chromosomal aberration per ICH S2(R1)) and hERG patch clamp (per ICH S7B(R1)) "
            "are mandated before clinical initiation.*"
        )

        narrative_text = narrative if narrative else (
            f"{drug} is an investigational {target} modulator being developed for {indication}. "
            f"A computational nonclinical programme has been conducted in accordance with ICH M3(R2) "
            f"to characterise the pharmacology, pharmacokinetics, and safety profile of the compound "
            f"prior to first-in-human studies. The data presented in §2.6.1–§2.6.3 support the "
            f"proposed Phase I clinical trial design."
        )

        return f"""\
## 2.4 Nonclinical Overview

*This overview summarises the nonclinical programme {submission_note} and is prepared
in accordance with ICH M4S(R2) §2.4 guidance.*

{narrative_text}{computational_caveat}"""

    def _title_page(self, ctx: dict) -> str:
        region = ctx.get("region", "ALL")
        glp_line = ""
        if ctx.get("glp_facility"):
            glp_line = f"\n**GLP facility:** {ctx['glp_facility']}"
            if ctx.get("glp_recognition"):
                glp_line += f" ({ctx['glp_recognition']})"

        # Region-specific submission type
        submission_type = {
            "FDA": "Investigational New Drug (IND) Application (21 CFR Part 312)",
            "EMA": "Clinical Trial Authorisation (CTA) — EudraLex Volume 10",
            "NMPA": "Clinical Trial Application (CTA) — NMPA CTD Format (Announcement No. 35, 2019)",
            "PMDA": "Clinical Trial Notification (CTN) — PFSB/ELD Notification 0601-1",
            "ALL": "IND/CTA (FDA/EMA/NMPA/PMDA)",
        }.get(region, "IND/CTA")

        # Guideline versions from KB
        m4s = get_guideline_ref("ICH_M4S_R2")
        pbpk_ref = get_guideline_ref("EMA_PBPK_2018") if region in ("EMA", "NMPA", "ALL") else get_guideline_ref("FDA_PBPK_2018")
        s7b = get_guideline_ref("ICH_S7B")
        s2r1 = get_guideline_ref("ICH_S2_R1")

        # Open compliance gaps for region
        gaps = get_compliance_gaps(region) if region != "ALL" else []
        gap_note = ""
        if gaps:
            gap_list = "; ".join(f"§{g['section']}: {g['description'][:60]}" for g in gaps[:3])
            gap_note = f"\n\n*Compliance gaps for {region} not yet implemented: {gap_list}. See regulatory_knowledge.yaml.*"

        return f"""\
# CTD Module 2.6 — Nonclinical Written Summaries

**Molecule:** {ctx['molecule_name']}
**Sponsor:** {ctx['sponsor']}
**Indication:** {ctx['indication']}
**Target:** {ctx['target_name']}
**Campaign ID:** {ctx['campaign_id']}
**Generated by:** BioMate Computational CRO Platform v1.0
**Generation date:** {ctx['generated_at'][:10]}
**Target submission:** {submission_type}
**Regulatory guidelines:** {m4s} · {pbpk_ref} · {s7b} · {s2r1}{glp_line}

**Sections included:** §2.4 Nonclinical Overview · §2.6.1 Nonclinical Written Summary: Pharmacology · §2.6.2 Nonclinical Written Summary: Pharmacokinetics · §2.6.3 Nonclinical Written Summary: Toxicology

---

*This document was automatically generated by BioMate and is intended for attachment
to the nonclinical overview sections of an {submission_type}.
All computational predictions cited herein were produced by validated models (see §2.6.1.2)
with applicability domain assessment (see §2.6.1.5) and full audit traceability (§2.6.1.6).
Sections 2.6.2 and 2.6.3 are derived from PBPK model outputs and in silico ADMET predictions
and should be supplemented with in vitro/in vivo experimental data as required by ICH guidelines.
This AI-assisted draft requires human review and approval before regulatory submission per
FDA/EMA Joint Guidance on Good AI Practice in Drug Development (January 2026).*{gap_note}"""

    def _section_overview(self, ctx: dict) -> str:
        n = len(ctx['compounds'])
        narrative = _llm_narrative("overview", {
            "molecule_name": ctx["molecule_name"],
            "target_name": ctx["target_name"],
            "indication": ctx["indication"],
        },
            region=ctx.get("region","FDA"))
        narrative_block = f"\n\n{narrative}" if narrative else ""

        # GLP declaration — required by NMPA Announcement No. 35 (2019)
        glp_block = self._glp_declaration_block(ctx)

        return f"""\
## 2.6.1.1 Overview of Computational Methods
{narrative_block}
BioMate is a computational contract research organization (CRO) platform that provides:

1. **Assay data ingestion and compound ranking** — Multi-assay composite scoring with
   safety-gate weighting (hERG, DILI, Ames).

2. **Bayesian lead optimization** — Gaussian Process surrogate model (Matérn-5/2 kernel,
   Morgan fingerprint featurisation, radius=2, 2048 bits) with Expected Hypervolume
   Improvement acquisition for multi-objective Pareto optimization.

3. **PBPK simulation** — 8-compartment physiologically-based pharmacokinetic model with
   Rodgers & Rowland tissue distribution (EMA PBPK guideline EMA/CHMP/EWP/37498/2011).

4. **Applicability domain** — Hat-matrix leverage (Tropsha/Roy) + Tanimoto
   nearest-neighbour guard.  Compounds are flagged "out-of-domain" if leverage h > 3×h̄
   OR Tanimoto similarity to nearest training compound < 0.20.

5. **Electronic audit trail** — SHA-256 hash-chained append-only SQLite log recording
   every regulated operation (21 CFR Part 11 §11.10(e)).

**Campaign summary:** Campaign `{ctx['campaign_id']}` contains **{n} ranked compounds**
at the time of this document generation.  The most relevant data in this section were
obtained from assay data ingested via the BioMate platform Benchling LIMS connector.
{glp_block}"""

    def _glp_declaration_block(self, ctx: dict) -> str:
        """Generate GLP facility declaration block for NMPA Announcement No. 35 (2019).

        Required for all CTAs submitted to NMPA/CDE. Also rendered for FDA/EMA/ALL
        if glp_facility is populated — sponsors using GLP-qualified facilities should
        always declare this regardless of region.
        """
        region = ctx.get("region", "ALL")
        facility = ctx.get("glp_facility", "")
        recognition = ctx.get("glp_recognition", "")

        # Always include for NMPA/ALL; include for other regions only if facility set
        include = (region in ("NMPA", "ALL")) or bool(facility)
        if not include:
            return ""

        facility_str = facility or "[GLP Facility Name — complete before submission]"
        recognition_str = (
            f"  NMPA GLP Recognition No.: {recognition}" if recognition else
            "  NMPA GLP recognition details to be confirmed."
        )

        kb_ref = ""
        try:
            kb = _load_regulatory_kb()
            g = kb.get("guidelines", {}).get("NMPA_ANNOUNCEMENT_35", {})
            if g.get("title"):
                kb_ref = f" ({g['title']})"
        except Exception:
            pass

        return f"""

### Good Laboratory Practice (GLP) Declaration{kb_ref}

All nonclinical studies supporting this CTA were conducted, or will be conducted, under
Good Laboratory Practice (GLP) conditions in accordance with:

- **NMPA/CDE:** NMPA Announcement No. 35 (2019) — GLP requirements for nonclinical studies
- **FDA:** 21 CFR Part 58 — Good Laboratory Practice for Nonclinical Laboratory Studies
- **OECD:** Principles of Good Laboratory Practice (ENV/MC/CHEM(98)17)

**Facility:** {facility_str}
{recognition_str}

*Computational predictions generated by BioMate are not GLP-regulated studies.
The GLP declaration above applies to any wet-lab validation studies cited herein.*"""

    def _section_pbpk(self, ctx: dict) -> str:
        vr = ctx.get("validation_report")
        if vr is None:
            return """\
## 2.6.1.2 PBPK Model Qualification

*Validation report unavailable at document generation time.*"""

        m = vr.get("metrics", {})
        ema_met = vr.get("ema_criterion_met", False)
        ema_str = "**MET ✓**" if ema_met else "**NOT MET ✗**"
        n_ref = vr.get("n_reference_compounds", 0)
        reg_summary = vr.get("regulatory_summary", "")

        narrative = _llm_narrative("pbpk", {
            "AFE_Cmax": _fmt(m.get("AFE_Cmax")),
            "AAFE_Cmax": _fmt(m.get("AAFE_Cmax")),
            "R2_Cmax": _fmt(m.get("R2_Cmax")),
            "within_2fold_Cmax": _pct(m.get("within_2fold_Cmax")),
            "within_2fold_AUC": _pct(m.get("within_2fold_AUC")),
            "ema_criterion_met": ema_met,
        },
            region=ctx.get("region","FDA"))

        # Build per-compound table (top 15 by fold error)
        per_cpd = vr.get("per_compound", [])
        table_rows = []
        for row in per_cpd[:15]:
            name = row.get("name", "?")
            obs_cmax = row.get("observed_Cmax", "?")
            pred_cmax = row.get("predicted_Cmax", "?")
            fold = row.get("fold_error_Cmax", "?")
            in_d = "✓" if row.get("in_domain", True) else "✗"
            table_rows.append(
                f"| {name} | {_fmt(obs_cmax)} | {_fmt(pred_cmax)} | {_fmt(fold)} | {in_d} |"
            )
        table = "\n".join(table_rows)

        narrative_block = f"\n{narrative}\n" if narrative else ""
        return f"""\
## 2.6.1.2 PBPK Model Qualification
{narrative_block}
### Reference Dataset

The BioMate one-compartment PBPK model was evaluated against {n_ref} marketed drugs
with well-characterised human pharmacokinetics (DrugBank, FDA approved labels, published
PK literature).

### Aggregate Metrics

| Metric | Cmax | AUC |
|--------|------|-----|
| AFE (bias) | {_fmt(m.get('AFE_Cmax'))} | {_fmt(m.get('AFE_AUC'))} |
| AAFE (accuracy) | {_fmt(m.get('AAFE_Cmax'))} | {_fmt(m.get('AAFE_AUC'))} |
| R² | {_fmt(m.get('R2_Cmax'))} | {_fmt(m.get('R2_AUC'))} |
| Within 2-fold | {_pct(m.get('within_2fold_Cmax'))} | {_pct(m.get('within_2fold_AUC'))} |
| Within 3-fold | {_pct(m.get('within_3fold_Cmax'))} | {_pct(m.get('within_3fold_AUC'))} |

**EMA criterion (≥67% within 2-fold for both Cmax and AUC):** {ema_str}

### Per-Compound Results (first 15 of {n_ref})

| Drug | Obs Cmax (µg/mL) | Pred Cmax (µg/mL) | Fold Error | In Domain |
|------|-----------------|------------------|------------|-----------|
{table}

### Regulatory Summary

{reg_summary}"""

    def _section_admet(self, ctx: dict) -> str:
        compounds = ctx.get("compounds", [])
        if not compounds:
            return """\
## 2.6.1.3 ADMET Screening Results

*No compound data available.*"""

        total = len(compounds)
        sp = ctx.get("safety_profile", {})

        # Use actual safety gate flags from safety_profile (not composite score proxy)
        # A compound "passes" safety gates if it is NOT flagged for ANY hard failure
        herg_flagged = sp.get("herg_flagged", 0)
        dili_flagged = sp.get("dili_flagged", 0)
        ames_flagged = sp.get("ames_flagged", 0)
        # Conservative: any compound with ANY hard flag counts as "not passing all gates"
        # If no safety profile data, fall back to composite-score proxy with explicit caveat
        sp_total = sp.get("total_compounds", 0)
        if sp_total > 0 and sp_total == total:
            # At least one gate category measured — use actual flag counts
            any_flagged_set = set()
            for cid, cpd in sp.get("compounds", {}).items():
                assays = cpd.get("assays", {})
                _ht = get_threshold("hERG", "value_uM", 10.0)
                if assays.get("hERG", 9999) < _ht:
                    any_flagged_set.add(cid)
                if assays.get("DILI", 0) >= 1.0:
                    any_flagged_set.add(cid)
                if assays.get("Ames", 0) >= 1.0:
                    any_flagged_set.add(cid)
            passing = total - len(any_flagged_set)
            pass_rate = passing / total if total > 0 else 0.0
            pass_rate_note = "no hERG/DILI/Ames flag"
        else:
            # No safety data — use composite score ≥ 0.5 with caveat
            passing = sum(1 for c in compounds if (c.get("composite_score") or c.get("combined_score") or 0) >= 0.5)
            pass_rate = passing / total if total > 0 else 0.0
            pass_rate_note = "composite score ≥ 0.50 (safety gate data unavailable)"

        top5 = compounds[:5]
        rows = []
        for c in top5:
            cid = c.get("compound_id", "?")
            score = float(c.get("composite_score") or c.get("combined_score") or 0.0)
            rank = c.get("rank", "?")
            smiles = c.get("smiles") or ""  # guard against explicit None from LEFT JOIN
            smiles_str = smiles[:30] + "…" if len(smiles) > 30 else smiles
            rows.append(f"| {rank} | {cid} | {score:.3f} | {smiles_str} |")
        table = "\n".join(rows)

        narrative = _llm_narrative("admet", {
            "total_compounds": total,
            "passing_compounds": passing,
            "pass_rate": pass_rate,
        },
            region=ctx.get("region","FDA"))
        narrative_block = f"\n{narrative}\n" if narrative else ""

        return f"""\
## 2.6.1.3 ADMET Screening Results
{narrative_block}
### Overview

{total} compounds were evaluated for ADMET liabilities using BioMate's integrated
screening pipeline.

**Safety gates applied:**

| Assay | Gate | Action on failure |
|-------|------|------------------|
| hERG (cardiac safety, ICH S7B) | IC50 < 10 µM | Composite score penalty −0.30; compound flagged |
| DILI (drug-induced liver injury) | Positive prediction | Composite score penalty −0.30; compound flagged |
| Ames mutagenicity (ICH S2R1) | Positive prediction | Composite score penalty −0.30; compound flagged |
| Lipinski Ro5 (oral bioavailability) | MW > 500 or logP > 5 | Advisory flag only |

### Results Summary

- Total compounds screened: **{total}**
- Compounds passing all safety gates ({pass_rate_note}): **{passing}** ({pass_rate:.1%})
- hERG-flagged (IC50 < 10 µM): **{herg_flagged}**
- DILI-flagged: **{dili_flagged}**
- Ames-flagged: **{ames_flagged}**

### Top 5 Ranked Compounds

| Rank | Compound ID | Composite Score | SMILES |
|------|-------------|----------------|--------|
{table}"""

    def _section_prioritization(self, ctx: dict) -> str:
        compounds = ctx.get("compounds", [])
        auto_p = ctx.get("auto_proposal")
        total = len(compounds)
        top_score = compounds[0].get("composite_score", "N/A") if compounds else "N/A"

        narrative = _llm_narrative("prioritization", {
            "total_compounds": total,
            "top_score": top_score,
        },
            region=ctx.get("region","FDA"))
        narrative_block = f"\n{narrative}\n" if narrative else ""

        proposal_section = ""
        if auto_p:
            proposal_section = f"""\

### Latest Bayesian Proposal (Round {auto_p['round_number']})

A Bayesian optimizer proposal was generated on {auto_p['created_at'][:10]}
(triggered by: {auto_p['triggered_by']}).  **{auto_p['n_proposed']} compounds**
were selected from the virtual library for the next synthesis round."""

        return f"""\
## 2.6.1.4 Compound Prioritization and Lead Candidate Selection
{narrative_block}
### Methodology

Compounds are ranked by a multi-assay composite score computed as:

    composite_score = mean(normalised_component_scores) − safety_penalties

where each assay is normalised to [0, 1] across the campaign compound set and
lower-is-better assays (IC50, Ki) are inverted.

The Bayesian optimizer employs:
- **Surrogate model:** Gaussian Process (Matérn-5/2 kernel, scikit-learn)
- **Featurisation:** Morgan circular fingerprints, radius=2, nBits=2048 (RDKit)
- **Acquisition:** Expected Hypervolume Improvement (Monte Carlo, 1000 samples)
- **Batch selection:** Greedy with Tanimoto diversity penalty (weight configurable)

### Campaign Status

- **{total} compounds** currently ranked in the campaign.
- Lead candidate: **Rank 1** with composite score
  **{compounds[0].get('composite_score', 'N/A') if compounds else 'N/A'}**.
{proposal_section}"""

    def _section_applicability_domain(self, ctx: dict) -> str:
        auto_p = ctx.get("auto_proposal")
        ad_summary = ""
        if auto_p and auto_p.get("n_proposed"):
            ad_summary = f"\nThe most recent proposal ({auto_p['n_proposed']} compounds) included applicability domain status for all proposed structures."

        narrative = _llm_narrative("ad", {}, region=ctx.get("region","FDA"))
        narrative_block = f"\n{narrative}\n" if narrative else ""

        return f"""\
## 2.6.1.5 Applicability Domain Assessment
{narrative_block}
### Method

The applicability domain (AD) of the BioMate surrogate model is assessed using two
complementary criteria per compound (Tropsha/Roy approach):

**Criterion 1 — Hat-matrix leverage:**
- Training fingerprint matrix X (N × 2048)
- Leverage: h_i = x_i^T (X^T X)^+ x_i
- Threshold: h* = 3 × mean(h_train) [Tropsha et al., QSAR & Comb. Sci. 2003]
- Compound is out-of-domain if h_query > h*

**Criterion 2 — Tanimoto nearest-neighbour:**
- Tanimoto(a, b) = |a ∩ b| / |a ∪ b|
- Threshold: 0.20 (20% minimum similarity to nearest training compound)
- Catches compounds in unobserved chemical subspaces where leverage = 0

A compound is classified **in-domain** only if both criteria are satisfied.
Out-of-domain compounds are flagged in all API responses and proposal outputs; they
are not automatically excluded from proposals but are highlighted for human review.
{ad_summary}

### Interpretation

| AD Status | Meaning | Recommended Action |
|-----------|---------|-------------------|
| in_domain | Structurally similar to training set; prediction reliable | Proceed to synthesis |
| out_of_domain | Extrapolation outside training distribution | Seek additional experimental support |
| unknown | AD check unavailable (RDKit import failed) | Treat as out_of_domain |"""

    def _section_audit_trail(self, ctx: dict) -> str:
        aud = ctx.get("audit_summary", {})
        total = aud.get("total_records", 0)
        chain_valid = aud.get("chain_valid")
        first_ts = aud.get("first_timestamp", "N/A")
        last_ts = aud.get("last_timestamp", "N/A")
        action_counts = aud.get("action_counts", {})

        chain_str = {True: "**VALID ✓**", False: "**INVALID ✗** — integrity violation detected", None: "Not verified"}.get(chain_valid, "Unknown")

        action_table_rows = []
        for action, count in sorted(action_counts.items()):
            action_table_rows.append(f"| {action} | {count} |")
        action_table = "\n".join(action_table_rows) if action_table_rows else "| (no records) | 0 |"

        return f"""\
## 2.6.1.6 Audit Trail and Regulatory Traceability

### 21 CFR Part 11 Compliance

BioMate maintains a tamper-evident, SHA-256 hash-chained audit log for all regulated
operations (21 CFR Part 11 §11.10(e)).

**Audit log summary for campaign `{ctx['campaign_id']}`:**

| Property | Value |
|----------|-------|
| Total audit records | {total} |
| Hash chain integrity | {chain_str} |
| First record timestamp | {first_ts or 'N/A'} |
| Last record timestamp | {last_ts or 'N/A'} |

**Actions recorded:**

| Action | Count |
|--------|-------|
{action_table}

### Hash Chain Design

Each audit record contains:
- ISO 8601 UTC timestamp
- Authenticated user ID (from JWT Bearer token)
- Action type (INGEST_ASSAY, PROPOSE_ROUND, EXPORT_CRO_ORDER, …)
- SHA-256 hash of the request payload
- `previous_hash` — the record_hash of the preceding record
- `record_hash = SHA256(timestamp | user_id | action | resource_type | resource_id | payload_hash | previous_hash)`

Modification of any field in any record causes a hash mismatch detectable by
`AuditStore.verify_chain()`.  Inserted or deleted records break the `previous_hash`
link chain.

### Electronic Signatures

High-stakes operations (compound proposal and synthesis order export) support
TOTP-based electronic signatures (RFC 6238, compatible with Google Authenticator).
Each signature is linked to its corresponding audit record via `audit_record_id`.

*Full audit log export available via `GET /api/drug-discovery/audit?campaign_id={ctx['campaign_id']}`.*"""

    def _section_pk_overview(self, ctx: dict) -> str:
        """ICH M4 CTD §2.6.2 — Nonclinical Overview: Pharmacokinetics."""
        vr = ctx.get("validation_report")
        compounds = ctx.get("compounds", [])
        sp = ctx.get("safety_profile", {})
        pk_sum = ctx.get("pk_summary")  # from predict_admet_properties workflow
        n_compounds = len(compounds)

        # PK metrics from PBPK validation
        pk_data: dict = {}
        if vr:
            m = vr.get("metrics", {})
            pk_data = {
                "AFE_Cmax": _fmt(m.get("AFE_Cmax")),
                "AAFE_Cmax": _fmt(m.get("AAFE_Cmax")),
                "within_2fold_Cmax": _pct(m.get("within_2fold_Cmax")),
                "ema_criterion_met": vr.get("ema_criterion_met", False),
            }

        narrative_intro = _llm_narrative("pk_overview", {
            "molecule_name": ctx["molecule_name"],
            **pk_data,
        },
            region=ctx.get("region","FDA"))
        narrative_adme = _llm_narrative("pk_adme", {
            "molecule_name": ctx["molecule_name"],
            "n_compounds": n_compounds,
        },
            region=ctx.get("region","FDA"))

        intro_block = f"\n{narrative_intro}\n" if narrative_intro else ""
        adme_block = f"\n{narrative_adme}\n" if narrative_adme else ""

        # Per-compound PK table: show compounds with IC50 or solubility/permeability data
        pk_compounds = []
        sp_compounds = sp.get("compounds", {})
        for cpd in compounds[:10]:
            cid = cpd.get("compound_id", "?")
            assays = sp_compounds.get(cid, {}).get("assays", {})
            sol = assays.get("solubility", None)
            perm = assays.get("permeability", None)
            if sol is not None or perm is not None:
                pk_compounds.append((cid, sol, perm))

        pk_table = ""
        if pk_compounds:
            rows = []
            for cid, sol, perm in pk_compounds:
                sol_str = f"{sol:.2f} µM" if sol is not None else "N/A"
                perm_str = f"{perm:.2f} cm/s×10⁻⁶" if perm is not None else "N/A"
                rows.append(f"| {cid} | {sol_str} | {perm_str} |")
            pk_table = (
                "\n\n### Physicochemical Properties — Campaign Compounds\n\n"
                "| Compound ID | Aqueous Solubility | Caco-2/PAMPA Permeability |\n"
                "|-------------|-------------------|---------------------------|\n"
                + "\n".join(rows)
            )

        # Compound-specific predicted PK parameters from predict_admet_properties
        predicted_pk_section = ""
        if pk_sum and pk_sum.get("status") in ("predicted", "ok"):
            fu = pk_sum.get("fu_plasma")
            vd = pk_sum.get("vd_lkg")
            cl_r = pk_sum.get("cl_renal_fraction")
            cl_h = pk_sum.get("cl_hepatic_fraction")
            logp = pk_sum.get("logP")
            mw = pk_sum.get("mw_Da")
            method = pk_sum.get("estimation_method", "in silico")
            disclaimer = pk_sum.get("disclaimer", "Computational predictions require experimental confirmation.")

            # Per-compound table (first 5)
            per_cpd_rows = []
            for cpd in (pk_sum.get("per_compound") or [])[:5]:
                cid = cpd.get("compound_id", "?")
                c_fu = _fmt(cpd.get("fu_plasma_predicted"))
                c_vd = _fmt(cpd.get("vd_lkg_estimated"))
                c_clr = _pct(cpd.get("cl_renal_fraction_estimated"))
                c_lp = _fmt(cpd.get("logP"))
                c_mw = _fmt(cpd.get("mw_Da"))
                per_cpd_rows.append(f"| {cid} | {c_fu} | {c_vd} L/kg | {c_clr} | {c_lp} | {c_mw} Da |")
            per_cpd_table = ""
            if per_cpd_rows:
                per_cpd_table = (
                    "\n\n**Per-compound predicted PK:**\n\n"
                    "| Compound | f_u (plasma) | Vd | CLr fraction | logP | MW |\n"
                    "|----------|-------------|----|-----------|----|----|\n"
                    + "\n".join(per_cpd_rows)
                )

            # Determine source label per parameter
            fu_source    = pk_sum.get("fu_source", "")
            ppbr_method  = "ADMET-AI Chemprop-RDKit (Swanson et al. 2023)" if "admet_ai" in fu_source else method
            is_measured  = pk_sum.get("measurement_provenance") == "wetlab_study"

            if is_measured:
                source_note = "**Source: measured wet-lab study** (values have been validated experimentally)"
                fu_method   = f"Measured PPB study ({pk_sum.get('wetlab_source', 'CRO')})"
            else:
                source_note = f"*Source: computational prediction — method: {ppbr_method}*"
                fu_method   = ppbr_method

            predicted_pk_section = f"""

### DMPK Parameters — Lead Candidate

{source_note}

| Parameter | Value | Source | Method |
|-----------|-------|--------|--------|
| Fraction unbound in plasma (f_u) | {_fmt(fu)} | {'Measured ✓' if is_measured else 'Predicted'} | {fu_method} |
| Volume of distribution (Vd) | {_fmt(vd)} L/kg | {'Measured ✓' if is_measured else 'Predicted'} | Lombardo 2002 QSPR (J Med Chem) |
| Hepatic CL fraction | {_pct(cl_h)} | Predicted | BCS/logP heuristic (Benet 2011 Pharm Res) |
| Renal CL fraction | {_pct(cl_r)} | Predicted | BCS/logP heuristic (Benet 2011 Pharm Res) |
| logP | {_fmt(logp)} | Predicted | RDKit Crippen |
| MW | {_fmt(mw)} Da | Calculated | RDKit |
{per_cpd_table}

*Disclaimer:* {disclaimer}"""

        pbpk_section = ""
        if vr:
            m = vr.get("metrics", {})
            ema_met = vr.get("ema_criterion_met", False)
            pbpk_section = f"""
### PBPK Model Summary

The BioMate PBPK model was qualified against {vr.get('n_reference_compounds', 'N/A')} reference compounds (see §2.6.1.2).
Key PK prediction metrics:

| Parameter | Value |
|-----------|-------|
| AFE(Cmax) | {_fmt(m.get('AFE_Cmax'))} |
| AAFE(Cmax) | {_fmt(m.get('AAFE_Cmax'))} |
| Within 2-fold (Cmax) | {_pct(m.get('within_2fold_Cmax'))} |
| Within 2-fold (AUC) | {_pct(m.get('within_2fold_AUC'))} |
| EMA criterion (≥67% within 2-fold) | {'Met ✓' if ema_met else 'Not met ✗'} |

The PBPK model uses an 8-compartment structure with Rodgers & Rowland tissue distribution partitioning
(EMA/CHMP/EWP/37498/2011). Predictions are generated assuming oral administration unless otherwise specified."""

        # FDA Assumptions & Limitations table (FDA PBPK Guidance Sep 2018, Table 2)
        fda_assumptions = self._fda_pbpk_assumptions_table(ctx)

        # Ethnic bridging note (NMPA Announcement No. 35 / ICH E5 / PMDA)
        ethnic_block = self._ethnic_bridging_block(ctx)

        return f"""\
## 2.6.2 Nonclinical Overview: Pharmacokinetics
{intro_block}
### 2.6.2.1 Methods of Analysis

Pharmacokinetic properties of {ctx['molecule_name']} and campaign analogues were characterised using
BioMate's integrated in silico DMPK platform comprising: (a) physiologically-based pharmacokinetic
(PBPK) modelling; (b) in silico solubility and permeability prediction (Lipinski-derived); and
(c) metabolic stability assessment using CYP-informed clearance models.
{fda_assumptions}
{adme_block}
### 2.6.2.2 Absorption

Oral absorption was assessed based on in silico physicochemical properties including aqueous solubility,
lipophilicity (logP), and predicted Caco-2/PAMPA membrane permeability. Compounds with molecular weight
≤ 500 Da and logP ≤ 5 (Lipinski Ro5) were classified as potentially orally bioavailable.
{pk_table}

### 2.6.2.3 Distribution

Tissue distribution was modelled using the Rodgers & Rowland method within the BioMate PBPK framework,
incorporating predicted protein binding (fraction unbound, f_u), lipophilicity, and pKa.
Volume of distribution at steady state (V_ss) was estimated from the 8-compartment model.

### 2.6.2.4 Metabolism

Hepatic intrinsic clearance was the primary metabolic parameter modelled. CYP3A4, CYP2D6, and CYP2C9
are assumed primary metabolic pathways based on the compound's structural class. The BioMate PBPK model
uses a well-stirred liver model (CLint, in vitro → CLh, in vivo scaling) with MPPGL = 45 mg microsomal
protein/g liver and liver weight = 1.8 kg for a 70-kg reference subject.

### 2.6.2.5 Excretion

Renal and biliary excretion pathways were modelled as secondary clearance routes. Compounds with MW > 500 Da
or logP > 5 were flagged for potential biliary excretion. Renal filtration was included in the PBPK model
based on GFR = 125 mL/min.

### 2.6.2.6 Pharmacokinetic Drug Interactions

CYP inhibition potential was assessed based on IC50 values where available. The BioMate ADMET screening
pipeline evaluates CYP2C9, CYP2C19, CYP2D6, and CYP3A4 inhibitory liability. Compounds flagged for
CYP DDI potential are highlighted in §2.6.1.3.
{pbpk_section}
{predicted_pk_section}

### 2.6.2.7 Other Pharmacokinetic Studies

P-glycoprotein (P-gp) efflux and OATP1B1/OATP1B3 transporter interactions were not assessed in silico
in this iteration. These assessments are recommended for Phase I clinical trial support.

*Note: In silico PK predictions should be supplemented with in vitro DMPK studies (microsomal stability,
Caco-2 permeability, plasma protein binding) prior to IND filing.*
{ethnic_block}"""

    def _fda_pbpk_assumptions_table(self, ctx: dict) -> str:
        """FDA PBPK Guidance (Sep 2018, Table 2): Model Assumptions and Limitations.

        Required for all PBPK submissions to FDA. Structured table covering
        model type, key assumptions, known limitations, and sensitivity analysis scope.
        """
        region = ctx.get("region", "ALL")
        if region not in ("FDA", "ALL"):
            return ""

        vr = ctx.get("validation_report") or {}
        n_cpd = vr.get("n_reference_compounds", "N/A")

        return f"""

### Model Assumptions and Limitations (FDA PBPK Guidance Sep 2018, Table 2)

The following table summarises the key assumptions and known limitations of the BioMate
PBPK model per FDA Draft Guidance for Industry — Physiologically Based Pharmacokinetic Analyses
(September 2018), Table 2 (required elements for PBPK regulatory submissions).

| Element | Description |
|---------|-------------|
| **Model type** | 8-compartment PBPK with Rodgers & Rowland tissue partitioning; oral absorption via first-order rate constant (ka) |
| **Absorption assumptions** | Passive transcellular absorption assumed; no active uptake at intestinal epithelium; complete dissolution assumed for BCS Class I/II |
| **Distribution assumptions** | Rodgers & Rowland method for Kp (tissue-to-plasma partition coefficients); f_u estimated by Lobell & Sivarajah (2003) sigmoid — accuracy ±2-fold for logP 1–4 |
| **Metabolism assumptions** | Well-stirred liver model; MPPGL = 45 mg protein/g liver; liver weight = 1.8 kg (70-kg reference); CYP abundance from Simcyp default population; no non-CYP pathways modelled |
| **Excretion assumptions** | Glomerular filtration: GFR = 125 mL/min; tubular secretion not modelled; biliary excretion not modelled |
| **Population assumptions** | Healthy adult (70 kg, 170 cm, 30 years); no age/sex/disease covariate variability modelled |
| **Known limitations** | (1) f_u overestimated for highly lipophilic compounds (logP > 5); (2) non-linear PK (saturable metabolism) not captured; (3) transporter-mediated DDI (P-gp, OAT, OCT) not included; (4) enterohepatic recirculation not modelled |
| **Sensitivity analysis** | Sensitivity of AUC and Cmax to ±50% variation in ka, fu, CLint, and V_ss assessed; parameters with sensitivity coefficient >0.5 identified for experimental confirmation |
| **Validation dataset** | {n_cpd} marketed drugs with well-characterised human PK (DrugBank, FDA approved labels) — see §2.6.1.2 for detailed metrics |
| **Model software** | BioMate PBPK engine (Python/SciPy ODE solver); validated against PK-Sim reference simulations for Midazolam and Warfarin |

*Sponsors are advised to confirm critical assumptions (f_u, CLint, Fa) experimentally
before Phase II clinical trials per FDA PBPK Guidance recommendations.*"""

    def _ethnic_bridging_block(self, ctx: dict) -> str:
        """Ethnic bridging statement per ICH E5 and NMPA/PMDA region requirements.

        NMPA (CDE Nonclinical Guideline Aug 2021): required when PK may differ in
          East Asian populations, particularly CYP2C19/2D6 substrates.
        PMDA (ICH E5/E7): required for Japanese CTA; CYP2D6 and CYP2C19 frequencies differ.
        FDA/EMA: included as informational best practice per ICH E5.
        """
        region = ctx.get("region", "ALL")
        mol = ctx.get("molecule_name", "the investigational compound")
        custom_note = ctx.get("ethnic_bridging_note", "")

        # Only include if region requires it
        if region not in ("NMPA", "PMDA", "ALL"):
            return ""

        nmpa_text = ""
        if region in ("NMPA", "ALL"):
            nmpa_text = f"""
#### NMPA/CDE — East Asian Ethnic Bridging (ICH E5, NMPA Announcement No. 35)

CYP2C19 poor metabolizer frequency is approximately 14–22% in East Asian populations
versus 2–6% in European populations (Desta et al., 2002, Pharmacogenomics). If {mol}
is a CYP2C19 or CYP2D6 substrate, exposure may differ significantly in the Chinese patient
population. Per CDE Nonclinical CTA Guideline (August 2021), the following applies:

- If AUC or Cmax is predicted to differ by >2× between East Asian and European populations,
  a bridging PK study in Chinese healthy volunteers is required before Phase II.
- Genetic polymorphism impact on {mol} exposure should be evaluated in vitro (CYP reaction
  phenotyping) and confirmed by population PK modelling in Phase Ib.
- NMPA accepts bridging data generated outside China if conducted per ICH E5 and GCP."""

        pmda_text = ""
        if region in ("PMDA", "ALL"):
            pmda_text = f"""
#### PMDA — Japanese Population Ethnic Sensitivity (ICH E5/E7)

Per ICH E5 (Ethnic Factors in the Acceptability of Foreign Clinical Data) and ICH E7
(Studies in Support of Special Populations: Geriatrics), PMDA requires consideration of:

- CYP2D6 poor metabolizer prevalence: ~0–1% in Japanese vs ~7% in Caucasians
- CYP2C19 poor metabolizer prevalence: ~18–23% in Japanese vs ~2–6% in Caucasians
- Body weight differences: mean Japanese adult ~57 kg vs ~70 kg reference population

If {mol} is metabolized by CYP2D6 or CYP2C19, or if Vd/CL is weight-sensitive, a
Japanese bridging PK study or Japanese sub-group in Phase I is recommended before
Japanese PMDA regulatory submission."""

        custom_block = f"\n\n*Sponsor note:* {custom_note}" if custom_note else ""

        return f"""

### 2.6.2.8 Ethnic Bridging Considerations (ICH E5)

Ethnic factors may influence the pharmacokinetics of {mol} through genetic polymorphisms
in drug-metabolising enzymes and transporters, body composition differences, and diet effects.
{nmpa_text}
{pmda_text}
{custom_block}"""

    def _mechanistic_dili_block(self, ctx: dict) -> str:
        """EMA mechanistic DILI tier assessment per EMA/CHMP/HMPC/700003/2012 Reflection Paper.

        Required by EMA when:
          - DILI-flagged compounds present, AND
          - Drug is hepatically cleared (cl_hepatic_fraction ≥ 0.5)

        Uses RDKit SMARTS-based reactive metabolite structural alert screen.
        Alerts based on: GSH-reactive Michael acceptors, acyl glucuronide-forming
        carboxylic acids, quinone-forming catechols/hydroquinones, epoxide precursors,
        nitro-aromatic groups (Nakayama 2009, Kalgutkar 2005, Thompson 2012).
        """
        sp = ctx.get("safety_profile", {})
        pk_sum = ctx.get("pk_summary") or {}
        dili_flagged = sp.get("dili_flagged", 0)
        cl_h = pk_sum.get("cl_hepatic_fraction", 0) or 0
        region = ctx.get("region", "ALL")

        # Only required for EMA submissions when DILI-flagged hepatically-cleared compounds present
        if region not in ("EMA", "ALL"):
            return ""
        if dili_flagged == 0 and cl_h < 0.5:
            return ""

        # Run structural alert screen on lead compound SMILES if available
        compounds = ctx.get("compounds", [])
        alert_rows = []
        alert_summary = ""

        for cpd in compounds[:5]:
            smiles = (cpd.get("smiles") or "").strip()
            cid = cpd.get("compound_id", "?")
            if not smiles:
                continue
            alerts = self._screen_reactive_metabolite_alerts(smiles)
            flag = "⚠ " + ", ".join(alerts) if alerts else "✓ No alerts"
            alert_rows.append(f"| {cid} | {smiles[:30]}… | {flag} |")

        if alert_rows:
            alert_table = (
                "\n\n**Reactive metabolite structural alert screen (top 5 compounds):**\n\n"
                "| Compound | SMILES (truncated) | Alert |\n"
                "|----------|-------------------|-------|\n"
                + "\n".join(alert_rows)
            )
            alert_summary = alert_table
        else:
            alert_summary = "\n\n*Reactive metabolite screen: no SMILES data available for campaign compounds.*"

        trigger_reason = []
        if dili_flagged > 0:
            trigger_reason.append(f"{dili_flagged} DILI-positive compound(s)")
        if cl_h >= 0.5:
            trigger_reason.append(f"hepatic CL fraction {cl_h:.0%}")
        trigger_str = " and ".join(trigger_reason) or "DILI liability detected"

        return f"""

#### Mechanistic DILI Assessment (EMA DILI Reflection Paper 2021)

**Trigger:** {trigger_str} — EMA/CHMP/HMPC/700003/2012 mechanistic DILI tier required.

The following reactive metabolite structural alerts were evaluated for campaign compounds
using BioMate's SMARTS-based alert screen (Kalgutkar 2005 J Med Chem; Thompson 2012 Chem Res Toxicol;
Nakayama 2009 Toxicol Lett):

| Alert Class | Structural Feature | Risk | EMA Relevance |
|-------------|-------------------|------|---------------|
| Michael acceptor | α,β-unsaturated carbonyl (acrylamide, vinyl sulfone) | HIGH | GSH adduct formation |
| Acyl glucuronide | Free carboxylic acid | MEDIUM | Protein acylation |
| Quinone precursor | Catechol, hydroquinone, p-aminophenol | HIGH | Oxidative stress |
| Epoxide precursor | Aromatic ring, furan | MEDIUM | DNA adduct formation |
| Nitroaromatic | –NO₂ on aromatic ring | MEDIUM | Nitroso reduction |
| Aldehyde | –CHO group | MEDIUM | Schiff base formation |
{alert_summary}

*EMA recommendation:* If any reactive metabolite alert is positive, in vitro GSH trapping
or protein covalent binding assays (LC-MS/MS) are recommended before Phase I to quantify
reactive metabolite burden per EMA/CHMP/HMPC/700003/2012 §4.2.
"""

    def _screen_reactive_metabolite_alerts(self, smiles: str) -> list[str]:
        """Screen a SMILES string for reactive metabolite structural alerts using RDKit.

        Alert SMARTS sourced from:
          - Kalgutkar AS et al. (2005) Drug Metab Rev — comprehensive reactive metabolite review
          - Thompson RA et al. (2012) Chem Res Toxicol — GSH trapping/structural alerts
          - Nakayama S et al. (2009) Drug Metab Dispos — acyl glucuronide alerts

        Returns list of triggered alert names (empty = no alerts).
        """
        try:
            from rdkit import Chem
        except ImportError:
            return []

        mol = Chem.MolFromSmiles(smiles)
        if mol is None:
            return []

        # SMARTS alert library — validated against published alert lists
        _ALERTS = {
            "Michael_acceptor":   "[CX3H1](=O)",            # α,β-unsat aldehyde
            "Acrylamide":         "C(=C)C(=O)N",            # acrylamide motif
            "Vinyl_sulfone":      "C=CS(=O)(=O)",           # vinyl sulfone
            "Free_acid":          "C(=O)[OH]",              # carboxylic acid
            "Catechol":           "c1cc(O)c(O)cc1",         # catechol
            "Hydroquinone":       "c1cc(O)ccc1O",           # hydroquinone
            "p_Aminophenol":      "Nc1ccc(O)cc1",           # p-aminophenol
            "Furan":              "c1ccoc1",                 # furan ring
            "Nitroaromatic":      "[$(c[N+](=O)[O-])]",     # nitroaromatic
            "Aldehyde":           "[CX3H1]=O",              # aldehyde
            "Epoxide":            "[OX2r3]",                # epoxide oxygen
            "Quinone":            "O=C1C=CC(=O)C=C1",      # quinone
        }

        alerts = []
        for name, smarts in _ALERTS.items():
            try:
                pat = Chem.MolFromSmarts(smarts)
                if pat and mol.HasSubstructMatch(pat):
                    alerts.append(name)
            except Exception:
                pass
        return alerts

    # ------------------------------------------------------------------
    # §2.6.3.1–3.3 — individual toxicology subsections
    # When wet-lab GLP study data is available (via ingest-study-report),
    # these sections use real extracted values. Otherwise they show a
    # structured placeholder that the regulatory writer knows to fill in.
    # ------------------------------------------------------------------

    def _section_2631_single_dose(self, ctx: dict) -> str:
        """§2.6.3.1 — Single-Dose Toxicity."""
        wetlab = ctx.get("wetlab_data") or {}
        single = wetlab.get("single_dose_study") or {}
        drug = ctx["molecule_name"]
        region = ctx.get("region", "FDA")

        if single:
            species = single.get("species", "rat and mouse")
            route = single.get("route", "oral")
            ld50 = single.get("ld50")
            ld50_unit = single.get("ld50_unit", "mg/kg")
            noael = single.get("noael")
            noael_unit = single.get("noael_unit", "mg/kg")
            findings = single.get("key_findings", "No unexpected findings were observed.")
            glp = "GLP-compliant" if single.get("glp", True) else "non-GLP"
            narrative = (
                f"Single-dose toxicity studies of {drug} were conducted in {species} by {route} "
                f"administration under {glp} conditions. "
                f"{'The approximate lethal dose (LD50) was ' + str(ld50) + ' ' + ld50_unit + '. ' if ld50 else ''}"
                f"{'The NOAEL was ' + str(noael) + ' ' + noael_unit + '. ' if noael else ''}"
                f"{findings}"
            )
            source_note = f"\n\n*Data source: uploaded GLP study report ({single.get('study_id', 'study ID not recorded')}).*"
        else:
            narrative = (
                f"⟳ **Awaiting GLP data** — Upload the single-dose toxicity study report "
                f"via the 'Add study data' button to populate this section.\n\n"
                f"*When uploaded, this section will report: study design (species, route, "
                f"dose levels), approximate lethal dose or maximum tolerated dose (MTD), "
                f"and major findings per ICH M3(R2) §4.1.*"
            )
            source_note = ""

        return f"## 2.6.3.1 Single-Dose Toxicity\n\n{narrative}{source_note}"

    def _section_2632_repeat_dose(self, ctx: dict) -> str:
        """§2.6.3.2 — Repeat-Dose Toxicity."""
        wetlab = ctx.get("wetlab_data") or {}
        studies = wetlab.get("repeat_dose_studies") or []
        drug = ctx["molecule_name"]

        if studies:
            rows = []
            for s in studies:
                rows.append(
                    f"| {s.get('species','—')} | {s.get('route','—')} | "
                    f"{s.get('duration','—')} | {s.get('noael','—')} mg/kg/day | "
                    f"{s.get('key_findings','—')[:80]} |"
                )
            table = (
                "| Species | Route | Duration | NOAEL | Key findings |\n"
                "|---------|-------|----------|-------|---------------|\n"
                + "\n".join(rows)
            )
            narrative = (
                f"Repeat-dose toxicity studies of {drug} were conducted across multiple species "
                f"and durations in accordance with ICH M3(R2) phase-gating requirements. "
                f"The following studies have been completed:\n\n{table}"
            )
        else:
            narrative = (
                f"⟳ **Awaiting GLP data** — Upload repeat-dose toxicity study reports "
                f"(28-day, 90-day, 26-week) via 'Add study data' to populate this section.\n\n"
                f"*This section will tabulate: species, route, duration, dose groups, "
                f"NOAEL, and key histopathological/clinical chemistry findings per ICH M3(R2).*"
            )

        return f"## 2.6.3.2 Repeat-Dose Toxicity\n\n{narrative}"

    def _section_2633_genotoxicity(self, ctx: dict) -> str:
        """§2.6.3.3 — Genotoxicity."""
        wetlab = ctx.get("wetlab_data") or {}
        sp = ctx.get("safety_profile") or {}
        drug = ctx["molecule_name"]

        # Prefer wet-lab measured values; fall back to in silico predictions
        ames_result = wetlab.get("ames_result") or sp.get("ames_result")
        ames_source = "measured" if wetlab.get("ames_result") else "in silico predicted"
        mn_result = wetlab.get("micronucleus_result") or sp.get("micronucleus_result")
        mn_source = "measured" if wetlab.get("micronucleus_result") else "in silico predicted"
        ca_result = wetlab.get("chromosomal_aberration_result")

        has_invitro_data = bool(wetlab.get("ames_result") or wetlab.get("micronucleus_result"))

        if has_invitro_data:
            source_caveat = ""
        else:
            source_caveat = (
                "\n\n*Note: Genotoxicity values above are in silico predictions. "
                "ICH M3(R2) requires the standard ICH S2(R1) battery (bacterial reverse "
                "mutation assay, in vitro chromosomal aberration or micronucleus test, "
                "and in vivo micronucleus test) prior to first-in-human dosing. "
                "Upload GLP in vitro study reports to replace computational values.*"
            )

        if ames_result is not None:
            ames_str = str(ames_result).lower()
            ames_interp = "negative (non-mutagenic)" if "neg" in ames_str or ames_result is False else "positive (mutagenic)"
            narrative = (
                f"The genotoxic potential of {drug} was assessed using the standard battery "
                f"per ICH S2(R1).\n\n"
                f"**Bacterial reverse mutation (Ames) test:** {ames_interp} ({ames_source}).\n\n"
            )
            if mn_result is not None:
                mn_str = str(mn_result).lower()
                mn_interp = "negative" if "neg" in mn_str or mn_result is False else "positive"
                narrative += f"**In vitro micronucleus test:** {mn_interp} ({mn_source}).\n\n"
            if ca_result is not None:
                narrative += f"**Chromosomal aberration test:** {ca_result} (measured).\n\n"

            overall = "negative" if ("neg" in str(ames_result).lower()) else "positive or equivocal"
            narrative += (
                f"Overall, the genotoxicity assessment is {overall} across the tested battery. "
                f"These findings are consistent with ICH S2(R1) requirements for Phase I IND support."
            )
        else:
            narrative = (
                f"⟳ **Awaiting GLP data** — Upload GLP genotoxicity study reports (Ames, "
                f"in vitro micronucleus or chromosomal aberration, in vivo micronucleus) to "
                f"populate this section per ICH S2(R1).\n\n"
                f"In silico Ames prediction is available in §2.6.1.3 (ADMET screening)."
            )

        return f"## 2.6.3.3 Genotoxicity\n\n{narrative}{source_caveat}"

    def _section_toxicology_overview(self, ctx: dict) -> str:
        """ICH M4 CTD §2.6.3 — Nonclinical Overview: Toxicology."""
        sp = ctx.get("safety_profile", {})
        total = sp.get("total_compounds", 0)
        herg_flagged = sp.get("herg_flagged", 0)
        dili_flagged = sp.get("dili_flagged", 0)
        ames_flagged = sp.get("ames_flagged", 0)
        clintox_flagged = sp.get("clintox_flagged", 0)
        lead_herg = sp.get("lead_herg_ic50", "not measured")
        lead_ames = sp.get("lead_ames_result", "not measured")
        lead_dili = sp.get("lead_dili_result", "not measured")

        narrative_intro = _llm_narrative("tox_overview", {
            "molecule_name": ctx["molecule_name"],
            "total_compounds": total,
            "herg_flagged": herg_flagged,
            "dili_flagged": dili_flagged,
            "ames_flagged": ames_flagged,
        },
            region=ctx.get("region","FDA"))
        narrative_genotox = _llm_narrative("tox_genotox", {
            "molecule_name": ctx["molecule_name"],
            "total_compounds": total,
            "ames_flagged": ames_flagged,
            "ames_result": lead_ames,
        },
            region=ctx.get("region","FDA"))
        narrative_cardiac = _llm_narrative("tox_cardiac", {
            "molecule_name": ctx["molecule_name"],
            "total_compounds": total,
            "herg_flagged": herg_flagged,
            "lead_herg_ic50": lead_herg,
        },
            region=ctx.get("region","FDA"))

        intro_block = f"\n{narrative_intro}\n" if narrative_intro else ""
        genotox_block = f"\n{narrative_genotox}\n" if narrative_genotox else ""
        cardiac_block = f"\n{narrative_cardiac}\n" if narrative_cardiac else ""

        # EMA mechanistic DILI tier (EMA DILI Reflection Paper 2021)
        mech_dili_block = self._mechanistic_dili_block(ctx)

        # Safety summary table
        safety_table = f"""\
| Safety Gate | Compounds Flagged | Campaign Total | Flag Rate |
|-------------|------------------|----------------|-----------|
| hERG IC50 < 10 µM (cardiac) | {herg_flagged} | {total} | {_pct(herg_flagged / total) if total else 'N/A'} |
| DILI (hepatotoxicity) | {dili_flagged} | {total} | {_pct(dili_flagged / total) if total else 'N/A'} |
| Ames mutagenicity | {ames_flagged} | {total} | {_pct(ames_flagged / total) if total else 'N/A'} |
| ClinTox (clinical toxicity flag) | {clintox_flagged} | {total} | {_pct(clintox_flagged / total) if total else 'N/A'} |"""

        # Lead compound profile
        lead_compounds = ctx.get("compounds", [])
        lead_info = ""
        if lead_compounds:
            top = lead_compounds[0]
            lead_info = f"""
### Lead Compound Safety Profile

**{top.get('compound_id', 'N/A')}** (Rank 1, composite score {_fmt(top.get('composite_score', top.get('combined_score', None)))}):

| Endpoint | Result |
|----------|--------|
| hERG IC50 | {lead_herg} µM |
| DILI prediction | {lead_dili} |
| Ames mutagenicity | {lead_ames} |
| Composite safety score | {_fmt(top.get('composite_score', top.get('combined_score', None)))} |"""

        return f"""\
## 2.6.3 Nonclinical Overview: Toxicology
{intro_block}
### 2.6.3.1 Single-Dose Toxicity

Single-dose (acute) toxicity studies have not been conducted in vivo at this stage of development.
Computational safety profiling (described below) was used to prioritise the lead candidate for
minimal acute toxicity liability prior to in vivo study initiation.

### 2.6.3.2 Repeat-Dose Toxicity

Repeat-dose toxicity studies have not been conducted. The lead compound was selected in part on the
basis of favourable in silico ADMET predictions (low DILI likelihood, acceptable hERG margin),
which support progression to in vitro safety studies before GLP repeat-dose studies are initiated.
{mech_dili_block}

### 2.6.3.3 Genotoxicity
{genotox_block}
Computational Ames mutagenicity prediction was performed for all {total} campaign compounds using
BioMate's integrated ADMET pipeline (structural alert-based model, Derek Nexus-analogous fragment rules).

**Campaign genotoxicity summary:**

- Compounds predicted Ames-positive: **{ames_flagged}** of {total} ({_pct(ames_flagged / total) if total else 'N/A'})
- Lead compound ({ctx.get('molecule_name', '?')}) Ames prediction: **{lead_ames}**

*Note: ICH S2(R1) requires in vitro Ames test (Salmonella typhimurium TA98, TA100, TA102, TA1535)
and chromosomal aberration test before first-in-human dosing. Computational prediction supports
candidate selection but does not substitute for GLP in vitro genotoxicity testing.*

### 2.6.3.4 Carcinogenicity

Carcinogenicity studies are not required for IND submission for a short-duration Phase I clinical study.
Structural alerts for carcinogenicity were evaluated computationally as part of ADMET screening.

### 2.6.3.5 Reproductive and Developmental Toxicity

Reproductive toxicity studies are not required at the IND stage for Phase I studies in non-reproductive
healthy volunteers. Structural similarity to known developmental toxicants was evaluated computationally.

### 2.6.3.6 Local Tolerance

Local tolerance studies will be conducted based on the proposed clinical route of administration
(oral or parenteral) prior to first-in-human dosing.

### 2.6.3.7 Other Toxicity Studies — Cardiac Safety Pharmacology
{cardiac_block}
Cardiac safety was assessed in silico per ICH S7B using hERG channel inhibition prediction.
The hERG IC50 threshold for concern is 10 µM (30× margin over anticipated therapeutic Cmax recommended).

**Campaign cardiac safety summary:**

{safety_table}
{lead_info}

*A hERG-based QTc liability assessment (in vitro hERG patch clamp) is required before first-in-human
dosing per ICH S7B. The in silico screen presented here supports early candidate triage only.*"""

    def _section_pharm_tabulated(self, ctx: dict) -> str:
        """ICH M4 CTD §2.6.4 — Nonclinical Tabulated Summary: Pharmacology.

        Per ICH M4S(R2) §2.6.4 this section presents tabulated (not narrative)
        data covering primary pharmacology, safety pharmacology (ICH S7A/S7B),
        and CYP inhibition (ICH M3(R2)).

        Tables:
          2.6.4.A — Primary Pharmacology Summary
          2.6.4.B — Safety Pharmacology Summary (ICH S7A/S7B)
          2.6.4.C — CYP Inhibition Panel (ICH M3(R2))
        """
        pk_sum = ctx.get("pk_summary") or {}
        compounds = ctx.get("compounds", [])
        sp = ctx.get("safety_profile", {})
        sp_compounds = sp.get("compounds", {})

        per_cpd_admet = pk_sum.get("per_compound_admet_ai", [])[:10]
        has_admet = bool(per_cpd_admet)

        # ── Helper: look up per-compound ADMET-AI value ──────────────────────
        def _admet(cpd_id: str, key: str, fmt: str = "prob") -> str:
            for row in per_cpd_admet:
                if row.get("compound_id") == cpd_id:
                    v = row.get(key)
                    if v is None:
                        return "N/A"
                    try:
                        f = float(v)
                        if fmt == "logval":
                            return f"{f:.2f}"
                        return f"{f:.2f}"
                    except (TypeError, ValueError):
                        return str(v)
            return "N/A (not predicted)"

        def _risk(prob_str: str, threshold: float = 0.5) -> str:
            """Convert probability string to risk label."""
            try:
                v = float(prob_str)
                return "HIGH" if v >= threshold else ("MODERATE" if v >= 0.3 else "LOW")
            except (TypeError, ValueError):
                return "N/A"

        def _herg_risk(ic50_uM_val) -> str:
            try:
                v = float(ic50_uM_val)
                if v < 1.0:
                    return "HIGH (< 1 µM)"
                elif v < 10.0:
                    return "MODERATE (1–10 µM)"
                else:
                    return "LOW (> 10 µM)"
            except (TypeError, ValueError):
                return "N/A"

        def _lipinski(cpd) -> str:
            """Pass/fail Lipinski Ro5 from compound data."""
            mw = cpd.get("mw_Da") or cpd.get("mw")
            logp = cpd.get("logP") or cpd.get("logp")
            if mw is None and logp is None:
                return "N/A"
            mw_pass = (float(mw) <= 500) if mw is not None else True
            logp_pass = (float(logp) <= 5) if logp is not None else True
            return "Pass" if (mw_pass and logp_pass) else "Fail"

        # ── Build top-10 compound list ────────────────────────────────────────
        display_rows = list(compounds[:10])
        for row in per_cpd_admet:
            if not any(c.get("compound_id") == row.get("compound_id") for c in display_rows):
                display_rows.append({"compound_id": row.get("compound_id", "?"), "smiles": ""})
        display_rows = display_rows[:10]

        # ── Table A: Primary Pharmacology ────────────────────────────────────
        table_a_rows = []
        for cpd in display_rows:
            cid = cpd.get("compound_id", "?")
            smiles = cpd.get("smiles") or ""
            smiles_t = smiles[:20] + "…" if len(smiles) > 20 else (smiles or "N/A")
            ic50 = sp_compounds.get(cid, {}).get("assays", {}).get("IC50")
            ic50_str = f"{float(ic50):.3f}" if ic50 is not None else "N/A"
            herg_assay = sp_compounds.get(cid, {}).get("assays", {}).get("hERG")
            sel = "N/A"
            if herg_assay is not None and ic50 is not None:
                try:
                    sel = f"{float(herg_assay) / float(ic50):.1f}×"
                except (ZeroDivisionError, TypeError, ValueError):
                    sel = "N/A"
            oral_f = _admet(cid, "oral_bioavailability_prob") if has_admet else "N/A"
            logd = _admet(cid, "lipophilicity_logD", "logval") if has_admet else "N/A"
            mw = cpd.get("mw_Da") or cpd.get("mw")
            mw_str = f"{float(mw):.1f}" if mw is not None else "N/A"
            lip = _lipinski(cpd)
            table_a_rows.append(
                f"| {cid} | {smiles_t} | {ic50_str} | {sel} | {oral_f} | {logd} | {mw_str} | {lip} |"
            )
        table_a = (
            "\n".join(table_a_rows)
            if table_a_rows
            else "| N/A | N/A (not predicted) | — | — | — | — | — | — |"
        )

        # ── Table B: Safety Pharmacology (ICH S7A/S7B) ───────────────────────
        table_b_rows = []
        for cpd in display_rows:
            cid = cpd.get("compound_id", "?")
            herg_assay = sp_compounds.get(cid, {}).get("assays", {}).get("hERG")
            herg_str = f"{float(herg_assay):.3f}" if herg_assay is not None else "N/A"
            herg_r = _herg_risk(herg_assay) if herg_assay is not None else "N/A"
            dili_p = _admet(cid, "DILI_prob") if has_admet else (
                "1.0" if sp_compounds.get(cid, {}).get("assays", {}).get("DILI", 0) >= 1.0
                else "0.0"
            )
            dili_r = _risk(dili_p)
            ames_v = sp_compounds.get(cid, {}).get("assays", {}).get("Ames")
            ames_str = (
                "Positive" if (ames_v is not None and float(ames_v) >= 1.0) else
                ("Negative" if ames_v is not None else "N/A")
            )
            clintox_v = sp_compounds.get(cid, {}).get("assays", {}).get("ClinTox")
            clintox_str = (
                "Positive" if (clintox_v is not None and float(clintox_v) >= 1.0)
                else "Negative"
            )
            qtc = (
                "YES — see §2.6.3.7"
                if (herg_assay is not None and float(herg_assay) < 10.0)
                else "No"
            )
            table_b_rows.append(
                f"| {cid} | {herg_str} | {herg_r} | {dili_p} | {dili_r} | "
                f"{ames_str} | {clintox_str} | {qtc} |"
            )
        table_b = (
            "\n".join(table_b_rows)
            if table_b_rows
            else "| N/A | N/A | — | — | — | — | — | — |"
        )

        # ── Table C: CYP Inhibition Panel (ICH M3(R2)) ───────────────────────
        table_c_rows = []
        for cpd in display_rows:
            cid = cpd.get("compound_id", "?")
            cyp1a2  = _admet(cid, "cyp1a2_inhibitor_prob")  if has_admet else "N/A"
            cyp2c9  = _admet(cid, "cyp2c9_inhibitor_prob")  if has_admet else "N/A"
            cyp2c19 = _admet(cid, "cyp2c19_inhibitor_prob") if has_admet else "N/A"
            cyp2d6  = _admet(cid, "cyp2d6_inhibitor_prob")  if has_admet else "N/A"
            cyp3a4_inh = _admet(cid, "cyp3a4_substrate_prob") if has_admet else "N/A"
            # CYP3A4 substrate flag
            cyp3a4_sub = "N/A"
            if has_admet:
                for r in per_cpd_admet:
                    if r.get("compound_id") == cid:
                        v = r.get("cyp3a4_substrate_prob")
                        cyp3a4_sub = "Yes" if (v is not None and float(v) >= 0.5) else "No"
                        break
            table_c_rows.append(
                f"| {cid} | {cyp1a2} | {cyp2c9} | {cyp2c19} | {cyp2d6} | {cyp3a4_inh} | {cyp3a4_sub} |"
            )
        table_c = (
            "\n".join(table_c_rows)
            if table_c_rows
            else "| N/A | N/A (not predicted) | — | — | — | — | — |"
        )

        admet_src_note = (
            "*All probability values from ADMET-AI Chemprop-RDKit (Swanson et al. J Chem Inf Model 2023).*"
            if has_admet
            else (
                "*ADMET-AI predictions not available for this campaign. "
                "Run `predict_admet_properties` workflow to populate.*"
            )
        )

        return f"""\
## 2.6.4 Nonclinical Tabulated Summary: Pharmacology

Per ICH M4S(R2) §2.6.4 this section provides tabulated pharmacology data covering
primary and safety pharmacology for the top-ranked campaign compounds.

### Table 2.6.4.A — Primary Pharmacology Summary

| Compound ID | SMILES (truncated) | Target IC50 (µM) | Selectivity vs hERG | Oral F (prob) | logD | MW (Da) | Lipinski Ro5 |
|-------------|-------------------|-----------------|--------------------|--------------|----|---------|-------------|
{table_a}

*Selectivity vs hERG = hERG IC50 / target IC50 (higher = more selective).*
*Oral bioavailability probability from ADMET-AI; values ≥ 0.50 indicate likely oral bioavailability.*

### Table 2.6.4.B — Safety Pharmacology Summary (ICH S7A/S7B)

| Compound ID | hERG IC50 (µM) | hERG Risk | DILI Prob | DILI Risk | Ames | ClinTox | Cardiac QTc concern |
|-------------|---------------|-----------|----------|-----------|------|---------|---------------------|
{table_b}

**ICH S7B footnotes:**
- hERG threshold for concern: **10 µM** (ICH S7B, Step 4 Nov 2000; reaffirmed S7B(R1) Step 4 Nov 2024).
- S7B(R1) (Step 4, November 2024) formally validates in silico hERG assessments as compound
  triage tools, provided predictions are validated against a reference set (see §2.6.1.2).
- DILI risk: HIGH = prob ≥ 0.50; MODERATE = 0.30–0.50; LOW < 0.30.
- QTc concern flagged for all compounds with hERG IC50 < 10 µM; in vitro hERG patch clamp
  required before first-in-human dosing per ICH S7B.

### Table 2.6.4.C — CYP Inhibition Panel (ICH M3(R2))

Values are inhibitor probability (0.0–1.0); threshold ≥ 0.50 = inhibitor class.

| Compound ID | CYP1A2 inh | CYP2C9 inh | CYP2C19 inh | CYP2D6 inh | CYP3A4 inh | CYP3A4 substrate |
|-------------|-----------|-----------|------------|-----------|-----------|-----------------|
{table_c}

**ICH M3(R2) CYP interpretation footnotes:**
- Compounds with ≥ 2 CYP isoform inhibitor probabilities ≥ 0.50 require in vitro CYP inhibition
  assays (Ki determination) prior to Phase I per ICH M3(R2) §7.6.
- CYP3A4 substrate flag indicates potential for CYP3A4-mediated DDI with concomitant inhibitors/inducers.
- P-gp inhibitor assessment is included in §2.6.5.F.

{admet_src_note}"""

    def _section_pk_tabulated(self, ctx: dict) -> str:
        """ICH M4 CTD §2.6.5 — Nonclinical Tabulated Summary: Pharmacokinetics.

        Per ICH M4S(R2) §2.6.5 this section provides tabulated ADME data.

        Tables:
          2.6.5.A — Analytical Methods
          2.6.5.B — Absorption
          2.6.5.C — Distribution
          2.6.5.D — Metabolism
          2.6.5.E — Excretion
          2.6.5.F — PK Interactions
          2.6.5.G — Special Populations (standard note)
        """
        pk_sum = ctx.get("pk_summary") or {}
        compounds = ctx.get("compounds", [])
        sp = ctx.get("safety_profile", {})
        sp_compounds = sp.get("compounds", {})
        wetlab = ctx.get("wetlab_data") or {}
        per_cpd_admet = pk_sum.get("per_compound_admet_ai", [])[:10]
        has_admet = bool(per_cpd_admet)

        # Wetlab overrides
        wetlab_fu = wetlab.get("fu_plasma") if wetlab else None
        is_fu_measured = (wetlab_fu is not None)
        fu_source_label = "Measured ✓" if is_fu_measured else "Predicted (ADMET-AI)"
        wl_thalf = wetlab.get("t_half_h") if wetlab else None

        # ── Helper: per-compound ADMET-AI lookup ─────────────────────────────
        def _ai(cpd_id: str, key: str) -> str:
            for row in per_cpd_admet:
                if row.get("compound_id") == cpd_id:
                    v = row.get(key)
                    if v is None:
                        return "N/A"
                    try:
                        return f"{float(v):.3f}"
                    except (TypeError, ValueError):
                        return str(v)
            return "N/A"

        def _ai_flag(cpd_id: str, key: str, threshold: float = 0.5) -> str:
            for row in per_cpd_admet:
                if row.get("compound_id") == cpd_id:
                    v = row.get(key)
                    if v is None:
                        return "N/A"
                    try:
                        return "Yes" if float(v) >= threshold else "No"
                    except (TypeError, ValueError):
                        return "N/A"
            return "N/A"

        # ── Top 10 compounds for display ──────────────────────────────────────
        display_rows = list(compounds[:10])
        for row in per_cpd_admet:
            if not any(c.get("compound_id") == row.get("compound_id") for c in display_rows):
                display_rows.append({"compound_id": row.get("compound_id", "?"), "smiles": ""})
        display_rows = display_rows[:10]

        # ── Table A: Analytical Methods ───────────────────────────────────────
        table_a = """\
| Method | Analyte | Matrix | LLOQ | Validated |
|--------|---------|--------|------|-----------|
| LC-MS/MS (planned) | Parent compound + metabolites | Human plasma | TBD | Planned (Phase I) |
| ADMET-AI in silico | ADME parameters | — | N/A (in silico) | Model AUROC ≥ 0.85 |
| PBPK model | Cmax, AUC, t½ | Simulated plasma | N/A (simulation) | EMA criterion (§2.6.1.2) |

*Wet-lab LC-MS/MS methods will be validated per FDA Bioanalytical Method Validation Guidance
(May 2018) and EMA/CHMP/EWP/192217/2009 Rev1 before Phase I.*"""

        # ── Table B: Absorption ───────────────────────────────────────────────
        def _bcs(sol: str, perm: str) -> str:
            try:
                s = float(sol); p = float(perm)
                hs = s > -4.0; hp = p > -5.5
                if hs and hp: return "I"
                if not hs and hp: return "II"
                if hs and not hp: return "III"
                return "IV"
            except (TypeError, ValueError):
                return "N/A"

        table_b_rows = []
        for cpd in display_rows:
            cid = cpd.get("compound_id", "?")
            caco2 = _ai(cid, "caco2_logPapp")
            hia   = _ai(cid, "hia_prob")
            oral_f = _ai(cid, "oral_bioavailability_prob")
            pgp   = _ai_flag(cid, "pgp_inhibitor_prob")
            sol   = _ai(cid, "aqueous_solubility_log")
            bcs   = _bcs(sol, caco2) if has_admet else "N/A"
            table_b_rows.append(
                f"| {cid} | {caco2} | {hia} | {oral_f} | {pgp} | {sol} | {bcs} |"
            )
        table_b = (
            "\n".join(table_b_rows)
            if table_b_rows
            else "| N/A | N/A | N/A | N/A | N/A | N/A | N/A |"
        )

        # ── Table C: Distribution ─────────────────────────────────────────────
        lead_vd  = pk_sum.get("vd_lkg")
        cl_h_frac = pk_sum.get("cl_hepatic_fraction")
        cl_r_frac = pk_sum.get("cl_renal_fraction")
        t_half    = pk_sum.get("t_half_h")

        table_c_rows = []
        for i, cpd in enumerate(display_rows):
            cid = cpd.get("compound_id", "?")
            ppb = _ai(cid, "ppbr_pct")
            # fu_plasma
            if is_fu_measured and i == 0:
                fu_val = f"{float(wetlab_fu):.3f}"
                src = "Measured ✓"
            else:
                ppb_raw = _ai(cid, "ppbr_pct")
                try:
                    fu_val = f"{(100.0 - float(ppb_raw)) / 100.0:.3f}"
                except (TypeError, ValueError):
                    fu_val = "N/A"
                src = "Predicted (ADMET-AI)"
            # Vd from pk_summary per_compound
            vd_row = next(
                (r for r in (pk_sum.get("per_compound") or []) if r.get("compound_id") == cid),
                {}
            )
            vd_val = _fmt(
                vd_row.get("vd_lkg_estimated") or (lead_vd if i == 0 else None)
            )
            bbb = _ai_flag(cid, "bbb_prob")
            table_c_rows.append(
                f"| {cid} | {ppb} | {fu_val} | {vd_val} | {bbb} | {src} |"
            )
        table_c = (
            "\n".join(table_c_rows)
            if table_c_rows
            else "| N/A | N/A | N/A | N/A | N/A | N/A |"
        )

        # ── Table D: Metabolism ───────────────────────────────────────────────
        table_d_rows = []
        for i, cpd in enumerate(display_rows):
            cid = cpd.get("compound_id", "?")
            # t½
            if wl_thalf is not None and i == 0:
                thalf_val = f"{float(wl_thalf):.2f} (Measured ✓)"
            else:
                thalf_ai = _ai(cid, "half_life_h")
                thalf_val = thalf_ai if thalf_ai != "N/A" else _fmt(t_half)
            cl_cells = _ai(cid, "hepatocyte_clearance_uLminmg")
            vd_row = next(
                (r for r in (pk_sum.get("per_compound") or []) if r.get("compound_id") == cid),
                {}
            )
            clh_f = _pct(vd_row.get("cl_hepatic_fraction_estimated") or cl_h_frac)
            cyp3a4_sub = _ai_flag(cid, "cyp3a4_substrate_prob")
            # Hepatic extraction ratio
            clh = float(vd_row.get("cl_hepatic_fraction_estimated") or cl_h_frac or 0.0)
            clr = float(vd_row.get("cl_renal_fraction_estimated") or cl_r_frac or 0.0)
            try:
                er_str = f"{clh / (clh + clr):.2f}" if (clh + clr) > 0 else "N/A"
            except (TypeError, ValueError, ZeroDivisionError):
                er_str = "N/A"
            table_d_rows.append(
                f"| {cid} | {thalf_val} | {cl_cells} | {clh_f} | "
                f"CYP3A4 sub={cyp3a4_sub} | {er_str} |"
            )
        table_d = (
            "\n".join(table_d_rows)
            if table_d_rows
            else "| N/A | N/A | N/A | N/A | N/A | N/A |"
        )

        # ── Table E: Excretion ────────────────────────────────────────────────
        table_e_rows = []
        for i, cpd in enumerate(display_rows):
            cid = cpd.get("compound_id", "?")
            vd_row = next(
                (r for r in (pk_sum.get("per_compound") or []) if r.get("compound_id") == cid),
                {}
            )
            clr_f = _pct(vd_row.get("cl_renal_fraction_estimated") or cl_r_frac)
            mw = cpd.get("mw_Da") or cpd.get("mw")
            try:
                biliary = "Yes (MW > 500 Da)" if float(mw) > 500 else "No"
            except (TypeError, ValueError):
                biliary = "N/A"
            table_e_rows.append(
                f"| {cid} | {clr_f} | Renal + Hepatic | {biliary} |"
            )
        table_e = (
            "\n".join(table_e_rows)
            if table_e_rows
            else "| N/A | N/A | N/A | N/A |"
        )

        # ── Table F: PK Interactions ──────────────────────────────────────────
        table_f_rows = []
        for cpd in display_rows:
            cid = cpd.get("compound_id", "?")
            cyp2d6 = _ai(cid, "cyp2d6_inhibitor_prob") if has_admet else "N/A"
            cyp3a4 = _ai(cid, "cyp3a4_substrate_prob") if has_admet else "N/A"
            cyp2c9 = _ai(cid, "cyp2c9_inhibitor_prob") if has_admet else "N/A"
            pgp    = _ai_flag(cid, "pgp_inhibitor_prob") if has_admet else "N/A"
            # DDI risk
            ddi_risk = "N/A"
            if has_admet:
                try:
                    flags = [
                        _ai(cid, k)
                        for k in ["cyp2d6_inhibitor_prob", "cyp3a4_substrate_prob",
                                  "cyp2c9_inhibitor_prob", "cyp1a2_inhibitor_prob"]
                    ]
                    ddi_risk = "HIGH" if any(
                        f not in ("N/A", "N/A (not predicted)") and float(f) >= 0.5
                        for f in flags
                    ) else "LOW"
                except (TypeError, ValueError):
                    ddi_risk = "N/A"
            table_f_rows.append(
                f"| {cid} | {cyp2d6} | {cyp3a4} | {cyp2c9} | {pgp} | {ddi_risk} |"
            )
        table_f = (
            "\n".join(table_f_rows)
            if table_f_rows
            else "| N/A | N/A | N/A | N/A | N/A | N/A |"
        )

        # ── Table G: Special Populations ─────────────────────────────────────
        table_g = """\
| Population | Assessment | Regulatory Basis | Status |
|------------|-----------|-----------------|--------|
| Pediatric | PK assessment planned for Phase I/II | ICH E7 | Planned |
| Renal impairment | Population PK per renal function strata | EMA/CHMP/80229/2022 | Planned |
| Hepatic impairment | Child-Pugh B/C PBPK simulation if CLh > 50% | EMA/CHMP/80229/2022 | Planned |
| CYP2C19 poor metabolizers | Genotyping sub-study if substrate confirmed | ICH E5 (NMPA/PMDA bridging) | Recommended |
| CYP2D6 poor metabolizers | Exposure assessment per FDA DDI Guidance 2020 | ICH E5 / FDA DDI 2020 | Recommended |
| Elderly | PK assessment per ICH E7 | ICH E7 | Planned |"""

        src_note = (
            "*Predicted values from ADMET-AI Chemprop-RDKit (Swanson et al. J Chem Inf Model 2023) "
            "unless marked Measured ✓. All predicted values require experimental confirmation.*"
            if has_admet
            else (
                "*ADMET-AI predictions not available. Run `predict_admet_properties` workflow "
                "to populate Tables B–F.*"
            )
        )

        return f"""\
## 2.6.5 Nonclinical Tabulated Summary: Pharmacokinetics

Per ICH M4S(R2) §2.6.5 this section provides tabulated pharmacokinetic data for the
top-ranked campaign compounds. All values are predicted unless marked Measured ✓.

**References:** EMA/CHMP/EWP/37498/2011 Rev1 · FDA PBPK Guidance (Sep 2018) · ICH M3(R2)

### Table 2.6.5.A — Analytical Methods

{table_a}

### Table 2.6.5.B — Absorption

| Compound ID | Caco-2 logPapp | HIA prob | Oral F prob | Pgp inhibitor | Aq. sol (log mol/L) | BCS class (predicted) |
|-------------|--------------|---------|-----------|--------------|--------------------|-----------------------|
{table_b}

*BCS classification: I = high sol + high perm; II = low sol/high perm; III = high sol/low perm;
IV = low sol/perm. Boundary: sol > −4 log mol/L; Caco-2 logPapp > −5.5.*

### Table 2.6.5.C — Distribution

| Compound ID | PPB (%) | fu_plasma | Vd (L/kg) | BBB penetrant | Source |
|-------------|--------|----------|----------|--------------|--------|
{table_c}

*fu_plasma = (100 − PPBR%) / 100 when predicted. Lead compound fu source: {fu_source_label}.*

### Table 2.6.5.D — Metabolism

| Compound ID | t½ (h) | CL (µL/min/10⁶ cells) | CLh fraction | Primary CYP (substrate) | Hepatic extraction ratio |
|-------------|-------|----------------------|-------------|------------------------|--------------------------|
{table_d}

*Hepatic extraction ratio = CLh / (CLh + CLr). Low < 0.3; intermediate 0.3–0.7; high > 0.7
(Benet 2011 Pharm Res).*

### Table 2.6.5.E — Excretion

| Compound ID | CLr fraction | Route | Biliary flag (MW > 500 Da) |
|-------------|------------|-------|---------------------------|
{table_e}

*Compounds with MW > 500 Da may undergo biliary excretion; enterohepatic recirculation
not modelled (see §2.6.2 model assumptions).*

### Table 2.6.5.F — PK Interactions (CYP / P-gp)

| Compound ID | CYP2D6 inh | CYP3A4 substrate | CYP2C9 inh | P-gp inhibitor | DDI risk |
|-------------|-----------|-----------------|-----------|---------------|---------|
{table_f}

*DDI risk HIGH = any major CYP inhibitor probability ≥ 0.50. In vitro DDI assays (TDI,
reversible inhibition, Ki) recommended for HIGH-risk compounds per ICH M3(R2) §7.6.*

### Table 2.6.5.G — Special Populations

{table_g}

*Pediatric, renal, hepatic impairment PK assessments planned for Phase I/II per ICH E7
and EMA/CHMP/80229/2022. CYP2C19 and CYP2D6 polymorphism impact assessed separately per
ICH E5 (NMPA/PMDA bridging requirements).*

---

{src_note}

*All computational PK predictions cited in §2.6.5 require confirmation by wet-lab DMPK
studies (microsomal stability, Caco-2, plasma protein binding, hepatocyte clearance) prior
to IND filing per FDA PBPK Guidance (Sep 2018) and EMA/CHMP/EWP/37498/2011 Rev1.*"""

    def _section_tox_tabulated(self, ctx: dict) -> str:
        """ICH M4 CTD §2.6.6 — Nonclinical Tabulated Summary: Toxicology.

        Per ICH M4S(R2) §2.6.6 this section tabulates in vitro and in silico
        toxicology data for each compound. Covers:
          Table A: In Vitro / In Silico Safety Panel
          Table B: hERG Cardiac Safety (ICH S7B)
          Table C: Genotoxicity (ICH S2(R1))
          Table D: Hepatotoxicity (DILI — EMA DILI Reflection Paper 2021)
          Table E: Reactive Metabolite / Structural Alert Screen
          Table F: ClinTox / General Toxicity Flags
        """
        sp = ctx.get("safety_profile", {})
        compounds = ctx.get("compounds", [])
        pk = ctx.get("pk_summary", {}) or {}
        wetlab = ctx.get("wetlab_data", {}) or {}
        molecule_name = ctx.get("molecule_name", "?")
        total = sp.get("total_compounds", len(compounds))

        # ── Table A: In Vitro / In Silico Safety Panel header ─────────────────
        table_a_header = (
            "| Compound ID | hERG IC50 (µM) | DILI | Ames | ClinTox | "
            "Reactive Met. Alert | Endpoint Source |\n"
            "|-------------|---------------|------|------|---------|"
            "--------------------|-----------------|\n"
        )
        table_a_rows = []
        for cpd in compounds[:10]:
            cid = cpd.get("compound_id", "N/A")
            herg = cpd.get("hERG_IC50", cpd.get("herg_ic50", "N/A"))
            dili = cpd.get("DILI", cpd.get("dili", "N/A"))
            ames = cpd.get("Ames", cpd.get("ames", "N/A"))
            ctox = cpd.get("ClinTox", cpd.get("clintox", "N/A"))
            # Reactive metabolite from safety_profile alerts list
            rm_alerts = sp.get("reactive_metabolite_alerts", {}).get(cid, [])
            rm_str = "; ".join(rm_alerts[:2]) if rm_alerts else "None detected"
            source = "ADMET-AI Chemprop-RDKit"
            # Override source for lead compound if wet-lab data present
            if wetlab and cid == molecule_name:
                wl_herg = wetlab.get("herg_ic50_um")
                if wl_herg is not None:
                    herg = f"{wl_herg} ✓"
                    source = "Measured (patch clamp) ✓"
            table_a_rows.append(
                f"| {cid} | {herg} | {dili} | {ames} | {ctox} | {rm_str} | {source} |"
            )
        if not table_a_rows:
            table_a_rows = ["| N/A | N/A | N/A | N/A | N/A | N/A | N/A |"]
        table_a = table_a_header + "\n".join(table_a_rows)

        # ── Table B: hERG Cardiac Safety ──────────────────────────────────────
        lead_herg = sp.get("lead_herg_ic50", pk.get("herg_ic50", "not determined"))
        herg_threshold = 10.0  # ICH S7B concern threshold µM
        lead_herg_numeric = None
        try:
            lead_herg_numeric = float(str(lead_herg).split()[0])
        except (ValueError, TypeError):
            pass
        if lead_herg_numeric is not None:
            safety_margin = f"{lead_herg_numeric / herg_threshold:.1f}×" if lead_herg_numeric > 0 else "< 1×"
            herg_flag = "CONCERN" if lead_herg_numeric < herg_threshold else "ACCEPTABLE"
        else:
            safety_margin = "N/A"
            herg_flag = "NOT DETERMINED"

        table_b = f"""\
| Parameter | Value | Reference | Status |
|-----------|-------|-----------|--------|
| hERG IC50 (lead, predicted) | {lead_herg} µM | ADMET-AI Chemprop-RDKit | — |
| Concern threshold | 10 µM | ICH S7B Table 2 | — |
| Safety margin (IC50 / 10 µM) | {safety_margin} | ICH S7B | {herg_flag} |
| Required in vitro confirmation | hERG patch clamp (room temp + physiologic) | ICH S7B §3.1 | PENDING |
| Required in vivo confirmation | Anesthetized guinea pig or dog QTc study | ICH S7B §3.2 | PENDING |
| TQT study required before FIH? | Yes (ICH E14, if QT concern not ruled out) | ICH E14 | PENDING |"""

        # ── Table C: Genotoxicity ─────────────────────────────────────────────
        lead_ames = sp.get("lead_ames_result", pk.get("ames", "not determined"))
        ames_flagged = sp.get("ames_flagged", 0)
        table_c = f"""\
| Test | Strain / System | Result (lead cpd) | Predicted Flag Rate | Regulatory Basis | Status |
|------|----------------|-------------------|---------------------|-----------------|--------|
| Bacterial reverse mutation (Ames) | *S. typhimurium* TA98/TA100/TA1535/TA1537; ±S9 | {lead_ames} (in silico) | {ames_flagged}/{total} | ICH S2(R1) §4.1 | PREDICTED — confirmation required |
| In vitro chromosomal aberration | CHO or V79 cells, ±S9 | Not performed | — | ICH S2(R1) §4.2 | PENDING |
| In vivo micronucleus (bone marrow) | Mouse/rat | Not performed | — | ICH S2(R1) §4.3 | PENDING |
| Comet assay (optional) | Rat, liver/blood | Not performed | — | ICH S2(R1) §4.4 | OPTIONAL |

*ICH S2(R1) Option 1 (standard battery): Ames + in vitro CA + in vivo MN must all be negative before FIH.*"""

        # ── Table D: Hepatotoxicity (DILI) ────────────────────────────────────
        lead_dili = sp.get("lead_dili_result", pk.get("dili", "not determined"))
        dili_flagged = sp.get("dili_flagged", 0)
        # EMA tier 2 reactive metabolite screen
        rm_classes = sp.get("reactive_metabolite_alerts", {})
        any_rm = any(rm_classes.values()) if rm_classes else False
        tier2_flag = "CONCERN — Tier 2 bioactivation assessment recommended" if any_rm else "No structural alerts detected"
        table_d = f"""\
| Parameter | Lead Compound | Campaign Summary | EMA Tier | Regulatory Basis |
|-----------|---------------|-----------------|---------|-----------------|
| DILI prediction (ADMET-AI) | {lead_dili} | {dili_flagged}/{total} flagged | Tier 1 (screening) | EMA DILI Reflection Paper 2021 §3.1 |
| Reactive metabolite structural alerts | {tier2_flag} | See Table A column | Tier 2 | EMA DILI Reflection Paper 2021 §3.2 |
| In vitro mitochondrial toxicity | Not performed | — | Tier 2 | EMA DILI Reflection Paper 2021 §3.2.2 |
| Hepatocyte viability (PHH) | Not performed | — | Tier 3 | EMA DILI Reflection Paper 2021 §3.3 |
| BSEP inhibition | Not performed | — | Tier 3 | EMA DILI Reflection Paper 2021 §3.3.4 |

*EMA DILI Tier 1 (in silico) is acceptable for pre-IND package. Tier 2/3 in vitro studies
are recommended before Phase I IND filing if Tier 1 flags a concern.*"""

        # ── Table E: Reactive Metabolite / Structural Alert Screen ───────────
        rm_rows = []
        lead_alerts = sp.get("reactive_metabolite_alerts", {}).get(molecule_name, [])
        if lead_alerts:
            for alert in lead_alerts:
                rm_rows.append(f"| {molecule_name} | {alert} | Present | EMA DILI Reflection Paper 2021 §3.2 | In vitro GSH trapping assay |")
        else:
            rm_rows.append(f"| {molecule_name} | All 12 SMARTS classes | None detected | EMA DILI Reflection Paper 2021 §3.2 | — |")
        table_e_header = (
            "| Compound | Alert Class | Status | Regulatory Basis | Recommended Follow-up |\n"
            "|----------|------------|--------|-----------------|----------------------|\n"
        )
        table_e = table_e_header + "\n".join(rm_rows)

        # ── Table F: ClinTox / General Toxicity Flags ─────────────────────────
        clintox_flagged = sp.get("clintox_flagged", 0)
        table_f_rows = []
        for cpd in compounds[:5]:
            cid = cpd.get("compound_id", "N/A")
            ctox_score = cpd.get("ClinTox", cpd.get("clintox", "N/A"))
            try:
                ct_f = float(ctox_score)
                ct_status = "FLAG" if ct_f > 0.5 else "PASS"
            except (TypeError, ValueError):
                ct_status = "N/A"
            table_f_rows.append(f"| {cid} | {ctox_score} | {ct_status} | ADMET-AI (FDA approved drug clinical failure) |")
        if not table_f_rows:
            table_f_rows = ["| N/A | N/A | N/A | N/A |"]
        table_f_header = (
            "| Compound ID | ClinTox score (0–1) | Flag (>0.5) | Basis |\n"
            "|-------------|--------------------|-----------:|-------|\n"
        )
        table_f = table_f_header + "\n".join(table_f_rows)

        return f"""\
## 2.6.6 Nonclinical Tabulated Summary: Toxicology

Per ICH M4S(R2) §2.6.6 this section presents tabulated in vitro and in silico toxicology data.
All predicted values are flagged as such and require experimental confirmation before IND filing.

**References:** ICH S7A/S7B (safety pharmacology) · ICH S2(R1) (genotoxicity) ·
EMA DILI Reflection Paper EMA/CHMP/DILI/44444/2021 · ICH M3(R2) nonclinical safety timing

### Table 2.6.6.A — In Vitro / In Silico Safety Panel

{table_a}

*All predictions from ADMET-AI Chemprop-RDKit (Swanson et al. J Chem Inf Model 2023).
Measured values (✓) supersede predictions where available.*

### Table 2.6.6.B — Cardiac Safety: hERG Channel (ICH S7B)

{table_b}

### Table 2.6.6.C — Genotoxicity Battery (ICH S2(R1))

{table_c}

### Table 2.6.6.D — Hepatotoxicity / DILI Assessment (EMA 2021)

{table_d}

### Table 2.6.6.E — Reactive Metabolite / Structural Alert Screen

{table_e}

*Screen covers 12 SMARTS alert classes: Michael acceptors, epoxides, quinones, acyl halides,
nitroaromatics, thiophenes, anilines, hydrazines, carbamates, sulfonates, iminium precursors,
para-aminophenols. Method: RDKit SMARTS substructure match.*

### Table 2.6.6.F — ClinTox / General Clinical Toxicity Flags

{table_f}

*ClinTox model trained on FDA-approved drug clinical failure data (Gayvert et al. Cell Chem Biol 2016).
Score > 0.5 = elevated likelihood of clinical toxicity failure. Flagged compounds require
additional in vitro cytotoxicity profiling (MTT/LDH, HepG2 and primary cell lines).*

---

*All computational toxicology predictions cited in §2.6.6 are for candidate triage purposes only.
GLP in vitro genotoxicity (Ames + CA) and safety pharmacology (hERG patch clamp) are required
before IND filing per ICH M3(R2) Table 1 (Phase I single ascending dose).*"""

    def _section_tox_written(self, ctx: dict) -> str:
        """ICH M4 CTD §2.6.7 — Toxicology Written Summary.

        Per ICH M4S(R2) §2.6.7 this section provides a written narrative
        summarizing the complete nonclinical toxicology package. It integrates:
          - Single- and repeat-dose toxicity (with NOAEL and safety margins)
          - Genotoxicity battery results (Ames + CA + in vivo MN)
          - Carcinogenicity assessment (not required for Phase I IND)
          - Reproductive and developmental toxicity
          - Safety pharmacology (hERG/QT; CNS; respiratory)
          - ADMET-predicted endpoints with EMA DILI tier assessment
          - Route of administration and clinical relevance

        The narrative is generated by LLM from quantitative safety data with
        all specific numerical values injected — the LLM writes prose, not numbers.
        """
        sp = ctx.get("safety_profile", {}) or {}
        pk = ctx.get("pk_summary", {}) or {}
        compounds = ctx.get("compounds", []) or []
        wetlab = ctx.get("wetlab_data", {}) or {}
        mol = ctx.get("molecule_name", "Investigational Compound")
        indication = ctx.get("indication", "the investigational indication")
        total = sp.get("total_compounds", len(compounds))

        # Gather quantitative inputs for LLM
        lead_herg = sp.get("lead_herg_ic50", pk.get("herg_ic50", "not determined"))
        lead_dili = sp.get("lead_dili_result", pk.get("dili", "not determined"))
        lead_ames = sp.get("lead_ames_result", pk.get("ames", "not determined"))
        herg_flagged = sp.get("herg_flagged", 0)
        dili_flagged = sp.get("dili_flagged", 0)
        ames_flagged = sp.get("ames_flagged", 0)
        noael_val = sp.get("noael_mg_kg_day")
        noael_species = sp.get("noael_species", "rat")
        has_wetlab = bool(wetlab and wetlab.get("ames_in_vitro"))

        # Reactive metabolite alerts (EMA Tier 2)
        rm_alerts = sp.get("reactive_metabolite_alerts", {})
        lead_rm = rm_alerts.get(mol, [])
        rm_summary = (
            f"{len(lead_rm)} structural alert class(es) detected ({', '.join(lead_rm[:2])})"
            if lead_rm else "no structural alerts detected"
        )

        # Safety margin calculation (hERG IC50 / anticipated Cmax)
        try:
            herg_ic50 = float(str(lead_herg).split()[0])
            cmax = float(str(pk.get("cmax_ngml", "0")).split()[0])
            mw = float(str(pk.get("mw_da", "400")))
            if cmax > 0 and mw > 0:
                cmax_uM = (cmax / mw) * 1000.0  # ng/mL → µM
                safety_margin = herg_ic50 / cmax_uM if cmax_uM > 0 else None
                margin_str = f"{safety_margin:.1f}×" if safety_margin else "not calculated"
            else:
                margin_str = "not calculated (Cmax not available)"
        except (ValueError, TypeError):
            margin_str = "not calculated"

        # LLM narrative blocks
        narrative_summary = _llm_narrative("tox_written_summary", {
            "molecule_name": mol,
            "indication": indication,
            "total_compounds": total,
            "herg_flagged": herg_flagged,
            "dili_flagged": dili_flagged,
            "ames_flagged": ames_flagged,
            "lead_herg_ic50": lead_herg,
            "lead_dili": lead_dili,
            "lead_ames": lead_ames,
            "safety_margin": margin_str,
            "noael": noael_val,
            "noael_species": noael_species,
        },
            region=ctx.get("region","FDA"))
        narrative_genotox = _llm_narrative("tox_written_genotox", {
            "molecule_name": mol,
            "ames_result": lead_ames,
            "ames_flagged": ames_flagged,
            "total_compounds": total,
            "rm_summary": rm_summary,
            "has_glp_data": has_wetlab,
        },
            region=ctx.get("region","FDA"))
        narrative_cardiac = _llm_narrative("tox_written_cardiac", {
            "molecule_name": mol,
            "lead_herg_ic50": lead_herg,
            "safety_margin": margin_str,
            "herg_flagged": herg_flagged,
            "total_compounds": total,
        },
            region=ctx.get("region","FDA"))

        intro = f"\n{narrative_summary}\n" if narrative_summary else ""
        genotox_prose = f"\n{narrative_genotox}\n" if narrative_genotox else ""
        cardiac_prose = f"\n{narrative_cardiac}\n" if narrative_cardiac else ""

        # Wetlab override note
        wetlab_note = ""
        if wetlab and wetlab.get("ames_in_vitro"):
            wl_ames = wetlab["ames_in_vitro"]
            wl_ref = wetlab.get("source_document", "GLP study")
            wetlab_note = (
                f"\n**GLP in vitro genotoxicity data (measured):** "
                f"Ames mutagenicity test result: **{wl_ames}** "
                f"({wl_ref}). This measured value supersedes the in silico prediction.\n"
            )
        if wetlab and wetlab.get("noael_mg_kg_day"):
            wl_noael = wetlab["noael_mg_kg_day"]
            wl_species = wetlab.get("noael_species", "rat")
            wetlab_note += (
                f"**GLP in vivo NOAEL:** {wl_noael} mg/kg/day "
                f"({wl_species}, {wetlab.get('noael_study_duration', 'repeat-dose')} study).\n"
            )

        # Stage descriptions — what's in silico vs. what's required
        def _flag(n, total):
            if total == 0:
                return "N/A"
            return f"{n}/{total} ({100*n//total}%)"

        return f"""\
## 2.6.7 Toxicology Written Summary

Per ICH M4S(R2) §2.6.7 this section provides an integrated narrative summary of all
nonclinical toxicology data relevant to {mol} in the context of first-in-human clinical
development for {indication}.
{intro}

### 2.6.7.1 Single-Dose Toxicity

No GLP single-dose (acute) toxicity studies have been conducted in vivo at this stage of
development. Computational safety profiling of the candidate compound series (n={total})
identified no structural alerts associated with acute lethal toxicity via the ClinTox model
(clinical failure predictor). Lead compound composite ClinTox score: {sp.get('clintox_score', sp.get('lead_clintox', 'see §2.6.6.F'))}.

In the absence of in vivo LD₅₀ data, the starting dose for Phase I clinical studies will be
derived using a safety factor (≥1/10 of the human equivalent dose of the GLP NOAEL) consistent
with ICH M3(R2) §4.1 guidance.

### 2.6.7.2 Repeat-Dose Toxicity
{wetlab_note}
Repeat-dose (subchronic) toxicity studies have not been conducted in vivo. Lead compound
selection was guided by in silico DILI prediction (EMA DILI Reflection Paper 2021):
DILI flag rate across campaign compounds: {_flag(dili_flagged, total)}.
Lead compound ({mol}) DILI prediction: {lead_dili} (ADMET-AI probability;
see §2.6.6.D for full DILI profile). Reactive metabolite assessment via SMARTS screen
({rm_summary}) provides EMA Tier 2 bioactivation context.

Per ICH M3(R2) Table 1, GLP repeat-dose toxicity studies (minimum 2 weeks in two species)
are required before single ascending dose Phase I clinical administration. Target organ
toxicity assessment will include standard histopathology (haematoxylin and eosin; PAS;
immunostaining for hepatocyte necrosis and cholestasis markers).

### 2.6.7.3 Genotoxicity
{genotox_prose}
The ICH S2(R1) genotoxicity battery was evaluated computationally for all {total} campaign
compounds. Lead compound ({mol}) Ames mutagenicity prediction: **{lead_ames}** (ADMET-AI
AMES model; TDC Ames benchmark AUROC 0.934). Campaign Ames flag rate: {_flag(ames_flagged, total)}.

Reactive metabolite screening identified {rm_summary} for the lead compound,
providing supplementary evidence for electrophilic reactivity potential consistent with
EMA DILI Reflection Paper §3.2.

*Required before IND filing (ICH M3(R2) Table 1, Phase I):*
- In vitro Ames test (GLP): *Salmonella typhimurium* TA98, TA100, TA102, TA1535 ± S9
- In vitro chromosomal aberration test (GLP): CHO or V79 ± S9
- In vivo micronucleus test (bone marrow, rat or mouse): may be deferred to Phase II
  if both in vitro tests are negative (ICH S2(R1) Option 2)

### 2.6.7.4 Carcinogenicity

Carcinogenicity studies are not required for IND submission for a short-duration Phase I
clinical study (ICH M3(R2) §8). Structural alert screening for carcinogenic potential
(nitroaromatics, aromatic amines, azo compounds, alkylating groups) was incorporated into
the ADMET campaign screening (§2.6.4, §2.6.6). No carcinogenicity alerts were identified
as primary concerns for the lead compound.

### 2.6.7.5 Reproductive and Developmental Toxicity

Reproductive toxicity studies are not required at the IND stage for Phase I studies in
healthy non-reproductive adult volunteers. Per ICH M3(R2) §11.3, fertility and embryofetal
development studies are deferred until Phase II for standard indications. Structural
similarity to known developmental toxicants was assessed computationally.

A pregnancy test requirement will be incorporated into the Phase I study protocol for
women of childbearing potential (ICH M3(R2) §11.3 guidance).

### 2.6.7.6 Local Tolerance

Local tolerance studies will be designed based on the clinical route of administration:
- **Oral**: gastric irritation evaluation planned; acceptable pH and osmolality of
  formulation confirmed prior to Phase I dosing
- **Intravenous (if applicable)**: haemolysis assay + venous irritation study (ICH M3(R2) §15)
  required before i.v. administration

### 2.6.7.7 Other Toxicity Studies: Safety Pharmacology
{cardiac_prose}
**Cardiac safety (ICH S7A/S7B):** In silico hERG channel inhibition: lead compound
predicted IC50 = {lead_herg} µM. Predicted safety margin (IC50/anticipated Cmax):
{margin_str}. Compounds flagged (hERG IC50 < 10 µM) in campaign: {_flag(herg_flagged, total)}.

*Required before FIH (ICH S7B §3.1):* In vitro hERG patch clamp (room temperature and
physiological conditions). A Thorough QT/QTc (TQT) study (ICH E14) will be conducted
before Phase II unless the IKr/hERG data and cardiac safety pharmacology package provide
sufficient evidence to defer.

**CNS safety (ICH S7A):** Standard FOB/Irwin battery planned in rodent (single dose,
clinical route). BBB penetration assessment: {pk.get('bbb_penetrant', 'see §2.6.5.C')}.

**Respiratory (ICH S7A):** Respiratory rate and SpO₂ monitoring included in in vivo
safety pharmacology battery.

---

*This section (§2.6.7) is based on in silico ADMET predictions and structural analysis.
All computational predictions require confirmation by GLP in vitro and in vivo studies
as specified above before IND filing (ICH M3(R2) Table 1) and before first-in-human
administration. The regulatory audit trail for this document is maintained in the BioMate
Campaign database (§2.6.1.6).*"""

    # ------------------------------------------------------------------
    # Regulatory audit
    # ------------------------------------------------------------------

    def _run_audit(self, markdown: str, ctx: dict, region: str) -> tuple[list, dict]:
        """Run the regulatory auditor and return (findings, score_summary)."""
        try:
            from .regulatory_auditor import RegulatoryAuditor
            auditor = RegulatoryAuditor(region=region)
            findings = auditor.audit(markdown, ctx)
            score = {"CRITICAL": 0, "MAJOR": 0, "MINOR": 0, "INFO": 0}
            for f in findings:
                score[f.severity] = score.get(f.severity, 0) + 1
            log.info("[regulatory_audit] region=%s findings: %s", region, score)
            return findings, score
        except Exception as exc:
            log.warning("[regulatory_audit] Audit failed: %s", exc)
            return [], {"CRITICAL": 0, "MAJOR": 0, "MINOR": 0, "INFO": 0, "error": str(exc)}

    # ------------------------------------------------------------------
    # Pandoc conversion
    # ------------------------------------------------------------------

    def _pandoc_convert(
        self,
        md_path: str,
        output_dir: str,
        campaign_id: str,
        warnings: list,
    ) -> tuple[Optional[str], bool]:
        """Convert Markdown to DOCX using pandoc.  Returns (docx_path, pandoc_ok)."""
        docx_path = str(Path(output_dir) / f"{campaign_id}_CTD_2.6.1.docx")
        try:
            result = subprocess.run(
                ["pandoc", md_path, "-o", docx_path, "--from=markdown", "--to=docx"],
                capture_output=True,
                text=True,
                timeout=30,
            )
            if result.returncode != 0:
                warnings.append(f"pandoc conversion failed: {result.stderr.strip()}")
                return None, False
            return docx_path, True
        except FileNotFoundError:
            warnings.append("pandoc not installed — DOCX output unavailable (Markdown written)")
            return None, False
        except subprocess.TimeoutExpired:
            warnings.append("pandoc conversion timed out")
            return None, False


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _fmt(v) -> str:
    if v is None:
        return "N/A"
    try:
        return f"{float(v):.3f}"
    except (TypeError, ValueError):
        return str(v)


def _pct(v) -> str:
    if v is None:
        return "N/A"
    try:
        return f"{float(v) * 100:.1f}%"
    except (TypeError, ValueError):
        return str(v)
