import 'express-session';

declare module 'express-session' {
  interface SessionData {
    galaxyHistoryId?: string;
    uploadedDatasets?: Array<{
      dataset_id: string;
      galaxy_dataset_id: string;
      name: string;
      description: string;
      file_type: string;
      file_size: number;
    }>;
    workflowJobs?: Record<string, {
      job_id: string;
      tool_id: string;
      state: string;
      started_at: string;
    }>;
  }
}
