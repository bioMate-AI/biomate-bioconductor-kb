"""
Generic persistent HTTP cache utility.

Any module that calls external APIs during AI assistant processing should use
this class to avoid rate limits and ensure consistent responses across runs.

Pattern:
    cache = PersistentAPICache("gwas_catalog")
    data = cache.fetch("https://...url...")  # returns cached or live
"""

from __future__ import annotations

import json
import logging
import time
from pathlib import Path
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)

# Default location for all API cache files
_CACHE_DIR = Path(__file__).parent.parent.parent.parent.parent / "database" / "knowledge_cache"


class PersistentAPICache:
    """
    Persistent disk-backed HTTP GET cache.

    - Reads cache from disk on first access per process
    - Writes new entries back to disk every `flush_interval` new entries
    - Thread-safe for read-only; callers must serialize writes if needed
    """

    def __init__(
        self,
        name: str,
        cache_dir: Optional[Path] = None,
        flush_interval: int = 50,
        default_timeout: int = 5,
    ) -> None:
        self.name = name
        self.path = (cache_dir or _CACHE_DIR) / f"{name}_cache.json"
        self.flush_interval = flush_interval
        self.default_timeout = default_timeout
        self._cache: Dict[str, Any] = {}
        self._dirty = False
        self._loaded = False

    def _load(self) -> None:
        if self._loaded:
            return
        self._loaded = True
        if self.path.exists():
            try:
                with open(self.path) as f:
                    self._cache = json.load(f)
                logger.debug("%s cache loaded: %d entries", self.name, len(self._cache))
            except Exception as exc:
                logger.warning("Failed to load %s cache: %s", self.name, exc)
                self._cache = {}

    def flush(self) -> None:
        if not self._dirty:
            return
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            with open(self.path, "w") as f:
                json.dump(self._cache, f)
            self._dirty = False
            logger.debug("%s cache saved: %d entries", self.name, len(self._cache))
        except Exception as exc:
            logger.warning("Failed to save %s cache: %s", self.name, exc)

    def get(self, key: str) -> Optional[Any]:
        self._load()
        return self._cache.get(key)

    def set(self, key: str, value: Any) -> None:
        self._load()
        self._cache[key] = value
        self._dirty = True
        if len(self._cache) % self.flush_interval == 0:
            self.flush()

    def fetch(
        self,
        url: str,
        *,
        timeout: Optional[int] = None,
        headers: Optional[Dict[str, str]] = None,
        params: Optional[Dict[str, Any]] = None,
    ) -> Optional[Any]:
        """
        GET *url* and return parsed JSON. Checks disk cache first.
        Returns None on network failure or non-200 response.
        """
        self._load()
        cache_key = url
        if params:
            cache_key = url + "?" + "&".join(f"{k}={v}" for k, v in sorted(params.items()))

        if cache_key in self._cache:
            return self._cache[cache_key]

        try:
            import requests as _req
            h = {"Accept": "application/json"}
            if headers:
                h.update(headers)
            t = timeout or self.default_timeout
            r = _req.get(url, headers=h, params=params, timeout=(t, t))
            r.raise_for_status()
            data = r.json()
            self.set(cache_key, data)
            return data
        except Exception as exc:
            logger.debug("%s fetch failed for %s: %s", self.name, url, exc)
            return None

    def __len__(self) -> int:
        self._load()
        return len(self._cache)

    def __contains__(self, key: str) -> bool:
        self._load()
        return key in self._cache
