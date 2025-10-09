import OpenAI from 'openai';

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

export interface Dataset {
  dataset_id: string;
  galaxy_dataset_id?: string;
  name: string;
  description?: string;
  file_type: string;
  file_size: number;
}

export interface WorkflowStep {
  id: string;
  title: string;
  description: string;
  tool: string;
  parameters: Record<string, any>;
}

export interface DatasetValidationResult {
  valid: boolean;
  issues: string[];
  warnings: string[];
  suggestions: string[];
  mappings: Array<{
    dataset_id: string;
    step_id: string;
    input_name: string;
    confidence: 'high' | 'medium' | 'low';
    reasoning: string;
  }>;
}

/**
 * AI-powered dataset validator that analyzes uploaded datasets
 * against workflow requirements and suggests appropriate mappings
 */
export class DatasetValidator {
  /**
   * Validate datasets against workflow requirements
   */
  async validateDatasets(
    datasets: Dataset[],
    workflowSteps: WorkflowStep[],
    workflowName: string
  ): Promise<DatasetValidationResult> {
    // Get first step (where datasets will be assigned)
    const firstStep = workflowSteps[0];

    if (!firstStep) {
      return {
        valid: false,
        issues: ['Workflow has no steps'],
        warnings: [],
        suggestions: [],
        mappings: []
      };
    }

    // Build analysis prompt
    const prompt = this.buildValidationPrompt(datasets, firstStep, workflowName);

    try {
      const response = await openai.chat.completions.create({
        model: 'gpt-4',
        messages: [
          {
            role: 'system',
            content: `You are an expert bioinformatics workflow analyst. Your task is to validate if uploaded datasets are appropriate for a workflow's first step. Analyze dataset characteristics (name, description, file type) against the tool requirements and provide validation results in JSON format.`
          },
          {
            role: 'user',
            content: prompt
          }
        ],
        response_format: { type: 'json_object' },
        temperature: 0.3,
      });

      const result = JSON.parse(response.choices[0].message.content || '{}');

      return {
        valid: result.valid || false,
        issues: result.issues || [],
        warnings: result.warnings || [],
        suggestions: result.suggestions || [],
        mappings: result.mappings || datasets.map(d => ({
          dataset_id: d.dataset_id,
          step_id: firstStep.id,
          input_name: this.inferInputName(firstStep.tool),
          confidence: 'medium' as const,
          reasoning: 'Auto-assigned to first step'
        }))
      };
    } catch (error: any) {
      console.error('[DatasetValidator] Validation failed:', error);

      // Fallback: auto-assign to first step without validation
      return {
        valid: true,
        issues: [],
        warnings: [`Could not validate datasets: ${error.message}. Proceeding with auto-assignment.`],
        suggestions: [],
        mappings: datasets.map(d => ({
          dataset_id: d.dataset_id,
          step_id: firstStep.id,
          input_name: this.inferInputName(firstStep.tool),
          confidence: 'low' as const,
          reasoning: 'Validation service unavailable, auto-assigned to first step'
        }))
      };
    }
  }

  /**
   * Build validation prompt for LLM
   */
  private buildValidationPrompt(
    datasets: Dataset[],
    firstStep: WorkflowStep,
    workflowName: string
  ): string {
    return `
Workflow: ${workflowName}
First Step: ${firstStep.title} (${firstStep.tool})
Step Description: ${firstStep.description}
Step Parameters: ${JSON.stringify(firstStep.parameters, null, 2)}

Uploaded Datasets:
${datasets.map(d => `
- File: ${d.name}
  Type: ${d.file_type}
  Size: ${(d.file_size / 1024 / 1024).toFixed(2)} MB
  ${d.description ? `Description: ${d.description}` : '(No description provided)'}
`).join('\n')}

Please analyze if datasets are provided for the workflow's first step. Return a JSON object with:
{
  "valid": boolean,  // true if datasets are uploaded
  "issues": string[],  // Critical problems (e.g., "No datasets uploaded", "Missing required input")
  "warnings": string[],  // Non-critical concerns (e.g., "Description not provided for better context")
  "suggestions": string[],  // Helpful tips (e.g., "Consider adding sample metadata", "Paired-end data may improve results")
  "mappings": [  // How each dataset should map to workflow inputs
    {
      "dataset_id": "string",
      "step_id": "${firstStep.id}",
      "input_name": "string",  // e.g., "input_file", "data_file", "reads"
      "confidence": "high" | "medium" | "low",
      "reasoning": "string"  // Why this mapping makes sense
    }
  ]
}

Common input names by tool type:
- FastQC, Trimmomatic: "input_file", "reads"
- HISAT2, BWA: "input_file", "reads"
- MACS2: "treatment_file", "control_file"
- XCMS: "input_file", "data_file"
- featureCounts, HTSeq: "input_file", "alignment_file"

IMPORTANT RULES:
1. **DO NOT validate file formats** - Tools will validate formats themselves and provide feedback during execution
2. **Only check if datasets are uploaded** - Don't assume what format is "correct"
3. **Accept CSV, FASTQ, BAM, mzML, mzXML, TXT, etc.** - All formats may be valid depending on tool capabilities
4. **Focus on missing inputs** - e.g., "No datasets uploaded", "Typically need 2+ files for paired analysis"
5. **Be permissive, not restrictive** - Let the workflow tools validate and report issues through chat

Examples of ACCEPTABLE datasets:
- CSV for LC-MS workflow (could be pre-processed peak lists)
- TXT for any workflow (could be custom format)
- Any format if user provided description explaining it
`;
  }

  /**
   * Infer input name from tool name
   */
  private inferInputName(toolName: string): string {
    const tool = toolName.toLowerCase();

    if (tool.includes('fastqc') || tool.includes('trimmomatic') || tool.includes('cutadapt')) {
      return 'fastq_input';
    }
    if (tool.includes('hisat') || tool.includes('bwa') || tool.includes('bowtie')) {
      return 'fastq_reads';
    }
    if (tool.includes('macs')) {
      return 'treatment_bam';
    }
    if (tool.includes('xcms') || tool.includes('msdial')) {
      return 'mzml_files';
    }
    if (tool.includes('featurecounts') || tool.includes('htseq')) {
      return 'bam_alignment';
    }

    return 'input_file';
  }

  /**
   * Quick validation: just check if any datasets uploaded
   */
  async quickValidate(datasets: Dataset[]): Promise<{ valid: boolean; message?: string }> {
    if (datasets.length === 0) {
      return {
        valid: false,
        message: 'No datasets uploaded. Please upload input files for your workflow.'
      };
    }

    return { valid: true };
  }
}

// Export singleton
export const datasetValidator = new DatasetValidator();
