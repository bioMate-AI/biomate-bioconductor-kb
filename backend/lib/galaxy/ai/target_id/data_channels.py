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
import re
import urllib.request
from typing import Any, Callable, Dict, List, Optional

from .channels import Channel
from .types import ChannelResult

OPENTARGETS_GQL = "https://api.platform.opentargets.org/api/v4/graphql"

# VERIFIED live 2026-10-20 (e.g. efoId=MONDO_0005105 -> melanoma associated targets); ``target{id}`` (the
# Ensembl gene id) added and re-verified live 2026-11-01 so each row can link to its Open Targets evidence page.
_OT_ASSOC_QUERY = (
    "query($efo:String!,$size:Int!){disease(efoId:$efo){name "
    "associatedTargets(page:{index:0,size:$size}){count rows{target{id approvedSymbol} score}}}}"
)
OT_EVIDENCE_URL = "https://platform.opentargets.org/evidence/%s/%s"
OT_SEARCH_URL = "https://platform.opentargets.org/search?q=%s"


def _truthy(v: Optional[str]) -> bool:
    return str(v or "").strip().lower() in ("1", "true", "yes", "on")


def offline_mode() -> bool:
    """True when the deployment forbids external calls (TARGET_ID_OFFLINE=1). Channels then use local snapshots only."""
    return _truthy(os.environ.get("TARGET_ID_OFFLINE")) or _truthy(os.environ.get("BIOMATE_OFFLINE"))


def snapshot_dir() -> Optional[str]:
    return os.environ.get("TARGET_ID_SNAPSHOT_DIR") or None


def snapshot_path(directory: str, efo: str) -> str:
    safe = "".join(ch for ch in str(efo) if ch.isalnum() or ch in "_-")
    return os.path.join(directory, "ot_%s.json" % safe)


def list_snapshots(directory: Optional[str]) -> List[str]:
    if not directory or not os.path.isdir(directory):
        return []
    out = []
    for f in sorted(os.listdir(directory)):
        if f.startswith("ot_") and f.endswith(".json"):
            out.append(f[3:-5])
    return out


def _default_http_post(url: str, payload: Dict[str, Any], timeout: int = 25,
                       headers: Optional[Dict[str, str]] = None) -> Dict[str, Any]:
    data = json.dumps(payload).encode("utf-8")
    hdrs = {"Content-Type": "application/json"}
    if headers:
        hdrs.update(headers)
    req = urllib.request.Request(url, data=data, method="POST", headers=hdrs)
    with urllib.request.urlopen(req, timeout=timeout) as r:  # nosec - fixed https endpoint
        return json.loads(r.read().decode("utf-8"))


def resolve_disease_name(name: str, http: Optional[Callable[..., Any]] = None) -> Dict[str, str]:
    """Resolve an exact public disease name, never a guessed first search hit.

    Ambiguous/nonexact names require clarification. Offline installations must
    supply a verified identifier instead of silently making an external call.
    """
    if offline_mode():
        raise ValueError('Disease-name lookup is unavailable offline; provide a verified disease_id')
    if not isinstance(name, str) or not name.strip() or len(name.strip()) > 300:
        raise ValueError('disease must be a non-empty name of at most 300 characters')
    query = ('query($name:String!){search(queryString:$name,entityNames:["disease"],'
             'page:{index:0,size:20}){hits{id name}}}')
    response = (http or _default_http_post)(OPENTARGETS_GQL, {'query': query, 'variables': {'name': name.strip()}})
    if not isinstance(response, dict) or response.get('errors'):
        raise RuntimeError('Open Targets disease-name lookup failed')
    hits = ((response.get('data') or {}).get('search') or {}).get('hits')
    if not isinstance(hits, list):
        raise RuntimeError('Open Targets disease-name lookup returned invalid results')
    normalize = lambda text: re.sub(r'[\s\-\u2010-\u2015]+', ' ', text.strip().casefold())
    exact = {hit['id']: hit['name'] for hit in hits if isinstance(hit, dict)
             and isinstance(hit.get('name'), str) and isinstance(hit.get('id'), str)
             and re.fullmatch(r'(?:EFO|MONDO)_\d+', hit['id'])
             and normalize(hit['name']) == normalize(name)}
    if not exact:
        # Search also indexes ontology synonyms. Verify them against the source
        # and accept ONLY hasExactSynonym, never broad/narrow/related matches.
        identifiers = sorted({hit['id'] for hit in hits if isinstance(hit, dict)
                              and isinstance(hit.get('id'), str)
                              and re.fullmatch(r'(?:EFO|MONDO)_\d+', hit['id'])})[:20]
        if identifiers:
            declarations = ','.join('$d%d:String!' % i for i in range(len(identifiers)))
            fields = ' '.join('d%d:disease(efoId:$d%d){name synonyms{relation terms}}' % (i, i)
                              for i in range(len(identifiers)))
            synonyms = (http or _default_http_post)(OPENTARGETS_GQL, {
                'query': 'query(' + declarations + '){' + fields + '}',
                'variables': {'d%d' % i: identifier for i, identifier in enumerate(identifiers)},
            })
            if not isinstance(synonyms, dict) or synonyms.get('errors') or not isinstance(synonyms.get('data'), dict):
                raise RuntimeError('Open Targets exact-synonym verification failed')
            for i, identifier in enumerate(identifiers):
                record = synonyms['data'].get('d%d' % i)
                if not isinstance(record, dict) or not isinstance(record.get('name'), str):
                    continue
                groups = record.get('synonyms')
                if not isinstance(groups, list):
                    continue
                names = [record['name']]
                for group in groups:
                    if isinstance(group, dict) and group.get('relation') == 'hasExactSynonym' and isinstance(group.get('terms'), list):
                        names.extend(term for term in group['terms'] if isinstance(term, str))
                if any(normalize(term) == normalize(name) for term in names):
                    exact[identifier] = record['name']
    if len(exact) != 1:
        raise ValueError('Disease name has no unique exact match in Open Targets; provide the full disease name or a verified disease_id')
    identifier, label = next(iter(exact.items()))
    return {'disease_id': identifier, 'disease': label, 'source': 'Open Targets disease search'}


class OpenTargetsGeneticsChannel(Channel):
    """Target scores = OpenTargets disease-association scores (genetics + aggregated evidence).

    context keys: 'disease_id' (an EFO/MONDO id, e.g. 'MONDO_0005105'); falls back to the
    channel's default_disease_id. (Name->id resolution is a documented follow-up; v1 requires an
    id so we never guess an unverified query.) ``http`` is injectable for tests.
    """

    name = "genetics_ot"

    def __init__(self, default_disease_id: Optional[str] = None, size: int = 200,
                 http: Optional[Callable[..., Dict[str, Any]]] = None, name: str = "genetics_ot",
                 snapshot_directory: Optional[str] = None, offline: Optional[bool] = None):
        self.default_disease_id = default_disease_id
        self.size = size
        self.http = http or _default_http_post
        self.name = name
        self.snapshot_directory = snapshot_directory
        self.offline = offline

    # -- snapshot helpers ---------------------------------------------------------------------
    def _snapshot_dir(self) -> Optional[str]:
        return self.snapshot_directory or snapshot_dir()

    def _from_snapshot(self, efo: str, live_error: Optional[str]) -> ChannelResult:
        d = self._snapshot_dir()
        if not d:
            return ChannelResult(channel=self.name, error=(live_error or "offline mode") + "; no TARGET_ID_SNAPSHOT_DIR configured")
        p = snapshot_path(d, efo)
        if not os.path.exists(p):
            return ChannelResult(channel=self.name, error="%s; no snapshot for %s (available: %s)" % (
                live_error or "offline mode", efo, ", ".join(list_snapshots(d)) or "none"))
        try:
            with open(p) as fh:
                snap = json.load(fh)
        except Exception as e:
            return ChannelResult(channel=self.name, error="snapshot unreadable: %s: %s" % (type(e).__name__, e))
        return self._build_result(efo, snap.get("disease"), snap.get("rows") or [], served_from="snapshot",
                                  extra={"snapshot_date": snap.get("snapshot_date"), "live_error": live_error})

    def _build_result(self, efo: str, disease_name: Optional[str], rows: List[Dict[str, Any]],
                      served_from: str, extra: Optional[Dict[str, Any]] = None) -> ChannelResult:
        scores: Dict[str, float] = {}
        links: Dict[str, Dict[str, str]] = {}
        for row in rows:
            sym, sc, gid = row.get("symbol"), row.get("score"), row.get("id")
            if sym is None or sc is None:
                continue
            try:
                scores[str(sym).upper()] = float(sc)
            except Exception:
                continue
            key = str(sym).upper()
            if gid:
                links[key] = {"url": OT_EVIDENCE_URL % (gid, efo), "label": "Open Targets evidence: %s in %s" % (key, disease_name or efo)}
            else:
                links[key] = {"url": OT_SEARCH_URL % key, "label": "Open Targets search: %s" % key}
        if not scores:
            return ChannelResult(channel=self.name, error="OT: no scored targets for %s" % efo)
        prov = {"source": "OpenTargets Platform assoc", "disease": disease_name, "disease_id": efo,
                "n": len(scores), "served_from": served_from}
        prov.update(extra or {})
        return ChannelResult(channel=self.name, scores=scores, provenance=prov, links=links, evidence_kind="public_source")

    def run(self, context: Dict[str, Any]) -> ChannelResult:
        efo = (context or {}).get("disease_id") or self.default_disease_id
        if not efo:
            return ChannelResult(channel=self.name,
                                 error="no disease_id in context (EFO/MONDO id required in v1)")
        off = offline_mode() if self.offline is None else bool(self.offline)
        if off:
            return self._from_snapshot(efo, None)
        try:
            resp = self.http(OPENTARGETS_GQL, {"query": _OT_ASSOC_QUERY,
                                               "variables": {"efo": efo, "size": int(self.size)}})
        except Exception as e:
            return self._from_snapshot(efo, "OT request failed: %s: %s" % (type(e).__name__, e)) \
                if self._snapshot_dir() else ChannelResult(channel=self.name, error="OT request failed: %s: %s" % (type(e).__name__, e))
        if not isinstance(resp, dict):
            return ChannelResult(channel=self.name, error="OT returned non-dict")
        dis = (resp.get("data") or {}).get("disease")
        if not dis:
            return ChannelResult(channel=self.name, error="OT: disease %s did not resolve" % efo)
        rows = []
        for row in ((dis.get("associatedTargets") or {}).get("rows")) or []:
            tgt = (row or {}).get("target") or {}
            rows.append({"symbol": tgt.get("approvedSymbol"), "id": tgt.get("id"), "score": (row or {}).get("score")})
        return self._build_result(efo, dis.get("name"), rows, served_from="live")


def write_ot_snapshot(efo: str, directory: str, size: int = 500, http: Optional[Callable[..., Dict[str, Any]]] = None,
                      today: Optional[str] = None) -> str:
    """Fetch Open Targets associations for ``efo`` (needs network) and store them for offline use. Returns the path."""
    import datetime
    ch = OpenTargetsGeneticsChannel(size=size, http=http, offline=False, snapshot_directory=None)
    resp = (http or _default_http_post)(OPENTARGETS_GQL, {"query": _OT_ASSOC_QUERY, "variables": {"efo": efo, "size": int(size)}})
    dis = (resp.get("data") or {}).get("disease")
    if not dis:
        raise ValueError("disease %s did not resolve" % efo)
    rows = []
    for row in ((dis.get("associatedTargets") or {}).get("rows")) or []:
        tgt = (row or {}).get("target") or {}
        rows.append({"symbol": tgt.get("approvedSymbol"), "id": tgt.get("id"), "score": (row or {}).get("score")})
    os.makedirs(directory, exist_ok=True)
    path = snapshot_path(directory, efo)
    with open(path, "w") as fh:
        json.dump({"source": "Open Targets Platform (api v4)", "disease_id": efo, "disease": dis.get("name"),
                   "snapshot_date": today or datetime.date.today().isoformat(), "n_rows": len(rows), "rows": rows}, fh)
    return path


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
                 reader: Optional[Callable[[str], List[Dict[str, str]]]] = None, evidence_kind: str = "table"):
        self.evidence_kind = evidence_kind
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
            return ChannelResult(channel=self.name, evidence_kind=self.evidence_kind, error="table not found: %s" % os.path.basename(self.path))
        try:
            rows = self._read_rows()
        except Exception as e:
            return ChannelResult(channel=self.name, evidence_kind=self.evidence_kind, error="read failed: %s" % type(e).__name__)
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
            return ChannelResult(channel=self.name, evidence_kind=self.evidence_kind, error="no rows matched (filter=%r)" % filt)
        return ChannelResult(channel=self.name, scores=scores, evidence_kind=self.evidence_kind,
                             provenance={"source": "table", "table": os.path.basename(self.path), "n": len(scores)})


def frozen_fm_channel(path: str, model_name: str = "captain", **table_kwargs) -> "TableChannel":
    """A frozen SOTA cell-FM (CAPTAIN / scGPT) as a target-ID CHANNEL — never the arbiter.

    The FM's precomputed per-target relevance scores (produced where GPU + public weights exist,
    then dumped to a CSV/TSV ``target,score``) enter as a TableChannel so the FM is a probationary
    column that must earn linear-advantage through the gate like any other channel. We deliberately
    do NOT run GPU inference inside the orchestrator.

    Runner spec (to produce ``path``): run CAPTAIN (github.com/iamjiboya/CAPTAIN, CAPTAIN_Base /
    CAPTAIN_PBMC weights) — e.g. its protein-informed cell-cell-communication task on the cohort —
    map the FM output to per-gene relevance, and write a ``target,score`` table. scGPT is analogous.
    Provenance is tagged with the model name so the arbiter's audit shows it as an FM channel.
    """
    ch = TableChannel(path, name=model_name, **table_kwargs)
    return ch


def default_channels(disease_id: Optional[str] = None, tables: Optional[List[Dict[str, Any]]] = None,
                     llm_client: Any = None, client_tables: Optional[List[Dict[str, Any]]] = None,
                     include_network: bool = True, gmt_path: Optional[str] = None) -> List[Channel]:
    """Assemble a sensible default channel set from whatever inputs are available.

    - OpenTargets genetics channel when a disease_id is given, plus (include_network) the STRING network
      channel and, if a gene-set file is configured (TARGET_ID_GMT_PATH), the pathway channel. The network
      channels expand from the Open Targets top genes in the orchestrator's second stage, so they run in the
      live route; STRING needs the network and is skipped in offline mode.
    - One TableChannel per entry in ``tables`` (already vetted by table_policy.safe_table_specs).
    - One ClientTableChannel per entry in ``client_tables`` (the hospital's own analysis results, inline rows).
    - LLMReasonedChannel when an llm_client is provided.
    Returns [] safely if nothing is available (orchestrator then reports no channels).
    """
    from .client_data import build_client_channels
    chans: List[Channel] = []
    if disease_id:
        chans.append(OpenTargetsGeneticsChannel(default_disease_id=disease_id))
        if include_network:
            from .network_channels import PathwayCoMembershipChannel, StringPpiChannel
            if not offline_mode():
                chans.append(StringPpiChannel(include_seed_edges=True))
            gp = gmt_path or os.environ.get("TARGET_ID_GMT_PATH")
            if gp and os.path.exists(gp):
                chans.append(PathwayCoMembershipChannel(gmt_path=gp))
    for t in (tables or []):
        chans.append(TableChannel(**t))
    chans.extend(build_client_channels(client_tables))
    if llm_client is not None:
        from .channels import LLMReasonedChannel
        chans.append(LLMReasonedChannel(llm_client))
    return chans
