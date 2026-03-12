import { test, expect, Page } from '@playwright/test';

const BASE_URL = process.env.BIOMATE_URL || 'http://localhost:5000';

interface UXFinding {
  severity: 'high' | 'medium' | 'low';
  issue: string;
  userImpact: string;
  repro: string;
}

interface UXReport {
  worksWell: string[];
  unclearConfusing: UXFinding[];
  brokenRisky: UXFinding[];
  topFixes: UXFinding[];
}

test('BioMate UX Evaluation - Port 5310', async ({ page }) => {
  const report: UXReport = {
    worksWell: [],
    unclearConfusing: [],
    brokenRisky: [],
    topFixes: []
  };

  console.log('\n' + '='.repeat(80));
  console.log('BIOMATE UX EVALUATION - REALISTIC USER INTERACTION');
  console.log(`Target: ${BASE_URL}`);
  console.log('='.repeat(80));

  // Step 1: First Impression Assessment
  console.log('\n[STEP 1] Opening app and assessing first impression...');
  
  try {
    await page.goto(BASE_URL, { waitUntil: 'networkidle', timeout: 10000 });
    await page.screenshot({ path: '/tmp/ux_eval_01_landing.png', fullPage: true });
    
    // Check page title
    const title = await page.title();
    console.log(`✓ Page title: "${title}"`);
    if (title.toLowerCase().includes('biomate') || title.toLowerCase().includes('bioinformatics')) {
      report.worksWell.push('Clear page title explains the application purpose');
    }
    
    // Check for header/branding
    const header = page.locator('header, [role="banner"], h1, h2').first();
    if (await header.count() > 0) {
      const headerText = await header.textContent();
      console.log(`✓ Header/branding: "${headerText?.trim()}"`);
      report.worksWell.push('Prominent branding visible on landing');
    }
    
    // Check for chat input - primary interaction point
    const chatInput = page.locator('textarea, input[type="text"], [contenteditable="true"]').first();
    if (await chatInput.count() > 0) {
      const placeholder = await chatInput.getAttribute('placeholder') || '';
      console.log(`✓ Chat input found with placeholder: "${placeholder}"`);
      
      if (placeholder && placeholder.length > 5) {
        report.worksWell.push(`Chat input has helpful placeholder: "${placeholder}"`);
      } else {
        report.unclearConfusing.push({
          severity: 'medium',
          issue: 'Chat input lacks clear placeholder guidance',
          userImpact: 'Users may not know what to type or how to phrase requests',
          repro: 'Open app and look at chat input field'
        });
      }
    } else {
      report.brokenRisky.push({
        severity: 'high',
        issue: 'No visible chat input on landing page',
        userImpact: 'Users cannot start interacting with the application',
        repro: 'Open app - no textarea or input field visible'
      });
    }
    
    // Check for welcome message or instructions
    const bodyText = await page.locator('body').textContent() || '';
    if (bodyText.toLowerCase().includes('welcome') || bodyText.toLowerCase().includes('hello')) {
      console.log('✓ Welcome message present');
      report.worksWell.push('Welcome message helps orient new users');
    } else {
      report.unclearConfusing.push({
        severity: 'low',
        issue: 'No welcome message or onboarding',
        userImpact: 'New users lack guidance on capabilities and how to start',
        repro: 'Open app - no welcome or getting started message'
      });
    }
    
    // Check for quick action buttons
    const quickButtons = await page.locator('button').count();
    console.log(`✓ Found ${quickButtons} buttons on landing page`);
    
    // Check for navigation
    const navElements = await page.locator('nav, [role="navigation"]').count();
    if (navElements === 0) {
      report.unclearConfusing.push({
        severity: 'medium',
        issue: 'No visible navigation menu',
        userImpact: 'Users cannot explore other features or sections beyond chat',
        repro: 'Open app - no nav menu or links to other sections'
      });
    }
    
  } catch (error) {
    console.error('✗ Failed to load application:', error);
    report.brokenRisky.push({
      severity: 'high',
      issue: 'Application failed to load or timed out',
      userImpact: 'Users cannot access the application at all',
      repro: `Navigate to ${BASE_URL} - error: ${error}`
    });
    
    // Generate report and exit
    generateReport(report);
    return;
  }

  // Step 2: Submit workflow request
  console.log('\n[STEP 2] Submitting workflow request...');
  
  const workflowRequest = 'Build me a quality control workflow for RNA-seq FASTQ files';
  const chatInput = page.locator('textarea, input[type="text"], [contenteditable="true"]').first();
  
  if (await chatInput.count() > 0) {
    await chatInput.click();
    await page.waitForTimeout(300);
    await chatInput.fill(workflowRequest);
    console.log(`✓ Typed: "${workflowRequest}"`);
    
    await page.screenshot({ path: '/tmp/ux_eval_02_typed.png', fullPage: true });
    
    // Find send button
    const sendButton = page.locator('button:has-text("Send"), button[type="submit"]').first();
    if (await sendButton.count() > 0) {
      const isEnabled = await sendButton.isEnabled();
      console.log(`✓ Send button found, enabled: ${isEnabled}`);
      
      if (isEnabled) {
        await sendButton.click();
        console.log('✓ Clicked send button');
        await page.waitForTimeout(1000);
        await page.screenshot({ path: '/tmp/ux_eval_03_sent.png', fullPage: true });
      } else {
        report.brokenRisky.push({
          severity: 'high',
          issue: 'Send button is disabled after typing message',
          userImpact: 'Users cannot submit their workflow requests',
          repro: 'Type message in chat input - send button remains disabled'
        });
      }
    } else {
      // Try pressing Enter
      await chatInput.press('Enter');
      console.log('✓ Pressed Enter (no send button found)');
      await page.waitForTimeout(1000);
    }
    
    // Check for loading indicator
    await page.waitForTimeout(500);
    const loadingIndicators = await page.locator('[class*="loading"], [class*="spinner"], [class*="typing"]').count();
    if (loadingIndicators > 0) {
      console.log('✓ Loading indicator visible');
      report.worksWell.push('Loading indicator shows system is processing request');
    } else {
      report.unclearConfusing.push({
        severity: 'high',
        issue: 'No loading indicator after submitting request',
        userImpact: 'Users do not know if their request was received or if system is working',
        repro: 'Submit chat message - no loading/thinking indicator appears'
      });
    }
    
  } else {
    console.error('✗ Cannot proceed - no chat input available');
  }

  // Step 3: Wait for and inspect response
  console.log('\n[STEP 3] Waiting for assistant response...');
  
  try {
    // Wait for new content to appear (max 25 seconds)
    const initialLength = (await page.locator('body').textContent())?.length || 0;
    await page.waitForFunction(
      (len) => document.body.innerText.length > len + 100,
      initialLength,
      { timeout: 25000 }
    );
    
    await page.waitForTimeout(2000); // Let animations finish
    console.log('✓ Response received');
    await page.screenshot({ path: '/tmp/ux_eval_04_response.png', fullPage: true });
    
    // Check if response mentions workflow or QC
    const responseText = await page.locator('body').textContent() || '';
    if (responseText.toLowerCase().includes('workflow') || responseText.toLowerCase().includes('quality control')) {
      console.log('✓ Response is relevant to request');
      report.worksWell.push('AI response is contextually relevant to user request');
    }
    
    // Look for workflow card/artifact
    const workflowCards = await page.locator('[class*="workflow"], [data-testid*="workflow"], [class*="artifact"]').count();
    console.log(`✓ Found ${workflowCards} workflow-related elements`);
    
    if (workflowCards > 0) {
      report.worksWell.push('Workflow is displayed as a distinct visual artifact');
      
      // Check for workflow labels and status
      const statusElements = await page.locator('[class*="status"], [class*="state"]').count();
      if (statusElements > 0) {
        console.log(`✓ Found ${statusElements} status indicators`);
      } else {
        report.unclearConfusing.push({
          severity: 'medium',
          issue: 'Workflow status not clearly indicated',
          userImpact: 'Users cannot tell if workflow is ready to run or what state it is in',
          repro: 'Generate workflow - no visible status label (pending/ready/running)'
        });
      }
    } else {
      report.unclearConfusing.push({
        severity: 'high',
        issue: 'Workflow not displayed as distinct visual element',
        userImpact: 'Users cannot easily identify or interact with generated workflow',
        repro: 'Request workflow - response is text only, no workflow card/viewer'
      });
    }
    
    // Check for action buttons
    const actionButtons = await page.locator('button:has-text("Run"), button:has-text("Execute"), button:has-text("Start")').all();
    console.log(`✓ Found ${actionButtons.length} execution action buttons`);
    
    if (actionButtons.length > 0) {
      report.worksWell.push('Clear action button available to run workflow');
    } else {
      report.brokenRisky.push({
        severity: 'high',
        issue: 'No Run/Execute button visible after workflow generation',
        userImpact: 'Users cannot execute the generated workflow',
        repro: 'Generate workflow - no Run or Execute button appears'
      });
    }
    
  } catch (error) {
    console.error('✗ Timeout waiting for response:', error);
    report.brokenRisky.push({
      severity: 'high',
      issue: 'AI response timeout or extremely slow',
      userImpact: 'Users wait indefinitely without feedback, likely to abandon',
      repro: 'Submit workflow request - no response after 25 seconds'
    });
    await page.screenshot({ path: '/tmp/ux_eval_04_timeout.png', fullPage: true });
  }

  // Step 4: Execute workflow
  console.log('\n[STEP 4] Attempting to run workflow...');
  
  const runButton = page.locator('button:has-text("Run"), button:has-text("Execute"), button:has-text("Start")').first();
  
  if (await runButton.count() > 0) {
    const isEnabled = await runButton.isEnabled();
    const isVisible = await runButton.isVisible();
    console.log(`✓ Run button - visible: ${isVisible}, enabled: ${isEnabled}`);
    
    if (!isEnabled) {
      report.unclearConfusing.push({
        severity: 'high',
        issue: 'Run button is disabled without explanation',
        userImpact: 'Users cannot execute workflow and do not know why or what is missing',
        repro: 'Generate workflow - Run button is disabled with no tooltip or message'
      });
      
      // Check for prerequisite messages
      const prereqMessages = await page.locator('text=/prerequisite|required|missing|upload/i').count();
      if (prereqMessages === 0) {
        report.topFixes.push({
          severity: 'high',
          issue: 'Add prerequisite checklist before Run button',
          userImpact: 'Users need clear indication of what is required before execution',
          repro: 'Show checklist: input files, parameters, etc. with status indicators'
        });
      }
    } else if (isVisible && isEnabled) {
      await runButton.click();
      console.log('✓ Clicked Run button');
      await page.waitForTimeout(1500);
      await page.screenshot({ path: '/tmp/ux_eval_05_running.png', fullPage: true });
      
      // Check for progress indicators
      const progressElements = await page.locator('[class*="progress"], [role="progressbar"]').count();
      if (progressElements > 0) {
        console.log(`✓ Found ${progressElements} progress indicators`);
        report.worksWell.push('Progress indicators show workflow execution status');
      } else {
        report.unclearConfusing.push({
          severity: 'medium',
          issue: 'No progress bar or percentage during execution',
          userImpact: 'Users cannot gauge how long execution will take',
          repro: 'Run workflow - no progress bar or percentage shown'
        });
      }
      
      // Check for status transitions
      await page.waitForTimeout(3000);
      const statusText = await page.locator('[class*="status"], [class*="state"]').first().textContent() || '';
      console.log(`✓ Current status: "${statusText.trim()}"`);
      
      // Check for logs or execution details
      const logElements = await page.locator('[class*="log"], [class*="output"], [class*="console"]').count();
      if (logElements > 0) {
        console.log(`✓ Found ${logElements} log/output elements`);
      } else {
        report.unclearConfusing.push({
          severity: 'low',
          issue: 'No execution logs or detailed progress visible',
          userImpact: 'Power users cannot debug or understand what is happening',
          repro: 'Run workflow - no expandable logs or step-by-step progress'
        });
      }
    }
  } else {
    console.log('✗ No Run button found - skipping execution test');
  }

  // Step 5: Interact with results
  console.log('\n[STEP 5] Checking for results and download options...');
  
  await page.waitForTimeout(2000);
  
  // Look for results section
  const resultElements = await page.locator('[class*="result"], [class*="output"], [data-testid*="result"]').count();
  console.log(`✓ Found ${resultElements} result-related elements`);
  
  if (resultElements > 0) {
    // Check for view/hide toggles
    const toggleButtons = await page.locator('button:has-text("View"), button:has-text("Hide"), button:has-text("Show"), button:has-text("Expand")').all();
    if (toggleButtons.length > 0) {
      console.log(`✓ Found ${toggleButtons.length} view toggle buttons`);
      
      // Try clicking first toggle
      const firstToggle = toggleButtons[0];
      const toggleText = await firstToggle.textContent();
      await firstToggle.click();
      console.log(`✓ Clicked toggle: "${toggleText}"`);
      await page.waitForTimeout(500);
      await page.screenshot({ path: '/tmp/ux_eval_06_results_toggled.png', fullPage: true });
    }
    
    // Check for download buttons
    const downloadButtons = await page.locator('button:has-text("Download"), a[download], button:has-text("Export")').all();
    console.log(`✓ Found ${downloadButtons.length} download buttons`);
    
    if (downloadButtons.length > 0) {
      report.worksWell.push('Download buttons available for results');
      
      // Try clicking first download
      const firstDownload = downloadButtons[0];
      if (await firstDownload.isVisible() && await firstDownload.isEnabled()) {
        const downloadText = await firstDownload.textContent();
        console.log(`✓ Attempting download: "${downloadText}"`);
        await firstDownload.click();
        await page.waitForTimeout(500);
      }
    } else {
      report.unclearConfusing.push({
        severity: 'medium',
        issue: 'No download buttons for workflow results',
        userImpact: 'Users cannot save or export their analysis results',
        repro: 'Complete workflow - no download or export options visible'
      });
    }
    
    // Check for visualizations
    const vizElements = await page.locator('canvas, svg, img[src*="plot"], [class*="chart"]').count();
    if (vizElements > 0) {
      console.log(`✓ Found ${vizElements} visualization elements`);
      report.worksWell.push('Results include visual representations (charts/plots)');
    }
  } else {
    report.unclearConfusing.push({
      severity: 'medium',
      issue: 'Results section not clearly distinguished',
      userImpact: 'Users may not realize workflow has completed or where to find outputs',
      repro: 'Complete workflow - no clear "Results" section or output area'
    });
  }

  // Step 6: Check for feedback mechanisms
  console.log('\n[STEP 6] Looking for feedback mechanisms...');
  
  // Check for thumbs up/down
  const thumbsButtons = await page.locator('button[aria-label*="thumbs"], button:has-text("👍"), button:has-text("👎")').count();
  if (thumbsButtons > 0) {
    console.log(`✓ Found ${thumbsButtons} thumbs up/down feedback buttons`);
    report.worksWell.push('Inline feedback buttons allow users to rate responses');
  } else {
    report.topFixes.push({
      severity: 'low',
      issue: 'Add inline feedback (thumbs up/down) to each AI response',
      userImpact: 'Collect user satisfaction data to improve AI quality',
      repro: 'Add thumbs buttons next to each assistant message'
    });
  }
  
  // Check for survey or feedback form
  const feedbackForms = await page.locator('form, [class*="feedback"], [class*="survey"]').count();
  if (feedbackForms > 0) {
    console.log(`✓ Found ${feedbackForms} feedback forms`);
  }
  
  // Check for help or report issue buttons
  const helpButtons = await page.locator('button:has-text("Help"), button:has-text("Report"), button:has-text("Feedback")').count();
  if (helpButtons === 0) {
    report.topFixes.push({
      severity: 'medium',
      issue: 'Add "Report Issue" or "Get Help" button',
      userImpact: 'Users need a way to report problems or get assistance when stuck',
      repro: 'Add persistent help button in header or footer'
    });
  }

  await page.screenshot({ path: '/tmp/ux_eval_07_final.png', fullPage: true });

  // Generate final report
  console.log('\n[STEP 7] Generating UX report...');
  generateReport(report);
});

function generateReport(report: UXReport) {
  console.log('\n' + '='.repeat(80));
  console.log('BIOMATE UX EVALUATION REPORT');
  console.log('='.repeat(80));
  
  console.log('\n## WHAT WORKS WELL');
  console.log('-'.repeat(80));
  if (report.worksWell.length > 0) {
    report.worksWell.forEach((item, idx) => {
      console.log(`${idx + 1}. ${item}`);
    });
  } else {
    console.log('(No positive findings observed)');
  }
  
  console.log('\n## WHAT IS UNCLEAR/CONFUSING');
  console.log('-'.repeat(80));
  if (report.unclearConfusing.length > 0) {
    report.unclearConfusing.forEach((item, idx) => {
      console.log(`\n${idx + 1}. [${item.severity.toUpperCase()}] ${item.issue}`);
      console.log(`   User Impact: ${item.userImpact}`);
      console.log(`   Repro: ${item.repro}`);
    });
  } else {
    console.log('(No unclear/confusing issues found)');
  }
  
  console.log('\n## WHAT IS BROKEN OR RISKY');
  console.log('-'.repeat(80));
  if (report.brokenRisky.length > 0) {
    report.brokenRisky.forEach((item, idx) => {
      console.log(`\n${idx + 1}. [${item.severity.toUpperCase()}] ${item.issue}`);
      console.log(`   User Impact: ${item.userImpact}`);
      console.log(`   Repro: ${item.repro}`);
    });
  } else {
    console.log('None - no broken or risky issues observed');
  }
  
  console.log('\n## TOP UX FIXES TO PRIORITIZE NEXT');
  console.log('-'.repeat(80));
  
  // Compile top fixes from all categories
  const allIssues = [
    ...report.brokenRisky.map(i => ({ ...i, category: 'broken' })),
    ...report.unclearConfusing.filter(i => i.severity === 'high').map(i => ({ ...i, category: 'unclear' })),
    ...report.topFixes.map(i => ({ ...i, category: 'suggestion' }))
  ];
  
  // Sort by severity
  const severityOrder = { high: 0, medium: 1, low: 2 };
  allIssues.sort((a, b) => severityOrder[a.severity] - severityOrder[b.severity]);
  
  const topFixes = allIssues.slice(0, 5);
  
  if (topFixes.length > 0) {
    topFixes.forEach((item, idx) => {
      console.log(`\n${idx + 1}. [${item.severity.toUpperCase()}] ${item.issue}`);
      console.log(`   User Impact: ${item.userImpact}`);
      console.log(`   Repro: ${item.repro}`);
    });
  } else {
    console.log('(Application is in good shape - no critical fixes needed)');
  }
  
  console.log('\n' + '='.repeat(80));
  console.log('Screenshots saved to /tmp/ux_eval_*.png');
  console.log('='.repeat(80) + '\n');
}
