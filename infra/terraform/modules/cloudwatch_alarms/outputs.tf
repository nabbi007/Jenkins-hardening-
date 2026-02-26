output "cpu_alarm_name" {
  description = "CPU alarm name"
  value       = aws_cloudwatch_metric_alarm.ecs_cpu_high.alarm_name
}

output "memory_alarm_name" {
  description = "Memory alarm name"
  value       = aws_cloudwatch_metric_alarm.ecs_memory_high.alarm_name
}
