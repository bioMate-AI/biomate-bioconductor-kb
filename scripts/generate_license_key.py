#!/usr/bin/env python3
"""
BioMate License Key Generator — Internal Use Only
==================================================
Run this to generate a license key for an on-premises customer.

Usage:
  python3 scripts/generate_license_key.py \\
      --customer ACME_PHARMA \\
      --expiry 2027-06 \\
      --secret $BIOMATE_LICENSE_SECRET

  # Generate a 30-day demo key (uses built-in demo secret):
  python3 scripts/generate_license_key.py --demo

  # Verify an existing key:
  python3 scripts/generate_license_key.py \\
      --verify BMOP-XXXX-XXXX-XXXX-XXXX \\
      --secret $BIOMATE_LICENSE_SECRET

Output:
  BMOP-XXXX-XXXX-XXXX-XXXX

Send both BIOMATE_LICENSE_KEY and BIOMATE_LICENSE_SECRET to the customer.
The customer sets both in their .env file.
"""

import argparse
import datetime
import hashlib
import hmac
import sys

# Well-known demo key — uses this secret, hardcoded in license.py as well.
# Only grants access to demo licenses; never use for real customers.
DEMO_SECRET = "biomate-onprem-demo-secret-2026"
DEMO_CUSTOMER = "DEMO"


def customer_to_token(customer: str) -> str:
    """Stable 8-hex-char token from customer name."""
    h = hashlib.sha256(customer.upper().encode()).hexdigest()
    return h[:8].upper()


def expiry_to_hex(expiry: str) -> str:
    """2027-06 → 0x2706 = '2706' (decimal YYMM stored as 4 hex chars)."""
    try:
        dt = datetime.datetime.strptime(expiry, "%Y-%m")
        yymm = (dt.year - 2000) * 100 + dt.month
        return f'{yymm:04X}'
    except ValueError:
        print(f"ERROR: expiry must be YYYY-MM format, got {expiry}", file=sys.stderr)
        sys.exit(1)


def hex_to_expiry(hex_str: str) -> str:
    """'2706' (hex YYMM) → '2027-06'."""
    try:
        yymm = int(hex_str, 16)
        year = 2000 + (yymm // 100)
        month = yymm % 100
        return f"{year:04d}-{month:02d}"
    except (ValueError, ZeroDivisionError):
        return "(invalid)"


def compute_sig(p1: str, p2: str, p3: str, secret: str) -> str:
    payload = f'{p1}-{p2}-{p3}'
    return hmac.new(secret.encode(), payload.encode(), hashlib.sha256).hexdigest()[:4].upper()


def generate_key(customer: str, expiry: str, secret: str) -> str:
    token = customer_to_token(customer)
    p1, p2 = token[:4], token[4:]
    p3 = expiry_to_hex(expiry)
    p4 = compute_sig(p1, p2, p3, secret)
    return f'BMOP-{p1}-{p2}-{p3}-{p4}'


def verify_key(key: str, secret: str) -> dict:
    """Returns a dict with valid (bool), expiry (str), and reason (str)."""
    parts = key.upper().split("-")
    if len(parts) != 5 or parts[0] != "BMOP":
        return {"valid": False, "reason": "Wrong format (expected BMOP-XXXX-XXXX-XXXX-XXXX)"}
    _, p1, p2, p3, p4 = parts
    if len(p1) != 4 or len(p2) != 4 or len(p3) != 4 or len(p4) != 4:
        return {"valid": False, "reason": "Each segment must be 4 characters"}
    expected_sig = compute_sig(p1, p2, p3, secret)
    if expected_sig != p4:
        return {"valid": False, "reason": f"HMAC mismatch (got {p4}, expected {expected_sig})"}
    expiry = hex_to_expiry(p3)
    try:
        dt = datetime.datetime.strptime(expiry, "%Y-%m")
        # Key is valid through the last day of the expiry month
        import calendar
        last_day = calendar.monthrange(dt.year, dt.month)[1]
        exp_date = dt.replace(day=last_day)
        now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
        if now > exp_date:
            return {"valid": False, "reason": f"Expired on {expiry}-{last_day:02d}"}
    except ValueError:
        return {"valid": False, "reason": f"Invalid expiry segment: {p3}"}
    return {"valid": True, "expiry": expiry, "reason": "OK"}


def main():
    parser = argparse.ArgumentParser(description='Generate or verify BioMate on-prem license keys')
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--customer', help='Customer name/identifier (e.g. ACME_PHARMA)')
    group.add_argument('--demo', action='store_true', help='Generate a demo key (30-day, uses built-in demo secret)')
    group.add_argument('--verify', metavar='KEY', help='Verify an existing key')

    parser.add_argument('--expiry', help='Expiry month (e.g. 2027-06) — required with --customer')
    parser.add_argument('--secret', help='BIOMATE_LICENSE_SECRET value — required with --customer/--verify')
    args = parser.parse_args()

    if args.demo:
        # Generate a demo key expiring end of next month
        now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
        next_month = (now.month % 12) + 1
        next_year = now.year + (1 if now.month == 12 else 0)
        expiry = f"{next_year}-{next_month:02d}"
        key = generate_key(DEMO_CUSTOMER, expiry, DEMO_SECRET)
        print()
        print("Demo license key (uses built-in demo secret):")
        print(f"  BIOMATE_LICENSE_KEY={key}")
        print(f"  BIOMATE_LICENSE_SECRET={DEMO_SECRET}")
        print(f"  Expires: {expiry}")
        print()
        print("For testing only — do NOT issue to real customers.")
        return

    if args.verify:
        secret = args.secret
        if not secret:
            # Try demo secret as fallback
            result = verify_key(args.verify, DEMO_SECRET)
            if result["valid"]:
                print(f"VALID (demo key) — expires {result['expiry']}")
                return
            print("ERROR: --secret is required to verify a non-demo key", file=sys.stderr)
            sys.exit(1)
        result = verify_key(args.verify, secret)
        if result["valid"]:
            print(f"VALID — expires {result['expiry']}")
        else:
            print(f"INVALID — {result['reason']}")
            sys.exit(1)
        return

    # Generate new key for customer
    if not args.expiry:
        print("ERROR: --expiry is required with --customer (e.g. --expiry 2027-06)", file=sys.stderr)
        sys.exit(1)
    if not args.secret:
        print("ERROR: --secret is required with --customer", file=sys.stderr)
        sys.exit(1)

    key = generate_key(args.customer, args.expiry, args.secret)

    print()
    print(f'Customer:    {args.customer}')
    print(f'Expiry:      {args.expiry}')
    print()
    print(f'License Key: {key}')
    print()
    print('─' * 52)
    print('Send to customer (.env entries):')
    print(f'  BIOMATE_LICENSE_KEY={key}')
    print(f'  BIOMATE_LICENSE_SECRET={args.secret}')
    print('─' * 52)


if __name__ == '__main__':
    main()
