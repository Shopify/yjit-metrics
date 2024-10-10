resource "aws_iam_role" "yjit-benchmarking-instance-profile" {
  name = "yjit-benchmarking"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole"
        ]
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  # Allow the instance to read the secret we created (for git, slack, etc).
  inline_policy {
    name = "yjit-secrets"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = [
            "secretsmanager:GetSecretValue"
          ]
          Effect = "Allow"
          Resource = [
            resource.aws_secretsmanager_secret.yjit-benchmarking.arn,
          ]
        },
      ]
    })
  }

  max_session_duration = var.instance_profile_session_duration_seconds
}

resource "aws_iam_instance_profile" "yjit-benchmarking" {
  name = "yjit-benchmarking"
  role = aws_iam_role.yjit-benchmarking-instance-profile.name
}

resource "aws_iam_policy" "job-bot" {
  name        = "yjit-benchmark-bot"
  path        = "/"
  description = "Permissions for Job to launch instances and initiate benchmarking"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeLaunchTemplates",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "ec2:StartInstances",
          "ec2:StopInstances",
        ]
        Effect   = "Allow"
        Resource = [
          aws_instance.benchmarking["x86"].arn,
          aws_instance.benchmarking["arm"].arn,
          aws_instance.reporting.arn,
        ]
      },
    ]
  })
}

resource "aws_iam_user_policy_attachment" "job-bot" {
  user       = var.job_bot_user_name
  policy_arn = aws_iam_policy.job-bot.arn
}
