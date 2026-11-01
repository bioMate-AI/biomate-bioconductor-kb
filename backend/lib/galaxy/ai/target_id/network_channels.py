"""Network / gene-set evidence channels (expansion from a seed gene set).

- StringPpiChannel: STRING-DB interaction_partners — scores candidate targets by PPI proximity
  to context['seed_genes']. API shape VERIFIED live 2026-10-20
  (interaction_partners -> rows{preferredName_A(seed), preferredName_B(partner), score 0-1}).
- PathwayCoMembershipChannel: guilt-by-association — scores candidates by how many gene sets they
  share with a seed (gene_sets injected or loaded from a GMT).

Both need context['seed_genes'] (e.g. known disease genes, the OT top hits, or the LLM plan's
candidates). Both fail soft + take injectable fetchers for offline tests. Degree bias in PPI is a
known caveat; the gate's union-universe z partially controls it and a degree-preserving null is the
pre-registered v2 upgrade. 3.9-safe, stdlib-only.
"""
import json
import urllib.parse
import urllib.request
from typing import Any, Callable, Dict, List, Optional

from .channels import Channel
from .types import ChannelResult

STRING_API = "https://string-db.org/api/json/"


def _string_get(endpoint: str, params: Dict[str, Any], timeout: int = 25) -> Any:
    url = STRING_API + endpoint + "?" + urllib.parse.urlencode(params)
    with urllib.request.urlopen(url, timeout=timeout) as r:  # nosec - fixed https endpoint
        return json.loads(r.read().decode("utf-8"))


class StringPpiChannel(Channel):
    """Candidate target score = PPI proximity to the seed set (STRING combined score).

    context: 'seed_genes' (List[str], required). agg="max" (strongest edge to any seed; less
    degree-biased) or "sum" (total connectivity). ``http`` injectable: http(endpoint, params)->rows.

    include_seed_edges (default False = candidate EXPANSION: seeds are kept out of the candidate set). When True
    (used by the live route, where the seeds ARE the Open Targets top genes being ranked) a seed is scored by its
    strongest edge to ANOTHER seed, so the top genes themselves get network corroboration rather than none.
    """

    name = "ppi_string"
    needs_seeds = True              # expands from a seed gene set supplied by the orchestrator's second stage

    def __init__(self, species: int = 9606, agg: str = "max", limit: int = 50,
                 http: Optional[Callable[..., Any]] = None, name: str = "ppi_string",
                 include_seed_edges: bool = False):
        self.include_seed_edges = include_seed_edges
        self.species = species
        self.agg = agg
        self.limit = limit
        self.http = http or _string_get
        self.name = name

    def run(self, context: Dict[str, Any]) -> ChannelResult:
        seeds = [str(s).upper() for s in ((context or {}).get("seed_genes") or [])]
        if not seeds:
            return ChannelResult(channel=self.name, error="no seed_genes in context")
        try:
            rows = self.http("interaction_partners", {
                "identifiers": "\r".join(seeds), "species": self.species,
                "limit": self.limit, "caller_identity": "biomate_target_id",
            })
        except Exception as e:
            return ChannelResult(channel=self.name, error="STRING request failed: %s: %s" % (type(e).__name__, e))
        if not isinstance(rows, list):
            return ChannelResult(channel=self.name, error="STRING returned non-list")
        seed_set = set(seeds)
        scores: Dict[str, float] = {}
        for row in rows:
            partner = str((row or {}).get("preferredName_B", "")).upper()
            anchor = str((row or {}).get("preferredName_A", "")).upper()
            if not partner:
                continue
            if partner in seed_set and not (self.include_seed_edges and anchor in seed_set and anchor != partner):
                continue                             # keep seeds out of the candidate set (unless scoring seed-to-seed edges)
            try:
                sc = float(row.get("score"))
            except Exception:
                continue
            if self.agg == "sum":
                scores[partner] = scores.get(partner, 0.0) + sc
            else:  # max
                scores[partner] = max(scores.get(partner, 0.0), sc)
        if not scores:
            return ChannelResult(channel=self.name, error="STRING: no partners for seeds")
        # the cgi/network form resolves for every client (the /network/<id> form returns 403 to non-browsers; checked 2026-11-01)
        links = {g: {"url": "https://string-db.org/cgi/network?identifiers=%s&species=%d" % (urllib.parse.quote(g), self.species),
                     "label": "STRING network: %s" % g} for g in scores}
        return ChannelResult(channel=self.name, scores=scores, links=links,
                             provenance={"source": "STRING interaction_partners", "agg": self.agg,
                                         "seeds": seeds, "n": len(scores), "seed_to_seed_edges": self.include_seed_edges})


def _load_gmt(path: str) -> Dict[str, set]:
    sets: Dict[str, set] = {}
    with open(path, "r") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 3:
                sets[parts[0]] = set(g.upper() for g in parts[2:] if g)
    return sets


class PathwayCoMembershipChannel(Channel):
    """Candidate score = number of gene sets shared with a seed (guilt-by-association).

    gene_sets: {set_name: iterable[gene]} injected, OR gmt_path to load. context: 'seed_genes' required.
    """

    name = "pathway_comembership"
    needs_seeds = True

    def __init__(self, gene_sets: Optional[Dict[str, Any]] = None, gmt_path: Optional[str] = None,
                 name: str = "pathway_comembership"):
        self._gene_sets = None
        if gene_sets is not None:
            self._gene_sets = {k: set(str(g).upper() for g in v) for k, v in gene_sets.items()}
        self.gmt_path = gmt_path
        self.name = name

    def _sets(self) -> Dict[str, set]:
        if self._gene_sets is not None:
            return self._gene_sets
        if self.gmt_path:
            self._gene_sets = _load_gmt(self.gmt_path)
            return self._gene_sets
        return {}

    def run(self, context: Dict[str, Any]) -> ChannelResult:
        seeds = set(str(s).upper() for s in ((context or {}).get("seed_genes") or []))
        if not seeds:
            return ChannelResult(channel=self.name, error="no seed_genes in context")
        try:
            sets = self._sets()
        except Exception as e:
            return ChannelResult(channel=self.name, error="gene-set load failed: %s: %s" % (type(e).__name__, e))
        if not sets:
            return ChannelResult(channel=self.name, error="no gene_sets available (inject gene_sets or gmt_path)")
        scores: Dict[str, float] = {}
        for genes in sets.values():
            if genes & seeds:                         # a seed is in this pathway
                for g in genes:
                    if g not in seeds:                # score the co-members (not the seeds)
                        scores[g] = scores.get(g, 0.0) + 1.0
        if not scores:
            return ChannelResult(channel=self.name, error="no co-members found for seeds")
        return ChannelResult(channel=self.name, scores=scores,
                             provenance={"source": "pathway co-membership", "n_sets": len(sets),
                                         "seeds": sorted(seeds), "n": len(scores)})
