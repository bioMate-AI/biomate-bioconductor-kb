/**
 * Schema Validation Tests
 *
 * Tests for Zod schema validation
 */

import { describe, it, expect } from 'vitest';
import {
  messageSchema,
  workflowStepSchema,
  userSettingsSchema,
  citationSchema,
} from './schema';

describe('Message Schema', () => {
  it('should validate a valid user message', () => {
    const message = {
      id: '123',
      role: 'user',
      content: 'Hello, AI!',
      timestamp: new Date().toISOString(),
    };

    const result = messageSchema.safeParse(message);
    expect(result.success).toBe(true);
  });

  it('should validate a valid assistant message', () => {
    const message = {
      id: '456',
      role: 'assistant',
      content: 'Hello! How can I help you?',
      timestamp: new Date().toISOString(),
    };

    const result = messageSchema.safeParse(message);
    expect(result.success).toBe(true);
  });

  it('should reject invalid role', () => {
    const message = {
      id: '789',
      role: 'admin', // Invalid role
      content: 'Test',
      timestamp: new Date().toISOString(),
    };

    const result = messageSchema.safeParse(message);
    expect(result.success).toBe(false);
  });

  it('should reject missing required fields', () => {
    const message = {
      id: '123',
      // Missing role, content, timestamp
    };

    const result = messageSchema.safeParse(message);
    expect(result.success).toBe(false);
  });
});

describe('WorkflowStep Schema', () => {
  it('should validate a valid workflow step', () => {
    const step = {
      id: 'step1',
      title: 'Quality Control',
      description: 'Run FastQC on input files',
      tool: 'fastqc',
      status: 'pending',
      complexity: 'simple',
    };

    const result = workflowStepSchema.safeParse(step);
    expect(result.success).toBe(true);
  });

  it('should validate with optional parameters', () => {
    const step = {
      id: 'step2',
      title: 'Alignment',
      description: 'Align reads to reference genome',
      tool: 'bowtie2',
      status: 'running',
      complexity: 'intermediate',
      parameters: { threads: 8, sensitivity: 'very-sensitive' },
      estimatedTime: '15 minutes',
    };

    const result = workflowStepSchema.safeParse(step);
    expect(result.success).toBe(true);
  });

  it('should reject invalid status', () => {
    const step = {
      id: 'step1',
      title: 'Test Step',
      description: 'Test',
      tool: 'test_tool',
      status: 'unknown', // Invalid status
      complexity: 'simple',
    };

    const result = workflowStepSchema.safeParse(step);
    expect(result.success).toBe(false);
  });
});

// Note: workflowConfigSchema is not exported from schema.ts
// Workflow configs are validated through workflowStepSchema for individual steps

describe('UserSettings Schema', () => {
  it('should validate user settings with required id', () => {
    const settings = {
      id: 'settings-123',
      theme: 'system',
    };

    const result = userSettingsSchema.safeParse(settings);
    expect(result.success).toBe(true);
  });

  it('should validate dark theme setting', () => {
    const settings = {
      id: 'settings-456',
      theme: 'dark',
      language: 'english',
      autoSaveWorkflows: true,
    };

    const result = userSettingsSchema.safeParse(settings);
    expect(result.success).toBe(true);
  });

  it('should reject missing required id field', () => {
    const settings = {
      theme: 'system',
    };

    const result = userSettingsSchema.safeParse(settings);
    expect(result.success).toBe(false);
  });
});

describe('Citation Schema', () => {
  it('should validate a valid citation', () => {
    const citation = {
      tool_id: 'fastqc',
      tool_name: 'FastQC',
      title: 'FastQC: A Quality Control tool for High Throughput Sequence Data',
      authors: ['Andrews S.'],
      year: 2010,
    };

    const result = citationSchema.safeParse(citation);
    expect(result.success).toBe(true);
  });

  it('should validate citation with DOI and PMID', () => {
    const citation = {
      tool_id: 'bwa',
      tool_name: 'BWA',
      doi: '10.1093/bioinformatics/btp324',
      pmid: '19451168',
      title: 'Fast and accurate short read alignment with Burrows-Wheeler transform',
      authors: ['Li H.', 'Durbin R.'],
      year: 2009,
      journal: 'Bioinformatics',
    };

    const result = citationSchema.safeParse(citation);
    expect(result.success).toBe(true);
  });
});
