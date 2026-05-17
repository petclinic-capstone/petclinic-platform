# Log group name matches what the EKS module creates — shared via naming convention
output "eks_cluster_log_group"     { value = "/aws/eks/${var.cluster_name}/cluster" }
output "eks_application_log_group" { value = aws_cloudwatch_log_group.eks_application.name }
output "eks_host_log_group"        { value = aws_cloudwatch_log_group.eks_host.name }
output "dashboard_name"            { value = aws_cloudwatch_dashboard.petclinic.dashboard_name }
