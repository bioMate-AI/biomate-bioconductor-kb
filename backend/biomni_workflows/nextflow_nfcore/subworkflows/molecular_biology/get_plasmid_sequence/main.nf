#!/usr/bin/env nextflow
/*
 * molecular_biology/get_plasmid_sequence
 * Unified function to retrieve plasmid sequences from either Addgene or NCBI.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Retrieve pUC19 plasmid from NCBI
params.identifier = 'pUC19'
params.is_addgene = 'false'

process GET_PLASMID_SEQUENCE {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("get_plasmid_sequence_results.json"), emit: results
    tuple val(meta), path("get_plasmid_sequence_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_IDENTIFIER="${params.identifier?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_IS_ADDGENE="${params.is_addgene?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
from Bio import Entrez
from bs4 import BeautifulSoup
from typing import Any
from Bio import SeqIO
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



def get_plasmid_sequence(identifier: str, is_addgene: bool = None) -> dict[str, Any] | None:
    '''Unified function to retrieve plasmid sequences from either Addgene or NCBI.
    If is_addgene is True or identifier is numeric, uses Addgene.
    Otherwise searches NCBI using the plasmid name.

    Args:
        identifier (str): Either an Addgene ID or plasmid name
        is_addgene (bool, optional): Force Addgene lookup if True, force NCBI if False.
            If None, attempts to auto-detect based on identifier format.

    Returns:
        Optional[Dict[str, Any]]: The plasmid sequence and metadata if found, None otherwise

    '''

    def _get_sequence_from_addgene(plasmid_id: str) -> dict[str, Any] | None:
        '''Helper function to get sequence from Addgene.'''
        ADDGENE_BASE_URL = "https://www.addgene.org"
        ADDGENE_PLASMID_SEQUENCES_PATH = "/{plasmid_id}/sequences/"

        url = f"{ADDGENE_BASE_URL}{ADDGENE_PLASMID_SEQUENCES_PATH.format(plasmid_id=plasmid_id)}"
        response = requests.get(url)

        if response.status_code != 200:
            print(f"Failed to retrieve Addgene plasmid {plasmid_id}")
            return None

        soup = BeautifulSoup(response.content, "html.parser")
        textarea = soup.find("textarea", {"class": "copy-from"})

        if textarea:
            sequence_text = textarea.text.strip()
            lines = sequence_text.split("\\n")
            if lines[0].strip() == "> Addgene NGS Result":
                sequence = "".join(lines[1:]).replace(" ", "")
                return {
                    "explanation": (
                        "Output fields:\\n"
                        "- source: Source database (Addgene)\\n"
                        "- identifier: Addgene plasmid ID\\n"
                        "- sequence: Complete plasmid sequence"
                    ),
                    "source": "Addgene",
                    "identifier": plasmid_id,
                    "sequence": sequence,
                }

        print(f"No sequence found for Addgene plasmid {plasmid_id}")
        return None

    def _get_sequence_from_ncbi(plasmid_name: str) -> dict[str, Any] | None:
        '''Helper function to get sequence from NCBI with retry logic.'''
        import time
        from urllib.error import HTTPError

        max_retries = 3
        for attempt in range(max_retries):
            try:
                # First get the accession number
                query = f"Cloning vector {plasmid_name}"
                with Entrez.esearch(db="nuccore", term=query, retmax=1, sort="relevance") as handle:
                    record = Entrez.read(handle)

                if not record["IdList"]:
                    print(f"No results found for {plasmid_name} in NCBI.")
                    return None

                plasmid_id = record["IdList"][0]

                # Get the sequence using the accession
                with Entrez.efetch(db="nuccore", id=plasmid_id, rettype="fasta", retmode="text") as handle:
                    sequence = SeqIO.read(handle, "fasta")
                    return {
                        "explanation": (
                            "Output fields:\\n"
                            "- source: Source database (NCBI)\\n"
                            "- identifier: NCBI accession number\\n"
                            "- sequence: Complete plasmid sequence"
                        ),
                        "source": "NCBI",
                        "identifier": plasmid_id,
                        "sequence": str(sequence.seq),
                    }
            except HTTPError as e:
                # Retry on 5xx server errors
                if 500 <= e.code < 600 and attempt < max_retries - 1:
                    time.sleep(2 ** attempt)  # Exponential backoff
                    continue
                raise
            except Exception as e:
                print(f"Error retrieving sequence for {plasmid_name}: {str(e)}")
                return None
        return None

    # Auto-detect if is_addgene wasn't specified
    if is_addgene is None:
        is_addgene = identifier.isdigit()

    if is_addgene:
        return _get_sequence_from_addgene(identifier)
    else:
        return _get_sequence_from_ncbi(identifier)

# Execute the function
try:
    result = get_plasmid_sequence(
        identifier=auto_convert(os.environ.get("PARAM_IDENTIFIER", "")),
        is_addgene=auto_convert(os.environ.get("PARAM_IS_ADDGENE", "")),
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
    "function": "get_plasmid_sequence",
    "domain": "molecular_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("get_plasmid_sequence_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("get_plasmid_sequence_output.txt", "w") as f:
    f.write("Biomni: Get Plasmid Sequence" + NL)
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
        biomni_function: "get_plasmid_sequence"
    END_VERSIONS
    """
}

workflow GET_PLASMID_SEQUENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    GET_PLASMID_SEQUENCE(ch_input)

    emit:
    results = GET_PLASMID_SEQUENCE.out.results
    output = GET_PLASMID_SEQUENCE.out.output
    versions = GET_PLASMID_SEQUENCE.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    GET_PLASMID_SEQUENCE_WORKFLOW(ch_input)

    GET_PLASMID_SEQUENCE_WORKFLOW.out.output.view { "Output: $it" }
}
