"""K2 loader: read knowledge_kb_scaled_v1.jsonl with the filters the experiments need. Compatible fields with the K schema."""
import json


def load_rules(path, min_tier="T2", require_entailment=True, exclude_benchmark_overlap=True, min_papers=1,
               exclude_conflict=False, properties=None):
    rank = {"T1": 0, "T2": 1, "T3": 2}
    out = []
    for line in open(path):
        r = json.loads(line)
        if rank[r["evidence_tier"]] > rank[min_tier]:
            continue
        if require_entailment and r.get("proxy_entailment") != "YES":
            continue
        if exclude_benchmark_overlap and r.get("possible_benchmark_source"):
            continue
        if r["support"]["n_papers"] < min_papers:
            continue
        if exclude_conflict and r.get("direction_conflict_in_cell"):
            continue
        if properties and r["property"] not in properties:
            continue
        out.append(r)
    return out


def context_snippets(rules, substructure=None, prop=None, k=8):
    """Short provenance-tagged sentences for retrieval prompts."""
    rs = [r for r in rules if (substructure is None or r["substructure_class"] == substructure) and (prop is None or r["property"] == prop)]
    rs.sort(key=lambda r: (-r["support"]["n_papers"], r["evidence_tier"], -r["confidence"]))
    return [f"{r['statement']} [{r['evidence_tier']}, {r['support']['n_papers']} paper(s), {r['citation'].get('doi') or r['citation']['pmcid']}]"
            for r in rs[:k]]
