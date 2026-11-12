import type { ProjectFile } from "@/components/project-file-tree"
import type { DatasetRef } from "./dataset-object"

/** A project file row as the dataset object view consumes it (Data page and the chat's file panel). */
export function toDatasetRef(f: ProjectFile): DatasetRef {
  return {
    id: f.id,
    name: f.name,
    ref: f.s3_key || null,
    // project_files.size is BIGINT → node-postgres returns it as a STRING, so
    // coerce to a real number here (the DatasetRef.size type expects one, and a
    // string silently failed the header size-badge's typeof guard).
    size: f.size == null ? null : Number(f.size),
    contentType: f.content_type || null,
    source: f.source,
    accession: (f.input_context?.accession as string | undefined) ?? null,
    runId: f.run_id,
    workflowName: f.workflow_name,
    stepName: f.step_name,
    createdAt: f.created_at,
    contentHash: f.content_hash ?? null,
  }
}
