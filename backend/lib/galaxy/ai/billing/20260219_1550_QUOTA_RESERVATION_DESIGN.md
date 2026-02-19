# Quota Reservation Rollback Design

## Problem Statement (Audit Finding HIGH-2)

When submitting AWS Batch jobs, the current flow is:
1. Call `check_and_reserve(user_id, estimated_cost)` to check quota and reserve estimated cost
2. Build Batch job request
3. Call `batch.submit_job()` to submit to AWS

**Issue**: If step 3 fails (network error, AWS API error, invalid params), the reservation from step 1 is never released, causing permanent quota reduction.

## Proposed Solutions

### Option 1: Reservation TTL (Recommended - Simplest)

Add a TTL to quota reservations so they auto-expire if not confirmed.

**Implementation**:
```python
# In quota_enforcer.py or realtime_cost_service.py

def reserve_quota(user_id: str, amount_usd: float, reservation_id: str) -> bool:
    """
    Reserve quota with TTL. Returns True if reservation succeeds.
    Reservation expires after 5 minutes if not confirmed.
    """
    month = _month_key()
    reservation_key = f"reservation:{user_id}:month:{month}:{reservation_id}"
    total_key = f"cost:{user_id}:month:{month}:total"
    quota_key = f"quota:{user_id}:month:{month}:limit"

    # Get current spend and quota
    r = get_redis()
    current_spend = float(r.get(total_key) or 0)
    quota_limit = float(r.get(quota_key) or 0)

    # Get pending reservations
    pending_reservations = 0
    for key in r.scan_iter(f"reservation:{user_id}:month:{month}:*"):
        pending_reservations += float(r.get(key) or 0)

    # Check if reservation would exceed quota
    if current_spend + pending_reservations + amount_usd > quota_limit:
        return False

    # Create reservation with 5-minute TTL
    r.setex(reservation_key, 300, str(amount_usd))  # 300 seconds = 5 minutes
    return True


def confirm_reservation(user_id: str, reservation_id: str):
    """
    Confirm reservation after successful job submission.
    Deletes the reservation key (actual cost will be tracked when job completes).
    """
    month = _month_key()
    reservation_key = f"reservation:{user_id}:month:{month}:{reservation_id}"
    r = get_redis()
    r.delete(reservation_key)


def cancel_reservation(user_id: str, reservation_id: str):
    """
    Explicitly cancel a reservation if job submission fails.
    """
    month = _month_key()
    reservation_key = f"reservation:{user_id}:month:{month}:{reservation_id}"
    r = get_redis()
    r.delete(reservation_key)
```

**Usage in batch_submitter.py**:
```python
def submit_batch_job(user_id: str, job_spec: JobSpec) -> str:
    """Submit job to AWS Batch with quota reservation."""
    import uuid

    # Generate unique reservation ID
    reservation_id = f"batch-{uuid.uuid4()}"

    # Estimate cost
    estimated_cost = calculator.estimate_batch_job_cost(
        vcpus=job_spec.vcpus,
        memory_gb=job_spec.memory_gb,
        gpu_count=job_spec.gpu_count,
        estimated_runtime_seconds=job_spec.estimated_runtime
    )

    # Reserve quota with TTL
    if not reserve_quota(user_id, estimated_cost, reservation_id):
        raise HTTPException(
            status_code=402,
            detail=f"Quota exceeded. Current quota: ${quota_limit:.2f}"
        )

    try:
        # Build and submit job
        response = batch_client.submit_job(**build_job_request(job_spec))
        job_id = response['jobId']

        # Confirm reservation (deletes reservation key)
        confirm_reservation(user_id, reservation_id)

        return job_id

    except Exception as exc:
        # Explicitly cancel reservation on failure
        cancel_reservation(user_id, reservation_id)
        raise HTTPException(
            status_code=500,
            detail=f"Job submission failed: {exc}"
        )
```

**Advantages**:
- Simple to implement
- Auto-cleanup via TTL prevents permanent leaks
- No manual cleanup needed
- Reservation expires even if process crashes

**Disadvantages**:
- Slight race condition window (5 minutes)
- Need to scan for pending reservations on quota check

---

### Option 2: Reserve After Submit (Simpler but Less Safe)

Don't reserve quota until job actually starts (in Lambda handler).

**Implementation**:
```python
def submit_batch_job(user_id: str, job_spec: JobSpec) -> str:
    """Submit job without pre-reservation."""

    # Check current quota (but don't reserve)
    current_spend = get_current_spend(user_id)
    quota_limit = get_quota_limit(user_id)

    if current_spend >= quota_limit:
        raise HTTPException(status_code=402, detail="Quota exceeded")

    # Submit job (no reservation)
    response = batch_client.submit_job(**build_job_request(job_spec))

    # Quota will be checked again when Lambda receives RUNNING event
    # If quota exceeded at that point, job will be terminated

    return response['jobId']
```

**Advantages**:
- No reservation leak possible
- Simpler code

**Disadvantages**:
- User could submit many jobs that all fail quota check when they start
- Wastes AWS Batch scheduling resources
- Jobs may fail after being queued

---

### Option 3: Transaction-Based Reservation (Most Complex)

Use Redis transactions (MULTI/EXEC) to atomically reserve and check.

**Implementation**:
```python
def reserve_quota_atomic(user_id: str, amount_usd: float) -> tuple[bool, str]:
    """
    Atomically reserve quota using Redis transaction.
    Returns (success, reservation_id).
    """
    import uuid
    reservation_id = str(uuid.uuid4())
    month = _month_key()

    reservation_key = f"reservation:{user_id}:month:{month}:{reservation_id}"
    total_key = f"cost:{user_id}:month:{month}:total"
    quota_key = f"quota:{user_id}:month:{month}:limit"

    r = get_redis()

    # Use optimistic locking with WATCH
    with r.pipeline() as pipe:
        while True:
            try:
                # Watch keys for changes
                pipe.watch(total_key, quota_key)

                # Get current values
                current_spend = float(pipe.get(total_key) or 0)
                quota_limit = float(pipe.get(quota_key) or 0)

                # Check pending reservations
                pending = sum(
                    float(r.get(key) or 0)
                    for key in r.scan_iter(f"reservation:{user_id}:month:{month}:*")
                )

                # Check quota
                if current_spend + pending + amount_usd > quota_limit:
                    pipe.unwatch()
                    return False, ""

                # Execute transaction
                pipe.multi()
                pipe.setex(reservation_key, 300, str(amount_usd))
                pipe.execute()

                return True, reservation_id

            except redis.WatchError:
                # Retry if values changed during transaction
                continue
```

**Advantages**:
- Atomicity guaranteed
- No race conditions

**Disadvantages**:
- Complex code
- Retry loops can be slow under contention
- Still needs TTL cleanup

---

## Recommendation

**Use Option 1 (Reservation TTL)** for production:
- Best balance of safety and simplicity
- Auto-cleanup prevents leaks
- Explicit confirmation on success
- Explicit cancellation on failure
- 5-minute TTL is long enough for job submission but short enough to prevent quota blocking

## Implementation Checklist

- [ ] Add `reserve_quota()` method to quota_enforcer.py or realtime_cost_service.py
- [ ] Add `confirm_reservation()` method
- [ ] Add `cancel_reservation()` method
- [ ] Update `check_and_reserve()` to use new reservation system
- [ ] Add reservation scanning to quota check logic
- [ ] Update batch_submitter.py to use try/except with explicit cancellation
- [ ] Add unit tests for reservation TTL expiry
- [ ] Add integration tests for submit failure scenarios
- [ ] Update DEPLOYMENT_GUIDE.md with reservation cleanup notes
- [ ] Add CloudWatch alarm for high reservation counts (indicates submit failures)

## Testing Scenarios

1. **Normal flow**: Reserve → Submit succeeds → Confirm → Reservation deleted
2. **Submit fails**: Reserve → Submit fails → Cancel → Reservation deleted
3. **Process crashes**: Reserve → Process dies → TTL expires → Reservation deleted
4. **Quota check**: Multiple pending reservations counted correctly
5. **Concurrent submits**: Multiple users don't interfere with each other
6. **TTL expiry**: Reservation disappears after 5 minutes if not confirmed/cancelled

## Monitoring

Add these CloudWatch metrics:
- `billing.reservations.created` - Count of reservations created
- `billing.reservations.confirmed` - Count confirmed after successful submit
- `billing.reservations.cancelled` - Count cancelled after failed submit
- `billing.reservations.expired` - Count that expired via TTL (indicates crashes or bugs)

Alert if `expired > 10 per hour` (indicates systemic issue with job submission).
