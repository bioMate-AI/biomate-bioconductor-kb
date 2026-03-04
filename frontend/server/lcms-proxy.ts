/**
 * LC-MS Agent Proxy
 * Thin HTTP client wrapping the LC-MS microservice API.
 * Used by BioMate's main chat to route mass-spectrometry queries.
 */
import axios, { AxiosInstance } from 'axios';

export interface LCMSAgentRequest {
  query: string;
  agent_type?: string;
  session_id?: string;
  context?: Record<string, any>;
  data_files?: string[];
  metadata?: Record<string, any>;
}

export interface LCMSAgentResponse {
  agent_type: string;
  content: string;
  actions_taken: string[];
  recommendations: string[];
  follow_up_questions: string[];
  requires_user_input: boolean;
  confidence: number;
  session_id: string;
  metadata: Record<string, any>;
}

export interface LCMSMethodologyRequest {
  application: string;
  sample_type?: string;
  analysis_type?: string;
  instrument?: string;
  session_id?: string;
}

export interface LCMSHealthStatus {
  status: string;
  service: string;
  version?: string;
}

export class LCMSProxy {
  private client: AxiosInstance;
  private baseUrl: string;
  public isAvailable: boolean = false;

  constructor() {
    this.baseUrl = process.env.LCMS_AGENT_URL || 'http://localhost:8000';
    this.client = axios.create({
      baseURL: this.baseUrl,
      timeout: 60000,
      headers: { 'Content-Type': 'application/json' },
    });
    // Non-blocking health check on startup
    this.checkHealth().catch(() => {});
  }

  async checkHealth(): Promise<LCMSHealthStatus> {
    try {
      const res = await this.client.get<LCMSHealthStatus>('/api/health/');
      this.isAvailable = res.data.status === 'healthy' || res.data.status === 'ok';
      return res.data;
    } catch {
      this.isAvailable = false;
      return { status: 'unavailable', service: 'lc-ms-agent' };
    }
  }

  async query(req: LCMSAgentRequest): Promise<LCMSAgentResponse> {
    const res = await this.client.post<LCMSAgentResponse>('/api/agents/query', req);
    return res.data;
  }

  async designMethodology(req: LCMSMethodologyRequest): Promise<LCMSAgentResponse> {
    const res = await this.client.post<LCMSAgentResponse>('/api/agents/methodology', req);
    return res.data;
  }

  async troubleshoot(req: {
    issue_description: string;
    error_logs?: string;
    instrument?: string;
  }): Promise<LCMSAgentResponse> {
    const res = await this.client.post<LCMSAgentResponse>('/api/agents/troubleshoot', req);
    return res.data;
  }

  async planWorkflow(req: {
    requirements: string;
    data_files?: string[];
    workflow_type?: string;
  }): Promise<LCMSAgentResponse> {
    const res = await this.client.post<LCMSAgentResponse>('/api/agents/workflow', req);
    return res.data;
  }

  async listAgents(): Promise<Record<string, any>> {
    const res = await this.client.get('/api/agents/agents');
    return res.data;
  }
}

export const lcmsProxy = new LCMSProxy();
