# BioMate Infrastructure-as-Code (Terraform)

Single source of truth for all AWS resources backing dev / test / stage / prod.

```
infra/terraform/
├── modules/                  reusable building blocks
│   ├── ec2_app/              EC2 + SG + idle alarm for an app host
│   ├── github_oidc_role/     OIDC provider + role for GHA ECR push (singleton)
│   └── ec2_deploy_profile/   IAM role + instance profile for app hosts
└── envs/
    ├── dev/                  imports of existing dev resources (EC2 i-06696b0d...)
    ├── test/                 imports of existing test resources (EC2 i-0482a6fa..., stage-public DNS)
    ├── stage/                empty for now; provisioned in P2.4
    └── prod/                 empty for now; provisioned in P4.1
```

## State backend

Each env's state lives at `s3://biomate-terraform-state/<env>/terraform.tfstate`
with `biomate-terraform-lock` DynamoDB table for state locking. SSE-AES256,
versioning on, public access blocked.

```bash
# bucket + table were created on 2026-05-18 via aws-cli (one-time bootstrap).
# To recreate from scratch see infra/terraform/bootstrap_state.md (TODO).
```

## Conventions

- Resource names: `biomate-<env>-<resource>` (e.g. `biomate-test-app-sg`).
- Tags on every resource: `Name`, `Env`, `ManagedBy=terraform`.
- IAM role names that span envs (e.g. `GitHubActionsECRPush`) live in their own
  bootstrap stack so they aren't deleted by a single env's destroy.

## Usage

```bash
cd infra/terraform/envs/test
terraform init
terraform plan          # should be a no-op after the initial import session
terraform apply         # apply any drift back to TF-defined config
```

## Phase status (per `docs/20260514_CICD_REBUILD_PLAN.md`)

- **P2.1 (this PR)**: skeleton + import existing dev/test resources. Plans
  are no-op after import; no changes applied.
- **P2.4**: add stage env (Route53 A record on `stage-public.biomate.ai`, EC2,
  SG, ALB+ACM cert, idle alarm).
- **P4.1**: add prod env on `platform.biomate.ai`.

## Out of scope (deferred — see plan §6)

- Lago + Java billing on `35.86.137.71` (standalone, untouched).
- GPU compute environments + AWS Batch + CryoSPARC remote. A `gpu_compute_env`
  placeholder module is reserved in `modules/` so future-us doesn't forget
  the missing-ECS-GPU-AMI issue (L19 in plan).
