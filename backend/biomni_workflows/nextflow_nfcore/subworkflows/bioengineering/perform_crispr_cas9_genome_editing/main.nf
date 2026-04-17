#!/usr/bin/env nextflow
/*
 * bioengineering/perform_crispr_cas9_genome_editing
 * Simulates CRISPR-Cas9 genome editing process including guide RNA design, delivery, and analysis.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: CRISPR editing of BRCA1 gene exon 11
params.guide_rna_sequences = '["GTGTCCCATCTGTCTGGAGT", "TCTGGAGTTGATCAAGGAAC"]'
params.target_genomic_loci = 'ATGGATTTATCTGCTCTTCGCGTTGAAGAAGTACAAAATGTCATTAATGCTATGCAGAAAATCTTAGAGTGTCCCATCTGTCTGGAGTTGATCAAGGAACCTGTCTCCACAAAGTGTGACCACATATTTTGCAAATTTTG'
params.cell_tissue_type = 'HEK293'

process PERFORM_CRISPR_CAS9_GENOME_EDITING {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("perform_crispr_cas9_genome_editing_results.json"), emit: results
    tuple val(meta), path("perform_crispr_cas9_genome_editing_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_GUIDE_RNA_SEQUENCES="${params.guide_rna_sequences?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TARGET_GENOMIC_LOCI="${params.target_genomic_loci?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CELL_TISSUE_TYPE="${params.cell_tissue_type?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation

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



def perform_crispr_cas9_genome_editing(guide_rna_sequences, target_genomic_loci, cell_tissue_type):
    '''Simulates CRISPR-Cas9 genome editing process including guide RNA design, delivery, and analysis.

    Parameters
    ----------
    guide_rna_sequences : list of str
        List of guide RNA sequences (20 nucleotides each) targeting the genomic region of interest

    target_genomic_loci : str
        Target genomic sequence to be edited (should be longer than guide RNA and contain the target sites)

    cell_tissue_type : str
        Type of cell or tissue being edited (affects delivery efficiency and editing outcomes)

    Returns
    -------
    str
        Research log detailing the CRISPR-Cas9 editing process, including steps taken and results

    '''
    import os
    import random
    from datetime import datetime

    # Initialize research log
    log = "CRISPR-Cas9 Genome Editing Research Log\\n"
    log += f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\\n"
    log += f"Cell/Tissue Type: {cell_tissue_type}\\n\\n"

    # Step 1: Validate guide RNA sequences
    log += "STEP 1: Guide RNA Validation\\n"
    valid_guides = []

    for i, guide in enumerate(guide_rna_sequences):
        if len(guide) != 20:
            log += f"  Guide {i + 1}: INVALID - Guide RNA must be 20 nucleotides (current length: {len(guide)})\\n"
            continue

        if not all(n in "ATGC" for n in guide.upper()):
            log += f"  Guide {i + 1}: INVALID - Guide RNA contains invalid nucleotides\\n"
            continue

        # Calculate GC content (affects guide efficiency)
        gc_content = (guide.upper().count("G") + guide.upper().count("C")) / len(guide) * 100
        efficiency_score = 0

        if 40 <= gc_content <= 60:
            efficiency_score += 1
            gc_quality = "Optimal"
        else:
            gc_quality = "Suboptimal"

        log += f"  Guide {i + 1}: VALID - {guide} (GC content: {gc_content:.1f}% - {gc_quality})\\n"
        valid_guides.append((guide, efficiency_score))

    if not valid_guides:
        log += "\\nNo valid guide RNAs found. Genome editing cannot proceed.\\n"
        return log

    # Step 2: Target site identification
    log += "\\nSTEP 2: Target Site Identification\\n"

    target_seq = target_genomic_loci.upper()
    target_matches = []

    for i, (guide, score) in enumerate(valid_guides):
        # Find guide RNA target in genomic sequence (including PAM site NGG)
        guide.upper() + "NGG"

        # Check if guide sequence is in target (simplified)
        if guide.upper() in target_seq:
            position = target_seq.find(guide.upper())
            # Check if there's a PAM sequence (NGG) after the guide
            if position + len(guide) + 2 <= len(target_seq):
                potential_pam = target_seq[position + len(guide) : position + len(guide) + 3]
                if potential_pam[1:3] == "GG":
                    pam_quality = "Found"
                    score += 2
                else:
                    pam_quality = "Not found"
            else:
                pam_quality = "Out of bounds"

            log += f"  Guide {i + 1}: Found at position {position} (PAM: {pam_quality})\\n"
            target_matches.append((guide, position, score))
        else:
            log += f"  Guide {i + 1}: No match found in target sequence\\n"

    if not target_matches:
        log += "\\nNo matching target sites found. Genome editing cannot proceed.\\n"
        return log

    # Step 3: Simulate CRISPR-Cas9 delivery
    log += "\\nSTEP 3: CRISPR-Cas9 Delivery Simulation\\n"

    # Cell-specific delivery efficiencies (simplified model)
    delivery_efficiencies = {
        "hek293": 0.85,
        "hela": 0.75,
        "ipsc": 0.60,
        "primary_neuron": 0.40,
        "hematopoietic_stem_cell": 0.55,
        "mouse_embryo": 0.70,
        "plant_cell": 0.30,
    }

    # Get delivery efficiency based on cell type (default to 0.5 if unknown)
    cell_type_key = cell_tissue_type.lower().replace(" ", "_")
    delivery_efficiency = delivery_efficiencies.get(cell_type_key, 0.5)

    log += f"  Delivery method: Lipofection for {cell_tissue_type}\\n"
    log += f"  Estimated delivery efficiency: {delivery_efficiency * 100:.1f}%\\n"

    # Step 4: Simulate genome editing
    log += "\\nSTEP 4: Genome Editing Simulation\\n"

    # Select best guide based on score
    best_guide, best_position, best_score = sorted(target_matches, key=lambda x: x[2], reverse=True)[0]

    log += f"  Selected guide RNA: {best_guide} (highest efficiency score)\\n"
    log += f"  Target position: {best_position} to {best_position + len(best_guide) - 1}\\n"

    # Simulate editing outcome
    edit_success_rate = delivery_efficiency * (0.5 + (best_score * 0.1))  # Between 50-90% based on guide quality

    # Cut site (typically 3 bases upstream of PAM)
    cut_position = best_position + len(best_guide) - 3
    log += f"  Predicted cut site: Between positions {cut_position} and {cut_position + 1}\\n"

    # Simulate editing outcomes
    indel_size = random.randint(1, 5)  # Random indel size between 1-5 bp

    # Create modified sequence (simulate a deletion for simplicity)
    modified_sequence = target_seq[:cut_position] + target_seq[cut_position + indel_size :]

    log += f"  Simulated edit: {indel_size}bp deletion at cut site\\n"
    log += f"  Predicted editing efficiency: {edit_success_rate * 100:.1f}%\\n"

    # Step 5: Analysis of editing outcomes
    log += "\\nSTEP 5: Editing Outcome Analysis\\n"

    # Calculate basic stats
    log += f"  Original sequence length: {len(target_seq)} bp\\n"
    log += f"  Modified sequence length: {len(modified_sequence)} bp\\n"

    # Save sequences to files
    os.makedirs("crispr_results", exist_ok=True)

    original_file = "crispr_results/original_sequence.txt"
    with open(original_file, "w") as f:
        f.write(f">Original_Sequence\\n{target_seq}\\n")

    modified_file = "crispr_results/modified_sequence.txt"
    with open(modified_file, "w") as f:
        f.write(f">Modified_Sequence\\n{modified_sequence}\\n")

    log += f"  Original sequence saved to: {original_file}\\n"
    log += f"  Modified sequence saved to: {modified_file}\\n"

    # Summary
    log += "\\nSUMMARY:\\n"
    log += f"  CRISPR-Cas9 editing successfully simulated for {cell_tissue_type}\\n"
    log += f"  {indel_size}bp deletion introduced at position {cut_position}\\n"
    log += f"  Expected success rate in cell population: {edit_success_rate * 100:.1f}%\\n"

    return log

# Execute the function
try:
    result = perform_crispr_cas9_genome_editing(
        guide_rna_sequences=auto_convert(os.environ.get("PARAM_GUIDE_RNA_SEQUENCES", "")),
        target_genomic_loci=auto_convert(os.environ.get("PARAM_TARGET_GENOMIC_LOCI", "")),
        cell_tissue_type=auto_convert(os.environ.get("PARAM_CELL_TISSUE_TYPE", "")),
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
    "function": "perform_crispr_cas9_genome_editing",
    "domain": "bioengineering",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("perform_crispr_cas9_genome_editing_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("perform_crispr_cas9_genome_editing_output.txt", "w") as f:
    f.write("Biomni: Perform Crispr Cas9 Genome Editing" + NL)
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
        biomni_function: "perform_crispr_cas9_genome_editing"
    END_VERSIONS
    """
}

workflow PERFORM_CRISPR_CAS9_GENOME_EDITING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    PERFORM_CRISPR_CAS9_GENOME_EDITING(ch_input)

    emit:
    results = PERFORM_CRISPR_CAS9_GENOME_EDITING.out.results
    output = PERFORM_CRISPR_CAS9_GENOME_EDITING.out.output
    versions = PERFORM_CRISPR_CAS9_GENOME_EDITING.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    PERFORM_CRISPR_CAS9_GENOME_EDITING_WORKFLOW(ch_input)

    PERFORM_CRISPR_CAS9_GENOME_EDITING_WORKFLOW.out.output.view { "Output: $it" }
}
