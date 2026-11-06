/** A workflow path identifies code, not a requested execution.
 * Two intents can use the same code with different inhibitors, targets or inputs.
 */
export function additionalIntentWorkflows<T extends { generatedWorkflow?: any }>(
  results: T[], primary: T | undefined, isRunnable: (workflow: any) => boolean,
): any[] {
  return results.filter(result => result !== primary && isRunnable(result.generatedWorkflow))
    .map(result => result.generatedWorkflow);
}

export function workflowIntent(subQuery: string, originalMessage: string): string {
  return subQuery.trim() || originalMessage;
}
