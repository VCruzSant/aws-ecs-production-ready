#!/usr/bin/env bash
# Runs a command as a one-off ECS task in the network of a service and fails unless it exits 0.
set -euo pipefail

if [ $# -lt 5 ]; then
  echo "usage: $0 <region> <cluster> <service> <task-definition|current> <command>..." >&2
  exit 2
fi
region=$1
cluster=$2
service=$3
taskdef=$4
shift 4

for word in "$@"; do
  case $word in
    *[\"\\]*)
      echo "The command takes plain words only, without quotes or backslashes: $word" >&2
      exit 2
      ;;
  esac
done
command_json=$(printf '"%s",' "$@")
command_json="[${command_json%,}]"

ecs() { aws ecs "$@" --region "$region"; }

read -r current subnets security_groups container < <(ecs describe-services --cluster "$cluster" --services "$service" \
  --query "services[0].[taskDefinition, join(',', networkConfiguration.awsvpcConfiguration.subnets), join(',', networkConfiguration.awsvpcConfiguration.securityGroups), loadBalancers[0].containerName]" \
  --output text)
if [ -z "${container:-}" ] || [ "$current" = "None" ]; then
  echo "Service $service not found in cluster $cluster" >&2
  exit 1
fi
if [ "$taskdef" = "current" ]; then
  taskdef=$current
fi

read -r log_group log_prefix < <(ecs describe-task-definition --task-definition "$taskdef" \
  --query "taskDefinition.containerDefinitions[?name=='$container'] | [0].logConfiguration.options.[\"awslogs-group\", \"awslogs-stream-prefix\"]" \
  --output text)

task=$(ecs run-task --cluster "$cluster" --task-definition "$taskdef" \
  --launch-type FARGATE --started-by db-migrate \
  --network-configuration "awsvpcConfiguration={subnets=[$subnets],securityGroups=[$security_groups],assignPublicIp=DISABLED}" \
  --overrides "{\"containerOverrides\":[{\"name\":\"$container\",\"command\":$command_json}]}" \
  --query 'tasks[0].taskArn' --output text)
if [ -z "$task" ] || [ "$task" = "None" ]; then
  echo "run-task did not start a task" >&2
  exit 1
fi
echo "Started ${task##*/} (${taskdef##*/}) running '$*', waiting for it to stop"

if ! ecs wait tasks-stopped --cluster "$cluster" --tasks "$task"; then
  echo "Still running after 10 minutes; do not start another migration until it stops."
  echo "Check it: aws ecs describe-tasks --region $region --cluster $cluster --tasks $task"
  exit 1
fi

code=$(ecs describe-tasks --cluster "$cluster" --tasks "$task" --query 'tasks[0].containers[0].exitCode' --output text)
stream="$log_prefix/$container/${task##*/}"
aws logs get-log-events --region "$region" --log-group-name "$log_group" --log-stream-name "$stream" \
  --query 'events[].message' --output text 2>/dev/null | tr '\t' '\n' || true

if [ "$code" != "0" ]; then
  reason=$(ecs describe-tasks --cluster "$cluster" --tasks "$task" \
    --query 'tasks[0].[stoppedReason, containers[0].reason]' --output text | tr '\t' ' ' | sed 's/ None$//')
  echo "Migration failed (exit code $code): $reason"
  echo "Logs: aws logs tail $log_group --region $region --log-stream-names $stream"
  exit 1
fi
echo "Migration finished (exit code 0)"
