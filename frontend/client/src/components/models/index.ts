/**
 * Models module — the three-tab Models surface (训练 / 模型库 / 分子学习), the
 * model object, the training launcher, and the inference→viewer routing.
 */
export { ModelsPanel, MODELS_TRACKS, HOUSE_STYLE_HIDDEN, TrainingRuns } from "./models-panel"
export type {
  ModelsPanelProps,
  TrainData,
  TrainRun,
  OptimiseData,
  OptimiseSurrogate,
  OptimiseRound,
  OptimiseProposal,
} from "./models-panel"
export { ModelObject, ModelObjectLoader } from "./model-object"
export { RunPretrained } from "./run-pretrained"
export { TrainingLauncher } from "./training-launcher"
export { CodeSandboxPath } from "./code-sandbox-path"
export { FoldOutputs } from "./fold-outputs"
export * from "./training-logic"
export { InferenceResultView } from "./inference-result"
export {
  useModels,
  useModel,
  useInfer,
  useInferenceResult,
  useTrainTrack,
  useOptimiseTrack,
  useRunStatus,
  launchTraining,
  TrainingLaunchError,
} from "./models-api"
export type { InferArgs, TrainingPlan, TrainingPlanRequest, RunStatus } from "./models-api"
export * from "./types"
