/**
 * BioMate Agentic Orchestrator
 *
 * Replaces the hardcoded intent→routing-table→agents pipeline with
 * Claude-as-orchestrator: Claude is given all backend capabilities as tool
 * schemas and decides what to call, in what order, with no regex overrides
 * and no enumerated ActionCategories lookup.
 *
 * Architecture:
 *   user message
 *     → Claude (orchestrator, claude-sonnet-4-6, tool_use loop)
 *       → search_workflows(intent)           → BioMate workflow library (2,455 workflows)
 *       → search_literature(query)           → ResearchAgent (PubMed, S2, GWAS, OMIM...)
 *       → query_database(query, dbs)         → biological DB APIs
 *       → run_code(language, code)           → Galaxy /api/code/run
 *       → synthesize_papers(paths, question) → PaperQA2 (multi-paper RAG)
 *       → get_benchmark_evidence(tools, task)→ BenchmarkKnowledgeDB
 *     → Claude synthesises all tool results into one response
 *
 * Activate with:  ORCHESTRATOR_MODE=agentic
 * Falls back to the legacy routing when disabled or on error.
 *
 * Max loop depth: 8 turns (prevents infinite tool-call loops).
 * Rate limit: uses _withAnthropicRetry from GalaxyAssistant (Retry-After aware).
 */

import Anthropic from '@anthropic-ai/sdk';
import type { ChatContext } from './galaxy-assistant';

// ---------------------------------------------------------------------------
// Tool schemas — each maps to one backend capability
// ---------------------------------------------------------------------------

export const ORCHESTRATOR_TOOL_SCHEMAS: Anthropic.Tool[] = [
  {
    name: 'search_workflows',
    description:
      'Search BioMate\'s library of 2,455 bioinformatics workflows and suggest the best match ' +
      'for the user\'s analysis intent. Returns a workflow card the user can run. ' +
      'Use for any computational biology task: RNA-seq, genomics, proteomics, single-cell, ' +
      'ADMET, PBPK, drug docking, cryo-EM, metagenomics, etc. ' +
      'Do NOT use for literature questions or general biology knowledge — use search_literature instead.',
    input_schema: {
      type: 'object' as const,
      properties: {
        intent: {
          type: 'string',
          description:
            'One-sentence description of what the user wants to compute or analyse. ' +
            'Include data type (e.g. FASTQ, BAM, SMILES, PDB), organism, and goal.',
        },
        params: {
          type: 'object',
          description:
            'Key parameters already provided by the user (e.g. {"organism": "human", ' +
            '"genome": "GRCh38", "strandedness": "reverse"}). Omit unknowns — do not guess.',
          additionalProperties: true,
        },
        preferred_domains: {
          type: 'array',
          items: { type: 'string' },
          description:
            'Biological domains to prefer when ranking workflows, e.g. ["transcriptomics", ' +
            '"drug_discovery"]. Leave empty to let the system infer.',
        },
      },
      required: ['intent'],
    },
  },

  {
    name: 'search_literature',
    description:
      'Search scientific literature and biological databases for evidence-backed answers. ' +
      'Covers PubMed, Semantic Scholar, GWAS Catalog, Open Targets, OMIM, ClinVar, Ensembl, ' +
      'mygene.info, and the BioMate benchmark knowledge base. ' +
      'Use for: research questions, mechanism questions, gene-disease associations, ' +
      'tool comparisons, best practices, method selection, protocol guidance.',
    input_schema: {
      type: 'object' as const,
      properties: {
        query: {
          type: 'string',
          description: 'The research question or topic to search for.',
        },
        include_benchmark_evidence: {
          type: 'boolean',
          description: 'If true, also query BioMate\'s tool benchmark knowledge base for performance comparisons.',
        },
        databases: {
          type: 'array',
          items: { type: 'string' },
          description:
            'Specific databases to query, e.g. ["pubmed", "gwas_catalog", "omim", "open_targets"]. ' +
            'Leave empty to search all available.',
        },
      },
      required: ['query'],
    },
  },

  {
    name: 'run_code',
    description:
      'Execute Python or R code directly in BioMate\'s secure sandbox. ' +
      'Use for: data parsing, statistical calculations, format conversions, quick analyses ' +
      'that do not need a full Nextflow pipeline. ' +
      'Uploaded files are accessible via their dataset_id. ' +
      'Do NOT use for long-running ML training or genome assembly — use search_workflows instead.',
    input_schema: {
      type: 'object' as const,
      properties: {
        language: {
          type: 'string',
          enum: ['python', 'r', 'bash'],
          description: 'Programming language to execute.',
        },
        code: {
          type: 'string',
          description: 'The code to execute. Must be self-contained and complete.',
        },
        dataset_ids: {
          type: 'array',
          items: { type: 'string' },
          description: 'IDs of uploaded datasets to make available to the code.',
        },
      },
      required: ['language', 'code'],
    },
  },

  {
    name: 'synthesize_papers',
    description:
      'Use PaperQA2 (Future House) to synthesize answers from multiple uploaded research papers. ' +
      'Chunks all PDFs, embeds them, retrieves relevant passages from across ALL papers, ' +
      'and synthesizes ONE answer with inline citations. ' +
      'Use when the user has uploaded 2+ papers and asks a question that requires ' +
      'cross-paper synthesis, comparison, or evidence aggregation. ' +
      'For a single paper, prefer injecting the text directly.',
    input_schema: {
      type: 'object' as const,
      properties: {
        question: {
          type: 'string',
          description: 'The question to answer from the papers.',
        },
        dataset_ids: {
          type: 'array',
          items: { type: 'string' },
          description: 'dataset_ids of the uploaded PDF files to search across.',
        },
      },
      required: ['question', 'dataset_ids'],
    },
  },

  {
    name: 'get_benchmark_evidence',
    description:
      'Retrieve performance benchmarks for bioinformatics tools from BioMate\'s benchmark database. ' +
      'Returns precision/recall/F1 scores, ranking tables, and evidence summaries. ' +
      'Use when the user asks to compare tools or wants to know which tool performs best for a task.',
    input_schema: {
      type: 'object' as const,
      properties: {
        task: {
          type: 'string',
          description: 'The bioinformatics task to benchmark, e.g. "RNA-seq differential expression", "variant calling".',
        },
        tool_names: {
          type: 'array',
          items: { type: 'string' },
          description: 'Specific tools to compare. Leave empty to retrieve the full ranking table for the task.',
        },
      },
      required: ['task'],
    },
  },
];

// ---------------------------------------------------------------------------
// Executor — maps tool names to actual backend calls
// ---------------------------------------------------------------------------

export interface OrchestratorExecutorDeps {
  galaxyUrl: string;
  galaxyAPI: any;  // GalaxyAPIProxy — typed loosely to avoid circular import
  getUploadedFile: (id: string) => { filePath: string; name: string } | undefined;
  withRetry: <T>(fn: () => Promise<T>, label: string) => Promise<T>;
}

export async function executeOrchestratorTool(
  name: string,
  input: Record<string, any>,
  context: ChatContext,
  deps: OrchestratorExecutorDeps,
): Promise<unknown> {
  const { galaxyUrl, galaxyAPI, getUploadedFile, withRetry } = deps;

  switch (name) {
    // -----------------------------------------------------------------------
    case 'search_workflows': {
      const resp = await fetch(`${galaxyUrl}/api/ai_assistant/generate_workflow`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          request_text: input.intent,
          inline_parameters: input.params ?? {},
          preferred_domains: input.preferred_domains ?? [],
        }),
        signal: AbortSignal.timeout(90_000),
      });
      if (!resp.ok) throw new Error(`search_workflows HTTP ${resp.status}`);
      const data = await resp.json();
      return {
        workflow_name: data.workflow_ga?.name ?? data.workflow_name,
        description: data.workflow_ga?.description ?? '',
        nextflow_path: data.workflow_ga?.nextflow_path ?? data.nextflow_path ?? '',
        required_params: data.workflow_ga?.required_params ?? [],
        optional_params: data.workflow_ga?.optional_params ?? [],
        confidence: data.confidence ?? 0,
        workflow_ga: data.workflow_ga ?? null,
        // Pass the full object through so the response layer can render a workflow card
        _raw: data,
      };
    }

    // -----------------------------------------------------------------------
    case 'search_literature': {
      const resp = await fetch(`${galaxyUrl}/api/ai_assistant/research_query`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          query: input.query,
          context: { information_need: 'research_question', databases: input.databases ?? [] },
          include_citations: true,
          include_benchmark_evidence: input.include_benchmark_evidence ?? false,
        }),
        signal: AbortSignal.timeout(60_000),
      });
      if (!resp.ok) throw new Error(`search_literature HTTP ${resp.status}`);
      return resp.json();
    }

    // -----------------------------------------------------------------------
    case 'run_code': {
      const { runCode } = await import('./code-runner');
      const inputDatasets = (input.dataset_ids ?? []).map((id: string) => ({ id }));
      return runCode({
        language: input.language,
        code: input.code,
        input_datasets: inputDatasets,
      });
    }

    // -----------------------------------------------------------------------
    case 'synthesize_papers': {
      const filePaths: string[] = [];
      for (const id of (input.dataset_ids ?? [])) {
        const f = getUploadedFile(id);
        if (f?.filePath) filePaths.push(f.filePath);
      }
      if (filePaths.length === 0) return { error: 'No valid file paths found for given dataset_ids' };

      const resp = await fetch(`${galaxyUrl}/api/ai_assistant/paperqa_synthesize`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          file_paths: filePaths,
          question: input.question,
          llm: 'claude-sonnet-4-6',
        }),
        signal: AbortSignal.timeout(300_000),
      });
      if (!resp.ok) throw new Error(`synthesize_papers HTTP ${resp.status}: ${await resp.text()}`);
      return resp.json();
    }

    // -----------------------------------------------------------------------
    case 'get_benchmark_evidence': {
      const resp = await fetch(`${galaxyUrl}/api/ai_assistant/benchmark_query`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          query: `${input.task} ${(input.tool_names ?? []).join(' ')}`.trim(),
          top_k: 10,
        }),
        signal: AbortSignal.timeout(30_000),
      });
      if (!resp.ok) throw new Error(`get_benchmark_evidence HTTP ${resp.status}`);
      return resp.json();
    }

    // -----------------------------------------------------------------------
    default:
      return { error: `Unknown orchestrator tool: ${name}` };
  }
}

// ---------------------------------------------------------------------------
// Orchestrator loop
// ---------------------------------------------------------------------------

export interface OrchestratorResult {
  message: string;
  /** workflow_ga if search_workflows was called and returned one */
  generatedWorkflow?: any;
  /** tool calls made during orchestration, for telemetry */
  toolsInvoked: string[];
}

const MAX_TURNS = 8;

export async function runOrchestrator(
  claude: Anthropic,
  message: string,
  context: ChatContext,
  deps: OrchestratorExecutorDeps,
  systemPrompt: string,
  onResponseDelta?: (chunk: string) => void,
): Promise<OrchestratorResult> {
  const messages: Anthropic.MessageParam[] = [
    { role: 'user', content: message },
  ];

  let generatedWorkflow: any = null;
  const toolsInvoked: string[] = [];

  for (let turn = 0; turn < MAX_TURNS; turn++) {
    const completion = await deps.withRetry(
      () => claude.messages.create({
        model: 'claude-sonnet-4-6',
        max_tokens: 8192,
        system: systemPrompt,
        tools: ORCHESTRATOR_TOOL_SCHEMAS,
        messages,
      }),
      `orchestrator-turn-${turn}`,
    );

    const toolUseBlocks = completion.content.filter((b: any) => b.type === 'tool_use');

    if (completion.stop_reason === 'end_turn' || toolUseBlocks.length === 0) {
      // Final response — extract text
      const textBlock = completion.content.find((b: any) => b.type === 'text');
      const finalText = textBlock && textBlock.type === 'text' ? (textBlock as any).text : '';
      if (onResponseDelta && finalText) onResponseDelta(finalText);
      return { message: finalText, generatedWorkflow, toolsInvoked };
    }

    // Execute all tool calls in parallel (respecting each tool's own semantics)
    messages.push({ role: 'assistant', content: completion.content as any });

    const toolResults = await Promise.all(
      toolUseBlocks.map(async (block: any) => {
        toolsInvoked.push(block.name);
        let output: unknown;
        try {
          output = await executeOrchestratorTool(block.name, block.input, context, deps);
          // Track workflow if search_workflows returned one
          if (block.name === 'search_workflows' && (output as any)?._raw) {
            generatedWorkflow = (output as any)._raw;
          }
        } catch (err: any) {
          output = { error: err?.message ?? String(err) };
        }
        return {
          type: 'tool_result' as const,
          tool_use_id: block.id,
          content: JSON.stringify(output),
        };
      })
    );

    messages.push({ role: 'user', content: toolResults as any });
  }

  // Guard: max turns exceeded — return best effort from last assistant message
  const lastAssistant = [...messages].reverse().find(m => m.role === 'assistant');
  const lastText = (() => {
    if (!lastAssistant || !Array.isArray(lastAssistant.content)) return '';
    const tb = (lastAssistant.content as any[]).find((b: any) => b.type === 'text');
    return tb?.text ?? '';
  })();
  return {
    message: lastText || 'I reached the maximum planning depth. Please try rephrasing your request.',
    generatedWorkflow,
    toolsInvoked,
  };
}

// ---------------------------------------------------------------------------
// System prompt for the orchestrator
// ---------------------------------------------------------------------------

export const ORCHESTRATOR_SYSTEM_PROMPT = `\
You are BioMate, an AI assistant for biomedical research and bioinformatics.
You have access to the following capabilities as tools:

- **search_workflows** — find and suggest a bioinformatics workflow from BioMate's library of 2,455+ pipelines
- **search_literature** — query PubMed, GWAS Catalog, OMIM, Open Targets, Ensembl, and more
- **run_code** — execute Python, R, or bash in a secure sandbox
- **synthesize_papers** — use PaperQA2 to answer questions across multiple uploaded PDFs
- **get_benchmark_evidence** — compare tool performance from BioMate's benchmark database

## How to plan

1. **Identify what the user needs** — execution (run a pipeline), knowledge (literature/DB lookup), analysis (code), or synthesis (papers).
2. **Call the right tool(s)** — you may call multiple tools in one turn. Call them in parallel when they are independent.
3. **Chain tools when needed** — e.g. search_literature to understand the method, then search_workflows to run it.
4. **Synthesise** — once you have all tool results, write a clear, concise response.

## Rules

- Never fabricate tool outputs. If a tool returns an error, say so and explain what you tried.
- When search_workflows returns a workflow, always tell the user what it does and what parameters it needs.
- When search_literature returns citations, always include them in your response.
- Do not call the same tool twice with the same arguments.
- If the user's request is ambiguous, call a tool first, then ask a targeted follow-up if still unclear.
- Keep your final response concise — lead with the action/answer, not the reasoning.
`;
