#!/usr/bin/env nextflow
/*
 * synthetic_biology/identify_fas_functional_domains
 * Identifies functional domains within a Fatty Acid Synthase (FAS) sequence and predicts their roles.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: Sample FAS-like protein sequence fragment with ketoacyl synthase domain motifs
params.sequence = 'MGLFGKAIAGAGLEKVEGPGIEVEISVAECSGVAVSGTAFGLDEPDCWRLPPRVPKEWAAVPGQCIKSMKRYGGFVNSTNCGLATAAELHAADLVAHSPELLRAVLSGGVDAALSAGALRELEQQGWRRKPMVPLAGDLALAIQSSLLPLALQSTPEASPLPNVMGAIADGAVVVGDGGKVHLKFKAKGAGLRAEEIAEHLVHGAPTPVSAACTTSSACISVVQAMRALQSRGIEPRAVVACGGGAHLSPVELAEQIVAGCRIDFDVDNVKGPQPSDPMRVLSNYDALAGHLAGEYLGPVPLEKPDLLDAVKKGAELQATDVAYVUCHGAGTALGDPIEARALHAVSGRPRDFDPCRPRRVIGSVKTNIGHLEGAAGVAGVIKTVLALEHGVVLPATLHFAQNPSLPHDLDEHLRLIREAFNPVQQVLANTLPQIVTPANAPLVLMLTQCVEGRLGLSRPDGHKVGFCGGGAANVIVALLEGEKPPNATRGLAFRAVQRHSQDVGLPSTVFEYAPSIDAIAELQRQYQRLLVEAQPAELSRLVDDLVPRSPPEQLADVALLPQIAAAVRGLLVPGGFVILEMSAGIEAEASIAALHGLAPVNVEAAEIIAEARLAAEQKRKPAAAVPPALADLAADVAAVRPDRPVRVLAYIGAPVVRRSVASGQPAVAERYLKDYLAAYDLPRVDDEVALGQTSALGDLADFRPVAALDTGDLLEQAKLVQNATVTAEIAAFLAAHSAAVLAPHLLALQAELLGDDPALAAPAAVAEQLVRDVVRGLEAFSRDLGLAHSLFAPVRAEVDRQIAAHAELVETLRPASPAEPVAEAAAVETREAPSAPLPLAAIAETLAVLV'
params.sequence_type = 'protein'
params.output_file = 'fas_domains_report.txt'

process IDENTIFY_FAS_FUNCTIONAL_DOMAINS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("identify_fas_functional_domains_results.json"), emit: results
    tuple val(meta), path("identify_fas_functional_domains_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_SEQUENCE="${params.sequence?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SEQUENCE_TYPE="${params.sequence_type?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_FILE="${params.output_file?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def identify_fas_functional_domains(sequence, sequence_type="protein", output_file="fas_domains_report.txt"):
    '''Identifies functional domains within a Fatty Acid Synthase (FAS) sequence and predicts their roles.

    Parameters
    ----------
    sequence : str
        The nucleotide or protein sequence of a FAS gene
    sequence_type : str
        Type of sequence provided - "protein" or "nucleotide" (default: "protein")
    output_file : str
        Name of the output file to save the detailed domain report (default: "fas_domains_report.txt")

    Returns
    -------
    str
        A research log summarizing the steps taken and results of the domain analysis

    '''
    import json
    import time

    import requests
    from Bio.Seq import Seq

    research_log = "# Fatty Acid Synthase (FAS) Domain Analysis\\n\\n"
    research_log += "## Input Sequence Analysis\\n"
    research_log += f"- Sequence type: {sequence_type}\\n"
    research_log += (
        f"- Sequence length: {len(sequence)} {'nucleotides' if sequence_type == 'nucleotide' else 'amino acids'}\\n\\n"
    )

    # Convert nucleotide to protein if needed
    if sequence_type == "nucleotide":
        research_log += "## Sequence Translation\\n"
        research_log += "- Converting nucleotide sequence to protein\\n"
        try:
            protein_seq = str(Seq(sequence).translate())
            research_log += f"- Translated protein length: {len(protein_seq)} amino acids\\n\\n"
        except Exception as e:
            research_log += f"- Error in translation: {str(e)}\\n"
            return research_log
    else:
        protein_seq = sequence

    # FAS domain information dictionary
    fas_domains = {
        "ketoacyl-synt": {
            "name": "Ketoacyl Synthase (KS)",
            "function": "Catalyzes the condensation of malonyl-ACP with the growing fatty acid chain",
        },
        "Ketoacyl-synt_C": {
            "name": "Ketoacyl Synthase C-terminal (KS-C)",
            "function": "C-terminal domain of KS, involved in substrate binding",
        },
        "Acyl_transf_1": {
            "name": "Acyltransferase (AT)",
            "function": "Transfers acyl groups from acyl-CoA to ACP",
        },
        "ketoacyl-red": {
            "name": "Ketoacyl Reductase (KR)",
            "function": "Reduces the beta-ketoacyl group to a beta-hydroxyacyl group",
        },
        "Thioesterase": {
            "name": "Thioesterase (TE)",
            "function": "Releases the fatty acid from ACP by hydrolysis",
        },
        "PS-DH": {
            "name": "Dehydratase (DH)",
            "function": "Removes water from beta-hydroxyacyl-ACP to form trans-2-enoyl-ACP",
        },
        "Enoyl_red": {
            "name": "Enoyl Reductase (ER)",
            "function": "Reduces the double bond in enoyl-ACP to a saturated acyl-ACP",
        },
        "ACP": {
            "name": "Acyl Carrier Protein (ACP)",
            "function": "Carries the growing fatty acid chain between enzyme domains",
        },
        "PP-binding": {
            "name": "Phosphopantetheine Binding Domain",
            "function": "Attachment site for the phosphopantetheine prosthetic group in ACP",
        },
    }

    # HMMER web API for domain identification
    research_log += "## Domain Identification\\n"
    research_log += "- Using HMMER web API to search against Pfam database\\n"

    url = "https://www.ebi.ac.uk/Tools/hmmer/search/hmmscan"
    headers = {"Content-Type": "application/json", "Accept": "application/json"}
    data = {"hmmdb": "pfam", "seq": protein_seq}

    try:
        response = requests.post(url, data=json.dumps(data), headers=headers)
        if response.status_code != 200:
            research_log += f"- Error: HMMER API returned status code {response.status_code}\\n"
            return research_log

        result_url = response.headers.get("Location", "")
        if not result_url:
            research_log += "- Error: No result URL returned from HMMER API\\n"
            return research_log

        # Wait for results to be ready
        time.sleep(2)

        # Get results
        result_response = requests.get(f"{result_url}.json")
        if result_response.status_code != 200:
            research_log += "- Error: Could not retrieve results from HMMER API\\n"
            return research_log

        results = result_response.json()

        # Process results
        domains_found = []
        if "results" in results and "hits" in results["results"]:
            hits = results["results"]["hits"]
            for hit in hits:
                if "domains" in hit:
                    for domain in hit["domains"]:
                        domain_name = hit.get("name", "").split(".")[0]
                        domain_desc = hit.get("desc", "Unknown")
                        domain_start = domain.get("ali_from", 0)
                        domain_end = domain.get("ali_to", 0)

                        domains_found.append(
                            {
                                "name": domain_name,
                                "description": domain_desc,
                                "start": domain_start,
                                "end": domain_end,
                                "score": domain.get("score", 0),
                            }
                        )

        # Check for FAS domains
        research_log += f"- Found {len(domains_found)} domains in total\\n\\n"
        research_log += "## FAS Functional Domains Identified\\n"

        fas_domains_found = []
        for domain in domains_found:
            for fas_key, fas_info in fas_domains.items():
                if fas_key.lower() in domain["name"].lower():
                    fas_domains_found.append(
                        {
                            "name": fas_info["name"],
                            "pfam_id": domain["name"],
                            "start": domain["start"],
                            "end": domain["end"],
                            "function": fas_info["function"],
                        }
                    )

        if not fas_domains_found:
            research_log += "- No specific FAS domains identified in the sequence\\n"
        else:
            research_log += f"- Found {len(fas_domains_found)} FAS-related domains\\n"
            for i, domain in enumerate(fas_domains_found, 1):
                research_log += f"\\n### {i}. {domain['name']} (Positions {domain['start']}-{domain['end']})\\n"
                research_log += f"- Pfam ID: {domain['pfam_id']}\\n"
                research_log += f"- Function: {domain['function']}\\n"

        # Save detailed report to file
        with open(output_file, "w") as f:
            f.write("# Fatty Acid Synthase (FAS) Domain Analysis Detailed Report\\n\\n")
            f.write("## Input Sequence\\n")
            f.write(f"- Type: {sequence_type}\\n")
            f.write(f"- Length: {len(sequence)} {'nucleotides' if sequence_type == 'nucleotide' else 'amino acids'}\\n")
            if sequence_type == "nucleotide":
                f.write(f"- Translated protein length: {len(protein_seq)} amino acids\\n")

            f.write("\\n## All Domains Found\\n")
            for i, domain in enumerate(domains_found, 1):
                f.write(f"\\n### {i}. {domain['name']} (Positions {domain['start']}-{domain['end']})\\n")
                f.write(f"- Description: {domain['description']}\\n")
                f.write(f"- Score: {domain['score']}\\n")

            f.write("\\n## FAS Functional Domains\\n")
            if not fas_domains_found:
                f.write("- No specific FAS domains identified in the sequence\\n")
            else:
                for i, domain in enumerate(fas_domains_found, 1):
                    f.write(f"\\n### {i}. {domain['name']} (Positions {domain['start']}-{domain['end']})\\n")
                    f.write(f"- Pfam ID: {domain['pfam_id']}\\n")
                    f.write(f"- Function: {domain['function']}\\n")

        research_log += "\\n## Summary\\n"
        research_log += f"- Detailed domain analysis saved to: {output_file}\\n"
        if fas_domains_found:
            research_log += "- The sequence contains multiple domains characteristic of Fatty Acid Synthase\\n"
            research_log += "- The identified domains suggest this sequence is involved in fatty acid biosynthesis\\n"
        else:
            research_log += "- The sequence does not contain typical FAS domains\\n"
            research_log += "- This may not be a Fatty Acid Synthase gene or may be a partial sequence\\n"

    except Exception as e:
        research_log += f"- Error in domain identification: {str(e)}\\n"

    return research_log

# Execute the function
try:
    result = identify_fas_functional_domains(
        sequence=auto_convert(os.environ.get("PARAM_SEQUENCE", "")),
        sequence_type=auto_convert(os.environ.get("PARAM_SEQUENCE_TYPE", "protein")),
        output_file=auto_convert(os.environ.get("PARAM_OUTPUT_FILE", "fas_domains_report.txt")),
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
    "function": "identify_fas_functional_domains",
    "domain": "synthetic_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("identify_fas_functional_domains_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("identify_fas_functional_domains_output.txt", "w") as f:
    f.write("Biomni: Identify Fas Functional Domains" + NL)
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
        biomni_function: "identify_fas_functional_domains"
    END_VERSIONS
    """
}

workflow IDENTIFY_FAS_FUNCTIONAL_DOMAINS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    IDENTIFY_FAS_FUNCTIONAL_DOMAINS(ch_input)

    emit:
    results = IDENTIFY_FAS_FUNCTIONAL_DOMAINS.out.results
    output = IDENTIFY_FAS_FUNCTIONAL_DOMAINS.out.output
    versions = IDENTIFY_FAS_FUNCTIONAL_DOMAINS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    IDENTIFY_FAS_FUNCTIONAL_DOMAINS_WORKFLOW(ch_input)

    IDENTIFY_FAS_FUNCTIONAL_DOMAINS_WORKFLOW.out.output.view { "Output: $it" }
}
