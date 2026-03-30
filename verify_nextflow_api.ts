async function runTest() {
  const BASE_URL = 'http://localhost:5000';
  console.log('🧪 Starting Nextflow API Verification Test...');

  try {
    // 1. Health Check
    const health = await fetch(BASE_URL + '/');
    if (!health.ok) throw new Error('Frontend not reachable');
    console.log('✅ Frontend reachable');

    // 2. Chat Request - Explicit Nextflow
    const message = "Generate a workflow using the rnaseq-nf pipeline. I specifically want a Nextflow workflow.";
    console.log(`\n2️⃣ Sending Chat Request: "${message}"...`);

    const chatRes = await fetch(BASE_URL + '/api/chat', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message })
    });

    const data: any = await chatRes.json();
    
    // Debug output
    // console.log(JSON.stringify(data, null, 2));

    if (!data.workflow) {
        console.log('\n❌ No workflow returned.');
        console.log('Intent:', data.metadata?.intentType);
        console.log('Confidence:', data.metadata?.workflowSuggestion?.confidence);
        console.log('Reasoning:', data.metadata?.workflowSuggestion?.reasoning);
        
        if (data.metadata?.tools) {
             console.log('Returned Tools instead:', data.metadata.tools.length);
        }
        return;
    }

    console.log('\n✅ Workflow Returned!');
    console.log('Success:', data.workflow.success);
    console.log('Error:', data.workflow.error);
    console.log('Message:', data.workflow.message);
    console.log('Full Workflow Object:', JSON.stringify(data.workflow, null, 2));
    console.log('Workflow Object Keys:', Object.keys(data.workflow));
           console.log('Workflow Type:', data.workflow.workflow_type);
           console.log('Workflow Engine:', data.workflow.execution_engine);
    console.log('Source:', data.workflow.source);
    
    if (data.workflow.workflow_type === 'nextflow' || data.workflow.execution_engine === 'nextflow') {
        console.log('✅ SUCCESS: Nextflow workflow generated.');
        if (data.workflow.nextflow_path) {
            console.log('Path:', data.workflow.nextflow_path);
        } else {
            console.log('⚠️ Warning: Nextflow path missing.');
        }
    } else {
        console.log('❌ FAIL: Returned Galaxy workflow instead of Nextflow.');
    }

  } catch (error) {
    console.error('❌ Test Failed:', error);
  }
}

runTest();
