# Vanta — EC2 Public Ports Justification (`aws-ec2instances-ports-restricted`)

Date: 2026-08-05
Test: "EC2 instance public ports restricted (AWS)" — SOC 2 / HIPAA
Account: 399683337364 (us-west-2)

## Situation

The test passes only when publicly-exposed EC2 ports are limited to the
approved set (default 80/443) **or** to an explicitly configured allow-list.
BioMate exposes several additional ports that are **required for product
functionality** and cannot be moved behind the VPN without breaking the
product or billing.

Preferred remediation: in the Vanta test settings, **add the ports below to
the "permitted ports" parameter** (with the justifications here). This makes
the test pass legitimately. If parameter editing is unavailable, mark the
test **N/A** and attach this document.

## Ports and business justification

| Port(s) | Service | Why it must be public | Instance |
|---|---|---|---|
| 3000/tcp | Lago (SaaS metering / billing) | Called by the application backend over the box's public IP (35.86.137.71) to record LLM/compute usage; core billing path | bill (i-069fbdf5) |
| 8080/tcp | Java billing service | Subscription lifecycle / plan enforcement / invoicing; called over public IP (35.86.137.71:8080) | bill (i-069fbdf5) |
| 39000-39010/tcp | Galaxy Interactive Environments (GIE) | End-user interactive tool sessions (Jupyter/RStudio/etc.) opened by users' browsers over the public internet | app/galaxy nodes |
| 51820/udp | WireGuard VPN | The VPN endpoint itself; must be publicly reachable for clients to establish the tunnel | vpn-server (i-0fa1fc21) |

## Ports being reviewed for tightening (may be restricted to VPN/VPC)

| Port(s) | Service | Plan |
|---|---|---|
| 9090/tcp | Metrics (Prometheus?) | Restrict to VPC/VPN (172.31.0.0/16, 10.8.0.0/24) if only used internally |
| 8081/tcp | Galaxy backend | Confirm whether user-facing; if internal-only, restrict to VPC/VPN |

## Compensating controls

- Public SSH (port 22) is being locked to the VPC + WireGuard VPN subnets
  (see `firewall-config-server` remediation) — admin access is not public.
- All data in transit uses TLS (443); billing endpoints are authenticated.
- CloudTrail (multi-region) + log-file validation + Object Lock provide an
  immutable audit trail of any configuration change.
- 80/443 are the standard web ports and are expected to be public.

## Note on the VPN

A WireGuard VPN exists (endpoint 35.89.131.56:51820, client subnet
10.8.0.0/24, routes 172.31.0.0/16). It is used to make **admin** access
(SSH, metrics) private. It cannot front the billing (3000/8080) or GIE
(39000-39010) ports because those are consumed by external callers (the
app over public IP, and end-user browsers) that are not on the VPN.
