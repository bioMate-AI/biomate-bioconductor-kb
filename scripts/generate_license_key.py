#!/usr/bin/env python3
"""
BioMate License Key Generator — Internal Use Only
==================================================
Run this to generate a license key for an on-premises customer.

Usage:
  python3 scripts/generate_license_key.py \
      --customer ACME_PHARMA \
      --expiry 2027-06 \
      --secret $BIOMATE_LICENSE_SECRET

Output:
  BMOP-XXXX-XXXX-XXXX-XXXX

This key and the SECRET are then sent to the customer together.
The customer puts BIOMATE_LICENSE_KEY in their .env;
the SECRET goes in BIOMATE_LICENSE_SECRET (also in their .env).
"""

import argparse
import datetime
import hashlib
import hmac
import sys


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


def compute_sig(p1: str, p2: str, p3: str, secret: str) -> str:
    payload = f'{p1}-{p2}-{p3}'
    return hmac.new(secret.encode(), payload.encode(), hashlib.sha256).hexdigest()[:4].upper()


def generate_key(customer: str, expiry: str, secret: str) -> str:
    token = customer_to_token(customer)
    p1, p2 = token[:4], token[4:]
    p3 = expiry_to_hex(expiry)
    p4 = compute_sig(p1, p2, p3, secret)
    return f'BMOP-{p1}-{p2}-{p3}-{p4}'


def main():
    parser = argparse.ArgumentParser(description='Generate BioMate on-prem license key')
    parser.add_argument('--customer', required=True, help='Customer name/identifier (e.g. ACME_PHARMA)')
    parser.add_argument('--expiry', required=True, help='Expiry month (e.g. 2027-06)')
    parser.add_argument('--secret', required=True, help='BIOMATE_LICENSE_SECRET value')
    args = parser.parse_args()

    key = generate_key(args.customer, args.expiry, args.secret)

    print()
    print(f'Customer:    {args.customer}')
    print(f'Expiry:      {args.expiry}')
    print()
    print(f'License Key: {key}')
    print()
    print('─' * 52)
    print('Send to customer:')
    print(f'  BIOMATE_LICENSE_KEY={key}')
    print(f'  BIOMATE_LICENSE_SECRET={args.secret}')
    print('─' * 52)


if __name__ == '__main__':
    main()
