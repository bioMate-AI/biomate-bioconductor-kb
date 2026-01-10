/**
 * Utils Module Tests
 *
 * Tests for utility functions in the lib/utils module
 */

import { describe, it, expect } from 'vitest';
import { cn, getSimpleToolName } from './utils';

describe('cn (className merging)', () => {
  it('should merge class names correctly', () => {
    expect(cn('foo', 'bar')).toBe('foo bar');
  });

  it('should handle conditional classes', () => {
    expect(cn('foo', false && 'bar', 'baz')).toBe('foo baz');
    expect(cn('foo', true && 'bar', 'baz')).toBe('foo bar baz');
  });

  it('should handle undefined and null', () => {
    expect(cn('foo', undefined, null, 'bar')).toBe('foo bar');
  });

  it('should handle array inputs', () => {
    expect(cn(['foo', 'bar'])).toBe('foo bar');
  });

  it('should merge tailwind classes correctly', () => {
    // tailwind-merge should handle conflicting classes
    expect(cn('bg-red-500', 'bg-blue-500')).toBe('bg-blue-500');
    expect(cn('px-4', 'px-8')).toBe('px-8');
  });
});

describe('getSimpleToolName', () => {
  it('should extract simple name from tool_id', () => {
    expect(getSimpleToolName('toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.73+galaxy0'))
      .toBe('fastqc');
  });

  it('should handle simple tool names', () => {
    expect(getSimpleToolName('bowtie2')).toBe('bowtie2');
  });

  it('should handle galaxy tool format (returns as-is when no pattern match)', () => {
    // The function doesn't have special handling for 'galaxy/tools/' prefix
    // so it returns as-is when no capitalized words are found
    expect(getSimpleToolName('galaxy/tools/bwa_mem/bwa_mem')).toBe('galaxy/tools/bwa_mem/bwa_mem');
  });

  it('should return the input if no pattern matches', () => {
    expect(getSimpleToolName('simple_tool')).toBe('simple_tool');
  });
});
