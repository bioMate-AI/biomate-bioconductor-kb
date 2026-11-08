# Spot cost reconciliation — 29 October 2026

**Decision:** M1 is within the documented method-stage scope, but this audit does **not yet certify an all-in remaining allowance for a new launch**. The known method inventory has a conservative **compute-only upper estimate of USD 12.1897**, leaving a conditional USD 1.8103 below the USD 14 aggregate cap. This is not a measured balance: storage/other charges, complete scope attribution and individual stream caps remain unresolved. K2 and K4 have no demonstrated headroom under their separate USD 3 pilot caps. No resources were launched, changed or terminated in this audit.

## Evidence and method

Read-only AWS queries ran around 21:11–21:14 UTC in `us-west-2`: EC2 instance lifecycle and live-instance inventory, retained Spot requests, AZ/type-specific Linux Spot price history from 16:00 UTC, and CloudTrail RunInstances/TerminateInstances events. Cost Explorer was queried for same-day EC2 Compute spend. Local cost logs supplied stream identity and cross-checks.

Sanitised evidence is retained in [instance_ledger.json](20261029_spot_cost_evidence/instance_ledger.json), [launch_index.json](20261029_spot_cost_evidence/launch_index.json) and [spot_prices.json](20261029_spot_cost_evidence/spot_prices.json). These files omit CloudTrail credentials/principals and unrelated account events. The launch index has 104 `allatom-*` instances. None appeared in the live-instance inventory (running, pending, stopping, stopped or shutting-down). Earlier terminated records had expired from ordinary EC2 describe results; their absence alone was not treated as a termination timestamp.

For each matched instance, the compute envelope is `(end bound − launch time) × maximum observed Spot price for its actual AZ/type`. A closed Spot request's final status-update time is used as the end bound; it can lag actual shutdown by several minutes. For expired request records, the conservative end bound is **21:20 UTC**, deliberately later than the live-inventory check. The price history includes the predecessor price at the start of the query. This bounds observed-run compute conservatively; it is not an invoice, an exact running-time integral, or evidence that all time until the status update was billed. No lower bound sufficient to prove an overrun is asserted from these status timestamps.

Excluded from these compute estimates: EBS, snapshots, S3, transfer, public IPv4, taxes/credits and any unattributed or differently tagged run. Root volumes and their deletion status were not reconciled. Same-day Cost Explorer returned **USD 23.8484391812**, `Estimated: true`, for account-wide EC2 Compute, under empty `Name` tag attribution. That value cannot be assigned to these streams and must not be added to or substituted for their reconstructed costs.

## Method stages 0–1

The implementation plan allocates USD 14 total: I-A 1.5, I-B 1.0, U1 2.0, U2+U3 2.0, E 4.0 and M3 reserve 3.5. The historical generation-pilot-3 overrun (~USD 6.8 against its original USD 4 cap, with a separately approved USD 1.5 ChemFM continuation) is a separately documented budget; it has not been silently charged against or erased from this method allowance.

| Stream | Identified instances | End records expired | Conservative compute upper estimate (USD) | Interpretation |
|---|---:|---:|---:|---|
| I-A | 2 | 2 | 0.2889 | Missing actual end times; coarse upper bound |
| I-B | 11 | 9 | 1.3626 | Upper bound exceeds its 1.0 subcap; actual spend unresolved |
| U1 | 12 | 1 | 0.9630 | Includes 11 retained requests; those alone total about 0.613 |
| U2+U3 | 6 | 4 | 4.7550 | Very loose upper bound; exceeds its 2.0 subcap, not proof of an overrun |
| E | 10 | 2 | 4.4893 | Includes quality, replacement, tuning, prep and evaluation launches; not only latest run |
| Early harness tests | 2 | 2 | 0.3308 | Conservatively included in aggregate method scope |
| **Aggregate** | **43** | **20** | **12.1897** | Compute only; no confirmed M3 study launch identified |

The latest E worker `i-098cc97fa8999f24d` launched 19:48:20 UTC, was reported closed by 20:19:38, and has compute upper estimate **USD 0.3119** at USD 0.5979/h in us-west-2d. U1 tests6 `i-0430822d721c62507` launched 19:47:38 and was reported closed by 20:02:20. These are now terminated, superseding the earlier takeover snapshot that described E as running.

The USD 3.5 M3 row is a budget allocation, not proof of an untouched cash balance. A bounded M1 real-model check is a required, already-scoped integration step, but **the record is insufficient to say that a specific new M1 launch fits every existing cap**. To establish that without a new budget request, recover actual ends for the 20 expired method requests, account for ancillary charges, resolve allocation of harness work and freeze a hard-dollar M1 envelope covering setup, model load, sampling/update, upload and shutdown. Compare that envelope with both the aggregate and applicable subcap. Do not use K2/K4 funds as a reserve. No further stage-2/audit spending is inferred as authorized.

For planning only, the observed maximum g5.4xlarge Spot price in us-west-2b was USD 0.8304/h. A 30-minute compute window at that price is USD 0.4152, before ancillary charges. This is a price-based scenario, not a measured M1 runtime or a guarantee of future price/capacity. The proposed 1,200-second application timeout does not include all boot/setup time and cannot alone enforce a dollar ceiling.

## K2 and K4 pilot caps

All nine logged K2 instances and all nine logged K4 instances matched retained closed Spot requests. The maxima below include failed attempts and CPU preparation, not just the final successful extraction worker.

| Pilot | Cap (USD) | Lifecycle/price compute envelope (USD) | Remaining allowance |
|---|---:|---:|---|
| K2 literature/import/check attempts | 3.00 | up to **3.0112** | Not demonstrated; no additional extraction spend on this evidence |
| K4 patent selection/extraction attempts | 3.00 | up to **3.2570** | Not demonstrated; no additional extraction spend on this evidence |

K2 final worker `i-0dace5be00919a762` was actually **g5.4xlarge in us-west-2b**, launched 19:59:22 and reported closed 20:46:17. Its observed price range was USD 0.8225–0.8304/h and its compute upper estimate is USD 0.6493. The older amendment's g5.2xlarge rate of roughly USD 0.49–0.55/h is not the rate of this worker. K2's earlier USD 1.9 spent / USD 1.1 remaining statement was a timestamp estimate before this reconciliation; it must not be reused as current headroom.

K4 final worker `i-0609fef39c55c57f2` was g6.4xlarge in us-west-2b, launched 18:52:24 and reported closed 21:04:26. Its observed price range was USD 1.0655–1.0773/h and its compute upper estimate is USD 2.3707. Earlier extraction attempts and preparation bring the envelope above USD 3. This is evidence of **possible cap exhaustion**, not an exact billed overrun: termination-status lag can overstate runtime, and billing is not yet attributable. Conversely, omitted ancillary charges can increase total spend.

The final-worker envelopes include any concurrent read-only/CPU QA done while the extraction instances existed; those checks must not be double-counted as new instance costs. Any later K2/K4 continuation requires actual reconciliation and the existing approval process, not an assumption that the shutdown timer left spare budget.

## Other identified knowledge instances

For completeness, separately scoped K3 (30 instances), K gold collection (12) and KA (1) have compute upper estimates USD 0.6302, 0.2978 and 0.0200 respectively. They are retained in the ledger but not silently reassigned to the method USD 14 or K2/K4 caps. K3 entries embedded in `orchestrator/cost_log_ia.csv` were separated by their actual `allatom-k3` tags; charging every row of that file to I-A would misallocate costs.

## Remaining verification

1. Recover shutdown times for expired method records from S3 boot/terminal logs or detailed billing; preserve actual timestamps rather than assume planned timers fired.
2. Reconcile EBS creation/deletion, other ancillary costs and any different-tag launches with the intended budget owner.
3. Replace the conservative bounds with invoice-backed costs when tagged/resource-level billing is available. Keep estimates labelled until then.
4. Record a concrete M1 maximum charge and allocation before launching. This audit neither grants additional budget nor treats uncertainty as a scientific reason to stop the method study.
