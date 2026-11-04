# Handling Sales Day Demand for the Onward Logistics Order System

Week 3 lab (Compute & Delivery on AWS) · Gabriel Anyaele · eu-west-1

The order system is one Python (Flask) app that serves the UI and the order logic. It runs on private t3.micro servers in two Availability Zones, behind one internet-facing Application Load Balancer. The Auto Scaling group keeps average CPU near 50%, growing from 2 to at most 4 servers on a sales day and shrinking back afterwards. Servers reach the internet outbound only, through a regional NAT gateway, and are administered through Systems Manager with no open admin ports.

- Architecture: [architecture.png](architecture.png)
- Discovery report: [docs/discovery-report.docx](docs/discovery-report.docx)
- Cost estimate: [AWS Pricing Calculator](https://calculator.aws/#/estimate?id=d0baa32f99ba428baf14ca9345c19cf6f0218d86) ([PDF export](docs/pricing-calculator-export.pdf))

## Repository layout

```
infra/network/        VPC, subnets, internet gateway, regional NAT gateway
infra/security/       security groups, server IAM role (AWS managed policy only)
infra/compute/        load balancer, launch template, Auto Scaling group, CPU scaling policy
scripts/              cpu-spike.sh (SSM Run Command), watch.sh (shows which server answered)
```

Each `infra/<layer>/` folder has a `template.yaml` and a Git sync `deployment.yaml` (parameters and stack tags). The stacks share values through exports: compute imports from network and security, and security imports from network.

## Deploy

All commands use `--profile onward-logistics --region eu-west-1`. The one-time bootstrap templates (GitHub connection, Git sync role and sync configs, placeholder stack) live outside this repository, in the shared `bootstrap/` folder.

1. **Connect GitHub (once).** Deploy `bootstrap/github-connection.yaml` as `onward-dev-github-connection`. Approve the pending connection in the console and install the AWS Connector for GitHub app on this repository, then update the stack with `CreateRepositoryLink=true`.
2. **Reserve the stack names.** Git sync can only manage a stack that already exists, so create `onward-dev-orders-network`, `onward-dev-orders-security` and `onward-dev-orders-compute` from `bootstrap/placeholder-stack.yaml`.
3. **Turn on Git sync, layer by layer.** Deploy `bootstrap/git-sync.yaml` as `onward-dev-orders-git-sync` (needs `CAPABILITY_NAMED_IAM`) with `SyncedLayers=1`. When the network stack finishes, update it to `2`, and when security finishes, to `3`.

After that, every change merged to `main` that touches a layer's template or deployment file redeploys that stack. Servers clone the app from [ghaby27/aws-dev-associate-lab-app](https://github.com/ghaby27/aws-dev-associate-lab-app) (`main`) when they launch.

## Demonstrating the client's checks

| Check | How |
|---|---|
| One public address; requests shared; page shows the server | Open the `AppUrl` output, or run `scripts/watch.sh`, and watch the instance ID alternate between zones. |
| Scales out and back in | Run `scripts/cpu-spike.sh 10`. The group grows from 2 toward 4 within a few minutes, then returns to 2 about 15 minutes after the spike ends. |
| Failed server replaced | Terminate one instance. The site keeps answering from the other server, and the group launches a replacement. |
| Losing an Availability Zone | Terminate every instance in one zone. The other zone keeps serving while replacements launch. |
| Only the load balancer is public | Servers have no public IP and their security group only accepts port 8080 from the load balancer. Open a Session Manager shell and run `sudo dnf check-update` to show outbound updates still work. |
| Rebuild from the repository | Delete the three stacks and repeat the deploy steps. |

## Cleanup

Delete `onward-dev-orders-compute`, then `-security`, then `-network`, then the Git sync and connection stacks. The NAT gateway and load balancer bill hourly, so delete the stacks once the lab is graded.
