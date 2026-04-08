#!/usr/bin/env nextflow
/*
 * genetics/analyze_crispr_genome_editing
 * Analyzes CRISPR-Cas9 genome editing results by comparing original and edited sequences.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: CRISPR editing of BRCA1 gene exon 11
params.original_sequence = 'ATGGATTTATCTGCTCTTCGCGTTGAAGAAGTACAAAATGTCATTAATGCTATGCAGAAAATCTTAGAGTGTCCCATCTGTCTGGAGTTGATCAAGGAACCTGTCTCCACAAAGTGTGACCACATATTTTGCAAATTTTG'
params.edited_sequence = 'ATGGATTTATCTGCTCTTCGCGTTGAAGAAGTACAAAATGTCATTAATGCTATGCAGAAAATCTTAGAGTGTCCCATCTGTCTGGAGTTGATCAAGGAACCTGTCTCCACAAAGTGTGACCACATATTTTGCAAATTTTG'
params.guide_rna = 'GTGTCCCATCTGTCTGGAGT'
params.repair_template = null

process ANALYZE_CRISPR_GENOME_EDITING {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_crispr_genome_editing_results.json"), emit: results
    tuple val(meta), path("analyze_crispr_genome_editing_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_ORIGINAL_SEQUENCE="${params.original_sequence?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_EDITED_SEQUENCE="${params.edited_sequence?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_GUIDE_RNA="${params.guide_rna?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_REPAIR_TEMPLATE="${params.repair_template?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
from datetime import datetime
import json
import os

def auto_convert(val):
    # Auto-convert string to appropriate type
    if val is None or val == '' or val == 'null':
        return None
    # Try bool
    if isinstance(val, str) and val.lower() in ('true', 'false'):
        return val.lower() == 'true'
    # Try JSON for lists and dicts
    if isinstance(val, str) and val.strip().startswith(('[', '{')):
        try:
            return json.loads(val)
        except json.JSONDecodeError:
            pass
    # Try int
    try:
        if isinstance(val, str) and '.' not in val:
            return int(val)
    except ValueError:
        pass
    # Try float
    try:
        return float(val)
    except ValueError:
        pass
    # Return as string
    return val



def analyze_crispr_genome_editing(original_sequence, edited_sequence, guide_rna, repair_template=None):
    '''Analyzes CRISPR-Cas9 genome editing results by comparing original and edited sequences.

    Parameters
    ----------
    original_sequence : str
        The original DNA sequence before CRISPR-Cas9 editing
    edited_sequence : str
        The DNA sequence after CRISPR-Cas9 editing
    guide_rna : str
        The CRISPR guide RNA (crRNA) sequence used for targeting
    repair_template : str, optional
        The homology-directed repair template sequence, if used

    Returns
    -------
    str
        A research log summarizing the CRISPR-Cas9 editing analysis, including identified
        mutations and characterization of the edited loci

    '''
    import datetime

    from Bio import pairwise2
    from Bio.Seq import Seq

    log = []
    log.append(f"CRISPR-Cas9 Genome Editing Analysis - {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    log.append("=" * 70)

    # Step 1: Find the target site in the original sequence
    log.append("\\n1. Identifying target site in original sequence")
    target_site = original_sequence.find(guide_rna)
    if target_site == -1:
        # Try with the reverse complement
        guide_rna_seq = Seq(guide_rna)
        rev_comp_guide = str(guide_rna_seq.reverse_complement())
        target_site = original_sequence.find(rev_comp_guide)
        if target_site != -1:
            log.append(f"   - Target site found at position {target_site} (using reverse complement of guide RNA)")
            guide_rna = rev_comp_guide
        else:
            log.append("   - Warning: Guide RNA sequence not found in original sequence")
            target_site = None
    else:
        log.append(f"   - Target site found at position {target_site}")

    # Step 2: Align sequences to identify mutations
    log.append("\\n2. Aligning original and edited sequences to identify mutations")
    alignments = pairwise2.align.globalms(original_sequence, edited_sequence, 2, -1, -2, -0.5)
    best_alignment = alignments[0]

    # Extract aligned sequences
    aligned_orig = best_alignment[0]
    aligned_edit = best_alignment[1]

    # Find mutations
    mutations = []
    indels = []

    for i in range(len(aligned_orig)):
        if aligned_orig[i] != aligned_edit[i]:
            orig_base = aligned_orig[i]
            edit_base = aligned_edit[i]

            # Skip gaps in counting the actual position
            actual_pos = len(aligned_orig[:i].replace("-", ""))

            if orig_base == "-":  # Insertion
                indels.append(f"Insertion of {edit_base} at position {actual_pos}")
            elif edit_base == "-":  # Deletion
                indels.append(f"Deletion of {orig_base} at position {actual_pos}")
            else:  # Substitution
                mutations.append(f"{orig_base}→{edit_base} at position {actual_pos}")

    # Log mutations
    if mutations:
        log.append("   - Substitutions detected:")
        for mutation in mutations:
            log.append(f"     * {mutation}")
    else:
        log.append("   - No substitutions detected")

    if indels:
        log.append("   - Insertions/Deletions detected:")
        for indel in indels:
            log.append(f"     * {indel}")
    else:
        log.append("   - No insertions or deletions detected")

    # Step 3: Check if editing occurred near the target site
    if target_site is not None:
        log.append("\\n3. Analyzing mutations relative to target site")
        target_end = target_site + len(guide_rna)
        target_region = range(target_site - 3, target_end + 3)  # Include some buffer

        on_target_edits = [m for m in mutations + indels if any(str(pos) in m for pos in target_region)]

        if on_target_edits:
            log.append("   - On-target edits detected near guide RNA binding site:")
            for edit in on_target_edits:
                log.append(f"     * {edit}")
        else:
            log.append("   - No edits detected near guide RNA binding site")

    # Step 4: Check for homology-directed repair if template was provided
    if repair_template:
        log.append("\\n4. Checking for homology-directed repair template incorporation")
        # Look for unique sequence markers from the repair template
        template_len = len(repair_template)
        marker_size = min(10, template_len // 3)
        marker = repair_template[template_len // 2 - marker_size // 2 : template_len // 2 + marker_size // 2]

        if marker in edited_sequence and marker not in original_sequence:
            log.append(f"   - Repair template marker '{marker}' found in edited sequence")
            log.append("   - Homology-directed repair likely successful")
        else:
            log.append("   - No clear evidence of repair template incorporation")
            log.append("   - Editing likely resulted from non-homologous end joining (NHEJ)")

    # Step 5: Overall assessment
    log.append("\\n5. Overall assessment")
    if mutations or indels:
        log.append("   - CRISPR-Cas9 editing appears successful")
        if target_site is not None and any(
            str(pos) in "".join(mutations + indels) for pos in range(target_site, target_site + len(guide_rna))
        ):
            log.append("   - Edits occurred at the intended target site")
        else:
            log.append("   - Edits may have occurred outside the intended target site")
    else:
        log.append("   - No significant editing detected, CRISPR-Cas9 may not have been effective")

    return "\\n".join(log)

# Execute the function
try:
    result = analyze_crispr_genome_editing(
        original_sequence=auto_convert(os.environ.get("PARAM_ORIGINAL_SEQUENCE", "")),
        edited_sequence=auto_convert(os.environ.get("PARAM_EDITED_SEQUENCE", "")),
        guide_rna=auto_convert(os.environ.get("PARAM_GUIDE_RNA", "")),
        repair_template=auto_convert(os.environ.get("PARAM_REPAIR_TEMPLATE", "")),
    )
    success = True
    error_msg = None
except Exception as e:
    result = None
    success = False
    error_msg = str(e)

# Save results
output_data = {
    "success": success,
    "function": "analyze_crispr_genome_editing",
    "domain": "genetics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_crispr_genome_editing_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_crispr_genome_editing_output.txt", "w") as f:
    f.write("Biomni: Analyze Crispr Genome Editing" + NL)
    f.write("=" * 60 + NL + NL)
    if success:
        if isinstance(result, str):
            f.write(result)
        elif isinstance(result, dict):
            for key, value in result.items():
                f.write(f"{key}: {value}" + NL)
        else:
            f.write(str(result))
    else:
        f.write(f"ERROR: {error_msg}" + NL)

if not success:
    exit(1)
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | cut -d' ' -f2)
        biomni_function: "analyze_crispr_genome_editing"
    END_VERSIONS
    """
}

workflow ANALYZE_CRISPR_GENOME_EDITING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_CRISPR_GENOME_EDITING(ch_input)

    emit:
    results = ANALYZE_CRISPR_GENOME_EDITING.out.results
    output = ANALYZE_CRISPR_GENOME_EDITING.out.output
    versions = ANALYZE_CRISPR_GENOME_EDITING.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_CRISPR_GENOME_EDITING_WORKFLOW(ch_input)

    ANALYZE_CRISPR_GENOME_EDITING_WORKFLOW.out.output.view { "Output: $it" }
}
