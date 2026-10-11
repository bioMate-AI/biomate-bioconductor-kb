/**
 * Last-mile guard for requests that explicitly prohibit computation.
 *
 * Intent classification is model-based and deliberately permissive for scientific
 * workflows.  That is useful for underspecified "PBPK" or "ADMET" requests, but
 * it must never override an unambiguous instruction such as "do not launch a
 * workflow; interpret these PK values only".  Keep this small and deterministic
 * so it can be applied after all domain-specific routing overrides.
 */

const NO_EXECUTION = /\b(?:(?:do\s+not|don't|dont|without)\s+(?:run(?:ning)?|launch(?:ing)?|execute|execut(?:ing|ion)|start(?:ing)?|submit(?:ting)?|trigger(?:ing)?|generat(?:e|ing|ion)|creat(?:e|ing|ion))|no\s+(?:run|launch|execution|compute|computation|simulation|workflow|pipeline|job))\b/i;

// Objects accept plurals ("do not launch the jobs") — broadening this only makes the
// launch-prohibition detection MORE conservative (it never loosens a launch block).
const EXECUTION_OBJECT = /\b(?:nextflow|workflows?|pipelines?|jobs?|compute|simulations?|analys[ei]s|pbpk|models?)\b/i;

// The English classifier has historically been used for these requests, but
// an explicit Chinese instruction must be just as authoritative.  Keep this
// deliberately limited to an imperative plus a workflow/compute object so a
// normal scientific discussion of e.g. "PBPK 模拟" is not suppressed.
const CHINESE_NO_EXECUTION = /(?:不要|别|无需|不需要)\s*(?:运行|执行|启动|提交|生成|创建|发起)\s*(?:任何\s*)?(?:PBPK|Nextflow|工作流|流程|任务|计算|模拟|分析)/u;

/**
 * True when the user has explicitly ruled out launching a computational job.
 *
 * The object is optional ("don't run it") because the action itself is already
 * unambiguous.  We intentionally do not treat ordinary explanatory language as
 * a prohibition: "explain how to run PBPK" and "don't just explain PBPK" both
 * remain eligible for their normal routes.
 */
export function prohibitsWorkflowExecution(message: string): boolean {
  if (CHINESE_NO_EXECUTION.test(message)) return true;
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
    /\b(?:interpret|interpretation|explain|assess|evaluate|review|summari[sz]e|what\s+(?:does|do)|mean(?:ing)?|implication)\b|(?:解释|解读|评估|分析|说明|含义)/iu.test(message);
}

// A prohibition on *generating/drafting* a plan — distinct from prohibiting its
// launch. Only generation verbs (generate/create/build/draft/produce/write),
// never run/launch/execute, so "do not launch the jobs" does NOT match here.
const NO_GENERATION = /\b(?:do\s+not|don't|dont|without|refrain\s+from|no\s+need\s+to)\s+(?:generat(?:e|ing|ion)|creat(?:e|ing|ion)|build(?:ing)?|draft(?:ing)?|produc(?:e|ing)|writ(?:e|ing)|author(?:ing)?)\b/i;
const CHINESE_NO_GENERATION = /(?:不要|别|无需|不需要)\s*(?:生成|创建|编写|起草|制作|构建)\s*(?:任何\s*)?(?:新的\s*)?(?:工作流|流程|方案|计划|pipeline|workflow)?/u;

/**
 * True when the user explicitly rules out *generating/drafting* a workflow or
 * plan at all — distinct from `prohibitsWorkflowExecution`, which only prohibits
 * launching. "Draft the plan, but do not launch the jobs yet" must still PRODUCE
 * a plan, so a launch prohibition alone must never suppress generation; only an
 * explicit generation prohibition (or an interpretation-only request) may.
 */
export function prohibitsWorkflowGeneration(message: string): boolean {
  return CHINESE_NO_GENERATION.test(message) || NO_GENERATION.test(message);
}
