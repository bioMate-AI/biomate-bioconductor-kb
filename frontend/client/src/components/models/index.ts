/**
 * Models module — the 5-track Models surface, the model object, and the
 * "Run a pre-trained model" inference→viewer routing.
 */
export { ModelsPanel, MODELS_TRACKS } from "./models-panel"
export type {
  ModelsPanelProps,
  TrainData,
  TrainRun,
  AdaptData,
  AdaptPair,
  OptimiseData,
  OptimiseSurrogate,
  OptimiseRound,
  OptimiseProposal,
} from "./models-panel"
export { ModelObject, ModelObjectLoader } from "./model-object"
export { RunPretrained } from "./run-pretrained"
export { InferenceResultView } from "./inference-result"
export {
  useModels,
  useModel,
  useInfer,
  useInferenceResult,
  useTrainTrack,
  useAdaptTrack,
  useOptimiseTrack,
} from "./models-api"
export type { InferArgs } from "./models-api"
export * from "./types"
