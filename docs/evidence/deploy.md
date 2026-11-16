# Deploy

Output of `make infra-up` on an empty `dev` environment in us-east-2, trimmed to the summary. Account ID and resource IDs are replaced.

```
Apply complete! Resources: 2 added, 0 changed, 0 destroyed.
Apply complete! Resources: 51 added, 0 changed, 0 destroyed.
53 resources created, 0 changed, 0 destroyed

Migration task:
INFO  [alembic.runtime.migration] Running upgrade  -> 0001, create tasks table
Migration finished (exit code 0)
```

Total time from `apply` to the migration finishing: about 10 minutes.
