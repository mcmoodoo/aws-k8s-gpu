locals {
  eks_node_role_name = "${var.project_prefix}-eks-node-role"
}

resource "aws_iam_role" "eks_node" {
  name = local.eks_node_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_node_AmazonEKSWorkerNodePolicy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_node_AmazonEKS_CNI_Policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_node_AmazonEC2ContainerRegistryReadOnly" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Cluster Autoscaler: allow nodes to describe/update ASGs (node instance profile approach; IRSA later)
resource "aws_iam_role_policy" "eks_node_cluster_autoscaler" {
  name   = "${var.project_prefix}-cluster-autoscaler"
  role   = aws_iam_role.eks_node.id
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

resource "aws_eks_node_group" "cpu_system" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "cpu-system"
  node_role_arn   = aws_iam_role.eks_node.arn

  subnet_ids = [for s in aws_subnet.public : s.id]

  scaling_config {
    desired_size = 1
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["t3.large"]

  tags = {
    Name           = "${var.project_prefix}-cpu-system"
    "NodePurpose"  = "cpu"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks_node_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks_node_AmazonEC2ContainerRegistryReadOnly,
    aws_eks_cluster.this,
  ]
}

resource "aws_eks_node_group" "gpu_inference" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "gpu-inference"
  node_role_arn   = aws_iam_role.eks_node.arn

  subnet_ids = [for s in aws_subnet.public : s.id]

  scaling_config {
    desired_size = 0
    max_size     = 1
    min_size     = 0
  }

  instance_types = ["g5.4xlarge"]

  # AL2_x86_64_GPU is only supported for Kubernetes 1.32 or earlier; use AL2023 for 1.33+
  ami_type  = "AL2023_x86_64_NVIDIA"
  disk_size = 100

  labels = {
    "node-purpose" = "gpu"
  }

  taint {
    key    = "gpu"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  tags = {
    Name           = "${var.project_prefix}-gpu-inference"
    "NodePurpose"  = "gpu"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks_node_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks_node_AmazonEC2ContainerRegistryReadOnly,
    aws_eks_cluster.this,
  ]
}

# Tag EKS-managed ASGs so Cluster Autoscaler can discover them (run after node groups exist).
# Using local-exec avoids for_each over "known only after apply" ASG names.
resource "null_resource" "autoscaler_asg_tags" {
  triggers = {
    cpu_system    = aws_eks_node_group.cpu_system.id
    gpu_inference = aws_eks_node_group.gpu_inference.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      CLUSTER="${aws_eks_cluster.this.name}"
      ASGS=$(aws autoscaling describe-auto-scaling-groups \
        --query "AutoScalingGroups[?Tags[?Key=='eks:cluster-name'].Value | [0] == \`$CLUSTER\`].AutoScalingGroupName" \
        --output text --region ${var.aws_region})
      for asg in $ASGS; do
        [ -z "$asg" ] && continue
        aws autoscaling create-or-update-tags --region ${var.aws_region} \
          --tags "ResourceId=$asg,ResourceType=auto-scaling-group,Key=k8s.io/cluster-autoscaler/enabled,Value=true,PropagateAtLaunch=false"
        aws autoscaling create-or-update-tags --region ${var.aws_region} \
          --tags "ResourceId=$asg,ResourceType=auto-scaling-group,Key=k8s.io/cluster-autoscaler/$CLUSTER,Value=owned,PropagateAtLaunch=false"
      done
    EOT
    environment = {
      AWS_DEFAULT_REGION = var.aws_region
    }
  }

  depends_on = [
    aws_eks_node_group.cpu_system,
    aws_eks_node_group.gpu_inference,
  ]
}
