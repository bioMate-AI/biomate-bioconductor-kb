"""
BioMate On-Premises License Validation
---------------------------------------
Key format:  BMOP-CCCC-CCCC-YYMM-SSSS
  CCCC-CCCC  8 hex chars — customer token (assigned by BioMate team)
  YYMM       4 hex chars — expiry year/month (e.g. 2712 = Dec 2027 → 0x2712 = 10002 decimal)
  SSSS       4 hex chars — HMAC-SHA256(SECRET, "CCCC-CCCC-YYMM")[:2].hex().upper()

BIOMATE_LICENSE_SECRET must be set in the server environment by BioMate team.
It is NOT stored in the source repo.

Demo key (trial, no expiry check, no HMAC check):
  BMOP-DEMO-DEMO-DEMO-DEMO
"""

from __future__ import annotations

import datetime
import hmac
import hashlib
import logging
import os
import re
from typing import Optional

from fastapi import APIRouter

log = logging.getLogger(__name__)

router = APIRouter()

_KEY_PATTERN = re.compile(
    r'^BMOP-([0-9A-F]{4})-([0-9A-F]{4})-([0-9A-F]{4})-([0-9A-F]{4})$'
)
_DEMO_KEY = 'BMOP-DEMO-DEMO-DEMO-DEMO'


def _signing_secret() -> str:
    return os.environ.get('BIOMATE_LICENSE_SECRET', '')


def _compute_sig(p1: str, p2: str, p3: str) -> str:
    secret = _signing_secret()
    if not secret:
        return '0000'
    payload = f'{p1}-{p2}-{p3}'
    return hmac.new(secret.encode(), payload.encode(), hashlib.sha256).hexdigest()[:4].upper()


def validate_license_key(key: Optional[str]) -> dict:
    """Validate a BioMate license key offline.  Returns a status dict."""
    if not key:
        return {
            'valid': False,
            'status': 'missing',
            'message': '未配置许可证密钥，请在环境变量中设置 BIOMATE_LICENSE_KEY',
        }

    key = key.strip().upper()

    # Demo / trial key
    if key == _DEMO_KEY:
        return {
            'valid': True,
            'status': 'demo',
            'tier': 'trial',
            'expires': None,
            'message': '演示许可证（功能不受限，但仅供评估使用）',
        }

    m = _KEY_PATTERN.match(key)
    if not m:
        return {
            'valid': False,
            'status': 'invalid_format',
            'message': f'许可证格式错误（应为 BMOP-XXXX-XXXX-XXXX-XXXX），收到：{key}',
        }

    p1, p2, p3, p4 = m.groups()

    # Decode expiry: p3 as decimal YYMM (NOT hex, easier to read)
    try:
        yymm = int(p3, 16)
        yy, mm = divmod(yymm, 100)
        if not (1 <= mm <= 12):
            raise ValueError('invalid month')
        expiry = datetime.date(2000 + yy, mm, 1)
    except (ValueError, OverflowError):
        return {
            'valid': False,
            'status': 'invalid_expiry',
            'message': f'许可证有效期字段解析失败（字段值：{p3}）',
        }

    today = datetime.date.today()
    if expiry.year < today.year or (expiry.year == today.year and expiry.month < today.month):
        return {
            'valid': False,
            'status': 'expired',
            'message': f'许可证已于 20{yy:02d}-{mm:02d} 到期，请联系 BioMate 团队续期',
            'expires': f'20{yy:02d}-{mm:02d}',
        }

    # Signature check (skipped when SECRET not configured — allows BioMate team to test)
    if _signing_secret():
        expected = _compute_sig(p1, p2, p3)
        if expected != p4:
            return {
                'valid': False,
                'status': 'invalid_signature',
                'message': '许可证签名无效，请确认密钥未被修改',
            }
    else:
        log.warning('[License] BIOMATE_LICENSE_SECRET not set — signature check skipped')

    return {
        'valid': True,
        'status': 'active',
        'tier': 'enterprise',
        'customer_token': f'{p1}{p2}',
        'expires': f'20{yy:02d}-{mm:02d}',
        'message': f'许可证有效（到期：20{yy:02d}-{mm:02d}）',
    }


# ── Cached result (re-check once per hour) ────────────────────────────────────

_cache: dict = {}
_cache_ts: float = 0.0
_CACHE_TTL = 3600.0


def get_license_status() -> dict:
    import time
    global _cache, _cache_ts
    now = time.monotonic()
    if _cache and (now - _cache_ts) < _CACHE_TTL:
        return _cache
    key = os.environ.get('BIOMATE_LICENSE_KEY', '')
    result = validate_license_key(key)
    _cache = result
    _cache_ts = now
    if result['valid']:
        log.info('[License] %s', result['message'])
    else:
        log.warning('[License] INVALID — %s', result['message'])
    return result


# ── FastAPI endpoint ──────────────────────────────────────────────────────────

@router.get('/api/license/status')
def license_status():
    """Return current license status.  Safe to expose — no secrets returned."""
    status = get_license_status()
    # Never expose customer_token or internal fields externally
    return {
        'valid': status['valid'],
        'status': status['status'],
        'tier': status.get('tier', 'none'),
        'expires': status.get('expires'),
        'message': status['message'],
    }
