# Optional scheduled GPU pre-warm (Step 8): EventBridge → Lambda sets GPU node group desired capacity.
# Enable with: enable_gpu_prewarm = true

locals {
  gpu_prewarm_cluster_name   = aws_eks_cluster.this.name
  gpu_prewarm_nodegroup_name = "gpu-inference"
}

data "archive_file" "gpu_prewarm_lambda" {
  count = var.enable_gpu_prewarm ? 1 : 0

  type        = "zip"
  source_file = "${path.module}/lambda/gpu-prewarm/main.py"
  output_path = "${path.module}/lambda/gpu-prewarm/function.zip"
}

resource "aws_iam_role" "gpu_prewarm_lambda" {
  count = var.enable_gpu_prewarm ? 1 : 0

  name = "${var.project_prefix}-gpu-prewarm-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "gpu_prewarm_lambda" {
  count = var.enable_gpu_prewarm ? 1 : 0

  name   = "invoke"
  role   = aws_iam_role.gpu_prewarm_lambda[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["eks:DescribeNodegroup"]
        Resource = aws_eks_node_group.gpu_inference.arn
      },
      {
        Effect   = "Allow"
        Action   = ["autoscaling:SetDesiredCapacity", "autoscaling:DescribeAutoScalingGroups"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "gpu_prewarm" {
  count = var.enable_gpu_prewarm ? 1 : 0

  function_name = "${var.project_prefix}-gpu-prewarm"
  role          = aws_iam_role.gpu_prewarm_lambda[0].arn
  handler       = "main.handler"
  runtime       = "python3.12"
  timeout       = 30

  filename         = data.archive_file.gpu_prewarm_lambda[0].output_path
  source_code_hash = data.archive_file.gpu_prewarm_lambda[0].output_base64sha256

  environment {
    variables = {
      EKS_CLUSTER_NAME   = local.gpu_prewarm_cluster_name
      EKS_NODEGROUP_NAME = local.gpu_prewarm_nodegroup_name
    }
  }
}

# 14:00 UTC (= 09:00 EST / America/New_York) → set GPU desired = 1
resource "aws_cloudwatch_event_rule" "gpu_prewarm_start" {
  count = var.enable_gpu_prewarm ? 1 : 0

  name                = "${var.project_prefix}-gpu-prewarm-start"
  description         = "Set GPU node group desired capacity to 1 (pre-warm start)"
  schedule_expression = "cron(0 14 * * ? *)"
}

resource "aws_cloudwatch_event_target" "gpu_prewarm_start" {
  count = var.enable_gpu_prewarm ? 1 : 0

  rule      = aws_cloudwatch_event_rule.gpu_prewarm_start[0].name
  target_id = "Lambda"
  arn       = aws_lambda_function.gpu_prewarm[0].arn
  input     = jsonencode({ desired_capacity = var.gpuprewarm_desired_capacity })
}

# 17:00 UTC (= 12:00 EST / America/New_York) → set GPU desired = 0
resource "aws_cloudwatch_event_rule" "gpu_prewarm_end" {
  count = var.enable_gpu_prewarm ? 1 : 0

  name                = "${var.project_prefix}-gpu-prewarm-end"
  description         = "Set GPU node group desired capacity to 0 (pre-warm end)"
  schedule_expression = "cron(0 17 * * ? *)"
}

resource "aws_cloudwatch_event_target" "gpu_prewarm_end" {
  count = var.enable_gpu_prewarm ? 1 : 0

  rule      = aws_cloudwatch_event_rule.gpu_prewarm_end[0].name
  target_id = "Lambda"
  arn       = aws_lambda_function.gpu_prewarm[0].arn
  input     = jsonencode({ desired_capacity = 0 })
}

resource "aws_lambda_permission" "gpu_prewarm_start" {
  count = var.enable_gpu_prewarm ? 1 : 0

  statement_id  = "AllowExecutionFromEventBridgeStart"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.gpu_prewarm[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.gpu_prewarm_start[0].arn
}

resource "aws_lambda_permission" "gpu_prewarm_end" {
  count = var.enable_gpu_prewarm ? 1 : 0

  statement_id  = "AllowExecutionFromEventBridgeEnd"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.gpu_prewarm[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.gpu_prewarm_end[0].arn
}
