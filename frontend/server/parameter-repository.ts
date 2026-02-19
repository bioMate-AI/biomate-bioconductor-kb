/**
 * Use Case-Based Parameter Repository
 *
 * Stores and retrieves validated parameter templates for different analysis scenarios.
 * Enables users to save proven parameter configurations and reuse them across workflows.
 */

import fs from 'fs/promises';
import path from 'path';
import { v4 as uuidv4 } from 'uuid';
import type {
  ParameterTemplate,
  ParameterTemplateSearchRequest,
  ParameterTemplateSearchResponse,
  SaveParameterTemplateRequest,
  UseCaseMetadata,
} from '../shared/galaxy-types';

export class ParameterRepository {
  private repositoryPath: string;
  private templates: Map<string, ParameterTemplate> = new Map();

  constructor(repositoryPath: string = './data/parameter-templates') {
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
          const template: ParameterTemplate = JSON.parse(content);
          this.templates.set(template.id, template);
        }
      }

      console.log(`[ParameterRepository] Loaded ${this.templates.size} parameter templates`);
    } catch (error) {
      console.error('[ParameterRepository] Failed to initialize:', error);
      throw error;
    }
  }

  /**
   * Save a new parameter template
   */
  async saveTemplate(request: SaveParameterTemplateRequest, userId: string = 'system'): Promise<ParameterTemplate> {
    const now = new Date().toISOString();

    const useCase: UseCaseMetadata = {
      id: uuidv4(),
      name: request.use_case_name,
      description: request.use_case_description,
      category: request.use_case_category as any,
      tags: request.tags || [],
      sample_type: request.sample_type,
      analysis_type: request.analysis_type,
      difficulty: 'intermediate', // Default, can be updated later
      created_by: userId,
      created_at: now,
      updated_at: now,
      usage_count: 0,
      success_rate: 0,
    };

    const template: ParameterTemplate = {
      id: uuidv4(),
      tool_id: request.tool_id,
      tool_version: request.tool_version,
      tool_name: request.tool_name,
      use_case: useCase,
      parameters: request.parameters,
      rationale: request.rationale,
      references: request.references,
      notes: request.notes,
      validated: false,
    };

    // Save to memory
    this.templates.set(template.id, template);

    // Persist to disk
    const filePath = path.join(this.repositoryPath, `${template.id}.json`);
    await fs.writeFile(filePath, JSON.stringify(template, null, 2));

    console.log(`[ParameterRepository] Saved template: ${template.id} for ${template.tool_id}`);
    return template;
  }

  /**
   * Search for parameter templates
   */
  async searchTemplates(request: ParameterTemplateSearchRequest): Promise<ParameterTemplateSearchResponse> {
    let results = Array.from(this.templates.values());

    // Filter by tool_id
    if (request.tool_id) {
      results = results.filter(t => t.tool_id === request.tool_id);
    }

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
        t.use_case.sample_type?.toLowerCase().includes(request.sample_type!.toLowerCase())
      );
    }

    // Filter by tags
    if (request.tags && request.tags.length > 0) {
      results = results.filter(t =>
        request.tags!.some(tag => t.use_case.tags.includes(tag))
      );
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
   * Get a specific parameter template by ID
   */
  async getTemplate(templateId: string): Promise<ParameterTemplate | null> {
    return this.templates.get(templateId) || null;
  }

  /**
   * Update template usage statistics
   */
  async recordUsage(templateId: string, success: boolean): Promise<void> {
    const template = this.templates.get(templateId);
    if (!template) {
      throw new Error(`Template not found: ${templateId}`);
    }

    template.use_case.usage_count = (template.use_case.usage_count || 0) + 1;
    const successCount = (template.use_case.success_rate || 0) * ((template.use_case.usage_count || 1) - 1);
    template.use_case.success_rate = (successCount + (success ? 1 : 0)) / template.use_case.usage_count;
    template.use_case.updated_at = new Date().toISOString();

    // Persist changes
    const filePath = path.join(this.repositoryPath, `${template.id}.json`);
    await fs.writeFile(filePath, JSON.stringify(template, null, 2));
  }

  /**
   * Mark template as validated
   */
  async validateTemplate(
    templateId: string,
    testDatasets: string[],
    success: boolean,
    metrics?: Record<string, number>
  ): Promise<void> {
    const template = this.templates.get(templateId);
    if (!template) {
      throw new Error(`Template not found: ${templateId}`);
    }

    template.validated = success;
    template.validation_date = new Date().toISOString();
    template.validation_results = {
      test_datasets: testDatasets,
      success,
      metrics,
    };

    // Persist changes
    const filePath = path.join(this.repositoryPath, `${template.id}.json`);
    await fs.writeFile(filePath, JSON.stringify(template, null, 2));

    console.log(`[ParameterRepository] Validated template ${templateId}: ${success}`);
  }

  /**
   * Delete a parameter template
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

    console.log(`[ParameterRepository] Deleted template: ${templateId}`);
  }

  /**
   * Get all templates for a specific tool
   */
  async getTemplatesForTool(toolId: string): Promise<ParameterTemplate[]> {
    return Array.from(this.templates.values()).filter(t => t.tool_id === toolId);
  }

  /**
   * Get popular templates (by usage)
   */
  async getPopularTemplates(limit: number = 10): Promise<ParameterTemplate[]> {
    return Array.from(this.templates.values())
      .sort((a, b) => (b.use_case.usage_count || 0) - (a.use_case.usage_count || 0))
      .slice(0, limit);
  }

  /**
   * Get validated templates only
   */
  async getValidatedTemplates(): Promise<ParameterTemplate[]> {
    return Array.from(this.templates.values()).filter(t => t.validated);
  }

  /**
   * Seed repository with example templates (for initial setup)
   */
  async seedExamples(): Promise<void> {
    const examples: SaveParameterTemplateRequest[] = [
      {
        tool_id: 'fastqc',
        tool_version: '0.12.1',
        tool_name: 'FastQC Quality Control',
        use_case_name: 'RNA-seq Quality Control - Human',
        use_case_description: 'Standard QC parameters for human RNA-seq data',
        use_case_category: 'quality_control',
        analysis_type: 'rna_seq',
        sample_type: 'human',
        tags: ['qc', 'rna-seq', 'human', 'illumina'],
        parameters: {
          threads: 4,
          nogroup: false,
          kmers: 7,
          min_length: 0,
        },
        rationale: 'Default parameters optimized for Illumina RNA-seq reads. Threads set to 4 for balanced performance.',
        references: ['https://www.bioinformatics.babraham.ac.uk/projects/fastqc/'],
      },
      {
        tool_id: 'macs2',
        tool_version: '2.2.7.1',
        tool_name: 'MACS2 Peak Calling',
        use_case_name: 'ChIP-seq Narrow Peaks - Human',
        use_case_description: 'Parameters for calling narrow peaks in human ChIP-seq data',
        use_case_category: 'analysis',
        analysis_type: 'chip_seq_peak_calling',
        sample_type: 'human',
        tags: ['chip-seq', 'peak-calling', 'human', 'narrow-peaks'],
        parameters: {
          gsize: 'hs',
          qvalue: 0.05,
          pvalue: null,
          mfold_lower: 5,
          mfold_upper: 50,
          broad: false,
          nomodel: false,
          extsize: 200,
        },
        rationale: 'Standard narrow peak calling for transcription factors. Q-value 0.05 for good specificity.',
        references: [
          'Zhang et al. (2008) Model-based Analysis of ChIP-Seq (MACS)',
          'https://github.com/macs3-project/MACS',
        ],
      },
      {
        tool_id: 'xcms',
        tool_version: '3.16.1',
        tool_name: 'XCMS Peak Detection',
        use_case_name: 'LC-MS Metabolomics - Positive Mode',
        use_case_description: 'Peak detection for LC-MS metabolomics in positive ionization mode',
        use_case_category: 'metabolomics',
        analysis_type: 'lc_ms_peak_detection',
        sample_type: 'plasma',
        tags: ['metabolomics', 'lc-ms', 'positive-mode', 'plasma'],
        parameters: {
          method: 'centWave',
          ppm: 15,
          peakwidth_min: 5,
          peakwidth_max: 20,
          snthresh: 10,
          prefilter_k: 3,
          prefilter_i: 100,
          noise: 0,
        },
        rationale: 'CentWave method with 15 ppm tolerance for high-resolution MS. Peak width 5-20s typical for UPLC.',
        references: [
          'Smith et al. (2006) XCMS: Processing mass spectrometry data',
          'https://bioconductor.org/packages/xcms/',
        ],
      },
    ];

    for (const example of examples) {
      try {
        await this.saveTemplate(example, 'system');
      } catch (error) {
        console.error(`[ParameterRepository] Failed to seed example:`, error);
      }
    }

    console.log(`[ParameterRepository] Seeded ${examples.length} example templates`);
  }
}

// Singleton instance
export const parameterRepository = new ParameterRepository();
