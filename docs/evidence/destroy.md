# Destroy

`terraform destroy` on the `dev` environment, then a check of what is left in the account.

```
Destroy complete! Resources: 53 destroyed.
ECS clusters: none
NAT Gateways: deleted
Load balancers: 0
RDS instances: 0
Secrets: 0
Log groups: 0
S3 buckets: only the Terraform state bucket from the bootstrap
```
