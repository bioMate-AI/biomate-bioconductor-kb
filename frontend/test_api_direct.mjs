/**
 * Direct API test - bypasses frontend redirect
 */

import http from 'http';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const OUTPUT_DIR = path.join(__dirname, '..', 'demo_videos');
const TIMESTAMP = Date.now();
const TEST_DIR = path.join(OUTPUT_DIR, `direct_api_${TIMESTAMP}`);

if (!fs.existsSync(TEST_DIR)) {
  fs.mkdirSync(TEST_DIR, { recursive: true });
}

function httpRequest(options, postData) {
  return new Promise((resolve, reject) => {
    const req = http.request(options, (res) => {
      let data = '';

      res.on('data', (chunk) => {
        data += chunk;
      });

      res.on('end', () => {
        resolve({
          statusCode: res.statusCode,
          headers: res.headers,
          body: data
        });
      });
    });

    req.on('error', (error) => {
      reject(error);
    });

    if (postData) {
      req.write(postData);
    }

    req.end();
  });
}

async function runTest() {
  console.log('🎬 BioMate Direct API Test\n');
  console.log(`📁 Output: ${TEST_DIR}\n`);

  let passed = 0;
  let failed = 0;

  // Test 1: Chat API on port 5000 (direct HTTP, ignore redirect)
  console.log('━'.repeat(70));
  console.log('TEST 1: Chat API on Port 5000');
  console.log('━'.repeat(70));

  try {
    const chatMessage = {
      message: 'Model bacterial growth dynamics with initial population of 1000 cells and growth rate of 0.5'
    };

    const options = {
      hostname: 'localhost',
      port: 5000,
      path: '/api/chat',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      }
    };

    console.log('Sending request to http://localhost:5000/api/chat...');

    const response = await httpRequest(options, JSON.stringify(chatMessage));

    console.log(`Status: ${response.statusCode}`);

    if (response.statusCode === 301 || response.statusCode === 302) {
      console.log('⚠️  API redirects to HTTPS');
      console.log(`Location: ${response.headers.location}`);
      failed++;
    } else if (response.statusCode === 200) {
      const result = JSON.parse(response.body);

      fs.writeFileSync(
        path.join(TEST_DIR, 'chat_response_5000.json'),
        JSON.stringify(result, null, 2)
      );

      console.log('✅ Chat API responded successfully!');
      console.log(`  Has workflow: ${!!result.workflow}`);
      console.log(`  Workflow success: ${result.workflow?.success}`);

      if (result.workflow?.workflow_ga) {
        const steps = Object.keys(result.workflow.workflow_ga.steps || {});
        console.log(`  Steps: ${steps.length}`);
        steps.forEach(id => {
          console.log(`    - ${result.workflow.workflow_ga.steps[id].tool_id}`);
        });
      }

      passed++;
    } else {
      console.log(`❌ Unexpected status: ${response.statusCode}`);
      console.log(response.body);
      failed++;
    }
  } catch (error) {
    console.log(`❌ Error: ${error.message}`);
    failed++;
  }

  // Test 2: Try port 5001
  console.log('\n' + '━'.repeat(70));
  console.log('TEST 2: Chat API on Port 5001');
  console.log('━'.repeat(70));

  try {
    const chatMessage = {
      message: 'Model bacterial growth dynamics with initial population of 1000 cells and growth rate of 0.5'
    };

    const options = {
      hostname: 'localhost',
      port: 5001,
      path: '/api/chat',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      }
    };

    console.log('Sending request to http://localhost:5001/api/chat...');

    const response = await httpRequest(options, JSON.stringify(chatMessage));

    console.log(`Status: ${response.statusCode}`);

    if (response.statusCode === 200) {
      const result = JSON.parse(response.body);

      fs.writeFileSync(
        path.join(TEST_DIR, 'chat_response_5001.json'),
        JSON.stringify(result, null, 2)
      );

      console.log('✅ Chat API responded successfully on port 5001!');
      console.log(`  Has workflow: ${!!result.workflow}`);
      console.log(`  Workflow success: ${result.workflow?.success}`);

      if (result.workflow?.workflow_ga) {
        const steps = Object.keys(result.workflow.workflow_ga.steps || {});
        console.log(`  Steps: ${steps.length}`);
      }

      passed++;
    } else {
      console.log(`⚠️  Port 5001 status: ${response.statusCode}`);
    }
  } catch (error) {
    console.log(`⚠️  Port 5001 not available: ${error.message}`);
  }

  // Summary
  console.log('\n' + '═'.repeat(70));
  console.log('TEST SUMMARY');
  console.log('═'.repeat(70));
  console.log(`✅ Passed: ${passed}`);
  console.log(`${failed > 0 ? '❌' : '✅'} Failed: ${failed}`);

  console.log(`\n📁 Output: ${TEST_DIR}`);

  const files = fs.readdirSync(TEST_DIR);
  if (files.length > 0) {
    console.log('\n📄 Generated files:');
    files.forEach(f => console.log(`  ✓ ${f}`));
  }

  return failed === 0 ? 0 : 1;
}

runTest()
  .then(exitCode => process.exit(exitCode))
  .catch(error => {
    console.error('Fatal error:', error);
    process.exit(1);
  });
