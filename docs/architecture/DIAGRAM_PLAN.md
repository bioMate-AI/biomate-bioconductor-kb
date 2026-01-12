# BioMate Architecture Diagrams Plan

**Purpose:** Comprehensive draw.io diagrams for onboarding new team members
**Format:** XML files compatible with draw.io (diagrams.net)

---

## Diagram List

### 1. Overall System Architecture
**File:** `01_overall_system_architecture.drawio.xml`

**Content:**
- High-level view of entire BioMate platform
- Three main layers: Frontend, Backend, External Services
- Key components: React UI, Galaxy Server, Biomni Tools, LLM Services, Databases
- Network boundaries and deployment zones
- User entry points

**Information Flow:**
- User → Frontend → Backend API → Galaxy → Tools → Results → User
- LLM queries: Backend → Ollama/Anthropic → Response

---

### 2. Frontend Architecture
**File:** `02_frontend_architecture.drawio.xml`

**Content:**
- React application structure
- Key components: Chat Interface, Workflow Artifact, Parameter Dialog
- State management (hooks: useWorkflowExecution)
- API communication layer
- SSE (Server-Sent Events) for real-time updates

**Information Flow:**
- User Input → Chat Interface → API Call → Backend
- Backend → SSE → Workflow Status Updates → UI Render

---

### 3. Backend Architecture
**File:** `03_backend_architecture.drawio.xml`

**Content:**
- Galaxy server core
- AI Assistant module
- Workflow Generator
- Tool execution pipeline
- Database connections (SQLite, PostgreSQL)

**Information Flow:**
- API Request → Router → Service Layer → Galaxy Core → Tool Execution
- Tool Results → History Manager → Response

---

### 4. Biomni Tool Framework
**File:** `04_biomni_tool_framework.drawio.xml`

**Content:**
- Tool categories (21 domains: genomics, biochemistry, etc.)
- Tool structure: XML definition + Python wrapper
- Schema files for database queries
- Docker container execution

**Information Flow:**
- Tool Request → XML Parser → Wrapper Script → Docker Container → Output

---

### 5. Enhanced Database Query Engine
**File:** `05_enhanced_database_query_engine.drawio.xml`

**Content:**
- EnhancedQueryEngine class structure
- LocalDatabaseManager (local files + SQLite cache)
- QueryValidator (schema validation)
- RateLimiter (per-database limits)
- LLM integration for query generation

**Information Flow:**
- Natural Language Query → Local Check → Cache Check → LLM Generation → Validation → Rate Limit → API Call → Cache Store → Result

---

### 6. LLM Integration Architecture
**File:** `06_llm_integration_architecture.drawio.xml`

**Content:**
- Dual LLM support: Ollama (local) + Anthropic (cloud)
- LLM client abstraction (langchain)
- Query generation prompts with schema injection
- Retry with feedback loop

**Information Flow:**
- Prompt + Schema → LLM → JSON Response → Parse → Validate → Execute or Retry

---

### 7. Galaxy Workflow Execution
**File:** `07_galaxy_workflow_execution.drawio.xml`

**Content:**
- Workflow definition structure
- Step execution sequence
- Job scheduling and Docker execution
- History and dataset management

**Information Flow:**
- Workflow Definition → Step Queue → Job Runner → Docker Container → Output Dataset → History

---

### 8. Docker Container Architecture
**File:** `08_docker_container_architecture.drawio.xml`

**Content:**
- biomate/biotools:arm64 container structure
- Installed tools by layer (aligners, quantification, variant calling, etc.)
- Volume mounts for Galaxy integration
- Environment variables for LLM access

**Information Flow:**
- Galaxy Job → Docker Run → Tool Execution → Output Files → Galaxy Dataset

---

### 9. Data Flow Overview
**File:** `09_data_flow_overview.drawio.xml`

**Content:**
- End-to-end data flow from user query to results
- All data transformation points
- Storage locations (cache, history, local files)
- External API interactions

**Information Flow:**
- Complete trace: User Query → Frontend → Backend → Tool → External DB → Cache → Result Display

---

### 10. API Endpoints Map
**File:** `10_api_endpoints_map.drawio.xml`

**Content:**
- All REST API endpoints
- Request/Response formats
- Authentication flow
- SSE subscription endpoints

**Information Flow:**
- Client → /api/ai/chat → AI Assistant → Response
- Client → /api/workflows → Workflow CRUD
- Client → /api/histories → History Management

---

### 11. Memory Management Architecture
**File:** `11_memory_management_architecture.drawio.xml`

**Content:**
- Conversation context management
- Token budget allocation and tracking
- Context window optimization strategies
- Automatic summarization triggers
- Cache memory hierarchy (L1: in-memory, L2: SQLite, L3: disk)
- Memory pressure handling

**Information Flow:**
- New Message → Token Counter → Budget Check → Summarize if needed → Context Window
- Query Result → Cache Decision → Memory Tier Selection → Store/Evict

**Key Components:**
- ConversationMemory: Tracks dialog history with token counts
- ContextWindowManager: Manages LLM context limits
- SummarizationEngine: Compresses old context when needed
- CacheManager: Multi-tier caching with LRU eviction

---

### 12. Test Harness Architecture
**File:** `12_test_harness_architecture.drawio.xml`

**Content:**
- Test framework structure (pytest)
- Test categories: Unit, Integration, E2E, Benchmark
- Mock services for deterministic testing
- CI/CD pipeline integration
- Test data management
- Coverage reporting

**Information Flow:**
- Test Suite → Test Runner → Mock Services → Assertions → Report
- CI Trigger → Test Matrix → Parallel Execution → Results Aggregation

**Key Components:**
- UnitTests: Individual function testing
- IntegrationTests: Component interaction testing
- E2ETests: Full workflow testing with Selenium/Playwright
- BenchmarkTests: Performance regression testing
- MockLLMService: Deterministic LLM responses for testing
- MockAPIService: Simulated external API responses
- TestDataGenerator: Synthetic bioinformatics data

---

### 13. Multi-Environment Infrastructure
**File:** `13_multi_environment_infrastructure.drawio.xml`

**Content:**
- Deployment abstraction layer
- Environment-specific configurations
- Resource provisioning strategies
- Service discovery mechanisms

**Supported Environments:**
- Local single server (development/small lab)
- AWS (EC2, ECS, EKS, Lambda)
- SLURM HPC cluster
- Google Cloud Platform
- Azure
- Hybrid combinations

**Information Flow:**
- Job Request → Environment Detector → Resource Allocator → Execution Backend → Results Collection

---

### 14. AWS Deployment Architecture
**File:** `14_aws_deployment_architecture.drawio.xml`

**Content:**
- VPC and subnet layout
- EC2 instances for Galaxy server
- ECS/EKS for containerized tools
- S3 for data storage
- RDS for database
- Lambda for serverless functions
- API Gateway for external access
- CloudWatch for monitoring
- Auto-scaling configuration

**Information Flow:**
- User → CloudFront → ALB → ECS Tasks → S3/RDS
- Tool Execution → ECS Fargate → S3 Results
- Monitoring → CloudWatch → Alerts

---

### 15. SLURM HPC Integration
**File:** `15_slurm_hpc_integration.drawio.xml`

**Content:**
- SLURM cluster topology
- Job submission from Galaxy
- Resource allocation (nodes, CPUs, GPUs, memory)
- Queue management and priorities
- Shared filesystem (NFS/Lustre)
- Module system integration

**Information Flow:**
- Galaxy Job → SLURM Runner → sbatch → Compute Node → Shared Storage → Galaxy History
- Job Status → squeue polling → Galaxy UI Update

**Key Components:**
- SLURMJobRunner: Galaxy job runner for SLURM
- PartitionSelector: Chooses appropriate queue based on job requirements
- ResourceEstimator: Predicts resource needs from tool parameters
- JobMonitor: Tracks job state and handles failures

---

### 16. Local Single Server Deployment
**File:** `16_local_single_server_deployment.drawio.xml`

**Content:**
- All-in-one server configuration
- Docker Compose setup
- Local PostgreSQL/SQLite
- Nginx reverse proxy
- Local Ollama LLM
- Systemd service management

**Information Flow:**
- User → Nginx → Frontend Container → Backend Container → Galaxy Container → Tool Container

**Key Components:**
- docker-compose.yml structure
- Volume mappings for persistence
- Network configuration
- Resource limits per container

---

### 17. Hybrid Cloud-Local Architecture
**File:** `17_hybrid_cloud_local_architecture.drawio.xml`

**Content:**
- Workload classification (local vs cloud)
- Data locality optimization
- Secure tunnel between local and cloud
- Cost optimization strategies
- Failover mechanisms

**Decision Criteria:**
- Data size: Large datasets stay local, results go to cloud
- Compute intensity: Heavy jobs go to cloud/HPC
- Latency requirements: Interactive queries stay local
- Cost: Burst to cloud when local capacity exceeded
- Compliance: Sensitive data stays on-premises

**Information Flow:**
- Job Request → Workload Classifier → Local Queue OR Cloud Queue
- Local Execution → Local Storage → Sync to Cloud (if needed)
- Cloud Execution → Cloud Storage → Sync to Local (if needed)

**Key Components:**
- WorkloadClassifier: Decides execution location
- DataSyncManager: Handles data movement between environments
- HybridJobScheduler: Unified job queue across environments
- CostOptimizer: Monitors and optimizes cloud spending
- SecureTunnel: VPN/SSH tunnel for cloud communication

---

### 18. Infrastructure Abstraction Layer
**File:** `18_infrastructure_abstraction_layer.drawio.xml`

**Content:**
- Unified API for all deployment targets
- Provider-specific adapters
- Configuration management
- Secrets management
- Infrastructure as Code (Terraform/Pulumi)

**Abstraction Layers:**
```
┌─────────────────────────────────────────┐
│         BioMate Application             │
├─────────────────────────────────────────┤
│      Infrastructure Abstraction API     │
├─────────────────────────────────────────┤
│  ComputeAdapter │ StorageAdapter │ ...  │
├────────┬────────┼────────┬──────┼───────┤
│  AWS   │ GCP    │ Azure  │SLURM │ Local │
└────────┴────────┴────────┴──────┴───────┘
```

**Information Flow:**
- App Request → Abstraction API → Provider Detection → Adapter Selection → Provider-Specific Call

---

## Diagram Style Guide

**Colors:**
- Frontend components: Blue (#4A90D9)
- Backend components: Green (#5CB85C)
- External services: Orange (#F0AD4E)
- Databases: Purple (#9B59B6)
- User actions: Gray (#95A5A6)
- Data flow arrows: Dark gray (#333333)
- AWS components: Orange (#FF9900)
- Local/On-prem: Blue (#0066CC)
- SLURM/HPC: Green (#228B22)
- Hybrid elements: Gradient or split colors

**Shapes:**
- Rectangles: Components/Services
- Cylinders: Databases/Storage
- Rounded rectangles: Processes
- Diamonds: Decision points
- Arrows: Data/Control flow
- Clouds: Cloud services
- Server icons: Physical/virtual machines
- Container icons: Docker containers

**Layout:**
- Left to right for main flow
- Top to bottom for hierarchies
- Swim lanes for different layers/responsibilities
- Dashed lines for optional/conditional paths
- Thick lines for primary data flow

---

## File Structure

```
docs/architecture/
├── DIAGRAM_PLAN.md (this file)
│
├── # Core Architecture (1-10)
├── 01_overall_system_architecture.drawio.xml
├── 02_frontend_architecture.drawio.xml
├── 03_backend_architecture.drawio.xml
├── 04_biomni_tool_framework.drawio.xml
├── 05_enhanced_database_query_engine.drawio.xml
├── 06_llm_integration_architecture.drawio.xml
├── 07_galaxy_workflow_execution.drawio.xml
├── 08_docker_container_architecture.drawio.xml
├── 09_data_flow_overview.drawio.xml
├── 10_api_endpoints_map.drawio.xml
│
├── # Memory & Testing (11-12)
├── 11_memory_management_architecture.drawio.xml
├── 12_test_harness_architecture.drawio.xml
│
├── # Infrastructure & Deployment (13-18)
├── 13_multi_environment_infrastructure.drawio.xml
├── 14_aws_deployment_architecture.drawio.xml
├── 15_slurm_hpc_integration.drawio.xml
├── 16_local_single_server_deployment.drawio.xml
├── 17_hybrid_cloud_local_architecture.drawio.xml
└── 18_infrastructure_abstraction_layer.drawio.xml
```

---

## Priority Order for Creation

### Phase 1: Core Understanding (Essential for onboarding)
1. `01_overall_system_architecture.drawio.xml` - Big picture first
2. `09_data_flow_overview.drawio.xml` - How data moves through system
3. `03_backend_architecture.drawio.xml` - Core system understanding

### Phase 2: Recent Work Documentation
4. `05_enhanced_database_query_engine.drawio.xml` - Recent implementation
5. `11_memory_management_architecture.drawio.xml` - Memory handling
6. `12_test_harness_architecture.drawio.xml` - Testing strategy

### Phase 3: Component Deep Dives
7. `02_frontend_architecture.drawio.xml` - UI components
8. `04_biomni_tool_framework.drawio.xml` - Tool ecosystem
9. `06_llm_integration_architecture.drawio.xml` - AI capabilities
10. `07_galaxy_workflow_execution.drawio.xml` - Workflow engine

### Phase 4: Infrastructure & Deployment
11. `13_multi_environment_infrastructure.drawio.xml` - Overview of all environments
12. `18_infrastructure_abstraction_layer.drawio.xml` - Abstraction design
13. `16_local_single_server_deployment.drawio.xml` - Simplest deployment
14. `14_aws_deployment_architecture.drawio.xml` - Cloud deployment
15. `15_slurm_hpc_integration.drawio.xml` - HPC integration
16. `17_hybrid_cloud_local_architecture.drawio.xml` - Hybrid scenarios

### Phase 5: Reference Diagrams
17. `08_docker_container_architecture.drawio.xml` - Container details
18. `10_api_endpoints_map.drawio.xml` - API reference

---

## Summary Table

| # | Diagram | Category | Priority |
|---|---------|----------|----------|
| 1 | Overall System Architecture | Core | P1 |
| 2 | Frontend Architecture | Core | P3 |
| 3 | Backend Architecture | Core | P1 |
| 4 | Biomni Tool Framework | Core | P3 |
| 5 | Enhanced Database Query Engine | Core | P2 |
| 6 | LLM Integration Architecture | Core | P3 |
| 7 | Galaxy Workflow Execution | Core | P3 |
| 8 | Docker Container Architecture | Core | P5 |
| 9 | Data Flow Overview | Core | P1 |
| 10 | API Endpoints Map | Core | P5 |
| 11 | Memory Management Architecture | Memory/Testing | P2 |
| 12 | Test Harness Architecture | Memory/Testing | P2 |
| 13 | Multi-Environment Infrastructure | Infrastructure | P4 |
| 14 | AWS Deployment Architecture | Infrastructure | P4 |
| 15 | SLURM HPC Integration | Infrastructure | P4 |
| 16 | Local Single Server Deployment | Infrastructure | P4 |
| 17 | Hybrid Cloud-Local Architecture | Infrastructure | P4 |
| 18 | Infrastructure Abstraction Layer | Infrastructure | P4 |

---

## Next Steps

1. Review and approve this plan
2. Create diagrams in priority order
3. Commit each diagram as completed
4. Update main documentation to reference diagrams
5. Create PNG exports for quick viewing in GitHub
