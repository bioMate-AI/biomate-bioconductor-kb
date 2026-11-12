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
import { ChevronDown, ChevronRight, Terminal, FileText, CheckCircle2, XCircle, Loader2, BookOpen, Search, Copy, Check, Download } from 'lucide-react';
import { redactInternalRefs } from '@shared/chat-system-blocks';

/** 23 → "23 B", 2048 → "2.0 KB", 3e6 → "2.9 MB" (a small report read "0.0 KB"). */
export function formatBytes(n: number): string {
  if (!Number.isFinite(n) || n < 1024) return `${Math.max(0, Math.round(n || 0))} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / (1024 * 1024)).toFixed(1)} MB`;
}

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

/**
 * Status events share the SSE 'tool_event' channel for observability of
 * non-tool work (schema-grounded extraction stage progress, etc.). They are
 * not rendered as tool calls in the chat UI — the chat-interface handler
 * filters them out — but the type widens AgentToolEvent so the discriminant
 * check (event.type === 'status') type-narrows correctly.
 */
export interface StatusEvent {
  type: 'status';
  tool_use_id: string;
  name: string;
  message?: string;
  payload?: Record<string, unknown>;
}

export type AgentToolEvent = ToolCallEvent | ToolResultEvent | StatusEvent;

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
  const [copied, setCopied] = useState(false);
  const { call, result } = block;
  const name = block.name;

  const copyCode = async (text?: string) => {
    if (!text) return;
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch { /* clipboard unavailable (insecure context) — no-op */ }
  };

  // Extract code for run_code tool
  const code = call?.input?.code as string | undefined;
  const language = (call?.input?.language as string | undefined) ?? 'python';
  const codeLines = code?.split('\n') ?? [];
  const previewLines = codeLines.slice(0, 3);

  const isPending = !result;
  const isError = !!result?.error || (result?.output as any)?.exit_code > 0;
  const exitCode = (result?.output as any)?.exit_code as number | undefined;
  const stdout = (result?.output as any)?.stdout as string | undefined;
  const outputFiles = (result?.output as any)?.output_files as Array<{ name: string; size: number; preview: string; image_data_uri?: string; download_url?: string }> | undefined;
  // Generated figures (plots) — surfaced inline so they are visible without
  // expanding the tool card (founder feedback 2026-11-10: "where is the plot?").
  const imageFiles = outputFiles?.filter(f => f.image_data_uri) ?? [];
  // Every output file gets a download: the saved dataset when persisted; for a figure, its inline
  // bytes as a fallback (older messages predate persistence).
  const hrefFor = (f: { download_url?: string; image_data_uri?: string }) => f.download_url || f.image_data_uri;
  const otherFiles = outputFiles?.filter(f => !f.image_data_uri) ?? [];

  // For read_file / query_domain_knowledge: show a compact result
  const isCodeTool = name === 'run_code';

  return (
    <div
      data-testid={`tool-block-${name}-${block.tool_use_id}`}
      className="my-2 rounded-md border border-border bg-muted/40 overflow-hidden text-sm font-mono"
    >
      {/* ── Header ─────────────────────────────────────────────────────── */}
      <button
        className="w-full flex items-center gap-2 px-3 py-2 hover:bg-muted transition-colors text-left"
        onClick={() => setExpanded(e => !e)}
        aria-expanded={expanded}
      >
        {toolIcon(name)}
        <span className="font-semibold text-foreground text-xs">{toolLabel(name)}</span>
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
          <span className="text-muted-foreground text-xs">{(result.duration_ms / 1000).toFixed(1)}s</span>
        )}
        {expanded ? <ChevronDown size={12} className="text-muted-foreground" /> : <ChevronRight size={12} className="text-muted-foreground" />}
      </button>

      {/* ── Generated figures — always visible (not hidden behind expand) ── */}
      {imageFiles.length > 0 && (
        <div className="px-3 py-2 border-t border-border space-y-2">
          {imageFiles.map(f => (
            <figure key={f.name} className="m-0">
              <img
                src={f.image_data_uri}
                alt={f.name}
                data-testid="run-code-figure"
                className="max-w-full h-auto rounded border border-border bg-white"
              />
              <figcaption className="mt-1 flex items-center gap-2 text-xs text-muted-foreground">
                <span>{f.name}</span>
                {hrefFor(f) && (
                  <a href={hrefFor(f)} download={f.name} data-testid="run-code-file-download"
                    className="inline-flex items-center gap-1 rounded px-1.5 py-0.5 text-primary hover:bg-muted"
                    onClick={(e) => e.stopPropagation()}>
                    <Download size={12} /> Download
                  </a>
                )}
              </figcaption>
            </figure>
          ))}
        </div>
      )}

      {/* ── Generated files (reports, tables…) — always visible, downloadable ── */}
      {otherFiles.length > 0 && (
        <div className="px-3 py-2 border-t border-border flex flex-wrap gap-2" data-testid="run-code-files">
          {otherFiles.map(f => (
            hrefFor(f) ? (
              <a key={f.name} href={hrefFor(f)} download={f.name} data-testid="run-code-file-download"
                className="inline-flex items-center gap-1.5 rounded border border-border bg-background px-2 py-1 text-xs text-foreground hover:bg-muted"
                onClick={(e) => e.stopPropagation()}>
                <FileText size={12} className="text-primary" />
                <span className="font-semibold">{f.name}</span>
                <span className="text-muted-foreground">{formatBytes(f.size)}</span>
                <Download size={12} className="text-primary" />
              </a>
            ) : (
              <span key={f.name} className="inline-flex items-center gap-1.5 rounded border border-border px-2 py-1 text-xs text-muted-foreground">
                <FileText size={12} /> {f.name}
              </span>
            )
          ))}
        </div>
      )}

      {/* ── Collapsed preview (code or summary) ────────────────────────── */}
      {!expanded && isCodeTool && code && (
        <div className="px-3 pb-2 border-t border-border">
          <pre className="text-xs text-muted-foreground whitespace-pre-wrap overflow-hidden max-h-12">
            {redactInternalRefs(previewLines.join('\n'))}
            {codeLines.length > 3 && <span className="text-muted-foreground/70"> …+{codeLines.length - 3} lines</span>}
          </pre>
        </div>
      )}
      {!expanded && !isCodeTool && call?.input && (
        <div className="px-3 pb-2 border-t border-border text-xs text-muted-foreground">
          {JSON.stringify(call.input).slice(0, 120)}{JSON.stringify(call.input).length > 120 ? '…' : ''}
        </div>
      )}

      {/* ── Expanded detail ─────────────────────────────────────────────── */}
      {expanded && (
        <div className="border-t border-border">
          {/* Full code — conventional dark code surface (readable in both themes).
              Copy button + scrollable viewport (max-height + overflow) so long
              scripts are both copyable and scrollable inside the card. */}
          {isCodeTool && code && (
            <div className="bg-gray-900 text-gray-100">
              <div className="flex items-center justify-between px-3 py-1.5 border-b border-gray-700/60">
                <span className="text-[10px] uppercase tracking-wide text-gray-400">{language}</span>
                <button
                  type="button"
                  onClick={(e) => { e.stopPropagation(); copyCode(redactInternalRefs(code)); }}
                  className="inline-flex items-center gap-1 rounded px-1.5 py-0.5 text-[11px] text-gray-300 hover:text-white hover:bg-gray-700/60 transition-colors"
                  aria-label="Copy code"
                  data-testid="copy-code-button"
                >
                  {copied ? <Check size={12} className="text-green-400" /> : <Copy size={12} />}
                  {copied ? 'Copied' : 'Copy'}
                </button>
              </div>
              <pre className="text-xs whitespace-pre overflow-auto max-h-96 px-3 py-2">{redactInternalRefs(code)}</pre>
            </div>
          )}

          {/* Input for non-code tools */}
          {!isCodeTool && call?.input && (
            <div className="px-3 py-2 bg-background border-b border-border">
              <div className="text-xs text-muted-foreground mb-1">Input</div>
              <pre className="text-xs text-foreground whitespace-pre-wrap">
                {redactInternalRefs(JSON.stringify(call.input, null, 2))}
              </pre>
            </div>
          )}

          {/* Result */}
          {result && (
            <div className="px-3 py-2 bg-background space-y-2">
              {result.error && (
                <div className="text-xs text-red-600 bg-red-50 dark:bg-red-950/40 dark:text-red-400 px-2 py-1 rounded">{result.error}</div>
              )}
              {exitCode !== undefined && exitCode !== 0 && (
                <div className="text-xs text-red-600 dark:text-red-400">Exit code: {exitCode}</div>
              )}
              {stdout && (
                <div>
                  <div className="text-xs text-muted-foreground mb-0.5">stdout</div>
                  <pre className="text-xs text-foreground whitespace-pre-wrap max-h-48 overflow-y-auto bg-muted/50 px-2 py-1 rounded">
                    {truncate(redactInternalRefs(stdout), 2000)}
                  </pre>
                </div>
              )}
              {outputFiles && outputFiles.length > 0 && (
                <div>
                  <div className="text-xs text-muted-foreground mb-1">Output files</div>
                  <div className="space-y-1">
                    {outputFiles.map(f => (
                      <div key={f.name} className="flex items-start gap-2 bg-accent rounded px-2 py-1">
                        <FileText size={12} className="text-primary mt-0.5 flex-shrink-0" />
                        <div>
                          <div className="text-xs font-semibold text-accent-foreground">{f.name}</div>
                          <div className="text-xs text-primary">{formatBytes(f.size)}</div>
                          {/* Image files are rendered as figures above — don't repeat
                              their useless "(binary)" text preview here. */}
                          {f.preview && !f.image_data_uri && (
                            <pre className="text-xs text-muted-foreground whitespace-pre-wrap max-h-20 overflow-hidden">
                              {redactInternalRefs(f.preview)}
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
                  <div className="text-xs text-muted-foreground mb-0.5">Result</div>
                  <pre className="text-xs text-foreground whitespace-pre-wrap max-h-48 overflow-y-auto bg-muted/50 px-2 py-1 rounded">
                    {truncate(redactInternalRefs(typeof result.output === 'string' ? result.output : JSON.stringify(result.output, null, 2)), 2000)}
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
