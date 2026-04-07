"""
Workflow Dataset Selector

Assigns available user datasets to workflow input steps based on format/type matching.
Returns assignments for user confirmation before execution.
"""

from typing import Dict, List, Any, Optional
import logging
import re

log = logging.getLogger(__name__)

# Map canonical format group → input description keywords that suggest that format.
FORMAT_GROUPS: Dict[str, List[str]] = {
    'fastq':   ['fastq', 'fq', 'reads', 'raw_reads', 'input_reads', 'paired', 'sequences', 'r1', 'r2', 'sequencing'],
    'bam':     ['bam', 'sam', 'cram', 'alignment', 'aligned', 'mapped', 'sorted_bam', 'coordinate'],
    'vcf':     ['vcf', 'bcf', 'variants', 'snp', 'snv', 'indel', 'calls', 'genotype'],
    'fasta':   ['fasta', 'fa', 'fna', 'reference', 'genome', 'ref', 'assembly', 'reference_genome'],
    'bed':     ['bed', 'regions', 'intervals', 'peaks', 'sites', 'annotation'],
    'gtf':     ['gtf', 'gff', 'gff3', 'annotation', 'genes', 'transcripts'],
    'tabular': ['csv', 'tsv', 'tabular', 'txt', 'counts', 'expression', 'matrix', 'count_matrix'],
    'h5ad':    ['h5ad', 'h5', 'anndata', 'single_cell', 'sc_data'],
}

# Common Galaxy tool name fragments → expected primary input format(s), priority order.
TOOL_INPUT_FORMATS: Dict[str, List[str]] = {
    'fastqc':        ['fastq'],
    'trimmomatic':   ['fastq'],
    'cutadapt':      ['fastq'],
    'fastp':         ['fastq'],
    'bwa':           ['fastq', 'fasta'],
    'hisat2':        ['fastq', 'fasta'],
    'star':          ['fastq', 'fasta'],
    'bowtie':        ['fastq', 'fasta'],
    'kallisto':      ['fastq', 'fasta'],
    'salmon':        ['fastq', 'fasta'],
    'samtools':      ['bam'],
    'picard':        ['bam'],
    'gatk':          ['bam', 'fasta', 'vcf'],
    'freebayes':     ['bam', 'fasta'],
    'bcftools':      ['vcf', 'bam'],
    'snpeff':        ['vcf'],
    'vep':           ['vcf'],
    'featurecounts': ['bam', 'gtf'],
    'htseq':         ['bam', 'gtf'],
    'deseq2':        ['tabular'],
    'limma':         ['tabular'],
    'edger':         ['tabular'],
    'seurat':        ['h5ad', 'tabular'],
    'scanpy':        ['h5ad'],
    'kraken':        ['fastq', 'fasta'],
    'metaphlan':     ['fastq'],
    'bracken':       ['tabular'],
    'multiqc':       ['tabular'],
    'bustools':      ['fastq'],
    'cellranger':    ['fastq'],
    'starsolo':      ['fastq'],
}


def _dataset_format_group(dataset: Dict[str, Any]) -> Optional[str]:
    """Return the canonical format group for a dataset, or None if unknown."""
    raw = (dataset.get('type') or dataset.get('fileType') or dataset.get('extension') or '').lower()
    raw = raw.replace('.gz', '').replace('.bz2', '').strip('.')
    for group, keywords in FORMAT_GROUPS.items():
        if raw == group or raw in keywords:
            return group
    return None


def _step_expected_formats(step: Dict[str, Any]) -> List[str]:
    """
    Infer which format groups a workflow step likely needs as primary input.
    Uses tool_id/name first, then falls back to description keyword scan.
    """
    tool_id = (step.get('tool_id') or '').lower()
    name    = (step.get('name') or step.get('tool_name') or '').lower()

    for tool_fragment, formats in TOOL_INPUT_FORMATS.items():
        if tool_fragment in tool_id or tool_fragment in name:
            return formats

    description = (step.get('description') or step.get('annotation') or '').lower()
    combined = f"{name} {description} {tool_id}"
    for group, keywords in FORMAT_GROUPS.items():
        if any(kw in combined for kw in keywords):
            return [group]

    return []


class WorkflowDatasetSelector:
    """
    Assigns user-provided datasets to workflow input steps.

    Matching strategy:
      1. For each workflow step, infer required input format(s) from tool name / description.
      2. Find the best-matching dataset from available_datasets by format group.
      3. Each dataset is assigned at most once (no double-use).

    Results are candidates — the caller must surface them via the prereq checklist
    (input_data item) for user confirmation before execution.
    """

    def __init__(self):
        log.info("WorkflowDatasetSelector initialized")

    def select_datasets_for_workflow(
        self,
        workflow: Dict[str, Any],
        user_intent: str,
        available_datasets: Optional[List[Dict[str, Any]]] = None,
        uploaded_datasets: Optional[List[str]] = None,  # legacy — ignored
    ) -> Dict[str, Any]:
        """
        Match available datasets to workflow steps by format.

        Args:
            workflow: Workflow dict with 'steps' key (list of step dicts).
            user_intent: User's original request (used for logging context).
            available_datasets: List of dataset dicts {id, name, type/fileType/extension}.
            uploaded_datasets: Deprecated legacy param (was List[str] of IDs only) — ignored.

        Returns:
            {
                'workflow_steps': [
                    {'step': int, 'tool_id': str,
                     'datasets': [{'name': str, 'path': str, 'dataset_id': str, 'format': str}]}
                ],
                'unassigned_inputs': [
                    {'step': int, 'tool_id': str, 'expected_formats': List[str]}
                ],
                'total_steps':    int,
                'assigned_count': int,
            }
        """
        datasets = available_datasets or []
        steps    = workflow.get('steps', [])

        log.info(
            "[DatasetSelector] Matching %d datasets to %d steps for: %.80s",
            len(datasets), len(steps), user_intent,
        )

        if not datasets:
            log.info("[DatasetSelector] No datasets provided — skipping assignment")
            return {'workflow_steps': [], 'unassigned_inputs': [], 'total_steps': len(steps), 'assigned_count': 0}

        # Pre-group datasets by format for fast lookup
        datasets_by_group: Dict[str, List[Dict]] = {}
        for ds in datasets:
            grp = _dataset_format_group(ds)
            if grp:
                datasets_by_group.setdefault(grp, []).append(ds)

        used_ids: set = set()
        assigned_steps: List[Dict] = []
        unassigned: List[Dict] = []

        for step in steps:
            step_num = step.get('step', 0)
            tool_id  = step.get('tool_id', '')
            expected = _step_expected_formats(step)

            if not expected:
                continue

            matched = None
            for fmt in expected:
                candidates = [ds for ds in datasets_by_group.get(fmt, []) if ds.get('id') not in used_ids]
                if candidates:
                    # Prefer dataset whose name overlaps most with the step description
                    step_desc = (step.get('description') or step.get('name') or '').lower()
                    candidates.sort(
                        key=lambda ds: sum(
                            1 for w in re.split(r'\W+', step_desc)
                            if w and w in ds.get('name', '').lower()
                        ),
                        reverse=True,
                    )
                    matched = candidates[0]
                    break

            if matched:
                used_ids.add(matched['id'])
                assigned_steps.append({
                    'step':    step_num,
                    'tool_id': tool_id,
                    'datasets': [{
                        'name':       matched.get('name', ''),
                        'path':       matched.get('id', ''),
                        'dataset_id': matched.get('id', ''),
                        'format':     _dataset_format_group(matched),
                    }],
                })
                log.debug("[DatasetSelector] step %d (%s) → '%s'", step_num, tool_id, matched.get('name'))
            else:
                unassigned.append({'step': step_num, 'tool_id': tool_id, 'expected_formats': expected})
                log.debug("[DatasetSelector] step %d (%s) — no match for %s", step_num, tool_id, expected)

        log.info("[DatasetSelector] %d assigned, %d unassigned", len(assigned_steps), len(unassigned))
        return {
            'workflow_steps':    assigned_steps,
            'unassigned_inputs': unassigned,
            'total_steps':       len(steps),
            'assigned_count':    len(assigned_steps),
        }
