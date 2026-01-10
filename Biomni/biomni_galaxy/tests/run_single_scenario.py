#!/usr/bin/env python3
"""
Run a single Biomni E2E scenario by index.
Usage: python run_single_scenario.py <scenario_index>
"""
import os
import sys
import time
from anthropic import Anthropic
from playwright.sync_api import sync_playwright

BASE_URL = "http://localhost:5000"
SCREENSHOT_DIR = "/home/yzhang/biomate/Biomni/biomni_galaxy/tests/screenshots"
os.makedirs(SCREENSHOT_DIR, exist_ok=True)

anthropic = Anthropic(api_key=os.environ.get("ANTHROPIC_API_KEY"))

BIOMNI_TEST_SCENARIOS = [
    {
        "name": "Single Tool - Database Query (query_uniprot)",
        "type": "single_tool",
        "domain": "database",
        "researcher_persona": """You are Dr. Kim, a protein biochemist.
You want to query UniProt database to get information about the BRCA1 protein.
You need the protein sequence and functional annotations.""",
        "initial_request": """I need to look up information about the BRCA1 protein from UniProt.
Can you help me query the database to get its sequence and functional annotations?""",
        "expected_tool": "biomni_database_query_uniprot"
    },
    {
        "name": "Single Tool - Genomics (gene_set_enrichment_analysis)",
        "type": "single_tool",
        "domain": "genomics",
        "researcher_persona": """You are Dr. Lee, a genomics researcher.
You have a list of differentially expressed genes and want to perform gene set enrichment analysis.
Gene list: BRCA1, TP53, EGFR, MYC, PTEN, RB1, AKT1, KRAS""",
        "initial_request": """I have a list of differentially expressed genes from my RNA-seq experiment.
Can you run gene set enrichment analysis on these genes: BRCA1, TP53, EGFR, MYC, PTEN, RB1, AKT1, KRAS?
I want to find which pathways and biological processes are enriched.""",
        "expected_tool": "biomni_genomics_gene_set_enrichment_analysis"
    },
    {
        "name": "Single Tool - Molecular Biology (design_primers)",
        "type": "single_tool",
        "domain": "molecular_biology",
        "researcher_persona": """You are Dr. Wang, a molecular biologist.
You need to design PCR primers for amplifying a specific gene region.
Target sequence: ATGCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCG""",
        "initial_request": """I need to design PCR primers for amplifying a gene region.
Here is my target sequence: ATGCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCG
Please design forward and reverse primers with Tm around 60C.""",
        "expected_tool": "biomni_molecular_biology_design_primers"
    },
    {
        "name": "Single Tool - Bioimaging (segment_cells)",
        "type": "single_tool",
        "domain": "bioimaging",
        "researcher_persona": """You are Dr. Patel, a cell biologist working with microscopy images.
You have fluorescence microscopy images and need to segment individual cells.
The images are DAPI-stained nuclei images.""",
        "initial_request": """I have fluorescence microscopy images of DAPI-stained cells.
I need to segment individual cells/nuclei from the images.
Can you help me with cell segmentation analysis?""",
        "expected_tool": "biomni_bioimaging_segment_cells"
    },
    {
        "name": "Single Tool - Pharmacology (predict_drug_target_interactions)",
        "type": "single_tool",
        "domain": "pharmacology",
        "researcher_persona": """You are Dr. Garcia, a pharmacologist studying drug-protein interactions.
You want to predict potential drug targets for a small molecule compound.
SMILES: CC(=O)OC1=CC=CC=C1C(=O)O (Aspirin)""",
        "initial_request": """I want to predict drug-target interactions for aspirin.
The SMILES structure is: CC(=O)OC1=CC=CC=C1C(=O)O
Can you identify potential protein targets this molecule might interact with?""",
        "expected_tool": "biomni_pharmacology_predict_drug_target_interactions"
    },
    {
        "name": "Subworkflow - scRNA Cell Type Annotation",
        "type": "subworkflow",
        "domain": "genomics",
        "researcher_persona": """You are Dr. Chen, a single-cell genomics researcher.
You have single-cell RNA-seq data in h5ad format and want to annotate cell types.
You need unsupervised cell type transfer from a reference dataset.""",
        "initial_request": """I have single-cell RNA-seq data that needs cell type annotation.
I have an annotated reference h5ad file and an unannotated query h5ad file.
Can you create a workflow to transfer cell type labels from the reference to my query data?
I want to use multiple methods like SCANVI and KNN-based approaches for consensus annotation.""",
        "expected_tool": "biomni_genomics_unsupervised_celltype_transfer"
    },
    {
        "name": "Workflow - Batch Image Registration (Progressive)",
        "type": "workflow_embedded",
        "domain": "bioimaging",
        "researcher_persona": """You are Dr. Smith, a bioimage analyst.
You have multiple microscopy images that need to be registered to a reference image.
You want progressive registration: rigid -> affine -> deformable.""",
        "initial_request": """I have a batch of microscopy images that need to be aligned to a reference image.
Can you create a complete workflow that performs progressive image registration?
I need: 1) rigid registration first, 2) then affine transformation, 3) then deformable registration.
The workflow should process all images in batch and output registered images with quality metrics.""",
        "expected_tool": "batch_register_images"
    },
    {
        "name": "Workflow - PCR Analysis with Primer Design",
        "type": "workflow_embedded",
        "domain": "molecular_biology",
        "researcher_persona": """You are Dr. Martinez, planning a PCR experiment.
You have a template sequence and need to design and verify primers.
You want alignment verification for the designed primers.""",
        "initial_request": """I need a complete PCR analysis workflow.
Given my template DNA sequence, I want to:
1. Design forward and reverse primers
2. Align and verify the primers against the template
3. Check for primer specificity
Can you create a workflow that handles the entire primer design and verification process?""",
        "expected_tool": "pcr_simple"
    }
]


def ai_user_responds(conversation_history, biomate_question, persona):
    system_prompt = f"""{persona}
IMPORTANT: Be confirmatory and direct. If BioMate suggests running a tool or workflow, say YES.
If asked about parameters, provide reasonable values."""
    messages = conversation_history + [{'role': 'user', 'content': f'BioMate asks: {biomate_question}'}]
    response = anthropic.messages.create(
        model='claude-sonnet-4-20250514',
        max_tokens=200,
        system=system_prompt,
        messages=messages
    )
    return response.content[0].text.strip()


def extract_biomate_response(page):
    try:
        page.wait_for_timeout(2000)
        messages = page.locator("[data-testid^='chat-message-']").all()
        if messages and len(messages) > 0:
            return messages[-1].inner_text()
    except:
        pass
    return None


def run_scenario(scenario_idx):
    if scenario_idx < 0 or scenario_idx >= len(BIOMNI_TEST_SCENARIOS):
        print(f"Invalid scenario index: {scenario_idx}. Must be 0-{len(BIOMNI_TEST_SCENARIOS)-1}")
        return False

    scenario = BIOMNI_TEST_SCENARIOS[scenario_idx]
    scenario_num = scenario_idx + 1

    print("=" * 80)
    print(f"SCENARIO {scenario_num}: {scenario['name']}")
    print(f"Type: {scenario['type']} | Domain: {scenario['domain']}")
    print("=" * 80)

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context(viewport={'width': 1600, 'height': 1000})
        page = context.new_page()

        # Register
        email = f'biomni_test_{int(time.time())}@biomate.test'
        password = 'TestPass123!'

        page.goto(f'{BASE_URL}/register')
        page.wait_for_timeout(2000)
        page.fill('#name', 'Biomni Tester')
        page.fill('#email', email)
        page.fill('#password', password)
        page.fill('#confirmPassword', password)
        page.click('#terms')
        page.click('button[type="submit"]')
        page.wait_for_timeout(5000)
        print(f'Registered: {email}')

        # Go to chat
        page.goto(BASE_URL)
        page.wait_for_timeout(3000)

        # Send request
        print(f'Sending: {scenario["initial_request"][:80]}...')
        chat_input = page.locator('textarea').first
        chat_input.fill(scenario['initial_request'])
        page.wait_for_timeout(500)
        chat_input.press('Enter')

        page.screenshot(path=f'{SCREENSHOT_DIR}/scenario_{scenario_num}_01_request.png')

        conversation_history = []
        success = False

        for turn in range(5):
            print(f'Turn {turn+1}: Waiting for response...')
            page.wait_for_timeout(20000)

            page.screenshot(path=f'{SCREENSHOT_DIR}/scenario_{scenario_num}_turn_{turn}.png', full_page=True)

            # Check for success indicators
            page_text = page.locator('body').inner_text().lower()

            indicators = [
                'workflow' in page_text,
                scenario['expected_tool'].lower().replace('_', ' ') in page_text,
                'tool' in page_text and scenario['domain'] in page_text,
            ]

            if any(indicators):
                print('Tool/workflow detected!')
                success = True
                break

            biomate_msg = extract_biomate_response(page)
            if biomate_msg:
                print(f'BioMate: {biomate_msg[:100]}...')
                ai_response = ai_user_responds(conversation_history, biomate_msg, scenario['researcher_persona'])
                print(f'AI User: {ai_response}')
                conversation_history.append({'role': 'user', 'content': biomate_msg})
                conversation_history.append({'role': 'assistant', 'content': ai_response})

                chat_input = page.locator('textarea').first
                chat_input.fill(ai_response)
                chat_input.press('Enter')
                page.wait_for_timeout(2000)

        page.screenshot(path=f'{SCREENSHOT_DIR}/scenario_{scenario_num}_final.png', full_page=True)
        browser.close()

    print("=" * 80)
    print(f"SCENARIO {scenario_num} RESULT: {'PASS' if success else 'FAIL'}")
    print("=" * 80)

    return success


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python run_single_scenario.py <scenario_index> (0-7)")
        print("\nAvailable scenarios:")
        for i, s in enumerate(BIOMNI_TEST_SCENARIOS):
            print(f"  {i}: {s['name']}")
        sys.exit(1)

    idx = int(sys.argv[1])
    success = run_scenario(idx)
    sys.exit(0 if success else 1)
