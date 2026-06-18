import 'express-session';

declare module 'express-session' {
  interface SessionData {
    galaxyHistoryId?: string;
    uploadedDatasets?: Array<{
      dataset_id: string;
      galaxy_dataset_id?: string;
      name: string;
      description: string;
      file_type: string;
      file_size: number;
      /** Absolute local path for uploaded files — Nextflow executor reads this directly */
      file_path?: string;
      /** Durable S3 URI mirror — the only upload reference that survives a server restart
       *  and is directly usable by AWS Batch (file_path is host-local). */
      s3_uri?: string;
      /** Original URL for URL-imported datasets — Nextflow can fetch http/https/s3 directly */
      source_url?: string;
    }>;
    workflowJobs?: Record<string, {
      job_id: string;
      tool_id: string;
      state: string;
      started_at: string;
    }>;
    lastActivity?: string;
  }
}
