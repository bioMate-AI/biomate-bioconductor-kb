/**
 * Mock Galaxy API for UI Development
 * Provides realistic responses matching actual Galaxy API structure
 * Allows UI development while Galaxy backend integration is finalized
 */

import type {
  GalaxyTool,
  ToolSearchResponse,
  ToolCategoriesResponse,
  ToolInstallRequest,
  ToolInstallResponse,
  InstalledToolsResponse,
  BioMNIDataset,
  DatasetSearchRequest,
  DatasetSearchResponse,
  GalaxyWorkflow,
  GalaxyWorkflowInvocation,
  GalaxyJob,
  GalaxyJobState,
  WorkflowStepConfig,
} from '../shared/galaxy-types';

/**
 * Mock Tool Database (based on actual LC-MS tools)
 */
const MOCK_TOOLS: GalaxyTool[] = [
  {
    id: 1,
    tool_id: 'toolshed.g2.bx.psu.edu/repos/galaxyp/mzml_to_msp/mzml_to_msp/1.0.0',
    name: 'mzML to MSP',
    description: 'Convert mzML files to MSP format for MS/MS library matching',
    version: '1.0.0',
    repo_owner: 'galaxyp',
    repo_name: 'mzml_to_msp',
    category: 'metabolomics',
    tool_shed_url: 'https://toolshed.g2.bx.psu.edu',
    is_installed: true,
    install_status: 'installed',
  },
  {
    id: 2,
    tool_id: 'toolshed.g2.bx.psu.edu/repos/workflow4metabolomics/xcms_xcmsset/abims_xcms_xcmsSet/3.12.0',
    name: 'XCMS findChromPeaks',
    description: 'Peak detection for LC-MS data using XCMS',
    version: '3.12.0',
    repo_owner: 'workflow4metabolomics',
    repo_name: 'xcms_xcmsset',
    category: 'metabolomics',
    tool_shed_url: 'https://toolshed.g2.bx.psu.edu',
    is_installed: true,
    install_status: 'installed',
  },
  {
    id: 3,
    tool_id: 'toolshed.g2.bx.psu.edu/repos/workflow4metabolomics/xcms_group/abims_xcms_group/3.12.0',
    name: 'XCMS groupChromPeaks',
    description: 'Group peaks across samples using XCMS',
    version: '3.12.0',
    repo_owner: 'workflow4metabolomics',
    repo_name: 'xcms_group',
    category: 'metabolomics',
    tool_shed_url: 'https://toolshed.g2.bx.psu.edu',
    is_installed: true,
    install_status: 'installed',
  },
  {
    id: 4,
    tool_id: 'toolshed.g2.bx.psu.edu/repos/workflow4metabolomics/xcms_retcor/abims_xcms_retcor/3.12.0',
    name: 'XCMS adjustRtime',
    description: 'Retention time alignment using XCMS',
    version: '3.12.0',
    repo_owner: 'workflow4metabolomics',
    repo_name: 'xcms_retcor',
    category: 'metabolomics',
    tool_shed_url: 'https://toolshed.g2.bx.psu.edu',
    is_installed: true,
    install_status: 'installed',
  },
  {
    id: 5,
    tool_id: 'toolshed.g2.bx.psu.edu/repos/workflow4metabolomics/camera_annotate/abims_CAMERA_annotateDiffreport/1.48.0',
    name: 'CAMERA Annotation',
    description: 'Annotate isotopes, adducts, and fragments using CAMERA',
    version: '1.48.0',
    repo_owner: 'workflow4metabolomics',
    repo_name: 'camera_annotate',
    category: 'metabolomics',
    tool_shed_url: 'https://toolshed.g2.bx.psu.edu',
    is_installed: false,
    install_status: 'not_installed',
  },
  {
    id: 6,
    tool_id: 'toolshed.g2.bx.psu.edu/repos/recetox/metaboblend/metaboblend/0.6.0',
    name: 'MetaboBlend',
    description: 'Metabolite identification using spectral library matching',
    version: '0.6.0',
    repo_owner: 'recetox',
    repo_name: 'metaboblend',
    category: 'metabolomics',
    tool_shed_url: 'https://toolshed.g2.bx.psu.edu',
    is_installed: false,
    install_status: 'not_installed',
  },
];

/**
 * Mock Dataset Database (based on actual BioMNI datasets)
 */
const MOCK_DATASETS: BioMNIDataset[] = [
  {
    id: 'kegg/kegg_compounds_complete.json',
    name: 'KEGG Compound Database',
    description: 'Complete KEGG compound database with pathways and cross-references',
    category: 'metabolomics',
    format: 'json',
    size_mb: 5.9,
    entries: 18000,
    fields: { compound_id: 'string', name: 'string', formula: 'string', mass: 'number', pathways: 'array' },
    lcms_relevant: true,
    source: 'database/kegg',
    path: '/tmp/biomni_datasets/data/databases/kegg/kegg_compounds_complete.json',
  },
  {
    id: 'hmdb/hmdb_metabolites.xml',
    name: 'HMDB Metabolite Database',
    description: 'Complete HMDB metabolite database (220K metabolites)',
    category: 'metabolomics',
    format: 'xml',
    size_mb: 909,
    entries: 220945,
    fields: { accession: 'string', name: 'string', chemical_formula: 'string', monisotopic_mass: 'number' },
    lcms_relevant: true,
    source: 'database/hmdb',
    path: '/tmp/biomni_datasets/data/databases/hmdb/hmdb_metabolites.xml',
  },
  {
    id: 'data_lake/BindingDB_All_202409.tsv',
    name: 'BindingDB Drug-Protein Interactions',
    description: 'Drug-protein binding affinities from BindingDB',
    category: 'pharmacology',
    format: 'tsv',
    size_mb: 5956,
    rows: 2700000,
    fields: { ligand_id: 'string', target_id: 'string', affinity: 'number', ki_nm: 'number' },
    lcms_relevant: false,
    source: 'data_lake',
    path: '/tmp/biomni_datasets/data/biomni_data/data_lake/BindingDB_All_202409.tsv',
  },
];

/**
 * Simulated job state progression
 */
class MockJobSimulator {
  private jobs: Map<string, GalaxyJob> = new Map();

  createJob(toolId: string, stepId: string): GalaxyJob {
    const jobId = `mock_job_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    const job: GalaxyJob = {
      id: jobId,
      tool_id: toolId,
      state: 'new',
      create_time: new Date().toISOString(),
      update_time: new Date().toISOString(),
    };
    this.jobs.set(jobId, job);

    // Simulate realistic state progression
    this.simulateJobProgression(jobId);

    return job;
  }

  private async simulateJobProgression(jobId: string) {
    const job = this.jobs.get(jobId);
    if (!job) return;

    // new -> queued (500ms)
    await this.sleep(500);
    job.state = 'queued';
    job.update_time = new Date().toISOString();

    // queued -> running (1-3 seconds)
    await this.sleep(1000 + Math.random() * 2000);
    job.state = 'running';
    job.update_time = new Date().toISOString();

    // running -> ok (5-15 seconds, or error 5% of time)
    await this.sleep(5000 + Math.random() * 10000);
    if (Math.random() < 0.05) {
      job.state = 'error';
      job.stderr = 'Mock error: Simulated tool failure for testing error handling';
      job.exit_code = 1;
    } else {
      job.state = 'ok';
      job.stdout = 'Mock job completed successfully';
      job.exit_code = 0;
    }
    job.update_time = new Date().toISOString();
  }

  getJob(jobId: string): GalaxyJob | undefined {
    return this.jobs.get(jobId);
  }

  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}

const jobSimulator = new MockJobSimulator();

/**
 * Mock Galaxy API Implementation
 */
export class MockGalaxyAPI {
  private installingTools: Set<string> = new Set();
  private invocations: Map<string, GalaxyWorkflowInvocation> = new Map();

  // ============================================================================
  // Tool Search API
  // ============================================================================

  async searchTools(query: string, category?: string, limit: number = 50): Promise<ToolSearchResponse> {
    await this.sleep(200); // Simulate network delay

    let results = MOCK_TOOLS.filter((tool) => {
      const matchesQuery =
        tool.name.toLowerCase().includes(query.toLowerCase()) ||
        tool.description.toLowerCase().includes(query.toLowerCase()) ||
        tool.tool_id.toLowerCase().includes(query.toLowerCase());

      const matchesCategory = !category || tool.category === category;

      return matchesQuery && matchesCategory;
    });

    results = results.slice(0, limit);

    return {
      query,
      category: category || null,
      count: results.length,
      tools: results,
    };
  }

  async getToolCategories(): Promise<ToolCategoriesResponse> {
    await this.sleep(100);

    const categories = Array.from(new Set(MOCK_TOOLS.map((t) => t.category)));
    return {
      categories: categories.map((cat) => ({
        name: cat,
        count: MOCK_TOOLS.filter((t) => t.category === cat).length,
      })),
    };
  }

  async getToolById(toolId: string): Promise<GalaxyTool> {
    await this.sleep(100);

    const tool = MOCK_TOOLS.find((t) => t.tool_id === toolId);
    if (!tool) {
      throw { error: 'ToolNotFound', message: `Tool not found: ${toolId}`, status_code: 404 };
    }
    return tool;
  }

  async installTool(request: ToolInstallRequest): Promise<ToolInstallResponse> {
    await this.sleep(500);

    const toolId = request.tool_id || `${request.owner}/${request.name}`;
    this.installingTools.add(toolId);

    // Simulate installation (3-5 seconds)
    setTimeout(() => {
      const tool = MOCK_TOOLS.find((t) => t.tool_id === toolId);
      if (tool) {
        tool.is_installed = true;
        tool.install_status = 'installed';
        tool.install_date = new Date().toISOString();
      }
      this.installingTools.delete(toolId);
    }, 3000 + Math.random() * 2000);

    return {
      success: true,
      message: 'Tool installation started',
      tool_id: toolId,
      status: 'installing',
    };
  }

  async checkAndInstallTool(toolId: string): Promise<ToolInstallResponse> {
    await this.sleep(200);

    const tool = MOCK_TOOLS.find((t) => t.tool_id === toolId);
    if (!tool) {
      throw { error: 'ToolNotFound', message: `Tool not found: ${toolId}`, status_code: 404 };
    }

    if (tool.is_installed) {
      return {
        success: true,
        message: 'Tool already installed',
        tool_id: toolId,
        status: 'installed',
      };
    }

    return this.installTool({ tool_id: toolId });
  }

  async getInstalledTools(): Promise<InstalledToolsResponse> {
    await this.sleep(100);

    const installed = MOCK_TOOLS.filter((t) => t.is_installed);
    return {
      count: installed.length,
      tools: installed,
    };
  }

  // ============================================================================
  // Dataset Discovery API
  // ============================================================================

  async searchDatasets(request: DatasetSearchRequest): Promise<DatasetSearchResponse> {
    await this.sleep(200);

    let results = MOCK_DATASETS.filter((dataset) => {
      const matchesQuery =
        dataset.name.toLowerCase().includes(request.query.toLowerCase()) ||
        dataset.description.toLowerCase().includes(request.query.toLowerCase());

      const matchesCategory = !request.category || dataset.category === request.category;
      const matchesFormat = !request.format_type || dataset.format === request.format_type;
      const matchesSize =
        (!request.min_size || dataset.size_mb >= request.min_size) &&
        (!request.max_size || dataset.size_mb <= request.max_size);
      const matchesLCMS = !request.lcms_only || dataset.lcms_relevant;

      return matchesQuery && matchesCategory && matchesFormat && matchesSize && matchesLCMS;
    });

    results = results.slice(0, request.limit || 10);

    return {
      query: request.query,
      count: results.length,
      datasets: results,
    };
  }

  async getDatasetsByCategory(category: string): Promise<BioMNIDataset[]> {
    await this.sleep(100);
    return MOCK_DATASETS.filter((d) => d.category === category);
  }

  async getDatasetById(datasetId: string): Promise<BioMNIDataset> {
    await this.sleep(100);
    const dataset = MOCK_DATASETS.find((d) => d.id === datasetId);
    if (!dataset) {
      throw { error: 'DatasetNotFound', message: `Dataset not found: ${datasetId}`, status_code: 404 };
    }
    return dataset;
  }

  // ============================================================================
  // Workflow Execution API
  // ============================================================================

  async invokeWorkflow(
    workflowId: string,
    inputs: Record<string, any>,
    parameters?: Record<string, any>
  ): Promise<GalaxyWorkflowInvocation> {
    await this.sleep(300);

    const invocationId = `mock_inv_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    const invocation: GalaxyWorkflowInvocation = {
      id: invocationId,
      workflow_id: workflowId,
      state: 'new',
      create_time: new Date().toISOString(),
      update_time: new Date().toISOString(),
      steps: [],
    };

    this.invocations.set(invocationId, invocation);

    // Simulate workflow execution
    this.simulateWorkflowExecution(invocationId, workflowId);

    return invocation;
  }

  private async simulateWorkflowExecution(invocationId: string, workflowId: string) {
    const invocation = this.invocations.get(invocationId);
    if (!invocation) return;

    // Create mock steps for typical LC-MS workflow
    const mockStepIds = ['step_1', 'step_2', 'step_3', 'step_4'];
    invocation.steps = mockStepIds.map((stepId, index) => ({
      id: `mock_step_${Date.now()}_${index}`,
      workflow_step_id: stepId,
      state: 'new',
      update_time: new Date().toISOString(),
      order_index: index,
    }));

    invocation.state = 'scheduled';
    invocation.update_time = new Date().toISOString();

    // Execute steps sequentially
    for (const step of invocation.steps) {
      const tool = MOCK_TOOLS[step.order_index % MOCK_TOOLS.length];
      const job = jobSimulator.createJob(tool.tool_id, step.workflow_step_id);

      step.job_id = job.id;
      step.state = 'running';
      step.update_time = new Date().toISOString();

      // Wait for job to complete
      await this.waitForJob(job.id);

      const completedJob = jobSimulator.getJob(job.id);
      step.state = completedJob?.state || 'error';
      step.update_time = new Date().toISOString();

      if (step.state === 'error') {
        invocation.state = 'failed';
        invocation.update_time = new Date().toISOString();
        return;
      }
    }

    // Mark workflow as completed (Galaxy doesn't have 'completed' state, workflow just finishes)
    // In reality, workflow stays in 'scheduled' state but all steps are done
    // For testing purposes, we'll keep it as 'scheduled' - the poller should detect completion
    invocation.update_time = new Date().toISOString();
  }

  private async waitForJob(jobId: string): Promise<void> {
    while (true) {
      const job = jobSimulator.getJob(jobId);
      if (!job || job.state === 'ok' || job.state === 'error') {
        return;
      }
      await this.sleep(500);
    }
  }

  async getInvocation(workflowId: string, invocationId: string): Promise<GalaxyWorkflowInvocation> {
    await this.sleep(100);

    const invocation = this.invocations.get(invocationId);
    if (!invocation) {
      throw { error: 'InvocationNotFound', message: `Invocation not found: ${invocationId}`, status_code: 404 };
    }
    return invocation;
  }

  async getJob(jobId: string): Promise<GalaxyJob> {
    await this.sleep(100);

    const job = jobSimulator.getJob(jobId);
    if (!job) {
      throw { error: 'JobNotFound', message: `Job not found: ${jobId}`, status_code: 404 };
    }
    return job;
  }

  async getJobStdout(jobId: string): Promise<string> {
    await this.sleep(100);
    const job = jobSimulator.getJob(jobId);
    return job?.stdout || '';
  }

  async getJobStderr(jobId: string): Promise<string> {
    await this.sleep(100);
    const job = jobSimulator.getJob(jobId);
    return job?.stderr || '';
  }

  async healthCheck(): Promise<boolean> {
    await this.sleep(50);
    return true;
  }

  // ============================================================================
  // Utilities
  // ============================================================================

  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}

// Export singleton instance
export const mockGalaxyAPI = new MockGalaxyAPI();
