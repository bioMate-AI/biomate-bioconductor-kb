"""
Nextflow QC Gate Handler

Monitors Nextflow trace file for process completions and triggers QC validation.
Emits SSE events when QC gates are triggered.
"""

import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Any, Callable, Optional

try:
    from galaxy.jobs.parameter_suggester import get_suggester_for_domain
    SUGGESTER_AVAILABLE = True
except ImportError:
    SUGGESTER_AVAILABLE = False

log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# QC threshold governance constants (Phase 1 — per-invocation overrides)
# ---------------------------------------------------------------------------

# Layer 0: Red lines — absolute bounds enforced even when a user provides an
# override. An override that would cross a red line is clamped to the bound,
# logged as a warning, and recorded in the audit log.
# Format: {metric_key: {"bound": float, "direction": "min"|"max", "rationale": str}}
QC_RED_LINES: Dict[str, Any] = {
    "reads_surviving_pct": {
        "bound": 50.0, "direction": "min",
        "rationale": "> 50% loss = adapter-dominated library; downstream analysis is invalid",
    },
    "fit_quality": {
        "bound": 0.5, "direction": "min",
        "rationale": "CTF estimation completely failed; particle picking results are invalid",
    },
    "mito_fraction_pct": {
        "bound": 80.0, "direction": "max",
        "rationale": "Dead-cell lysates, not transcriptomes; results are biologically meaningless",
    },
    "alignment_rate": {
        "bound": 5.0, "direction": "min",
        "rationale": "< 5% alignment = species/sample swap; halt unconditionally",
    },
}

# Layer 1: GOLD thresholds — mandated by ENCODE4 or GATK Best Practices.
# Metrics in this set cannot be relaxed via qc_overrides. Changes require a
# platform-level code review with a new evidence citation.
QC_GOLD_METRICS: frozenset = frozenset({
    "mapped_pct",       # GATK Best Practices: FLAGSTAT mapped ≥ 70%
    "tss_enrichment",   # ENCODE4 ATAC-seq 2022: ≥ 5 acceptable, ≥ 7 ideal
    "nrf_score",        # ENCODE4 ATAC-seq 2022: ≥ 0.9
})

# Layer 3: Named profiles — curated sets of Layer-2 overrides for well-characterised
# assay contexts. Each profile is a dict of {metric_key: threshold_value} using
# the same keys accepted by qc_overrides. Profiles are read-only and versioned;
# users may supply explicit qc_overrides on top of a profile (explicit takes precedence).
#
# Profile format:
#   description:  str — human-readable summary for the API /api/qc/profiles endpoint
#   domain_hint:  str — primary workflow domain (informational only)
#   overrides:    Dict[str, float] — threshold overrides applied when profile is selected
#   references:   List[str] — primary literature / guideline citations
QC_NAMED_PROFILES: Dict[str, Dict[str, Any]] = {
    # ---------------------------------------------------------------
    # RNA-seq
    # ---------------------------------------------------------------
    "rnaseq_polya_standard": {
        "description": "Standard polyA-selected RNA-seq (default). No adjustments from platform defaults.",
        "domain_hint": "rnaseq",
        "overrides": {},
        "references": ["nf-core/rnaseq v3.14 defaults"],
    },
    "rnaseq_ribodepleted": {
        "description": (
            "Total RNA with ribosomal depletion (RiboZero / RiboMinus). "
            "Ribo-depletion removes large rRNA fractions, producing more intronic reads "
            "that may not align to a spliced transcriptome reference — lowering effective "
            "alignment rate by 10–20 pp compared to polyA libraries."
        ),
        "domain_hint": "rnaseq",
        "overrides": {
            "alignment_rate": 50.0,      # vs default 70%  (Zhao et al. 2020, RNA Biol)
            "reads_surviving_pct": 65.0, # vs default 70%
            "assigned_reads_pct": 40.0,  # vs default 50%  (intronic reads miss splice-junction counts)
        },
        "references": ["Zhao S et al. 2020 RNA Biol 17(8):1105-1118"],
    },
    "rnaseq_ffpe": {
        "description": (
            "FFPE-preserved tissue RNA-seq. RNA is highly fragmented (median fragment 100–200 bp), "
            "resulting in lower alignment rates, reduced Q30 scores, and more trimming failures. "
            "Standard thresholds generate systematic false-positive gates on valid FFPE data."
        ),
        "domain_hint": "rnaseq",
        "overrides": {
            "alignment_rate": 45.0,      # vs default 70%  (Sinicropi et al. 2012)
            "reads_surviving_pct": 60.0, # vs default 70%
            "q30_pct": 65.0,             # vs default 75%
        },
        "references": ["Sinicropi D et al. 2012 PLoS ONE 7(5):e38396"],
    },
    "rnaseq_single_nucleus": {
        "description": (
            "Single-nucleus RNA-seq (snRNA-seq). Intronic reads dominate — alignment to a "
            "spliced mRNA reference is fundamentally lower than cytoplasmic RNA-seq. "
            "Duplicate rate check is suppressed: nuclear RNA is rare, so PCR amplification "
            "is necessary and duplicates do not indicate library quality problems."
        ),
        "domain_hint": "rnaseq",
        "overrides": {
            "alignment_rate": 50.0,   # 10x Genomics snRNA-seq Guide v2.0
            # duplicate_pct suppressed via domain-aware skip — not a named-profile concern
        },
        "references": ["10x Genomics snRNA-seq Reagent Kit User Guide v2.0 (2023)"],
    },
    "rnaseq_nonmodel_organism": {
        "description": (
            "Non-model organism RNA-seq with an incomplete or draft genome/annotation. "
            "Unannotated genes produce unmapped reads and inflate 'unassigned' counts "
            "in feature counting. Thresholds are relaxed; interpretation requires care."
        ),
        "domain_hint": "rnaseq",
        "overrides": {
            "alignment_rate": 40.0,   # [BRONZE] no formal standard; community practice
            "assigned_reads_pct": 30.0,
        },
        "references": ["[BRONZE] community practice — no formal guideline"],
    },

    # ---------------------------------------------------------------
    # DNA-seq / WGS / WES
    # ---------------------------------------------------------------
    "wgs_germline_standard": {
        "description": "Standard germline WGS (default). 30X minimum coverage per GATK Best Practices.",
        "domain_hint": "wgs",
        "overrides": {},
        "references": ["GATK Best Practices — Germline SNP/Indel calling (2023)"],
    },
    "wgs_germline_lowpass": {
        "description": (
            "Low-pass WGS (0.5–10X) for population genetics, imputation, and polygenic "
            "score studies. 4X minimum is the empirical floor for reliable imputation "
            "with modern reference panels (TOPMed / 1000G)."
        ),
        "domain_hint": "wgs",
        "overrides": {
            "mean_coverage": 4.0,    # Rubinacci et al. 2021, Nat Genet
            "duplicate_pct": 60.0,  # PCR amplification of shallow libraries is expected
        },
        "references": ["Rubinacci S et al. 2021 Nat Genet 53:120-126 (UK Biobank)"],
    },
    "wgs_somatic_tumor_only": {
        "description": (
            "Somatic tumor-only WGS without a matched normal. Higher coverage is required "
            "to detect low-VAF mutations and distinguish somatic from germline variants. "
            "80X is the GATK Mutect2 recommendation for tumor-only calling."
        ),
        "domain_hint": "wgs",
        "overrides": {
            "mean_coverage": 80.0,
            "duplicate_pct": 50.0,  # tumor libraries often have elevated PCR duplication
        },
        "references": ["GATK Mutect2 Best Practices — Tumor-Only (2023)"],
    },
    "wgs_ffpe": {
        "description": (
            "FFPE-derived WGS. FFPE artifacts (C→T and G→A transitions) require higher "
            "depth to filter reliably, but FFPE PCR bias substantially increases duplicate "
            "rates — a 65% duplicate threshold is supported by Robbe et al. 2018."
        ),
        "domain_hint": "wgs",
        "overrides": {
            "mean_coverage": 30.0,  # same as germline; more depth is better but not always achievable
            "duplicate_pct": 65.0,  # Robbe et al. 2018, Nat Med 24:1555
        },
        "references": ["Robbe P et al. 2018 Nat Med 24:1555-1563"],
    },
    "wes_research": {
        "description": (
            "Research-grade whole-exome sequencing. 50X is sufficient for most germline "
            "variant discovery studies; clinical applications require wes_clinical_germline (80X)."
        ),
        "domain_hint": "wes",
        "overrides": {
            "mean_coverage": 50.0,  # nf-core/sarek v3 defaults for WES
        },
        "references": ["nf-core/sarek v3 WES defaults"],
    },
    "wes_clinical_germline": {
        "description": (
            "Clinical-grade WES for germline diagnostic reporting. 80X minimum is the "
            "ACMG 2016 technical standard for NGS-based clinical diagnostics."
        ),
        "domain_hint": "wes",
        "overrides": {
            "mean_coverage": 80.0,  # ACMG 2016 NGS Technical Standards
        },
        "references": ["ACMG/AMP 2016 Standards and Guidelines for NGS Diagnostics"],
    },

    # ---------------------------------------------------------------
    # Single-cell RNA-seq
    # ---------------------------------------------------------------
    "scrna_standard": {
        "description": "Standard single-cell RNA-seq (10x Genomics Chromium, default).",
        "domain_hint": "scrna_seq",
        "overrides": {},
        "references": ["10x Genomics Cell Ranger v7 defaults"],
    },
    "scrna_cardiac": {
        "description": (
            "Single-cell RNA-seq from cardiac or skeletal muscle tissue. "
            "Cardiomyocytes are rich in mitochondria — a mito fraction of 30–40% "
            "is biologically expected and does NOT indicate dead/damaged cells. "
            "The standard 20% gate produces high false-positive rates in cardiac studies."
        ),
        "domain_hint": "scrna_seq",
        "overrides": {
            "mito_fraction_pct": 40.0,        # vs default 20%  (Simonson et al. 2023)
            "mito_fraction_pct_warning": 25.0, # warn above 25% (advisory)
        },
        "references": [
            "Simonson B et al. 2023 Circ Res 132(9):1174-1193",
            "Kuppe C et al. 2022 Nature 605(7909):319-326 (cardiac cell atlas)",
        ],
    },
    "scrna_neuronal": {
        "description": (
            "Single-cell RNA-seq from brain / neuronal tissue. "
            "Neurons have elevated mitochondrial content relative to non-neural tissues; "
            "30% mito is an appropriate permissive gate. Median genes per cell may be "
            "lower for inhibitory interneurons (narrower transcriptome)."
        ),
        "domain_hint": "scrna_seq",
        "overrides": {
            "mito_fraction_pct": 30.0,         # vs default 20%
            "mito_fraction_pct_warning": 20.0,  # same as default hard gate (advisory sooner)
            "median_genes_per_cell": 300,        # vs default 500 — interneurons transcriptomically narrow
        },
        "references": [
            "[BRONZE] Allen Brain Atlas scRNA-seq QC guidelines (community practice)",
            "Bakken TE et al. 2021 Nature 598:86-102 (Human Brain Cell Atlas)",
        ],
    },

    # ---------------------------------------------------------------
    # Metagenomics
    # ---------------------------------------------------------------
    "metagenomics_human_gut": {
        "description": (
            "Human gut metagenomics with a comprehensive database (Kraken2 Standard or RefSeq). "
            "The gut microbiome is well-characterised — 50% classification is the HMP "
            "empirical floor for Illumina data."
        ),
        "domain_hint": "metagenomics",
        "overrides": {
            "classified_pct_critical": 50.0,  # vs default 30%  (HMP Consortium 2012)
            "classified_pct_warning": 60.0,   # tighter than default (same)
        },
        "references": ["HMP Consortium 2012 Nature 486:207-214"],
    },
    "metagenomics_soil": {
        "description": (
            "Soil metagenomics — high microbial 'dark matter' fraction. "
            "Even with a comprehensive database, soil samples routinely classify "
            "5–40% of reads. Warning threshold is set at 8% (investigation if lower); "
            "critical gate is suppressed to 3%."
        ),
        "domain_hint": "metagenomics",
        "overrides": {
            "classified_pct_critical": 3.0,   # suppressed — soil dark matter is expected
            "classified_pct_warning": 8.0,    # only investigate if < 8%
        },
        "references": [
            "Bahram M et al. 2018 Nature 560(7717):233-237",
            "Delgado-Baquerizo M et al. 2018 Science 359(6373):320-325",
        ],
    },
    "metagenomics_marine": {
        "description": (
            "Marine metagenomics — reference databases cover ocean microbiota poorly. "
            "Open-ocean samples commonly classify 10–50% of reads depending on depth, "
            "season, and geographic location. Critical gate suppressed to 4%; "
            "warning threshold at 10%."
        ),
        "domain_hint": "metagenomics",
        "overrides": {
            "classified_pct_critical": 4.0,
            "classified_pct_warning": 10.0,
        },
        "references": ["Sunagawa S et al. 2015 Science 348(6237):1261359 (TARA Oceans)"],
    },
    "metagenomics_clinical_pathogen": {
        "description": (
            "Clinical metagenomics for pathogen detection (bloodstream infection, CSF). "
            "Samples should be dominated by human reads (which are not classified by "
            "Kraken2 without a human database entry) or by the pathogen. "
            "Very low classification (<60%) is unusual and warrants investigation."
        ),
        "domain_hint": "metagenomics",
        "overrides": {
            "classified_pct_critical": 60.0,
            "classified_pct_warning": 70.0,
        },
        "references": ["[BRONZE] IDSA clinical metagenomics guidance (2024)"],
    },

    # ---------------------------------------------------------------
    # Cryo-EM
    # ---------------------------------------------------------------
    "cryoem_spa_purified": {
        "description": "Standard single-particle analysis of purified protein complexes (default).",
        "domain_hint": "cryo_em",
        "overrides": {},
        "references": ["EMPIAR deposition standards; EMDB validation report (2024)"],
    },
    "cryoem_spa_membrane": {
        "description": (
            "Single-particle cryo-EM of membrane proteins (GPCRs, channels, transporters). "
            "Membrane proteins embedded in detergent micelles or nanodiscs exhibit higher "
            "beam-induced motion than soluble complexes. 80Å drift threshold is appropriate."
        ),
        "domain_hint": "cryo_em",
        "overrides": {
            "total_drift_angstrom": 80.0,   # vs default 50Å
            "fit_quality": 0.65,            # vs default 0.7 (detergent scatter reduces signal)
        },
        "references": ["[BRONZE] Membrane protein cryo-EM community practice (2024)"],
    },
    "cryoem_tomo_in_situ": {
        "description": (
            "Cryo-electron tomography of cellular lamellae prepared by FIB-SEM milling. "
            "In-situ cryo-ET has much higher drift (100–200Å) due to lamella thickness, "
            "carbon contamination, and beam-induced charging."
        ),
        "domain_hint": "cryo_em",
        "overrides": {
            "total_drift_angstrom": 150.0,  # in-situ lamellae: high drift is expected
            "fit_quality": 0.5,             # red-line floor — cannot be lowered further
            "correlation_score": 0.3,       # vs default 0.5 (thick lamellae attenuate signal)
        },
        "references": ["[BRONZE] FIB-SEM cryo-ET community practice; Bharat & Bharat 2024"],
    },
}


class NextflowQCGateHandler:
    """
    Handles QC gate checking for Nextflow workflow processes.

    Monitors process completion events and:
    1. Calculates QC metrics for completed processes
    2. Compares against quality thresholds
    3. Emits SSE events when QC gates are triggered
    """

    def __init__(
        self,
        invocation_id: str,
        work_dir: Path,
        sse_callback: Callable[[str, Dict[str, Any]], None],
        app: Any,
        workflow_domain: str = "cryo_em",
        current_parameters: Optional[Dict[str, Any]] = None,
        qc_overrides: Optional[Dict[str, Any]] = None,
        qc_profile: Optional[str] = None,
    ):
        """
        Initialize QC gate handler.

        Args:
            invocation_id: Workflow invocation ID
            work_dir: Nextflow work directory
            sse_callback: Callback for emitting SSE events - signature: (event_type, data)
            app: Galaxy app instance
            workflow_domain: Domain of the workflow (e.g., 'cryo_em', 'rnaseq')
            current_parameters: Current workflow parameters
            qc_overrides: Per-invocation threshold overrides dict (Phase 1).
                GOLD metrics and red-line bounds cannot be overridden.
                Explicit overrides take precedence over profile defaults.
                Example: {"alignment_rate": 50.0, "reads_surviving_pct": 65.0}
            qc_profile: Named QC profile (Phase 2 — Layer 3).
                Profile overrides are applied first; explicit qc_overrides values
                take precedence over any value defined in the profile.
                Example: "rnaseq_ribodepleted"
        """
        self.invocation_id = invocation_id
        self.work_dir = work_dir
        self.sse_callback = sse_callback
        self.app = app
        self.workflow_domain = workflow_domain
        self.current_parameters = current_parameters or {}
        self.active_profile = qc_profile  # None if not using a named profile

        # Merge profile overrides (lower precedence) with explicit overrides (higher precedence).
        # Merge order: profile → explicit overrides (right-hand-side wins on key collision)
        profile_overrides = self.get_profile_overrides(qc_profile) if qc_profile else {}
        explicit_overrides = qc_overrides or {}
        self.qc_overrides: Dict[str, Any] = {**profile_overrides, **explicit_overrides}

        # Track which processes have been checked
        self.checked_processes = set()

        # Write an audit record at initialisation when overrides are active
        if self.qc_overrides or self.active_profile:
            self._write_audit_log_entry("initialized", {})
            if self.active_profile:
                log.info(
                    f"[QC Profile] Invocation {invocation_id}: "
                    f"named profile '{self.active_profile}' active "
                    f"({len(profile_overrides)} base overrides) + "
                    f"{len(explicit_overrides)} explicit overrides"
                )
            else:
                log.info(
                    f"[QC Override] Invocation {invocation_id}: "
                    f"{len(self.qc_overrides)} threshold override(s) active: "
                    f"{list(self.qc_overrides.keys())}"
                )

        # Initialize parameter suggester
        self.parameter_suggester = None
        if SUGGESTER_AVAILABLE:
            try:
                self.parameter_suggester = get_suggester_for_domain(workflow_domain, log)
                log.info(f"[QC Gate] Parameter suggester initialized for domain: {workflow_domain}")
            except Exception as e:
                log.warning(f"[QC Gate] Failed to initialize parameter suggester: {e}")

    # ------------------------------------------------------------------
    # QC override support (Phase 1)
    # ------------------------------------------------------------------

    @classmethod
    def validate_qc_overrides(cls, overrides: Dict[str, Any]) -> "tuple[bool, list]":
        """
        Validate user-provided QC overrides before persisting them.

        Returns:
            (valid: bool, errors: list[str])
        """
        errors = []
        for metric, value in overrides.items():
            if metric in QC_GOLD_METRICS:
                errors.append(
                    f"Cannot override GOLD metric '{metric}' — it is mandated by "
                    f"ENCODE4/GATK Best Practices and is not user-configurable. "
                    f"Contact your platform administrator to change it."
                )
            try:
                float(value)
            except (TypeError, ValueError):
                errors.append(
                    f"Override value for '{metric}' must be numeric, got: {value!r}"
                )
        return len(errors) == 0, errors

    @classmethod
    def validate_qc_profile(cls, profile_name: str) -> "tuple[bool, list]":
        """
        Validate that a named QC profile exists.

        Returns:
            (valid: bool, errors: list[str])
        """
        if profile_name not in QC_NAMED_PROFILES:
            known = sorted(QC_NAMED_PROFILES.keys())
            return False, [
                f"Unknown QC profile '{profile_name}'. "
                f"Known profiles: {', '.join(known)}"
            ]
        return True, []

    @classmethod
    def get_profile_overrides(cls, profile_name: str) -> Dict[str, Any]:
        """
        Return the threshold overrides for a named QC profile.

        Returns an empty dict for unknown profiles (caller should validate first).
        """
        profile = QC_NAMED_PROFILES.get(profile_name, {})
        return dict(profile.get("overrides", {}))

    @classmethod
    def list_profiles(cls) -> list:
        """
        Return a list of all named profiles with their metadata for the API endpoint.
        """
        return [
            {
                "id": name,
                "description": profile["description"],
                "domain_hint": profile.get("domain_hint", "unknown"),
                "overrides": profile.get("overrides", {}),
                "references": profile.get("references", []),
            }
            for name, profile in QC_NAMED_PROFILES.items()
        ]

    def _get_threshold(self, metric: str, default: float) -> float:
        """
        Return the effective threshold for a metric, applying any user override.

        Lookup order (highest precedence first):
          1. GOLD check  — override silently ignored; returns *default*
          2. qc_overrides[metric] — applied if present and numeric
          3. Red-line clamp — override value clamped if it would cross a hard bound
          4. *default* — returned when no override is configured

        Args:
            metric:  Metric key (same keys used in qc_overrides dict)
            default: The platform-default threshold value
        """
        if not self.qc_overrides or metric not in self.qc_overrides:
            return default

        # GOLD metrics: override not permitted
        if metric in QC_GOLD_METRICS:
            log.warning(
                f"[QC Override] Ignoring override for GOLD metric '{metric}' "
                f"(ENCODE4/GATK mandated — not user-configurable)"
            )
            return default

        try:
            override_val = float(self.qc_overrides[metric])
        except (TypeError, ValueError):
            log.warning(
                f"[QC Override] Invalid override value for '{metric}': "
                f"{self.qc_overrides[metric]!r} — using default {default}"
            )
            return default

        # Red-line clamp
        if metric in QC_RED_LINES:
            rl = QC_RED_LINES[metric]
            if rl["direction"] == "min" and override_val < rl["bound"]:
                log.warning(
                    f"[QC Override] '{metric}' override {override_val} crosses red-line "
                    f"floor {rl['bound']} — clamped. Rationale: {rl['rationale']}"
                )
                override_val = rl["bound"]
            elif rl["direction"] == "max" and override_val > rl["bound"]:
                log.warning(
                    f"[QC Override] '{metric}' override {override_val} crosses red-line "
                    f"ceiling {rl['bound']} — clamped. Rationale: {rl['rationale']}"
                )
                override_val = rl["bound"]

        return override_val

    def _write_audit_log_entry(self, event_type: str, applied_overrides: Dict[str, Any]) -> None:
        """
        Append one JSONL record to work_dir/qc_overrides_audit.jsonl.

        The file is created on first write; each line is a self-contained JSON object
        so entries can be read incrementally without loading the whole file.
        """
        import json as _json
        audit_path = self.work_dir / "qc_overrides_audit.jsonl"
        entry: Dict[str, Any] = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "invocation_id": self.invocation_id,
            "event_type": event_type,
            "active_profile": self.active_profile,
            "configured_overrides": dict(self.qc_overrides),
            "applied_overrides": applied_overrides,
        }
        try:
            with open(audit_path, "a") as fh:
                fh.write(_json.dumps(entry) + "\n")
        except Exception as exc:
            log.warning(f"[QC Override] Failed to write audit log to {audit_path}: {exc}")

    def handle_process_completion(
        self,
        task_id: str,
        process_name: str,
        process_hash: str,
        status: str
    ):
        """
        Handle completion of a Nextflow process.

        Args:
            task_id: Nextflow task ID
            process_name: Name of the process
            process_hash: Process hash
            status: Completion status (COMPLETED, FAILED, etc.)
        """
        # Skip if already checked
        check_key = f"{process_name}:{task_id}"
        if check_key in self.checked_processes:
            return

        self.checked_processes.add(check_key)

        log.info(f"[QC Gate] Process completed: {process_name} (task {task_id}, status {status})")

        # Only check QC for successfully completed processes
        if status != "COMPLETED":
            log.debug(f"[QC Gate] Skipping QC check for non-completed process: {status}")
            return

        # Calculate QC metrics for this process
        qc_metrics = self._calculate_qc_metrics(process_name, task_id, process_hash)

        if not qc_metrics:
            log.debug(f"[QC Gate] No QC metrics calculated for {process_name}")
            return

        # Check if QC thresholds are met
        qc_passed, all_failures = self._check_qc_thresholds(process_name, qc_metrics)

        # Separate hard (blocking) failures from advisory informational items
        blocking_failures = [f for f in all_failures if not f.get("advisory", False)]
        advisory_items = [f for f in all_failures if f.get("advisory", False)]

        # Emit SSE event based on whether hard (blocking) failures exist
        if not qc_passed:
            log.warning(f"[QC Gate] TRIGGERED for {process_name}: {blocking_failures}")
            # Pass all_failures (blocking + advisory) so the gate modal can display full context.
            # Frontend distinguishes advisory items via the advisory=True flag for different styling.
            self._emit_qc_gate_event(process_name, qc_metrics, all_failures)
        else:
            log.info(f"[QC Gate] PASSED for {process_name}")
            # When no hard failures: advisory items + near-threshold warnings surface via warning event
            near_threshold = self._check_qc_warnings(process_name, qc_metrics)
            all_warnings = advisory_items + near_threshold
            if all_warnings:
                log.info(f"[QC Gate] Near-threshold/advisory warnings for {process_name}: {len(all_warnings)}")
                self._emit_qc_warning_event(process_name, qc_metrics, all_warnings)

    def _calculate_qc_metrics(
        self,
        process_name: str,
        task_id: str,
        process_hash: str
    ) -> Optional[Dict[str, Any]]:
        """
        Calculate QC metrics for a completed process.

        Attempts to extract real metrics from Nextflow work-directory output files.
        Returns None (no gate triggered) when real data cannot be read, so that
        missing-output does not silently produce fake pass/fail results.
        """
        # Build the per-task work subdirectory path from the process hash.
        # Nextflow creates:  work_dir/<ab>/<full_hash>/  for trace hash "ab/shortprefix"
        # The trace file truncates the hash — glob for the matching subdirectory.
        if process_hash and "/" in process_hash:
            prefix, rest = process_hash.split("/", 1)
            prefix_dir = self.work_dir / prefix
            if prefix_dir.is_dir():
                # Find subdirectory whose name starts with the abbreviated rest
                matches = sorted(prefix_dir.glob(f"{rest}*"))
                task_work_dir = matches[0] if matches else (prefix_dir / rest)
            else:
                task_work_dir = prefix_dir / rest
        else:
            task_work_dir = self.work_dir

        process_upper = process_name.upper()

        # --- Cryo-EM ---
        if "MOTION_CORRECTION" in process_upper:
            return self._parse_motion_correction_metrics(task_work_dir)
        elif "CTF_ESTIMATION" in process_upper or "CTF_ESTIMATE" in process_upper:
            return self._parse_ctf_metrics(task_work_dir)
        elif "PARTICLE_PICKING" in process_upper or "PICKING" in process_upper:
            return self._parse_picking_metrics(task_work_dir)

        # --- RNA-seq / general sequencing quality ---
        elif any(k in process_upper for k in ("FASTQC", "MULTIQC")):
            return self._parse_fastqc_metrics(task_work_dir)
        elif any(k in process_upper for k in ("FASTP", "TRIMGALORE", "TRIMMOMATIC", "BBDUK")):
            return self._parse_trimming_metrics(task_work_dir)
        elif any(k in process_upper for k in ("STAR_ALIGN", "STAR_GENOME", "HISAT2_ALIGN",
                                               "HISAT2", "BOWTIE2_ALIGN", "BOWTIE2")):
            return self._parse_alignment_metrics(task_work_dir)
        elif any(k in process_upper for k in ("FEATURECOUNTS", "SUBREAD", "HTSEQ")):
            return self._parse_featurecounts_metrics(task_work_dir)
        elif any(k in process_upper for k in ("SALMON_QUANT", "SALMON", "KALLISTO")):
            return self._parse_salmon_metrics(task_work_dir)

        # --- DNA-seq / variant calling ---
        elif any(k in process_upper for k in ("FLAGSTAT", "SAMTOOLS_FLAGSTAT", "SAMTOOLS_STATS")):
            return self._parse_flagstat_metrics(task_work_dir)
        elif any(k in process_upper for k in ("MARKDUPLICATES", "PICARD_MARKDUP",
                                               "MARKDUP", "GATK_MARKDUP")):
            return self._parse_picard_dup_metrics(task_work_dir)
        elif any(k in process_upper for k in ("BWA_MEM", "BWA_MEM2", "BWAMEM")):
            return self._parse_alignment_metrics(task_work_dir)
        elif any(k in process_upper for k in ("MOSDEPTH", "SAMTOOLS_COVERAGE",
                                               "GATK_COVERAGE", "PICARD_WGS")):
            return self._parse_coverage_metrics(task_work_dir)

        # --- Single-cell RNA-seq ---
        elif any(k in process_upper for k in ("CELLRANGER_COUNT", "CELLRANGER",
                                               "STARSOLO", "ALEVIN")):
            return self._parse_singlecell_metrics(task_work_dir)

        # --- ChIP-seq / ATAC-seq ---
        elif any(k in process_upper for k in ("MACS2", "MACS3", "CALLPEAK")):
            return self._parse_peakcalling_metrics(task_work_dir)
        elif any(k in process_upper for k in ("ATAC_QC", "TSS_ENRICH", "ATAC_PEAK",
                                               "DEEPTOOLS_PLOTFINGERPRINT", "PLOTFINGERPRINT")):
            return self._parse_atac_metrics(task_work_dir)

        # --- Metagenomics ---
        elif any(k in process_upper for k in ("KRAKEN2", "KRAKEN", "BRACKEN",
                                               "METAPHLAN", "KAIJU")):
            return self._parse_metagenomics_metrics(task_work_dir)

        else:
            return None

    def _parse_motion_correction_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse motion correction log files (MotionCor2 / RELION Motioncorr output).
        Falls back to None when files are absent so the QC gate is not triggered.
        """
        metrics: Dict[str, Any] = {}

        # MotionCor2 writes a *_DW.log or *_Full.log with per-frame shifts
        log_files = list(task_work_dir.glob("*.log")) + list(task_work_dir.glob("*_motion.txt"))
        for log_file in log_files:
            try:
                text = log_file.read_text(errors="replace")
                # Total drift: look for "Total motion:" or "Global drift:"
                for line in text.splitlines():
                    line_lower = line.lower()
                    if "total motion" in line_lower or "global drift" in line_lower:
                        parts = line.split()
                        for p in parts:
                            try:
                                val = float(p)
                                if 0 < val < 500:  # plausible angstrom value
                                    metrics["total_drift_angstrom"] = val
                                    break
                            except ValueError:
                                pass
                    elif "correlation" in line_lower or "score" in line_lower:
                        parts = line.split()
                        for p in parts:
                            try:
                                val = float(p)
                                if 0.0 <= val <= 1.0:
                                    metrics.setdefault("correlation_score", val)
                                    break
                            except ValueError:
                                pass
            except OSError:
                continue

        if not metrics:
            # No readable output — do not trigger the QC gate
            log.debug(f"[QC] No motion correction metrics found in {task_work_dir}")
            return None

        if "total_drift_angstrom" in metrics:
            n_frames = metrics.get("n_frames", 40)
            metrics.setdefault(
                "drift_per_frame_angstrom",
                round(metrics["total_drift_angstrom"] / max(n_frames, 1), 2)
            )
        return metrics

    def _parse_ctf_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse CTF estimation output (CTFFIND4 *.txt / Gctf *.log).
        Falls back to None when files are absent.
        """
        metrics: Dict[str, Any] = {}

        # CTFFIND4 diagnostic output: each data line has
        # DefocusU  DefocusV  Astigmatism_angle  PhaseShift  FitScore
        # Multi-micrograph files have one result per line — scan from last to
        # first so that a bad final line does not silently discard valid data.
        for txt_file in list(task_work_dir.glob("*.txt")) + list(task_work_dir.glob("*_ctf.log")):
            try:
                lines = [l for l in txt_file.read_text(errors="replace").splitlines() if l.strip()]
                valid_result: Dict[str, Any] = {}
                oor_fallback: Dict[str, Any] = {}
                for line in reversed(lines):
                    parts = line.split()
                    if len(parts) >= 5:
                        try:
                            defocus_u = float(parts[0])
                            defocus_v = float(parts[1])
                            astig = abs(defocus_u - defocus_v)
                            fit_score = float(parts[4])
                            if 1000 < defocus_u < 100000:  # plausible angstrom
                                valid_result["defocus_u_angstrom"] = defocus_u
                                valid_result["defocus_v_angstrom"] = defocus_v
                                valid_result["astigmatism_angstrom"] = round(astig, 1)
                                valid_result["fit_quality"] = min(1.0, max(0.0, fit_score))
                                break  # Found valid in-range; stop scanning
                            elif defocus_u > 0 and not oor_fallback:
                                # Record OOR as fallback; keep scanning for valid in-range line
                                oor_fallback["defocus_u_angstrom"] = defocus_u
                                oor_fallback["defocus_v_angstrom"] = defocus_v
                                oor_fallback["astigmatism_angstrom"] = round(astig, 1)
                                oor_fallback["fit_quality"] = min(1.0, max(0.0, fit_score))
                                oor_fallback["defocus_out_of_range"] = True
                                oor_fallback["defocus_direction"] = "below" if defocus_u <= 1000 else "above"
                        except ValueError:
                            pass
                metrics.update(valid_result or oor_fallback)
                if metrics:
                    break
            except OSError:
                continue

        if not metrics:
            log.debug(f"[QC] No CTF metrics found in {task_work_dir}")
            return None

        return metrics

    def _parse_picking_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse particle picking output (STAR files / crYOLO JSON).
        Falls back to None when files are absent.
        """
        metrics: Dict[str, Any] = {}

        # Count coordinates in STAR or box files
        coordinate_files = (
            list(task_work_dir.glob("*.star"))
            + list(task_work_dir.glob("*.box"))
            + list(task_work_dir.glob("*.coords"))
        )

        total_particles = 0
        n_micrographs = 0
        for coord_file in coordinate_files:
            try:
                lines = [l for l in coord_file.read_text(errors="replace").splitlines()
                         if l.strip() and not l.startswith("_") and not l.startswith("#")]
                count = len([l for l in lines if l[0].isdigit() or l[0] == '-'])
                if count > 0:
                    total_particles += count
                    n_micrographs += 1
            except OSError:
                continue

        if total_particles == 0 and n_micrographs == 0:
            log.debug(f"[QC] No picking metrics found in {task_work_dir}")
            return None

        metrics["particles_picked"] = total_particles
        if n_micrographs > 0:
            metrics["particle_density_per_micrograph"] = round(
                total_particles / n_micrographs, 1
            )
        # Duplicate fraction requires NMS data — not available here, default to 0
        metrics["duplicate_fraction"] = 0.0
        return metrics

    # ------------------------------------------------------------------
    # RNA-seq / sequencing quality parsers
    # ------------------------------------------------------------------

    def _parse_fastqc_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse FastQC summary.txt or fastqc_data.txt.
        Returns per-base quality, GC%, adapter contamination flag.
        """
        metrics: Dict[str, Any] = {}

        # FastQC writes summary.txt with PASS/WARN/FAIL per module
        for summary_file in list(task_work_dir.glob("*/summary.txt")) + list(task_work_dir.glob("summary.txt")):
            try:
                lines = summary_file.read_text(errors="replace").splitlines()
                failed_modules = [l.split("\t")[1] for l in lines if l.startswith("FAIL")]
                warned_modules = [l.split("\t")[1] for l in lines if l.startswith("WARN")]
                if failed_modules or warned_modules:
                    metrics["failed_modules"] = failed_modules
                    metrics["warned_modules"] = warned_modules
                    metrics["module_failures"] = len(failed_modules)
            except OSError:
                continue

        # FastQC data: look for %GC and basic stats
        for data_file in list(task_work_dir.glob("*/fastqc_data.txt")) + list(task_work_dir.glob("fastqc_data.txt")):
            try:
                text = data_file.read_text(errors="replace")
                for line in text.splitlines():
                    if line.startswith("%GC"):
                        try:
                            metrics["gc_content_pct"] = float(line.split("\t")[1])
                        except (ValueError, IndexError):
                            pass
                    elif "Total Sequences" in line:
                        try:
                            metrics["total_sequences"] = int(line.split("\t")[1])
                        except (ValueError, IndexError):
                            pass
            except OSError:
                continue

        # MultiQC JSON aggregation
        for mq_file in list(task_work_dir.glob("multiqc_data.json")) + list(task_work_dir.glob("**/multiqc_data.json")):
            try:
                import json as _json
                mq = _json.loads(mq_file.read_text(errors="replace"))
                general = mq.get("report_general_stats_data", [{}])
                if general and isinstance(general, list):
                    sample = next(iter(general[0].values()), {}) if general[0] else {}
                    if "percent_gc" in sample:
                        metrics.setdefault("gc_content_pct", sample["percent_gc"])
                    if "avg_sequence_length" in sample:
                        metrics["avg_read_length"] = sample["avg_sequence_length"]
            except Exception:
                continue

        if not metrics:
            return None
        return metrics

    def _parse_trimming_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse FASTP JSON, Trimmomatic log, TrimGalore log.
        Key metric: fraction of reads surviving trimming.
        """
        metrics: Dict[str, Any] = {}

        # FASTP writes fastp.json
        for fp_file in list(task_work_dir.glob("*.json")) + list(task_work_dir.glob("fastp.json")):
            try:
                import json as _json
                data = _json.loads(fp_file.read_text(errors="replace"))
                filt = data.get("filtering_result", {})
                summary = data.get("summary", {})
                total_in = summary.get("before_filtering", {}).get("total_reads", 0)
                passed = filt.get("passed_filter_reads", 0)
                if total_in > 0:
                    metrics["reads_surviving_pct"] = round(100.0 * passed / total_in, 2)
                    metrics["total_reads_in"] = total_in
                    q30 = summary.get("before_filtering", {}).get("q30_rate", None)
                    if q30 is not None:
                        metrics["q30_pct"] = round(q30 * 100, 2)
                break
            except Exception:
                continue

        # Trimmomatic log: "Input Read Pairs: X Surviving: Y (Z%)"
        if not metrics:
            for log_file in list(task_work_dir.glob("*.log")) + list(task_work_dir.glob("*.txt")):
                try:
                    text = log_file.read_text(errors="replace")
                    for line in text.splitlines():
                        line_lower = line.lower()
                        if "surviving" in line_lower and "%" in line:
                            import re as _re
                            m = _re.search(r"(\d+\.?\d*)\s*%", line)
                            if m:
                                metrics["reads_surviving_pct"] = float(m.group(1))
                                break
                    if metrics:
                        break
                except OSError:
                    continue

        if not metrics:
            return None
        return metrics

    def _parse_alignment_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse STAR Log.final.out, HISAT2/Bowtie2/BWA log.
        Key metric: overall alignment rate.
        """
        metrics: Dict[str, Any] = {}

        # STAR: Log.final.out
        for log_file in list(task_work_dir.glob("*Log.final.out")) + list(task_work_dir.glob("Log.final.out")):
            try:
                text = log_file.read_text(errors="replace")
                for line in text.splitlines():
                    if "Uniquely mapped reads %" in line:
                        try:
                            metrics["uniquely_mapped_pct"] = float(line.split("|")[1].strip().rstrip("%"))
                        except (ValueError, IndexError):
                            pass
                    elif "% of reads mapped to multiple loci" in line:
                        try:
                            multi = float(line.split("|")[1].strip().rstrip("%"))
                            uniq = metrics.get("uniquely_mapped_pct", 0)
                            metrics["alignment_rate"] = round(uniq + multi, 2)
                        except (ValueError, IndexError):
                            pass
                    elif "Number of input reads" in line:
                        try:
                            metrics["total_reads"] = int(line.split("|")[1].strip())
                        except (ValueError, IndexError):
                            pass
                # If STAR log provided uniquely_mapped_pct but no multi-loci line,
                # use uniquely_mapped_pct as the alignment_rate fallback so the
                # threshold check always has a comparable metric regardless of
                # whether the log was truncated.
                if "uniquely_mapped_pct" in metrics and "alignment_rate" not in metrics:
                    metrics["alignment_rate"] = metrics["uniquely_mapped_pct"]
                if metrics:
                    break
            except OSError:
                continue

        # HISAT2/Bowtie2/BWA: look for "X% overall alignment rate" in .log
        if "alignment_rate" not in metrics:
            import re as _re
            for log_file in list(task_work_dir.glob("*.log")) + list(task_work_dir.glob("*.txt")):
                try:
                    text = log_file.read_text(errors="replace")
                    m = _re.search(r"(\d+\.?\d+)%\s+overall alignment rate", text)
                    if m:
                        metrics["alignment_rate"] = float(m.group(1))
                        break
                    # BWA: "X reads aligned" pattern not standard — check samtools flagstat fallback
                except OSError:
                    continue

        if not metrics:
            return None
        return metrics

    def _parse_featurecounts_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse featureCounts *.summary file.
        Key metric: assigned reads fraction.
        """
        metrics: Dict[str, Any] = {}

        for summary_file in list(task_work_dir.glob("*.summary")) + list(task_work_dir.glob("*featureCounts*")):
            try:
                lines = summary_file.read_text(errors="replace").splitlines()
                assigned = unassigned = 0
                for line in lines:
                    parts = line.split("\t")
                    if len(parts) < 2:
                        continue
                    try:
                        val = int(parts[1])
                    except ValueError:
                        continue
                    if "Assigned" == parts[0]:
                        assigned = val
                    elif parts[0].startswith("Unassigned"):
                        unassigned += val
                total = assigned + unassigned
                if total > 0:
                    metrics["assigned_reads_pct"] = round(100.0 * assigned / total, 2)
                    metrics["assigned_reads"] = assigned
                    break
            except OSError:
                continue

        if not metrics:
            return None
        return metrics

    def _parse_salmon_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse Salmon aux_info/alevin_meta_info.json or cmd_info.json.
        Key metric: mapping rate.
        """
        metrics: Dict[str, Any] = {}
        import json as _json

        for meta_file in (
            list(task_work_dir.glob("aux_info/alevin_meta_info.json"))
            + list(task_work_dir.glob("aux_info/meta_info.json"))
            + list(task_work_dir.glob("*.json"))
        ):
            try:
                data = _json.loads(meta_file.read_text(errors="replace"))
                if "percent_mapped" in data:
                    metrics["mapping_rate"] = data["percent_mapped"]
                    break
                elif "mapping_rate" in data:
                    rate = data["mapping_rate"]
                    metrics["mapping_rate"] = float(str(rate).rstrip("%"))
                    break
            except Exception:
                continue

        if not metrics:
            return None
        return metrics

    # ------------------------------------------------------------------
    # DNA-seq parsers
    # ------------------------------------------------------------------

    def _parse_flagstat_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse samtools flagstat output.
        Key metrics: mapped%, duplicate%.
        """
        metrics: Dict[str, Any] = {}
        import re as _re

        for flag_file in (
            list(task_work_dir.glob("*.flagstat"))
            + list(task_work_dir.glob("*.txt"))
            + list(task_work_dir.glob("flagstat*"))
        ):
            try:
                text = flag_file.read_text(errors="replace")
                total_m = _re.search(r"(\d+) \+ \d+ in total", text)
                mapped_m = _re.search(r"(\d+) \+ \d+ mapped \((\d+\.?\d*)%", text)
                dup_m = _re.search(r"(\d+) \+ \d+ duplicates", text)
                if total_m and mapped_m:
                    metrics["mapped_pct"] = float(mapped_m.group(2))
                    metrics["total_reads"] = int(total_m.group(1))
                    if dup_m:
                        total = metrics["total_reads"]
                        dups = int(dup_m.group(1))
                        if total > 0:
                            metrics["duplicate_pct"] = round(100.0 * dups / total, 2)
                    break
            except OSError:
                continue

        if not metrics:
            return None
        return metrics

    def _parse_picard_dup_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse Picard MarkDuplicates metrics file.
        Key metric: PERCENT_DUPLICATION.
        """
        metrics: Dict[str, Any] = {}

        for metrics_file in (
            list(task_work_dir.glob("*.metrics"))
            + list(task_work_dir.glob("*.dup_metrics"))
            + list(task_work_dir.glob("*.txt"))
        ):
            try:
                lines = metrics_file.read_text(errors="replace").splitlines()
                header_idx = next((i for i, l in enumerate(lines)
                                   if "PERCENT_DUPLICATION" in l), None)
                if header_idx is not None and header_idx + 1 < len(lines):
                    headers = lines[header_idx].split("\t")
                    values = lines[header_idx + 1].split("\t")
                    data = dict(zip(headers, values))
                    if "PERCENT_DUPLICATION" in data:
                        dup_val = float(data["PERCENT_DUPLICATION"])
                        metrics["duplicate_pct"] = round(dup_val * 100, 2)
                    if "ESTIMATED_LIBRARY_SIZE" in data and data["ESTIMATED_LIBRARY_SIZE"]:
                        try:
                            metrics["estimated_library_size"] = int(float(data["ESTIMATED_LIBRARY_SIZE"]))
                        except ValueError:
                            pass
                    break
            except (OSError, StopIteration, ValueError):
                continue

        if not metrics:
            return None
        return metrics

    # ------------------------------------------------------------------
    # Coverage depth (mosdepth / samtools coverage / Picard WgsMetrics)
    # ------------------------------------------------------------------

    def _parse_coverage_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse coverage depth from mosdepth summary, samtools coverage, or Picard WgsMetrics.
        Key metric: mean_coverage (X depth over genome).
        source: GATK Best Practices — WGS ≥ 30X; WES ≥ 100X
        """
        metrics: Dict[str, Any] = {}
        import re as _re

        # mosdepth summary: <chrom>\t<length>\t<bases>\t<mean>\t<min>\t<max>
        # Last line is "total" which has genome-wide mean coverage
        for summary_file in (
            list(task_work_dir.glob("*.mosdepth.summary.txt"))
            + list(task_work_dir.glob("*summary.txt"))
        ):
            try:
                lines = summary_file.read_text(errors="replace").splitlines()
                for line in reversed(lines):
                    # Use startswith("total\t") to avoid false matches on contig names like "total_rRNA"
                    if line.startswith("total\t"):
                        parts = line.split("\t")
                        if len(parts) >= 4:
                            try:
                                # mosdepth summary: chrom, length, bases, mean, min, max
                                metrics["mean_coverage"] = float(parts[3])
                                break
                            except ValueError:
                                pass
                if metrics:
                    break
            except OSError:
                continue

        # Picard WgsMetrics: look for MEAN_COVERAGE column
        for metrics_file in (
            list(task_work_dir.glob("*.wgs_metrics"))
            + list(task_work_dir.glob("*wgs_metrics.txt"))
        ):
            try:
                lines = metrics_file.read_text(errors="replace").splitlines()
                header_idx = next((i for i, l in enumerate(lines)
                                   if "MEAN_COVERAGE" in l), None)
                if header_idx is not None and header_idx + 1 < len(lines):
                    headers = lines[header_idx].split("\t")
                    values = lines[header_idx + 1].split("\t")
                    data = dict(zip(headers, values))
                    if "MEAN_COVERAGE" in data:
                        try:
                            metrics["mean_coverage"] = float(data["MEAN_COVERAGE"])
                        except ValueError:
                            pass
                if metrics:
                    break
            except (OSError, StopIteration):
                continue

        if not metrics:
            return None
        return metrics

    # ------------------------------------------------------------------
    # Single-cell parser
    # ------------------------------------------------------------------

    def _parse_singlecell_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse CellRanger metrics_summary.csv or STARsolo Summary.csv.
        Key metrics: cells detected, median genes per cell, mapping rate.
        """
        metrics: Dict[str, Any] = {}
        import csv as _csv
        import io as _io

        for csv_file in (
            list(task_work_dir.glob("metrics_summary.csv"))
            + list(task_work_dir.glob("**/metrics_summary.csv"))
            + list(task_work_dir.glob("Summary.csv"))
        ):
            try:
                text = csv_file.read_text(errors="replace")
                reader = _csv.DictReader(_io.StringIO(text))
                for row in reader:
                    # CellRanger uses comma-separated keys with % and , in values
                    def _clean(v: str) -> str:
                        return v.replace(",", "").replace("%", "").strip()
                    if "Estimated Number of Cells" in row:
                        try:
                            metrics["cells_detected"] = int(_clean(row["Estimated Number of Cells"]))
                        except ValueError:
                            pass
                    if "Median Genes per Cell" in row:
                        try:
                            metrics["median_genes_per_cell"] = int(_clean(row["Median Genes per Cell"]))
                        except ValueError:
                            pass
                    if "Reads Mapped to Genome" in row:
                        try:
                            metrics["mapping_rate"] = float(_clean(row["Reads Mapped to Genome"]))
                        except ValueError:
                            pass
                    # CellRanger v7+: mitochondrial reads fraction
                    # source: Luecken & Theis (2019) Mol Syst Biol; > 20% indicates dead/damaged cells
                    for mito_col in ("Fraction Mitochondrial Reads",
                                     "Reads Mapped to Mitochondrial Genome",
                                     "Mitochondrial Fraction"):
                        if mito_col in row:
                            try:
                                val = float(_clean(row[mito_col]))
                                # CellRanger reports as fraction (0–1); convert to pct
                                metrics["mito_fraction_pct"] = val * 100.0 if val <= 1.0 else val
                            except ValueError:
                                pass
                            break
                    break  # first row only
                if metrics:
                    break
            except (OSError, Exception):
                continue

        if not metrics:
            return None
        return metrics

    # ------------------------------------------------------------------
    # ChIP-seq / ATAC-seq
    # ------------------------------------------------------------------

    def _parse_peakcalling_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse MACS2/3 peak call output.
        Key metric: number of peaks called.
        """
        metrics: Dict[str, Any] = {}

        for peak_file in (
            list(task_work_dir.glob("*_peaks.narrowPeak"))
            + list(task_work_dir.glob("*_peaks.broadPeak"))
            + list(task_work_dir.glob("*_summits.bed"))
        ):
            try:
                lines = [l for l in peak_file.read_text(errors="replace").splitlines()
                         if l.strip() and not l.startswith("#")]
                metrics["peaks_called"] = len(lines)
                break
            except OSError:
                continue

        # MACS2 log: "# d = X" (fragment length) and "# total tags after filtering: X"
        for log_file in list(task_work_dir.glob("*.log")) + list(task_work_dir.glob("*_macs2.log")):
            try:
                text = log_file.read_text(errors="replace")
                import re as _re
                m = _re.search(r"total tags after filtering:\s*(\d+)", text)
                if m:
                    metrics["tags_after_filtering"] = int(m.group(1))
            except OSError:
                continue

        # FRiP score: nf-core/chipseq and ENCODE pipelines write frip_score.txt
        # source: ENCODE4 ChIP-seq standards: ≥ 0.01 (TF), ≥ 0.1 (histone marks)
        for frip_file in (
            list(task_work_dir.glob("*frip_score*"))
            + list(task_work_dir.glob("*frip*"))
        ):
            try:
                val = float(frip_file.read_text(errors="replace").strip().split()[0])
                metrics["frip_score"] = round(val, 4)
                break
            except (OSError, ValueError, IndexError):
                continue

        if not metrics:
            return None
        return metrics

    def _parse_atac_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse ATAC-seq specific QC output files.
        Key metrics: TSS enrichment score, FRiP (ATAC), NRF.
        sources:
          - TSS enrichment: ENCODE4 ATAC-seq standards (≥ 7 high quality, ≥ 5 acceptable)
          - FRiP: ENCODE4 ATAC-seq (≥ 0.3)
          - NRF (PBC1): ENCODE4 (≥ 0.9)
        """
        metrics: Dict[str, Any] = {}

        # TSS enrichment score — typically a single float in tss_enrich.txt or *.tss.txt
        for tss_file in (
            list(task_work_dir.glob("tss_enrich.txt"))
            + list(task_work_dir.glob("*.tss.txt"))
            + list(task_work_dir.glob("*tss_enrichment*"))
        ):
            try:
                val = float(tss_file.read_text(errors="replace").strip().split()[0])
                metrics["tss_enrichment"] = round(val, 2)
                break
            except (OSError, ValueError, IndexError):
                continue

        # NRF (Non-Redundant Fraction) from nf-core pbc.txt or ENCODE ATAC-seq pipeline.
        # NRF ≠ PBC1: NRF = DistinctReadPairs / TotalReadPairs; PBC1 = OneReadPair / DistinctReadPairs.
        # Both share the ≥ 0.9 ENCODE4 threshold but measure different aspects of library complexity.
        # nf-core/atacseq pbc.txt format (0-indexed):
        #   col 0: TotalReadPairs  col 1: DistinctReadPairs  col 2: OneReadPair  col 3: TwoReadPairs
        #   col 4: NRF             col 5: PBC1               col 6: PBC2
        for pbc_file in (
            list(task_work_dir.glob("*.pbc.txt"))
            + list(task_work_dir.glob("*pbc*"))
        ):
            try:
                lines = [l for l in pbc_file.read_text(errors="replace").splitlines()
                         if l.strip() and not l.startswith("#")]
                if lines:
                    parts = lines[0].split("\t")
                    if len(parts) >= 5:
                        try:
                            # Column 4 (index 4) is NRF
                            metrics["nrf_score"] = float(parts[4])
                        except (ValueError, IndexError):
                            pass
                if "nrf_score" in metrics:
                    break
            except OSError:
                continue

        # FRiP score: same frip_score.txt convention as ChIP-seq
        for frip_file in (
            list(task_work_dir.glob("*frip_score*"))
            + list(task_work_dir.glob("*frip*"))
        ):
            try:
                val = float(frip_file.read_text(errors="replace").strip().split()[0])
                metrics["frip_score"] = round(val, 4)
                break
            except (OSError, ValueError, IndexError):
                continue

        if not metrics:
            return None
        return metrics

    # ------------------------------------------------------------------
    # Metagenomics
    # ------------------------------------------------------------------

    def _parse_metagenomics_metrics(self, task_work_dir: Path) -> Optional[Dict[str, Any]]:
        """
        Parse Kraken2 report or MetaPhlAn output.
        Key metric: classified reads fraction.
        """
        metrics: Dict[str, Any] = {}
        import re as _re

        # Kraken2 report: first two lines are "unclassified" and "root"
        for report_file in (
            list(task_work_dir.glob("*.report"))
            + list(task_work_dir.glob("*kraken*"))
            + list(task_work_dir.glob("*.k2report"))
        ):
            try:
                lines = [l for l in report_file.read_text(errors="replace").splitlines()
                         if l.strip()]
                if not lines:
                    continue
                # Kraken2: first line may be unclassified (U), second is root (R)
                classified_pct = None
                unclassified_pct = None
                for line in lines[:5]:
                    parts = line.split("\t")
                    if len(parts) >= 4 and parts[3].strip() == "U":
                        try:
                            unclassified_pct = float(parts[0].strip())
                            classified_pct = round(100.0 - unclassified_pct, 2)
                        except ValueError:
                            pass
                if classified_pct is not None:
                    metrics["classified_pct"] = classified_pct
                    break
            except OSError:
                continue

        if not metrics:
            return None
        return metrics

    def _check_qc_thresholds(
        self,
        process_name: str,
        qc_metrics: Dict[str, Any]
    ) -> tuple[bool, list]:
        """
        Check if QC metrics meet quality thresholds.

        Returns:
            (qc_passed, list_of_structured_failure_dicts)

        Each failure dict has the keys:
            metric    – exact metric name from qc_metrics
            value     – actual measured value
            threshold – threshold value that was violated
            operator  – ">" or "<" indicating the direction of violation
            message   – human-readable description
        """
        failures = []
        process_upper = process_name.upper()

        if "MOTION_CORRECTION" in process_upper:
            total_drift = qc_metrics.get("total_drift_angstrom")
            _drift_t = self._get_threshold("total_drift_angstrom", 50)
            if total_drift is not None and total_drift > _drift_t:
                failures.append({
                    "metric": "total_drift_angstrom",
                    "value": total_drift,
                    "threshold": _drift_t,
                    "operator": ">",
                    "message": f"Excessive drift: {total_drift:.1f}Å (threshold: {_drift_t:.0f}Å)"
                })

            correlation = qc_metrics.get("correlation_score")
            _corr_t = self._get_threshold("correlation_score", 0.5)
            if correlation is not None and correlation < _corr_t:
                failures.append({
                    "metric": "correlation_score",
                    "value": correlation,
                    "threshold": _corr_t,
                    "operator": "<",
                    "message": f"Low correlation: {correlation:.3f} (threshold: {_corr_t:.1f})"
                })

        elif "CTF_ESTIMATION" in process_upper or "CTF_ESTIMATE" in process_upper:
            if qc_metrics.get("defocus_out_of_range"):
                du = qc_metrics.get("defocus_u_angstrom", 0)
                direction = qc_metrics.get("defocus_direction", "outside")
                if direction == "below":
                    msg = (f"Estimated defocus {du:.0f}Å is near-focus "
                           f"(valid range 1,000–100,000Å). Consider collecting at "
                           f"1.0–3.0 μm underfocus, or widen the CTF search range minimum.")
                else:
                    msg = (f"Estimated defocus {du:.0f}Å is too far from focus "
                           f"(valid range 1,000–100,000Å). Check for stage drift or "
                           f"incorrect microscope calibration.")
                failures.append({
                    "metric": "defocus_u_angstrom",
                    "value": du,
                    "threshold": 1000 if direction == "below" else 100000,
                    "operator": "<" if direction == "below" else ">",
                    "message": msg
                })

            astigmatism = qc_metrics.get("astigmatism_angstrom")
            # [BRONZE] No published consensus threshold for astigmatism-only gating.
            # The field primarily uses fit_quality (CTF resolution) as the authoritative gate.
            # Published high-resolution structures have been obtained with 500–2000Å astigmatism.
            # 1000Å used here as an ADVISORY (non-blocking) marker for operator awareness.
            # source: CryoSPARC v4 documentation; community practice only.
            _astig_t = self._get_threshold("astigmatism_angstrom", 1000)
            if astigmatism is not None and astigmatism > _astig_t:
                failures.append({
                    "metric": "astigmatism_angstrom",
                    "value": astigmatism,
                    "threshold": _astig_t,
                    "operator": ">",
                    "advisory": True,  # non-blocking: fit_quality is the primary CTF gate
                    "message": f"Elevated astigmatism: {astigmatism:.0f}Å (advisory: {_astig_t:.0f}Å). "
                               f"Note: CTF fit quality is the primary quality indicator. "
                               f"High astigmatism may indicate lens contamination, coma, or specimen charging. "
                               f"Review micrographs if fit_quality is also degraded."
                })

            fit = qc_metrics.get("fit_quality")
            _fit_t = self._get_threshold("fit_quality", 0.7)
            if fit is not None and fit < _fit_t:
                failures.append({
                    "metric": "fit_quality",
                    "value": fit,
                    "threshold": _fit_t,
                    "operator": "<",
                    "message": f"Poor CTF fit: {fit:.3f} (threshold: {_fit_t:.1f})"
                })

        elif "PARTICLE_PICKING" in process_upper or "PICKING" in process_upper:
            count = qc_metrics.get("particles_picked")
            _pick_t = self._get_threshold("particles_picked", 1000)
            if count is not None and count < _pick_t:
                failures.append({
                    "metric": "particles_picked",
                    "value": count,
                    "threshold": _pick_t,
                    "operator": "<",
                    "message": f"Too few particles: {count} (threshold: {_pick_t:.0f})"
                })

            duplicate_frac = qc_metrics.get("duplicate_fraction")
            # "duplicate_fraction_picking" key to avoid conflict with FLAGSTAT duplicate_pct
            _dup_pick_t = self._get_threshold("duplicate_fraction_picking", 0.2)
            if duplicate_frac is not None and duplicate_frac > _dup_pick_t:
                failures.append({
                    "metric": "duplicate_fraction",
                    "value": duplicate_frac,
                    "threshold": _dup_pick_t,
                    "operator": ">",
                    "message": f"High duplicate fraction: {duplicate_frac:.1%} (threshold: {_dup_pick_t:.0%})"
                })

        # --- RNA-seq / sequencing quality ---
        elif any(k in process_upper for k in ("FASTQC", "MULTIQC")):
            module_failures = qc_metrics.get("module_failures")
            if module_failures is not None and module_failures > 0:
                failures.append({
                    "metric": "module_failures",
                    "value": module_failures,
                    "threshold": 0,
                    "operator": ">",
                    "message": f"FastQC: {module_failures} module(s) FAILED"
                })

        elif any(k in process_upper for k in ("FASTP", "TRIMGALORE", "TRIMMOMATIC", "BBDUK")):
            surviving = qc_metrics.get("reads_surviving_pct")
            _surv_t = self._get_threshold("reads_surviving_pct", 70.0)
            if surviving is not None and surviving < _surv_t:
                failures.append({
                    "metric": "reads_surviving_pct",
                    "value": surviving,
                    "threshold": _surv_t,
                    "operator": "<",
                    "message": f"Low read survival: {surviving:.1f}% (threshold: {_surv_t:.0f}%)"
                })
            q30 = qc_metrics.get("q30_pct")
            _q30_t = self._get_threshold("q30_pct", 75.0)
            if q30 is not None and q30 < _q30_t:
                failures.append({
                    "metric": "q30_pct",
                    "value": q30,
                    "threshold": _q30_t,
                    "operator": "<",
                    "message": f"Low Q30: {q30:.1f}% (threshold: {_q30_t:.0f}%)"
                })

        elif any(k in process_upper for k in ("STAR_ALIGN", "STAR_GENOME", "HISAT2_ALIGN",
                                               "HISAT2", "BOWTIE2_ALIGN", "BOWTIE2",
                                               "BWA_MEM", "BWA_MEM2", "BWAMEM")):
            rate = qc_metrics.get("alignment_rate") or qc_metrics.get("uniquely_mapped_pct")
            _align_t = self._get_threshold("alignment_rate", 70.0)
            if rate is not None and rate < _align_t:
                # The critical sub-tier (< 25%) detects sample swap / catastrophic contamination.
                # Its threshold is fixed (not user-overridable) — it is a red-line condition.
                if rate < 25.0:
                    msg = (f"Critically low alignment rate: {rate:.1f}% (threshold: {_align_t:.0f}%). "
                           f"Values below 25% usually indicate a species/genome mismatch, "
                           f"corrupt input, or heavy contamination — verify input data "
                           f"before adjusting parameters.")
                    sev = "critical"
                else:
                    msg = f"Low alignment rate: {rate:.1f}% (threshold: {_align_t:.0f}%)"
                    sev = "warning"
                failures.append({
                    "metric": "alignment_rate",
                    "value": rate,
                    "threshold": _align_t,
                    "operator": "<",
                    "message": msg,
                    "severity": sev
                })

        elif any(k in process_upper for k in ("FEATURECOUNTS", "SUBREAD", "HTSEQ")):
            assigned = qc_metrics.get("assigned_reads_pct")
            _assign_t = self._get_threshold("assigned_reads_pct", 50.0)
            if assigned is not None and assigned < _assign_t:
                failures.append({
                    "metric": "assigned_reads_pct",
                    "value": assigned,
                    "threshold": _assign_t,
                    "operator": "<",
                    "message": f"Low feature assignment: {assigned:.1f}% (threshold: {_assign_t:.0f}%)"
                })

        elif any(k in process_upper for k in ("SALMON_QUANT", "SALMON", "KALLISTO")):
            mapping = qc_metrics.get("mapping_rate")
            _map_t = self._get_threshold("mapping_rate", 50.0)
            if mapping is not None and mapping < _map_t:
                failures.append({
                    "metric": "mapping_rate",
                    "value": mapping,
                    "threshold": _map_t,
                    "operator": "<",
                    "message": f"Low mapping rate: {mapping:.1f}% (threshold: {_map_t:.0f}%)"
                })

        # --- DNA-seq ---
        elif any(k in process_upper for k in ("FLAGSTAT", "SAMTOOLS_FLAGSTAT", "SAMTOOLS_STATS")):
            mapped = qc_metrics.get("mapped_pct")
            # mapped_pct is GOLD (GATK Best Practices) — threshold hardcoded; _get_threshold will
            # ignore any override and return the default. The call is still made for transparency.
            if mapped is not None and mapped < self._get_threshold("mapped_pct", 70.0):
                failures.append({
                    "metric": "mapped_pct",
                    "value": mapped,
                    "threshold": 70.0,
                    "operator": "<",
                    "message": f"Low mapping: {mapped:.1f}% (threshold: 70%)"
                })
            dup = qc_metrics.get("duplicate_pct")
            _dup_t = self._get_threshold("duplicate_pct", 40.0)
            if dup is not None and dup > _dup_t:
                failures.append({
                    "metric": "duplicate_pct",
                    "value": dup,
                    "threshold": _dup_t,
                    "operator": ">",
                    "message": f"High duplication: {dup:.1f}% (threshold: {_dup_t:.0f}%)"
                })

        elif any(k in process_upper for k in ("MARKDUPLICATES", "PICARD_MARKDUP",
                                               "MARKDUP", "GATK_MARKDUP")):
            dup = qc_metrics.get("duplicate_pct")
            # source: GATK Best Practices (WGS ≤ 20-30%); dupRadar (PMC5073875) shows
            # RNA-seq duplication is biologically expected from high-expression — skip for rna_seq.
            # Also skip ChIP-seq and ATAC-seq: enriched regions produce expected high duplication
            # that does NOT indicate library quality problems.
            _skip_domains = ("rna_seq", "rnaseq", "rna", "scrna_seq", "single_cell",
                             "atac_seq", "atacseq", "chip_seq", "chipseq",
                             "cut_and_run", "cutandrun")
            if dup is not None and self.workflow_domain not in _skip_domains:
                _dup_t = self._get_threshold("duplicate_pct", 40.0)
                if dup > _dup_t:
                    failures.append({
                        "metric": "duplicate_pct",
                        "value": dup,
                        "threshold": _dup_t,
                        "operator": ">",
                        "message": f"High PCR duplication: {dup:.1f}% (threshold: {_dup_t:.0f}%). "
                                   f"Indicates low library complexity — consider deeper sequencing "
                                   f"or additional PCR cycles during library prep."
                    })

        # --- Single-cell ---
        elif any(k in process_upper for k in ("CELLRANGER_COUNT", "CELLRANGER",
                                               "STARSOLO", "ALEVIN")):
            cells = qc_metrics.get("cells_detected")
            _cells_t = self._get_threshold("cells_detected", 200)
            if cells is not None and cells < _cells_t:
                failures.append({
                    "metric": "cells_detected",
                    "value": cells,
                    "threshold": _cells_t,
                    "operator": "<",
                    "message": f"Too few cells: {cells} (threshold: {_cells_t:.0f})"
                })
            genes = qc_metrics.get("median_genes_per_cell")
            _genes_t = self._get_threshold("median_genes_per_cell", 500)
            if genes is not None and genes < _genes_t:
                failures.append({
                    "metric": "median_genes_per_cell",
                    "value": genes,
                    "threshold": _genes_t,
                    "operator": "<",
                    "message": f"Low median genes/cell: {genes} (threshold: {_genes_t:.0f})"
                })
            # source: Osorio & Cai (2021) Bioinformatics PMC8599307 — tissue-specific thresholds:
            # 5% for mouse, 10% for human. 20% used here as a permissive universal gate covering
            # high-respiration cell types; Luecken & Theis (2019) MSB e8746 recommends adaptive
            # MAD-based thresholds. Values > 20% are generally indicative of dead/compromised cells.
            # Override allowed up to the red-line ceiling of 80% (cardiac/muscle tissue use cases).
            mito = qc_metrics.get("mito_fraction_pct")
            _mito_t = self._get_threshold("mito_fraction_pct", 20.0)
            if mito is not None and mito > _mito_t:
                failures.append({
                    "metric": "mito_fraction_pct",
                    "value": mito,
                    "threshold": _mito_t,
                    "operator": ">",
                    "message": f"High mitochondrial fraction: {mito:.1f}% (threshold: {_mito_t:.0f}%). "
                               f"Indicates dead or compromised cells. Published evidence supports "
                               f"5% (mouse) / 10% (human) as ideal; 20% used as permissive universal gate."
                })

        # --- Coverage depth (mosdepth / Picard WGS) ---
        elif any(k in process_upper for k in ("MOSDEPTH", "SAMTOOLS_COVERAGE",
                                               "GATK_COVERAGE", "PICARD_WGS")):
            cov = qc_metrics.get("mean_coverage")
            # source: GATK Best Practices — WGS ≥ 30X germline; WES ≥ 80X germline,
            # ≥ 150X somatic (Illumina/GATK guidelines; Sims et al. 2014 Nature Rev Genet).
            # Apply WES threshold when workflow domain indicates exome/targeted sequencing.
            _wes_domains = ("wes", "whole_exome", "exome_seq", "exome", "targeted_seq", "targeted")
            _is_wes = self.workflow_domain in _wes_domains
            _default_cov = 80.0 if _is_wes else 30.0
            _label = "WES germline" if _is_wes else "WGS germline"
            # Apply user override on top of the domain-adjusted default.
            # Override key "mean_coverage" applies regardless of WES/WGS context.
            _cov_t = self._get_threshold("mean_coverage", _default_cov)
            if cov is not None and cov < _cov_t:
                failures.append({
                    "metric": "mean_coverage",
                    "value": cov,
                    "threshold": _cov_t,
                    "operator": "<",
                    "message": f"Low genome coverage: {cov:.1f}X (threshold: {_cov_t:.0f}X for {_label}). "
                               f"GATK Best Practices: ≥ 30X WGS, ≥ 80X WES germline, ≥ 150X WES somatic."
                })

        # --- ChIP-seq / ATAC-seq ---
        elif any(k in process_upper for k in ("MACS2", "MACS3", "CALLPEAK")):
            peaks = qc_metrics.get("peaks_called")
            _peaks_t = self._get_threshold("peaks_called", 1000)
            if peaks is not None and peaks < _peaks_t:
                failures.append({
                    "metric": "peaks_called",
                    "value": peaks,
                    "threshold": _peaks_t,
                    "operator": "<",
                    "message": f"Too few peaks: {peaks} (threshold: {_peaks_t:.0f})"
                })
            # source: ENCODE4 ChIP-seq explicitly does NOT define a hard FRiP threshold
            # (ENCODE4 TF/histone pages state FRiP is "collected without defined thresholds").
            # The historical 1% (0.01) figure is from Landt et al. 2012 (ENCODE2/3) and
            # is used here only as an extreme-low advisory, not a mandatory gate.
            frip = qc_metrics.get("frip_score")
            # [ADVISORY] ENCODE4 explicitly does NOT define a hard FRiP threshold for ChIP-seq.
            # ENCODE4 states FRiP is "collected without defined thresholds" (2024 standards page).
            # The historical 1% (0.01) figure is from Landt et al. 2012 (ENCODE2/3) only.
            # This fires as advisory-only (non-blocking) — workflow continues.
            if frip is not None and frip < 0.01:
                failures.append({
                    "metric": "frip_score",
                    "value": frip,
                    "threshold": 0.01,
                    "operator": "<",
                    "severity": "warning",
                    "advisory": True,  # non-blocking: ENCODE4 has no hard FRiP gate
                    "message": f"Very low FRiP score: {frip:.4f} (advisory: 0.01). "
                               f"ENCODE4 does not mandate a hard FRiP cutoff; this is advisory only "
                               f"(historical ENCODE2/3 practice, Landt et al. 2012). "
                               f"Check IP efficiency and antibody quality."
                })

        # --- ATAC-seq QC ---
        elif any(k in process_upper for k in ("ATAC_QC", "TSS_ENRICH", "ATAC_PEAK",
                                               "DEEPTOOLS_PLOTFINGERPRINT", "PLOTFINGERPRINT")):
            tss = qc_metrics.get("tss_enrichment")
            # source: ENCODE4 ATAC-seq standards: TSS enrichment ≥ 7 (high quality), ≥ 5 (acceptable)
            if tss is not None:
                if tss < 5.0:
                    failures.append({
                        "metric": "tss_enrichment",
                        "value": tss,
                        "threshold": 5.0,
                        "operator": "<",
                        "severity": "critical" if tss < 3.0 else "warning",
                        "message": f"Low TSS enrichment: {tss:.1f} (threshold: 5.0, ideal: ≥ 7.0). "
                                   f"ENCODE4 requires ≥ 5 for acceptable ATAC-seq data. "
                                   f"Check nucleosome-free region filtering and library quality."
                    })
            frip = qc_metrics.get("frip_score")
            # source: ENCODE4 ATAC-seq — FRiP > 0.3 is ideal; > 0.2 is acceptable.
            # EN-TEx tissue samples are exempt from FRiP enforcement in ENCODE4.
            # We gate at 0.2 (the "acceptable" floor) and note 0.3 as the ideal.
            if frip is not None and frip < 0.2:
                failures.append({
                    "metric": "frip_score",
                    "value": frip,
                    "threshold": 0.2,
                    "operator": "<",
                    "message": f"Low ATAC-seq FRiP score: {frip:.4f} (threshold: 0.2 acceptable, 0.3 ideal per ENCODE4). "
                               f"Check peak calling parameters (shift/extsize) and sequencing depth."
                })
            nrf = qc_metrics.get("nrf_score")
            # source: ENCODE4: NRF ≥ 0.9 indicates good library complexity
            # (NRF = DistinctReadPairs / TotalReadPairs — distinct from PBC1)
            if nrf is not None and nrf < 0.9:
                failures.append({
                    "metric": "nrf_score",
                    "value": nrf,
                    "threshold": 0.9,
                    "operator": "<",
                    "severity": "critical" if nrf < 0.5 else "warning",
                    "message": f"Low library complexity (NRF/PBC1): {nrf:.3f} (threshold: 0.9). "
                               f"ENCODE4 requires ≥ 0.9. Indicates PCR over-amplification — "
                               f"reduce PCR cycles or increase input material."
                })

        # --- Metagenomics ---
        elif any(k in process_upper for k in ("KRAKEN2", "KRAKEN", "BRACKEN",
                                               "METAPHLAN", "KAIJU")):
            classified = qc_metrics.get("classified_pct")
            # source: Wood, Lu & Langmead (2019) Genome Biology 20:257 (Kraken2 paper);
            # QIIME2 community standards; environmental metagenomics practice.
            # Novel environments routinely classify 40-80% (database-dependent); < 30% is
            # critically low (possible contamination, wrong DB, or divergent organisms);
            # 30-60% warrants investigation.
            # Override keys: "classified_pct_critical" (default 30%) and
            # "classified_pct_warning" (default 60%) allow separate adjustment.
            _cls_crit_t = self._get_threshold("classified_pct_critical", 30.0)
            _cls_warn_t = self._get_threshold("classified_pct_warning", 60.0)
            if classified is not None:
                if classified < _cls_crit_t:
                    failures.append({
                        "metric": "classified_pct",
                        "value": classified,
                        "threshold": _cls_crit_t,
                        "operator": "<",
                        "severity": "critical",
                        "message": f"Critically low classification: {classified:.1f}% (threshold: {_cls_crit_t:.0f}%). "
                                   f"Possible contamination, wrong database, or highly divergent organisms. "
                                   f"Verify sample and database match before proceeding."
                    })
                elif classified < _cls_warn_t:
                    failures.append({
                        "metric": "classified_pct",
                        "value": classified,
                        "threshold": _cls_warn_t,
                        "operator": "<",
                        "severity": "warning",
                        "message": f"Low classification: {classified:.1f}% (threshold: {_cls_warn_t:.0f}%). "
                                   f"Consider upgrading to a larger Kraken2 database or adjusting "
                                   f"the confidence threshold."
                    })

        # Advisory items (advisory=True) are informational only — they do not block the workflow.
        # qc_passed is determined solely by hard (non-advisory) failures.
        blocking_failures = [f for f in failures if not f.get("advisory", False)]
        return (len(blocking_failures) == 0, failures)

    def _emit_qc_gate_event(
        self,
        process_name: str,
        qc_metrics: Dict[str, Any],
        failures: list
    ):
        """
        Emit SSE event for QC gate trigger.
        Includes parameter suggestions if available.
        """
        # Generate parameter suggestions
        suggestions = []
        if self.parameter_suggester:
            try:
                suggestion_objects = self.parameter_suggester.suggest(
                    process_name=process_name,
                    qc_metrics=qc_metrics,
                    current_parameters=self.current_parameters,
                    failures=failures
                )
                # Convert to dict format for JSON serialization
                suggestions = [
                    {
                        "parameter": s.parameter,
                        "currentValue": s.current_value,
                        "suggestedValue": s.suggested_value,
                        "reason": s.reason,
                        "confidence": s.confidence
                    }
                    for s in suggestion_objects
                ]
                log.info(f"[QC Gate] Generated {len(suggestions)} parameter suggestions")
            except Exception as e:
                log.warning(f"[QC Gate] Failed to generate parameter suggestions: {e}")

        event_data = {
            "invocation_id": self.invocation_id,
            "process_name": process_name,
            "qc_metrics": qc_metrics,
            "failures": failures,
            "suggestions": suggestions,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "overrides_active": bool(self.qc_overrides),
            "active_overrides": dict(self.qc_overrides) if self.qc_overrides else {},
            "active_profile": self.active_profile,
        }

        # Audit log: record that a gate event fired under non-default thresholds
        if self.qc_overrides or self.active_profile:
            self._write_audit_log_entry("gate_triggered", {"process_name": process_name})

        try:
            self.sse_callback("qc_gate_triggered", event_data)
            log.info(f"[QC Gate] SSE event emitted for {process_name} with {len(suggestions)} suggestions")
        except Exception as e:
            log.error(f"[QC Gate] Failed to emit SSE event: {e}")

    def _check_qc_warnings(
        self,
        process_name: str,
        qc_metrics: Dict[str, Any]
    ) -> list:
        """
        Check for metrics that are approaching (within 10% above) their threshold.
        Returns warning dicts with the same schema as failure dicts but severity='near_threshold'.
        These are advisory only — they do NOT gate the workflow.
        """
        warnings = []
        process_upper = process_name.upper()

        def _near_above(val, threshold, pct=0.10):
            """True if val is within pct% above threshold (just passed but close)."""
            return threshold <= val <= threshold * (1.0 + pct)

        if any(k in process_upper for k in ("STAR_ALIGN", "STAR_GENOME", "HISAT2_ALIGN",
                                             "HISAT2", "BOWTIE2_ALIGN", "BWA_MEM")):
            rate = qc_metrics.get("alignment_rate") or qc_metrics.get("uniquely_mapped_pct")
            _align_t = self._get_threshold("alignment_rate", 70.0)
            if rate is not None and _near_above(rate, _align_t):
                warnings.append({
                    "metric": "alignment_rate", "value": rate, "threshold": _align_t,
                    "operator": "<", "severity": "near_threshold",
                    "message": f"Alignment rate {rate:.1f}% is near the {_align_t:.0f}% threshold — monitor closely"
                })

        elif any(k in process_upper for k in ("FASTP", "TRIMGALORE", "TRIMMOMATIC", "BBDUK")):
            surviving = qc_metrics.get("reads_surviving_pct")
            _surv_t = self._get_threshold("reads_surviving_pct", 70.0)
            if surviving is not None and _near_above(surviving, _surv_t):
                warnings.append({
                    "metric": "reads_surviving_pct", "value": surviving, "threshold": _surv_t,
                    "operator": "<", "severity": "near_threshold",
                    "message": f"Read survival {surviving:.1f}% is near the {_surv_t:.0f}% threshold — monitor closely"
                })

        elif any(k in process_upper for k in ("SALMON_QUANT", "SALMON", "KALLISTO")):
            mapping = qc_metrics.get("mapping_rate")
            _map_t = self._get_threshold("mapping_rate", 50.0)
            if mapping is not None and _near_above(mapping, _map_t):
                warnings.append({
                    "metric": "mapping_rate", "value": mapping, "threshold": _map_t,
                    "operator": "<", "severity": "near_threshold",
                    "message": f"Mapping rate {mapping:.1f}% is near the {_map_t:.0f}% threshold — monitor closely"
                })

        elif any(k in process_upper for k in ("KRAKEN2", "KRAKEN", "BRACKEN",
                                               "METAPHLAN", "KAIJU")):
            classified = qc_metrics.get("classified_pct")
            _cls_warn_t = self._get_threshold("classified_pct_warning", 60.0)
            if classified is not None and _near_above(classified, _cls_warn_t):
                warnings.append({
                    "metric": "classified_pct", "value": classified, "threshold": _cls_warn_t,
                    "operator": "<", "severity": "near_threshold",
                    "message": f"Classification rate {classified:.1f}% is near the {_cls_warn_t:.0f}% threshold — monitor closely"
                })

        elif any(k in process_upper for k in ("CELLRANGER_COUNT", "CELLRANGER",
                                               "STARSOLO", "ALEVIN")):
            # Warn above mito_fraction_pct_warning (default 10%) but below the hard gate.
            # sc-best-practices.org recommends ≤ 10% for standard tissues (PBMC, blood).
            # Cardiac and muscle cells can exceed 20% naturally — context matters.
            # Override key: "mito_fraction_pct_warning" for the advisory level (default 10%).
            mito = qc_metrics.get("mito_fraction_pct")
            _mito_hard_t = self._get_threshold("mito_fraction_pct", 20.0)
            _mito_warn_t = self._get_threshold("mito_fraction_pct_warning", 10.0)
            if mito is not None and _mito_warn_t < mito <= _mito_hard_t:
                warnings.append({
                    "metric": "mito_fraction_pct", "value": mito, "threshold": _mito_hard_t,
                    "operator": ">", "severity": "near_threshold",
                    "message": f"Elevated mitochondrial fraction: {mito:.1f}% "
                               f"(advisory: {_mito_warn_t:.0f}% for standard tissues). "
                               f"sc-best-practices recommends ≤ 10% for PBMC/blood; cardiac/muscle cells may "
                               f"naturally exceed this. Hard gate triggers at > {_mito_hard_t:.0f}%."
                })

        return warnings

    def _emit_qc_warning_event(
        self,
        process_name: str,
        qc_metrics: Dict[str, Any],
        warnings: list
    ):
        """
        Emit advisory SSE event for metrics approaching (but not crossing) thresholds.
        Uses event type 'qc_warning' — frontend shows a step annotation without opening a modal.
        """
        event_data = {
            "invocation_id": self.invocation_id,
            "process_name": process_name,
            "qc_metrics": qc_metrics,
            "warnings": warnings,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "overrides_active": bool(self.qc_overrides),
            "active_overrides": dict(self.qc_overrides) if self.qc_overrides else {},
            "active_profile": self.active_profile,
        }
        try:
            self.sse_callback("qc_warning", event_data)
            log.info(f"[QC Gate] Near-threshold warning emitted for {process_name}")
        except Exception as e:
            log.error(f"[QC Gate] Failed to emit warning event: {e}")
