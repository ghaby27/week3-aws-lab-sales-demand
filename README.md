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
bootstrap/            GitHub connection, Git sync role and sync configs, budget, placeholder stack,
                      deploy.sh (full build) and teardown.sh
scripts/              cpu-spike.sh (SSM Run Command), watch.sh (shows which server answered)
```

Each `infra/<layer>/` folder has a `template.yaml` and a Git sync `deployment.yaml` (parameters and stack tags). The stacks share values through exports: compute imports from network and security, and security imports from network. Git sync only watches `infra/`, so changes to `bootstrap/` never trigger a deploy.

## Deploy (and rebuild)

Everything uses the `onward-logistics` AWS profile in eu-west-1.

```bash
BUDGET_EMAIL=you@example.com bootstrap/deploy.sh
```

`deploy.sh` builds in dependency order and is safe to re-run:

1. **GitHub connection** (`onward-dev-github-connection`). On the very first run the script stops: approve the pending connection in the console (Developer Tools > Settings > Connections), install the AWS Connector for GitHub app on this repository, and run it again. This is the only console step, and it authorizes a connection CloudFormation created.
2. **Budget alert** (`onward-dev-budget`): USD 150 a month, emails at 80% actual and 100% forecast. The email is passed at deploy time and never stored in Git.
3. **Placeholder stacks** for `onward-dev-orders-network`, `-security` and `-compute`, because Git sync can only manage a stack that already exists.
4. **Git sync** (`onward-dev-orders-git-sync`), one layer at a time: network, then security, then compute, waiting for each because the next one imports its exports.

To rebuild from scratch, run `bootstrap/teardown.sh` (deletes compute, security, network and the Git sync stack, keeps the connection and budget) and then `bootstrap/deploy.sh`.

After that, every change merged to `main` that touches a layer's template or deployment file redeploys that stack. Servers clone the app from [ghaby27/aws-dev-associate-lab-app](https://github.com/ghaby27/aws-dev-associate-lab-app) (`main`) when they launch.

## Demonstrating the client's checks

| Check | How |
|---|---|
| One public address; requests shared; page shows the server | Open the `AppUrl` output, or run `scripts/watch.sh`, and watch the instance ID alternate between zones. |
| Scales out and back in | Run `scripts/cpu-spike.sh 10`. The group grows from 2 toward 4 within a few minutes, then returns to 2 about 15 minutes after the spike ends. |
| Failed server replaced | Terminate one instance. The site keeps answering from the other server, and the group launches a replacement. |
| Losing an Availability Zone | Terminate every instance in one zone. The other zone keeps serving while replacements launch. |
| Only the load balancer is public | Servers have no public IP and their security group only accepts port 8080 from the load balancer. Open a Session Manager shell and run `sudo dnf check-update` to show outbound updates still work. |
| Rebuild from the repository | `bootstrap/teardown.sh` then `bootstrap/deploy.sh`: about 15 minutes, no console steps. |

## Cleanup

Run `bootstrap/teardown.sh`, then delete `onward-dev-budget` and `onward-dev-github-connection`. The NAT gateway and load balancer bill hourly, so delete the stacks once the lab is graded.
