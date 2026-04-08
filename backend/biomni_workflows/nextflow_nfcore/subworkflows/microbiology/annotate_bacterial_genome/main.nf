#!/usr/bin/env nextflow
/*
 * microbiology/annotate_bacterial_genome
 * Annotate a bacterial genome using Prokka to identify genes, proteins, and functional features.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Uses inline-generated mock bacterial genome FASTA
params.genome_file_path = 'mock_genome.fasta'
params.output_dir = 'annotation_results'
params.genus = 'Escherichia'
params.species = 'coli'
params.strain = 'K12'
params.prefix = 'ecoli_test'

process ANNOTATE_BACTERIAL_GENOME {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("annotate_bacterial_genome_results.json"), emit: results
    tuple val(meta), path("annotate_bacterial_genome_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_GENOME_FILE_PATH="${params.genome_file_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_GENUS="${params.genus?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SPECIES="${params.species?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_STRAIN="${params.strain?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_PREFIX="${params.prefix?.toString()?.replace('"', '\\"') ?: 'null'}"

    # Generate mock bacterial genome FASTA for testing
    cat > mock_genome.fasta << 'FASTAEOF'
>mock_chromosome E. coli K12 test sequence
ATGAAACGCATTAGCACCACCATTACCACCACCATCACCATTACCACAGGTAACGGTGCG
GGCTGACGCGTACAGGAAACACAGAAAAAAGCCCGCACCTGACAGTGCGGGCTTTTTTT
TTCGACCAAAGGTAACGAGGTAACAACCATGCGAGTGTTGAAGTTCGGCGGTACATCAG
TGGCAAATGCAGAACGTTTTCTGCGTGTTGCCGATATTCTGGAAAGCAATGCCAGGCAG
GGGCAGGTGGCCACCGTCCTCTCTGCCCCCGCCAAAATCACCAACCACCTGGTGGCGAT
GATTGAAAAAACCATTAGCGGCCAGGATGCTTTACCCAATATCAGCGATGCCGAACGTA
TTTTTGCCGAACTTTTGACGGGACTCGCCGCCGCCCAGCCGGGGTTCCCGCTGGCGCAA
TTGAAAACTTTCGTCGATCAGGAATTTGCCCAAATAAAACATGTCCTGCATGGCATTAG
TTTGTTGGGGCAGTGCCCGGATAGCATCAACGCTGCGCTGATTTGCCGTGGCGAGAAAA
ATGTCGATCGCCATTATGGCCGGCGTATGTAA
FASTAEOF

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



def annotate_bacterial_genome(
    genome_file_path,
    output_dir="annotation_results",
    genus="",
    species="",
    strain="",
    prefix="",
):
    '''Annotate a bacterial genome using Prokka to identify genes, proteins, and functional features.

    Parameters
    ----------
    genome_file_path : str
        Path to the assembled genome sequence file in FASTA format
    output_dir : str, optional
        Directory where annotation results will be saved (default: "annotation_results")
    genus : str, optional
        Genus name for the organism (default: "")
    species : str, optional
        Species name for the organism (default: "")
    strain : str, optional
        Strain identifier (default: "")
    prefix : str, optional
        Prefix for output files (default: "")

    Returns
    -------
    str
        Research log summarizing the annotation process and results

    '''
    import os
    import subprocess
    import time

    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)

    # Generate a default prefix if not provided
    if not prefix:
        prefix = f"annotation_{int(time.time())}"

    # Build the Prokka command
    prokka_cmd = [
        "prokka",
        genome_file_path,
        "--outdir",
        output_dir,
        "--prefix",
        prefix,
    ]

    # Add organism information if provided
    if genus:
        prokka_cmd.extend(["--genus", genus])
    if species:
        prokka_cmd.extend(["--species", species])
    if strain:
        prokka_cmd.extend(["--strain", strain])

    # Run Prokka
    start_time = time.time()
    try:
        result = subprocess.run(
            prokka_cmd,
            check=True,
            capture_output=True,
            text=True,
        )
        success = True
        prokka_output = result.stdout
    except subprocess.CalledProcessError as e:
        success = False
        prokka_output = e.stderr
    except FileNotFoundError:
        return "ERROR: Prokka is not installed or not in PATH. Please install Prokka first."

    # Calculate runtime
    runtime = time.time() - start_time

    # Check if annotation was successful
    if not success:
        return f"ERROR: Genome annotation failed.\\n\\nProkka output:\\n{prokka_output}"

    # Parse annotation summary from Prokka output
    feature_counts = {}
    for line in prokka_output.split("\\n"):
        if "Found" in line and ":" in line:
            feature_type = line.split("Found")[1].split(":")[0].strip()
            count = line.split(":")[-1].strip()
            feature_counts[feature_type] = count

    # Generate research log
    log = f'''
GENOME ANNOTATION RESEARCH LOG

Input:
- Genome file: {genome_file_path}

Annotation Process:
- Tool: Prokka
- Runtime: {runtime:.2f} seconds
- Output directory: {output_dir}

Annotation Results:
'''

    # Add feature counts to log
    if feature_counts:
        for feature, count in feature_counts.items():
            log += f"- {feature}: {count}\\n"

    # List output files
    log += "\\nOutput Files:\\n"
    for file in os.listdir(output_dir):
        if file.startswith(prefix):
            file_path = os.path.join(output_dir, file)
            file_size = os.path.getsize(file_path) / 1024  # Size in KB
            log += f"- {file} ({file_size:.1f} KB)\\n"

    # Add explanation of key files
    log += '''
Key Output Files:
- .gff: Annotation in GFF3 format (contains all genomic features)
- .gbk: Annotation in GenBank format
- .faa: Protein sequences in FASTA format
- .ffn: Nucleotide sequences of genes in FASTA format
- .txt: Summary statistics of the annotation
'''

    return log

# Execute the function
try:
    result = annotate_bacterial_genome(
        genome_file_path=auto_convert(os.environ.get("PARAM_GENOME_FILE_PATH", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "annotation_results")),
        genus=auto_convert(os.environ.get("PARAM_GENUS", "")),
        species=auto_convert(os.environ.get("PARAM_SPECIES", "")),
        strain=auto_convert(os.environ.get("PARAM_STRAIN", "")),
        prefix=auto_convert(os.environ.get("PARAM_PREFIX", "")),
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
    "function": "annotate_bacterial_genome",
    "domain": "microbiology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("annotate_bacterial_genome_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("annotate_bacterial_genome_output.txt", "w") as f:
    f.write("Biomni: Annotate Bacterial Genome" + NL)
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
        biomni_function: "annotate_bacterial_genome"
    END_VERSIONS
    """
}

workflow ANNOTATE_BACTERIAL_GENOME_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANNOTATE_BACTERIAL_GENOME(ch_input)

    emit:
    results = ANNOTATE_BACTERIAL_GENOME.out.results
    output = ANNOTATE_BACTERIAL_GENOME.out.output
    versions = ANNOTATE_BACTERIAL_GENOME.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANNOTATE_BACTERIAL_GENOME_WORKFLOW(ch_input)

    ANNOTATE_BACTERIAL_GENOME_WORKFLOW.out.output.view { "Output: $it" }
}
