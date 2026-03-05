output "aws_region" {
  description = "AWS region used for this deployment."
  value       = var.aws_region
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "eks_cluster_endpoint" {
  description = "Endpoint for the EKS cluster."
  value       = aws_eks_cluster.this.endpoint
}

output "eks_cluster_oidc_issuer" {
  description = "OIDC issuer URL for the EKS cluster."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}


