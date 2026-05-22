#!/usr/bin/env nextflow
/*
 * molecular_biology/design_golden_gate_oligos
 * Design oligos for Golden Gate assembly by identifying backbone overhangs
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: pUC19-derived backbone with BsaI Golden Gate sites for inserting GFP
// Backbone has GGTCTC (BsaI) sites with AAAA and TTTT overhangs
params.backbone_sequence = 'ATGACCATGATTACGCCAAGCTTGCATGCCTGCAGGTCGACTCTAGAGGATCCGGTCTCAAAATCTAGATCTCGAGCTCAAGCTTCGAATTCTGCAGTCGACGGTACCGCGGGCCCGGGATCCACCGGTCGCCACCATGGTGAGCAAGGGCGAGGAGCTGTTCACCGGGGTGGTGCCCATCCTGGTCGAGCTGGACGGCGACGTAAACGGCCACAAGTTCAGCGTGTCCGGCGAGGGCGAGGGCGATGCCACCTACGGCAAGCTGACCCTGAAGTTCATCTGCACCACCGGCAAGCTGCCCGTGCCCTGGCCCACCCTCGTGACCACCTTCGGCTACGGCCTGATGTGCTTTGCCCGCTACCCCGACGATTTTTAAAAAGAGACCAGCTTGGACTGGAACAATAAAGCCCTGGAAGATATTACAATCACTTTATTTTAATTAACTTTTTGTTTTAAAAATTAAATTAAACTATTTTCTTAATTAACTTTTTGTTTTAAAAATTAAATTAAACTATTTTCTTAACTTTTTTTCTTTTTTTTTTGGAACCCCCCCCCC'
params.insert_sequence = 'ATGGTGAGCAAGGGCGAGGAG'
params.enzyme_name = 'BsaI'
params.is_circular = 'true'

process DESIGN_GOLDEN_GATE_OLIGOS {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("design_golden_gate_oligos_results.json"), emit: results
    tuple val(meta), path("design_golden_gate_oligos_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_BACKBONE_SEQUENCE="${params.backbone_sequence?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_INSERT_SEQUENCE="${params.insert_sequence?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_ENZYME_NAME="${params.enzyme_name?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_IS_CIRCULAR="${params.is_circular?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
from typing import Any
import os
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



def design_golden_gate_oligos(
    backbone_sequence: str,
    insert_sequence: str,
    enzyme_name: str,
    is_circular: bool = True,
) -> dict[str, Any]:
    '''Design oligos for Golden Gate assembly by identifying backbone overhangs
    and creating matching insert oligos.

    Args:
        backbone_sequence (str): The plasmid/backbone sequence
        insert_sequence (str): Sequence to be inserted
        enzyme_name (str): Type IIS restriction enzyme to be used
        is_circular (bool): Whether the backbone is circular (default: True)

    Returns:
        Dict: Dictionary containing overhang information and designed oligos

    '''
    # Dictionary of enzyme properties
    TYPE_IIS_PROPERTIES = {
        "BsaI": {"recognition_site": "GGTCTC", "offset_fwd": 1, "offset_rev": 5},
        "BsmBI": {"recognition_site": "CGTCTC", "offset_fwd": 1, "offset_rev": 5},
        "BbsI": {"recognition_site": "GAAGAC", "offset_fwd": 2, "offset_rev": 6},
        "Esp3I": {"recognition_site": "CGTCTC", "offset_fwd": 1, "offset_rev": 5},
        "BtgZI": {"recognition_site": "GCGATG", "offset_fwd": 10, "offset_rev": 14},
        "SapI": {"recognition_site": "GCTCTTC", "offset_fwd": 1, "offset_rev": 4},
    }

    if enzyme_name not in TYPE_IIS_PROPERTIES:
        supported = ", ".join(TYPE_IIS_PROPERTIES.keys())
        return {
            "success": False,
            "message": f"Unsupported enzyme: {enzyme_name}. Currently supporting: {supported}",
        }

    # Clean input sequences
    backbone_sequence = "".join(c for c in backbone_sequence.upper() if c in "ATGC")
    insert_sequence = "".join(c for c in insert_sequence.upper() if c in "ATGC")

    # Get enzyme properties
    enzyme_props = TYPE_IIS_PROPERTIES[enzyme_name]
    recognition_site = enzyme_props["recognition_site"]
    offset_fwd = enzyme_props["offset_fwd"]
    offset_rev = enzyme_props["offset_rev"]

    # Reverse complement function
    def reverse_complement(seq):
        '''Get the reverse complement of a DNA sequence.'''
        complement = {"A": "T", "T": "A", "G": "C", "C": "G"}
        return "".join(complement.get(base, "N") for base in reversed(seq))

    # Step 1: Find all restriction sites in the backbone
    restriction_sites = []
    for i in range(len(backbone_sequence)):
        # Check if this position starts a recognition site
        if is_circular and i + len(recognition_site) > len(backbone_sequence):
            site_seq = backbone_sequence[i:] + backbone_sequence[: i + len(recognition_site) - len(backbone_sequence)]
        elif i + len(recognition_site) <= len(backbone_sequence):
            site_seq = backbone_sequence[i : i + len(recognition_site)]
        else:
            continue

        # Check forward strand recognition site
        if site_seq == recognition_site:
            restriction_sites.append({"position": i, "strand": "forward"})

        # Check reverse complement recognition site
        rev_comp_site = reverse_complement(recognition_site)
        if site_seq == rev_comp_site:
            restriction_sites.append({"position": i, "strand": "reverse"})

    if len(restriction_sites) < 2:
        return {
            "success": False,
            "message": f"Need at least 2 {enzyme_name} recognition sites in the backbone for Golden Gate assembly.",
        }

    # Step 2: Determine the cut positions and resulting overhangs
    cut_sites = []

    for site in restriction_sites:
        pos = site["position"]

        if site["strand"] == "forward":
            # Calculate cut positions for forward strand site
            cut_fwd = (pos + len(recognition_site) + offset_fwd) % len(backbone_sequence)
            cut_rev = (pos + len(recognition_site) + offset_rev) % len(backbone_sequence)
        else:  # reverse strand
            # For reverse sites, cuts happen on the other side of the recognition site
            cut_rev = (pos - offset_fwd) % len(backbone_sequence)
            cut_fwd = (pos - offset_rev) % len(backbone_sequence)

            if cut_rev < 0:
                cut_rev += len(backbone_sequence)
            if cut_fwd < 0:
                cut_fwd += len(backbone_sequence)

        # Extract overhang sequence
        if cut_fwd < cut_rev:
            overhang = backbone_sequence[cut_fwd:cut_rev]
        else:  # Handle wrapping for circular sequences
            overhang = backbone_sequence[cut_fwd:] + backbone_sequence[:cut_rev]

        cut_sites.append(
            {
                "site_position": pos,
                "strand": site["strand"],
                "cut_fwd": cut_fwd,
                "cut_rev": cut_rev,
                "overhang": overhang,
            }
        )

    # Step 3: For Golden Gate, identify the two overhangs that will flank the insert
    # This is simplified - in practice, you'd want to identify which cut sites
    # correspond to the destination for your insert

    # For demonstration, let's use the first two cut sites
    # In a real application, we would need a more sophisticated algorithm to identify
    # which sites are relevant to the insertion

    # We'll assume the first overhang goes at the 5' end of the insert
    # and the second overhang (reverse complemented) goes at the 3' end
    upstream_overhang = cut_sites[0]["overhang"]
    downstream_overhang = cut_sites[1]["overhang"]

    # Step 4: Design simple oligos with matching overhangs
    # For forward oligo, add the upstream overhang
    fw_oligo = upstream_overhang + insert_sequence

    # For reverse oligo, use reverse complement of insert + reverse complement of downstream overhang
    rev_oligo = reverse_complement(insert_sequence + reverse_complement(downstream_overhang))

    return {
        "success": True,
        "overhangs": {"upstream": upstream_overhang, "downstream": downstream_overhang},
        "oligos": {
            "forward": fw_oligo,
            "reverse": rev_oligo,
            "notes": [
                f"Forward oligo: Add {upstream_overhang} to 5' end of your insert",
                f"Reverse oligo: Add {reverse_complement(downstream_overhang)} to 5' end of reverse complement of your insert",
            ],
        },
        "cut_sites": [{"position": site["site_position"], "overhang": site["overhang"]} for site in cut_sites],
        "assembly_notes": f"Found {len(restriction_sites)} {enzyme_name} sites. Using overhangs {upstream_overhang} and {downstream_overhang} for assembly.",
    }

# Execute the function
try:
    result = design_golden_gate_oligos(
        backbone_sequence=auto_convert(os.environ.get("PARAM_BACKBONE_SEQUENCE", "")),
        insert_sequence=auto_convert(os.environ.get("PARAM_INSERT_SEQUENCE", "")),
        enzyme_name=auto_convert(os.environ.get("PARAM_ENZYME_NAME", "")),
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
    "function": "design_golden_gate_oligos",
    "domain": "molecular_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("design_golden_gate_oligos_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("design_golden_gate_oligos_output.txt", "w") as f:
    f.write("Biomni: Design Golden Gate Oligos" + NL)
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
        biomni_function: "design_golden_gate_oligos"
    END_VERSIONS
    """
}

workflow DESIGN_GOLDEN_GATE_OLIGOS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    DESIGN_GOLDEN_GATE_OLIGOS(ch_input)

    emit:
    results = DESIGN_GOLDEN_GATE_OLIGOS.out.results
    output = DESIGN_GOLDEN_GATE_OLIGOS.out.output
    versions = DESIGN_GOLDEN_GATE_OLIGOS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    DESIGN_GOLDEN_GATE_OLIGOS_WORKFLOW(ch_input)

    DESIGN_GOLDEN_GATE_OLIGOS_WORKFLOW.out.output.view { "Output: $it" }
}
