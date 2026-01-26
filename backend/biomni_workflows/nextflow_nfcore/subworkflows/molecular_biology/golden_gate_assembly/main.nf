#!/usr/bin/env nextflow
/*
 * molecular_biology/golden_gate_assembly
 * Simulate Golden Gate assembly to predict final construct sequences.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.backbone_sequence = null
params.enzyme_name = null
params.fragments = null
params.is_circular = null

process GOLDEN_GATE_ASSEMBLY {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("golden_gate_assembly_results.json"), emit: results
    tuple val(meta), path("golden_gate_assembly_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_BACKBONE_SEQUENCE="${params.backbone_sequence?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_ENZYME_NAME="${params.enzyme_name?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_FRAGMENTS="${params.fragments?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_IS_CIRCULAR="${params.is_circular?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
from typing import Any
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



def golden_gate_assembly(
    backbone_sequence: str,
    enzyme_name: str,
    fragments: list[dict[str, str]],
    is_circular: bool = True,
) -> dict[str, Any]:
    '''Simulate Golden Gate assembly to predict final construct sequences.

    Args:
        backbone_sequence (str): Complete backbone sequence
        enzyme_name (str): Type IIS restriction enzyme to be used (e.g., "BsmBI", "BsaI")
        fragments (List[Dict[str, str]]): List of fragments to insert, containing one of:
            - name + fwd_oligo + rev_oligo: Oligo pair with matching overhangs
            - name + sequence: Double-stranded DNA fragment containing restriction sites
        is_circular (bool): Whether the backbone is circular (default: True)

    Returns:
        Dict: Dictionary containing:
            - success: Boolean indicating if assembly was successful
            - assembled_sequence: The final assembled sequence
            - message: Error message if assembly failed

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
            "assembled_sequence": None,
        }

    # Get enzyme properties
    enzyme_props = TYPE_IIS_PROPERTIES[enzyme_name]
    recognition_site = enzyme_props["recognition_site"]
    offset_fwd = enzyme_props["offset_fwd"]
    offset_rev = enzyme_props["offset_rev"]

    # Prepare reverse complement function
    def reverse_complement(seq):
        '''Get the reverse complement of a DNA sequence.'''
        complement = {"A": "T", "T": "A", "G": "C", "C": "G"}
        return "".join(complement.get(base, "N") for base in reversed(seq))

    # Standardize and clean sequences
    backbone_sequence = backbone_sequence.upper()

    # Process fragments to ensure they all have fwd_oligo and rev_oligo
    processed_fragments = []

    for idx, fragment in enumerate(fragments):
        fragment_name = fragment.get("name", f"fragment_{idx + 1}")

        # Check if this is a double-stranded fragment (contains 'sequence' but not oligos)
        if "sequence" in fragment and not ("fwd_oligo" in fragment and "rev_oligo" in fragment):
            # Process the double-stranded fragment to extract oligos
            ds_sequence = fragment["sequence"].upper()

            # Find restriction sites in the fragment
            fwd_sites = []
            rev_sites = []
            rev_comp_site = reverse_complement(recognition_site)

            # Find forward sites
            for i in range(len(ds_sequence) - len(recognition_site) + 1):
                site_seq = ds_sequence[i : i + len(recognition_site)]
                if site_seq == recognition_site:
                    fwd_sites.append(i)
                elif site_seq == rev_comp_site:
                    rev_sites.append(i)

            # Need exactly two sites for Golden Gate (one in each direction)
            if len(fwd_sites) == 0 or len(rev_sites) == 0:
                return {
                    "success": False,
                    "message": f"Fragment '{fragment_name}' must contain at least one {enzyme_name} site in each orientation",
                    "assembled_sequence": None,
                }

            # Find the first forward and last reverse site
            fwd_site = fwd_sites[0]
            rev_site = rev_sites[-1]

            # Calculate cut positions
            fwd_cut = fwd_site + len(recognition_site) + offset_rev
            # Fix: For reverse sites, cut happens offset_rev bases BEFORE (not after) the site
            rev_cut = rev_site - offset_rev

            # If the forward cut is after the reverse cut, the fragment is invalid
            if fwd_cut >= rev_cut:
                return {
                    "success": False,
                    "message": f"Invalid restriction sites in fragment '{fragment_name}': sites must be oriented to excise the insert",
                    "assembled_sequence": None,
                }

            # Extract the insert sequence (between the cuts)
            insert_seq = ds_sequence[fwd_cut:rev_cut]
            print(insert_seq)

            # Extract the overhangs (4 bases for most Type IIS enzymes)
            fwd_overhang = ds_sequence[fwd_cut - 4 : fwd_cut]
            rev_overhang_rc = ds_sequence[rev_cut : rev_cut + 4]
            rev_overhang = reverse_complement(rev_overhang_rc)

            # Create equivalent oligos for assembly
            fwd_oligo = fwd_overhang + insert_seq
            rev_oligo = rev_overhang + reverse_complement(insert_seq)

            processed_fragments.append(
                {
                    "name": fragment_name,
                    "fwd_oligo": fwd_oligo,
                    "rev_oligo": rev_oligo,
                    "original_sequence": ds_sequence,
                }
            )

        # Handle traditional oligo format
        elif "fwd_oligo" in fragment and "rev_oligo" in fragment:
            processed_fragments.append(
                {
                    "name": fragment_name,
                    "fwd_oligo": fragment["fwd_oligo"],
                    "rev_oligo": fragment["rev_oligo"],
                }
            )
        else:
            return {
                "success": False,
                "message": f"Fragment '{fragment_name}' must contain either 'sequence' or both 'fwd_oligo' and 'rev_oligo'",
                "assembled_sequence": None,
            }
    print(processed_fragments)

    # Step 1: Find all restriction sites in the backbone
    restriction_sites = []
    # For every position in the backbone sequence
    for i in range(len(backbone_sequence)):
        # Check if this position starts a recognition site
        # Handle circular sequences by wrapping around
        if is_circular:
            # Check if we need to wrap around for the recognition site
            if i + len(recognition_site) > len(backbone_sequence):
                site_seq = (
                    backbone_sequence[i:] + backbone_sequence[: i + len(recognition_site) - len(backbone_sequence)]
                )
            else:
                site_seq = backbone_sequence[i : i + len(recognition_site)]
        # For linear sequences, just check if we're in bounds
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

    if not restriction_sites:
        return {
            "success": False,
            "message": f"No {enzyme_name} recognition sites found in the backbone",
            "assembled_sequence": None,
        }

    # Continue with the rest of the function using processed_fragments
    # (remaining code is unchanged, just operate on processed_fragments)

    # Step 2: Determine the cut positions and resulting overhangs
    cut_fragments = []

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

        # Ensure cut positions are valid
        if 0 <= cut_fwd < len(backbone_sequence) and 0 <= cut_rev < len(backbone_sequence):
            # Extract overhang sequence
            if cut_fwd < cut_rev:
                overhang = backbone_sequence[cut_fwd:cut_rev]
            else:  # Handle wrapping for circular sequences
                overhang = backbone_sequence[cut_fwd:] + backbone_sequence[:cut_rev]

            cut_fragments.append(
                {
                    "site_position": pos,
                    "strand": site["strand"],
                    "cut_fwd": cut_fwd,
                    "cut_rev": cut_rev,
                    "overhang": overhang,
                }
            )

    if not cut_fragments:
        return {
            "success": False,
            "message": f"Could not determine valid cut positions for {enzyme_name} sites",
            "assembled_sequence": None,
        }

    # Step 3: Extract fragment overhangs from oligos
    fragment_overhangs = []
    for idx, fragment in enumerate(processed_fragments):
        # Clean oligo sequences
        fwd_oligo = "".join(c for c in fragment.get("fwd_oligo", "").upper() if c in "ATGC")
        rev_oligo = "".join(c for c in fragment.get("rev_oligo", "").upper() if c in "ATGC")

        # Get the overhang length (typically 4 bases for most Type IIS enzymes)
        overhang_length = 4

        # Extract overhangs and insert sequence
        fwd_overhang = fwd_oligo[:overhang_length]
        rev_overhang = rev_oligo[:overhang_length]

        # The actual insert is everything after the overhang in the forward oligo
        insert_seq = fwd_oligo[overhang_length:]

        fragment_overhangs.append(
            {
                "name": fragment.get("name", f"fragment_{idx + 1}"),
                "fwd_overhang": fwd_overhang,
                "rev_overhang": rev_overhang,
                "insert": insert_seq,
                "rc_rev_overhang": reverse_complement(rev_overhang),
            }
        )

    # Step 4: For multi-fragment assembly, determine the correct order
    # Create a map of overhangs to fragments
    fwd_overhang_map = {}  # Maps fwd overhangs to fragment indices
    rev_overhang_map = {}  # Maps rev overhangs to fragment indices

    for i, frag in enumerate(fragment_overhangs):
        fwd_overhang_map[frag["fwd_overhang"]] = i
        rev_overhang_map[frag["rc_rev_overhang"]] = i

    # Try to identify an entry point where a fragment's fwd overhang matches a backbone cut
    possible_starts = []
    for cut_idx, cut in enumerate(cut_fragments):
        if cut["overhang"] in fwd_overhang_map:
            possible_starts.append((cut_idx, fwd_overhang_map[cut["overhang"]]))

    if not possible_starts:
        return {
            "success": False,
            "message": "Could not find an entry point for assembly. No backbone cuts match fragment overhangs.",
            "assembled_sequence": None,
        }

    # Try each possible starting point
    for start_cut_idx, start_frag_idx in possible_starts:
        # Assemble a chain of fragments starting from this one
        assembled_fragments = [start_frag_idx]
        current_frag_idx = start_frag_idx

        # Keep adding fragments until we can't find a matching one
        while True:
            current_frag = fragment_overhangs[current_frag_idx]
            next_overhang = current_frag["rc_rev_overhang"]

            # Check if this overhang matches another fragment's fwd overhang
            next_frag_idx = None
            for i, frag in enumerate(fragment_overhangs):
                if i != current_frag_idx and frag["fwd_overhang"] == next_overhang:
                    next_frag_idx = i
                    break

            if next_frag_idx is None:
                # No more fragments to add - check if this overhang matches a backbone cut
                break

            # Add this fragment to the chain and continue
            assembled_fragments.append(next_frag_idx)
            current_frag_idx = next_frag_idx

            # Prevent infinite loops by checking if we've used all fragments
            if len(assembled_fragments) >= len(processed_fragments):
                break

        # Check if we've used all fragments
        if len(assembled_fragments) == len(processed_fragments):
            # Check if the last fragment's overhang matches a backbone cut
            last_frag = fragment_overhangs[assembled_fragments[-1]]
            end_overhang = last_frag["rc_rev_overhang"]

            end_cut_idx = None
            for cut_idx, cut in enumerate(cut_fragments):
                if cut["overhang"] == end_overhang and cut_idx != start_cut_idx:
                    end_cut_idx = cut_idx
                    break

            if end_cut_idx is not None:
                # We have a complete assembly path!
                start_cut = cut_fragments[start_cut_idx]
                end_cut = cut_fragments[end_cut_idx]

                # Assemble the final sequence
                # First, extract the backbone segment we're keeping
                if is_circular:
                    # For circular plasmids, we keep the region between end_cut and start_cut
                    if end_cut["cut_rev"] <= start_cut["cut_fwd"]:
                        backbone_segment = backbone_sequence[end_cut["cut_rev"] : start_cut["cut_fwd"]]
                    else:
                        # Handle wrapping around the origin
                        backbone_segment = (
                            backbone_sequence[end_cut["cut_rev"] :] + backbone_sequence[: start_cut["cut_fwd"]]
                        )
                else:
                    # For linear backbones, we keep everything outside the cut region
                    backbone_segment = (
                        backbone_sequence[: min(start_cut["cut_fwd"], end_cut["cut_rev"])]
                        + backbone_sequence[max(start_cut["cut_fwd"], end_cut["cut_rev"]) :]
                    )

                # Then concatenate all fragment inserts in the correct order
                insert_segment = ""
                for i, frag_idx in enumerate(assembled_fragments):
                    # Include the overhang for the first fragment
                    if i == 0:
                        insert_segment += fragment_overhangs[frag_idx]["fwd_overhang"]

                    # Add the main insert sequence
                    insert_segment += fragment_overhangs[frag_idx]["insert"]

                    # Include the reverse overhang for each fragment
                    insert_segment += reverse_complement(fragment_overhangs[frag_idx]["rev_overhang"])

                # Final assembled sequence
                assembled_sequence = backbone_segment + insert_segment

                return {
                    "success": True,
                    "assembled_sequence": assembled_sequence,
                    "message": f"Successfully assembled {len(processed_fragments)} fragments in correct order",
                    "fragments_used": len(processed_fragments),
                    "cuts_used": 2,  # We use exactly 2 cuts for the assembly
                    "backbone_fragment_size": len(backbone_segment),
                    "assembly_order": [processed_fragments[i]["name"] for i in assembled_fragments],
                }

    # If we get here, we couldn't find a valid assembly
    return {
        "success": False,
        "message": "Could not find a valid assembly path. Fragment overhangs may not form a complete circuit.",
        "assembled_sequence": None,
    }

# Execute the function
try:
    result = golden_gate_assembly(
        backbone_sequence=auto_convert(os.environ.get("PARAM_BACKBONE_SEQUENCE", "")),
        enzyme_name=auto_convert(os.environ.get("PARAM_ENZYME_NAME", "")),
        fragments=auto_convert(os.environ.get("PARAM_FRAGMENTS", "")),
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
    "function": "golden_gate_assembly",
    "domain": "molecular_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("golden_gate_assembly_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("golden_gate_assembly_output.txt", "w") as f:
    f.write("Biomni: Golden Gate Assembly" + NL)
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
        biomni_function: "golden_gate_assembly"
    END_VERSIONS
    """
}

workflow GOLDEN_GATE_ASSEMBLY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    GOLDEN_GATE_ASSEMBLY(ch_input)

    emit:
    results = GOLDEN_GATE_ASSEMBLY.out.results
    output = GOLDEN_GATE_ASSEMBLY.out.output
    versions = GOLDEN_GATE_ASSEMBLY.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    GOLDEN_GATE_ASSEMBLY_WORKFLOW(ch_input)

    GOLDEN_GATE_ASSEMBLY_WORKFLOW.out.output.view { "Output: $it" }
}
