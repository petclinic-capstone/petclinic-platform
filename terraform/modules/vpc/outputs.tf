output "vpc_id" {
  description = "ID of the PetClinic VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the PetClinic VPC"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "public_subnet_cidrs" {
  description = "CIDR blocks of the public subnets"
  value       = aws_subnet.public[*].cidr_block
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.this.id
}

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public.id
}

output "eks_cluster_security_group_id" {
  description = "Security group ID for the EKS control plane"
  value       = aws_security_group.eks_cluster.id
}

output "eks_node_security_group_id" {
  description = "Security group ID for the EKS worker nodes"
  value       = aws_security_group.eks_node.id
}

output "rds_security_group_id" {
  description = "Security group ID for RDS MySQL"
  value       = aws_security_group.rds.id
}

output "alb_security_group_id" {
  description = "Security group ID for public ALB"
  value       = aws_security_group.alb.id
}
