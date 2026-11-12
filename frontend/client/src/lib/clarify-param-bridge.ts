/**
 * ClarifyCard → workflow-panel bridge.
 *
 * The card emits `biomate:param-clarification-resolved` with the answer the
 * user confirmed; the panel pre-fills that parameter from the open workflow's
 * `inline_parameters`. An answer that refers to an attachment ("use the
 * attached file", "用附件", or the file's name) must bind THAT FILE's dataset
 * reference — binding the sentence left the required input unset, which is what
 * the founder saw when "Confirm and configure" appeared to do nothing
 * (2026-11-11).
 *
 * Pure so the behaviour is unit-testable without mounting the chat panel.
 */
import {
  attachedFilesFromMessages,
  bindClarificationAnswer,
  type AttachedFile,
  type BindableParam,
} from '@shared/attachment-binding';

export interface ClarificationResolvedDetail {
  messageId?: string;
  paramName: string;
  value: string;
}

export interface ClarificationBridgeResult {
  /** The workflow object to put back in the panel (unchanged on a no-op). */
  workflow: any;
  /** The value actually bound to the parameter. */
  value: string;
  /** The attachment it was resolved to, when the answer referred to one. */
  file?: AttachedFile;
}

/** The workflow's parameter definition for `name`, if the panel object has one. */
export function paramSpec(workflow: any, name: string): BindableParam | undefined {
  const all = [
    ...(workflow?.required_params || []),
    ...(workflow?.optional_params || []),
  ];
  return all.find((p: any) => String(p?.name || '') === name);
}

export function applyClarificationAnswer(
  workflow: any,
  detail: ClarificationResolvedDetail,
  messages: ReadonlyArray<{ role?: string; content?: unknown }> = [],
): ClarificationBridgeResult {
  const paramName = detail?.paramName;
  const answer = String(detail?.value ?? '');
  if (!workflow || !paramName) return { workflow, value: answer };
  const attached = attachedFilesFromMessages(messages);
  const resolved = attached.length > 0
    ? bindClarificationAnswer(answer, attached, paramSpec(workflow, paramName))
    : { value: answer, bound: false as const, file: undefined as AttachedFile | undefined };
  return {
    workflow: {
      ...workflow,
      inline_parameters: {
        ...(workflow.inline_parameters || {}),
        [paramName]: resolved.value,
      },
    },
    value: resolved.value,
    file: resolved.bound ? resolved.file : undefined,
  };
}
