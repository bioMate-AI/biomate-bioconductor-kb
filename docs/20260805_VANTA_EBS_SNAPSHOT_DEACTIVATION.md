# Vanta — EBS Snapshot Encryption Remediation (Plan A: deactivate legacy entities)

Date: 2026-08-05
Test: `aws-ebs-snapshot-encryption` — "EBS snapshots are encrypted (AWS)"
Account: 399683337364

## Context

Account-level **EBS default encryption is now ENABLED** in both `us-east-1`
and `us-west-2` (done 2026-08-04). All *newly created* volumes and
snapshots are encrypted going forward.

The 21 snapshots below are **legacy AMI backing snapshots** created before
default encryption was turned on. They are point-in-time AMI images; only
one is still referenced by a running instance. Per Vanta's allowed
remediation path, these legacy entities are **deactivated** with the
justification below (re-encrypting would require rebuilding the AMIs /
instances, and future images are covered by default encryption).

## Justification to paste into Vanta (per snapshot)

> Legacy AMI backing snapshot created prior to enabling account-level EBS
> default encryption (enabled 2026-08-04 in all regions). All new volumes
> and snapshots are encrypted by default. This snapshot backs a machine
> image being phased out; re-encryption would require rebuilding the image.
> Deactivated as a legacy, out-of-scope entity.

## Snapshots to deactivate

### us-east-1 (1)
| Snapshot | AMI | In use? |
|---|---|---|
| snap-0e6dc21caa4661068 | ami-008607f719aaac1b0 | no |

### us-west-2 (20)
| Snapshot | AMI | In use? |
|---|---|---|
| snap-0a35ee54425c149bf | ami-0eea98ee0c1afb58c | no |
| snap-079abcc4a1b20255d | ami-05cd45791f70a9693 | no |
| snap-06254b1231f300582 | ami-04aa855f08ac04d00 | no |
| snap-0952fe2357f40c269 | ami-0b87976a7d71c0747 | no |
| snap-0c96df574b0ce07ea | ami-0800408ab54e82130 | no |
| snap-0fb031a14fa1a5458 | ami-0546824943513c3be | no |
| snap-003a1b0d30a93d011 | ami-0af58415e7cb6c48d | no |
| snap-0be9c753b2f293027 | ami-04a94079fc4877101 | no |
| snap-0e70a88822724c660 | ami-0aa41b4bcb67b799a | no |
| snap-05c76f2edb806946c | ami-09ae3537d1d214ed2 | no |
| **snap-00ed6a98e20988b51** | ami-08fe495be97a3dbf4 | **YES — running instance** |
| snap-0022630198df4aea5 | ami-04ed7e19d6f94816d | no |
| snap-0dfb3c5e4f795dc0d | ami-01da1bf6eef10a8b5 | no |
| snap-07a0a8f20e3066dbb | ami-08ffb7a01eef6681c | no |
| snap-0f30e76c19a98160e | ami-0f6426bf1fcc3b796 | no |
| snap-05c82ae0773de9da4 | ami-051fc3d11efefcb16 | no |
| snap-0eaa42b33a1c61ce4 | ami-0f02c2b015a9cf35c | no |
| snap-09339be44a4b6a6c7 | ami-018d838f95a1ea229 | no |
| snap-0b9f78707a03642ba | ami-0b66c975e961f764f | no |
| snap-0e81a7b342d32f18a | ami-05dbb7cd1ff52b0e2 | no |

## Note on the one in-use snapshot

`snap-00ed6a98e20988b51` (ami-08fe495be97a3dbf4) backs a currently-running
instance. Options:
- **Deactivate in Vanta** (same justification) — simplest; acceptable since
  default encryption now covers all new images.
- **Re-encrypt properly** — copy AMI with encryption, relaunch the instance
  from the encrypted AMI, deregister the old AMI, delete the old snapshot.
  Do this only during a maintenance window for that instance.

## How to deactivate in the Vanta UI

1. Tests → open "EBS snapshots are encrypted (AWS)"
2. In the failing-entities list, select the snapshots above
3. Deactivate → paste the justification → save
