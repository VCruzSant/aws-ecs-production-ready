#!/usr/bin/env bash
set -euo pipefail

url=${1:?usage: load.sh <base-url> [seconds]}
seconds=${2:-240}
end=$((SECONDS + seconds))

# Parallel workers give the charts a shape without stressing a single Fargate task.
worker() {
  while [ "$SECONDS" -lt "$end" ]; do
    curl -s -o /dev/null "$url/health"
    curl -s -o /dev/null "$url/health/db"
    curl -s -o /dev/null -X POST "$url/tasks" -H 'Content-Type: application/json' -d '{"title":"load"}'
    for _ in 1 2 3; do curl -s -o /dev/null "$url/tasks"; done
    curl -s -o /dev/null "$url/does-not-exist"
    curl -s -o /dev/null "$url/tasks/999999"
    sleep 0.5
  done
}

echo "Sending traffic to $url for ${seconds}s"
for _ in 1 2 3 4; do worker & done
wait
echo "Done"
