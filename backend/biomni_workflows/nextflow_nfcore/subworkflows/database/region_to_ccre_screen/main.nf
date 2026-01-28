#!/usr/bin/env nextflow
/*
 * database/region_to_ccre_screen
 * Given starting and ending coordinates, this function retrieves information of intersecting cCREs.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Find cCREs in the TP53 tumor suppressor gene region on chromosome 17
params.coord_chrom = 'chr17'
params.coord_start = '7571720'
params.coord_end = '7590868'
params.assembly = 'GRCh38'

process REGION_TO_CCRE_SCREEN {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("region_to_ccre_screen_results.json"), emit: results
    tuple val(meta), path("region_to_ccre_screen_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_COORD_CHROM="${params.coord_chrom?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_COORD_START="${params.coord_start?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_COORD_END="${params.coord_end?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_ASSEMBLY="${params.assembly?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import requests
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



def region_to_ccre_screen(coord_chrom: str, coord_start: int, coord_end: int, assembly: str = "GRCh38") -> str:
    '''Given starting and ending coordinates, this function retrieves information of intersecting cCREs.

    Args:
        assembly (str): Assembly of the genome, formatted like 'GRCh38'. Default is 'GRCh38'.
        coord_chrom (str): Chromosome of the gene, formatted like 'chr12'.
        coord_start (int): Starting chromosome coordinate.
        coord_end (int): Ending chromosome coordinate.

    Returns:
        str: A detailed string explaining the steps and the intersecting cCRE data or any error encountered.

    '''
    steps = []
    try:
        steps.append(
            f"Starting cCRE data retrieval for coordinates: {coord_chrom}:{coord_start}-{coord_end} (Assembly: {assembly})."
        )

        # Build the URL and request payload
        url = "https://screen-beta-api.wenglab.org/dataws/cre_table"
        data = {
            "assembly": assembly,
            "coord_chrom": coord_chrom,
            "coord_start": coord_start,
            "coord_end": coord_end,
        }

        steps.append("Sending POST request to API with the following data:")
        steps.append(str(data))

        # Make the request
        response = requests.post(url, json=data)

        # Check if the response is successful
        if not response.ok:
            raise Exception(f"Request failed with status code {response.status_code}. Response: {response.text}")

        steps.append("Request executed successfully. Parsing the response...")

        # Parse the JSON response
        response_json = response.json()
        if "errors" in response_json:
            raise Exception(f"API error: {response_json['errors']}")

        # Function to reduce and filter response data
        def reduce_tokens(res_json):
            # Remove unnecessary fields and round floats
            res = sorted(res_json["cres"], key=lambda x: x["dnase_zscore"], reverse=True)
            filtered_res = []

            for item in res:
                new_item = {
                    "chrom": item["chrom"],
                    "start": item["start"],
                    "len": item["len"],
                    "pct": item["pct"],
                    "ctcf_zscore": round(item["ctcf_zscore"], 2),
                    "dnase_zscore": round(item["dnase_zscore"], 2),
                    "enhancer_zscore": round(item["enhancer_zscore"], 2),
                    "promoter_zscore": round(item["promoter_zscore"], 2),
                    "accession": item["info"]["accession"],
                    "isproximal": item["info"]["isproximal"],
                    "concordance": item["info"]["concordant"],
                    "ctcfmax": round(item["info"]["ctcfmax"], 2),
                    "k4me3max": round(item["info"]["k4me3max"], 2),
                    "k27acmax": round(item["info"]["k27acmax"], 2),
                }
                filtered_res.append(new_item)
            return filtered_res

        # Process the response data
        filtered_data = reduce_tokens(response_json)

        if not filtered_data:
            steps.append(f"No intersecting cCREs found for coordinates: {coord_chrom}:{coord_start}-{coord_end}.")
            return "\\n".join(steps + ["No cCRE data available for this genomic region."])

        # Format the result into a readable string
        ccre_data_string = f"Intersecting cCREs for {coord_chrom}:{coord_start}-{coord_end} (Assembly: {assembly}):\\n"
        for i, ccre in enumerate(filtered_data, 1):
            ccre_data_string += (
                f"cCRE {i}:\\n"
                f"  Chromosome: {ccre['chrom']}\\n"
                f"  Start: {ccre['start']}\\n"
                f"  Length: {ccre['len']}\\n"
                f"  PCT: {ccre['pct']}\\n"
                f"  CTCF Z-score: {ccre['ctcf_zscore']}\\n"
                f"  DNase Z-score: {ccre['dnase_zscore']}\\n"
                f"  Enhancer Z-score: {ccre['enhancer_zscore']}\\n"
                f"  Promoter Z-score: {ccre['promoter_zscore']}\\n"
                f"  Accession: {ccre['accession']}\\n"
                f"  Is Proximal: {ccre['isproximal']}\\n"
                f"  Concordance: {ccre['concordance']}\\n"
                f"  CTCFmax: {ccre['ctcfmax']}\\n"
                f"  K4me3max: {ccre['k4me3max']}\\n"
                f"  K27acmax: {ccre['k27acmax']}\\n\\n"
            )

        steps.append(f"cCRE data successfully retrieved and formatted for {coord_chrom}:{coord_start}-{coord_end}.")
        return "\\n".join(steps + [ccre_data_string])

    except Exception as e:
        steps.append(f"Exception encountered: {str(e)}")
        return "\\n".join(steps + [f"Error: {str(e)}"])

# Execute the function
try:
    result = region_to_ccre_screen(
        coord_chrom=auto_convert(os.environ.get("PARAM_COORD_CHROM", "")),
        coord_start=auto_convert(os.environ.get("PARAM_COORD_START", "")),
        coord_end=auto_convert(os.environ.get("PARAM_COORD_END", "")),
        assembly=auto_convert(os.environ.get("PARAM_ASSEMBLY", "GRCh38")),
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
    "function": "region_to_ccre_screen",
    "domain": "database",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("region_to_ccre_screen_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("region_to_ccre_screen_output.txt", "w") as f:
    f.write("Biomni: Region To Ccre Screen" + NL)
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
        biomni_function: "region_to_ccre_screen"
    END_VERSIONS
    """
}

workflow REGION_TO_CCRE_SCREEN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    REGION_TO_CCRE_SCREEN(ch_input)

    emit:
    results = REGION_TO_CCRE_SCREEN.out.results
    output = REGION_TO_CCRE_SCREEN.out.output
    versions = REGION_TO_CCRE_SCREEN.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    REGION_TO_CCRE_SCREEN_WORKFLOW(ch_input)

    REGION_TO_CCRE_SCREEN_WORKFLOW.out.output.view { "Output: $it" }
}
