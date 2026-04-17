#!/usr/bin/env nextflow
/*
 * genomics/analyze_genomic_region_overlap
 * Analyze overlaps between two or more sets of genomic regions.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.region_sets = null
params.output_prefix = 'overlap_analysis'

process ANALYZE_GENOMIC_REGION_OVERLAP {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_genomic_region_overlap_results.json"), emit: results
    tuple val(meta), path("analyze_genomic_region_overlap_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_REGION_SETS="${params.region_sets?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_PREFIX="${params.output_prefix?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import pandas as pd
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



def analyze_genomic_region_overlap(region_sets, output_prefix="overlap_analysis"):
    '''Analyze overlaps between two or more sets of genomic regions.

    Parameters
    ----------
    region_sets : list
        List of genomic region sets. Each item can be either:
        - A string path to a BED file
        - A list of tuples/lists with format (chrom, start, end) or (chrom, start, end, name)
    output_prefix : str, optional
        Prefix for output files (default: "overlap_analysis")

    Returns
    -------
    str
        Research log summarizing the analysis steps and results

    '''
    from datetime import datetime

    import pandas as pd
    import pybedtools

    # Start research log
    log = "# Genomic Region Overlap Analysis\\n"
    log += f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\\n\\n"

    # Create BedTool objects from inputs
    bedtools = []
    set_names = []

    log += "## Input Processing\\n"
    for i, regions in enumerate(region_sets):
        set_name = f"Region_Set_{i + 1}"
        set_names.append(set_name)

        if isinstance(regions, str) and os.path.exists(regions):
            # Input is a file path
            bedtool = pybedtools.BedTool(regions)
            log += f"- Loaded {set_name} from file: {regions}\\n"
        else:
            # Input is a list of coordinates
            temp_bed_file = f"{output_prefix}_{set_name}.bed"
            with open(temp_bed_file, "w") as f:
                for region in regions:
                    if len(region) >= 3:
                        chrom, start, end = region[0], region[1], region[2]
                        name = region[3] if len(region) > 3 else f"feature_{i}"
                        f.write(f"{chrom}\\t{start}\\t{end}\\t{name}\\n")
            bedtool = pybedtools.BedTool(temp_bed_file)
            log += f"- Created {set_name} from {len(regions)} provided coordinates\\n"

        bedtools.append(bedtool)

    log += "\\n## Analysis Results\\n"

    # Calculate basic statistics for each set
    stats = []
    for i, bt in enumerate(bedtools):
        # Calculate total base pairs from start and end coordinates
        total_bp = sum(int(feature.end) - int(feature.start) for feature in bt)
        stats.append({"Set": set_names[i], "Regions": len(bt), "Total_BP": total_bp})

    # Create a results dataframe to store pairwise overlaps
    results = []

    # Perform pairwise overlaps
    for i in range(len(bedtools)):
        for j in range(i + 1, len(bedtools)):
            # Find overlaps using a simpler approach - just get the overlap regions
            try:
                # Use intersect with -u option to get unique overlapping features
                # and -wa option to get the original features from the first set
                overlapping_regions_a = bedtools[i].intersect(bedtools[j], u=True)

                # Get overlapping features from the second set
                overlapping_regions_b = bedtools[j].intersect(bedtools[i], u=True)

                # Calculate statistics
                overlap_regions_count_a = len(overlapping_regions_a)
                overlap_regions_count_b = len(overlapping_regions_b)

                # Now find the actual overlap coordinates using intersect with -wo
                # -wo outputs the original features plus the overlap length
                overlap_with_bases = bedtools[i].intersect(bedtools[j], wo=True)

                if len(overlap_with_bases) > 0:
                    # Extract overlap base pairs from the last column of -wo output
                    overlap_bp = 0
                    unique_overlaps = set()

                    for line in overlap_with_bases:
                        # The last field in -wo output is the overlap size in bases
                        # Convert all fields to strings first to handle different data types
                        fields = [str(field) for field in line]

                        # The actual overlap width is usually the last column with -wo
                        try:
                            # Get overlap width from last field
                            overlap_width = int(fields[-1])
                            overlap_bp += overlap_width

                            # Create a unique identifier for this overlap
                            # Using the coordinates from both sets
                            chrom_a = fields[0]
                            start_a = int(fields[1])
                            end_a = int(fields[2])
                            chrom_b = fields[len(fields) // 2]  # Middle field is typically the start of second feature
                            identifier = f"{chrom_a}:{start_a}-{end_a}_{chrom_b}"
                            unique_overlaps.add(identifier)
                        except (ValueError, IndexError) as e:
                            # If parsing fails, try an alternative approach
                            log += f"  Warning: Couldn't parse overlap width, falling back to alternative method: {str(e)}\\n"

                            # Alternative: manually calculate overlap from coordinates
                            try:
                                midpoint = len(fields) // 2
                                start_a = int(fields[1])
                                end_a = int(fields[2])
                                start_b = int(fields[midpoint + 1])
                                end_b = int(fields[midpoint + 2])

                                overlap_start = max(start_a, start_b)
                                overlap_end = min(end_a, end_b)

                                if overlap_end > overlap_start:
                                    overlap_bp += overlap_end - overlap_start
                            except (ValueError, IndexError):
                                # If even this fails, log the issue and continue
                                log += f"  Warning: Couldn't calculate overlap from: {fields}\\n"

                    # Number of unique overlapping regions
                    overlap_regions = len(unique_overlaps)

                    # Calculate percentages
                    pct_of_set1 = (overlap_bp / stats[i]["Total_BP"]) * 100 if stats[i]["Total_BP"] > 0 else 0
                    pct_of_set2 = (overlap_bp / stats[j]["Total_BP"]) * 100 if stats[j]["Total_BP"] > 0 else 0

                    results.append(
                        {
                            "Set1": set_names[i],
                            "Set2": set_names[j],
                            "Overlap_Regions": overlap_regions,
                            "Overlap_BP": overlap_bp,
                            "Pct_of_Set1": pct_of_set1,
                            "Pct_of_Set2": pct_of_set2,
                        }
                    )

                    # Save detailed overlaps to file
                    overlap_file = f"{output_prefix}_{set_names[i]}_{set_names[j]}_overlaps.bed"
                    overlap_with_bases.saveas(overlap_file)

                    log += f"- Between {set_names[i]} and {set_names[j]}:\\n"
                    log += f"  * Overlapping regions from set 1: {overlap_regions_count_a}\\n"
                    log += f"  * Overlapping regions from set 2: {overlap_regions_count_b}\\n"
                    log += f"  * Unique overlaps: {overlap_regions}\\n"
                    log += f"  * Total overlap size: {overlap_bp} bp\\n"
                    log += f"  * Percentage of {set_names[i]}: {pct_of_set1:.2f}%\\n"
                    log += f"  * Percentage of {set_names[j]}: {pct_of_set2:.2f}%\\n"
                    log += f"  * Detailed overlaps saved to: {overlap_file}\\n\\n"
                else:
                    # No overlaps found
                    results.append(
                        {
                            "Set1": set_names[i],
                            "Set2": set_names[j],
                            "Overlap_Regions": 0,
                            "Overlap_BP": 0,
                            "Pct_of_Set1": 0,
                            "Pct_of_Set2": 0,
                        }
                    )
                    log += f"- No overlaps found between {set_names[i]} and {set_names[j]}\\n\\n"
            except Exception as e:
                # Handle any errors during the intersection process
                log += f"Error analyzing overlap between {set_names[i]} and {set_names[j]}: {str(e)}\\n"
                results.append(
                    {
                        "Set1": set_names[i],
                        "Set2": set_names[j],
                        "Overlap_Regions": 0,
                        "Overlap_BP": 0,
                        "Pct_of_Set1": 0,
                        "Pct_of_Set2": 0,
                        "Error": str(e),
                    }
                )

    # Save summary statistics to file
    summary_file = f"{output_prefix}_summary.tsv"
    summary_df = pd.DataFrame(results)
    summary_df.to_csv(summary_file, sep="\\t", index=False)

    log += "## Summary\\n"
    log += f"- Total sets analyzed: {len(bedtools)}\\n"
    log += f"- Pairwise comparisons: {len(results)}\\n"
    log += f"- Summary statistics saved to: {summary_file}\\n"

    return log

# Execute the function
try:
    result = analyze_genomic_region_overlap(
        region_sets=auto_convert(os.environ.get("PARAM_REGION_SETS", "")),
        output_prefix=auto_convert(os.environ.get("PARAM_OUTPUT_PREFIX", "overlap_analysis")),
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
    "function": "analyze_genomic_region_overlap",
    "domain": "genomics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_genomic_region_overlap_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_genomic_region_overlap_output.txt", "w") as f:
    f.write("Biomni: Analyze Genomic Region Overlap" + NL)
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
        biomni_function: "analyze_genomic_region_overlap"
    END_VERSIONS
    """
}

workflow ANALYZE_GENOMIC_REGION_OVERLAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_GENOMIC_REGION_OVERLAP(ch_input)

    emit:
    results = ANALYZE_GENOMIC_REGION_OVERLAP.out.results
    output = ANALYZE_GENOMIC_REGION_OVERLAP.out.output
    versions = ANALYZE_GENOMIC_REGION_OVERLAP.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_GENOMIC_REGION_OVERLAP_WORKFLOW(ch_input)

    ANALYZE_GENOMIC_REGION_OVERLAP_WORKFLOW.out.output.view { "Output: $it" }
}
