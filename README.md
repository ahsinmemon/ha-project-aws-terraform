# Highly Available AWS Infrastructure — Built with Terraform, Broken on Purpose

A 3-tier, multi-AZ AWS architecture provisioned entirely with Terraform, then deliberately
failure-tested to prove it actually recovers — not just that it deploys.

**TL;DR:** I built a highly available web app on AWS (ALB → Auto Scaling Group → RDS Multi-AZ),
then terminated one of two running EC2 instances while live traffic was hitting it, and recorded
the system detecting the failure and healing itself automatically.

📹 [Chaos test recording](https://drive.google.com/file/d/1sY5mrEPUCIxjtPRvUc1emvdVoqh9ah3h/view?usp=sharing)
🏗️ [Terraform source](https://github.com/ahsinmemon/ha-project-aws-terraform.git)

---

## Architecture

```
                            Internet
                               │
                        ┌──────▼──────┐
                        │     ALB     │  (public subnets, 2 AZs)
                        └──────┬──────┘
                               │
                 ┌─────────────┴─────────────┐
                 │                            │
          ┌──────▼──────┐             ┌──────▼──────┐
          │  EC2 (AZ-a) │             │  EC2 (AZ-b) │   Auto Scaling Group
          │  private sn │             │  private sn │   (min 2, max 4, target CPU 50%)
          └──────┬──────┘             └──────┬──────┘
                 │                            │
                 └─────────────┬──────────────┘
                                │
                        ┌───────▼───────┐
                        │  RDS MySQL    │  Multi-AZ
                        │  (primary +   │  (private subnets)
                        │   standby)    │
                        └───────────────┘
```

- **VPC** with 2 public and 2 private subnets across 2 Availability Zones
- **Application Load Balancer** in the public subnets, health-checking targets every 15s
- **Auto Scaling Group** (min 2 / max 4) running EC2 instances in the private subnets, with a
  CPU-based target tracking scaling policy (target: 50% average CPU)
- **RDS MySQL, Multi-AZ enabled** — synchronous standby in the second AZ, automatic failover
- **CloudWatch dashboard + alarm** on unhealthy target count, wired to an SNS email notification
- **Security groups** chained so only the ALB is reachable from the internet, only the ALB can
  reach the EC2 instances, and only the EC2 instances can reach the database

All of it is defined in Terraform — `terraform apply` builds the entire stack from nothing, with
state stored remotely in S3 with DynamoDB locking.

## Tech stack

Terraform · AWS (VPC, EC2, ALB, Auto Scaling, RDS, CloudWatch, SNS, Secrets Manager) · Bash

## Why Multi-AZ, not just multiple instances

A load-balanced ASG across two AZs protects the *application* layer — lose an instance, or even
lose a whole AZ, and the app keeps serving. But that's meaningless if the database is a single
point of failure underneath it. RDS Multi-AZ solves that half: AWS maintains a synchronously
replicated standby in the second AZ, and promotes it automatically if the primary fails. Together,
both halves of the stack — compute and data — can survive losing an AZ, not just losing a server.

---

## The chaos test

Proving "highly available" with a README claim isn't proof — it's a sentence. So I broke it on
camera instead.

### What I did

1. Confirmed baseline: 2 healthy EC2 instances registered in the target group, traffic alternating
   between both via the ALB.
2. Started a continuous request loop against the ALB's public DNS name, printing the responding
   instance's ID every 2 seconds — this is the live proof the site stays reachable.
3. Ran `aws ec2 terminate-instances` against one of the two running instances while the loop was
   live.
4. Watched the ALB, ASG, and CloudWatch alarm react in real time.

### What happened

- **One request failed** with a `504 Gateway Timeout` in the exact window the instance was
  terminated — the ALB hadn't fully deregistered it yet when the request was routed there.
- **Every request immediately after succeeded**, served entirely by the surviving instance — no
  extended outage, no dropped site.
- **CloudWatch's `UnHealthyHostCount` alarm fired** within about a minute, and an email
  notification arrived via SNS.
- **The Auto Scaling Group detected it was below its desired capacity of 2** and launched a
  replacement instance automatically. Once the new instance passed its health checks, the request
  loop began returning its instance ID — proof a genuinely new server had taken over, not a
  restart of the old one.

### Why it recovered

- The ALB's health checks (`unhealthy_threshold = 2`, 15s interval) are what let the system notice
  a dead target in roughly 30 seconds instead of waiting on a slower default.
- The ASG's `health_check_type = "ELB"` means it trusts the load balancer's application-level
  health check, not just "is the EC2 instance running" — so it reacts to real app failure, not
  only hardware/OS failure.
- `min_size = 2` combined across two AZs means there was always a second, unaffected instance
  absorbing 100% of traffic the moment the first one died.

### An honest limitation, not a hidden one

The single dropped request came from the absence of **connection draining**
(`deregistration_delay`) on the target group — in a production setup, I'd configure the ALB to
stop sending new requests to a terminating instance while letting its in-flight request finish
first, which would eliminate that dropped request entirely. I left it out here to keep the demo
focused on the core failover mechanism, but it's the natural next hardening step.

I also intentionally ran a **single NAT Gateway** instead of one per AZ, to keep costs low for a
demo project — a fully redundant setup would put a NAT Gateway in each AZ so a lost AZ can't also
take down outbound internet access for the private subnets in the *other* AZ.

---

## Repo structure

```
.
├── providers.tf              # AWS + backend config
├── variables.tf               # input variable declarations
├── network.tf                 # VPC, subnets, IGW, NAT, route tables
├── security_groups.tf         # ALB / EC2 / RDS security groups
├── database.tf                # RDS Multi-AZ + Secrets Manager
├── compute.tf                 # launch template, ALB, target group, ASG, scaling policy
├── monitoring.tf              # SNS topic, CloudWatch alarm, CloudWatch dashboard
├── user_data.sh                # EC2 boot script (installs httpd, serves instance ID/AZ)
├── terraform.tfvars.example   # copy to terraform.tfvars and fill in your own values
└── outputs.tf
```

## Running it yourself

```bash
cp terraform.tfvars.example terraform.tfvars
# fill in your own AMI ID, IP, and email in terraform.tfvars

terraform init
terraform plan
terraform apply
```

`terraform.tfvars` is gitignored — it's not included in this repo since it contains
account-specific values (your IP for SSH access, your alert email, your AMI ID).

## Teardown

```bash
terraform destroy
```
