/**
 * Last-mile guard for requests that explicitly prohibit computation.
 *
 * Intent classification is model-based and deliberately permissive for scientific
 * workflows.  That is useful for underspecified "PBPK" or "ADMET" requests, but
 * it must never override an unambiguous instruction such as "do not launch a
 * workflow; interpret these PK values only".  Keep this small and deterministic
 * so it can be applied after all domain-specific routing overrides.
 */

const NO_EXECUTION = /\b(?:(?:do\s+not|don't|dont|without)\s+(?:run(?:ning)?|launch(?:ing)?|execute|execut(?:ing|ion)|start(?:ing)?|submit(?:ting)?|trigger(?:ing)?)|no\s+(?:run|launch|execution|compute|computation|simulation|workflow|pipeline|job))\b/i;

const EXECUTION_OBJECT = /\b(?:nextflow|workflow|pipeline|job|compute|simulation|analysis|pbpk|model)\b/i;

/**
 * True when the user has explicitly ruled out launching a computational job.
 *
 * The object is optional ("don't run it") because the action itself is already
 * unambiguous.  We intentionally do not treat ordinary explanatory language as
 * a prohibition: "explain how to run PBPK" and "don't just explain PBPK" both
 * remain eligible for their normal routes.
 */
export function prohibitsWorkflowExecution(message: string): boolean {
  if (!NO_EXECUTION.test(message)) return false;

  // A direct prohibition ("do not run") is enough. The object check documents
  // the common workflow forms and keeps this helper readable for future changes.
  return EXECUTION_OBJECT.test(message) || /\b(?:do\s+not|don't|dont)\s+(?:run|launch|execute|start|submit|trigger)\s+(?:it|this|anything)\b/i.test(message) ||
    /\b(?:interpret|explain|assess|evaluate|review|summari[sz]e|what\s+does)\b/i.test(message);
}

/**
 * Interpretation language is used only to label the resulting chat response;
 * `prohibitsWorkflowExecution` is the safety-critical execution decision.
 */
export function isInterpretationOnlyRequest(message: string): boolean {
  return prohibitsWorkflowExecution(message) &&
    /\b(?:interpret|interpretation|explain|assess|evaluate|review|summari[sz]e|what\s+(?:does|do)|mean(?:ing)?|implication)\b/i.test(message);
}
