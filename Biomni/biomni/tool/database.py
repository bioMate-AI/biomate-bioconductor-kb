"""
Biomni Database Tools - Non-LLM Functions Only

This module contains biological database query functions that do not require LLM.
LLM-dependent query functions have been removed as Galaxy tools are used instead.
"""

import time
from typing import Any

import requests
from Bio.Blast import NCBIWWW, NCBIXML
from Bio.Seq import Seq

from biomni.utils import parse_hpo_obo


def get_hpo_names(hpo_terms: list[str], data_lake_path: str) -> list[str]:
    """Retrieve the names of given HPO terms.

    Args:
        hpo_terms (List[str]): A list of HPO terms (e.g., ['HP:0001250']).
        data_lake_path (str): Path to the data lake containing hp.obo file.

    Returns:
        List[str]: A list of corresponding HPO term names.

    """
    hp_dict = parse_hpo_obo(data_lake_path + "/hp.obo")

    hpo_names = []
    for term in hpo_terms:
        name = hp_dict.get(term, f"Unknown term: {term}")
        hpo_names.append(name)
    return hpo_names


def blast_sequence(sequence: str, database: str, program: str) -> dict[str, str | float] | str:
    """Identifies a DNA sequence using NCBI BLAST with improved error handling, timeout management, and debugging.

    Args:
        sequence (str): The sequence to identify. If DNA, use database: core_nt, program: blastn;
                        if protein, use database: nr, program: blastp
        database (str): The BLAST database to search against
        program (str): The BLAST program to use

    Returns:
        dict: A dictionary containing the title, e-value, identity percentage, and coverage percentage of the best alignment

    """
    max_attempts = 1  # One initial attempt plus one retry
    attempts = 0
    max_runtime = 600  # 10 minutes in seconds

    while attempts < max_attempts:
        try:
            attempts += 1
            query_sequence = Seq(sequence)

            # Start timer
            start_time = time.time()

            # Submit BLAST job
            print(f"Submitting BLAST job (attempt {attempts}/{max_attempts})...")
            result_handle = NCBIWWW.qblast(
                program,
                database,
                query_sequence,
                expect=100,
                word_size=7,
                megablast=True,
            )

            # Parse results with timeout check
            blast_records = NCBIXML.parse(result_handle)
            blast_record = None

            # Try to get the first record with timeout check
            while time.time() - start_time < max_runtime:
                try:
                    # Set a short timeout for next operation
                    blast_record = next(blast_records)  # Get first record
                    break  # Successfully got the record
                except StopIteration:
                    # No more records
                    return "No BLAST results found"
                except Exception:
                    # Check if we've exceeded the time limit
                    if time.time() - start_time >= max_runtime:
                        if attempts < max_attempts:
                            print("BLAST job timeout exceeded. Resubmitting...")
                            break  # Break to retry
                        else:
                            return "BLAST search failed after maximum attempts due to timeout"
                    # Brief pause before trying again
                    time.sleep(1)

            # Check if we timed out during record retrieval
            if blast_record is None:
                if attempts < max_attempts:
                    continue  # Retry
                else:
                    return "BLAST search failed after maximum attempts due to timeout"

            # Debug information
            print(f"Number of alignments found: {len(blast_record.alignments)}")

            if blast_record.alignments:
                for alignment in blast_record.alignments:
                    print("\nAlignment:")
                    print(f"hit_id: {alignment.hit_id}")
                    print(f"hit_def: {alignment.hit_def}")
                    print(f"accession: {alignment.accession}")
                    for hsp in alignment.hsps:
                        print(f"E-value: {hsp.expect}")
                        print(f"Score: {hsp.score}")
                        print(f"Identities: {hsp.identities}/{hsp.align_length}")

                        return {
                            "hit_id": alignment.hit_id,
                            "hit_def": alignment.hit_def,
                            "accession": alignment.accession,
                            "e_value": hsp.expect,
                            "identity": (hsp.identities / float(hsp.align_length)) * 100,
                            "coverage": len(hsp.query) / len(sequence) * 100,
                        }
            else:
                return "No alignments found - sequence might be too short or low complexity"

        except Exception as e:
            if attempts < max_attempts:
                print(f"Error during BLAST search: {str(e)}. Retrying...")
                time.sleep(2)  # Wait briefly before retrying
            else:
                return f"Error during BLAST search after maximum attempts: {str(e)}"


def region_to_ccre_screen(coord_chrom: str, coord_start: int, coord_end: int, assembly: str = "GRCh38") -> str:
    """Given starting and ending coordinates, this function retrieves information of intersecting cCREs.

    Args:
        assembly (str): Assembly of the genome, formatted like 'GRCh38'. Default is 'GRCh38'.
        coord_chrom (str): Chromosome of the gene, formatted like 'chr12'.
        coord_start (int): Starting chromosome coordinate.
        coord_end (int): Ending chromosome coordinate.

    Returns:
        str: A detailed string explaining the steps and the intersecting cCRE data or any error encountered.

    """
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
            return "\n".join(steps + ["No cCRE data available for this genomic region."])

        # Format the result into a readable string
        ccre_data_string = f"Intersecting cCREs for {coord_chrom}:{coord_start}-{coord_end} (Assembly: {assembly}):\n"
        for i, ccre in enumerate(filtered_data, 1):
            ccre_data_string += (
                f"cCRE {i}:\n"
                f"  Chromosome: {ccre['chrom']}\n"
                f"  Start: {ccre['start']}\n"
                f"  Length: {ccre['len']}\n"
                f"  PCT: {ccre['pct']}\n"
                f"  CTCF Z-score: {ccre['ctcf_zscore']}\n"
                f"  DNase Z-score: {ccre['dnase_zscore']}\n"
                f"  Enhancer Z-score: {ccre['enhancer_zscore']}\n"
                f"  Promoter Z-score: {ccre['promoter_zscore']}\n"
                f"  Accession: {ccre['accession']}\n"
                f"  Is Proximal: {ccre['isproximal']}\n"
                f"  Concordance: {ccre['concordance']}\n"
                f"  CTCFmax: {ccre['ctcfmax']}\n"
                f"  K4me3max: {ccre['k4me3max']}\n"
                f"  K27acmax: {ccre['k27acmax']}\n\n"
            )

        steps.append(f"cCRE data successfully retrieved and formatted for {coord_chrom}:{coord_start}-{coord_end}.")
        return "\n".join(steps + [ccre_data_string])

    except Exception as e:
        steps.append(f"Exception encountered: {str(e)}")
        return "\n".join(steps + [f"Error: {str(e)}"])


def get_genes_near_ccre(accession: str, assembly: str, chromosome: str, k: int = 10) -> str:
    """Given a cCRE (Candidate cis-Regulatory Element), this function returns a string containing the
    steps it performs and the k nearest genes sorted by distance.

    Parameters
    ----------
    - accession (str): ENCODE Accession ID of query cCRE, e.g., EH38E1516980.
    - assembly (str): Assembly of the gene, e.g., 'GRCh38'.
    - chromosome (str): Chromosome of the gene, e.g., 'chr12'.
    - k (int): Number of nearby genes to return, sorted by distance. Default is 10.

    Returns
    -------
    - str: Steps performed and the result.

    """
    steps_log = (
        f"Starting process with accession: {accession}, assembly: {assembly}, chromosome: {chromosome}, k: {k}\n"
    )

    url = "https://screen-beta-api.wenglab.org/dataws/re_detail/nearbyGenomic"
    data = {"accession": accession, "assembly": assembly, "coord_chrom": chromosome}

    steps_log += "Sending POST request to API with given data.\n"
    response = requests.post(url, json=data)

    if not response.ok:
        steps_log += f"API request failed with response: {response.text}\n"
        return steps_log

    response_json = response.json()

    if "errors" in response_json:
        steps_log += f"API returned errors: {response_json['errors']}\n"
        return steps_log

    nearby_genes = response_json.get(accession, {}).get("nearby_genes", [])
    if not nearby_genes:
        steps_log += "No nearby genes found for the given accession.\n"
        return steps_log

    steps_log += "Successfully retrieved nearby genes. Sorting them by distance.\n"
    sorted_genes = sorted(nearby_genes, key=lambda x: x["distance"])[:k]

    steps_log += f"Returning the top {k} nearest genes.\n"
    steps_log += "Result:\n"

    for gene in sorted_genes:
        gene_name = gene.get("name", "Unknown")
        distance = gene.get("distance", "N/A")
        ensembl_id = gene.get("ensemblid_ver", "N/A")
        start = gene.get("start", "N/A")
        stop = gene.get("stop", "N/A")
        chrom = gene.get("chrom", "N/A")
        steps_log += f"Gene: {gene_name}, Distance: {distance}, Ensembl ID: {ensembl_id}, Chromosome: {chrom}, Start: {start}, Stop: {stop}\n"

    return steps_log
