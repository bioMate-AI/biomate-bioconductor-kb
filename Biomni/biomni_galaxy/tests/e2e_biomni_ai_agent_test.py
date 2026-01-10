#!/usr/bin/env python3
"""
Biomni AI Agent E2E Test
Uses Claude as a simulated researcher to test Biomni tools, subworkflows, and workflows
Tests via BioMate interface with AI-driven conversation
"""

import os
import time
from anthropic import Anthropic
from playwright.sync_api import sync_playwright

BASE_URL = "http://localhost:5000"
SCREENSHOT_DIR = "/home/yzhang/biomate/Biomni/biomni_galaxy/tests/screenshots"
os.makedirs(SCREENSHOT_DIR, exist_ok=True)

# Initialize Claude as the simulated user
anthropic = Anthropic(api_key=os.environ.get("ANTHROPIC_API_KEY"))

# Test scenarios for Biomni - covering single tools, subworkflows, and workflows
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


def ai_user_responds(conversation_history: list, biomate_question: str, persona: str) -> str:
    """
    AI agent acts as a researcher responding to BioMate's questions
    """

    system_prompt = f"""{persona}

IMPORTANT BEHAVIORS:
- When asked about your data or requirements, provide specific details
- Be confirmatory and direct to help trigger workflow/tool execution
- If asked to confirm parameters, say YES
- If BioMate suggests a specific tool or workflow, confirm it's what you need
- Help move the conversation toward tool execution

When BioMate asks questions, answer naturally but BE CONFIRMATORY and DIRECT.
"""

    messages = conversation_history + [{
        "role": "user",
        "content": f"BioMate asks: {biomate_question}\n\nYour response (be concise, 1-2 sentences):"
    }]

    response = anthropic.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=200,
        system=system_prompt,
        messages=messages
    )

    answer = response.content[0].text.strip()

    # Add to conversation history
    conversation_history.append({"role": "user", "content": biomate_question})
    conversation_history.append({"role": "assistant", "content": answer})

    return answer


def wait_for_ai_response(page, timeout_ms=60000):
    """
    Wait for AI to finish typing by checking for 'AI is typing...' to disappear
    """
    print("    Waiting for AI response to complete...")
    start_time = time.time()
    max_wait = timeout_ms / 1000

    # First wait for typing indicator to appear (AI started)
    page.wait_for_timeout(2000)

    # Then wait for it to disappear (AI finished)
    while time.time() - start_time < max_wait:
        typing_indicator = page.locator("text=AI is typing").first
        if typing_indicator.count() == 0:
            # No typing indicator - AI finished or never started
            page.wait_for_timeout(1000)  # Small buffer
            print(f"    AI response completed after {time.time() - start_time:.1f}s")
            return True
        page.wait_for_timeout(1000)

    print(f"    Timeout waiting for AI response after {max_wait}s")
    return False


def extract_biomate_response(page) -> str:
    """
    Extract the last response from BioMate in the chat
    """
    try:
        page.wait_for_timeout(2000)

        # Get all chat messages
        messages = page.locator("[data-testid^='chat-message-']").all()

        if messages and len(messages) > 0:
            last_message = messages[-1].inner_text()
            if last_message and len(last_message) > 20:
                return last_message

        # Fallback
        chat_container = page.locator("[data-testid='chat-messages']").first
        if chat_container.count() > 0:
            all_text = chat_container.inner_text()
            if all_text and len(all_text) > 50:
                return all_text

    except Exception as e:
        print(f"Error extracting message: {e}")
    return None


def run_biomni_scenario(page, scenario: dict, scenario_num: int) -> dict:
    """
    Run a single Biomni test scenario
    """
    result = {
        "name": scenario["name"],
        "type": scenario["type"],
        "domain": scenario["domain"],
        "success": False,
        "error": None,
        "turns": 0
    }

    print(f"\n{'='*80}")
    print(f"  SCENARIO {scenario_num}: {scenario['name']}")
    print(f"  Type: {scenario['type']} | Domain: {scenario['domain']}")
    print(f"{'='*80}")

    conversation_history = []

    try:
        # Send initial request
        print(f"\n[Initial Request]")
        print(f"Researcher: {scenario['initial_request'][:100]}...")

        chat_input = page.locator("textarea").first
        chat_input.fill(scenario['initial_request'])
        page.wait_for_timeout(500)
        chat_input.press("Enter")
        page.wait_for_timeout(2000)

        page.screenshot(path=f"{SCREENSHOT_DIR}/scenario_{scenario_num}_01_request.png")

        # Conversation loop - up to 6 turns
        for turn in range(6):
            result["turns"] = turn + 1
            print(f"\n[Turn {turn + 1}] Waiting for BioMate response...")

            # Wait for AI response to complete (up to 60s)
            wait_for_ai_response(page, timeout_ms=60000)

            page.screenshot(
                path=f"{SCREENSHOT_DIR}/scenario_{scenario_num}_turn_{turn}.png",
                full_page=True
            )

            # Check for workflow/tool generation - look for Run/Execute button
            run_btn = page.locator("button:has-text('Run')").first
            execute_btn = page.locator("button:has-text('Execute')").first
            start_workflow_btn = page.locator("button:has-text('Start Workflow')").first

            workflow_generated = run_btn.count() > 0 or execute_btn.count() > 0 or start_workflow_btn.count() > 0

            if workflow_generated:
                print(f"Workflow generated! Clicking Run/Execute...")
                page.screenshot(
                    path=f"{SCREENSHOT_DIR}/scenario_{scenario_num}_workflow_ready.png",
                    full_page=True
                )

                # Click Run, Execute, or Start Workflow button
                if run_btn.count() > 0:
                    run_btn.click()
                elif execute_btn.count() > 0:
                    execute_btn.click()
                elif start_workflow_btn.count() > 0:
                    start_workflow_btn.click()

                print("    Waiting for workflow execution...")
                page.wait_for_timeout(5000)

                # Wait for execution to complete - check for output indicators
                execution_timeout = 120  # 2 minutes max for execution
                start_exec = time.time()
                execution_complete = False

                while time.time() - start_exec < execution_timeout:
                    # Check for execution completion indicators
                    output_indicators = [
                        page.locator("text=Workflow completed").first,
                        page.locator("text=Execution complete").first,
                        page.locator("text=Results").first,
                        page.locator("[data-testid='workflow-output']").first,
                        page.locator("text=Output").first,
                        page.locator(".workflow-results").first,
                        # Check if new chat message appeared with results
                        page.locator("text=Here are the results").first,
                        page.locator("text=successfully").first,
                    ]

                    # Check for error indicators
                    error_indicators = [
                        page.locator("text=Error").first,
                        page.locator("text=failed").first,
                        page.locator("[data-testid='error-message']").first,
                    ]

                    if any(ind.count() > 0 for ind in output_indicators):
                        print(f"    Execution completed after {time.time() - start_exec:.1f}s")
                        execution_complete = True
                        result["success"] = True
                        break

                    if any(ind.count() > 0 for ind in error_indicators):
                        print(f"    Execution error detected after {time.time() - start_exec:.1f}s")
                        result["error"] = "Workflow execution failed"
                        break

                    # Also check if AI is still typing (processing results)
                    typing = page.locator("text=AI is typing").first
                    if typing.count() > 0:
                        page.wait_for_timeout(2000)
                        continue

                    page.wait_for_timeout(3000)

                page.screenshot(
                    path=f"{SCREENSHOT_DIR}/scenario_{scenario_num}_execution_result.png",
                    full_page=True
                )

                if result["success"]:
                    print("SUCCESS: Workflow executed with output!")
                    break
                elif not result.get("error"):
                    print(f"    Execution timeout after {execution_timeout}s")
                    result["error"] = "Execution timeout"
                break

            # Extract BioMate's response and continue conversation
            biomate_message = extract_biomate_response(page)

            if biomate_message and len(biomate_message) > 20:
                print(f"BioMate: {biomate_message[:150]}...")

                # AI agent responds
                ai_response = ai_user_responds(
                    conversation_history,
                    biomate_message,
                    scenario["researcher_persona"]
                )
                print(f"Researcher: {ai_response}")

                # Send response
                chat_input = page.locator("textarea").first
                chat_input.fill(ai_response)
                page.wait_for_timeout(1000)
                chat_input.press("Enter")
                page.wait_for_timeout(2000)
            else:
                print("No new message detected, waiting...")
                page.wait_for_timeout(10000)

        # Final check
        page.wait_for_timeout(10000)
        page.screenshot(
            path=f"{SCREENSHOT_DIR}/scenario_{scenario_num}_final.png",
            full_page=True
        )

    except Exception as e:
        result["error"] = str(e)
        print(f"Error: {e}")
        page.screenshot(
            path=f"{SCREENSHOT_DIR}/scenario_{scenario_num}_error.png",
            full_page=True
        )

    status = "PASS" if result["success"] else "FAIL"
    print(f"\nResult: {status} (Turns: {result['turns']})")

    return result


def run_biomni_e2e_test():
    """
    Run all Biomni E2E test scenarios
    """
    print("\n" + "="*80)
    print("  BIOMNI AI AGENT E2E TEST SUITE")
    print("  Testing: Single Tools, Subworkflows, Workflows with Embeddings")
    print("="*80)

    results = []

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context(viewport={"width": 1600, "height": 1000})
        page = context.new_page()

        try:
            # Register new user
            print("\n[SETUP] Registration")
            email = f"biomni_test_{int(time.time())}@biomate.test"
            password = "TestPass123!"

            page.goto(f"{BASE_URL}/register")
            page.wait_for_load_state("networkidle")

            # Wait for React to render the registration form
            print("    Waiting for registration form to load...")
            page.wait_for_selector("#name", state="visible", timeout=30000)
            print("    Registration form loaded")

            page.fill("#name", "Biomni Tester")
            page.fill("#email", email)
            page.fill("#password", password)
            page.fill("#confirmPassword", password)
            page.click("#terms")
            page.click("button[type='submit']")
            page.wait_for_timeout(5000)

            print(f"Registered: {email}")

            # Go to chat
            page.goto(BASE_URL)
            page.wait_for_timeout(3000)

            # Run each test scenario
            for i, scenario in enumerate(BIOMNI_TEST_SCENARIOS, 1):
                # Clear chat / start new conversation if possible
                new_chat_btn = page.locator("button:has-text('New Chat')").first
                if new_chat_btn.count() > 0:
                    new_chat_btn.click()
                    page.wait_for_timeout(2000)

                result = run_biomni_scenario(page, scenario, i)
                results.append(result)

                # Brief pause between scenarios
                page.wait_for_timeout(3000)

        except Exception as e:
            print(f"Test suite error: {e}")
            page.screenshot(path=f"{SCREENSHOT_DIR}/suite_error.png", full_page=True)

        finally:
            browser.close()

    # Print summary
    print("\n" + "="*80)
    print("  TEST SUMMARY")
    print("="*80)

    passed = sum(1 for r in results if r["success"])
    total = len(results)

    for r in results:
        status = "PASS" if r["success"] else "FAIL"
        error_msg = f" - {r['error'][:50]}" if r.get("error") else ""
        print(f"  [{status}] {r['name']} ({r['type']}, {r['turns']} turns){error_msg}")

    print(f"\nTotal: {passed}/{total} scenarios passed")
    print(f"Screenshots saved to: {SCREENSHOT_DIR}")
    print("="*80 + "\n")

    return results


if __name__ == "__main__":
    run_biomni_e2e_test()
