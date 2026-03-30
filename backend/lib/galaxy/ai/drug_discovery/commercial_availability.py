"""
Commercial availability checker for BioMate drug discovery campaigns.

Queries vendor databases to determine whether proposed compounds can be
ordered commercially, informing the 'synthesise vs. order' decision.
Fills Gap 10 in BioMate's drug discovery opportunity analysis.

In mock_mode=True (default) the checker returns plausible synthetic results
so CI pipelines never make real network requests.
"""
import csv
import json
import logging
import random
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional

log = logging.getLogger(__name__)

_MOCK_VENDORS = ["Sigma-Aldrich", "Enamine", "Combi-Blocks", "TCI"]

# Probability that a random compound is commercially available in mock mode.
_MOCK_AVAILABILITY_RATE = 0.70


# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------

@dataclass
class AvailabilityResult:
    """Availability data for a single compound across all queried vendors."""

    smiles: str
    compound_id: str
    is_available: bool
    query_timestamp: str
    sources: list[dict] = field(default_factory=list)
    cheapest_source: Optional[str] = None


# ---------------------------------------------------------------------------
# Checker
# ---------------------------------------------------------------------------

class CommercialAvailabilityChecker:
    """Check compound availability from major commercial vendors.

    Args:
        mock_mode: When True (default), return plausible mock results without
            making any real HTTP calls — safe for CI and offline use.
        pubchem_api_base: Base URL for the PubChem PUG REST API.
        enamine_api_base: Illustrative base URL for the Enamine store API
            (not a real functional endpoint; included for future integration).
    """

    def __init__(
        self,
        mock_mode: bool = True,
        pubchem_api_base: str = "https://pubchem.ncbi.nlm.nih.gov/rest/pug",
        enamine_api_base: str = "https://www.enaminestore.com/api",
    ):
        self.mock_mode = mock_mode
        self.pubchem_api_base = pubchem_api_base.rstrip("/")
        self.enamine_api_base = enamine_api_base.rstrip("/")

    # ------------------------------------------------------------------
    # Single compound
    # ------------------------------------------------------------------

    def check_single(self, smiles: str, compound_id: str) -> AvailabilityResult:
        """Check commercial availability for one compound.

        Mock mode: 70 % chance available; random vendor, price, lead time.
        Live mode: PubChem lookup to confirm the compound is known; full
            vendor API integration is flagged as 'live vendor API not configured'.
        """
        timestamp = datetime.now(timezone.utc).isoformat()

        if self.mock_mode:
            return self._mock_result(smiles, compound_id, timestamp)
        return self._live_result(smiles, compound_id, timestamp)

    def _mock_result(
        self, smiles: str, compound_id: str, timestamp: str
    ) -> AvailabilityResult:
        rng = random.Random(compound_id)  # deterministic per compound_id
        available = rng.random() < _MOCK_AVAILABILITY_RATE
        sources: list[dict] = []
        cheapest: Optional[str] = None

        if available:
            n_vendors = rng.randint(1, 3)
            seen_vendors = rng.sample(_MOCK_VENDORS, n_vendors)
            prices: list[tuple[str, float]] = []
            for vendor in seen_vendors:
                price = round(rng.uniform(5.0, 200.0), 2)
                lead_time = rng.randint(3, 14)
                catalog_id = f"{vendor[:3].upper()}-{rng.randint(100000, 999999)}"
                sources.append({
                    "vendor": vendor,
                    "catalog_id": catalog_id,
                    "price_usd_per_mg": price,
                    "lead_time_days": lead_time,
                    "url": None,
                })
                prices.append((vendor, price))
            if prices:
                cheapest = min(prices, key=lambda x: x[1])[0]

        return AvailabilityResult(
            smiles=smiles,
            compound_id=compound_id,
            is_available=available,
            query_timestamp=timestamp,
            sources=sources,
            cheapest_source=cheapest,
        )

    def _live_result(
        self, smiles: str, compound_id: str, timestamp: str
    ) -> AvailabilityResult:
        """Real availability check: PubChem lookup + placeholder vendor note."""
        sources: list[dict] = []
        is_available = False
        cheapest: Optional[str] = None

        # PubChem lookup
        encoded_smiles = urllib.parse.quote(smiles, safe="")
        url = (
            f"{self.pubchem_api_base}/compound/smiles/{encoded_smiles}"
            f"/property/IUPACName,MolecularFormula/JSON"
        )
        try:
            with urllib.request.urlopen(url, timeout=10) as resp:
                data = json.loads(resp.read().decode())
            props = data.get("PropertyTable", {}).get("Properties", [])
            if props:
                cid = props[0].get("CID", "unknown")
                sources.append({
                    "vendor": "PubChem",
                    "catalog_id": f"CID:{cid}",
                    "price_usd_per_mg": None,
                    "lead_time_days": None,
                    "url": f"https://pubchem.ncbi.nlm.nih.gov/compound/{cid}",
                })
                is_available = True
                cheapest = "PubChem"
        except urllib.error.HTTPError as exc:
            log.warning("PubChem HTTP error for %s: %s", compound_id, exc)
            sources.append({
                "vendor": "PubChem",
                "catalog_id": "N/A",
                "price_usd_per_mg": None,
                "lead_time_days": None,
                "url": None,
                "note": f"API error: HTTP {exc.code}",
            })
        except Exception as exc:
            log.warning("PubChem lookup failed for %s: %s", compound_id, exc)
            sources.append({
                "vendor": "PubChem",
                "catalog_id": "N/A",
                "price_usd_per_mg": None,
                "lead_time_days": None,
                "url": None,
                "note": f"API error: {exc}",
            })

        # Placeholder for Enamine / Sigma live APIs
        sources.append({
            "vendor": "Enamine/Sigma (live)",
            "catalog_id": "N/A",
            "price_usd_per_mg": None,
            "lead_time_days": None,
            "url": None,
            "note": "live vendor API not configured",
        })

        return AvailabilityResult(
            smiles=smiles,
            compound_id=compound_id,
            is_available=is_available,
            query_timestamp=timestamp,
            sources=sources,
            cheapest_source=cheapest,
        )

    # ------------------------------------------------------------------
    # Batch
    # ------------------------------------------------------------------

    def check_batch(
        self,
        smiles_list: list[str],
        compound_ids: list[str],
    ) -> list[AvailabilityResult]:
        """Check availability for multiple compounds.

        Args:
            smiles_list: SMILES strings, one per compound.
            compound_ids: Compound identifiers, same order as smiles_list.

        Returns:
            List of AvailabilityResult in the same order.
        """
        if len(smiles_list) != len(compound_ids):
            raise ValueError(
                f"smiles_list ({len(smiles_list)}) and compound_ids "
                f"({len(compound_ids)}) must have the same length."
            )
        return [
            self.check_single(smi, cid)
            for smi, cid in zip(smiles_list, compound_ids)
        ]

    # ------------------------------------------------------------------
    # Summary
    # ------------------------------------------------------------------

    def availability_summary(self, results: list[AvailabilityResult]) -> dict:
        """Aggregate statistics across a batch of availability results.

        Returns:
            Dict with keys: n_checked, n_available, availability_rate,
            cheapest_sources (vendor→count), avg_price_estimate_usd_per_mg,
            timestamp.
        """
        n_checked = len(results)
        n_available = sum(1 for r in results if r.is_available)
        availability_rate = (n_available / n_checked) if n_checked > 0 else 0.0

        vendor_counts: dict[str, int] = {}
        prices: list[float] = []
        for r in results:
            if r.cheapest_source:
                vendor_counts[r.cheapest_source] = (
                    vendor_counts.get(r.cheapest_source, 0) + 1
                )
            for src in r.sources:
                p = src.get("price_usd_per_mg")
                if isinstance(p, (int, float)):
                    prices.append(float(p))

        avg_price = round(sum(prices) / len(prices), 2) if prices else None

        return {
            "n_checked": n_checked,
            "n_available": n_available,
            "availability_rate": round(availability_rate, 4),
            "cheapest_sources": vendor_counts,
            "avg_price_estimate_usd_per_mg": avg_price,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

    # ------------------------------------------------------------------
    # CSV export
    # ------------------------------------------------------------------

    def export_availability_report(
        self,
        results: list[AvailabilityResult],
        output_path: str,
    ) -> str:
        """Write availability results to CSV.

        Columns: compound_id, smiles, is_available, cheapest_source,
                 price_usd_per_mg, lead_time_days.

        Returns:
            The output_path that was written.
        """
        fieldnames = [
            "compound_id", "smiles", "is_available",
            "cheapest_source", "price_usd_per_mg", "lead_time_days",
        ]
        with open(output_path, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            for r in results:
                # Find cheapest source details
                best_price: Optional[float] = None
                best_lead: Optional[int] = None
                for src in r.sources:
                    p = src.get("price_usd_per_mg")
                    if (
                        isinstance(p, (int, float))
                        and src.get("vendor") == r.cheapest_source
                    ):
                        best_price = float(p)
                        best_lead = src.get("lead_time_days")
                        break
                writer.writerow({
                    "compound_id": r.compound_id,
                    "smiles": r.smiles,
                    "is_available": r.is_available,
                    "cheapest_source": r.cheapest_source or "",
                    "price_usd_per_mg": best_price if best_price is not None else "",
                    "lead_time_days": best_lead if best_lead is not None else "",
                })
        log.info("Availability report written: %s", output_path)
        return output_path
