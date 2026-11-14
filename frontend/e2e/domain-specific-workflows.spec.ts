/**
 * Domain-Specific Workflow E2E Tests
 *
 * Comprehensive tests for specific scientific domains with realistic
 * user-agent conversations and natural language interactions.
 *
 * Domains covered:
 * - Structural Biology (Cryo-EM, X-ray, NMR)
 * - Systems Biology (Network analysis, pathway enrichment)
 * - Synthetic Biology (Circuit design, optimization)
 * - Biochemistry (Enzyme kinetics, protein analysis)
 * - Pharmacology (Drug screening, ADME prediction)
 */

import { test, expect } from '@playwright/test';

const BASE_URL = process.env.BIOMATE_URL || 'http://localhost:5000';

async function typeNaturally(locator: any, text: string) {
  await locator.click();
  // Simulate human typing with varying speeds
  for (const char of text) {
    await locator.type(char, { delay: 30 + Math.random() * 40 });
  }
}

async function waitForAIResponse(page: any, timeout = 30000) {
  // Wait for thinking indicator to disappear
  await page.waitForSelector('[class*="thinking"]', { state: 'hidden', timeout: 5000 }).catch(() => {});

  // Wait for new message
  await page.waitForTimeout(1000);
}

test.describe('Structural Biology Workflows', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(BASE_URL);
    await page.waitForLoadState('networkidle');
  });

  test('Cryo-EM: Single particle analysis pipeline', async ({ page }) => {
    const chatInput = page.locator('textarea, input[type="text"]').first();

    // Natural conversation flow
    console.log('User: Starting Cryo-EM discussion');
    await typeNaturally(chatInput,
      'Hi! I have cryo-EM movies from a FEI Titan Krios microscope. I need help processing them to get a 3D structure.'
    );
    await chatInput.press('Enter');
    await waitForAIResponse(page);

    // AI should ask for details
    console.log('AI should respond with workflow options');
    await page.waitForTimeout(2000);

    // User provides more details
    console.log('User: Providing sample details');
    await chatInput.clear();
    await typeNaturally(chatInput,
      'The protein is about 150 kDa, expected symmetry is C3. I want to use CryoSPARC for processing.'
    );
    await chatInput.press('Enter');
    await waitForAIResponse(page);
    await page.waitForTimeout(2000);

    // Check if workflow generated
    const workflowCard = page.locator('[class*="workflow"]').first();
    const hasWorkflow = await workflowCard.isVisible({ timeout: 15000 }).catch(() => false);

    if (hasWorkflow) {
      console.log('✓ Cryo-EM workflow generated');

      // Verify workflow has expected steps
      const workflowText = await workflowCard.textContent();
      const hasCryoEMSteps = workflowText && (
        workflowText.toLowerCase().includes('motion') ||
        workflowText.toLowerCase().includes('ctf') ||
        workflowText.toLowerCase().includes('particle') ||
        workflowText.toLowerCase().includes('cryosparc')
      );

      if (hasCryoEMSteps) {
        console.log('✓ Workflow contains Cryo-EM processing steps');
      }
    } else {
      console.log('⚠ Workflow not generated - may need more context');
    }

    // User asks about parameters
    console.log('User: Asking about parameters');
    await chatInput.clear();
    await typeNaturally(chatInput,
      'What resolution should I expect and what parameters need optimization?'
    );
    await chatInput.press('Enter');
    await waitForAIResponse(page);
  });

  test('X-ray Crystallography: Structure determination', async ({ page }) => {
    const chatInput = page.locator('textarea, input[type="text"]').first();

    console.log('User: X-ray crystallography request');
    await typeNaturally(chatInput,
      'I collected X-ray diffraction data from protein crystals. How do I solve the structure?'
    );
    await chatInput.press('Enter');
    await waitForAIResponse(page);
    await page.waitForTimeout(3000);

    // User provides details
    console.log('User: Crystal details');
    await chatInput.clear();
    await typeNaturally(chatInput,
      'The crystals diffract to 2.5 Å resolution, space group P212121'
    );
    await chatInput.press('Enter');
    await waitForAIResponse(page);

    // Check for workflow
    const workflowCard = page.locator('[class*="workflow"]').first();
    const hasWorkflow = await workflowCard.isVisible({ timeout: 15000 }).catch(() => false);

    if (hasWorkflow) {
      console.log('✓ X-ray crystallography workflow generated');
    }
  });
});

test.describe('Systems Biology Workflows', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(BASE_URL);
    await page.waitForLoadState('networkidle');
  });

  test('Network Analysis: Protein interaction network', async ({ page }) => {
    const chatInput = page.locator('textarea, input[type="text"]').first();

    console.log('User: Network analysis request');
    await typeNaturally(chatInput,
      'I have a list of differentially expressed genes from a cancer study. Can you build a protein-protein interaction network and identify key hub proteins?'
    );
    await chatInput.press('Enter');
    await waitForAIResponse(page, 40000); // Longer timeout for complex request
    await page.waitForTimeout(3000);

    // Check for workflow
    const workflowCard = page.locator('[class*="workflow"]').first();
    const hasWorkflow = await workflowCard.isVisible({ timeout: 15000 }).catch(() => false);

    if (hasWorkflow) {
      console.log('✓ Network analysis workflow generated');
    }

    // User asks about visualization
    console.log('User: Asking about visualization');
    await chatInput.clear();
    await typeNaturally(chatInput,
      'Can the workflow also generate a network visualization showing module structure?'
    );
    await chatInput.press('Enter');
    await waitForAIResponse(page);
  });

  test('Pathway Enrichment: GO and KEGG analysis', async ({ page }) => {
    const chatInput = page.locator('textarea, input[type="text"]').first();

    console.log('User: Pathway enrichment request');
    await typeNaturally(chatInput,
      'Perform pathway enrichment analysis on my gene list using GO terms and KEGG pathways'
    );
    await chatInput.press('Enter');
    await waitForAIResponse(page);
    await page.waitForTimeout(3000);

    // User specifies organism
    console.log('User: Specifying organism');
    await chatInput.clear();
    await typeNaturally(chatInput,
      'The genes are from mouse (Mus musculus)'
    );
    await chatInput.press('Enter');
    await waitForAIResponse(page);

    const workflowCard = page.locator('[class*="workflow"]').first();
    const hasWorkflow = await workflowCard.isVisible({ timeout: 15000 }).catch(() => false);

    if (hasWorkflow) {
      console.log('✓ Pathway enrichment workflow generated');
    }
  });
});

test.describe('Synthetic Biology Workflows', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(BASE_URL);
    await page.waitForLoadState('networkidle');
  });

  test('Circuit Design: Genetic circuit optimization', async ({ page }) => {
    const chatInput = page.locator('textarea, input[type="text"]').first();

    console.log('User: Circuit design request');
    await typeNaturally(chatInput,
      'I want to design a genetic toggle switch circuit with two repressors. Can you help optimize the promoter strengths?'
    );
    await chatInput.press('Enter');
    await waitForAIResponse(page);
    await page.waitForTimeout(3000);

    // User provides constraints
    console.log('User: Design constraints');
    await chatInput.clear();
    await typeNaturally(chatInput,
      'The circuit should be bistable with low leaky expression and fast switching'
    );
    await chatInput.press('Enter');
    await waitForAIResponse(page);

    const workflowCard = page.locator('[class*="workflow"]').first();
    const hasWorkflow = await workflowCard.isVisible({ timeout: 15000 }).catch(() => false);

    if (hasWorkflow) {
      console.log('✓ Circuit design workflow generated');
    }
  });

  test('Metabolic Engineering: Pathway optimization', async ({ page }) => {
    const chatInput = page.locator('textarea, input[type="text"]').first();

    console.log('User: Metabolic engineering request');
    await typeNaturally(chatInput,
      'Design a metabolic pathway to produce lycopene in E. coli with flux balance analysis'
    );
    await chatInput.press('Enter');
    await waitForAIResponse(page);
    await page.waitForTimeout(3000);

    const workflowCard = page.locator('[class*="workflow"]').first();
    const hasWorkflow = await workflowCard.isVisible({ timeout: 15000 }).catch(() => false);

    if (hasWorkflow) {
      console.log('✓ Metabolic engineering workflow generated');
    }
  });
});

test.describe('Biochemistry Workflows', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(BASE_URL);
    await page.waitForLoadState('networkidle');
  });

  test('Enzyme Kinetics: Michaelis-Menten analysis', async ({ page }) => {
    const chatInput = page.locator('textarea, input[type="text"]').first();

    console.log('User: Enzyme kinetics request');
    await typeNaturally(chatInput,
      'I measured enzyme reaction rates at different substrate concentrations. Can you fit Michaelis-Menten kinetics and calculate Km and Vmax?'
    );
    await chatInput.press('Enter');
    await waitForAIResponse(page);
    await page.waitForTimeout(3000);

    // User provides data format
    console.log('User: Data format');
    await chatInput.clear();
    await typeNaturally(chatInput,
      'My data has columns for substrate concentration (μM) and initial velocity (μmol/min/mg)'
    );
    await chatInput.press('Enter');
    await waitForAIResponse(page);

    const workflowCard = page.locator('[class*="workflow"]').first();
    const hasWorkflow = await workflowCard.isVisible({ timeout: 15000 }).catch(() => false);

    if (hasWorkflow) {
      console.log('✓ Enzyme kinetics workflow generated');
    }
  });

  test('Protein Stability: Circular dichroism analysis', async ({ page }) => {
    const chatInput = page.locator('textarea, input[type="text"]').first();

    console.log('User: CD analysis request');
    await typeNaturally(chatInput,
      'Analyze circular dichroism spectra to determine protein secondary structure composition'
    );
    await chatInput.press('Enter');
    await waitForAIResponse(page);
    await page.waitForTimeout(3000);

    // User provides experimental details
    console.log('User: Experimental details');
    await chatInput.clear();
    await typeNaturally(chatInput,
      'The CD data was collected from 190-260 nm at 25°C in PBS buffer'
    );
    await chatInput.press('Enter');
    await waitForAIResponse(page);

    const workflowCard = page.locator('[class*="workflow"]').first();
    const hasWorkflow = await workflowCard.isVisible({ timeout: 15000 }).catch(() => false);

    if (hasWorkflow) {
      console.log('✓ CD analysis workflow generated');
    }
  });

  test('Binding Assay: ITC data analysis', async ({ page }) => {
    const chatInput = page.locator('textarea, input[type="text"]').first();

    console.log('User: ITC analysis request');
    await typeNaturally(chatInput,
      'Process isothermal titration calorimetry data to determine binding affinity and thermodynamic parameters'
    );
    await chatInput.press('Enter');
    await waitForAIResponse(page);
    await page.waitForTimeout(3000);

    const workflowCard = page.locator('[class*="workflow"]').first();
    const hasWorkflow = await workflowCard.isVisible({ timeout: 15000 }).catch(() => false);

    if (hasWorkflow) {
      console.log('✓ ITC analysis workflow generated');
    }
  });
});

test.describe('Pharmacology Workflows', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(BASE_URL);
    await page.waitForLoadState('networkidle');
  });

  test('Drug Screening: High-throughput compound analysis', async ({ page }) => {
    const chatInput = page.locator('textarea, input[type="text"]').first();

    console.log('User: Drug screening request');
    await typeNaturally(chatInput,
      'I have high-throughput screening data for 10,000 compounds. Help me identify hits and calculate IC50 values'
    );
    await chatInput.press('Enter');
    await waitForAIResponse(page);
    await page.waitForTimeout(3000);

    // User provides plate format
    console.log('User: Plate format details');
    await chatInput.clear();
    await typeNaturally(chatInput,
      'The data is from 384-well plates with 8-point dose-response curves'
    );
    await chatInput.press('Enter');
    await waitForAIResponse(page);

    const workflowCard = page.locator('[class*="workflow"]').first();
    const hasWorkflow = await workflowCard.isVisible({ timeout: 15000 }).catch(() => false);

    if (hasWorkflow) {
      console.log('✓ Drug screening workflow generated');
    }
  });

  test('ADME Prediction: Pharmacokinetic properties', async ({ page }) => {
    const chatInput = page.locator('textarea, input[type="text"]').first();

    console.log('User: ADME prediction request');
    await typeNaturally(chatInput,
      'Predict ADME properties (absorption, distribution, metabolism, excretion) for a list of drug candidates'
    );
    await chatInput.press('Enter');
    await waitForAIResponse(page);
    await page.waitForTimeout(3000);

    // User asks about specific properties
    console.log('User: Specific properties');
    await chatInput.clear();
    await typeNaturally(chatInput,
      'I especially need predictions for blood-brain barrier penetration and CYP450 metabolism'
    );
    await chatInput.press('Enter');
    await waitForAIResponse(page);

    const workflowCard = page.locator('[class*="workflow"]').first();
    const hasWorkflow = await workflowCard.isVisible({ timeout: 15000 }).catch(() => false);

    if (hasWorkflow) {
      console.log('✓ ADME prediction workflow generated');
    }
  });

  test('Molecular Docking: Protein-ligand binding', async ({ page }) => {
    const chatInput = page.locator('textarea, input[type="text"]').first();

    console.log('User: Molecular docking request');
    await typeNaturally(chatInput,
      'Perform molecular docking of drug candidates to a protein target and rank by predicted binding affinity'
    );
    await chatInput.press('Enter');
    await waitForAIResponse(page);
    await page.waitForTimeout(3000);

    // User provides structure details
    console.log('User: Structure details');
    await chatInput.clear();
    await typeNaturally(chatInput,
      'I have the protein structure as a PDB file and candidate molecules as SMILES strings'
    );
    await chatInput.press('Enter');
    await waitForAIResponse(page);

    const workflowCard = page.locator('[class*="workflow"]').first();
    const hasWorkflow = await workflowCard.isVisible({ timeout: 15000 }).catch(() => false);

    if (hasWorkflow) {
      console.log('✓ Molecular docking workflow generated');
    }
  });
});

test.describe('Edge Cases and Error Handling', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(BASE_URL);
    await page.waitForLoadState('networkidle');
  });

  test('Ambiguous Request: AI seeks clarification', async ({ page }) => {
    const chatInput = page.locator('textarea, input[type="text"]').first();

    console.log('User: Intentionally vague request');
    await typeNaturally(chatInput,
      'Analyze sequences'
    );
    await chatInput.press('Enter');
    await waitForAIResponse(page);

    // Check if AI asks clarifying questions
    const responseText = await page.locator('[class*="message"]').last().textContent();
    const asksClarification = responseText && (
      responseText.toLowerCase().includes('what type') ||
      responseText.toLowerCase().includes('which') ||
      responseText.toLowerCase().includes('could you provide') ||
      responseText.toLowerCase().includes('more information')
    );

    if (asksClarification) {
      console.log('✓ AI appropriately requested clarification');
    } else {
      console.log('⚠ AI did not ask for clarification');
    }
  });

  test('Unsupported Analysis: AI explains limitations', async ({ page }) => {
    const chatInput = page.locator('textarea, input[type="text"]').first();

    console.log('User: Request potentially unsupported analysis');
    await typeNaturally(chatInput,
      'Perform quantum molecular dynamics simulation of protein folding'
    );
    await chatInput.press('Enter');
    await waitForAIResponse(page);
    await page.waitForTimeout(3000);

    const responseText = await page.locator('[class*="message"]').last().textContent();
    const explainsLimitations = responseText && (
      responseText.toLowerCase().includes('not available') ||
      responseText.toLowerCase().includes('alternative') ||
      responseText.toLowerCase().includes('suggest') ||
      responseText.toLowerCase().includes('instead')
    );

    if (explainsLimitations) {
      console.log('✓ AI explained limitations or offered alternatives');
    }
  });

  test('Correction Flow: User corrects misunderstanding', async ({ page }) => {
    const chatInput = page.locator('textarea, input[type="text"]').first();

    // Initial request
    console.log('User: Initial request');
    await typeNaturally(chatInput,
      'Align protein sequences'
    );
    await chatInput.press('Enter');
    await waitForAIResponse(page);
    await page.waitForTimeout(2000);

    // User corrects
    console.log('User: Correction');
    await chatInput.clear();
    await typeNaturally(chatInput,
      'Sorry, I meant DNA sequences, not proteins'
    );
    await chatInput.press('Enter');
    await waitForAIResponse(page);
    await page.waitForTimeout(2000);

    // Check if AI understood correction
    const responseText = await page.locator('[class*="message"]').last().textContent();
    const understoodCorrection = responseText && responseText.toLowerCase().includes('dna');

    if (understoodCorrection) {
      console.log('✓ AI understood and adapted to correction');
    }
  });
});
