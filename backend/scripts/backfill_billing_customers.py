#!/usr/bin/env python3
"""
One-time backfill: register all existing BioMate users as customers
in the Java billing service.

Usage:
    python scripts/backfill_billing_customers.py [--dry-run] [--url URL]

Options:
    --dry-run   Print what would be sent without making any HTTP calls.
    --url URL   Java billing service URL (overrides JAVA_BILLING_SERVICE_URL env var).

Reads users from the BioMate frontend PostgreSQL database (DATABASE_URL env var).
Falls back to querying the Galaxy SQLite DB if no DATABASE_URL is set.
"""

import argparse
import json
import os
import sys
import time

import httpx

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

DEFAULT_URL = os.environ.get("JAVA_BILLING_SERVICE_URL", "http://35.86.137.71:8080")
DATABASE_URL = os.environ.get("DATABASE_URL", "")

# Throttle to avoid overwhelming the Java service
REQUESTS_PER_SECOND = 5
DELAY = 1.0 / REQUESTS_PER_SECOND


def external_id(user_id: str) -> str:
    """Must match the convention in java_billing_client.py."""
    return f"bm_{user_id}"


# ---------------------------------------------------------------------------
# User fetching
# ---------------------------------------------------------------------------

def fetch_users_from_postgres(database_url: str) -> list[dict]:
    """Fetch id, email, full_name from the frontend PostgreSQL users table."""
    try:
        import psycopg2
        conn = psycopg2.connect(database_url)
        cur = conn.cursor()
        cur.execute('SELECT id, email, "fullName" FROM users ORDER BY id')
        rows = cur.fetchall()
        conn.close()
        return [{"id": str(r[0]), "email": r[1], "name": r[2] or r[1]} for r in rows]
    except ImportError:
        print("psycopg2 not installed — pip install psycopg2-binary", file=sys.stderr)
        sys.exit(1)
    except Exception as exc:
        print(f"PostgreSQL error: {exc}", file=sys.stderr)
        sys.exit(1)


def fetch_users_from_sqlite(sqlite_path: str) -> list[dict]:
    """Fallback: fetch users from the Galaxy SQLite DB."""
    import sqlite3
    try:
        conn = sqlite3.connect(sqlite_path)
        cur = conn.cursor()
        cur.execute("SELECT id, email, username FROM galaxy_user ORDER BY id")
        rows = cur.fetchall()
        conn.close()
        return [{"id": str(r[0]), "email": r[1], "name": r[2] or r[1]} for r in rows]
    except Exception as exc:
        print(f"SQLite error: {exc}", file=sys.stderr)
        sys.exit(1)


def get_users() -> list[dict]:
    if DATABASE_URL:
        print(f"Fetching users from PostgreSQL ({DATABASE_URL[:30]}...)")
        return fetch_users_from_postgres(DATABASE_URL)

    # Fallback to Galaxy SQLite
    sqlite_path = "/tmp/biomate_connection_formal.sqlite"
    if os.path.exists(sqlite_path):
        print(f"Fetching users from Galaxy SQLite ({sqlite_path})")
        return fetch_users_from_sqlite(sqlite_path)

    print("No database source found. Set DATABASE_URL or ensure Galaxy SQLite exists.",
          file=sys.stderr)
    sys.exit(1)


# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

def register_customer(client: httpx.Client, user: dict, base_url: str, dry_run: bool) -> bool:
    payload = {
        "externalId": external_id(user["id"]),
        "name": user["name"],
        "email": user["email"],
        "currency": "USD",
    }

    if dry_run:
        print(f"  [DRY RUN] POST {base_url}/api/billing/customers  {json.dumps(payload)}")
        return True

    try:
        r = client.post("/api/billing/customers", json=payload, timeout=10.0)
        if r.status_code in (200, 201):
            resp = r.json()
            if resp.get("code") == 0:
                return True
            # code=0 is success; non-zero means error
            print(f"  WARN {user['id']}: {resp.get('message')}")
            return False
        print(f"  ERROR {user['id']}: HTTP {r.status_code} {r.text[:120]}")
        return False
    except Exception as exc:
        print(f"  ERROR {user['id']}: {exc}")
        return False


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Backfill BioMate users into Java billing service")
    parser.add_argument("--dry-run", action="store_true", help="Print requests without sending them")
    parser.add_argument("--url", default=DEFAULT_URL, help="Java billing service base URL")
    args = parser.parse_args()

    base_url = args.url.rstrip("/")
    dry_run = args.dry_run

    print(f"Java billing service: {base_url}")
    print(f"Mode: {'DRY RUN' if dry_run else 'LIVE'}")
    print()

    users = get_users()
    print(f"Found {len(users)} users to register.\n")

    if not dry_run:
        # Quick connectivity check
        try:
            r = httpx.get(f"{base_url}/actuator/health", timeout=5.0)
            print(f"Service health: {r.json().get('status', 'unknown')}\n")
        except Exception as exc:
            print(f"WARNING: Cannot reach billing service: {exc}")
            answer = input("Continue anyway? [y/N] ").strip().lower()
            if answer != "y":
                sys.exit(0)

    ok = fail = skip = 0

    with httpx.Client(base_url=base_url) as client:
        for i, user in enumerate(users, 1):
            print(f"[{i:4d}/{len(users)}] user_id={user['id']} email={user['email']}", end=" ")
            if not user.get("email"):
                print("— SKIP (no email)")
                skip += 1
                continue

            success = register_customer(client, user, base_url, dry_run)
            if success:
                print("— OK")
                ok += 1
            else:
                fail += 1

            if not dry_run and i % REQUESTS_PER_SECOND == 0:
                time.sleep(DELAY)

    print(f"\nDone. ok={ok}  failed={fail}  skipped={skip}")
    if fail:
        sys.exit(1)


if __name__ == "__main__":
    main()
