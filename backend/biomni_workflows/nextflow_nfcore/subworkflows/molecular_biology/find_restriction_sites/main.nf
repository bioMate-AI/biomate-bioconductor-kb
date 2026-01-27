#!/usr/bin/env nextflow
/*
 * molecular_biology/find_restriction_sites
 * Identifies restriction enzyme sites in a given DNA sequence for specified enzymes.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.dna_sequence = null
params.enzymes = null
params.is_circular = null

process FIND_RESTRICTION_SITES {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("find_restriction_sites_results.json"), emit: results
    tuple val(meta), path("find_restriction_sites_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_DNA_SEQUENCE="${params.dna_sequence?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_ENZYMES="${params.enzymes?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_IS_CIRCULAR="${params.is_circular?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
from Bio import Restriction
from Bio.Seq import Seq
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



def find_restriction_sites(dna_sequence: str, enzymes: list, is_circular: bool = True) -> dict:
    '''Identifies restriction enzyme sites in a given DNA sequence for specified enzymes.'''
    # Validate inputs - use defaults if None
    if dna_sequence is None:
        dna_sequence = "ATGAATTCGAATTCATG"  # example with EcoRI site
    if enzymes is None:
        enzymes = ["EcoRI"]
    if is_circular is None:
        is_circular = False
    dna_sequence = str(dna_sequence)
    if isinstance(enzymes, str):
        enzymes = [enzymes]

    # Convert string to Bio.Seq object
    seq = Seq(dna_sequence.upper())

    # Create Analysis batch with specified enzymes
    rb = Restriction.RestrictionBatch(enzymes)

    # Analyze sequence for restriction sites, considering topology
    analysis = rb.search(seq, linear=not is_circular)

    results = {
        "explanation": (
            "Output fields:\\n"
            "- sequence_info: Information about the input sequence\\n"
            "  * length: Length of the sequence in base pairs\\n"
            "  * is_circular: Whether sequence is circular or linear\\n"
            "- restriction_sites: Dictionary of enzymes and their sites, where each contains:\\n"
            "  * recognition_sequence: The DNA sequence the enzyme recognizes\\n"
            "  * cut_positions: Details about where enzyme cuts relative to site\\n"
            "    - 5_prime: Cut position on 5' strand relative to start of recognition site\\n"
            "    - 3_prime: Cut position on 3' strand relative to start of recognition site\\n"
            "    - overhang: Length of overhang produced (negative for 3' overhang)\\n"
            "    - overhang_type: 'sticky' for overhanging cuts, 'blunt' for even cuts\\n"
            "  * sites: List of positions where enzyme cuts in the sequence (0-based)"
        ),
        "sequence_info": {
            "length": len(seq),
            "is_circular": is_circular,
        },
        "restriction_sites": {},
    }

    for enzyme, positions in analysis.items():
        if positions:
            enzyme_info = {
                "recognition_sequence": str(enzyme.elucidate()),
                "cut_positions": {
                    "5_prime": enzyme.fst5,
                    "3_prime": enzyme.fst3,
                    "overhang": enzyme.ovhg,
                    "overhang_type": "sticky" if enzyme.ovhg != 0 else "blunt",
                },
                "sites": sorted(positions),
            }
            results["restriction_sites"][str(enzyme)] = enzyme_info
        else:
            results["restriction_sites"][str(enzyme)] = {
                "recognition_sequence": str(enzyme.elucidate()),
                "cut_positions": {
                    "5_prime": enzyme.fst5,
                    "3_prime": enzyme.fst3,
                    "overhang": enzyme.ovhg,
                    "overhang_type": "sticky" if enzyme.ovhg != 0 else "blunt",
                },
                "sites": [],
            }

    return results

# Execute the function
try:
    result = find_restriction_sites(
        dna_sequence=auto_convert(os.environ.get("PARAM_DNA_SEQUENCE", "")),
        enzymes=auto_convert(os.environ.get("PARAM_ENZYMES", "")),
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
    "function": "find_restriction_sites",
    "domain": "molecular_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("find_restriction_sites_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("find_restriction_sites_output.txt", "w") as f:
    f.write("Biomni: Find Restriction Sites" + NL)
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
        biomni_function: "find_restriction_sites"
    END_VERSIONS
    """
}

workflow FIND_RESTRICTION_SITES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    FIND_RESTRICTION_SITES(ch_input)

    emit:
    results = FIND_RESTRICTION_SITES.out.results
    output = FIND_RESTRICTION_SITES.out.output
    versions = FIND_RESTRICTION_SITES.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    FIND_RESTRICTION_SITES_WORKFLOW(ch_input)

    FIND_RESTRICTION_SITES_WORKFLOW.out.output.view { "Output: $it" }
}
