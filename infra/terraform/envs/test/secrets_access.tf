# Allow the BioMateEc2DeployRole to read the RDS connection secret.
# Inline policy added to the existing role; doesn't replace its other policies.
#
# The role is shared across envs, so test/stage/prod each contribute their own
# secret-read policy that scopes the resource ARN to the env's secret(s).

resource "aws_iam_role_policy" "test_secrets_read" {
  name = "test-biomate-secrets-read"
  role = "BioMateEc2DeployRole"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadTestEnvSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        # Galaxy boot fetches these at startup:
        #   * test/biomate/rds-galaxy — Postgres DSN (deploy.sh writes to .env)
        #   * biomate/lago/api-key   — Lago metering key (lago_client.py imports
        #                              at module-load; missing → boot crash)
        # The lago key is org-wide (not env-scoped) because Lago itself is a
        # single hosted instance shared across envs. Adding env-scoped wrappers
        # later is a P2.3 follow-up; for now this matches the documented
        # CLAUDE.md billing topology.
        Resource = [
          aws_secretsmanager_secret.rds_galaxy.arn,
          "arn:aws:secretsmanager:us-west-2:399683337364:secret:biomate/lago/api-key-*",
          # Consolidated Galaxy backend env-var bundle (KEY=VAL JSON).
          # deploy.sh fetches and writes each key into /opt/biomate/.env.
          "arn:aws:secretsmanager:us-west-2:399683337364:secret:test/biomate/galaxy-env-*",
        ]
      }
    ]
  })
}
