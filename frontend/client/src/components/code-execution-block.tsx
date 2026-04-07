/**
 * CodeExecutionBlock — renders an agent tool call inline in a chat message.
 *
 * Displays:
 *  - tool_call events: language badge + collapsed/expandable code + "Running…" state
 *  - tool_result events: duration, stdout (truncated), output files, error state
 *
 * Matches the Claude Code mental model: short default view, expandable for full detail.
 */

import React, { useState } from 'react';
import { ChevronDown, ChevronRight, Terminal, FileText, CheckCircle2, XCircle, Loader2, BookOpen, Search } from 'lucide-react';

// ─── Types ────────────────────────────────────────────────────────────────────

export interface ToolCallEvent {
  type: 'tool_call';
  tool_use_id: string;
  name: string;
  input?: Record<string, unknown>;
}

export interface ToolResultEvent {
  type: 'tool_result';
  tool_use_id: string;
  name: string;
  output?: unknown;
  error?: string;
  duration_ms?: number;
}

export type AgentToolEvent = ToolCallEvent | ToolResultEvent;

// A merged call+result pair, keyed by tool_use_id
export interface ToolBlock {
  tool_use_id: string;
  name: string;
  call?: ToolCallEvent;
  result?: ToolResultEvent;
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

const LANGUAGE_COLORS: Record<string, string> = {
  python: 'bg-blue-100 text-blue-800',
  r: 'bg-green-100 text-green-800',
  bash: 'bg-gray-100 text-gray-700',
};

function truncate(s: string, max: number): string {
  if (s.length <= max) return s;
  return s.slice(0, max) + `\n…(${s.length - max} chars truncated)`;
}

function toolIcon(name: string) {
  if (name === 'run_code') return <Terminal size={14} className="text-blue-600" />;
  if (name === 'read_file') return <FileText size={14} className="text-indigo-600" />;
  if (name === 'query_domain_knowledge') return <BookOpen size={14} className="text-emerald-600" />;
  return <Search size={14} className="text-gray-500" />;
}

function toolLabel(name: string): string {
  if (name === 'run_code') return 'Run Code';
  if (name === 'read_file') return 'Read File';
  if (name === 'query_domain_knowledge') return 'Domain Knowledge';
  return name;
}

// ─── CodeExecutionBlock ───────────────────────────────────────────────────────

interface Props {
  block: ToolBlock;
}

export function CodeExecutionBlock({ block }: Props) {
  const [expanded, setExpanded] = useState(false);
  const { call, result } = block;
  const name = block.name;

  // Extract code for run_code tool
  const code = call?.input?.code as string | undefined;
  const language = (call?.input?.language as string | undefined) ?? 'python';
  const codeLines = code?.split('\n') ?? [];
  const previewLines = codeLines.slice(0, 3);

  const isPending = !result;
  const isError = !!result?.error || (result?.output as any)?.exit_code > 0;
  const exitCode = (result?.output as any)?.exit_code as number | undefined;
  const stdout = (result?.output as any)?.stdout as string | undefined;
  const outputFiles = (result?.output as any)?.output_files as Array<{ name: string; size: number; preview: string }> | undefined;

  // For read_file / query_domain_knowledge: show a compact result
  const isCodeTool = name === 'run_code';

  return (
    <div
      data-testid={`tool-block-${name}-${block.tool_use_id}`}
      className="my-2 rounded-md border border-gray-200 bg-gray-50 overflow-hidden text-sm font-mono"
    >
      {/* ── Header ─────────────────────────────────────────────────────── */}
      <button
        className="w-full flex items-center gap-2 px-3 py-2 hover:bg-gray-100 transition-colors text-left"
        onClick={() => setExpanded(e => !e)}
        aria-expanded={expanded}
      >
        {toolIcon(name)}
        <span className="font-semibold text-gray-700 text-xs">{toolLabel(name)}</span>
        {isCodeTool && language && (
          <span className={`px-1.5 py-0.5 rounded text-xs font-mono ${LANGUAGE_COLORS[language] ?? 'bg-gray-100 text-gray-700'}`}>
            {language}
          </span>
        )}
        <span className="flex-1" />
        {isPending && <Loader2 size={12} className="animate-spin text-gray-400" />}
        {!isPending && !isError && <CheckCircle2 size={12} className="text-green-500" />}
        {!isPending && isError && <XCircle size={12} className="text-red-500" />}
        {result?.duration_ms && (
          <span className="text-gray-400 text-xs">{(result.duration_ms / 1000).toFixed(1)}s</span>
        )}
        {expanded ? <ChevronDown size={12} className="text-gray-400" /> : <ChevronRight size={12} className="text-gray-400" />}
      </button>

      {/* ── Collapsed preview (code or summary) ────────────────────────── */}
      {!expanded && isCodeTool && code && (
        <div className="px-3 pb-2 border-t border-gray-100">
          <pre className="text-xs text-gray-600 whitespace-pre-wrap overflow-hidden max-h-12">
            {previewLines.join('\n')}
            {codeLines.length > 3 && <span className="text-gray-400"> …+{codeLines.length - 3} lines</span>}
          </pre>
        </div>
      )}
      {!expanded && !isCodeTool && call?.input && (
        <div className="px-3 pb-2 border-t border-gray-100 text-xs text-gray-500">
          {JSON.stringify(call.input).slice(0, 120)}{JSON.stringify(call.input).length > 120 ? '…' : ''}
        </div>
      )}

      {/* ── Expanded detail ─────────────────────────────────────────────── */}
      {expanded && (
        <div className="border-t border-gray-100">
          {/* Full code */}
          {isCodeTool && code && (
            <div className="bg-gray-900 text-gray-100 px-3 py-2">
              <pre className="text-xs whitespace-pre-wrap overflow-x-auto">{code}</pre>
            </div>
          )}

          {/* Input for non-code tools */}
          {!isCodeTool && call?.input && (
            <div className="px-3 py-2 bg-white border-b border-gray-100">
              <div className="text-xs text-gray-500 mb-1">Input</div>
              <pre className="text-xs text-gray-700 whitespace-pre-wrap">
                {JSON.stringify(call.input, null, 2)}
              </pre>
            </div>
          )}

          {/* Result */}
          {result && (
            <div className="px-3 py-2 bg-white space-y-2">
              {result.error && (
                <div className="text-xs text-red-600 bg-red-50 px-2 py-1 rounded">{result.error}</div>
              )}
              {exitCode !== undefined && exitCode !== 0 && (
                <div className="text-xs text-red-600">Exit code: {exitCode}</div>
              )}
              {stdout && (
                <div>
                  <div className="text-xs text-gray-400 mb-0.5">stdout</div>
                  <pre className="text-xs text-gray-700 whitespace-pre-wrap max-h-48 overflow-y-auto bg-gray-50 px-2 py-1 rounded">
                    {truncate(stdout, 2000)}
                  </pre>
                </div>
              )}
              {outputFiles && outputFiles.length > 0 && (
                <div>
                  <div className="text-xs text-gray-400 mb-1">Output files</div>
                  <div className="space-y-1">
                    {outputFiles.map(f => (
                      <div key={f.name} className="flex items-start gap-2 bg-blue-50 rounded px-2 py-1">
                        <FileText size={12} className="text-blue-500 mt-0.5 flex-shrink-0" />
                        <div>
                          <div className="text-xs font-semibold text-blue-700">{f.name}</div>
                          <div className="text-xs text-blue-500">{(f.size / 1024).toFixed(1)} KB</div>
                          {f.preview && (
                            <pre className="text-xs text-gray-500 whitespace-pre-wrap max-h-20 overflow-hidden">
                              {f.preview}
                            </pre>
                          )}
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )}
              {/* Non-code tool output */}
              {!isCodeTool && result.output != null && !result.error && (
                <div>
                  <div className="text-xs text-gray-400 mb-0.5">Result</div>
                  <pre className="text-xs text-gray-700 whitespace-pre-wrap max-h-48 overflow-y-auto bg-gray-50 px-2 py-1 rounded">
                    {truncate(typeof result.output === 'string' ? result.output : JSON.stringify(result.output, null, 2), 2000)}
                  </pre>
                </div>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
