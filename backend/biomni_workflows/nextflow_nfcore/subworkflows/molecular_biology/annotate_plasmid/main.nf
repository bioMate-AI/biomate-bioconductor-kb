#!/usr/bin/env nextflow
/*
 * molecular_biology/annotate_plasmid
 * Annotate a DNA sequence using pLannotate's command-line interface.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: pUC19 plasmid fragment containing MCS and lac promoter
params.sequence = 'ATGACCATGATTACGCCAAGCTTGCATGCCTGCAGGTCGACTCTAGAGGATCCCCGGGTACCGAGCTCGAATTCACTGGCCGTCGTTTTACAACGTCGTGACTGGGAAAACCCTGGCGTTACCCAACTTAATCGCCTTGCAGCACATCCCCCTTTCGCCAGCTGGCGTAATAGCGAAGAGGCCCGCACCGATCGCCCTTCCCAACAGTTGCGCAGCCTGAATGGCGAATGGCGCCTGATGCGGTATTTTCTCCTTACGCATCTGTGCGGTATTTCACACCGCATATGGTGCACTCTCAGTACAATCTGCTCTGATGCCGCATAGTTAAGCCAGCCCCGACACCCGCCAACACCCGCTGACGCGCCCTGACGGGCTTGTCTGCTCCCGGCATCCGCTTACAGACAAGCTGTGACCGTCTCCGGGAGCTGCATGTGTCAGAGGTTTTCACCGTCATCACCGAAACGCGCGAGACGAAAGGGCCTCGTGATACGCCTATTTTTATAGGTTAATGTCATGATAATAATGGTTTCTTAGACGTCAGGTGGCACTTTTCGGGGAAATGTGCGCGGAACCCCTATTTGTTTATTTTTCTAAATACATTCAAATATGTATCCGCTCATGAGACAATAACCCTGATAAATGCTTCAATAATATTGAAAAAGGAAGAGTATGAGTATTCAACATTTCCGTGTCGCCCTTATTCCCTTTTTTGCGGCATTTTGCCTTCCTGTTTTTGCTCACCCAGAAACGCTGGTGAAAGTAAAAGATGCTGAAGATCAGTTGGGTGCACGAGTGGGTTACATCGAACTGGATCTCAACAGCGGTAAGATCCTTGAGAGTTTTCGCCCCGAAGAACGTTTTCCAATGATGAGCACTTTTAAAGTTCTGCTATGTGGCGCGGTATTATCCCGTATTGACGCCGGGCAAGAGCAACTCGGTCGCCGCATACACTATTCTCAGAATGACTTGGTTGAGTACTCACCAGTCACAGAAAAGCATCTTACGGATGGCATGACAGTAAGAGAATTATGCAGTGCTGCCATAACCATGAGTGATAACACTGCGGCCAACTTACTTCTGACAACGATCGGAGGACCGAAGGAGCTAACCGCTTTTTTGCACAACATGGGGGATCATGTAACTCGCCTTGATCGTTGGGAACCGGAGCTGAATGAAGCCATACCAAACGACGAGCGTGACACCACGATGCCTGTAGCAATGGCAACAACGTTGCGCAAACTATTAACTGGCGAACTACTTACTCTAGCTTCCCGGCAACAATTAATAGACTGGATGGAGGCGGATAAAGTTGCAGGACCACTTCTGCGCTCGGCCCTTCCGGCTGGCTGGTTTATTGCTGATAAATCTGGAGCCGGTGAGCGTGGGTCTCGCGGTATCATTGCAGCACTGGGGCCAGATGGTAAGCCCTCCCGTATCGTAGTTATCTACACGACGGGGAGTCAGGCAACTATGGATGAACGAAATAGACAGATCGCTGAGATAGGTGCCTCACTGATTAAGCATTGGTAA'
params.is_circular = 'true'

process ANNOTATE_PLASMID {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("annotate_plasmid_results.json"), emit: results
    tuple val(meta), path("annotate_plasmid_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_SEQUENCE="${params.sequence?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_IS_CIRCULAR="${params.is_circular?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import pandas as pd
import os
import tempfile
from typing import Any
import subprocess
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



def annotate_plasmid(sequence: str, is_circular: bool = True) -> dict[str, Any]:
    '''Annotate a DNA sequence using pLannotate's command-line interface.

    Args:
        sequence (str): The DNA sequence to annotate
        is_circular (bool): Whether the sequence is circular (default: True)
        return_plot (bool): Whether to return the Bokeh plot object (default: False)

    Returns:
        Dict: Dictionary containing annotation results or None if annotation fails

    '''
    try:
        # Create a temporary directory to store input/output files
        with tempfile.TemporaryDirectory() as temp_dir:
            # Create temporary FASTA file
            fasta_path = os.path.join(temp_dir, "input.fasta")
            with open(fasta_path, "w") as f:
                f.write(f">sequence\\n{sequence}\\n")

            # Prepare command
            cmd = [
                "plannotate",
                "batch",
                "-i",
                fasta_path,
                "-o",
                temp_dir,
                "-f",
                "output",
                "--csv",  # Request CSV output
            ]

            # Add linear flag if sequence is not circular
            if not is_circular:
                cmd.append("-l")

            # Add detailed flag for more comprehensive search
            cmd.append("-d")

            # Run plannotate
            subprocess.run(cmd, check=True)

            # Read results from CSV
            csv_path = os.path.join(temp_dir, "output_pLann.csv")
            results = pd.read_csv(csv_path)

            explanation = (
                "Output fields for each annotation:\\n"
                "- sseqid: Subject sequence identifier (name of the feature)\\n"
                "- qstart/qend: Start and end positions in query sequence\\n"
                "- sstart/send: Start and end positions in subject sequence\\n"
                "- sframe: Reading frame (-1 for reverse strand, 1 for forward)\\n"
                "- score: Alignment score\\n"
                "- evalue: Expected value for the alignment\\n"
                "- qseq: Query sequence\\n"
                "- length: Length of the alignment\\n"
                "- slen: Length of the subject sequence\\n"
                "- pident: Percentage identity\\n"
                "- qlen: Length of the query sequence\\n"
                "- db: Database source (e.g., snapgene)\\n"
                "- Feature: Feature name\\n"
                "- Description: Detailed description of the feature\\n"
                "- Type: Feature type (e.g., CDS, promoter, rep_origin)\\n"
                "- priority: Priority score\\n"
                "- percmatch: Percentage match\\n"
                "- abs percmatch: Absolute percentage match\\n"
                "- pi_permatch: Per-identity match\\n"
                "- wiggle: Wiggle room for alignment\\n"
                "- wstart/wend: Wiggle start and end positions\\n"
                "- kind: Feature kind\\n"
                "- qstart_dup/qend_dup: Duplicate query positions\\n"
                "- fragment: Boolean indicating if feature is fragmented"
            )

            return {
                "explanation": explanation,
                "annotations": results.to_dict("records"),
            }

    except Exception as e:
        print(f"Error during annotation: {e}")
        return None

# Execute the function
try:
    result = annotate_plasmid(
        sequence=auto_convert(os.environ.get("PARAM_SEQUENCE", "")),
        is_circular=auto_convert(os.environ.get("PARAM_IS_CIRCULAR", "")),
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
    "function": "annotate_plasmid",
    "domain": "molecular_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("annotate_plasmid_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("annotate_plasmid_output.txt", "w") as f:
    f.write("Biomni: Annotate Plasmid" + NL)
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
        biomni_function: "annotate_plasmid"
    END_VERSIONS
    """
}

workflow ANNOTATE_PLASMID_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANNOTATE_PLASMID(ch_input)

    emit:
    results = ANNOTATE_PLASMID.out.results
    output = ANNOTATE_PLASMID.out.output
    versions = ANNOTATE_PLASMID.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANNOTATE_PLASMID_WORKFLOW(ch_input)

    ANNOTATE_PLASMID_WORKFLOW.out.output.view { "Output: $it" }
}
