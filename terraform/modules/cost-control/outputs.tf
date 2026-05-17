output "lambda_function_name" {
  description = "Name of the cost-control Lambda function — used by cost-control.sh"
  value       = aws_lambda_function.cost_control.function_name
}

output "lambda_function_arn" {
  description = "ARN of the cost-control Lambda function"
  value       = aws_lambda_function.cost_control.arn
}
