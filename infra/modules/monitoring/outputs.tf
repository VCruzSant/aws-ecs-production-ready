output "topic_arn" {
  description = "ARN of the SNS topic that receives every alarm."
  value       = aws_sns_topic.alerts.arn
}

output "alarm_names" {
  description = "Names of all alarms."
  value       = sort([for a in aws_cloudwatch_metric_alarm.this : a.alarm_name])
}
