# On premises configuration coverage

This is a coverage matrix, not a template to upload. Script-local names and document-only names require review. A value in .env is ineffective unless Compose passes it to the relevant service.

| Name | Git manifest | On prem template | Approved container services | Literal code read | Secret review |
|---|---|---|---|---|---|
| `ALLOWED_BUCKETS` | no | no | — | no | — |
| `ANTHROPIC_API_KEY` | yes | yes | frontend, galaxy-backend | yes | review |
| `APP_URL` | yes | yes | frontend | yes | — |
| `AWS_ACCESS_KEY_ID` | yes | yes | frontend, galaxy-backend, minio-init | yes | review |
| `AWS_DEFAULT_REGION` | yes | yes | galaxy-backend | yes | — |
| `AWS_REGION` | yes | no | frontend | yes | — |
| `AWS_SECRET_ACCESS_KEY` | yes | yes | frontend, galaxy-backend, minio-init | yes | review |
| `BACKUP_DIR` | no | no | — | no | — |
| `BILLING_INTERNAL_KEY` | yes | yes | frontend, galaxy-backend | yes | review |
| `BILLING_LAGO_ENABLED` | no | yes | frontend, galaxy-backend | yes | — |
| `BIOMATE_ADMET_CONTAINER` | no | no | galaxy-backend | yes | — |
| `BIOMATE_BACKEND_IMAGE` | no | yes | — | no | — |
| `BIOMATE_BIOC_CONTAINER` | no | yes | galaxy-backend | yes | — |
| `BIOMATE_BIOMNI_TOOLS_IMAGE` | no | yes | — | no | — |
| `BIOMATE_DB_URL` | no | yes | db-init | no | — |
| `BIOMATE_DOCKER_NETWORK` | no | no | galaxy-backend | yes | — |
| `BIOMATE_FRONTEND_IMAGE` | no | yes | — | no | — |
| `BIOMATE_LICENSE_KEY` | no | yes | frontend, galaxy-backend | yes | review |
| `BIOMATE_LICENSE_SECRET` | no | yes | frontend, galaxy-backend | yes | review |
| `BIOMATE_LOCAL_REGISTRY` | no | yes | galaxy-backend | no | — |
| `BIOMATE_MINIO_IMAGE` | no | no | — | no | — |
| `BIOMATE_MINIO_MC_IMAGE` | no | no | — | no | — |
| `BIOMATE_NFCORE_URL` | no | yes | nfcore-init | no | — |
| `BIOMATE_VERSION` | no | no | — | yes | — |
| `BIOMATE_WORKFLOW_TOOLS_IMAGE` | no | yes | — | no | — |
| `BLUE` | no | no | — | no | — |
| `BOLD` | no | no | — | no | — |
| `CORS_ORIGINS` | yes | yes | frontend | yes | — |
| `CPU_MODEL` | no | no | — | no | — |
| `CYN` | no | no | — | no | — |
| `DATABASE_URL` | yes | no | frontend | yes | review |
| `DEEPSEEK_API_KEY` | no | yes | frontend, galaxy-backend | yes | review |
| `DISABLE_GOOGLE_FONTS` | no | no | — | no | — |
| `DISK_FREE_GB` | no | no | — | no | — |
| `DOCKER_DEFAULT_PLATFORM` | no | no | galaxy-backend | yes | — |
| `DOCKER_GID` | no | yes | — | no | — |
| `EMAIL_FROM` | yes | yes | frontend | yes | — |
| `EMAIL_HOST` | yes | yes | frontend | yes | — |
| `EMAIL_PASS` | yes | yes | frontend | yes | review |
| `EMAIL_PORT` | yes | yes | frontend | yes | — |
| `EMAIL_SECURE` | yes | yes | frontend | yes | — |
| `EMAIL_USER` | yes | yes | frontend | yes | — |
| `ENABLE_HSTS` | yes | yes | frontend | yes | — |
| `ENV_FILE` | no | no | — | no | — |
| `FORCE_HTTPS` | yes | yes | frontend | yes | — |
| `FRONTEND_PORT` | no | yes | — | no | — |
| `FRONTEND_URL` | no | yes | frontend, galaxy-backend | yes | — |
| `FRP_VER` | no | no | — | no | — |
| `GALAXY_AI_LLM_MODEL` | no | yes | frontend, galaxy-backend | yes | — |
| `GALAXY_AI_LLM_PROVIDER` | no | yes | frontend, galaxy-backend | yes | — |
| `GALAXY_API_KEY` | yes | yes | frontend | yes | review |
| `GALAXY_CONFIG_FILE` | no | no | galaxy-backend | yes | — |
| `GALAXY_CONFIG_OVERRIDE_BOOTSTRAP_ADMIN_API_KEY` | no | no | galaxy-backend | no | review |
| `GALAXY_CONFIG_OVERRIDE_INVOLUCRO_AUTO_INIT` | no | no | galaxy-backend | no | — |
| `GALAXY_PORT` | no | no | — | no | — |
| `GALAXY_URL` | yes | no | frontend | yes | — |
| `GHCR_TOKEN` | no | yes | — | no | review |
| `GHCR_TOKEN_USER` | no | no | — | no | review |
| `GHCR_USER` | no | yes | — | no | — |
| `GREEN` | no | no | — | no | — |
| `GRN` | no | no | — | no | — |
| `HOST_ARCH` | no | no | — | no | — |
| `HOST_ARCH_NORM` | no | no | — | no | — |
| `HOST_IP` | no | no | — | no | — |
| `JWT_SECRET` | yes | yes | frontend | yes | review |
| `LAGO_API_KEY` | yes | no | galaxy-backend | yes | review |
| `LLM_API_KEY` | no | yes | frontend, galaxy-backend | yes | review |
| `LLM_API_URL` | no | yes | frontend, galaxy-backend | yes | — |
| `LLM_MODEL` | no | yes | frontend, galaxy-backend | yes | — |
| `LOG_LINES` | no | no | — | no | — |
| `MEM_GB` | no | no | — | no | — |
| `MINIO_ROOT_PASSWORD` | no | yes | minio | yes | review |
| `MINIO_ROOT_USER` | no | yes | minio | yes | — |
| `MKL_CBWR` | no | no | — | no | — |
| `MKL_DEBUG_CPU_TYPE` | no | yes | galaxy-backend | no | — |
| `MKL_ENABLE_INSTRUCTIONS` | no | yes | galaxy-backend | no | — |
| `NC` | no | no | — | no | — |
| `NEXTFLOW_DOCKER_GPU_OPTIONS` | no | yes | — | no | — |
| `NEXTFLOW_EXECUTOR` | no | yes | galaxy-backend | yes | — |
| `NEXTFLOW_USE_AWS` | yes | yes | frontend, galaxy-backend | yes | — |
| `NEXTFLOW_WORK_DIR` | no | yes | frontend, galaxy-backend | yes | — |
| `NODE_ENV` | yes | no | frontend | yes | — |
| `NXF_K8S_GPU_RESOURCE` | no | yes | — | yes | — |
| `NXF_K8S_NAMESPACE` | no | yes | — | yes | — |
| `NXF_K8S_PULL_POLICY` | no | yes | — | yes | — |
| `NXF_K8S_SERVICE_ACCOUNT` | no | yes | — | yes | — |
| `NXF_K8S_STORAGE_CLAIM` | no | yes | — | yes | — |
| `NXF_K8S_STORAGE_MOUNT` | no | yes | — | yes | — |
| `OLLAMA_BASE_URL` | no | yes | frontend, galaxy-backend | yes | — |
| `ONPREM_DELIVERY_CHECKLIST` | no | no | — | no | — |
| `ONPREM_SETUP` | no | no | — | no | — |
| `OPENAI_API_BASE_URL` | no | no | — | no | — |
| `OPENAI_API_KEY` | yes | yes | frontend, galaxy-backend | yes | review |
| `OPENBLAS_CORETYPE` | no | yes | galaxy-backend | no | — |
| `OPENROUTER_API_KEY` | no | yes | frontend, galaxy-backend | yes | review |
| `OSS_ACCESS_KEY_ID` | no | no | — | no | review |
| `OSS_ACCESS_KEY_SECRET` | no | no | — | no | review |
| `PORT` | no | no | frontend | yes | — |
| `POSTGRES_DB` | yes | yes | postgres | no | — |
| `POSTGRES_PASSWORD` | yes | yes | postgres | no | review |
| `POSTGRES_USER` | yes | yes | postgres | no | — |
| `PUBLIC_IP` | no | no | — | no | — |
| `PYTHONUNBUFFERED` | no | no | galaxy-backend | no | — |
| `RED` | no | no | — | no | — |
| `REDIS_URL` | yes | no | frontend, galaxy-backend | yes | review |
| `REGISTRY_STORAGE_DELETE_ENABLED` | no | no | registry | no | — |
| `RESET` | no | no | — | no | — |
| `RUN_STATE_STORE` | no | no | galaxy-backend | yes | — |
| `S3_BUCKET_NAME` | yes | yes | frontend, galaxy-backend, minio-init | yes | — |
| `S3_ENDPOINT_URL` | no | yes | frontend, galaxy-backend | yes | — |
| `S3_FORCE_PATH_STYLE` | no | yes | frontend, galaxy-backend | yes | — |
| `SESSION_SECRET` | yes | yes | frontend | yes | review |
| `SLURM_ACCOUNT` | no | yes | — | yes | — |
| `SLURM_PARTITION` | no | yes | — | yes | — |
| `SLURM_QOS` | no | yes | — | yes | — |
| `SLURM_WORK_DIR` | no | yes | — | yes | — |
| `STRIPE_SECRET_KEY` | no | yes | frontend | yes | review |
| `TIMESTAMP` | no | no | — | no | — |
| `WORKFLOW_NOTIFY` | no | yes | frontend | no | — |
| `YELLOW` | no | no | — | no | — |
| `YLW` | no | no | — | no | — |
| `YYYYMMDD_HHMMSS` | no | no | — | no | — |
| `ZHIPU_API_KEY` | no | yes | frontend, galaxy-backend | yes | review |
| `_FE_PORT` | no | no | — | no | — |
