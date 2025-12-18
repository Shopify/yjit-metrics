# Put all the tokens yjit-metrics might need in one json blob.

resource "aws_secretsmanager_secret" "yjit-benchmarking" {
  name        = var.secret_name
  description = "Secrets for automated yjit benchmarking (git, slack, etc)"

  # Disable recovery to allow terraform to destroy and recreate at will.
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "yjit-benchmarking" {
  secret_id = aws_secretsmanager_secret.yjit-benchmarking.id
  secret_string = jsonencode({
    "git-email"                 = var.git_email,
    "git-token"                 = var.git_token,
    "git-user"                  = var.git_user,
    "git-name"                  = var.git_name,
    "slack-token"               = var.slack_token,
    "rubybench-data-deploy-key" = var.rubybench_data_deploy_private_key,
  })
}
