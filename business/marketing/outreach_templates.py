"""
BioMate Outreach Email Templates
==================================
Generates personalized, ready-to-send email drafts for each target.
Each email is tailored to the target's specific research domain and maps
2–3 BioMate workflows to their work.

Keep emails under 200 words — cold email best practice.
Subject line is included in the output.
"""

from typing import Any

# ── Workflow → plain-English description ────────────────────────────────────
WORKFLOW_DESCRIPTIONS = {
    "rnaseq":            "RNA-seq differential expression analysis",
    "scrna":             "single-cell RNA-seq clustering and cell-type annotation",
    "wgs":               "whole-genome sequencing variant calling and QC",
    "wes":               "whole-exome sequencing analysis",
    "atac_seq":          "ATAC-seq chromatin accessibility analysis",
    "chip_seq":          "ChIP-seq peak calling and motif discovery",
    "metagenomics":      "metagenomics community profiling and functional annotation",
    "16s-rrna":          "16S rRNA amplicon sequencing and OTU classification",
    "proteomics":        "LC-MS/MS proteomics (MaxQuant/DIA-NN) with QC governance",
    "drug-discovery":    "ADMET prediction, molecular docking, and pharmacogenomics",
    "pharmacogenomics":  "pharmacogenomics variant interpretation (CYP2D6, TPMT, DPYD)",
    "variant-calling":   "clinical-grade variant calling and annotation (GATK/DeepVariant)",
    "crispr":            "CRISPR on-/off-target analysis and guide RNA design",
    "protein-structure": "protein structure prediction (AlphaFold/ESM integration)",
    "molecular-docking": "molecular docking and binding affinity prediction",
    "functional-annotation": "functional gene annotation and pathway enrichment",
    "small-rna-seq":     "small RNA-seq (miRNA, piRNA) differential expression",
    "immunophenotyping": "flow cytometry immunophenotyping and immune subset analysis",
    "metabolomics":      "metabolomics data processing and pathway analysis",
    "spatial-transcriptomics": "spatial transcriptomics deconvolution and visualization",
}

# ── Segment-specific value propositions ─────────────────────────────────────
SEGMENT_VALUE_PROPS = {
    "academic": (
        "no Nextflow or Python required — describe your analysis in plain English and "
        "BioMate generates, configures, and runs the workflow automatically"
    ),
    "medical": (
        "HIPAA-ready QC governance with evidence-graded thresholds and full audit trails "
        "for clinical translation and regulatory submissions"
    ),
    "biotech": (
        "complete drug discovery pipeline — ADMET, pharmacogenomics, proteomics, and "
        "multi-omics integration — in one governed platform"
    ),
    "energy": (
        "metagenomics workflows purpose-built for reservoir microbiome characterization, "
        "bioremediation scale-up, and algae strain optimization"
    ),
    "doe_labs": (
        "BER-grade reproducibility with QC governance across 10,595 validated bioinformatics "
        "tools — the same pipeline QC rigor DOE peer review expects"
    ),
    "gulf_coast_academic": (
        "no Nextflow required — describe your analysis in plain English and BioMate "
        "generates and runs your pipeline with evidence-graded QC"
    ),
    "gulf_coast_energy": (
        "metagenomics QC and functional annotation workflows for environmental compliance "
        "monitoring and bioremediation acceleration"
    ),
    "ag_genomics": (
        "agricultural genomics pipelines — crop WGS, soil metagenomics, 16S OTU profiling — "
        "all QC-governed with reproducible, USDA-ready audit trails"
    ),
    "cro": (
        "21 CFR Part 11-ready audit trails, evidence-graded QC thresholds, and "
        "per-run override logging for FDA and ICH E6 compliant genomics workflows"
    ),
}

# ── Conference / outreach channel context ───────────────────────────────────
CONFERENCE_MENTIONS = {
    "ASHG":  "I noticed your lab's work from ASHG — ",
    "AACR":  "Following your recent work cited at AACR — ",
    "ISMB":  "Your work at ISMB/ECCB caught our attention — ",
    "PAG":   "Given your presentations at PAG — ",
    "DIA":   "As a CRO serving regulated genomics workflows — ",
    "AIChE": "Given the intersection of bioprocess engineering and genomics — ",
    "ISME":  "Your environmental genomics work at ISME — ",
}


def _pick_workflows(target: dict, n: int = 3) -> list:
    """Pick up to n workflows with known descriptions."""
    wfs = target.get("biomate_workflows", [])
    result = []
    for w in wfs:
        if w in WORKFLOW_DESCRIPTIONS:
            result.append(WORKFLOW_DESCRIPTIONS[w])
        if len(result) >= n:
            break
    return result


def _get_primary_contact(target: dict) -> dict:
    contacts = target.get("key_contacts", [])
    return contacts[0] if contacts else {"name": "Research Team", "title": "PI", "email_hint": ""}


def _get_value_prop(target: dict) -> str:
    seg = target.get("segment", "academic")
    # Exact match first, then prefix match
    if seg in SEGMENT_VALUE_PROPS:
        return SEGMENT_VALUE_PROPS[seg]
    for key in SEGMENT_VALUE_PROPS:
        if seg.startswith(key):
            return SEGMENT_VALUE_PROPS[key]
    return SEGMENT_VALUE_PROPS["academic"]


def generate_email(target: dict) -> str:
    """Generate a complete, personalized outreach email for the target."""
    contact = _get_primary_contact(target)
    name_parts = contact["name"].split()
    first_name = name_parts[0] if name_parts else "there"
    # Avoid "Dear Research Team"
    salutation = f"Dear Dr. {name_parts[-1]}" if first_name not in ("Research", "Dean", "Director") else "Dear Colleagues"

    workflows = _pick_workflows(target, n=3)
    org_name = target["name"]
    city = target.get("city", "")
    energy_link = target.get("energy_link", False)
    segment = target.get("segment", "academic")
    domains = target.get("domains", [])
    value_prop = _get_value_prop(target)
    priority = target.get("priority", "B")

    # Build the domain hook
    domain_hooks = {
        "metagenomics": "microbiome characterization and environmental genomics work",
        "cancer-genomics": "cancer multi-omics research",
        "rare-disease-genomics": "rare disease genomics program",
        "drug-discovery": "drug discovery pipeline",
        "bioremediation": "bioremediation genomics program",
        "algae-biofuels": "algae biofuels research",
        "meor": "microbially enhanced oil recovery research",
        "agricultural-genomics": "agricultural genomics program",
        "crop-genomics": "crop genomics program",
        "single-cell": "single-cell genomics work",
        "proteomics": "proteomics research",
        "clinical-genomics": "clinical genomics program",
        "pharmacogenomics": "pharmacogenomics program",
    }
    hook_phrase = "computational biology research"
    for d in domains:
        if d in domain_hooks:
            hook_phrase = domain_hooks[d]
            break

    # Build workflow list
    if workflows:
        wf_lines = "\n".join(f"  • {w}" for w in workflows)
        wf_section = f"\nFor your {hook_phrase}, BioMate handles:\n{wf_lines}\n"
    else:
        wf_section = f"\nBioMate handles the full computational biology stack — from raw sequencing to publication-ready results.\n"

    # Subject line
    subject_hooks = {
        "metagenomics": "metagenomics QC in minutes — BioMate beta invite",
        "cancer-genomics": "multi-omics cancer analysis — BioMate beta invite",
        "drug-discovery": "drug discovery workflows — BioMate beta invite",
        "bioremediation": "metagenomics for bioremediation — BioMate beta invite",
        "algae-biofuels": "algae strain optimization — BioMate beta invite",
        "clinical-genomics": "clinical genomics with audit trails — BioMate beta invite",
        "agricultural-genomics": "ag genomics pipelines — BioMate beta invite",
        "pharmacogenomics": "pharmacogenomics workflows — BioMate beta invite",
    }
    subject = "BioMate beta invite — AI-powered bioinformatics for your research"
    for d in domains:
        if d in subject_hooks:
            subject = f"[BioMate beta] {subject_hooks[d]}"
            break

    # Energy-specific paragraph
    energy_para = ""
    if energy_link:
        energy_para = (
            "\nGiven the energy-biology convergence in your work — whether that's reservoir microbiome "
            "characterization, bioremediation scale-up, or synthetic biology for biofuels — BioMate's "
            "metagenomics workflows include evidence-graded QC thresholds and full audit logs that keep "
            "industrial-scale analyses reproducible and compliance-ready.\n"
        )

    # CRO/clinical compliance paragraph
    compliance_para = ""
    if segment in ("cro", "clinical_lab"):
        compliance_para = (
            "\nAll workflows produce full audit trails with per-run QC logs, evidence-cited thresholds "
            "(GOLD/SILVER/BRONZE), and override records — designed from the ground up for 21 CFR Part 11 "
            "and ICH E6 compliant genomics operations.\n"
        )

    email = f"""Subject: {subject}

{salutation},

I'm reaching out because your {hook_phrase} at {org_name} is exactly the kind of work BioMate was built for.

BioMate is an AI-powered research execution platform for life sciences — researchers describe their analysis in plain English and BioMate generates, configures, and runs the workflow end-to-end. No Nextflow, no Python, no pipeline debugging.
{wf_section}The core differentiator: {value_prop}.
{energy_para}{compliance_para}
We're opening a limited closed beta with invite codes for researchers in Texas and the surrounding region. As a Priority-{priority} early adopter, you'd get:
  • Free professional-tier access for 90 days
  • Direct line to our engineering team for workflow requests
  • Co-authorship consideration on our benchmark papers (Nature Methods, Genome Biology)

Would you be open to a 20-minute demo, or shall I send you an invite code directly?

Best regards,
[Your Name]
BioMate AI | biomate.ai
[Your email] | [Your LinkedIn]

P.S. BioMate currently covers {len(target.get('biomate_workflows', []))} workflows directly relevant to your lab, backed by 10,595 validated bioinformatics tools and evidence-graded QC thresholds with published citations.
"""
    return email


def generate_follow_up_email(target: dict, days_since_first: int = 7) -> str:
    """Generate a brief follow-up email."""
    contact = _get_primary_contact(target)
    name_parts = contact["name"].split()
    salutation = f"Dr. {name_parts[-1]}" if name_parts[0] not in ("Research", "Dean", "Director") else "Colleagues"

    return f"""Subject: Re: BioMate beta — following up

Hi {salutation},

Just a quick follow-up on my note from {days_since_first} days ago about BioMate beta access.

I know your inbox is busy — if bioinformatics workflow automation isn't a priority right now, no worries at all. But if you'd like a quick look, I'm happy to send an invite code with no strings attached.

Best,
[Your Name]
"""


if __name__ == "__main__":
    # Quick self-test
    sample_target = {
        "id": "test",
        "name": "UT Southwestern — Lyda Hill Dept of Bioinformatics",
        "city": "Dallas", "state": "TX",
        "segment": "academic",
        "domains": ["multi-omics", "single-cell", "cancer-genomics"],
        "biomate_workflows": ["rnaseq", "scrna", "wgs", "proteomics"],
        "priority": "A",
        "energy_link": False,
        "key_contacts": [{"name": "Gaudenz Danuser", "title": "Chair", "email_hint": "g.danuser@utsouthwestern.edu"}],
    }
    print(generate_email(sample_target))
