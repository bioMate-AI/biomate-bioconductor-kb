"""Real, data-backed evidence channels for target-ID.

- OpenTargetsGeneticsChannel: live OpenTargets Platform GraphQL (free, no key). Query shape
  VERIFIED against the live API 2026-10-20 (disease(efoId).associatedTargets.rows{target.approvedSymbol, score}).
- TableChannel: a cached evidence table (CSV/TSV: target,score[,filter]) — what the REPRODUCIBLE
  demonstration should use (versioned evidence, not flaky live APIs at eval time).

Both fail soft (return ChannelResult with .error, never raise) and take an injectable ``http``/reader
so unit tests run offline + deterministic. 3.9-safe; stdlib-only (urllib, csv, json).

STRING-PPI, pathway/TF, and CAPTAIN/scGPT-as-channel follow the same Channel contract; they're the
next adds (CAPTAIN needs weights+GPU, so it ships as an adapter run where those exist).
"""
import csv
import json
import os
import urllib.request
from typing import Any, Callable, Dict, List, Optional

from .channels import Channel
from .types import ChannelResult

OPENTARGETS_GQL = "https://api.platform.opentargets.org/api/v4/graphql"

# VERIFIED live 2026-10-20 (e.g. efoId=MONDO_0005105 -> melanoma associated targets).
_OT_ASSOC_QUERY = (
    "query($efo:String!,$size:Int!){disease(efoId:$efo){name "
    "associatedTargets(page:{index:0,size:$size}){count rows{target{approvedSymbol} score}}}}"
)


def _default_http_post(url: str, payload: Dict[str, Any], timeout: int = 25,
                       headers: Optional[Dict[str, str]] = None) -> Dict[str, Any]:
    data = json.dumps(payload).encode("utf-8")
    hdrs = {"Content-Type": "application/json"}
    if headers:
        hdrs.update(headers)
    req = urllib.request.Request(url, data=data, method="POST", headers=hdrs)
    with urllib.request.urlopen(req, timeout=timeout) as r:  # nosec - fixed https endpoint
        return json.loads(r.read().decode("utf-8"))


class OpenTargetsGeneticsChannel(Channel):
    """Target scores = OpenTargets disease-association scores (genetics + aggregated evidence).

    context keys: 'disease_id' (an EFO/MONDO id, e.g. 'MONDO_0005105'); falls back to the
    channel's default_disease_id. (Name->id resolution is a documented follow-up; v1 requires an
    id so we never guess an unverified query.) ``http`` is injectable for tests.
    """

    name = "genetics_ot"

    def __init__(self, default_disease_id: Optional[str] = None, size: int = 200,
                 http: Optional[Callable[..., Dict[str, Any]]] = None, name: str = "genetics_ot"):
        self.default_disease_id = default_disease_id
        self.size = size
        self.http = http or _default_http_post
        self.name = name

    def run(self, context: Dict[str, Any]) -> ChannelResult:
        efo = (context or {}).get("disease_id") or self.default_disease_id
        if not efo:
            return ChannelResult(channel=self.name,
                                 error="no disease_id in context (EFO/MONDO id required in v1)")
        try:
            resp = self.http(OPENTARGETS_GQL, {"query": _OT_ASSOC_QUERY,
                                               "variables": {"efo": efo, "size": int(self.size)}})
        except Exception as e:
            return ChannelResult(channel=self.name, error="OT request failed: %s: %s" % (type(e).__name__, e))
        if not isinstance(resp, dict):
            return ChannelResult(channel=self.name, error="OT returned non-dict")
        dis = (resp.get("data") or {}).get("disease")
        if not dis:
            return ChannelResult(channel=self.name, error="OT: disease %s did not resolve" % efo)
        rows = ((dis.get("associatedTargets") or {}).get("rows")) or []
        scores: Dict[str, float] = {}
        for row in rows:
            sym = ((row or {}).get("target") or {}).get("approvedSymbol")
            sc = (row or {}).get("score")
            if sym is None or sc is None:
                continue
            try:
                scores[str(sym).upper()] = float(sc)
            except Exception:
                continue
        if not scores:
            return ChannelResult(channel=self.name, error="OT: no scored targets for %s" % efo)
        return ChannelResult(channel=self.name, scores=scores,
                             provenance={"source": "OpenTargets Platform assoc", "disease": dis.get("name"),
                                         "disease_id": efo, "n": len(scores)})


class TableChannel(Channel):
    """Evidence from a cached CSV/TSV: columns target_col + score_col (+ optional filter_col).

    Use for reproducible, versioned evidence in the demonstration (DepMap, precomputed genetics,
    a frozen OT snapshot, CAPTAIN channel outputs dumped to disk, etc.). If ``filter_col`` is set,
    only rows whose filter_col == context[context_filter_key] are used. ``reader`` injectable for tests.
    """

    name = "table"

    def __init__(self, path: str, name: str = "table", target_col: str = "target",
                 score_col: str = "score", filter_col: Optional[str] = None,
                 context_filter_key: Optional[str] = None, delimiter: Optional[str] = None,
                 reader: Optional[Callable[[str], List[Dict[str, str]]]] = None):
        self.path = path
        self.name = name
        self.target_col = target_col
        self.score_col = score_col
        self.filter_col = filter_col
        self.context_filter_key = context_filter_key
        self.delimiter = delimiter
        self._reader = reader

    def _read_rows(self) -> List[Dict[str, str]]:
        if self._reader is not None:
            return self._reader(self.path)
        delim = self.delimiter or ("\t" if self.path.endswith((".tsv", ".txt")) else ",")
        with open(self.path, "r", newline="") as f:
            return list(csv.DictReader(f, delimiter=delim))

    def run(self, context: Dict[str, Any]) -> ChannelResult:
        if self._reader is None and not os.path.exists(self.path):
            return ChannelResult(channel=self.name, error="table not found: %s" % self.path)
        try:
            rows = self._read_rows()
        except Exception as e:
            return ChannelResult(channel=self.name, error="read failed: %s: %s" % (type(e).__name__, e))
        filt = None
        if self.filter_col and self.context_filter_key:
            filt = (context or {}).get(self.context_filter_key)
        scores: Dict[str, float] = {}
        for row in rows:
            if filt is not None and str(row.get(self.filter_col)) != str(filt):
                continue
            t = row.get(self.target_col)
            s = row.get(self.score_col)
            if t is None or s in (None, ""):
                continue
            try:
                scores[str(t).upper()] = float(s)
            except Exception:
                continue
        if not scores:
            return ChannelResult(channel=self.name, error="no rows matched (filter=%r)" % filt)
        return ChannelResult(channel=self.name, scores=scores,
                             provenance={"source": "table", "path": self.path, "n": len(scores)})


def default_channels(disease_id: Optional[str] = None, tables: Optional[List[Dict[str, Any]]] = None,
                     llm_client: Any = None) -> List[Channel]:
    """Assemble a sensible default channel set from whatever inputs are available.

    - OpenTargets genetics channel when a disease_id is given.
    - One TableChannel per entry in ``tables`` (each a kwargs dict for TableChannel).
    - LLMReasonedChannel when an llm_client is provided.
    Returns [] safely if nothing is available (orchestrator then reports no channels).
    """
    chans: List[Channel] = []
    if disease_id:
        chans.append(OpenTargetsGeneticsChannel(default_disease_id=disease_id))
    for t in (tables or []):
        chans.append(TableChannel(**t))
    if llm_client is not None:
        from .channels import LLMReasonedChannel
        chans.append(LLMReasonedChannel(llm_client))
    return chans
