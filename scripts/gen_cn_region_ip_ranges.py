#!/usr/bin/env python3
"""Regenerate frontend/server/data/cn-region-ip-ranges.json — the IP ranges that count as a China
user for the Chinese-LLM region policy (frontend/server/llm-region-policy.ts).

"China user by IP" = the client IP GEOLOCATES to one of CN_REGION_COUNTRIES: mainland China (CN),
Hong Kong (HK), Macau (MO) or Taiwan (TW). Keep this list equal to CN_REGION_COUNTRIES in
frontend/server/llm-region-policy.ts.

Source: DB-IP "IP to Country Lite" (monthly, CC BY 4.0 — attribution: "IP Geolocation by DB-IP",
https://db-ip.com):
    https://download.db-ip.com/free/dbip-country-lite-YYYY-MM.csv.gz
A geolocation database, not a registry allocation list: APNIC's delegated file misses blocks that
are registered elsewhere but used in China/HK (e.g. Alibaba Cloud HK 47.242.0.0/15 is an ARIN
registration), so it would miss real Hong Kong users.
Rows: start_ip,end_ip,country (IPv4 and IPv6 mixed).

Output: {"source", "license", "generated", "countries", "ipv4": [[start,end],...] (merged,
inclusive, uint32), "ipv6": [[start_hex32,end_hex32],...] (merged, inclusive, 128-bit as 32 hex)}.

Usage: python3 scripts/gen_cn_hk_ip_ranges.py [path-to-dbip-country-lite.csv.gz] [YYYY-MM]
Refresh monthly (DB-IP publishes a new file each month).
"""
import datetime, gzip, io, ipaddress, json, os, sys, urllib.request

COUNTRIES = ("CN", "HK", "MO", "TW")  # == CN_REGION_COUNTRIES (llm-region-policy.ts)
OUT = os.path.join(os.path.dirname(__file__), "..", "frontend", "server", "data", "cn-region-ip-ranges.json")


def merged(ranges):
    ranges.sort()
    out = []
    for s, e in ranges:
        if out and s <= out[-1][1] + 1:
            out[-1][1] = max(out[-1][1], e)
        else:
            out.append([s, e])
    return out


def main():
    month = sys.argv[2] if len(sys.argv) > 2 else datetime.date.today().strftime("%Y-%m")
    src = f"https://download.db-ip.com/free/dbip-country-lite-{month}.csv.gz"
    raw = open(sys.argv[1], "rb").read() if len(sys.argv) > 1 else urllib.request.urlopen(src, timeout=300).read()
    v4, v6 = [], []
    for line in io.TextIOWrapper(gzip.GzipFile(fileobj=io.BytesIO(raw)), encoding="utf-8"):
        start, end, cc = line.strip().split(",")[:3]
        if cc not in COUNTRIES:
            continue
        a, b = ipaddress.ip_address(start), ipaddress.ip_address(end)
        (v4 if a.version == 4 else v6).append([int(a), int(b)])
    out = {
        "source": src,
        "license": "CC BY 4.0 — IP Geolocation by DB-IP (https://db-ip.com)",
        "generated": datetime.date.today().isoformat(),
        "countries": list(COUNTRIES),
        "ipv4": merged(v4),
        "ipv6": [[format(s, "032x"), format(e, "032x")] for s, e in merged(v6)],
    }
    with open(OUT, "w") as fh:
        json.dump(out, fh, separators=(",", ":"))
    print(f"ipv4 ranges: {len(out['ipv4'])}  ipv6 ranges: {len(out['ipv6'])}  -> {os.path.normpath(OUT)}")


if __name__ == "__main__":
    main()
