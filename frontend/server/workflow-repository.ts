/**
 * Use Case-Based Workflow Repository
 *
 * Stores and retrieves validated workflow templates for different analysis scenarios.
 * Extends existing Galaxy workflows with use case metadata for easier discovery and reuse.
 */

import fs from 'fs/promises';
import path from 'path';
import { v4 as uuidv4 } from 'uuid';
import type {
  WorkflowTemplate,
  WorkflowTemplateSearchRequest,
  WorkflowTemplateSearchResponse,
  SaveWorkflowTemplateRequest,
  WorkflowUseCase,
} from '../shared/galaxy-types';

export class WorkflowRepository {
  private repositoryPath: string;
  private templates: Map<string, WorkflowTemplate> = new Map();

  constructor(repositoryPath: string = './data/workflow-templates') {
    this.repositoryPath = repositoryPath;
  }

  /**
   * Initialize the repository (load existing templates from disk)
   */
  async initialize(): Promise<void> {
    try {
      await fs.mkdir(this.repositoryPath, { recursive: true });

      // Load existing templates
      const files = await fs.readdir(this.repositoryPath);
      for (const file of files) {
        if (file.endsWith('.json')) {
          const filePath = path.join(this.repositoryPath, file);
          const content = await fs.readFile(filePath, 'utf-8');
          const template: WorkflowTemplate = JSON.parse(content);
          this.templates.set(template.id, template);
        }
      }

      console.log(`[WorkflowRepository] Loaded ${this.templates.size} workflow templates`);
    } catch (error) {
      console.error('[WorkflowRepository] Failed to initialize:', error);
      throw error;
    }
  }

  /**
   * Save a new workflow template
   */
  async saveTemplate(request: SaveWorkflowTemplateRequest, userId: string = 'system'): Promise<WorkflowTemplate> {
    const now = new Date().toISOString();

    const useCase: WorkflowUseCase = {
      id: uuidv4(),
      name: request.use_case_name,
      description: request.use_case_description,
      category: request.use_case_category as any,
      tags: request.tags || [],
      analysis_type: request.analysis_type,
      sample_types: request.sample_types,
      input_types: request.input_types,
      expected_outputs: request.expected_outputs,
      difficulty: (request.difficulty as any) || 'intermediate',
      estimated_time: request.estimated_time || 'Unknown',
      rationale: request.rationale,
      protocol_references: request.protocol_references,
      created_by: userId,
      created_at: now,
      updated_at: now,
      usage_count: 0,
      success_rate: 0,
    };

    // Extract steps from workflow_ga
    const steps = Object.entries(request.workflow_ga.steps || {}).map(([stepId, stepData]: [string, any]) => ({
      step_id: stepId,
      tool_id: stepData.tool_id || 'unknown',
      tool_name: stepData.name || 'Unknown Tool',
      parameter_template_id: request.parameter_template_ids?.[stepId],
      custom_parameters: stepData.tool_state,
    }));

    const template: WorkflowTemplate = {
      id: uuidv4(),
      name: request.name,
      description: request.description,
      use_case: useCase,
      workflow_ga: request.workflow_ga,
      steps,
      validated: false,
    };

    // Save to memory
    this.templates.set(template.id, template);

    // Persist to disk
    const filePath = path.join(this.repositoryPath, `${template.id}.json`);
    await fs.writeFile(filePath, JSON.stringify(template, null, 2));

    console.log(`[WorkflowRepository] Saved template: ${template.id} - ${template.name}`);
    return template;
  }

  /**
   * Search for workflow templates
   */
  async searchTemplates(request: WorkflowTemplateSearchRequest): Promise<WorkflowTemplateSearchResponse> {
    let results = Array.from(this.templates.values());

    // Filter by use case category
    if (request.use_case_category) {
      results = results.filter(t => t.use_case.category === request.use_case_category);
    }

    // Filter by analysis type
    if (request.analysis_type) {
      results = results.filter(t =>
        t.use_case.analysis_type?.toLowerCase().includes(request.analysis_type!.toLowerCase())
      );
    }

    // Filter by sample type
    if (request.sample_type) {
      results = results.filter(t =>
        t.use_case.sample_types.some(st =>
          st.toLowerCase().includes(request.sample_type!.toLowerCase())
        )
      );
    }

    // Filter by input type
    if (request.input_type) {
      results = results.filter(t =>
        t.use_case.input_types.some(it =>
          it.toLowerCase().includes(request.input_type!.toLowerCase())
        )
      );
    }

    // Filter by tags
    if (request.tags && request.tags.length > 0) {
      results = results.filter(t =>
        request.tags!.some(tag => t.use_case.tags.includes(tag))
      );
    }

    // Filter by difficulty
    if (request.difficulty) {
      results = results.filter(t => t.use_case.difficulty === request.difficulty);
    }

    // Sort by usage count and success rate
    results.sort((a, b) => {
      const scoreA = (a.use_case.usage_count || 0) * (a.use_case.success_rate || 0);
      const scoreB = (b.use_case.usage_count || 0) * (b.use_case.success_rate || 0);
      return scoreB - scoreA;
    });

    // Limit results
    if (request.limit) {
      results = results.slice(0, request.limit);
    }

    return {
      count: results.length,
      templates: results,
    };
  }

  /**
   * Get a specific workflow template by ID
   */
  async getTemplate(templateId: string): Promise<WorkflowTemplate | null> {
    return this.templates.get(templateId) || null;
  }

  /**
   * Update template usage statistics
   */
  async recordUsage(templateId: string, success: boolean, runtimeMinutes?: number): Promise<void> {
    const template = this.templates.get(templateId);
    if (!template) {
      throw new Error(`Template not found: ${templateId}`);
    }

    template.use_case.usage_count = (template.use_case.usage_count || 0) + 1;
    const successCount = (template.use_case.success_rate || 0) * ((template.use_case.usage_count || 1) - 1);
    template.use_case.success_rate = (successCount + (success ? 1 : 0)) / template.use_case.usage_count;
    template.use_case.updated_at = new Date().toISOString();

    // Update average runtime
    if (runtimeMinutes !== undefined) {
      const currentAvg = template.use_case.average_runtime || 0;
      const count = template.use_case.usage_count;
      template.use_case.average_runtime = ((currentAvg * (count - 1)) + runtimeMinutes) / count;
    }

    // Persist changes
    const filePath = path.join(this.repositoryPath, `${template.id}.json`);
    await fs.writeFile(filePath, JSON.stringify(template, null, 2));
  }

  /**
   * Mark template as validated
   */
  async validateTemplate(
    templateId: string,
    testRuns: number,
    successCount: number,
    failureModes?: string[]
  ): Promise<void> {
    const template = this.templates.get(templateId);
    if (!template) {
      throw new Error(`Template not found: ${templateId}`);
    }

    template.validated = successCount > 0;
    template.validation_results = {
      test_runs: testRuns,
      success_count: successCount,
      failure_modes: failureModes,
    };

    // Persist changes
    const filePath = path.join(this.repositoryPath, `${template.id}.json`);
    await fs.writeFile(filePath, JSON.stringify(template, null, 2));

    console.log(`[WorkflowRepository] Validated template ${templateId}: ${successCount}/${testRuns} successful`);
  }

  /**
   * Delete a workflow template
   */
  async deleteTemplate(templateId: string): Promise<void> {
    const template = this.templates.get(templateId);
    if (!template) {
      throw new Error(`Template not found: ${templateId}`);
    }

    // Remove from memory
    this.templates.delete(templateId);

    // Remove from disk
    const filePath = path.join(this.repositoryPath, `${templateId}.json`);
    await fs.unlink(filePath);

    console.log(`[WorkflowRepository] Deleted template: ${templateId}`);
  }

  /**
   * Get popular templates (by usage)
   */
  async getPopularTemplates(limit: number = 10): Promise<WorkflowTemplate[]> {
    return Array.from(this.templates.values())
      .sort((a, b) => (b.use_case.usage_count || 0) - (a.use_case.usage_count || 0))
      .slice(0, limit);
  }

  /**
   * Get validated templates only
   */
  async getValidatedTemplates(): Promise<WorkflowTemplate[]> {
    return Array.from(this.templates.values()).filter(t => t.validated);
  }

  /**
   * Seed repository with example templates (for initial setup)
   */
  async seedExamples(): Promise<void> {
    const examples: SaveWorkflowTemplateRequest[] = [
      {
        name: 'RNA-seq Differential Expression Analysis',
        description: 'Complete workflow for identifying differentially expressed genes from RNA-seq data',
        use_case_name: 'RNA-seq DE Analysis - Human',
        use_case_description: 'Standard differential expression workflow for human RNA-seq samples',
        use_case_category: 'genomics',
        analysis_type: 'differential_expression',
        sample_types: ['human_tissue', 'human_cell_line'],
        input_types: ['fastq', 'fastq.gz'],
        expected_outputs: ['counts_table', 'differential_expression_results', 'plots'],
        tags: ['rna-seq', 'differential-expression', 'human', 'illumina'],
        difficulty: 'intermediate',
        estimated_time: '2-4 hours',
        rationale: 'Standard Tuxedo suite workflow adapted for modern tools. Uses HISAT2 for alignment, featureCounts for quantification, and DESeq2 for statistical analysis.',
        protocol_references: [
          'Trapnell et al. (2012) Differential gene and transcript expression analysis of RNA-seq experiments',
          'Love et al. (2014) Moderated estimation of fold change and dispersion for RNA-seq data with DESeq2',
        ],
        workflow_ga: {
          a_galaxy_workflow: '1.0',
          annotation: 'RNA-seq differential expression analysis',
          format_version: '0.1',
          name: 'RNA-seq DE Analysis',
          steps: {
            '0': {
              annotation: 'Input dataset collection',
              id: 0,
              tool_id: 'data_input',
              type: 'data_input',
              name: 'Input Dataset Collection',
            },
            '1': {
              annotation: 'Quality control with FastQC',
              id: 1,
              tool_id: 'fastqc',
              tool_version: '0.12.1',
              name: 'FastQC',
              tool_state: {
                threads: 4,
                nogroup: false,
              },
            },
            '2': {
              annotation: 'Align reads with HISAT2',
              id: 2,
              tool_id: 'hisat2',
              tool_version: '2.2.1',
              name: 'HISAT2',
              tool_state: {
                threads: 8,
                reference_genome: 'hg38',
              },
            },
            '3': {
              annotation: 'Count reads with featureCounts',
              id: 3,
              tool_id: 'featurecounts',
              tool_version: '2.0.1',
              name: 'featureCounts',
              tool_state: {
                threads: 4,
                feature_type: 'exon',
                attribute_type: 'gene_id',
              },
            },
            '4': {
              annotation: 'Differential expression with DESeq2',
              id: 4,
              tool_id: 'deseq2',
              tool_version: '1.34.0',
              name: 'DESeq2',
              tool_state: {
                alpha: 0.05,
                fit_type: 'parametric',
              },
            },
          },
        },
      },
      {
        name: 'LC-MS Metabolomics Peak Detection',
        description: 'Workflow for detecting and quantifying metabolite peaks from LC-MS data',
        use_case_name: 'LC-MS Metabolomics - Positive Mode',
        use_case_description: 'Peak detection workflow optimized for positive ionization mode LC-MS data',
        use_case_category: 'metabolomics',
        analysis_type: 'metabolite_identification',
        sample_types: ['human_plasma', 'human_serum', 'cell_extract'],
        input_types: ['mzML', 'mzXML'],
        expected_outputs: ['peak_table', 'feature_annotations'],
        tags: ['metabolomics', 'lc-ms', 'positive-mode', 'xcms'],
        difficulty: 'advanced',
        estimated_time: '1-2 hours',
        rationale: 'XCMS-based workflow with optimized parameters for positive mode LC-MS. Uses centWave for peak detection and CAMERA for annotation.',
        protocol_references: [
          'Smith et al. (2006) XCMS: Processing mass spectrometry data for metabolite profiling',
          'Kuhl et al. (2012) CAMERA: An integrated strategy for compound spectra extraction',
        ],
        workflow_ga: {
          a_galaxy_workflow: '1.0',
          annotation: 'LC-MS metabolomics peak detection',
          format_version: '0.1',
          name: 'LC-MS Peak Detection',
          steps: {
            '0': {
              annotation: 'Input mzML files',
              id: 0,
              tool_id: 'data_input',
              type: 'data_input',
              name: 'Input Dataset Collection',
            },
            '1': {
              annotation: 'Peak detection with XCMS',
              id: 1,
              tool_id: 'xcms',
              tool_version: '3.16.1',
              name: 'XCMS Peak Detection',
              tool_state: {
                method: 'centWave',
                ppm: 15,
                peakwidth_min: 5,
                peakwidth_max: 20,
              },
            },
            '2': {
              annotation: 'Retention time correction',
              id: 2,
              tool_id: 'xcms',
              tool_version: '3.16.1',
              name: 'XCMS RT Correction',
              tool_state: {
                method: 'obiwarp',
              },
            },
            '3': {
              annotation: 'Peak annotation with CAMERA',
              id: 3,
              tool_id: 'camera',
              tool_version: '1.50.0',
              name: 'CAMERA Annotation',
              tool_state: {
                polarity: 'positive',
                ppm: 10,
              },
            },
          },
        },
      },
      {
        name: 'Quality Control for Next-Gen Sequencing',
        description: 'Comprehensive QC workflow for assessing NGS data quality',
        use_case_name: 'NGS Quality Control - Illumina',
        use_case_description: 'Standard QC workflow for Illumina sequencing data with trimming',
        use_case_category: 'quality_control',
        analysis_type: 'quality_assessment',
        sample_types: ['any_ngs'],
        input_types: ['fastq', 'fastq.gz'],
        expected_outputs: ['qc_reports', 'trimmed_reads'],
        tags: ['qc', 'quality-control', 'illumina', 'fastqc', 'trimming'],
        difficulty: 'beginner',
        estimated_time: '30-60 minutes',
        rationale: 'Essential first step for any NGS analysis. FastQC provides comprehensive quality metrics, Trimmomatic removes low-quality bases and adapters.',
        protocol_references: [
          'https://www.bioinformatics.babraham.ac.uk/projects/fastqc/',
          'Bolger et al. (2014) Trimmomatic: a flexible trimmer for Illumina sequence data',
        ],
        workflow_ga: {
          a_galaxy_workflow: '1.0',
          annotation: 'NGS quality control',
          format_version: '0.1',
          name: 'NGS QC Workflow',
          steps: {
            '0': {
              annotation: 'Input FASTQ files',
              id: 0,
              tool_id: 'data_input',
              type: 'data_input',
              name: 'Input Dataset Collection',
            },
            '1': {
              annotation: 'Pre-trim quality check',
              id: 1,
              tool_id: 'fastqc',
              tool_version: '0.12.1',
              name: 'FastQC Before',
              tool_state: {
                threads: 2,
              },
            },
            '2': {
              annotation: 'Trim adapters and low-quality bases',
              id: 2,
              tool_id: 'trimmomatic',
              tool_version: '0.39',
              name: 'Trimmomatic',
              tool_state: {
                illuminaclip: 'TruSeq3-PE.fa:2:30:10',
                leading: 3,
                trailing: 3,
                slidingwindow: '4:15',
                minlen: 36,
              },
            },
            '3': {
              annotation: 'Post-trim quality check',
              id: 3,
              tool_id: 'fastqc',
              tool_version: '0.12.1',
              name: 'FastQC After',
              tool_state: {
                threads: 2,
              },
            },
          },
        },
      },
    ];

    for (const example of examples) {
      try {
        await this.saveTemplate(example, 'system');
      } catch (error) {
        console.error(`[WorkflowRepository] Failed to seed example:`, error);
      }
    }

    console.log(`[WorkflowRepository] Seeded ${examples.length} example workflow templates`);
  }
}

// Singleton instance
export const workflowRepository = new WorkflowRepository();
