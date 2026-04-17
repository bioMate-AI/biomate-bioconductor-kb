#!/usr/bin/env nextflow
/*
 * molecular_biology/get_gene_coding_sequence
 * Retrieves the coding sequence(s) of a specified gene from NCBI Entrez.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Retrieve insulin gene coding sequence from human
params.gene_name = 'INS'
params.organism = 'Homo sapiens'
params.email = 'test@example.com'

process GET_GENE_CODING_SEQUENCE {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("get_gene_coding_sequence_results.json"), emit: results
    tuple val(meta), path("get_gene_coding_sequence_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_GENE_NAME="${params.gene_name?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_ORGANISM="${params.organism?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_EMAIL="${params.email?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
from Bio import Entrez
from Bio import SeqIO
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



def get_gene_coding_sequence(gene_name: str, organism: str, email: str = None) -> list[dict[str, str]]:
    '''Retrieves the coding sequence(s) of a specified gene from NCBI Entrez.

    Args:
        gene_name: Name of the gene
        organism: Name of the organism
        email: Email address for NCBI Entrez (recommended)

    Returns:
        List of dictionaries containing:
            - refseq_id: RefSeq ID of the gene
            - sequence: Coding sequence of the gene

    '''
    if email:
        Entrez.email = email

    def search_gene() -> str:
        '''Search for gene ID in NCBI database.'''
        query = f"{organism}[Organism] AND {gene_name}[Gene]"
        with Entrez.esearch(db="gene", term=query, retmax=5) as handle:
            record = Entrez.read(handle)

        if not record["IdList"]:
            raise ValueError(f"No records found for gene '{gene_name}' in organism '{organism}'")

        return record["IdList"][0]

    def get_refseq_id(gene_id: str) -> str:
        '''Get RefSeq ID from gene record.'''
        with Entrez.efetch(db="gene", id=gene_id, rettype="gb", retmode="xml") as handle:
            gene_record = Entrez.read(handle)

        try:
            locus = gene_record[0]["Entrezgene_locus"][0]
            accession = locus["Gene-commentary_accession"]
            version = locus["Gene-commentary_version"]
            return f"{accession}.{version}"
        except (KeyError, IndexError) as e:
            raise RuntimeError(f"Unable to process gene record: {e}") from None

    def get_coding_sequences(refseq_id: str) -> list[dict[str, str]]:
        '''Extract coding sequences from RefSeq record.'''
        with Entrez.efetch(db="nucleotide", id=refseq_id, rettype="gbwithparts", retmode="text") as handle:
            seq_record = SeqIO.read(handle, "genbank")

        sequences = []
        for feature in seq_record.features:
            if feature.type == "CDS" and feature.qualifiers.get("gene", ["N/A"])[0] == gene_name:
                cds_seq = feature.location.extract(seq_record).seq
                sequences.append({"refseq_id": refseq_id, "sequence": str(cds_seq)})

        return sequences

    # Main execution flow with retry logic for transient HTTP errors
    import time
    from urllib.error import HTTPError

    max_retries = 3
    last_error = None

    for attempt in range(max_retries):
        try:
            gene_id = search_gene()
            refseq_id = get_refseq_id(gene_id)
            sequences = get_coding_sequences(refseq_id)

            explanation = (
                "Output fields for each coding sequence:\\n"
                "- refseq_id: RefSeq identifier for the gene sequence\\n"
                "  * Format: NM_XXXXXX.X for mRNA or NC_XXXXXX.X for genomic DNA\\n"
                "  * Example: NM_000546.5 for human TP53\\n"
                "- sequence: The actual coding sequence of the gene\\n"
                "  * Contains only exons (introns removed)\\n"
                "  * Starts with ATG (start codon)\\n"
                "  * Ends with a stop codon (TAA, TAG, or TGA)"
            )

            return {"explanation": explanation, "sequences": sequences}

        except HTTPError as e:
            last_error = e
            # Retry on 5xx server errors
            if 500 <= e.code < 600 and attempt < max_retries - 1:
                time.sleep(2 ** attempt)  # Exponential backoff: 1s, 2s, 4s
                continue
            raise RuntimeError(f"Failed to retrieve coding sequences: {str(e)}") from e
        except Exception as e:
            raise RuntimeError(f"Failed to retrieve coding sequences: {str(e)}") from e

    raise RuntimeError(f"Failed to retrieve coding sequences after {max_retries} retries: {str(last_error)}")

# Execute the function
try:
    result = get_gene_coding_sequence(
        gene_name=auto_convert(os.environ.get("PARAM_GENE_NAME", "")),
        organism=auto_convert(os.environ.get("PARAM_ORGANISM", "")),
        email=auto_convert(os.environ.get("PARAM_EMAIL", "")),
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
    "function": "get_gene_coding_sequence",
    "domain": "molecular_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("get_gene_coding_sequence_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("get_gene_coding_sequence_output.txt", "w") as f:
    f.write("Biomni: Get Gene Coding Sequence" + NL)
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
        biomni_function: "get_gene_coding_sequence"
    END_VERSIONS
    """
}

workflow GET_GENE_CODING_SEQUENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    GET_GENE_CODING_SEQUENCE(ch_input)

    emit:
    results = GET_GENE_CODING_SEQUENCE.out.results
    output = GET_GENE_CODING_SEQUENCE.out.output
    versions = GET_GENE_CODING_SEQUENCE.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    GET_GENE_CODING_SEQUENCE_WORKFLOW(ch_input)

    GET_GENE_CODING_SEQUENCE_WORKFLOW.out.output.view { "Output: $it" }
}
