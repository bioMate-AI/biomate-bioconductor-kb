import { qualityControl } from './quality-control';
import { alignment } from './alignment';
import { quantification } from './quantification';
import { differential } from './differential';
import { variants } from './variants';
import { utils } from './utils';
import type { DatasetConfig } from '@shared/schema';

// Function execution result interface
export interface FunctionResult {
  success: boolean;
  outputs?: DatasetConfig[];
  logs: string[];
  error?: string;
  duration?: number;
  metrics?: Record<string, any>;
}

// Function parameter interface
export interface FunctionParams {
  inputs: DatasetConfig[];
  parameters: Record<string, any>;
  outputPath?: string;
}

// Function registry type
export type BioinformaticsFunction = (params: FunctionParams) => Promise<FunctionResult>;

// Central function registry
export const functionRegistry: Record<string, BioinformaticsFunction> = {
  // Quality Control Functions
  'FastQC': qualityControl.fastqc,
  'Trimmomatic': qualityControl.trimmomatic,
  'MultiQC': qualityControl.multiqc,
  
  // Alignment Functions
  'HISAT2': alignment.hisat2,
  'BWA-MEM': alignment.bwamem,
  'STAR': alignment.star,
  
  // Quantification Functions
  'featureCounts': quantification.featurecounts,
  'HTSeq': quantification.htseq,
  'RSEM': quantification.rsem,
  
  // Differential Expression
  'DESeq2': differential.deseq2,
  'edgeR': differential.edger,
  'limma': differential.limma,
  
  // Variant Calling
  'GATK': variants.gatk,
  'FreeBayes': variants.freebayes,
  'VarScan': variants.varscan,
  
  // Utility Functions
  'SAMtools': utils.samtools,
  'BCFtools': utils.bcftools,
  'Picard': utils.picard
};

// Execute a bioinformatics function
export async function executeFunction(
  tool: string, 
  params: FunctionParams
): Promise<FunctionResult> {
  const startTime = Date.now();
  
  try {
    const func = functionRegistry[tool];
    if (!func) {
      return {
        success: false,
        error: `Function '${tool}' not found in registry`,
        logs: [`Error: Unknown function '${tool}'`],
        duration: Date.now() - startTime
      };
    }
    
    console.log(`Executing ${tool} with parameters:`, params.parameters);
    const result = await func(params);
    
    return {
      ...result,
      duration: Date.now() - startTime
    };
    
  } catch (error) {
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error',
      logs: [`Error executing ${tool}: ${error}`],
      duration: Date.now() - startTime
    };
  }
}

// Get available functions and their metadata
export function getAvailableFunctions() {
  return Object.keys(functionRegistry).map(tool => ({
    name: tool,
    category: getFunctionCategory(tool),
    complexity: getFunctionComplexity(tool),
    description: getFunctionDescription(tool)
  }));
}

function getFunctionCategory(tool: string): string {
  if (['FastQC', 'Trimmomatic', 'MultiQC'].includes(tool)) return 'Quality Control';
  if (['HISAT2', 'BWA-MEM', 'STAR'].includes(tool)) return 'Alignment';
  if (['featureCounts', 'HTSeq', 'RSEM'].includes(tool)) return 'Quantification';
  if (['DESeq2', 'edgeR', 'limma'].includes(tool)) return 'Differential Expression';
  if (['GATK', 'FreeBayes', 'VarScan'].includes(tool)) return 'Variant Calling';
  return 'Utilities';
}

function getFunctionComplexity(tool: string): 'simple' | 'intermediate' | 'complex' {
  const simple = ['FastQC', 'MultiQC', 'SAMtools', 'BCFtools'];
  const complex = ['DESeq2', 'GATK', 'STAR', 'RSEM'];
  
  if (simple.includes(tool)) return 'simple';
  if (complex.includes(tool)) return 'complex';
  return 'intermediate';
}

function getFunctionDescription(tool: string): string {
  const descriptions: Record<string, string> = {
    'FastQC': 'Quality assessment of high throughput sequence data',
    'Trimmomatic': 'Flexible read trimming tool for Illumina sequencing data',
    'MultiQC': 'Aggregate results from bioinformatics analyses',
    'HISAT2': 'Graph-based alignment of next generation sequencing reads',
    'BWA-MEM': 'Burrows-Wheeler Aligner for short-read alignment',
    'STAR': 'Ultrafast universal RNA-seq aligner',
    'featureCounts': 'Efficient tool for counting reads to genomic features',
    'HTSeq': 'Framework for processing data from high-throughput sequencing',
    'RSEM': 'Accurate quantification of gene and isoform expression',
    'DESeq2': 'Differential gene expression analysis based on negative binomial distribution',
    'edgeR': 'Empirical analysis of digital gene expression data',
    'limma': 'Linear models for microarray and RNA-seq data',
    'GATK': 'Genome Analysis Toolkit for variant discovery',
    'FreeBayes': 'Bayesian haplotype-based genetic polymorphism discovery',
    'VarScan': 'Variant detection in massively parallel sequencing data'
  };
  
  return descriptions[tool] || `${tool} bioinformatics function`;
}