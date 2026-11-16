# State of the running environment

```
$ aws ecs describe-services
{
    "status": "ACTIVE",
    "desiredCount": 1,
    "runningCount": 1,
    "rolloutState": "COMPLETED",
    "launchType": "FARGATE"
}

$ aws elbv2 describe-target-health
[
    {
        "port": 8000,
        "state": "healthy"
    }
]

$ aws rds describe-db-instances
{
    "class": "db.t4g.micro",
    "engine": "postgres",
    "publiclyAccessible": false,
    "storageEncrypted": true,
    "multiAZ": false,
    "status": "available"
}

$ aws secretsmanager list-secrets
[
    {
        "managedBy": "rds"
    }
]
```
