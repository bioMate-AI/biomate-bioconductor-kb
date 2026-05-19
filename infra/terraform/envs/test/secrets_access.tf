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
        Resource = [aws_secretsmanager_secret.rds_galaxy.arn]
      }
    ]
  })
}
