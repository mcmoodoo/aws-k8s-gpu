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

