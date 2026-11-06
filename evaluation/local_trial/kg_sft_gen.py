"""KG -> SFT reasoning tasks (layer 2). Group PrimeKG facts per entity, have a teacher (gemini-3.8-flash)
phrase GROUNDED, hallucination-free examples (facts come ONLY from the KG, teacher just phrases):
  - grounded scientific_qa (single/aggregate fact)
  - kg_reasoning (multi-hop chain across 2+ edges)
This fixes the committee's weak-reasoning + teacher-hallucination findings (KG = ground truth).
Usage: python kg_sft_gen.py --kg kg.csv --out kg_sft.jsonl --target 20000 [--smoke]
"""
import argparse, csv, json, os, random, re, time, urllib.request
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
csv.field_size_limit(10 ** 7)
random.seed(29)
GK = os.environ.get("GOOGLE_API_KEY", "")
# informative relations for reasoning (skip the mega-repetitive anatomy_present / drug_drug)
GOOD_REL = {"protein_protein", "drug_protein", "target", "enzyme", "carrier", "transporter",
            "disease_protein", "indication", "contraindication", "off-label use", "pathway_protein",
            "bioprocess_protein", "molfunc_protein", "disease_phenotype_positive", "phenotype_protein",
            "drug_effect", "exposure_disease", "disease_disease"}
PHRASE = {"protein_protein": "interacts with the protein", "drug_protein": "acts on the protein",
          "target": "targets the protein", "enzyme": "is metabolized by", "carrier": "is carried by",
          "transporter": "is transported by", "disease_protein": "is genetically associated with the disease",
          "indication": "is indicated for", "contraindication": "is contraindicated in",
          "off-label use": "is used off-label for", "pathway_protein": "participates in the pathway",
          "bioprocess_protein": "is involved in the process", "molfunc_protein": "has the molecular function",
          "disease_phenotype_positive": "presents with the phenotype", "phenotype_protein": "is linked to phenotype",
          "drug_effect": "causes the effect", "exposure_disease": "influences the disease",
          "disease_disease": "is related to the disease"}


def gem(prompt, mx=4000):
    u = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent?key={GK}"
    b = json.dumps({"contents": [{"parts": [{"text": prompt}]}], "generationConfig": {"maxOutputTokens": mx}}).encode()
    for a in range(5):
        try:
            c = json.load(urllib.request.urlopen(urllib.request.Request(u, b, {"Content-Type": "application/json"}), timeout=90))["candidates"][0]
            if c.get("finishReason") in (None, "STOP"):
                return "".join(p.get("text", "") for p in c.get("content", {}).get("parts", [])).strip()
            return ""
        except Exception:
            time.sleep(min(2 ** a, 20))
    return ""


SYS = "You are BioMate, an agentic bioinformatics assistant."


def build_batch(entities):  # entities: list of (name, [fact_str,...])
    blocks = "\n\n".join(f"[{i}] Entity: {e}\nKG facts:\n" + "\n".join(f"  - {f}" for f in fs)
                         for i, (e, fs) in enumerate(entities))
    return (f"For EACH entity below, using ONLY its listed KG facts (never invent), write 2 grounded "
            f"BioMate training examples: (a) task 'scientific_qa' — a natural question a researcher would "
            f"ask, answered strictly from the facts; (b) task 'kg_reasoning' — a multi-hop question that "
            f"chains >=2 facts, with a short reasoning answer. Reply ONLY a JSON list, one object per "
            f'entity: {{"i":<idx>,"examples":[{{"task":"scientific_qa","user":...,"assistant":...}},'
            f'{{"task":"kg_reasoning","user":...,"assistant":...}}]}}.\n\n{blocks}')


def job(entities):
    txt = gem(build_batch(entities))
    m = re.search(r"\[.*\]", txt, re.S)
    if not m: return []
    try: arr = json.loads(m.group(0))
    except Exception: return []
    out = []
    for obj in arr:
        if not isinstance(obj, dict): continue
        for ex in obj.get("examples", []):
            if isinstance(ex, dict) and ex.get("user") and ex.get("assistant") and ex.get("task"):
                out.append({"messages": [{"role": "system", "content": SYS},
                                         {"role": "user", "content": ex["user"]},
                                         {"role": "assistant", "content": ex["assistant"]}],
                            "task": ex["task"], "source": "kg_sft"})
    return out


def load_adjacency(path):
    adj = defaultdict(list)
    with open(path, newline="") as f:
        for r in csv.DictReader(f):
            rel = r.get("display_relation") or r.get("relation")
            if rel not in GOOD_REL: continue
            x, y, yt = r.get("x_name"), r.get("y_name"), r.get("y_type")
            if x and y:
                adj[x].append(f"{x} {PHRASE.get(rel, rel)} {y}" + (f" ({yt})" if yt else "") + ".")
    return adj


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kg", default=""); ap.add_argument("--out", required=True)
    ap.add_argument("--target", type=int, default=20000); ap.add_argument("--batch", type=int, default=6)
    ap.add_argument("--workers", type=int, default=48); ap.add_argument("--smoke", action="store_true")
    a = ap.parse_args()
    if a.smoke:
        demo = [("Imatinib", ["Imatinib targets the protein ABL1.", "Imatinib targets the protein KIT.",
                              "Imatinib is indicated for chronic myeloid leukemia.", "ABL1 is genetically associated with chronic myeloid leukemia."]),
                ("TP53", ["TP53 interacts with the protein MDM2.", "TP53 is genetically associated with Li-Fraumeni syndrome.",
                         "TP53 participates in the pathway apoptosis.", "TP53 is involved in the process DNA damage response."])]
        print(json.dumps(job(demo), indent=2)[:2500]); return
    adj = load_adjacency(a.kg)
    ents = [(e, fs) for e, fs in adj.items() if len(fs) >= 2]
    random.shuffle(ents)
    print(f"[kgsft] {len(ents):,} entities with >=2 facts; target {a.target} examples", flush=True)
    batches = [ents[i:i + a.batch] for i in range(0, len(ents), a.batch)]
    n = 0
    with open(a.out, "w") as fo, ThreadPoolExecutor(max_workers=a.workers) as ex:
        futs = [ex.submit(job, b) for b in batches]
        for k, f in enumerate(as_completed(futs)):
            for r in (f.result() or []):
                fo.write(json.dumps(r) + "\n"); n += 1
            if n >= a.target: break
            if (k + 1) % 200 == 0: print(f"[kgsft] {k+1} batches -> {n} examples", flush=True)
    print(f"KGSFT DONE: {n} examples -> {a.out}", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
