"""Drug-type (modality) selector for target-ID: which drug type is a sensible STARTING POINT for a target?

Options ranked: small_molecule | biologic (antibody or other protein) | macrocycle_peptide | other
(oligonucleotide / degrader / cell or gene approaches).

DESIGN (anti-circularity, see docs/20261101_TARGETID_MODALITY_SELECTOR.md):
  The EVALUATED selector (``select_modality``) uses ONLY properties that are not derived from drug precedent:
  UniProt signal peptide, transmembrane count, topological-domain lengths, subcellular-location text,
  EC number, protein-family / keyword annotation, and chain length. It does NOT use Open Targets
  tractability buckets, ChEMBL activity/mechanism data, ligand-bound structures, or UniProt
  pharmaceutical/drug-related text, all of which partly encode the approved-drug answer.
  ``precedent_aware_modality`` (Open Targets tractability) is a SEPARATE, labelled mode that must never be
  scored on an approved-drug gold set.

The output is guidance: ``validated`` is False unless the evaluation (modality_eval.py) supports it.

Fetchers take an injectable ``http_get(url) -> parsed JSON`` so tests run offline. Fail soft; 3.9-safe;
stdlib only.
"""
import hashlib
import json
import os
import time
import urllib.parse
import urllib.request
from typing import Any, Callable, Dict, List, Optional

UNIPROT_SEARCH = "https://rest.uniprot.org/uniprotkb/search"
UNIPROT_FIELDS = "accession,gene_primary,length,cc_subcellular_location,ft_signal,ft_transmem,ft_topo_dom,cc_similarity,ec,keyword,organism_id"
OT_GQL = "https://api.platform.opentargets.org/api/v4/graphql"

MODALITIES = ("small_molecule", "biologic", "macrocycle_peptide", "other")
# Set True only if modality_eval.py shows the selector beats the baselines on the held-out split.
VALIDATED = False
GUIDANCE_NOTE = ("Guidance only: a rule-based starting-point suggestion from protein-level annotations. "
                 "It is not a validated prediction; see the evaluation document for measured agreement.")

HttpGet = Callable[..., Any]


# --------------------------------------------------------------------------- fetching

def _default_http_get(url: str, timeout: int = 40, retries: int = 3) -> Any:
    last = None
    for i in range(retries):
        try:
            req = urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": "biomate-targetid/1"})
            with urllib.request.urlopen(req, timeout=timeout) as r:  # nosec - fixed https endpoints
                return json.loads(r.read().decode("utf-8"))
        except Exception as e:  # noqa: BLE001
            last = e
            time.sleep(1.5 * (i + 1))
    raise last  # type: ignore[misc]


def _cache_get(http_get: HttpGet, url: str, cache_dir: Optional[str]) -> Any:
    if cache_dir:
        os.makedirs(cache_dir, exist_ok=True)
        p = os.path.join(cache_dir, hashlib.sha1(url.encode("utf-8")).hexdigest() + ".json")
        if os.path.exists(p):
            with open(p) as f:
                return json.load(f)
        data = http_get(url)
        with open(p, "w") as f:
            json.dump(data, f)
        return data
    return http_get(url)


def _loc(f: Dict[str, Any]) -> Any:
    try:
        return int(f["location"]["start"]["value"]), int(f["location"]["end"]["value"])
    except Exception:  # noqa: BLE001
        return None


def parse_uniprot_entry(e: Dict[str, Any]) -> Dict[str, Any]:
    """Reduce one UniProtKB JSON entry to the property dict the selector uses (pure function)."""
    feats = e.get("features") or []
    n_tm = sum(1 for f in feats if f.get("type") == "Transmembrane")
    signal = any(f.get("type") == "Signal" for f in feats)
    ecd = icd = 0
    for f in feats:
        if f.get("type") != "Topological domain":
            continue
        lo = _loc(f)
        if not lo:
            continue
        d = (f.get("description") or "").lower()
        n = lo[1] - lo[0] + 1
        if d.startswith("extracellular"):
            ecd = max(ecd, n)
        elif d.startswith("cytoplasmic"):
            icd = max(icd, n)
    locs: List[str] = []
    similarity = ""
    for c in e.get("comments") or []:
        if c.get("commentType") == "SUBCELLULAR LOCATION":
            for sl in c.get("subcellularLocations") or []:
                v = (sl.get("location") or {}).get("value")
                if v:
                    locs.append(v)
        elif c.get("commentType") == "SIMILARITY":
            for t in c.get("texts") or []:
                similarity += (t.get("value") or "") + " "
    ec = []
    pd = e.get("proteinDescription") or {}
    for blk in (pd.get("recommendedName"), ) + tuple(pd.get("alternativeNames") or ()):
        for x in ((blk or {}).get("ecNumbers") or []):
            if x.get("value"):
                ec.append(x["value"])
    genes = e.get("genes") or []
    sym = ""
    if genes and (genes[0].get("geneName") or {}).get("value"):
        sym = genes[0]["geneName"]["value"]
    return {
        "accession": e.get("primaryAccession"),
        "gene": sym,
        "length": (e.get("sequence") or {}).get("length"),
        "signal_peptide": signal,
        "n_tm": n_tm,
        "extracellular_len": ecd,
        "cytoplasmic_len": icd,
        "locations": locs,
        "ec": sorted(set(ec)),
        "keywords": [k.get("name") for k in e.get("keywords") or [] if k.get("name")],
        "family_text": similarity.strip(),
        "organism_id": (e.get("organism") or {}).get("taxonId"),
        "source": "UniProtKB (reviewed) " + str(e.get("primaryAccession")),
    }


def fetch_uniprot_features(accessions: List[str], http_get: Optional[HttpGet] = None,
                           cache_dir: Optional[str] = None, batch: int = 60) -> Dict[str, Dict[str, Any]]:
    """accession -> property dict. Batched (<= ``batch`` per request). Missing accessions are absent."""
    http_get = http_get or _default_http_get
    out: Dict[str, Dict[str, Any]] = {}
    accs = sorted(set(a for a in accessions if a))
    for i in range(0, len(accs), batch):
        chunk = accs[i:i + batch]
        q = "(" + " OR ".join("accession:" + a for a in chunk) + ")"
        url = UNIPROT_SEARCH + "?" + urllib.parse.urlencode(
            {"query": q, "fields": UNIPROT_FIELDS, "format": "json", "size": str(len(chunk))})
        try:
            data = _cache_get(http_get, url, cache_dir)
        except Exception:  # noqa: BLE001  fail soft
            continue
        for e in (data or {}).get("results") or []:
            p = parse_uniprot_entry(e)
            if p["accession"]:
                out[p["accession"]] = p
    return out


def fetch_features_for_symbol(symbol: str, http_get: Optional[HttpGet] = None,
                              cache_dir: Optional[str] = None) -> Optional[Dict[str, Any]]:
    """Human reviewed UniProt entry for a gene symbol (exact match), or None."""
    http_get = http_get or _default_http_get
    q = "gene_exact:%s AND organism_id:9606 AND reviewed:true" % symbol
    url = UNIPROT_SEARCH + "?" + urllib.parse.urlencode(
        {"query": q, "fields": UNIPROT_FIELDS, "format": "json", "size": "1"})
    try:
        data = _cache_get(http_get, url, cache_dir)
    except Exception:  # noqa: BLE001
        return None
    res = (data or {}).get("results") or []
    return parse_uniprot_entry(res[0]) if res else None


# --------------------------------------------------------------------------- selector

def _kw(props: Dict[str, Any]) -> set:
    return set(k.lower() for k in props.get("keywords") or [])


def _is_secreted(props: Dict[str, Any]) -> bool:
    return any("secreted" in l.lower() or "extracellular space" in l.lower() or "extracellular matrix" in l.lower()
               for l in props.get("locations") or [])


def classify_location(props: Dict[str, Any]) -> str:
    n_tm = int(props.get("n_tm") or 0)
    kw = _kw(props)
    if n_tm >= 4:
        return "membrane_multipass"
    if n_tm >= 1:
        return "membrane_single_or_few"
    if "gpi-anchor" in kw:
        return "membrane_gpi"
    if props.get("signal_peptide") and (_is_secreted(props) or not props.get("locations")):
        return "secreted"
    if _is_secreted(props):
        return "secreted"
    return "intracellular"


def select_modality(props: Dict[str, Any]) -> Dict[str, Any]:
    """Rule-based, precedent-free modality suggestion with a rationale citing the property values used."""
    kw = _kw(props)
    fam = (props.get("family_text") or "").lower()
    ec = props.get("ec") or []
    length = props.get("length") or 0
    ecd = int(props.get("extracellular_len") or 0)
    loc = classify_location(props)
    s = {m: 0.0 for m in MODALITIES}
    why: List[str] = []

    kinase = "kinase" in kw or "protein kinase" in fam
    gpcr = "g-protein coupled receptor" in kw or "g-protein coupled receptor" in fam
    nuc_rec = "nuclear receptor" in fam or "nuclear receptor" in kw or "steroid hormone receptor" in fam
    channel = bool(kw & {"ion channel", "voltage-gated channel", "ligand-gated ion channel", "potassium channel",
                         "sodium channel", "calcium channel", "chloride channel"})
    transporter = "transport" in kw and loc.startswith("membrane")
    cytokine = bool(kw & {"cytokine", "growth factor", "hormone"})
    class_b_gpcr = "g-protein coupled receptor 2 family" in fam
    enzyme = bool(ec) or bool(kw & {"hydrolase", "transferase", "oxidoreductase", "protease", "lyase", "isomerase", "ligase"})

    if loc == "membrane_multipass":
        s["small_molecule"] += 4
        s["biologic"] += 1
        why.append("multi-pass membrane protein (%d transmembrane helices): ligand-binding pocket in the membrane" % props.get("n_tm", 0))
        if ecd >= 150:
            s["biologic"] += 1.5
            why.append("large extracellular domain (%d aa) is antibody-accessible" % ecd)
        if class_b_gpcr:
            s["biologic"] += 3.5
            s["macrocycle_peptide"] += 1.5
            why.append("GPCR family 2 (secretin/class B) annotation: peptide-hormone receptor, orthosteric site binds a large peptide")
    elif loc in ("membrane_single_or_few", "membrane_gpi"):
        s["biologic"] += 3
        s["macrocycle_peptide"] += 0.5
        why.append("membrane protein with %d transmembrane segment(s)%s" % (props.get("n_tm", 0), "" if loc == "membrane_single_or_few" else " (GPI-anchored)"))
        if ecd >= 100:
            s["biologic"] += 1.5
            why.append("extracellular domain %d aa" % ecd)
        elif loc == "membrane_single_or_few" and ecd == 0:
            s["small_molecule"] += 1.5
            why.append("no annotated extracellular domain")
        if enzyme or kinase:
            s["small_molecule"] += 4.5
            why.append("catalytic activity (%s)" % ("kinase" if kinase else "EC " + ",".join(ec)))
    elif loc == "secreted":
        s["biologic"] += 3.5
        s["macrocycle_peptide"] += 1.0
        why.append("secreted protein (signal peptide=%s, location: %s)" % (bool(props.get("signal_peptide")), "; ".join(props.get("locations") or []) or "n/a"))
        if cytokine:
            s["biologic"] += 1.5
            why.append("cytokine / growth-factor / hormone annotation")
        if enzyme:
            s["small_molecule"] += 4
            why.append("secreted enzyme (EC %s)" % ",".join(ec) if ec else "secreted enzyme-class keyword")
        if length and length < 120:
            s["macrocycle_peptide"] += 0.5
    else:  # intracellular
        s["small_molecule"] += 3
        why.append("intracellular protein (no signal peptide or transmembrane segment; location: %s)" % ("; ".join(props.get("locations") or []) or "n/a"))
        if enzyme or kinase:
            s["small_molecule"] += 2.5
            why.append("enzyme (%s): active-site pocket" % ("kinase" if kinase else "EC " + ",".join(ec or ["keyword"])))
        else:
            s["small_molecule"] -= 1.0
            s["macrocycle_peptide"] += 1.0
            s["other"] += 1.0
            why.append("no catalytic annotation: pocket less certain, interface-type target (constrained peptide / oligonucleotide / degrader options)")
        if length and length > 1500:
            s["small_molecule"] -= 0.5
            why.append("very large protein (%d aa)" % length)

    if kinase and loc == "intracellular":
        why.append("protein-kinase family annotation")
    if gpcr:
        s["small_molecule"] += 1.5
        why.append("GPCR family annotation")
    if nuc_rec:
        s["small_molecule"] += 3
        why.append("nuclear-receptor family annotation (lipophilic ligand pocket)")
    if channel:
        s["small_molecule"] += 2
        why.append("ion-channel keyword")
    if transporter:
        s["small_molecule"] += 1
        why.append("membrane transport keyword")

    ranked = sorted(MODALITIES, key=lambda m: (-s[m], MODALITIES.index(m)))
    margin = s[ranked[0]] - s[ranked[1]]
    conf = "high" if margin >= 3 else ("medium" if margin >= 1.5 else "low")
    return {
        "target": props.get("gene") or props.get("accession"),
        "accession": props.get("accession"),
        "ranked_options": [{"modality": m, "score": round(s[m], 2)} for m in ranked],
        "top": ranked[0],
        "confidence": conf,
        "confidence_statement": "%s: score margin %.1f between '%s' and '%s' (rule scores are heuristic units, not probabilities)." % (conf, margin, ranked[0], ranked[1]),
        "location_class": loc,
        "properties": {k: props.get(k) for k in ("signal_peptide", "n_tm", "extracellular_len", "cytoplasmic_len", "length", "locations", "ec")},
        "rationale": "; ".join(why),
        "sources": [props.get("source", "UniProtKB")],
        "uses_drug_precedent": False,
        "validated": VALIDATED,
        "note": GUIDANCE_NOTE,
    }


def baseline_membrane_rule(props: Dict[str, Any]) -> str:
    """Simple baseline: extracellular or membrane-exposed -> biologic, otherwise small molecule."""
    exposed = bool(props.get("signal_peptide")) or int(props.get("n_tm") or 0) >= 1 or _is_secreted(props)
    return "biologic" if exposed else "small_molecule"


def suggest_modality(symbol: str, http_get: Optional[HttpGet] = None, cache_dir: Optional[str] = None) -> Dict[str, Any]:
    """Public entry point: gene symbol -> selector result (fails soft with an ``error`` key)."""
    props = fetch_features_for_symbol(symbol, http_get, cache_dir)
    if not props:
        return {"target": symbol, "error": "no reviewed human UniProt entry found or UniProt unreachable",
                "ranked_options": [], "validated": False, "note": GUIDANCE_NOTE}
    res = select_modality(props)
    res["target"] = symbol
    return res


# --------------------------------------------------------------------------- precedent-aware mode (separate)

_OT_TRACT_QUERY = ("query($q:String!){search(queryString:$q,entityNames:[\"target\"],page:{index:0,size:1})"
                   "{hits{id}}}")
_OT_TRACT_BY_ID = ("query($id:String!){target(ensemblId:$id){approvedSymbol tractability{modality label value}}}")


def precedent_aware_modality(symbol: str, http_post: Optional[Callable[..., Any]] = None) -> Dict[str, Any]:
    """Open Targets tractability by modality. PRECEDENT-AWARE: the buckets partly derive from approved-drug and
    clinical precedent, so this must NOT be scored against an approved-drug gold set. Labelled accordingly."""
    def _post(payload):
        if http_post:
            return http_post(OT_GQL, payload)
        req = urllib.request.Request(OT_GQL, data=json.dumps(payload).encode(), method="POST",
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=30) as r:  # nosec - fixed endpoint
            return json.loads(r.read().decode())
    try:
        hit = _post({"query": _OT_TRACT_QUERY, "variables": {"q": symbol}})["data"]["search"]["hits"]
        if not hit:
            return {"target": symbol, "error": "target not found", "mode": "precedent_aware"}
        t = _post({"query": _OT_TRACT_BY_ID, "variables": {"id": hit[0]["id"]}})["data"]["target"]
    except Exception as e:  # noqa: BLE001
        return {"target": symbol, "error": str(e)[:200], "mode": "precedent_aware"}
    mod_map = {"SM": "small_molecule", "AB": "biologic", "PR": "other", "OC": "other"}
    best: Dict[str, int] = {}
    for r in t.get("tractability") or []:
        if r.get("value"):
            best[mod_map.get(r["modality"], "other")] = best.get(mod_map.get(r["modality"], "other"), 0) + 1
    ranked = sorted(best, key=lambda m: -best[m])
    return {"target": symbol, "mode": "precedent_aware", "uses_drug_precedent": True,
            "ranked_options": [{"modality": m, "n_positive_buckets": best[m]} for m in ranked],
            "sources": ["Open Targets Platform tractability (%s)" % OT_GQL],
            "note": "Precedent-aware: buckets partly derive from approved-drug/clinical precedent. Not evaluated, not a prediction."}
