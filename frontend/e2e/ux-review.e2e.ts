import { setupTestUser } from "./helpers.js";
import { test, expect, Page } from '@playwright/test';
import * as fs from 'fs';
const BASE_URL = process.env.BIOMATE_URL || 'http://localhost:5000';


interface Observation {
  timestamp: string;
  observation: string;
  severity: 'info' | 'low' | 'medium' | 'high' | 'critical';
}

interface Observations {
  first_impression: Observation[];
  navigation: Observation[];
  chat_interaction: Observation[];
  workflow_execution: Observation[];
  results_interaction: Observation[];
  issues: Observation[];
  positive_findings: Observation[];
}

class UXReviewer {
  observations: Observations = {
    first_impression: [],
    navigation: [],
    chat_interaction: [],
    workflow_execution: [],
    results_interaction: [],
    issues: [],
    positive_findings: []
  };

  log(category: keyof Observations, observation: string, severity: Observation['severity'] = 'info') {
    const entry: Observation = {
      timestamp: new Date().toISOString(),
      observation,
      severity
    };
    this.observations[category].push(entry);
    console.log(`[${category.toUpperCase()}] ${severity.toUpperCase()}: ${observation}`);
  }

  async reviewFirstImpression(page: Page) {
    console.log('\n=== STEP 1: First Impression & Onboarding ===');
    
    await page.goto(BASE_URL, { waitUntil: 'networkidle' });
    await page.waitForTimeout(2000);
    await page.screenshot({ path: '/tmp/biomate_ux_01_landing.png', fullPage: true });
    
    const title = await page.title();
    this.log('first_impression', `Page title: ${title}`);
    
    // Check for header/branding
    const header = page.locator('header, [role="banner"], h1').first();
    const headerCount = await header.count();
    if (headerCount > 0) {
      const headerText = await header.textContent();
      this.log('first_impression', `Header found: ${headerText}`, 'info');
    } else {
      this.log('first_impression', 'No clear header/branding visible', 'medium');
    }
    
    // Check for onboarding/welcome message
    const welcomeElements = await page.locator('text=/welcome|getting started|introduction/i').count();
    if (welcomeElements > 0) {
      this.log('first_impression', `Found ${welcomeElements} onboarding elements`, 'info');
    } else {
      this.log('first_impression', 'No obvious onboarding/welcome message', 'low');
    }
    
    // Check for chat interface
    const chatInput = page.locator('textarea, input[type="text"], [contenteditable="true"]').first();
    const chatInputCount = await chatInput.count();
    if (chatInputCount > 0) {
      const placeholder = await chatInput.getAttribute('placeholder') || '';
      this.log('first_impression', `Chat input found with placeholder: '${placeholder}'`, 'info');
      if (!placeholder) {
        this.log('first_impression', 'Chat input has no placeholder text - unclear what to type', 'medium');
      }
    } else {
      this.log('first_impression', 'No chat input immediately visible', 'high');
    }
    
    // Check for navigation elements
    const navItems = await page.locator('nav, [role="navigation"], a[href]').count();
    this.log('first_impression', `Found ${navItems} navigation elements`, 'info');
    
    // Check for trust cues
    const links = await page.locator('a').all();
    const linkTexts: string[] = [];
    for (const link of links.slice(0, 10)) {
      const text = await link.textContent();
      if (text?.trim()) {
        linkTexts.push(text.trim());
      }
    }
    this.log('first_impression', `Visible links: ${linkTexts.slice(0, 5).join(', ')}`, 'info');
  }

  async testChatWorkflowRequest(page: Page): Promise<boolean> {
    console.log('\n=== STEP 2: Chat Workflow Request ===');
    
    const chatInput = page.locator('textarea, input[type="text"], [contenteditable="true"]').first();
    
    if (await chatInput.count() === 0) {
      this.log('chat_interaction', 'Cannot find chat input field', 'critical');
      return false;
    }
    
    const workflowRequest = 'Build me a quality control workflow for RNA-seq FASTQ files';
    await chatInput.click();
    await page.waitForTimeout(500);
    await chatInput.fill(workflowRequest);
    this.log('chat_interaction', `Typed request: '${workflowRequest}'`, 'info');
    await page.screenshot({ path: '/tmp/biomate_ux_02_typed_request.png', fullPage: true });
    
    // Find and click send button
    const sendButton = page.locator('button:has-text("Send"), button[type="submit"], button:has(svg)').first();
    if (await sendButton.count() > 0) {
      await sendButton.click();
      this.log('chat_interaction', 'Send button clicked', 'info');
    } else {
      await chatInput.press('Enter');
      this.log('chat_interaction', 'Pressed Enter to send (no visible send button)', 'low');
    }
    
    await page.waitForTimeout(1000);
    await page.screenshot({ path: '/tmp/biomate_ux_03_request_sent.png', fullPage: true });
    
    // Wait for response
    this.log('chat_interaction', 'Waiting for AI response...', 'info');
    try {
      const initialLength = (await page.locator('body').textContent())?.length || 0;
      await page.waitForFunction(
        (len) => document.body.innerText.length > len,
        initialLength,
        { timeout: 30000 }
      );
      await page.waitForTimeout(2000);
      this.log('chat_interaction', 'Response received', 'info');
    } catch (e) {
      this.log('chat_interaction', `Timeout waiting for response: ${e}`, 'high');
      return false;
    }
    
    await page.screenshot({ path: '/tmp/biomate_ux_04_response_received.png', fullPage: true });
    return true;
  }

  async examineResponseArtifact(page: Page) {
    console.log('\n=== STEP 3: Examine Response Artifact ===');
    
    const bodyText = await page.locator('body').textContent() || '';
    
    // Check for workflow artifact/card
    const workflowCards = await page.locator('[class*="workflow"], [class*="artifact"], [data-testid*="workflow"]').count();
    this.log('workflow_execution', `Found ${workflowCards} workflow-related elements`, 'info');
    
    // Look for action buttons
    const actionButtons = await page.locator('button:has-text("Run"), button:has-text("Execute"), button:has-text("Start")').all();
    if (actionButtons.length > 0) {
      this.log('workflow_execution', `Found ${actionButtons.length} action buttons`, 'info');
      for (const btn of actionButtons.slice(0, 3)) {
        const btnText = await btn.textContent();
        const isVisible = await btn.isVisible();
        const isEnabled = await btn.isEnabled();
        this.log('workflow_execution', `Button '${btnText}' - visible: ${isVisible}, enabled: ${isEnabled}`, 'info');
      }
    } else {
      this.log('workflow_execution', 'No obvious Run/Execute buttons found', 'high');
    }
    
    // Check for workflow description
    if (bodyText.toLowerCase().includes('quality control') && bodyText.toLowerCase().includes('rna-seq')) {
      this.log('workflow_execution', 'Response mentions QC and RNA-seq (relevant)', 'info');
    } else {
      this.log('workflow_execution', 'Response may not be relevant to request', 'medium');
    }
    
    // Check for parameter inputs
    const inputs = await page.locator('input, select, textarea').count();
    this.log('workflow_execution', `Found ${inputs} input fields (parameters?)`, 'info');
    
    await page.screenshot({ path: '/tmp/biomate_ux_05_artifact_examined.png', fullPage: true });
  }

  async executeWorkflow(page: Page): Promise<boolean> {
    console.log('\n=== STEP 4: Execute Workflow ===');
    
    const runButton = page.locator('button:has-text("Run"), button:has-text("Execute"), button:has-text("Start")').first();
    
    if (await runButton.count() === 0) {
      this.log('workflow_execution', 'Cannot find Run button to execute workflow', 'critical');
      return false;
    }
    
    if (!await runButton.isEnabled()) {
      this.log('workflow_execution', 'Run button is disabled - unclear why', 'high');
      const errorMsgs = await page.locator('[class*="error"], [role="alert"]').all();
      for (const msg of errorMsgs) {
        const text = await msg.textContent();
        this.log('workflow_execution', `Error/alert visible: ${text}`, 'medium');
      }
      return false;
    }
    
    await runButton.click();
    this.log('workflow_execution', 'Clicked Run button', 'info');
    await page.waitForTimeout(1000);
    await page.screenshot({ path: '/tmp/biomate_ux_06_workflow_started.png', fullPage: true });
    
    return true;
  }

  async observeProgress(page: Page) {
    console.log('\n=== STEP 5: Observe Progress ===');
    
    const progressElements = await page.locator('[class*="progress"], [role="progressbar"], [class*="status"]').count();
    this.log('workflow_execution', `Found ${progressElements} progress-related elements`, 'info');
    
    // Monitor for status changes over 20 seconds
    for (let i = 0; i < 10; i++) {
      await page.waitForTimeout(2000);
      
      const statusTexts = await page.locator('[class*="status"], [class*="state"]').all();
      for (const status of statusTexts.slice(0, 5)) {
        if (await status.isVisible()) {
          const text = await status.textContent();
          if (text?.trim()) {
            this.log('workflow_execution', `Status at ${i*2}s: ${text.trim()}`, 'info');
          }
        }
      }
      
      // Check for completion
      if (await page.locator('text=/completed|finished|success|done/i').count() > 0) {
        this.log('workflow_execution', 'Workflow appears completed', 'info');
        await page.screenshot({ path: '/tmp/biomate_ux_07_workflow_completed.png', fullPage: true });
        break;
      }
      
      // Check for errors
      if (await page.locator('text=/failed|error/i').count() > 0) {
        this.log('workflow_execution', 'Workflow appears to have failed', 'high');
        await page.screenshot({ path: '/tmp/biomate_ux_07_workflow_failed.png', fullPage: true });
        break;
      }
    }
    
    this.log('workflow_execution', 'Workflow monitoring complete', 'info');
    await page.screenshot({ path: '/tmp/biomate_ux_07_workflow_final.png', fullPage: true });
  }

  async interactWithResults(page: Page) {
    console.log('\n=== STEP 6-7: Results Interaction ===');
    
    const resultSections = await page.locator('[class*="result"], [class*="output"], [data-testid*="result"]').count();
    this.log('results_interaction', `Found ${resultSections} result-related sections`, 'info');
    
    const vizElements = await page.locator('canvas, svg, img[src*="plot"], [class*="chart"]').count();
    this.log('results_interaction', `Found ${vizElements} visualization elements`, 'info');
    
    const downloadButtons = await page.locator('button:has-text("Download"), a[download], button:has-text("Export")').all();
    if (downloadButtons.length > 0) {
      this.log('results_interaction', `Found ${downloadButtons.length} download controls`, 'info');
      for (const btn of downloadButtons.slice(0, 3)) {
        const text = await btn.textContent();
        const isVisible = await btn.isVisible();
        this.log('results_interaction', `Download option: '${text}' (visible: ${isVisible})`, 'info');
      }
    } else {
      this.log('results_interaction', 'No download controls found', 'medium');
    }
    
    const toggleButtons = await page.locator('button:has-text("View"), button:has-text("Hide"), button:has-text("Show")').all();
    if (toggleButtons.length > 0) {
      this.log('results_interaction', `Found ${toggleButtons.length} view toggle controls`, 'info');
    }
    
    const cards = await page.locator('[class*="card"], [class*="output-item"]').count();
    this.log('results_interaction', `Found ${cards} card-like elements`, 'info');
    
    // Try clicking a download button
    if (downloadButtons.length > 0) {
      try {
        const firstDownload = downloadButtons[0];
        if (await firstDownload.isVisible() && await firstDownload.isEnabled()) {
          await firstDownload.click();
          this.log('results_interaction', 'Clicked first download button', 'info');
          await page.waitForTimeout(1000);
        }
      } catch (e) {
        this.log('results_interaction', `Error clicking download: ${e}`, 'low');
      }
    }
    
    await page.screenshot({ path: '/tmp/biomate_ux_08_results_final.png', fullPage: true });
  }

  async checkForIssues(page: Page) {
    console.log('\n=== STEP 8: Issue Detection ===');
    
    // Check for visible error messages
    const errorElements = await page.locator('[class*="error"], [role="alert"], [class*="warning"]').all();
    for (const elem of errorElements) {
      if (await elem.isVisible()) {
        const text = await elem.textContent();
        this.log('issues', `Visible error/warning: ${text}`, 'medium');
      }
    }
    
    // Check for broken images
    const images = await page.locator('img').all();
    for (const img of images) {
      const src = await img.getAttribute('src');
      const naturalWidth = await img.evaluate((el: HTMLImageElement) => el.naturalWidth);
      if (naturalWidth === 0 && src) {
        this.log('issues', `Broken image: ${src}`, 'low');
      }
    }
    
    // Check for 404 or not found states
    const bodyText = await page.locator('body').textContent() || '';
    if (bodyText.includes('404') || bodyText.toLowerCase().includes('not found')) {
      this.log('issues', 'Possible 404 or "not found" state', 'high');
    }
    
    // Check for persistent loading states
    const loadingElements = await page.locator('[class*="loading"], [class*="spinner"]').all();
    for (const elem of loadingElements) {
      if (await elem.isVisible()) {
        this.log('issues', 'Persistent loading indicator visible', 'medium');
      }
    }
    
    // Check for disabled buttons without explanation
    const disabledButtons = await page.locator('button:disabled').all();
    for (const btn of disabledButtons.slice(0, 5)) {
      const text = await btn.textContent();
      const parent = await btn.locator('..').first();
      const parentText = await parent.textContent() || '';
      if (!parentText.toLowerCase().includes('disabled') && !parentText.toLowerCase().includes('cannot')) {
        this.log('issues', `Disabled button '${text}' without clear explanation`, 'medium');
      }
    }
  }

  generateReport() {
    console.log('\n' + '='.repeat(80));
    console.log('BIOMATE UX REVIEW REPORT');
    console.log('='.repeat(80));
    
    const criticalIssues: [string, string][] = [];
    const highIssues: [string, string][] = [];
    const mediumIssues: [string, string][] = [];
    const lowIssues: [string, string][] = [];
    const positiveFindings: [string, string][] = [];
    
    for (const [category, entries] of Object.entries(this.observations)) {
      for (const entry of entries) {
        const { severity, observation } = entry;
        
        if (severity === 'critical') {
          criticalIssues.push([category, observation]);
        } else if (severity === 'high') {
          highIssues.push([category, observation]);
        } else if (severity === 'medium') {
          mediumIssues.push([category, observation]);
        } else if (severity === 'low') {
          lowIssues.push([category, observation]);
        } else if (observation.toLowerCase().includes('found') && 
                   ['button', 'element', 'input'].some(x => observation.toLowerCase().includes(x))) {
          positiveFindings.push([category, observation]);
        }
      }
    }
    
    console.log('\n## WHAT WORKS WELL');
    console.log('-'.repeat(80));
    if (positiveFindings.length > 0) {
      for (const [category, finding] of positiveFindings.slice(0, 10)) {
        console.log(`  • [${category}] ${finding}`);
      }
    } else {
      console.log('  (Limited positive findings observed)');
    }
    
    console.log('\n## WHAT IS UNCLEAR/CONFUSING');
    console.log('-'.repeat(80));
    for (const [category, issue] of [...mediumIssues, ...lowIssues]) {
      console.log(`  • [${category}] ${issue}`);
    }
    
    console.log('\n## WHAT APPEARS BROKEN OR RISKY');
    console.log('-'.repeat(80));
    for (const [category, issue] of [...criticalIssues, ...highIssues]) {
      console.log(`  • [${category}] ${issue}`);
    }
    
    console.log('\n## UX SEVERITY RANKING');
    console.log('-'.repeat(80));
    console.log(`  CRITICAL: ${criticalIssues.length} issues`);
    console.log(`  HIGH:     ${highIssues.length} issues`);
    console.log(`  MEDIUM:   ${mediumIssues.length} issues`);
    console.log(`  LOW:      ${lowIssues.length} issues`);
    
    console.log('\n## TOP 10 PRIORITIZED UX FIXES');
    console.log('-'.repeat(80));
    
    const allIssues: [[string, string], string][] = [
      ...criticalIssues.map((i): [[string, string], string] => [i, 'CRITICAL']),
      ...highIssues.map((i): [[string, string], string] => [i, 'HIGH']),
      ...mediumIssues.map((i): [[string, string], string] => [i, 'MEDIUM'])
    ];
    
    for (let idx = 0; idx < Math.min(10, allIssues.length); idx++) {
      const [[category, issue], severity] = allIssues[idx];
      console.log(`\n${idx + 1}. [${severity}] ${issue}`);
      console.log(`   Category: ${category}`);
      
      // Add rationale
      const lowerIssue = issue.toLowerCase();
      if (lowerIssue.includes('cannot find') || lowerIssue.includes('no obvious')) {
        console.log('   Rationale: Missing critical UI element blocks user progress');
      } else if (lowerIssue.includes('disabled')) {
        console.log('   Rationale: Unclear affordances frustrate users');
      } else if (lowerIssue.includes('unclear') || lowerIssue.includes('no placeholder')) {
        console.log('   Rationale: Lack of guidance increases cognitive load');
      } else if (lowerIssue.includes('timeout') || lowerIssue.includes('failed')) {
        console.log('   Rationale: Functional failures prevent task completion');
      } else {
        console.log('   Rationale: Impacts user experience and task flow');
      }
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('Review complete. Screenshots saved to /tmp/biomate_ux_*.png');
    console.log('='.repeat(80));
    
    // Save report to file
    fs.writeFileSync('/tmp/biomate_ux_report.json', JSON.stringify(this.observations, null, 2));
    console.log('Detailed observations saved to /tmp/biomate_ux_report.json');
  }
}

test('BioMate UX Review - Complete Walkthrough', async ({ page }) => {
    await setupTestUser(page, "ux_rev");
  const reviewer = new UXReviewer();
  
  try {
    await reviewer.reviewFirstImpression(page);
    
    const chatSuccess = await reviewer.testChatWorkflowRequest(page);
    if (chatSuccess) {
      await reviewer.examineResponseArtifact(page);
      
      const executionSuccess = await reviewer.executeWorkflow(page);
      if (executionSuccess) {
        await reviewer.observeProgress(page);
        await reviewer.interactWithResults(page);
      }
    }
    
    await reviewer.checkForIssues(page);
    
  } catch (e) {
    reviewer.log('issues', `Critical error during review: ${e}`, 'critical');
  } finally {
    reviewer.generateReport();
  }
});
