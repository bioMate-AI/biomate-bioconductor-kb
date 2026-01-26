#!/usr/bin/env nextflow
/*
 * genomics/analyze_chromatin_interactions
 * Analyze chromatin interactions from Hi-C data to identify enhancer-promoter interactions and TADs.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.hic_file_path = null
params.regulatory_elements_bed = null
params.output_dir = './output'

process ANALYZE_CHROMATIN_INTERACTIONS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_chromatin_interactions_results.json"), emit: results
    tuple val(meta), path("analyze_chromatin_interactions_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_HIC_FILE_PATH="${params.hic_file_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_REGULATORY_ELEMENTS_BED="${params.regulatory_elements_bed?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import pandas as pd
import os
import numpy as np
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



def analyze_chromatin_interactions(hic_file_path, regulatory_elements_bed, output_dir="./output"):
    '''Analyze chromatin interactions from Hi-C data to identify enhancer-promoter interactions and TADs.

    Parameters
    ----------
    hic_file_path : str
        Path to the Hi-C data file (.cool or .hic format)
    regulatory_elements_bed : str
        Path to BED file containing genomic coordinates of regulatory elements
        (enhancers, promoters, CTCF sites, etc.)
    output_dir : str
        Directory to save output files (default: "./output")

    Returns
    -------
    str
        Research log summarizing the analysis steps and results

    '''
    import cooler
    import numpy as np
    import pandas as pd
    from scipy import stats

    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)

    # Initialize research log
    log = []
    log.append("# Chromatin Interaction Analysis\\n")

    # Step 1: Load Hi-C data
    log.append("## Step 1: Loading Hi-C data")
    try:
        c = cooler.Cooler(hic_file_path)
        log.append(f"Successfully loaded Hi-C data from {hic_file_path}")
        log.append(f"Resolution: {c.binsize} bp")
        log.append(f"Chromosomes: {c.chromnames}")

        # Check if balancing weights are available
        has_weights = False
        try:
            # Try different ways to check for weights
            if (
                hasattr(c.bins(), "columns")
                and "weight" in c.bins().columns
                or hasattr(c.bins(), "keys")
                and "weight" in c.bins()
                or hasattr(c, "bins")
                and callable(c.bins)
                and "bins/weight" in c.bins()
            ):
                has_weights = True
        except Exception as e:
            log.append(f"Warning: Could not check for balancing weights: {str(e)}")

        if not has_weights:
            log.append("Warning: No balancing weights found in the cooler file. Using unbalanced data.")

        # Function to get matrix with proper balancing option
        def get_matrix(chrom, balance_if_possible=True):
            try:
                # Try to get balanced matrix if requested and available
                if balance_if_possible and has_weights:
                    return c.matrix(balance=True).fetch(chrom)
                else:
                    return c.matrix(balance=False).fetch(chrom)
            except Exception as e:
                log.append(f"Warning: Error getting matrix with balance={balance_if_possible}: {str(e)}")
                # If balanced fails, try unbalanced as fallback
                if balance_if_possible:
                    log.append("Falling back to unbalanced matrix")
                    return c.matrix(balance=False).fetch(chrom)
                else:
                    # If even unbalanced fails, raise the exception
                    raise e

    except Exception as e:
        log.append(f"Error loading Hi-C data: {str(e)}")
        return "\\n".join(log)

    # Step 2: Load regulatory elements
    log.append("\\n## Step 2: Loading regulatory elements")
    try:
        reg_elements = pd.read_csv(
            regulatory_elements_bed,
            sep="\\t",
            names=["chrom", "start", "end", "name", "score", "strand"],
        )
        log.append(f"Loaded {len(reg_elements)} regulatory elements")

        # Separate enhancers and promoters based on name field (assuming naming convention)
        enhancers = reg_elements[reg_elements["name"].str.contains("enhancer", case=False)]
        promoters = reg_elements[reg_elements["name"].str.contains("promoter", case=False)]
        log.append(f"Identified {len(enhancers)} enhancers and {len(promoters)} promoters")
    except Exception as e:
        log.append(f"Error loading regulatory elements: {str(e)}")
        return "\\n".join(log)

    # Step 3: Normalize Hi-C matrix using iterative correction
    log.append("\\n## Step 3: Normalizing Hi-C contact matrix")
    try:
        # Cooler already implements iterative correction (IC)
        log.append("Applying iterative correction to normalize for technical biases")
    except Exception as e:
        log.append(f"Error during normalization: {str(e)}")

    # Step 4: Identify significant interactions between regulatory elements
    log.append("\\n## Step 4: Identifying significant interactions")

    # Initialize results dataframe for enhancer-promoter interactions
    interactions = []

    try:
        # Process chromosome by chromosome
        for chrom in c.chromnames:
            log.append(f"Processing chromosome {chrom}...")

            # Get matrix for this chromosome using the helper function
            try:
                matrix = get_matrix(chrom, balance_if_possible=True)
            except Exception as e:
                log.append(f"Error getting matrix for chromosome {chrom}: {str(e)}")
                log.append(f"Skipping chromosome {chrom}")
                continue

            # Filter enhancers and promoters for this chromosome
            chrom_enhancers = enhancers[enhancers["chrom"] == chrom]
            chrom_promoters = promoters[promoters["chrom"] == chrom]

            if len(chrom_enhancers) == 0 or len(chrom_promoters) == 0:
                log.append(f"No enhancers or promoters found on chromosome {chrom}, skipping")
                continue

            # For each enhancer, find interactions with promoters
            for _, enh in chrom_enhancers.iterrows():
                enh_bin = int(enh["start"] // c.binsize)

                for _, prom in chrom_promoters.iterrows():
                    prom_bin = int(prom["start"] // c.binsize)

                    # Skip if bins are out of range
                    if enh_bin >= matrix.shape[0] or prom_bin >= matrix.shape[0]:
                        continue

                    # Get interaction strength
                    interaction_strength = matrix[enh_bin, prom_bin]

                    # Calculate expected interaction based on genomic distance
                    distance = abs(enh_bin - prom_bin)
                    if distance == 0:
                        continue

                    # Get average interaction at this distance
                    diag_values = np.diagonal(matrix, offset=distance)
                    expected = np.nanmean(diag_values) if len(diag_values) > 0 else 0

                    # Calculate significance (fold enrichment)
                    fold_enrichment = interaction_strength / expected if expected > 0 else 0

                    # Store significant interactions (fold enrichment > 2)
                    if fold_enrichment > 2:
                        interactions.append(
                            {
                                "chrom": chrom,
                                "enhancer_start": enh["start"],
                                "enhancer_end": enh["end"],
                                "enhancer_name": enh["name"],
                                "promoter_start": prom["start"],
                                "promoter_end": prom["end"],
                                "promoter_name": prom["name"],
                                "interaction_strength": interaction_strength,
                                "fold_enrichment": fold_enrichment,
                            }
                        )

        # Define interactions file path (moved before the empty check)
        interactions_file = os.path.join(output_dir, "enhancer_promoter_interactions.tsv")

        # Save interactions to file if any were found
        if interactions:
            interactions_df = pd.DataFrame(interactions)
            interactions_df.to_csv(interactions_file, sep="\\t", index=False)
            log.append(f"Identified {len(interactions)} significant enhancer-promoter interactions")
            log.append(f"Saved interactions to {interactions_file}")
        else:
            # Create an empty file with headers if no interactions were found
            pd.DataFrame(
                columns=[
                    "chrom",
                    "enhancer_start",
                    "enhancer_end",
                    "enhancer_name",
                    "promoter_start",
                    "promoter_end",
                    "promoter_name",
                    "interaction_strength",
                    "fold_enrichment",
                ]
            ).to_csv(interactions_file, sep="\\t", index=False)
            log.append("No significant enhancer-promoter interactions were identified")
            log.append(f"Created empty interactions file at {interactions_file}")
    except Exception as e:
        log.append(f"Error identifying interactions: {str(e)}")
        # Ensure the interactions_file variable is defined even in case of error
        interactions_file = os.path.join(output_dir, "enhancer_promoter_interactions.tsv")

    # Step 5: Call TADs using simple insulation score method
    log.append("\\n## Step 5: Identifying Topologically Associated Domains (TADs)")

    # Define tads_file early to ensure it's always available
    tads_file = os.path.join(output_dir, "topological_domains.bed")

    try:
        # We'll use a simple approach to identify TADs based on insulation scores
        # For a real analysis, specialized tools like tadbit or HiCExplorer would be better

        tad_results = []
        window_size = 5  # Window size for insulation score calculation

        for chrom in c.chromnames:
            if chrom not in c.chromsizes:
                continue

            # Get matrix with balancing if possible
            try:
                matrix = get_matrix(chrom, balance_if_possible=True)
            except Exception as e:
                log.append(f"Error getting matrix for chromosome {chrom}: {str(e)}")
                log.append(f"Skipping chromosome {chrom}")
                continue

            # Calculate insulation score
            insulation_score = np.zeros(matrix.shape[0] - 2 * window_size)
            for i in range(window_size, matrix.shape[0] - window_size):
                # Calculate sum of interactions crossing bin i
                cross_interactions = np.sum(matrix[i - window_size : i, i : i + window_size])
                insulation_score[i - window_size] = cross_interactions

            # Normalize insulation score
            if len(insulation_score) > 0:
                insulation_score = stats.zscore(insulation_score, nan_policy="omit")

                # Find local minima as TAD boundaries
                boundaries = []
                for i in range(1, len(insulation_score) - 1):
                    if (
                        insulation_score[i] < insulation_score[i - 1]
                        and insulation_score[i] < insulation_score[i + 1]
                        and insulation_score[i] < -1
                    ):  # Threshold for boundary strength
                        boundaries.append(i + window_size)

                # Define TADs as regions between boundaries
                if len(boundaries) > 1:
                    for i in range(len(boundaries) - 1):
                        start_bin = boundaries[i]
                        end_bin = boundaries[i + 1]

                        # Convert bin positions to genomic coordinates
                        start_pos = start_bin * c.binsize
                        end_pos = end_bin * c.binsize

                        tad_results.append(
                            {
                                "chrom": chrom,
                                "start": start_pos,
                                "end": end_pos,
                                "size_kb": (end_pos - start_pos) / 1000,
                            }
                        )

        # Save TADs to file if any were found
        tads_df = pd.DataFrame(tad_results)
        if not tads_df.empty:
            tads_df.to_csv(tads_file, sep="\\t", index=False)
            log.append(f"Identified {len(tad_results)} topologically associated domains")
            log.append(f"Average TAD size: {tads_df['size_kb'].mean():.2f} kb")
            log.append(f"Saved TADs to {tads_file}")
        else:
            # Create an empty file with headers if no TADs were found
            pd.DataFrame(columns=["chrom", "start", "end", "size_kb"]).to_csv(tads_file, sep="\\t", index=False)
            log.append("No topologically associated domains were identified")
            log.append(f"Created empty TADs file at {tads_file}")
    except Exception as e:
        log.append(f"Error calling TADs: {str(e)}")

    # Step 6: Generate chromatin interaction map for visualization
    log.append("\\n## Step 6: Generating chromatin interaction maps")

    # Define matrix_file early to ensure it's always available
    matrix_file = os.path.join(output_dir, "contact_matrix.npy")

    try:
        # Export normalized matrix for first chromosome as example
        if len(c.chromnames) > 0:
            chrom = c.chromnames[0]
            matrix_file = os.path.join(output_dir, f"{chrom}_contact_matrix.npy")

            # Get matrix with balancing if possible
            try:
                matrix = get_matrix(chrom, balance_if_possible=True)
                np.save(matrix_file, matrix)
                log.append(f"Saved contact matrix for {chrom} to {matrix_file}")
            except Exception as e:
                log.append(f"Error getting matrix for chromosome {chrom}: {str(e)}")
                # Create an empty matrix file
                np.save(matrix_file, np.zeros((10, 10)))  # Small placeholder
                log.append(f"Saved empty placeholder matrix to {matrix_file}")
        else:
            log.append("No chromosomes available for matrix export")
    except Exception as e:
        log.append(f"Error generating interaction maps: {str(e)}")

    # Step 7: Summary
    log.append("\\n## Summary")
    log.append(f"- Processed Hi-C data at {c.binsize} bp resolution")
    log.append(f"- Analyzed {len(reg_elements)} regulatory elements")

    # Make sure these are defined even if empty
    interactions = interactions if "interactions" in locals() else []
    tad_results = tad_results if "tad_results" in locals() else []

    log.append(f"- Identified {len(interactions)} significant enhancer-promoter interactions")
    log.append(f"- Called {len(tad_results)} topologically associated domains")
    log.append("\\nOutput files:")
    log.append(f"- Enhancer-promoter interactions: {interactions_file}")
    log.append(f"- Topological domains: {tads_file}")
    log.append(f"- Contact matrix: {matrix_file}")

    return "\\n".join(log)

# Execute the function
try:
    result = analyze_chromatin_interactions(
        hic_file_path=auto_convert(os.environ.get("PARAM_HIC_FILE_PATH", "")),
        regulatory_elements_bed=auto_convert(os.environ.get("PARAM_REGULATORY_ELEMENTS_BED", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "./output")),
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
    "function": "analyze_chromatin_interactions",
    "domain": "genomics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_chromatin_interactions_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_chromatin_interactions_output.txt", "w") as f:
    f.write("Biomni: Analyze Chromatin Interactions" + NL)
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
        biomni_function: "analyze_chromatin_interactions"
    END_VERSIONS
    """
}

workflow ANALYZE_CHROMATIN_INTERACTIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_CHROMATIN_INTERACTIONS(ch_input)

    emit:
    results = ANALYZE_CHROMATIN_INTERACTIONS.out.results
    output = ANALYZE_CHROMATIN_INTERACTIONS.out.output
    versions = ANALYZE_CHROMATIN_INTERACTIONS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_CHROMATIN_INTERACTIONS_WORKFLOW(ch_input)

    ANALYZE_CHROMATIN_INTERACTIONS_WORKFLOW.out.output.view { "Output: $it" }
}
