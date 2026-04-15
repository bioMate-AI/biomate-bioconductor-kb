
  // Chat endpoint with Galaxy Assistant integration
  app.post("/api/chat", optionalAuth, async (req, res) => {
    const requestStartTime = Date.now();
    const timings: { step: string; elapsed: number }[] = [];
    const addTiming = (step: string) => {
      timings.push({ step, elapsed: Date.now() - requestStartTime });
      console.log(`[Chat API] [${Date.now() - requestStartTime}ms] ${step}`);
    };

    try {
      addTiming('Request received');
      const { message, context } = req.body;

      if (!message) {
        addTiming('Error: Message missing');
        return res.status(400).json({ error: "Message is required" });
      }

      if (!galaxyAssistant) {
        addTiming('Error: Galaxy Assistant not available');
        return res.status(503).json({
          error: "Galaxy Assistant not available. ANTHROPIC_API_KEY is not configured."
        });
      }

      addTiming('Validation passed');
      console.log('[Chat API] Processing message with Galaxy Assistant:', message);

      // ----------------------------------------------------------------
      // Conversation State: Load persisted state (pre-compaction flush)
      // ----------------------------------------------------------------
      const sessionId = context?.memorySessionId || context?.sessionId;
      let convState: ConversationState | undefined;

      if (sessionId) {
        convState = await conversationStateManager.loadState(sessionId);
        convState.currentTurn += 1;

        // Check if this message answers a pending clarification
        const resolvedClarification = conversationStateManager.resolveClarifications(convState, message);
        if (resolvedClarification) {
          addTiming(`Clarification resolved: ${resolvedClarification.type}`);
        }
      }

      // Check if memory integration should be used
      const useMemory = memoryIntegration && (context?.memorySessionId || context?.projectId);
      let assistantResponse;
      let episodeId: number | undefined;

      // Build enriched context for the LLM — pass accumulated facts so it can
      // decide supersession, and turnIndex so facts get the right timestamp
      const enrichedContext = {
        ...(context || {}),
        turnIndex: convState?.currentTurn,
        accumulatedFacts: convState
          ? conversationStateManager.getActiveFacts(convState).map(f => ({
              id: f.id,
              category: f.category,
              value: f.value,
            }))
          : undefined,
        // Billing: pass authenticated user id so the Python backend can track LLM costs
        billingUserId: req.user ? String(req.user.id) : undefined,
        // Session-uploaded datasets: activates WorkflowDatasetSelector + domain-specialist format context
        sessionDatasets: req.session?.uploadedDatasets?.length
          ? req.session.uploadedDatasets.map((d: any) => ({
              id: d.galaxy_dataset_id || d.dataset_id,
              name: d.name,
              type: d.file_type || 'unknown',
            }))
          : undefined,
      };

      addTiming('Starting AI processing');

      if (useMemory) {
        // Process with memory enhancement
        addTiming('Using memory-enhanced processing');
        const memoryResponse = await memoryIntegration!.processWithMemory(message, context as MemoryEnhancedContext);
        assistantResponse = memoryResponse;
        episodeId = memoryResponse.episodeId;
        addTiming('Memory processing complete');
      } else {
        // Standard processing without memory
        addTiming('Using standard processing');
        assistantResponse = await galaxyAssistant.processMessage(message, enrichedContext);
        addTiming('Standard processing complete');
      }

      // ----------------------------------------------------------------
      // Conversation State: Update with extracted facts and intent
      // ----------------------------------------------------------------
      if (convState) {
        // Update intent from assistant response
        if (assistantResponse.intentType) {
          conversationStateManager.updateIntent(
            convState,
            assistantResponse.intentType,
            assistantResponse.intentConfidence || 0.8,
          );
        }

        // Add extracted facts (turnIndex already set via enrichedContext)
        if (assistantResponse.extractedFacts && assistantResponse.extractedFacts.length > 0) {
          conversationStateManager.addFacts(convState, assistantResponse.extractedFacts);
        } else if (assistantResponse.inlineParameters) {
          // Backwards compatibility: convert inlineParameters to facts
          const facts = Object.entries(assistantResponse.inlineParameters).map(([key, value]) =>
            conversationStateManager.createFact(
              key as any,
              String(value),
              convState!.currentTurn,
            )
          );
          conversationStateManager.addFacts(convState, facts);
        }

        // Recommendations update removed

        // Update phase if workflow was generated
        if (assistantResponse.generatedWorkflow) {
          convState.phase = 'generated';
        }

        // Track workflow steps in ConversationState for pipeline output→input wiring.
        // When the AI returns a generated workflow, record it as a step so subsequent
        // chained workflows can check type compatibility against it.
        if (assistantResponse.generatedWorkflow && convState) {
          const wf = assistantResponse.generatedWorkflow as any;
          const workflowName: string = wf?.name || wf?.workflowName || wf?.nextflow_path || '';
          if (workflowName) {
            // Fetch type info from backend (fire-and-forget, don't block response)
            const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
            fetch(`${galaxyUrl}/api/workflows/${encodeURIComponent(workflowName)}/types`, {
              signal: AbortSignal.timeout(3000),
            })
              .then(r => r.ok ? r.json() : null)
              .then((typeInfo: any) => {
                if (!typeInfo) return;
                conversationStateManager.addWorkflowStep(convState!, {
                  workflowId: String(wf?.id || ''),
                  workflowName,
                  domain: wf?.domain || typeInfo?.domain || 'general',
                  inputTypes: typeInfo?.input_types ?? [],
                  outputTypes: typeInfo?.output_types ?? [],
                  status: 'planned',
                  turnIndex: convState!.currentTurn,
                });
                conversationStateManager.saveState(convState!).catch(() => {});
              })
              .catch(() => {});
          }
        }

        // Create task arcs for multi-intent responses
        if (assistantResponse.isMultiIntent && assistantResponse.subIntentResults) {
          conversationStateManager.createTaskArcs(convState,
            assistantResponse.subIntentResults.map(r => ({
              id: r.intentId,
              type: r.intentType,
              subQuery: r.subQuery,
              facts: [],
              dependsOn: [],
            }))
          );
          // Update arc statuses based on results
          for (const result of assistantResponse.subIntentResults) {
            conversationStateManager.updateTaskArc(convState, result.intentId, {
              status: result.status === 'success' ? 'completed' : 'failed',
              resultSummary: result.message?.substring(0, 200),
            });
          }
        }

        // Evaluate readiness
        conversationStateManager.evaluateReadiness(convState);

        // Save state (pre-compaction flush — persists every turn)
        await conversationStateManager.saveState(convState);

        // Persist current turn's facts to the facts table for cross-session analysis
        await conversationStateManager.persistFacts(convState);

        // Periodic consolidation: every 10 turns, compact facts and intent history
        if (convState.currentTurn > 0 && convState.currentTurn % 10 === 0) {
          conversationStateManager.consolidateFacts(convState);
          conversationStateManager.compactIntentHistory(convState);
          await conversationStateManager.saveState(convState);
        }

        // Doom loop detection: check every turn
        const doomLoop = conversationStateManager.detectDoomLoop(convState);
        if (doomLoop.detected) {
          console.log(`[Chat API] Doom loop detected: ${doomLoop.intentType} repeated ${doomLoop.occurrences} times`);
        }

        addTiming('Conversation state saved');
      }

      console.log('[Chat API] Galaxy Assistant response:', {
        toolSearchUsed: assistantResponse.sources.toolSearchUsed,
        datasetRAGUsed: assistantResponse.sources.datasetRAGUsed,
        workflowGenerated: assistantResponse.sources.workflowGenerated,
        thinkingUsed: assistantResponse.sources.thinkingUsed,
        toolsFound: assistantResponse.recommendedTools?.length || 0,
        datasetsFound: assistantResponse.recommendedDatasets?.length || 0,
        memoryUsed: useMemory,
        episodeId,
      });

      // If workflow was generated, validate prerequisites
      let prerequisitesValidation = null;
      if (assistantResponse.generatedWorkflow && prerequisitesValidator) {
        try {
          console.log('[Chat API] Validating workflow prerequisites...');
          prerequisitesValidation = await prerequisitesValidator.validate({
            workflowDefinition: assistantResponse.generatedWorkflow,
            historyId: context?.historyId,
            userContext: message, // Use original message as context
          });
          console.log('[Chat API] Prerequisites validation:', {
            fulfilled: prerequisitesValidation.fulfilled,
            missingInputs: prerequisitesValidation.analysis.missingInputs.length,
            missingParams: prerequisitesValidation.analysis.missingParameters.length,
          });
        } catch (validationError: any) {
          console.error('[Chat API] Prerequisites validation failed:', validationError.message);
          // Non-fatal - continue without validation
        }
      }

      // Domain-fit guardrail: block execution when generated tools are clearly off-domain.
      const requestTextLower = (message || '').toLowerCase();
      const requestedWesLike =
        requestTextLower.includes('whole-exome') ||
        requestTextLower.includes('whole exome') ||
        /\bwes\b/.test(requestTextLower) ||
        requestTextLower.includes('tumor-normal') ||
        requestTextLower.includes('tumor normal');
      const toolText = (assistantResponse.recommendedTools || [])
        .map((t: any) => `${t?.tool?.name || ''} ${t?.tool?.tool_id || ''} ${t?.tool?.category || ''}`.toLowerCase())
        .join(' ');
      const hasWesPreferredSignals =
        /picard|samtools|qualimap|mosdepth|bcftools|gatk|bamqc/.test(toolText);
      const hasMicrobiomeSignals =
        /qiime|microbiome|metagenom|16s/.test(toolText);
      const selfReportedMismatch =
        /not (the )?ideal match|aren't (the )?ideal match|not ideal for/.test(
          (assistantResponse.message || '').toLowerCase()
        );

      const domainGuard =
        (requestedWesLike && hasMicrobiomeSignals && !hasWesPreferredSignals) || selfReportedMismatch
          ? {
              blocked: true,
              reason:
                "Generated workflow appears domain-mismatched for your request. Please regenerate with domain-specific constraints before execution.",
              detectedDomain: requestedWesLike ? "wes_qc" : "general",
            }
          : {
              blocked: false,
              reason: null,
              detectedDomain: requestedWesLike ? "wes_qc" : "unspecified",
            };

      const workflowPayload = assistantResponse.generatedWorkflow;
      const runnableWorkflow = !!(
        workflowPayload?.success &&
        !workflowPayload?.error &&
        (workflowPayload?.workflow_ga || workflowPayload?.nextflow_path ||
         workflowPayload?.workflow_type === "chain" || workflowPayload?.chain_name)
      );
      const workflowGenerationFailed = !!workflowPayload && !runnableWorkflow;
      const workflowGenerationDiagnostics = (() => {
        if (!workflowGenerationFailed) return null;

        const reasonText = String(workflowPayload?.error || workflowPayload?.message || "").toLowerCase();
        const likelyReasons: string[] = [];
        const recommendedActions: string[] = [];
        const followUpQuestions: string[] = [];
        const suggestionConfidence = Number(assistantResponse.workflowSuggestion?.confidence || 0);

        if (domainGuard.blocked) {
          likelyReasons.push("The generated candidate appears domain-mismatched for your request.");
          recommendedActions.push("Regenerate with explicit domain constraints and required tool families.");
        }
        if (/timeout|timed out|deadline|temporar/.test(reasonText)) {
          likelyReasons.push("Upstream workflow generation timed out or an upstream service was temporarily unavailable.");
          recommendedActions.push("Retry generation with a narrower workflow scope (fewer stages) first.");
        }
        if (/auth|forbidden|permission|unauthor|401|403/.test(reasonText)) {
          likelyReasons.push("Generation hit an authentication/permission boundary in a dependent service.");
          recommendedActions.push("Confirm service credentials and retry after auth context is refreshed.");
        }
        if (/tool|runtime|install|dependency/.test(reasonText)) {
          likelyReasons.push("Tool/runtime constraints prevented assembling a runnable workflow.");
          recommendedActions.push("Constrain to currently available tools and rerun generation.");
        }
        if ((assistantResponse.recommendedTools?.length || 0) === 0) {
          likelyReasons.push("No strong tool matches were found for the current request phrasing.");
          recommendedActions.push("Provide required method/tool hints (must-use or must-avoid) to improve ranking.");
        }
        if (suggestionConfidence > 0 && suggestionConfidence < 0.7) {
          likelyReasons.push("Intent-to-workflow confidence is low; requirements may still be underspecified.");
          recommendedActions.push("Clarify organism/data type/input format/desired outputs before regenerating.");
        }
        if (likelyReasons.length === 0) {
          likelyReasons.push("The generation pipeline returned a non-runnable candidate due to unmet constraints.");
          recommendedActions.push("Regenerate with stricter constraints and explicit required outputs.");
        }

        followUpQuestions.push(
          "What exact input data do you already have (format + example filenames)?",
          "Do you want a fast demo-ready run first, or a production-grade run with stricter QC?",
          "Any required tools/runtimes to include or avoid?"
        );

        return {
          failed: true,
          likelyReasons,
          recommendedActions,
          followUpQuestions,
          processOutputs: {
            error: workflowPayload?.error || null,
            message: workflowPayload?.message || null,
            source: workflowPayload?.source || null,
            confidence: workflowPayload?.confidence ?? null,
            templateMatchScore: workflowPayload?.template_match_score ?? null,
            toolCount: assistantResponse.recommendedTools?.length || 0,
            datasetCount: assistantResponse.recommendedDatasets?.length || 0,
            domainGuard: domainGuard.blocked ? domainGuard.reason : null,
          },
        };
      })();

      const assistantMessage = String(assistantResponse.message || "");

      // Compute response state for consistent downstream handling.
      // Clarification responses (workflow_type="clarification") are "needs_input" — BioMate
      // is asking for more context before it can proceed. They must NOT fall through to
      // "workflow_failed" (which would misrepresent the situation).
      const isClarificationRequest = workflowPayload?.workflow_type === "clarification";
      const responseState: "workflow_ready" | "needs_input" | "workflow_failed" | "chat_only" =
        runnableWorkflow ? "workflow_ready"
        : isClarificationRequest ? "needs_input"
        : workflowGenerationFailed ? "workflow_failed"
        : (prerequisitesValidation && !(prerequisitesValidation as any).canRun) ? "needs_input"
        : "chat_only";

      // Format response for frontend
      addTiming('Sending response');
      const suggestions = generateSuggestions(
        String(assistantResponse.message || ""),
        String(message || "")
      );

      // Persist chat cost estimate for end-to-end process auditing.
      // This is an approximation based on local token counting heuristics.
      try {
        const inCount = tokenCounter.countText(String(message || "")).tokens;
        const outCount = tokenCounter.countText(String(assistantResponse.message || "")).tokens;
        const pricing = tokenCounter.estimateCost([
          { role: "user", content: String(message || "") },
          { role: "assistant", content: String(assistantResponse.message || "") },
        ]);
        const estimatedCostUsd = Number((pricing.total || 0).toFixed(8));
        const sessionId = String(context?.memorySessionId || context?.sessionId || "");
        const runId = String(context?.runId || context?.executionRunId || "");
        const invocationId = String(context?.invocationId || "");

        telemetryService
          .create("cost.chat.estimated", new Date(), {
            userId: req.user ? String(req.user.id) : "anonymous",
            sessionId: sessionId || undefined,
            runId: runId || undefined,
            invocationId: invocationId || undefined,
            provider: "anthropic",
            model: galaxyAssistant?.getModelConfig().responseModel || "claude-sonnet-4-6",
            inputTokensEstimated: inCount,
            outputTokensEstimated: outCount,
            estimatedCostUsd,
            estimationMethod: "token_counter_heuristic",
          })
          .catch((error) => {
            console.warn("[CostAudit] Failed to persist chat cost estimate:", error?.message || error);
          });

        // Emit LLM cost event to Galaxy billing backend → Lago (fire-and-forget)
        if (req.user) {
          const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
          const billingKey = process.env.BILLING_INTERNAL_KEY;
          if (billingKey) {
            fetch(`${galaxyUrl}/internal/billing/llm_cost`, {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
                'X-Internal-Key': billingKey,
              },
              body: JSON.stringify({
                user_id: String(req.user.id),
                session_id: sessionId || `chat-${Date.now()}`,
                model: galaxyAssistant?.getModelConfig().responseModel || 'claude-sonnet-4-6',
                input_tokens: inCount,
                output_tokens: outCount,
                duration_ms: 0,
              }),
              signal: AbortSignal.timeout(5000),
            }).catch((err: any) => {
              console.warn('[Billing] llm_cost emission failed:', err?.message || err);
            });
          }
        }
      } catch (costError: any) {
        console.warn("[CostAudit] Failed to estimate chat cost:", costError?.message || costError);
      }

      res.json({
        response: assistantMessage,
        state: responseState,
        suggestions,
        workflow: assistantResponse.generatedWorkflow,

        // Pre-execution validation (if workflow was generated)
        prerequisitesValidation,

        // Thinking mode support
        thinking_content: assistantResponse.thinking_content,
        thinking_level: assistantResponse.thinking_level,

        // Memory tracking
        episodeId,

        // Additional metadata for UI enhancement
        metadata: {
          intentType: assistantResponse.intentType,
          inlineParameters: assistantResponse.inlineParameters,
          workflowSuggestion: assistantResponse.workflowSuggestion,
          sources: assistantResponse.sources,
          memoryUsed: useMemory,
          domainGuard,
          workflowGenerationDiagnostics,
        },

        // Multi-intent results
        subIntentResults: assistantResponse.subIntentResults,
        isMultiIntent: assistantResponse.isMultiIntent || false,

        // Research and benchmark results (for specialized rendering)
        researchResponse: assistantResponse.researchResponse,
        benchmarkEvidence: assistantResponse.benchmarkEvidence,

        // Conversation state snapshot for UI transparency
        stateSnapshot: convState ? {
          phase: convState.phase,
          factCount: conversationStateManager.getActiveFacts(convState).length,
          readinessScore: convState.readiness.score,
          missingRequired: convState.readiness.missingRequired,
          intentType: convState.intent.primaryType,
          intentConfidence: convState.intent.confidence,
          taskArcs: convState.taskArcs?.map(a => ({
            id: a.id, intentType: a.intentType, status: a.status,
          })),
          doomLoop: (() => {
            const dl = conversationStateManager.detectDoomLoop(convState);
            return dl.detected ? { suggestion: dl.suggestion } : undefined;
          })(),
          // Pipeline chain state — surfaces type compatibility warnings to UI
          pipelineSteps: convState.workflowSteps?.map(s => ({
            stepIndex: s.stepIndex,
            workflowName: s.workflowName,
            status: s.status,
            inputTypes: s.inputTypes,
            outputTypes: s.outputTypes,
            warnings: s.compatibilityWarnings,
          })) ?? [],
          pipelineWarnings: conversationStateManager.getPipelineWarnings(convState),
        } : undefined,

        // Clarification request (if system needs user input or doom loop detected)
        clarification: (() => {
          // Doom loop clarification takes priority if no pending clarifications
          const pending = convState?.pendingClarifications.find(c => c.status === 'pending');
          if (pending) {
            return { id: pending.id, question: pending.question, options: pending.options, type: pending.type };
          }
          if (convState) {
            const dl = conversationStateManager.detectDoomLoop(convState);
            if (dl.detected && dl.suggestion) {
              return { id: 'doom_loop', question: dl.suggestion, type: 'ambiguous_intent' as const };
            }
          }
          return undefined;
        })(),

        // Debug: Include timings
        _debug_timings: timings,
      });
      addTiming('Response sent');

    } catch (error: any) {
      addTiming(`Error: ${error.message}`);
      console.error("Chat API error:", error);

      // Track AI assistant errors for error-rate dashboard
      telemetryService.create('ai_assistant_error', new Date(), {
        error: (error as Error).message?.slice(0, 200),
        path: req.path,
      }).catch(() => {});

      // Fallback response
      const fallbackResponse = "I'm here to help you with bioinformatics analysis! What kind of data or workflow would you like to work on?";

      res.json({
        response: fallbackResponse,
        suggestions: generateSuggestions(fallbackResponse, String(req.body?.message || "")),
        workflow: null,
        metadata: {
          error: error.message,
        },
      });
    }
  });
