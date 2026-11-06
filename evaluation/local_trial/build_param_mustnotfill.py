#!/usr/bin/env python3
"""Build param `must_not_fill` negative anchors to fix the 34->61 over-fill regression
(docs/.../20261006_SFT_V2_DECOMP_RETRAIN.md). Teaches the model to NOT fill optional /
conditional params the request does not state.

Real source only: workflows.params_schema (optional flags + real descriptions). NO fabrication:
the query is the workflow's own description; the correct extraction for a bare-intent query is
the empty set (defaults are applied by the system, not "filled" by extraction), with the
schema's OPTIONAL params listed as must_not_fill. A small rule layer fills the one param a
deterministic signal in the description licenses (e.g. 'human' -> genome/species), so the
lesson is selective restraint, not "always empty".

Leakage control: the param_prefill EVAL (evaluation/datasets/public_export/param_prefill/data.jsonl)
is query->params with NO workflow names; these anchors are workflow-description->params. We also
drop any anchor whose query duplicates an eval user_query.

Out: docs/20260912_onprem_llm/data_pool_v2/param_mustnotfill_neg.jsonl
"""
import sqlite3, json, re, os, hashlib, collections

REPO = "/Users/kky/biomate-review"
DB = f"{REPO}/backend/database/galaxy_ai_tools.db"
EVAL = f"{REPO}/evaluation/datasets/public_export/param_prefill/data.jsonl"
OUT = f"{REPO}/docs/20260912_onprem_llm/data_pool_v2/param_mustnotfill_neg.jsonl"

SYS = ("You are BioMate's parameter extractor. Extract ONLY the workflow parameters the user "
       "EXPLICITLY states or unambiguously implies. Do NOT fill optional or conditional "
       "parameters the user did not mention — leave them to the workflow defaults. Reply ONLY "
       "a JSON object of the parameters to set (use {} if the request specifies none).")

# deterministic, licensed fills (rule layer per CLAUDE.md hybrid rule+LLM policy).
# A signal fills a param ONLY if that param exists in the workflow schema.
GENOME_PARAMS = {'genome', 'species', 'organism', 'reference', 'assembly', 'genome_build', 'ref_genome'}
SIGNALS = [
    (r'\b(human|homo sapiens)\b', {g: v for g in GENOME_PARAMS
     for v in [{'genome': 'GRCh38', 'species': 'homo_sapiens', 'organism': 'human',
                'reference': 'GRCh38', 'assembly': 'GRCh38', 'genome_build': 'GRCh38',
                'ref_genome': 'GRCh38'}[g]]}),
    (r'\b(mouse|mus musculus|murine)\b', {g: v for g in GENOME_PARAMS
     for v in [{'genome': 'GRCm39', 'species': 'mus_musculus', 'organism': 'mouse',
                'reference': 'GRCm39', 'assembly': 'GRCm39', 'genome_build': 'GRCm39',
                'ref_genome': 'GRCm39'}[g]]}),
    (r'\bpaired[- ]end\b', {'paired_end': 'true', 'single_end': 'false', 'paired': 'true'}),
    (r'\bsingle[- ]end\b', {'single_end': 'true', 'paired_end': 'false', 'paired': 'false'}),
    (r'\b(reverse strand|dutp|reverse-strand)\b', {'strandedness': 'reverse'}),
    (r'\bforward strand|fr-secondstrand\b', {'strandedness': 'forward'}),
    (r'\bunstranded\b', {'strandedness': 'unstranded'}),
]
SPECIES_SIGNALS = SIGNALS  # back-compat name


def eval_queries():
    s = set()
    try:
        for l in open(EVAL):
            r = json.loads(l)
            s.add((r.get('user_query') or '').strip().lower())
    except Exception:
        pass
    return s


def licensed_fill(desc, schema_names):
    """Return {param: value} the description deterministically licenses, restricted to schema."""
    out = {}
    low = desc.lower()
    for pat, mapping in SPECIES_SIGNALS:
        if re.search(pat, low):
            for p, v in mapping.items():
                if p in schema_names:
                    out[p] = v
    return out


GROUNDED = f"{REPO}/docs/20260912_onprem_llm/data_pool_v2/grounded_param.jsonl"


def optional_sets(db):
    """workflow name -> (set(optional params), [all schema param names])."""
    m = {}
    for r in db.execute("select name,params_schema from workflows where params_schema is not null "
                        "and length(params_schema)>30"):
        try:
            ps = json.loads(r['params_schema'])
        except Exception:
            continue
        params = ps.get('parameters') or []
        m[r['name']] = ({p['name'] for p in params if p.get('optional') is True},
                        [p['name'] for p in params])
    return m


SEL_SYS = ("You are BioMate's parameter extractor. From the request, set ONLY the parameters the "
           "user explicitly specifies. Do NOT add optional or conditional parameters they did not "
           "mention. Reply ONLY a JSON object of the parameters to set.")


def build_selective(db, evalq, seen_q):
    """Real selective-restraint anchors from grounded_param (real query + real db_gold)."""
    optmap = optional_sets(db)
    out = []
    try:
        lines = open(GROUNDED)
    except Exception:
        return out
    for l in lines:
        try:
            r = json.loads(l)
        except Exception:
            continue
        if r.get('split') == 'eval':
            continue
        wf = r.get('workflow')
        q = (r.get('query') or '').strip()
        gold = r.get('db_gold') or {}
        if not wf or not q or not isinstance(gold, dict) or not gold:
            continue
        if wf not in optmap:
            continue
        opt, allnames = optmap[wf]
        if q.lower() in evalq:
            continue
        qh = hashlib.md5(q.encode()).hexdigest()
        if qh in seen_q:
            continue
        mnf = sorted(p for p in opt if p not in gold)
        if not mnf:
            continue
        seen_q.add(qh)
        user = (f"{q}\n\nAvailable parameters you MAY set (only if the request specifies them): "
                f"{allnames}")
        out.append({
            "messages": [
                {"role": "system", "content": SEL_SYS},
                {"role": "user", "content": user},
                {"role": "assistant", "content": json.dumps(gold)},
            ],
            "task": "param_extraction", "source": "real_grounded_param_restraint",
            "workflow": wf, "domain": r.get('domain', ''),
            "gold_params": gold, "must_not_fill": mnf, "schema_params": allnames,
            "split": "train",
        })
    return out


def main():
    db = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    db.row_factory = sqlite3.Row
    evalq = eval_queries()
    rows = []
    by_domain = collections.Counter()
    seen_q = set()
    for r in db.execute("select name,domain,description,params_schema from workflows "
                        "where params_schema is not null and length(params_schema)>50 "
                        "and description is not null and length(description)>60"):
        try:
            ps = json.loads(r['params_schema'])
        except Exception:
            continue
        params = ps.get('parameters') or []
        if not params:
            continue
        opt = [p['name'] for p in params if p.get('optional') is True]
        allnames = {p['name'] for p in params}
        if not opt:
            continue
        # tool-free-ish query: the workflow description, trimmed of a leading "domain/name " prefix
        desc = re.sub(r'^\s*[\w\-]+/[\w\-/]+\s+', '', r['description']).strip()
        q = re.sub(r'\s+', ' ', desc)[:500]
        if len(re.findall(r'[A-Za-z]{3,}', q)) < 8:
            continue
        if q.strip().lower() in evalq:
            continue
        qh = hashlib.md5(q.encode()).hexdigest()
        if qh in seen_q:
            continue
        seen_q.add(qh)
        gold = licensed_fill(desc, allnames)
        # must_not_fill = optional params the query does not state (all of them for a bare intent);
        # a filled param is removed from must_not_fill.
        mnf = sorted(p for p in opt if p not in gold)
        if not mnf:
            continue
        schema_params = [p['name'] for p in params]
        user = (f"{q}\n\nAvailable parameters you MAY set (only if the request specifies them): "
                f"{schema_params}")
        rows.append({
            "messages": [
                {"role": "system", "content": SYS},
                {"role": "user", "content": user},
                {"role": "assistant", "content": json.dumps(gold)},
            ],
            "task": "param_extraction",
            "source": "real_params_schema_restraint",
            "workflow": r['name'], "domain": r['domain'],
            "gold_params": gold, "must_not_fill": mnf, "schema_params": schema_params,
            "split": "train",
        })
        by_domain[r['domain']] += 1

    # selective-restraint anchors from grounded_param (real query+gold)
    sel = build_selective(db, evalq, seen_q)
    for s in sel:
        by_domain[s.get('domain') or 'unknown'] += 1
    rows += sel
    db.close()

    with open(OUT, "w") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")

    empty = sum(1 for r in rows if not r['gold_params'])
    print(json.dumps({
        "anchor_count": len(rows),
        "pure_restraint_empty_gold": empty,
        "selective_restraint_with_fill": len(rows) - empty,
        "total_must_not_fill_params": sum(len(r['must_not_fill']) for r in rows),
        "distinct_must_not_fill_params": len({p for r in rows for p in r['must_not_fill']}),
        "by_domain_top": dict(by_domain.most_common(12)),
    }, indent=2))


if __name__ == "__main__":
    main()
