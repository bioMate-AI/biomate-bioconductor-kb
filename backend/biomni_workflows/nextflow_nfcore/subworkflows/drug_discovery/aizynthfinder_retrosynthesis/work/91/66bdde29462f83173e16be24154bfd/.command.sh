#!/bin/bash -ue
if [ "false" = "true" ]; then
        python3 << 'EOF'
import json
import random
import hashlib
from datetime import datetime

compound_id = "CPND0001"
smiles      = "C1=CC(=CC=C1NC2=NC=NC3=CC(=C(C=C23)OCCO)OCC)C#N erlotinib"
max_routes  = int("5")
max_depth   = int("6")

# ---------------------------------------------------------------------------
# Seed RNG from SMILES for reproducible mock outputs across CI runs.
# ---------------------------------------------------------------------------
seed = int(hashlib.md5(smiles.encode()).hexdigest(), 16) % (2**31)
rng  = random.Random(seed)

MOCK_REAGENTS = [
    ("Pd(OAc)2 / PPh3",      "Suzuki coupling"),
    ("NaBH4 / MeOH",          "Carbonyl reduction"),
    ("SOCl2 / pyridine",       "Chlorination"),
    ("LiAlH4 / THF",           "Amide reduction"),
    ("Ac2O / Et3N",            "Acetylation"),
    ("EDCI / HOBt / DMF",      "Amide coupling"),
    ("K2CO3 / DMF",            "N-alkylation"),
    ("m-CPBA / CH2Cl2",        "Epoxidation"),
    ("NBS / CCl4 / hv",        "Radical bromination"),
    ("H2 / Pd-C / EtOH",      "Hydrogenation"),
]

MOCK_PRECURSORS = [
    "c1ccccc1",
    "CC(=O)O",
    "NC(=O)O",
    "c1ccc(Br)cc1",
    "CCOC(=O)CCl",
    "OC(=O)c1ccccc1",
    "c1ccc(N)cc1",
    "CC(C)=O",
    "OCC",
    "c1ccc(Cl)cc1",
]

def make_steps(rng, n_steps):
    steps = []
    for i in range(n_steps):
        reagent, rxn_class = rng.choice(MOCK_REAGENTS)
        precursor = rng.choice(MOCK_PRECURSORS)
        steps.append({
            "step":             i + 1,
            "reaction_class":   rxn_class,
            "reagent":          reagent,
            "precursor_smiles": precursor,
            "yield_pct":        round(rng.uniform(60.0, 95.0), 1),
        })
    return steps

# ---------------------------------------------------------------------------
# Basic validity check: balanced parentheses/brackets, non-empty, no spaces.
# Full SMILES validation requires RDKit (not available in mock mode).
# ---------------------------------------------------------------------------
smiles_valid = (
    len(smiles.strip()) > 0
    and " " not in smiles.strip()
    and smiles.count("(") == smiles.count(")")
    and smiles.count("[") == smiles.count("]")
)

if not smiles_valid:
    routes = []
    feasibility_rank = []
else:
    n_routes = min(3, max_routes)
    routes = []
    for r_idx in range(n_routes):
        n_steps  = rng.randint(2, min(4, max_depth))
        score    = round(rng.uniform(0.50, 0.92), 3)
        sa_score = round(rng.uniform(1.5, 4.5), 2)  # SA score: 1=easy, 10=very hard
        steps    = make_steps(rng, n_steps)
        routes.append({
            "route_id":   r_idx + 1,
            "score":      score,
            "step_count": n_steps,
            "sa_score":   sa_score,
            "steps":      steps,
        })
    # Sort descending by score → position = feasibility_rank
    routes.sort(key=lambda x: x["score"], reverse=True)
    feasibility_rank = [r["route_id"] for r in routes]

result = {
    "compound_id":      compound_id,
    "smiles":           smiles,
    "smiles_valid":     smiles_valid,
    "n_routes":         len(routes),
    "routes":           routes,
    "feasibility_rank": feasibility_rank,
    "max_routes":       max_routes,
    "max_depth":        max_depth,
    "tool":             "aizynthfinder",
    "version":          "3.7.0-mock",
    "timestamp":        datetime.utcnow().isoformat() + "Z",
    "mock_mode":        True,
}

with open(f"{compound_id}_routes.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"AiZynthFinder predict (mock) [{compound_id}]: {len(routes)} routes  smiles={smiles[:50]}")
for r in routes:
    print(f"  Route {r['route_id']}: steps={r['step_count']}  score={r['score']}  sa_score={r['sa_score']}")
if not smiles_valid:
    print(f"  WARNING: SMILES failed validity check — 0 routes generated")
EOF

    else
        # ---------------------------------------------------------------------------
        # Live: run aizynthcli and normalize its output into BioMate JSON format.
        # aizynthcli writes a JSON file containing a list of solved route trees.
        # ---------------------------------------------------------------------------
        aizynthcli             --smiles "C1=CC(=CC=C1NC2=NC=NC3=CC(=C(C=C23)OCCO)OCC)C#N erlotinib"             --output CPND0001_routes_raw.json             --config "/opt/aizynthfinder/config.yml"             --max-transforms 6             --iteration-limit 100

        python3 << 'PYEOF'
import json
import sys
from datetime import datetime

compound_id = "CPND0001"
smiles      = "C1=CC(=CC=C1NC2=NC=NC3=CC(=C(C=C23)OCCO)OCC)C#N erlotinib"
max_routes  = int("5")
raw_file    = f"{compound_id}_routes_raw.json"

try:
    raw = json.load(open(raw_file))
except (FileNotFoundError, json.JSONDecodeError) as exc:
    print(f"ERROR: could not read {raw_file}: {exc}", file=sys.stderr)
    result = {
        "compound_id":      compound_id,
        "smiles":           smiles,
        "smiles_valid":     False,
        "n_routes":         0,
        "routes":           [],
        "feasibility_rank": [],
        "error":            str(exc),
        "mock_mode":        False,
    }
    with open(f"{compound_id}_routes.json", "w") as f:
        json.dump(result, f, indent=2)
    sys.exit(0)

# aizynthcli output is a list of route tree dicts; handle both list and dict root
routes_raw = raw if isinstance(raw, list) else raw.get("routes", raw.get("trees", []))

def count_steps(node):
    if node.get("type") == "reaction":
        return 1 + sum(count_steps(c) for c in node.get("children", []))
    return sum(count_steps(c) for c in node.get("children", []))

def collect_steps(node, depth=0):
    steps = []
    if node.get("type") == "reaction":
        steps.append({
            "step":             depth + 1,
            "reaction_class":   node.get("metadata", {}).get("classification", "unknown"),
            "reagent":          node.get("metadata", {}).get("name", "unknown"),
            "precursor_smiles": ".".join(
                c.get("smiles", "") for c in node.get("children", [])
                if c.get("type") == "mol"
            ),
            "yield_pct": None,
        })
    for child in node.get("children", []):
        next_depth = depth + 1 if node.get("type") == "reaction" else depth
        steps.extend(collect_steps(child, next_depth))
    return steps

routes = []
for r_idx, route_tree in enumerate(routes_raw[:max_routes]):
    meta     = route_tree.get("metadata", {})
    n_steps  = count_steps(route_tree)
    steps    = collect_steps(route_tree)
    score    = float(meta.get("score", meta.get("reaction_class_score", 0.5)))
    sa_score = float(meta.get("sa_score", 3.0))
    routes.append({
        "route_id":   r_idx + 1,
        "score":      round(score, 3),
        "step_count": n_steps,
        "sa_score":   round(sa_score, 2),
        "steps":      steps,
    })

routes.sort(key=lambda x: x["score"], reverse=True)

result = {
    "compound_id":      compound_id,
    "smiles":           smiles,
    "smiles_valid":     True,
    "n_routes":         len(routes),
    "routes":           routes,
    "feasibility_rank": [r["route_id"] for r in routes],
    "max_routes":       max_routes,
    "max_depth":        int("6"),
    "tool":             "aizynthfinder",
    "version":          "3.7.0",
    "timestamp":        datetime.utcnow().isoformat() + "Z",
    "mock_mode":        False,
}

with open(f"{compound_id}_routes.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"AiZynthFinder predict (live) [{compound_id}]: {len(routes)} routes found")
for r in routes:
    print(f"  Route {r['route_id']}: steps={r['step_count']}  score={r['score']}  sa_score={r['sa_score']}")
PYEOF
    fi

    cat <<-END_VERSIONS > versions.yml
    "AIZYNTHFINDER_RETROSYNTHESIS:AIZYNTHFINDER_PREDICT":
        aizynthfinder: $(aizynthcli --version 2>&1 | head -1 || echo "3.7.0-mock")
        python: $(python3 --version 2>&1 | cut -d' ' -f2)
        mock_mode: "false"
    END_VERSIONS
