#!/usr/bin/env nextflow
/*
 * synthetic_biology/engineer_bacterial_genome_for_therapeutic_delivery
 * Engineer a bacterial genome by integrating therapeutic genetic parts for therapeutic delivery.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: Uses inline-generated genome file
params.bacterial_genome_file = 'test_genome.fasta'
// Genetic parts for therapeutic IL-10 expression cassette
params.genetic_parts = '{"promoters": [{"name": "Ptac", "sequence": "AATTGTGAGCGGATAACAATT", "position": 100}], "genes": [{"name": "IL10", "sequence": "ATGCACAGCTCAGCACTGCTCTGTTGCCTGGTCCTCCTGACTGGGGTGAGGGCCAGCCCAGGCCAGGGCACCCAGTCTGAGAACAGCTGCACCCACTTCCCAGGCAACCTGCCTAACATGCTTCGAGATCTCCGAGATGCCTTCAGCAGAGTGAAGACTTTCTTTCAAATGAAGGATCAGCTGGACAACTTGTTGTTAAAGGAGTCCTTGCTGGAGGACTTTAAGGGTTACCTGGGTTGCCAAGCCTTGTCTGAGATGATCCAGTTTTACCTGGAGGAGGTGATGCCCCAAGCTGAGAACCAAGACCCAGACATCAAGGCGCATGTGAACTCCCTGGGGGAGAACCTGAAGACCCTCAGGCTGAGGCTACGGCGCTGTCATCGATTTCTTCCCTGTGAAAACAAGAGCAAGGCCGTGGAGCAGGTGAAGAATGCCTTTAATAAGCTCCAAGAGAAAGGCATCTACAAAGCCATGAGTGAGTTTGACATCTTCATCAACTACATAGAAGCCTACATGACAATGAAGATACGAAACTGA", "position": 200}], "terminators": [{"name": "T7term", "sequence": "CTAGCATAACCCCTTGGGGCCTCTAAACGGGTCTTGAGGGGTTTTTTG", "position": 1500}], "cargo": {"name": "therapeutic_IL10", "sequence": "ATGCACAGCTCAGCACTGCTCTGTTGCCTGGTCCTCCTGACTGGGGTGAGGGCCAGCCCAGGCCAGGGC"}}'

process ENGINEER_BACTERIAL_GENOME_FOR_THERAPEUTIC_DELIVERY {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("engineer_bacterial_genome_for_therapeutic_delivery_results.json"), emit: results
    tuple val(meta), path("engineer_bacterial_genome_for_therapeutic_delivery_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Create mock bacterial genome FASTA file for testing
    cat > test_genome.fasta << 'FASTAEOF'
>EcoliK12_mini
ATGAAACGCATTAGCACCACCATTACCACCACCATCACCATTACCACAGGTAACGGTGCGGGCTGACGCGTACAGGAAACACAGAAAAAAGCCCGCACCTGACAGTGCGGGCTTTTTTTTTCGACCAAAGGTAACGAGGTAACAACCATGCGAGTGTTGAAGTTCGGCGGTACATCAGTGGCAAATGCAGAACGTTTTCTGCGTGTTGCCGATATTCTGGAAAGCAATGCCAGGCAGGGGCAGGTGGCCACCGTCCTCTCTGCCCCCGCCAAAATCACCAACCACCTGGTGGCGATGATTGAAAAAACCATTAGCGGCCAGGATGCTTTACCCAATATCAGCGATGCCGAACGTATTTTTGCCGAACTTTTGACGGGACTCGCCGCCGCCCAGCCGGGGTTCCCGCTGGCGCAATTGAAAACTTTCGTCGATCAGGAATTTGCCCAAATAAA
FASTAEOF

    # Export parameters as environment variables
    export PARAM_BACTERIAL_GENOME_FILE="${params.bacterial_genome_file?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_GENETIC_PARTS="${params.genetic_parts?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def engineer_bacterial_genome_for_therapeutic_delivery(bacterial_genome_file, genetic_parts):
    '''Engineer a bacterial genome by integrating therapeutic genetic parts for therapeutic delivery.

    Parameters
    ----------
    bacterial_genome_file : str
        Path to the file containing the bacterial genome sequence in FASTA format
    genetic_parts : dict
        Dictionary containing genetic parts to be integrated::

        {
            'promoters': list of dict with 'name', 'sequence', and 'position',
            'genes': list of dict with 'name', 'sequence', and 'position',
            'terminators': list of dict with 'name', 'sequence', and 'position',
            'cargo': dict with 'name' and 'sequence' of the therapeutic cargo
        }

    Returns
    -------
    str
        Research log summarizing the engineering process, including the filename of the
        engineered genome and plasmid map

    '''
    import datetime

    from Bio import SeqIO
    from Bio.Graphics import GenomeDiagram
    from Bio.Seq import Seq
    from Bio.SeqFeature import FeatureLocation, SeqFeature
    from Bio.SeqRecord import SeqRecord
    from reportlab.lib import colors

    # Initialize research log
    log = ["# Bacterial Genome Engineering for Therapeutic Delivery\\n"]
    log.append(f"Date: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\\n")

    # Step 1: Load the bacterial genome
    log.append("## Step 1: Loading Bacterial Genome")
    try:
        genome_record = SeqIO.read(bacterial_genome_file, "fasta")
        genome_seq = genome_record.seq
        log.append(f"Successfully loaded genome: {genome_record.id}")
        log.append(f"Genome length: {len(genome_seq)} bp\\n")
    except Exception as e:
        log.append(f"Error loading genome: {str(e)}")
        return "\\n".join(log)

    # Step 2: Design and integrate genetic parts
    log.append("## Step 2: Integrating Genetic Parts")

    # Create a new genome sequence for modifications
    # In newer BioPython versions, Seq objects are mutable by default
    # or we can convert to a string and modify it, then convert back to Seq
    engineered_seq = str(genome_seq)

    # Track features for visualization
    features = []

    # Keep track of position adjustments as we add sequences
    position_adjustment = 0

    # Add promoters
    if "promoters" in genetic_parts:
        log.append("### Adding Promoters:")
        for promoter in genetic_parts["promoters"]:
            position = promoter["position"] + position_adjustment

            # Insert the sequence at the position
            engineered_seq = engineered_seq[:position] + promoter["sequence"] + engineered_seq[position:]
            position_adjustment += len(promoter["sequence"])

            # Adjust positions of subsequent elements
            for part_type in ["genes", "terminators"]:
                if part_type in genetic_parts:
                    for part in genetic_parts[part_type]:
                        if part["position"] > promoter["position"]:
                            part["position"] += len(promoter["sequence"])

            # Add feature for visualization
            feature = SeqFeature(
                FeatureLocation(position, position + len(promoter["sequence"])),
                type="promoter",
                qualifiers={"label": promoter["name"]},
            )
            features.append(feature)

            log.append(f"  - Added promoter {promoter['name']} at position {position}")

    # Add genes
    if "genes" in genetic_parts:
        log.append("### Adding Genes:")
        for gene in genetic_parts["genes"]:
            position = gene["position"] + position_adjustment

            # Insert the sequence at the position
            engineered_seq = engineered_seq[:position] + gene["sequence"] + engineered_seq[position:]
            position_adjustment += len(gene["sequence"])

            # Adjust positions of subsequent elements
            for part_type in ["terminators"]:
                if part_type in genetic_parts:
                    for part in genetic_parts[part_type]:
                        if part["position"] > gene["position"]:
                            part["position"] += len(gene["sequence"])

            # Add feature for visualization
            feature = SeqFeature(
                FeatureLocation(position, position + len(gene["sequence"])),
                type="gene",
                qualifiers={"label": gene["name"]},
            )
            features.append(feature)

            log.append(f"  - Added gene {gene['name']} at position {position}")

    # Add terminators
    if "terminators" in genetic_parts:
        log.append("### Adding Terminators:")
        for terminator in genetic_parts["terminators"]:
            position = terminator["position"] + position_adjustment

            # Insert the sequence at the position
            engineered_seq = engineered_seq[:position] + terminator["sequence"] + engineered_seq[position:]
            position_adjustment += len(terminator["sequence"])

            # Add feature for visualization
            feature = SeqFeature(
                FeatureLocation(position, position + len(terminator["sequence"])),
                type="terminator",
                qualifiers={"label": terminator["name"]},
            )
            features.append(feature)

            log.append(f"  - Added terminator {terminator['name']} at position {position}")

    # Add therapeutic cargo
    if "cargo" in genetic_parts:
        cargo = genetic_parts["cargo"]
        # Find a suitable position (after the last added element)
        position = max([f.location.end for f in features]) if features else len(engineered_seq) // 2

        # Insert the sequence at the position
        engineered_seq = engineered_seq[:position] + cargo["sequence"] + engineered_seq[position:]

        # Add feature for visualization
        feature = SeqFeature(
            FeatureLocation(position, position + len(cargo["sequence"])),
            type="therapeutic_cargo",
            qualifiers={"label": cargo["name"]},
        )
        features.append(feature)

        log.append("### Added Therapeutic Cargo:")
        log.append(f"  - Added {cargo['name']} at position {position}")
        log.append(f"  - Cargo length: {len(cargo['sequence'])} bp\\n")

    # Step 3: Create the engineered genome record
    log.append("## Step 3: Finalizing Engineered Genome")
    engineered_genome = SeqRecord(
        seq=Seq(engineered_seq),
        id=f"{genome_record.id}_engineered",
        name=f"{genome_record.id}_engineered",
        description=f"Engineered {genome_record.id} for therapeutic delivery",
    )

    # Add all features to the engineered genome
    engineered_genome.features = features

    # Save the engineered genome to a file
    output_genome_file = f"{genome_record.id}_engineered.fasta"
    SeqIO.write(engineered_genome, output_genome_file, "fasta")
    log.append(f"Engineered genome saved to: {output_genome_file}")
    log.append(f"Total genome length: {len(engineered_genome.seq)} bp\\n")

    # Step 4: Generate a plasmid map
    log.append("## Step 4: Generating Plasmid Map")

    # Create the diagram
    gd_diagram = GenomeDiagram.Diagram("Engineered Bacterial Genome")
    gd_track = gd_diagram.new_track(1, name="Engineered Features")
    gd_feature_set = gd_track.new_set()

    # Add features with different colors
    for feature in features:
        if feature.type == "promoter":
            color = colors.green
        elif feature.type == "gene":
            color = colors.blue
        elif feature.type == "terminator":
            color = colors.red
        elif feature.type == "therapeutic_cargo":
            color = colors.purple
        else:
            color = colors.grey

        gd_feature_set.add_feature(feature, color=color, label=True)

    # Draw and save the plasmid map
    plasmid_map_file = f"{genome_record.id}_engineered_map.pdf"
    gd_diagram.draw(format="circular", circular=True, pagesize=(1000, 1000))
    gd_diagram.write(plasmid_map_file, "PDF")

    log.append(f"Plasmid map generated and saved to: {plasmid_map_file}\\n")

    # Step 5: Final summary
    log.append("## Summary of Engineered Bacterial Strain")
    log.append(f"- Base strain: {genome_record.id}")
    log.append("- Added genetic parts:")

    if "promoters" in genetic_parts:
        log.append(f"  - Promoters: {len(genetic_parts['promoters'])}")
    if "genes" in genetic_parts:
        log.append(f"  - Genes: {len(genetic_parts['genes'])}")
    if "terminators" in genetic_parts:
        log.append(f"  - Terminators: {len(genetic_parts['terminators'])}")
    if "cargo" in genetic_parts:
        log.append(f"  - Therapeutic cargo: {genetic_parts['cargo']['name']}")

    log.append("\\nThe engineered bacterial strain is ready for transformation and selection.")

    return "\\n".join(log)

# Execute the function
try:
    result = engineer_bacterial_genome_for_therapeutic_delivery(
        bacterial_genome_file=auto_convert(os.environ.get("PARAM_BACTERIAL_GENOME_FILE", "")),
        genetic_parts=auto_convert(os.environ.get("PARAM_GENETIC_PARTS", "")),
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
    "function": "engineer_bacterial_genome_for_therapeutic_delivery",
    "domain": "synthetic_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("engineer_bacterial_genome_for_therapeutic_delivery_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("engineer_bacterial_genome_for_therapeutic_delivery_output.txt", "w") as f:
    f.write("Biomni: Engineer Bacterial Genome For Therapeutic Delivery" + NL)
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
        biomni_function: "engineer_bacterial_genome_for_therapeutic_delivery"
    END_VERSIONS
    """
}

workflow ENGINEER_BACTERIAL_GENOME_FOR_THERAPEUTIC_DELIVERY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ENGINEER_BACTERIAL_GENOME_FOR_THERAPEUTIC_DELIVERY(ch_input)

    emit:
    results = ENGINEER_BACTERIAL_GENOME_FOR_THERAPEUTIC_DELIVERY.out.results
    output = ENGINEER_BACTERIAL_GENOME_FOR_THERAPEUTIC_DELIVERY.out.output
    versions = ENGINEER_BACTERIAL_GENOME_FOR_THERAPEUTIC_DELIVERY.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ENGINEER_BACTERIAL_GENOME_FOR_THERAPEUTIC_DELIVERY_WORKFLOW(ch_input)

    ENGINEER_BACTERIAL_GENOME_FOR_THERAPEUTIC_DELIVERY_WORKFLOW.out.output.view { "Output: $it" }
}
