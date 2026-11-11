/**
 * Build the assistant chat message (text + workflow-card metadata) from the
 * server's `final` SSE payload of POST /api/chat/stream.
 *
 * Single source of truth for two paths that must agree:
 *   1. the live stream (chat-interface onSuccess), and
 *   2. session reload (chat-history fetchSessionDetail) when the stored
 *      assistant message carries only the server-persisted `finalPayload`
 *      — i.e. the browser left before its own session sync wrote `metadata`.
 * Without (2) a turn whose browser tab closed/reloaded after the server
 * finished came back as the summary text with NO workflow card
 * (docs/20261110_COLDSTART_EXAMPLES_LIVE_AUDIT.md §4.1).
 */
import { awaitsWorkflowInput, hasGeneratedWorkflow } from "./workflow-response-state"

export interface AssistantMessageFromFinal {
  message: {
    id: string
    content: string
    role: "assistant"
    timestamp: Date
    invocationId?: string
    suggestions: string[]
    metadata: Record<string, any>
  }
  workflowSuccess: boolean
  workflowData: any
  stepsArray: Array<{ name: string; tool_id?: string; annotation?: string }>
}

export function buildAssistantMessageFromFinal(data: any, messageId: string): AssistantMessageFromFinal {
  // Handle /api/chat response format (full hybrid intelligence)
  // Response structure: { response, suggestions, workflow, thinking_content, metadata }
  let workflowData: any = data.workflow?.workflow_ga || data.workflow;
  const awaitingWorkflowInput = awaitsWorkflowInput(data.workflow, data.metadata);
  const workflowSuccess = hasGeneratedWorkflow(data.workflow, data.metadata);

  // Check if workflow was generated
  if (data.workflow && !workflowSuccess && !awaitingWorkflowInput) {
    console.warn('[ChatInterface] Workflow generation returned but failed:', data.workflow.error || data.workflow.message);
    workflowData = null;
  }

  // Use the natural language response from /api/chat
  // This includes tool recommendations, dataset suggestions, etc.
  let workflowInfo: string = data.response || '';
  const diagnostics = data.metadata?.workflowGenerationDiagnostics;
  const hasFailureDiagnostics = !!diagnostics?.failed;
  const failureNarrativePattern =
    /workflow generation failed|could not build (a|the) runnable workflow|domain alignment|recovery plan|targeted follow-up questions/i;
  const looksLikeNarrativeFailure =
    typeof data.response === 'string' && failureNarrativePattern.test(data.response);
  // Show collaborative failure UI only when generation explicitly failed (diagnostics.failed=true)
  // or when the LLM response itself describes a failure narrative. A workflow object being
  // present alone (e.g. a failed generation attempt that the LLM handled as a clarification
  // question) is not a sufficient signal — it would wrongly show the failure card for every
  // clarification turn with openai_compatible providers (Qianwen, DeepSeek, etc.).
  const shouldRenderCollaborativeFailure =
    !workflowSuccess && !awaitingWorkflowInput && (hasFailureDiagnostics || looksLikeNarrativeFailure);

  // If workflow was generated, append workflow-specific info
  if (workflowSuccess && workflowData) {
    // No canned "✅ I've generated a workflow" line: the card already says it, and the English
    // check (`includes('workflow')`) appended it to every Chinese reply.
    // Generation already completed. Loading belongs to the transient typing
    // indicator, not persisted reply text that remains after a run finishes.
    if (data.workflow?.needs_user_feedback) {
      workflowInfo += `\n\n⚠️ ${data.workflow?.feedback_prompt || 'Confidence is not high enough yet. Please review and provide corrections before execution.'}`;
    }
  } else if (shouldRenderCollaborativeFailure) {
    const reasons = Array.isArray(diagnostics?.likelyReasons) ? diagnostics.likelyReasons : [];
    const actions = Array.isArray(diagnostics?.recommendedActions) ? diagnostics.recommendedActions : [];
    const followUps = Array.isArray(diagnostics?.followUpQuestions) ? diagnostics.followUpQuestions : [];
    const reasonText = reasons.length > 0 ? `\n\nLikely reasons:\n- ${reasons.join('\n- ')}` : '';
    const actionText = actions.length > 0 ? `\n\nSuggested next actions:\n- ${actions.join('\n- ')}` : '';
    const followUpText =
      followUps.length > 0
        ? `\n\nTo continue collaboratively, please answer:\n- ${followUps.join('\n- ')}`
        : '';
    const baseFailureText = /workflow generation is currently unavailable/i.test(data.response || '')
      ? (data.response || '')
      : `${data.response || ''}\n\n⚠️ **Workflow generation is currently unavailable for this request.**`;
    workflowInfo =
      baseFailureText +
      reasonText +
      actionText +
      followUpText;
  } else if (!workflowInfo) {
    // Empty response — likely a backend initialization error during workflow generation.
    // Emit an informative recovery message so classifiers and users can act on it.
    workflowInfo = '⚠️ **Workflow generation failed — no response received from the AI service.** ' +
      'This may be a temporary initialization issue. Please try your request again, or rephrase your query. ' +
      'Suggested recovery steps:\n- Retry the same message\n- Simplify your request\n- Check that the backend service is running';
  }

  // Convert workflow_ga.steps object to array
  const stepsArray = workflowData?.steps ?
    Object.values(workflowData.steps).map((step: any) => ({
      name: step.name || step.tool_id || step.title || 'Unknown step',
      tool_id: step.tool_id || step.tool,
      annotation: step.annotation || step.description
    })) : []

  // Push LLM-extracted inline params from data.metadata.inlineParameters
  // (camelCase, set by galaxy-assistant.ts after WORKFLOW_PARAM_ALIASES remap)
  // into workflowData.inline_parameters (snake_case) where the viewer reads
  // them via workflowDefinition.inline_parameters. Without this, the form
  // renders with default values and the execute POST body has empty
  // toolParameters — the original demo-blocker bug.
  if (workflowData && data.metadata?.inlineParameters && typeof data.metadata.inlineParameters === 'object') {
    const remappedParams = data.metadata.inlineParameters as Record<string, any>;
    if (Object.keys(remappedParams).length > 0) {
      workflowData = {
        ...workflowData,
        inline_parameters: {
          ...(workflowData.inline_parameters || {}),
          ...remappedParams,
        },
      };
    }
  }
  // The workflow panel reads validation from the workflow definition while
  // the chat card reads it from message metadata. Keep one backend verdict
  // on both surfaces so a selected workflow cannot change readiness merely
  // because it moved from chat into the right panel.
  if (workflowData && data.prerequisitesValidation) {
    workflowData = {
      ...workflowData,
      prerequisitesValidation: data.prerequisitesValidation,
    };
  }

  
  const aiMessage = {
    id: messageId,
    content: workflowInfo,
    role: "assistant" as const,
    timestamp: new Date(),
    // Include invocationId from API response to trigger output viewers
    invocationId: data.invocationId,
    // Use suggestions from /api/chat or fallbacks
    suggestions: data.suggestions || (data.workflow?.needs_user_feedback
      ? ["This domain looks correct", "Use different domain/tools", "Regenerate with stricter constraints", "Show alternative workflows"]
      : workflowSuccess
      ? ["Open in Workflow Builder", "Show details", "Generate another"]
      : data.metadata?.workflowGenerationDiagnostics?.followUpQuestions?.slice?.(0, 3) ||
        ["Try again with different request", "Provide required inputs/formats", "Regenerate with tighter constraints"]),
    metadata: {
      type: workflowSuccess ? 'workflow' : (data.researchResponse ? 'research_response' : 'text'),
      // Code-execution blocks streamed during the turn (run_code / read_file). The final
      // message REPLACES the streaming placeholder, so without carrying them here the
      // executed code + output vanished from the answer once streaming ended (live
      // journey on dev, 2026-11-11).
      ...(Array.isArray(data.toolBlocks) && data.toolBlocks.length > 0 ? { toolBlocks: data.toolBlocks } : {}),
      research_response: data.researchResponse || null,
      workflow: workflowData,
      steps: stepsArray,
      confidence: data.workflow?.confidence || data.metadata?.workflowSuggestion?.confidence,
      source: data.workflow?.source || 'chat',
      needsUserFeedback: awaitingWorkflowInput,
      feedbackPrompt: data.workflow?.feedback_prompt,
      candidateWorkflows: data.workflow?.candidate_workflows || [],
      selectedTrial: data.workflow?.selected_trial,
      trialCount: data.workflow?.trial_count,
      isDemo: false,
      generationFailed: data.workflow && !workflowSuccess && !awaitingWorkflowInput,
      failureReason: data.workflow?.error || data.workflow?.message,
      // Thinking mode support from /api/chat
      thinking_content: data.thinking_content,
      thinking_level: data.thinking_level,
      // Tool and dataset recommendations from hybrid intelligence
      recommendedTools: data.metadata?.recommendedTools || [],
      recommendedDatasets: data.metadata?.recommendedDatasets || [],
      workflowSuggestion: data.metadata?.workflowSuggestion,
      // Store LLM-extracted inline params at message metadata level too —
      // chat-with-artifacts panel auto-open merges this into workflow.inline_parameters
      // as a fallback in case workflowData mutation gets serialized away (Bug A+C).
      inlineParameters: data.metadata?.inlineParameters,
      // Forward clarification payloads to chat-message so the UI cards render.
      // Without these the IntentClarificationCard / ParamClarificationCard
      // never appears even when the backend emits the data (caught
      // 2026-06-16 by the intent-clarification e2e: backend friendly
      // message rendered but card didn't).
      intentClarification: data.metadata?.intentClarification,
      paramClarifications: data.metadata?.paramClarifications,
      sources: data.metadata?.sources || {},
      memoryUsed: data.metadata?.memoryUsed || false,
      domainGuard: data.metadata?.domainGuard,
      episodeId: data.episodeId,
      // Validation info from workflow if available
      validation: data.workflow?.validation || { is_valid: true, issues: [], warnings: [] },
      tool_installation: data.workflow?.tool_installation || { success: true, failed_tools: [] },
      // Prerequisites validation (input data, parameters needed before execution)
      prerequisitesValidation: data.prerequisitesValidation || null,
      // Ids this turn's selected references could not resolve — threaded into
      // the execute request so the server's inputs_unresolved gate engages.
      datasetReferenceUnresolvedIds: data.datasetReferenceUnresolvedIds || undefined,
    }
  }

  return { message: aiMessage as AssistantMessageFromFinal["message"], workflowSuccess, workflowData, stepsArray }
}
