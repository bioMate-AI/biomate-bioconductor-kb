#!/usr/bin/env python3
"""T2 spend log from EC2 records (not assumptions). For every instance tagged project=cyclic-selector, Name=t2-*: instance type, AZ, launch time, end time (StateTransitionReason or now),
and the cost = integral of the AZ-specific Linux spot price (describe-spot-price-history, stepwise-constant) over [launch, end] (spot is billed per second at the market price).
usage: cost_log.py OUT.csv [--ids i-... i-...]   (extra IDs for instances that no longer appear in describe-instances)"""
import sys, csv, re, json, subprocess, datetime as dt
UTC = dt.timezone.utc


def aws(*a):
    return json.loads(subprocess.run(["aws", "--region", "us-west-2", *a, "--output", "json"], capture_output=True, text=True, check=True).stdout)


def parse(s): return dt.datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(UTC)


def price_steps(itype, az, t0, t1):
    pts = []; tok = None
    while True:
        args = ["ec2", "describe-spot-price-history", "--instance-types", itype, "--availability-zone", az, "--product-descriptions", "Linux/UNIX", "--start-time", (t0 - dt.timedelta(hours=8)).isoformat(), "--end-time", t1.isoformat()]
        if tok: args += ["--starting-token", tok]
        d = aws(*args); pts += [(parse(x["Timestamp"]), float(x["SpotPrice"])) for x in d["SpotPriceHistory"]]; tok = d.get("NextToken")
        if not tok: break
    return sorted(pts)


def cost(itype, az, t0, t1):
    pts = price_steps(itype, az, t0, t1)
    if not pts: return None, None
    tot, last_t = 0.0, t0; cur = [p for t, p in pts if t <= t0]; price = cur[-1] if cur else pts[0][1]; paid = []
    for t, p in pts:
        if t <= t0: continue
        if t >= t1: break
        tot += price * (t - last_t).total_seconds() / 3600; last_t = t; price = p
    tot += price * (t1 - last_t).total_seconds() / 3600; return tot, (tot / max((t1 - t0).total_seconds() / 3600, 1e-9))


if __name__ == "__main__":
    out = sys.argv[1]; extra = sys.argv[sys.argv.index("--ids") + 1:] if "--ids" in sys.argv else []
    now = dt.datetime.now(UTC); inst = {}
    f = aws("ec2", "describe-instances", "--filters", "Name=tag:project,Values=cyclic-selector", "Name=tag:Name,Values=t2-*")
    for r in f["Reservations"]:
        for i in r["Instances"]: inst[i["InstanceId"]] = i
    for k in range(0, len(extra), 50):
        try:
            for r in aws("ec2", "describe-instances", "--instance-ids", *extra[k:k + 50])["Reservations"]:
                for i in r["Instances"]: inst.setdefault(i["InstanceId"], i)
        except subprocess.CalledProcessError: pass
    rows = []
    for iid, i in sorted(inst.items(), key=lambda kv: kv[1]["LaunchTime"]):
        name = next((t["Value"] for t in i.get("Tags", []) if t["Key"] == "Name"), ""); t0 = parse(i["LaunchTime"]); st = i["State"]["Name"]; end = now
        m = re.search(r"\((\d{4}-\d\d-\d\d \d\d:\d\d:\d\d) GMT\)", i.get("StateTransitionReason", "") or "")
        if st in ("terminated", "shutting-down") and m: end = dt.datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S").replace(tzinfo=UTC)
        c, avg = cost(i["InstanceType"], i["Placement"]["AvailabilityZone"], t0, end)
        rows.append(dict(instance=iid, name=name, type=i["InstanceType"], az=i["Placement"]["AvailabilityZone"], launch=t0.isoformat(timespec="minutes"), end=end.isoformat(timespec="minutes"), state=st,
                         hours=round((end - t0).total_seconds() / 3600, 3), avg_spot_price=(round(avg, 4) if avg else None), cost_usd=(round(c, 3) if c is not None else None)))
    w = csv.DictWriter(open(out, "w", newline=""), fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
    tot = sum(r["cost_usd"] or 0 for r in rows); hrs = sum(r["hours"] for r in rows); unk = [r["instance"] for r in rows if r["cost_usd"] is None]
    print(f"instances={len(rows)} instance_hours={hrs:.2f} cost_usd={tot:.2f} unpriced={unk}"); [print(r) for r in rows]
