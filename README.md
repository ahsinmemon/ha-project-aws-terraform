# Highly Available AWS Infrastructure — Built with Terraform, Broken on Purpose

A multi-AZ AWS web tier provisioned entirely with Terraform, then deliberately failure-tested to
check whether it actually recovers — not just whether it deploys.

**TL;DR:** I built a load-balanced, auto-scaling web tier on AWS (ALB → Auto Scaling Group) with a
Multi-AZ RDS database provisioned alongside it, then terminated one of two running EC2 instances
while live traffic was hitting the ALB, and recorded what actually happened.

📹 [Chaos test recording](https://drive.google.com/file/d/1SNNAYuVHYTtoSQmkBhKUxkeNgGJ4Sknb/view?usp=sharing)
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
          │  private sn │             │  private sn │   (min 2, max 5, target CPU 50%)
          └──────┬──────┘             └──────┬──────┘
                 │                            │
                 └─────────────┬──────────────┘
                                │
                        ┌───────▼───────┐
                        │  RDS MySQL    │  Multi-AZ, provisioned
                        │  (primary +   │  but not connected to
                        │   standby)    │  by the app (see below)
                        └───────────────┘
```

- **VPC** with 2 public and 2 private subnets across 2 Availability Zones
- **Application Load Balancer** in the public subnets, health-checking targets every 15s
- **Auto Scaling Group** (min 2, max 5, desired 4) running EC2 instances in the private subnets,
  with a CPU-based target tracking scaling policy (target: 50% average CPU)
- **RDS MySQL, Multi-AZ enabled** — synchronous standby in the second AZ, automatic failover
- **CloudWatch dashboard**, plus an alarm on unhealthy target count wired to SNS (see the Known
  Issues section — this alarm currently has a bug and doesn't fire)
- **Security groups** chained so only the ALB is reachable from the internet, only the ALB can
  reach the EC2 instances, and only the EC2 instances can reach the database (though nothing in
  the app currently exercises that last connection — see below)

All of it is defined in Terraform — `terraform apply` builds the entire stack from nothing, with
state stored remotely in S3 with DynamoDB locking.

## Tech stack

Terraform · AWS (VPC, EC2, ALB, Auto Scaling, RDS, CloudWatch, SNS, Secrets Manager) · Bash

## What this project is, and isn't

This is a **highly available web tier with a Multi-AZ database provisioned alongside it** — not a
working 3-tier application. `user_data.sh` installs `httpd` and serves a static page showing the
instance's own ID and AZ; it never opens a connection to MySQL, and no IAM role or instance
profile exists to let it authenticate to Secrets Manager even if it tried. The database, security
group rule between EC2 and RDS, and the Secrets Manager secret are all provisioned and correctly
network-isolated, but currently sit idle — none of that path has been exercised end to end. I'm
stating that plainly here rather than leaving "3-tier" as a label the code doesn't back.

## Why Multi-AZ, not just multiple instances

A load-balanced ASG across two AZs protects the *application* layer — lose an instance, or even
lose a whole AZ, and the app keeps serving. RDS Multi-AZ is meant to solve the equivalent problem
for the data layer: AWS maintains a synchronously replicated standby in the second AZ and can
promote it automatically if the primary fails. In this project that data-layer protection is
provisioned but unused, since nothing in the app talks to the database yet (see above).

---

## The chaos test

### What I did

1. Confirmed baseline: 2 healthy EC2 instances registered in the target group, traffic alternating
   between both via the ALB.
2. Started a continuous request loop against the ALB's public DNS name, printing the responding
   instance's ID every 2 seconds.
3. Ran `aws ec2 terminate-instances` against one of the running instances while the loop was live.
4. Watched the ALB and ASG react in real time.

### What happened

- **One request failed** with a `504 Gateway Timeout` in the exact window the instance was
  terminated — the ALB hadn't fully deregistered it yet when the request was routed there.
- **Every request immediately after succeeded**, served entirely by the surviving instance.
- **The Auto Scaling Group detected it was short an instance** and launched a replacement. Once
  the new instance passed its health checks, the request loop began returning its instance ID —
  proof a new server had taken over, not a restart of the old one.
- **The CloudWatch alarm did not fire, and no email arrived.** I found out afterward why: the
  alarm's `metric_name` was written as `UnhealthyHostCount` (lowercase h), but the real ALB metric
  name is `UnHealthyHostCount` (capital H) — a one-character typo that meant the alarm was
  watching a metric that doesn't exist, and sat in `INSUFFICIENT_DATA` the entire time. I'm
  documenting this as-is rather than rewriting the story after the fact; the fix is a one-line
  change, tracked below.

### Why the parts that did work, worked

- The ALB's health checks (`unhealthy_threshold = 2`, 15s interval) let the target group notice a
  dead target in roughly 30 seconds instead of waiting on a slower default.
- The ASG's `health_check_type = "ELB"` means it trusts the load balancer's application-level
  health check, not just "is the EC2 instance running" — so it reacts to real app failure, not
  only hardware/OS failure.
- With `min_size = 2` and instances spread across two AZs, there was always a second, unaffected
  instance absorbing traffic the moment the first one died.

---

## Known issues / honest limitations

These are gaps I know about, not ones I'm hoping nobody notices:

- **CloudWatch alarm metric name bug** — `UnhealthyHostCount` should be `UnHealthyHostCount`. As
  written at the time of the chaos test, this alarm never left `INSUFFICIENT_DATA` and did not
  notify on the failure above.
- **No IAM instance profile** — the launch template has no `iam_instance_profile`, so nothing
  running on the EC2 instances can authenticate to fetch the Secrets Manager secret, even though
  the secret and the security group path to RDS both exist.
- **App does not connect to RDS** — see "What this project is, and isn't" above.
- **Single NAT Gateway**, not one per AZ — kept to one deliberately to control cost for a demo
  project; a fully redundant setup would put a NAT Gateway in each AZ so a lost AZ can't also take
  down outbound internet access for the private subnets in the other AZ.
- **No connection draining** (`deregistration_delay`) on the target group — this is the direct
  cause of the single dropped request during the chaos test. Configuring it would let an
  in-flight request finish before the ALB stops routing to a terminating instance.
- **RDS is not encrypted at rest** (`storage_encrypted` not set) and the **ALB listener is
  HTTP-only**, no TLS.
- **The SSH ingress rule on the EC2 security group is currently unreachable** — instances sit in
  private subnets with no public IP and no bastion host, so despite the rule existing, there's no
  actual path to use it as written.
- **The AWS provider profile is hardcoded** (`profile = "ha-project"`) — this repo runs as-is only
  under that named CLI profile; it isn't portable to another machine without editing that value.

## Repo structure

```
.
├── providers.tf              # AWS + backend config
├── variables.tf               # input variable declarations
├── network.tf                 # VPC, subnets, IGW, NAT, route tables
├── security_groups.tf         # ALB / EC2 / RDS security groups
├── database.tf                # RDS Multi-AZ + Secrets Manager (provisioned, not yet wired to the app)
├── compute.tf                 # launch template, ALB, target group, ASG, scaling policy
├── monitoring.tf              # SNS topic, CloudWatch alarm (has a known metric-name bug), dashboard
├── user_data.sh                # EC2 boot script (installs httpd, serves instance ID/AZ — no DB connection)
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

*(Infrastructure for this project has since been destroyed to avoid ongoing cost. The fixes listed
under Known Issues are tracked but not yet re-applied and re-tested against live infrastructure.)*
