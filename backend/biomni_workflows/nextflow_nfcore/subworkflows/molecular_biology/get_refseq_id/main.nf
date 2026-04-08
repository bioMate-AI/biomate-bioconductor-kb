#!/usr/bin/env nextflow
/*
 * molecular_biology/get_refseq_id
 * Get RefSeq ID from gene record using NCBI Entrez.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Retrieve RefSeq ID for BRCA1 gene in human
params.gene_name = 'BRCA1'
params.organism = 'Homo sapiens'
params.email = 'test@example.com'

process GET_REFSEQ_ID {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("get_refseq_id_results.json"), emit: results
    tuple val(meta), path("get_refseq_id_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_GENE_NAME="${params.gene_name?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_ORGANISM="${params.organism?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_EMAIL="${params.email?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Self-contained implementation using NCBI Entrez API
from Bio import Entrez
import json
import os
import time
from urllib.error import HTTPError, URLError
from socket import timeout as SocketTimeout

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


def get_refseq_id(gene_name: str, organism: str, email: str = None) -> dict:
    '''Get RefSeq ID(s) for a gene symbol using NCBI Entrez.

    Args:
        gene_name: Name of the gene (e.g., 'BRCA1', 'TP53', 'INS')
        organism: Name of the organism (e.g., 'Homo sapiens', 'Mus musculus')
        email: Email address for NCBI Entrez (recommended for API access)

    Returns:
        Dictionary containing:
            - gene_name: The queried gene name
            - organism: The queried organism
            - gene_id: NCBI Gene ID
            - refseq_ids: List of RefSeq IDs (mRNA transcripts)
            - explanation: Description of the output fields

    Raises:
        ValueError: If no records found for the gene/organism combination
        RuntimeError: If NCBI is unavailable after retries
    '''
    if email:
        Entrez.email = email

    max_retries = 3

    def search_gene() -> str:
        '''Search for gene ID in NCBI Gene database.'''
        query = f"{organism}[Organism] AND {gene_name}[Gene]"
        last_error = None

        for attempt in range(max_retries):
            try:
                with Entrez.esearch(db="gene", term=query, retmax=5) as handle:
                    record = Entrez.read(handle)

                if not record["IdList"]:
                    raise ValueError(f"No records found for gene '{gene_name}' in organism '{organism}'")

                return record["IdList"][0]

            except (HTTPError, URLError, SocketTimeout) as e:
                last_error = e
                if attempt < max_retries - 1:
                    time.sleep(2 ** attempt)  # Exponential backoff
                    continue
                raise RuntimeError(f"NCBI unavailable after {max_retries} retries: {str(e)}")

        raise RuntimeError(f"NCBI unavailable after {max_retries} retries: {str(last_error)}")

    def get_refseq_ids_from_gene(gene_id: str) -> list:
        '''Get RefSeq IDs from gene record.'''
        last_error = None

        for attempt in range(max_retries):
            try:
                with Entrez.efetch(db="gene", id=gene_id, rettype="gb", retmode="xml") as handle:
                    gene_record = Entrez.read(handle)

                refseq_ids = []

                # Extract RefSeq IDs from the gene record structure
                try:
                    # Navigate through the gene record to find RefSeq accessions
                    locus_list = gene_record[0].get("Entrezgene_locus", [])
                    for locus in locus_list:
                        accession = locus.get("Gene-commentary_accession")
                        version = locus.get("Gene-commentary_version")
                        if accession and version:
                            refseq_ids.append(f"{accession}.{version}")

                        # Also check for products (mRNA transcripts)
                        products = locus.get("Gene-commentary_products", [])
                        for product in products:
                            prod_accession = product.get("Gene-commentary_accession")
                            prod_version = product.get("Gene-commentary_version")
                            if prod_accession and prod_version:
                                full_id = f"{prod_accession}.{prod_version}"
                                if full_id not in refseq_ids:
                                    refseq_ids.append(full_id)

                except (KeyError, IndexError, TypeError):
                    pass  # Continue with partial results

                return refseq_ids

            except (HTTPError, URLError, SocketTimeout) as e:
                last_error = e
                if attempt < max_retries - 1:
                    time.sleep(2 ** attempt)
                    continue
                raise RuntimeError(f"NCBI unavailable after {max_retries} retries: {str(e)}")

        raise RuntimeError(f"NCBI unavailable after {max_retries} retries: {str(last_error)}")

    # Main execution
    gene_id = search_gene()
    refseq_ids = get_refseq_ids_from_gene(gene_id)

    explanation = (
        "Output fields:\\n"
        "- gene_name: The queried gene symbol\\n"
        "- organism: The species searched\\n"
        "- gene_id: NCBI Gene database identifier\\n"
        "- refseq_ids: List of RefSeq accession numbers\\n"
        "  * NM_ prefix: mRNA transcript\\n"
        "  * NR_ prefix: non-coding RNA\\n"
        "  * NC_ prefix: genomic sequence (chromosome)\\n"
        "  * Example: NM_007294.4 for human BRCA1 mRNA"
    )

    return {
        "gene_name": gene_name,
        "organism": organism,
        "gene_id": gene_id,
        "refseq_ids": refseq_ids,
        "explanation": explanation
    }

# Execute the function
try:
    result = get_refseq_id(
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
    "function": "get_refseq_id",
    "domain": "molecular_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("get_refseq_id_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("get_refseq_id_output.txt", "w") as f:
    f.write("Biomni: Get RefSeq ID" + NL)
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
        biopython: \$(python3 -c "import Bio; print(Bio.__version__)")
        biomni_function: "get_refseq_id"
    END_VERSIONS
    """
}

workflow GET_REFSEQ_ID_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    GET_REFSEQ_ID(ch_input)

    emit:
    results = GET_REFSEQ_ID.out.results
    output = GET_REFSEQ_ID.out.output
    versions = GET_REFSEQ_ID.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    GET_REFSEQ_ID_WORKFLOW(ch_input)

    GET_REFSEQ_ID_WORKFLOW.out.output.view { "Output: $it" }
}
