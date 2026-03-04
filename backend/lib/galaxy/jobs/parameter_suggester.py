"""
Parameter suggestion engine for workflow QC failures.

Analyzes QC metrics and suggests parameter adjustments to improve results.
Domain-specific suggesters provide tailored recommendations for different workflows.
"""
import logging
from typing import Dict, Any, List, Optional
from dataclasses import dataclass


@dataclass
class ParameterSuggestion:
    """A suggested parameter adjustment."""
    parameter: str
    current_value: Any
    suggested_value: Any
    reason: str
    confidence: float  # 0.0 to 1.0
    source: str = "rule"  # "rule" = empirical heuristic; "literature" = cites a paper/standard


class BaseParameterSuggester:
    """Base class for parameter suggestion engines."""

    def __init__(self, logger: Optional[logging.Logger] = None):
        self.logger = logger or logging.getLogger(__name__)

    def suggest(
        self,
        process_name: str,
        qc_metrics: Dict[str, Any],
        current_parameters: Dict[str, Any],
        failures: List[str]
    ) -> List[ParameterSuggestion]:
        """
        Generate parameter suggestions based on QC metrics.

        Args:
            process_name: Name of the failed process
            qc_metrics: Dictionary of QC metric name -> value
            current_parameters: Current parameter values
            failures: List of failure messages

        Returns:
            List of parameter suggestions
        """
        raise NotImplementedError("Subclasses must implement suggest()")


class CryoEMParameterSuggester(BaseParameterSuggester):
    """Parameter suggester for Cryo-EM SPA workflows."""

    def suggest(
        self,
        process_name: str,
        qc_metrics: Dict[str, Any],
        current_parameters: Dict[str, Any],
        failures: List[str]
    ) -> List[ParameterSuggestion]:
        """Generate Cryo-EM specific parameter suggestions."""
        suggestions = []
        # Use substring matching (same as QC gate handler) so that Nextflow-qualified
        # names like "NFCORE:MOTION_CORRECTION" are handled consistently.
        process_upper = process_name.upper()

        # Motion correction suggestions
        if 'MOTION_CORRECTION' in process_upper:
            suggestions.extend(self._suggest_motion_correction(qc_metrics, current_parameters))

        # CTF estimation suggestions
        elif 'CTF_ESTIMATION' in process_upper or 'CTF_ESTIMATE' in process_upper:
            suggestions.extend(self._suggest_ctf_estimation(qc_metrics, current_parameters))

        # Particle picking suggestions
        elif 'PARTICLE_PICKING' in process_upper or 'PICKING' in process_upper:
            suggestions.extend(self._suggest_particle_picking(qc_metrics, current_parameters))

        # 2D classification suggestions
        elif 'CLASSIFY_2D' in process_upper or '2D_CLASSIFICATION' in process_upper:
            suggestions.extend(self._suggest_2d_classification(qc_metrics, current_parameters))

        # Ab initio reconstruction suggestions
        elif 'AB_INITIO' in process_upper:
            suggestions.extend(self._suggest_ab_initio(qc_metrics, current_parameters))

        # Refinement suggestions
        elif 'REFINE' in process_upper:
            suggestions.extend(self._suggest_refinement(qc_metrics, current_parameters))

        return suggestions

    def _suggest_motion_correction(
        self,
        qc_metrics: Dict[str, Any],
        current_params: Dict[str, Any]
    ) -> List[ParameterSuggestion]:
        """Suggest motion correction parameter adjustments."""
        suggestions = []

        # Check total drift
        total_drift = qc_metrics.get('total_drift_angstrom', 0)
        if total_drift > 50:  # Excessive drift
            # Suggest enabling dose weighting if not enabled
            if not current_params.get('dose_weighting', False):
                suggestions.append(ParameterSuggestion(
                    parameter='dose_weighting',
                    current_value=False,
                    suggested_value=True,
                    reason=f'Excessive drift ({total_drift:.1f}Å). Dose weighting can improve motion correction.',
                    confidence=0.85
                ))

            # Suggest increasing patch size
            current_patch = current_params.get('patch_size', 3)
            if current_patch < 5:
                suggestions.append(ParameterSuggestion(
                    parameter='patch_size',
                    current_value=current_patch,
                    suggested_value=5,
                    reason=f'Excessive drift ({total_drift:.1f}Å). Larger patches can handle more motion.',
                    confidence=0.75
                ))

        # Check correlation score — skip entirely if metric is absent
        correlation = qc_metrics.get('correlation_score')
        if correlation is not None and correlation < 0.5:  # Low correlation
            current_frames = current_params.get('alignment_frames', 1)
            if current_frames < 3:
                suggestions.append(ParameterSuggestion(
                    parameter='alignment_frames',
                    current_value=current_frames,
                    suggested_value=3,
                    reason=f'Low correlation ({correlation:.2f}). More frames can improve alignment.',
                    confidence=0.70
                ))

        return suggestions

    def _suggest_ctf_estimation(
        self,
        qc_metrics: Dict[str, Any],
        current_params: Dict[str, Any]
    ) -> List[ParameterSuggestion]:
        """Suggest CTF estimation parameter adjustments."""
        suggestions = []

        # Check astigmatism — [BRONZE] no published consensus; 1000Å advisory threshold
        # (aligned with the advisory gate in qc_trace_monitor.py; fit_quality is primary gate)
        astigmatism = qc_metrics.get('astigmatism_angstrom', 0)
        if astigmatism > 1000:  # Elevated astigmatism (advisory; 1000Å threshold)
            # Suggest using CTF tilt search
            if not current_params.get('use_tilt_search', False):
                suggestions.append(ParameterSuggestion(
                    parameter='use_tilt_search',
                    current_value=False,
                    suggested_value=True,
                    reason=f'High astigmatism ({astigmatism:.0f}Å). Tilt search can better handle stage tilt.',
                    confidence=0.80
                ))

        # Check fit quality — skip entirely if metric is absent
        fit_quality = qc_metrics.get('fit_quality')
        if fit_quality is not None and fit_quality < 0.7:  # Poor fit
            current_min = current_params.get('defocus_min', 5000)
            current_max = current_params.get('defocus_max', 50000)
            if current_max - current_min < 30000:
                # Use a dict so the frontend can apply defocus_min and defocus_max separately
                suggestions.append(ParameterSuggestion(
                    parameter='defocus_search_range',
                    current_value={"defocus_min": current_min, "defocus_max": current_max},
                    suggested_value={"defocus_min": 5000, "defocus_max": 50000},
                    reason=f'Poor fit quality ({fit_quality:.2f}). Wider search range may improve fitting.',
                    confidence=0.75
                ))

        return suggestions

    def _suggest_particle_picking(
        self,
        qc_metrics: Dict[str, Any],
        current_params: Dict[str, Any]
    ) -> List[ParameterSuggestion]:
        """Suggest particle picking parameter adjustments."""
        suggestions = []

        # Check particle count — skip entirely if metric is absent
        particle_count = qc_metrics.get('particles_picked')
        if particle_count is not None and particle_count < 1000:
            current_threshold = current_params.get('picking_threshold', 0.5)
            if current_threshold > 0.3:
                suggestions.append(ParameterSuggestion(
                    parameter='picking_threshold',
                    current_value=current_threshold,
                    suggested_value=max(0.3, current_threshold - 0.1),
                    reason=f'Only {particle_count} particles picked. Lowering threshold picks more candidates — review class averages afterward.',
                    confidence=0.65
                ))

        # Check duplicate fraction — skip entirely if metric is absent
        duplicate_frac = qc_metrics.get('duplicate_fraction')
        if duplicate_frac is not None and duplicate_frac > 0.2:
            # Suggest increasing minimum separation
            current_sep = current_params.get('minimum_separation', 10)
            suggestions.append(ParameterSuggestion(
                parameter='minimum_separation',
                current_value=current_sep,
                suggested_value=current_sep + 10,
                reason=f'High duplicate rate ({duplicate_frac:.1%}). Increase separation to reduce overlaps.',
                confidence=0.80
            ))

        return suggestions

    def _suggest_2d_classification(
        self,
        qc_metrics: Dict[str, Any],
        current_params: Dict[str, Any]
    ) -> List[ParameterSuggestion]:
        """Suggest 2D classification parameter adjustments."""
        suggestions = []

        # Check if classes are converging — skip entirely if metric is absent
        class_convergence = qc_metrics.get('class_convergence')
        if class_convergence is not None and class_convergence < 0.8:
            # Suggest more iterations
            current_iterations = current_params.get('max_iterations', 20)
            if current_iterations < 30:
                suggestions.append(ParameterSuggestion(
                    parameter='max_iterations',
                    current_value=current_iterations,
                    suggested_value=30,
                    reason=f'Poor class convergence ({class_convergence:.2f}). More iterations may help.',
                    confidence=0.75
                ))

        return suggestions

    def _suggest_ab_initio(
        self,
        qc_metrics: Dict[str, Any],
        current_params: Dict[str, Any]
    ) -> List[ParameterSuggestion]:
        """Suggest ab initio reconstruction parameter adjustments."""
        suggestions = []

        # Check initial resolution — skip entirely if metric is absent
        initial_res = qc_metrics.get('initial_resolution')
        if initial_res is not None and initial_res > 20:  # Poor initial model
            # Suggest more classes to explore conformational space
            current_classes = current_params.get('num_classes', 1)
            if current_classes < 3:
                suggestions.append(ParameterSuggestion(
                    parameter='num_classes',
                    current_value=current_classes,
                    suggested_value=3,
                    reason=f'Poor initial resolution ({initial_res:.1f}Å). Multiple classes can help.',
                    confidence=0.70
                ))

        return suggestions

    def _suggest_refinement(
        self,
        qc_metrics: Dict[str, Any],
        current_params: Dict[str, Any]
    ) -> List[ParameterSuggestion]:
        """Suggest refinement parameter adjustments."""
        suggestions = []

        # Check FSC resolution — skip entirely if metric is absent
        fsc_resolution = qc_metrics.get('fsc_resolution')
        if fsc_resolution is not None and fsc_resolution > 5:  # Poor resolution
            # Suggest per-particle CTF refinement
            if not current_params.get('per_particle_ctf', False):
                suggestions.append(ParameterSuggestion(
                    parameter='per_particle_ctf',
                    current_value=False,
                    suggested_value=True,
                    reason=f'Resolution not improving ({fsc_resolution:.1f}Å). Per-particle CTF may help.',
                    confidence=0.80
                ))

        return suggestions


class RNASeqParameterSuggester(BaseParameterSuggester):
    """Parameter suggester for RNA-seq workflows."""

    def suggest(
        self,
        process_name: str,
        qc_metrics: Dict[str, Any],
        current_parameters: Dict[str, Any],
        failures: List[str]
    ) -> List[ParameterSuggestion]:
        """Generate RNA-seq specific parameter suggestions."""
        suggestions = []
        process_upper = process_name.upper()

        # Quality trimming suggestions (FASTP, TrimGalore, Trimmomatic)
        if any(k in process_upper for k in ('TRIM', 'FASTP', 'BBDUK', 'QC')):
            surviving = qc_metrics.get('reads_surviving_pct')
            if surviving is not None and surviving < 70.0:
                current_q = current_parameters.get('quality_cutoff', 20)
                if current_q < 25:
                    suggestions.append(ParameterSuggestion(
                        parameter='quality_cutoff',
                        current_value=current_q,
                        suggested_value=25,
                        reason=f'Only {surviving:.1f}% reads survived trimming. Stricter quality cutoff recommended.',
                        confidence=0.85
                    ))
            q30 = qc_metrics.get('q30_pct')
            if q30 is not None and q30 < 75.0:
                min_len = current_parameters.get('min_length', 36)
                if min_len > 20:
                    suggestions.append(ParameterSuggestion(
                        parameter='min_length',
                        current_value=min_len,
                        suggested_value=max(20, min_len - 5),
                        reason=f'Q30 rate {q30:.1f}% is low. Shorter minimum length retains more reads.',
                        confidence=0.65
                    ))

        # Alignment suggestions (STAR, HISAT2, Bowtie2, BWA)
        elif any(k in process_upper for k in ('STAR', 'HISAT2', 'BOWTIE2', 'BWA', 'ALIGN', 'MAP')):
            rate = qc_metrics.get('alignment_rate') or qc_metrics.get('uniquely_mapped_pct')
            if rate is not None and rate < 70.0:
                # Suggest checking genome/annotation compatibility
                two_pass = current_parameters.get('twopass_mode', False)
                if not two_pass and 'STAR' in process_upper:
                    suggestions.append(ParameterSuggestion(
                        parameter='twopass_mode',
                        current_value=False,
                        suggested_value=True,
                        reason=f'Alignment rate {rate:.1f}% is low. STAR two-pass mode improves novel splice detection.',
                        confidence=0.75,
                        source="literature"  # Dobin et al. (2013) Bioinformatics; nf-core/rnaseq default
                    ))
                mismatches = current_parameters.get('max_mismatches', 2)
                if mismatches < 3:
                    suggestions.append(ParameterSuggestion(
                        parameter='max_mismatches',
                        current_value=mismatches,
                        suggested_value=min(4, mismatches + 1),
                        reason=f'Alignment rate {rate:.1f}% is low. More mismatches may help divergent samples.',
                        confidence=0.65
                    ))

        # Feature counting suggestions
        elif any(k in process_upper for k in ('FEATURECOUNTS', 'HTSEQ', 'SUBREAD')):
            assigned = qc_metrics.get('assigned_reads_pct')
            if assigned is not None and assigned < 50.0:
                strandedness = current_parameters.get('strandedness', 0)
                if strandedness == 0:
                    suggestions.append(ParameterSuggestion(
                        parameter='strandedness',
                        current_value=0,
                        suggested_value=1,
                        reason=f'Only {assigned:.1f}% reads assigned. Check library strandedness — try sense (1) or antisense (2).',
                        confidence=0.70
                    ))

        # Salmon/Kallisto mapping suggestions
        elif any(k in process_upper for k in ('SALMON', 'KALLISTO')):
            mapping = qc_metrics.get('mapping_rate')
            if mapping is not None and mapping < 50.0:
                suggestions.append(ParameterSuggestion(
                    parameter='decoy_aware',
                    current_value=current_parameters.get('decoy_aware', False),
                    suggested_value=True,
                    reason=f'Mapping rate {mapping:.1f}% is low. Decoy-aware mapping reduces spurious alignments.',
                    confidence=0.75,
                    source="literature"  # Srivastava et al. (2020) Bioinformatics
                ))

        return suggestions


class GenomicsParameterSuggester(BaseParameterSuggester):
    """Parameter suggester for DNA-seq / variant calling workflows."""

    def suggest(
        self,
        process_name: str,
        qc_metrics: Dict[str, Any],
        current_parameters: Dict[str, Any],
        failures: List[str]
    ) -> List[ParameterSuggestion]:
        suggestions = []
        process_upper = process_name.upper()

        # Alignment
        if any(k in process_upper for k in ('BWA', 'BOWTIE2', 'ALIGN')):
            rate = qc_metrics.get('mapped_pct') or qc_metrics.get('alignment_rate')
            if rate is not None and rate < 70.0:
                suggestions.append(ParameterSuggestion(
                    parameter='min_seed_length',
                    current_value=current_parameters.get('min_seed_length', 19),
                    suggested_value=15,
                    reason=f'Mapped rate {rate:.1f}% is low. Shorter seed length increases sensitivity.',
                    confidence=0.70
                ))

        # Deduplication
        elif any(k in process_upper for k in ('MARKDUP', 'MARKDUPLICATES', 'PICARD')):
            dup = qc_metrics.get('duplicate_pct')
            if dup is not None and dup > 30.0:
                suggestions.append(ParameterSuggestion(
                    parameter='optical_duplicate_pixel_distance',
                    current_value=current_parameters.get('optical_duplicate_pixel_distance', 100),
                    suggested_value=2500,
                    reason=f'Duplication {dup:.1f}% is high. Increase optical duplicate distance for patterned flow cells.',
                    confidence=0.75
                ))

        # Flagstat quality
        elif any(k in process_upper for k in ('FLAGSTAT', 'SAMTOOLS')):
            dup = qc_metrics.get('duplicate_pct')
            if dup is not None and dup > 40.0:
                suggestions.append(ParameterSuggestion(
                    parameter='remove_duplicates',
                    current_value=current_parameters.get('remove_duplicates', False),
                    suggested_value=True,
                    reason=f'Duplication {dup:.1f}% exceeds 40% — consider removing duplicates for downstream analysis.',
                    confidence=0.80
                ))

        return suggestions


class SingleCellParameterSuggester(BaseParameterSuggester):
    """Parameter suggester for single-cell RNA-seq workflows."""

    def suggest(
        self,
        process_name: str,
        qc_metrics: Dict[str, Any],
        current_parameters: Dict[str, Any],
        failures: List[str]
    ) -> List[ParameterSuggestion]:
        suggestions = []
        process_upper = process_name.upper()

        if any(k in process_upper for k in ('CELLRANGER', 'STARSOLO', 'ALEVIN')):
            cells = qc_metrics.get('cells_detected')
            if cells is not None and cells < 200:
                current_expect = current_parameters.get('expected_cells', 3000)
                if current_expect > 500:
                    suggestions.append(ParameterSuggestion(
                        parameter='expected_cells',
                        current_value=current_expect,
                        suggested_value=max(200, cells * 3),
                        reason=f'Only {cells} cells detected. Lowering expected cells may improve detection in sparse samples.',
                        confidence=0.70
                    ))
                suggestions.append(ParameterSuggestion(
                    parameter='min_umi_cutoff',
                    current_value=current_parameters.get('min_umi_cutoff', 500),
                    suggested_value=100,
                    reason=f'Only {cells} cells detected. Lower UMI cutoff may recover low-quality cells for inspection.',
                    confidence=0.65
                ))

            genes = qc_metrics.get('median_genes_per_cell')
            if genes is not None and genes < 500:
                suggestions.append(ParameterSuggestion(
                    parameter='min_genes',
                    current_value=current_parameters.get('min_genes', 200),
                    suggested_value=100,
                    reason=f'Median genes/cell is {genes}. Lowering gene threshold may indicate data quality issues.',
                    confidence=0.60
                ))

        return suggestions


class ChIPSeqParameterSuggester(BaseParameterSuggester):
    """Parameter suggester for ChIP-seq / ATAC-seq workflows."""

    def suggest(
        self,
        process_name: str,
        qc_metrics: Dict[str, Any],
        current_parameters: Dict[str, Any],
        failures: List[str]
    ) -> List[ParameterSuggestion]:
        suggestions = []
        process_upper = process_name.upper()

        if any(k in process_upper for k in ('MACS2', 'MACS3', 'CALLPEAK')):
            peaks = qc_metrics.get('peaks_called')
            if peaks is not None and peaks < 1000:
                current_qval = current_parameters.get('qvalue', 0.05)
                if current_qval < 0.1:
                    suggestions.append(ParameterSuggestion(
                        parameter='qvalue',
                        current_value=current_qval,
                        suggested_value=min(0.1, current_qval * 2),
                        reason=f'Only {peaks} peaks called. Relaxing q-value threshold may recover weak peaks.',
                        confidence=0.70
                    ))
                extsize = current_parameters.get('extsize', 200)
                suggestions.append(ParameterSuggestion(
                    parameter='extsize',
                    current_value=extsize,
                    suggested_value=150,
                    reason=f'Low peak count ({peaks}). Shorter extension size may improve narrow peak detection.',
                    confidence=0.60
                ))

        elif any(k in process_upper for k in ('ATAC_QC', 'TSS_ENRICH', 'PLOTFINGERPRINT')):
            # ATAC-seq specific suggestions
            # source: ENCODE4 ATAC-seq standards; Corces et al. (2017) Nature Methods
            tss = qc_metrics.get('tss_enrichment')
            if tss is not None and tss < 5.0:
                # Suggest filtering fragments to NFR (< 200 bp) for better TSS enrichment
                current_min_len = current_parameters.get('min_fragment_length', 0)
                if current_min_len > 150:  # Already filtered; suggest algo change
                    suggestions.append(ParameterSuggestion(
                        parameter='min_fragment_length',
                        current_value=current_min_len,
                        suggested_value=0,
                        reason=f'Low TSS enrichment ({tss:.1f}). Including all fragment sizes may improve TSS signal.',
                        confidence=0.65
                    ))
                suggestions.append(ParameterSuggestion(
                    parameter='shift',
                    current_value=current_parameters.get('shift', 0),
                    suggested_value=-100,
                    reason=f'Low TSS enrichment ({tss:.1f}). ATAC-seq shift of -100 bp centers reads on Tn5 cut sites.',
                    confidence=0.75,
                    source="literature"  # ENCODE4; Corces et al. (2017) Nat Methods
                ))
                suggestions.append(ParameterSuggestion(
                    parameter='extsize',
                    current_value=current_parameters.get('extsize', 200),
                    suggested_value=200,
                    reason=f'Low TSS enrichment ({tss:.1f}). ATAC-seq extsize of 200 bp is standard for open chromatin.',
                    confidence=0.70,
                    source="literature"  # ENCODE4 ATAC-seq standards
                ))

            nrf = qc_metrics.get('nrf_score')
            if nrf is not None and nrf < 0.9:
                # Low library complexity — suggest reducing PCR cycles
                current_cycles = current_parameters.get('pcr_cycles', 12)
                if current_cycles > 8:
                    suggestions.append(ParameterSuggestion(
                        parameter='pcr_cycles',
                        current_value=current_cycles,
                        suggested_value=max(8, current_cycles - 4),
                        reason=f'Low library complexity (NRF={nrf:.3f}). Fewer PCR cycles reduce optical duplicates.',
                        confidence=0.70,
                        source="literature"  # ENCODE4 library complexity standards
                    ))

        return suggestions


class MetagenomicsParameterSuggester(BaseParameterSuggester):
    """Parameter suggester for metagenomics workflows."""

    def suggest(
        self,
        process_name: str,
        qc_metrics: Dict[str, Any],
        current_parameters: Dict[str, Any],
        failures: List[str]
    ) -> List[ParameterSuggestion]:
        suggestions = []
        process_upper = process_name.upper()

        if any(k in process_upper for k in ('KRAKEN2', 'KRAKEN', 'BRACKEN', 'METAPHLAN', 'KAIJU')):
            classified = qc_metrics.get('classified_pct')
            if classified is not None and classified < 60.0:
                # Suggest for both critical (< 30%) and warning (30–60%) zones
                confidence_threshold = current_parameters.get('confidence_threshold', 0.1)
                if confidence_threshold > 0.0:
                    suggestions.append(ParameterSuggestion(
                        parameter='confidence_threshold',
                        current_value=confidence_threshold,
                        suggested_value=0.0,
                        reason=(f'Only {classified:.1f}% reads classified. Removing confidence threshold '
                                f'increases sensitivity by allowing less certain classifications.'),
                        confidence=0.75
                    ))
                suggestions.append(ParameterSuggestion(
                    parameter='database',
                    current_value=current_parameters.get('database', 'standard'),
                    suggested_value='standard_8gb',
                    reason=(f"Classification rate {classified:.1f}% is {'critically low' if classified < 30 else 'below recommended 60%'}. "
                            f'A larger database may substantially improve classification rates.'),
                    confidence=0.65 if classified < 30.0 else 0.60
                ))

        return suggestions


def get_suggester_for_domain(domain: str, logger: Optional[logging.Logger] = None) -> BaseParameterSuggester:
    """
    Get the appropriate parameter suggester for a workflow domain.

    Args:
        domain: Workflow domain (e.g., 'cryo_em', 'rnaseq')
        logger: Optional logger instance

    Returns:
        Domain-specific parameter suggester
    """
    domain_lower = domain.lower()

    # Use targeted keywords to avoid false matches from broad substrings like 'em'
    # which appears in 'system', 'theorem', 'genome', etc.
    # '_em' must only match when not followed by more word characters — e.g.
    # 'cryo_em', 'cryo_em_spa' are valid but 'item_embedding' is not.
    import re as _re
    cryo_em_keywords = ('cryo', 'electron_micro', 'cryosparc', 'cryoem')
    has_em_suffix = bool(_re.search(r'_em(?:[^a-z]|$)', domain_lower))
    if any(kw in domain_lower for kw in cryo_em_keywords) or has_em_suffix or domain_lower == 'em':
        return CryoEMParameterSuggester(logger)
    elif any(k in domain_lower for k in ('single_cell', 'singlecell', 'scrna', 'sc_rna', 'cellranger')):
        return SingleCellParameterSuggester(logger)
    elif any(k in domain_lower for k in ('rna', 'rnaseq', 'transcriptom')):
        return RNASeqParameterSuggester(logger)
    elif any(k in domain_lower for k in ('chip', 'atac', 'chipseq', 'atacseq', 'cut_and_run', 'cutandrun')):
        return ChIPSeqParameterSuggester(logger)
    elif any(k in domain_lower for k in ('metagenomic', 'metagenom', 'microbiom', 'kraken', 'metaphlan')):
        return MetagenomicsParameterSuggester(logger)
    elif any(k in domain_lower for k in ('dna', 'genomic', 'variant', 'wgs', 'wes', 'exome', 'bwa', 'gatk')):
        return GenomicsParameterSuggester(logger)
    elif any(k in domain_lower for k in ('seq', 'sequenc')):
        # Generic sequencing fallback — covers bulk RNA-seq, amplicon, etc.
        return RNASeqParameterSuggester(logger)
    else:
        # Default to base suggester (raises NotImplementedError — no suggestions)
        return BaseParameterSuggester(logger)
