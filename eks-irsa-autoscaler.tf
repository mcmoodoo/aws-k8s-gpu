# IRSA for Cluster Autoscaler so the pod has AWS credentials (fixes NoCredentialProviders).
# The Helm chart uses the service account role when annotated; node instance profile is no longer required for the autoscaler.

data "tls_certificate" "eks" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
}

locals {
  oidc_provider = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
}

resource "aws_iam_role" "cluster_autoscaler" {
  name = "${var.project_prefix}-cluster-autoscaler-irsa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_provider}:aud" = "sts.amazonaws.com"
            # Chart default SA can be "cluster-autoscaler" or "cluster-autoscaler-aws-cluster-autoscaler" depending on chart version
            "${local.oidc_provider}:sub" = [
              "system:serviceaccount:kube-system:cluster-autoscaler",
              "system:serviceaccount:kube-system:cluster-autoscaler-aws-cluster-autoscaler"
            ]
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "cluster_autoscaler" {
  name   = "cluster-autoscaler"
  role   = aws_iam_role.cluster_autoscaler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeTags",
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = [
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:DescribeImages"
        ]
        Resource = "*"
      }
    ]
  })
}
