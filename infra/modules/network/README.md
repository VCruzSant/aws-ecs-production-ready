# Module: network

A VPC written from scratch (no third-party modules) with the classic two-tier layout used by most production workloads on AWS:

- **Public subnets**, one per AZ, routed to an Internet Gateway. Home of the load balancer and the NAT Gateway.
- **Private subnets**, one per AZ, with no inbound path from the internet. Home of the ECS tasks and the database. Outbound traffic (pulling images, calling external APIs) goes through the NAT Gateway.

```
                       Internet
                           │
                   ┌───────┴────────┐
                   │ Internet GW    │
 VPC 10.0.0.0/16   └───────┬────────┘
 ┌─────────────────────────┼─────────────────────────┐
 │  AZ a                   │                  AZ b   │
 │ ┌──────────────────┐    │    ┌──────────────────┐ │
 │ │ public 10.0.0/24 │◄───┴───►│ public 10.0.1/24 │ │
 │ │   NAT Gateway    │         │ (NAT if not      │ │
 │ └────────┬─────────┘         │  single)         │ │
 │          │                   └──────────────────┘ │
 │ ┌────────▼──────────┐        ┌──────────────────┐ │
 │ │ private 10.0.10/24│        │private 10.0.11/24│ │
 │ └───────────────────┘        └──────────────────┘ │
 └───────────────────────────────────────────────────┘
```

Subnet CIDRs are derived with `cidrsubnet`: public subnets take blocks `0..n-1`, private subnets take blocks `10..10+n-1`.

The default security group of the VPC is managed with no rules, so nothing can rely on it by accident.

## VPC Flow Logs

On by default. The flow log records `REJECT` traffic only (connections a security group or network ACL blocked), which is what matters for security and costs the least. Records go to the CloudWatch log group `/vpc/<name>/flow-logs`, kept for 7 days and aggregated every minute. The IAM role of the flow log can only create streams in, write to and describe the streams of that group and has no `logs:CreateLogGroup`, so a delivery that arrives after `terraform destroy` cannot recreate it. CloudWatch Logs charges $0.50 per GB ingested; rejected traffic of a small VPC is a few MB a day.

## NAT Gateway modes

| `enable_nat_gateway` | `single_nat_gateway` | Result | Cost (us-east-2) |
|---|---|---|---|
| `true` | `true` (default) | One NAT in the first AZ shared by all private subnets | ~$0.045/h + data |
| `true` | `false` | One NAT per AZ: an AZ outage does not cut the others off | ~$0.045/h per AZ + data |
| `false` | any | No NAT: private subnets have no internet access | $0 |

Each NAT also uses an Elastic IP (public IPv4, ~$0.005/h).

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | (required) | Name prefix for every resource |
| `vpc_cidr` | `string` | `"10.0.0.0/16"` | IPv4 CIDR block of the VPC (/16 to /28) |
| `az_count` | `number` | `2` | Number of AZs (2 to 4, and no more than the region has); one public and one private subnet per AZ |
| `subnet_newbits` | `number` | `8` | Bits added to the VPC prefix per subnet (/16 + 8 = /24) |
| `enable_nat_gateway` | `bool` | `true` | Create NAT Gateway(s) for the private subnets |
| `single_nat_gateway` | `bool` | `true` | One shared NAT instead of one per AZ |
| `enable_flow_logs` | `bool` | `true` | Send VPC Flow Logs to CloudWatch Logs |
| `flow_logs_traffic_type` | `string` | `"REJECT"` | `REJECT`, `ACCEPT` or `ALL` |
| `flow_logs_retention_days` | `number` | `7` | Retention of the flow logs |
| `tags` | `map(string)` | `{}` | Extra tags merged into every resource |

## Outputs

| Name | Description |
|---|---|
| `vpc_id` | ID of the VPC |
| `vpc_cidr` | CIDR block of the VPC |
| `azs` | AZs used, in the same order as the subnet lists |
| `public_subnet_ids` | Public subnet IDs, one per AZ |
| `private_subnet_ids` | Private subnet IDs, one per AZ |
| `nat_gateway_ids` | NAT Gateway IDs (empty when NAT is disabled) |
| `flow_logs_log_group_name` | Log group of the flow logs (null when they are off) |

## Usage

```hcl
module "network" {
  source = "../../modules/network"

  name     = "my-app-dev"
  vpc_cidr = "10.0.0.0/16"
  az_count = 2

  enable_nat_gateway = true
  single_nat_gateway = true # set to false in production for one NAT per AZ
}

# Then, for example:
#   subnets = module.network.private_subnet_ids
```

Requires Terraform `>= 1.10` and the AWS provider `~> 6.73`.
