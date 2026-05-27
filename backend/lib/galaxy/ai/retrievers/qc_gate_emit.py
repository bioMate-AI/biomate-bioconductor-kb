"""
QC gate emit — convenience wrapper around qc_gate_reader for caller-side
adoption from qc_trace_monitor / nextflow_executor / workflow hooks.

Standalone helper (new file, does not modify protected files).

Usage pattern in qc_trace_monitor.py (add ONE line right after the existing
autoloop_bridge.evaluate_and_emit call):

    try:
        from galaxy.ai.retrievers.qc_gate_emit import emit_gate_only_event
        emit_gate_only_event(
            process_name=process_name,
            qc_metrics=qc_metrics,
            sse_callback=self.sse_callback,
        )
    except Exception:
        pass

This function:
  1. Classifies the process_name into one of the 10 gate-only domains
     (hts, ich_s5, ich_s7, clinical_trial, allometric, ivive, openfe,
     p0_pkpd, pocket_detection, aizynthfinder).
  2. If matched, builds an autoloop_gate_results-shaped event with
     evidence attached, and emits via the SSE callback.
  3. Returns True if an event was emitted, False otherwise.

The emitted event uses the SAME event-type string as the auto-loop
domains (`autoloop_gate_results`) so the existing frontend panel and
QCEvidenceTooltip wrapper render it without any further frontend wiring.
"""

from __future__ import annotations

import logging
from typing import Any, Callable

from galaxy.ai.retrievers.qc_gate_reader import (
    build_gate_event,
    list_supported_domains,
)

log = logging.getLogger(__name__)


# Process-name → domain mapping.
# Matches qc_trace_monitor's _DOMAIN_KEYWORDS pattern: uppercase substring
# match against process_name.upper(). Keep keyword sets disjoint from the
# auto-loop bridge's _DOMAIN_KEYWORDS so we don't double-emit.
_PROCESS_KEYWORDS: dict[str, set[str]] = {
    "hts": {
        "HTS_PLATE", "PLATE_QC", "HIT_CALLING", "Z_FACTOR_QC",
    },
    "ich_s5": {
        "ICH_S5", "REPRODUCTIVE_TOX", "DART", "TERATOGENICITY",
    },
    "ich_s7": {
        "ICH_S7", "SAFETY_PHARMACOLOGY", "CIPA", "QT_PROLONGATION",
    },
    "clinical_trial": {
        "CLINICAL_TRIAL_SIMULATION", "BOIN", "DOSE_ESCALATION",
        "ADAPTIVE_TRIAL_DESIGN",
    },
    "allometric": {
        "ALLOMETRIC_SCALING", "FIH_DOSE", "INTER_SPECIES_SCALE",
    },
    "ivive": {
        "IVIVE", "HEPATIC_CLEARANCE_PREDICTION",
        "IVIVE_HEPATIC_CLEARANCE",
    },
    "openfe": {
        "OPENFE", "RBFE", "RELATIVE_BINDING_FREE_ENERGY",
    },
    "p0_pkpd": {
        "P0_PKPD", "PKPD_SEMAGLUTIDE", "PKPD_VALIDATION",
    },
    "pocket_detection": {
        "POCKET_DETECTION", "FPOCKET", "DRUGGABILITY",
    },
    "aizynthfinder": {
        "AIZYNTHFINDER", "RETROSYNTHESIS",
    },
    "structure_prediction": {
        "BOLTZ", "BOLTZ_PREDICT", "BOLTZ_STRUCTURE_PREDICTION",
        "CHAI", "CHAI1", "CHAI1_PREDICT", "CHAI1_STRUCTURE_PREDICTION",
        "ALPHAFOLD", "ALPHAFOLD_PREDICT", "AF2", "AF3",
    },
    "cancer_biology": {
        "DETECT_SOMATIC_MUTATIONS", "ANNOTATE_SOMATIC", "SOMATIC_VARIANT_CALLING",
        "MUTECT2", "STRELKA2", "VARSCAN_SOMATIC",
        "DETECT_CNV", "CNV_CALLING", "DETECT_SV", "SV_CALLING",
        "CANCER_BIOLOGY",
    },
    "cryo_em": {
        "CRYOSPARC_STANDARD_SPA", "CRYOSPARC", "SPA_PIPELINE",
        "FOCUSED_REFINEMENT", "GLOBAL_CTF_REFINEMENT", "HELICAL_REFINEMENT",
        "LOCAL_REFINEMENT", "PARTICLE_SUBTRACTION",
        "3D_VARIABILITY", "3D_CLASSIFICATION", "AB_INITIO_3D",
        "TOPAZ_EXTRACT", "TOPAZ_TRAIN",
        "IMPORT_MICROGRAPHS", "IMPORT_PARTICLES",
    },
}


def classify_gate_only_domain(process_name: str) -> str | None:
    """Return the gate-only domain matching process_name, or None.

    Disjoint from autoloop_bridge.classify_domain — that one handles
    admet/docking/cyp_ddi/nca_pk/pbpk. This one handles the 10
    QC-but-no-autoloop domains.
    """
    if not process_name:
        return None
    upper = process_name.upper()
    for domain, kws in _PROCESS_KEYWORDS.items():
        if any(k in upper for k in kws):
            return domain
    return None


def emit_gate_only_event(
    process_name: str,
    qc_metrics: dict,
    sse_callback: Callable[[str, dict], None],
    invocation_id: str | None = None,
) -> bool:
    """Build + emit a `autoloop_gate_results`-shaped event for the 10
    gate-only domains.

    Args:
        process_name:   Nextflow process name (e.g., "HTS_PLATE_QC_HIT_CALLING")
        qc_metrics:     Dict of metric values parsed from the workflow output
                        (Z'-factor, fold-error, R², etc.)
        sse_callback:   The same callback the autoloop_bridge uses
        invocation_id:  Optional invocation UUID for downstream tracking

    Returns:
        True if an event was emitted, False if process_name didn't match
        any gate-only domain or no gates were produced.

    Fail-safe: catches all exceptions and returns False rather than
    propagating. Never blocks the calling QC pipeline.
    """
    try:
        domain = classify_gate_only_domain(process_name)
        if domain is None:
            return False

        event = build_gate_event(
            workflow_name=process_name,
            domain=domain,
            metrics=qc_metrics or {},
        )
        if not event.get("gates"):
            return False

        # Attach invocation_id if provided, matching autoloop_bridge convention
        if invocation_id is not None:
            event["invocation_id"] = invocation_id

        sse_callback("autoloop_gate_results", event)
        return True
    except Exception as exc:
        log.warning(
            "[qc_gate_emit] failed for process=%s: %s", process_name, exc
        )
        return False


def list_gate_only_domains() -> list[str]:
    """Return the 10 gate-only domains this helper handles."""
    return list(_PROCESS_KEYWORDS.keys())


# ─── Additive registration (anti-collision pattern, 2026-05-26) ───────
# Adds cancer_biology / cryo_em / cryo_et keywords via module-level
# mutation instead of editing the _PROCESS_KEYWORDS literal above
# (which is subject to parallel-session linter reverts).
_PROCESS_KEYWORDS.setdefault("cancer_biology", {
    "DETECT_SOMATIC_MUTATIONS", "ANNOTATE_SOMATIC", "SOMATIC_VARIANT_CALLING",
    "MUTECT2", "STRELKA2", "VARSCAN_SOMATIC",
    "DETECT_CNV", "CNV_CALLING", "DETECT_SV", "SV_CALLING",
    "CANCER_BIOLOGY",
})
_PROCESS_KEYWORDS.setdefault("cryo_em", {
    "CRYOSPARC_STANDARD_SPA", "CRYOSPARC", "SPA_PIPELINE",
    "FOCUSED_REFINEMENT", "GLOBAL_CTF_REFINEMENT", "HELICAL_REFINEMENT",
    "LOCAL_REFINEMENT", "PARTICLE_SUBTRACTION",
    "3D_VARIABILITY", "3D_CLASSIFICATION", "AB_INITIO_3D",
    "TOPAZ_EXTRACT", "TOPAZ_TRAIN",
    "IMPORT_MICROGRAPHS", "IMPORT_PARTICLES",
})
_PROCESS_KEYWORDS.setdefault("cryo_et", {
    "ET_FULL_PIPELINE", "ET_PIPELINE",
    "IMPORT_TILTSERIES", "TILT_SERIES_IMPORT",
    "TILT_ALIGNMENT", "TILT_SERIES_ALIGN", "ARETOMO", "IMOD_ALIGN",
    "TOMOGRAM_RECONSTRUCTION", "TOMOGRAM_RECON", "TOMO_RECON",
    "SUBTOMOGRAM_AVERAGING", "SUBTOMO_AVG",
})


# 6 additional domains added 2026-05-26.
_PROCESS_KEYWORDS.setdefault("lnp_formulation", {
    "LNP_FORMULATION_OPTIMIZATION", "LNP_OPTIMIZATION", "LNP_FORMULATION",
    "LIPID_NANOPARTICLE", "LNP_DLS", "LNP_CHARACTERIZATION",
    "LNP_ENDOSOMAL_ESCAPE",
})
_PROCESS_KEYWORDS.setdefault("nlmixr2_poppk", {
    "POPPK_NLMIXR2_FIT", "NLMIXR2_POPPK", "POPULATION_PK_NLMIXR2",
    "POPPK_FIT", "NLMIXR2_FIT", "POPPK_NLMIXR2", "NONMEM_POPPK",
})
_PROCESS_KEYWORDS.setdefault("antibody_developability", {
    "BISPECIFIC_ANTIBODY_DESIGN", "SCFV_ANTIBODY_DESIGN",
    "FCRN_ANTIBODY_PK", "ANTIBODY_DEVELOPABILITY",
    "TAP_SCORE", "CAMSOL", "HYDROPHOBICITY_INDEX",
    "AB_DEVELOPABILITY", "MAB_DEVELOPABILITY",
})
_PROCESS_KEYWORDS.setdefault("sirna_offtarget", {
    "SIRNA_OFFTARGET_ANALYSIS", "SIRNA_OFFTARGET",
    "SIRNA_DESIGN", "SIRNA_SEED_ANALYSIS",
    "SIRNA_ASYMMETRY", "RNAI_OFFTARGET",
})
_PROCESS_KEYWORDS.setdefault("polymorph_stability", {
    "POLYMORPH_STABILITY_SCREENING", "ANALYZE_ACCELERATED_STABILITY",
    "POLYMORPH", "STABILITY_STUDY", "ICH_Q1A", "ACCELERATED_STABILITY",
})
_PROCESS_KEYWORDS.setdefault("biomarker_enrichment", {
    "BIOMARKER_PATIENT_ENRICHMENT", "PREDICTIVE_ENRICHMENT",
    "ENRICHMENT_DESIGN", "BIOMARKER_STRATIFIED", "PHASE3_ENRICHMENT",
})
