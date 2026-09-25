"""Frontier-LLM ceiling on the SAME gold routing eval (realbio+dbtest candidate-grounded, DB gold).
Runs Claude / GPT / Gemini (latest) via API, parallel, accept-set scoring — apples-to-apples with the
on-prem 4B's eval_gold.py. Usage: python frontier_gold.py --evalfile gold_routing_eval.jsonl --out o.json
Keys: OPENAI_API_KEY, GOOGLE_API_KEY, ANTHROPIC_API_KEY (env).
"""
import argparse, json, os, re, urllib.request, time
from concurrent.futures import ThreadPoolExecutor

MODELS = {
    "claude-opus-4-8": ("anthropic", "claude-opus-4-8"),
    "gpt-6-luna":      ("openai",    "gpt-6-luna"),
    "gemini-3.8-flash":("google",    "gemini-3.8-flash"),
}


def norm(s): return re.sub(r"[^a-z0-9]+", " ", str(s).lower()).strip()
def answer_of(o):
    if "</think>" in o: o = o.rsplit("</think>", 1)[1]
    return o.strip()


def call(provider, model, prompt, mx=512):
    for attempt in range(4):
        try:
            if provider == "anthropic":
                url = "https://api.anthropic.com/v1/messages"
                h = {"x-api-key": os.environ["ANTHROPIC_API_KEY"], "anthropic-version": "2023-06-01", "content-type": "application/json"}
                b = {"model": model, "max_tokens": mx, "messages": [{"role": "user", "content": prompt}]}
                d = json.load(urllib.request.urlopen(urllib.request.Request(url, json.dumps(b).encode(), h), timeout=90))
                return "".join(p.get("text", "") for p in d.get("content", []))
            if provider == "openai":
                url = "https://api.openai.com/v1/chat/completions"
                h = {"Authorization": f"Bearer {os.environ['OPENAI_API_KEY']}", "Content-Type": "application/json"}
                b = {"model": model, "messages": [{"role": "user", "content": prompt}], "max_completion_tokens": mx, "reasoning_effort": "low"}
                d = json.load(urllib.request.urlopen(urllib.request.Request(url, json.dumps(b).encode(), h), timeout=90))
                return d["choices"][0]["message"]["content"]
            if provider == "google":
                url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={os.environ['GOOGLE_API_KEY']}"
                b = {"contents": [{"parts": [{"text": prompt}]}], "generationConfig": {"maxOutputTokens": mx}}
                d = json.load(urllib.request.urlopen(urllib.request.Request(url, json.dumps(b).encode(), {"Content-Type": "application/json"}), timeout=90))
                c = d["candidates"][0]
                return "".join(p.get("text", "") for p in c.get("content", {}).get("parts", []))
        except Exception as e:
            time.sleep(min(2 ** attempt, 15))
    return ""


def prompt_for(r):
    cands = "\n".join(f"- {c}" for c in r["candidates"])
    return ("You are BioMate. Choose the single best workflow for this request from the candidates. "
            f"Reply ONLY the exact workflow name.\n\nRequest: {r['query']}\n\nCandidates:\n{cands}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--evalfile", required=True); ap.add_argument("--out", required=True)
    ap.add_argument("--limit", type=int, default=0)
    a = ap.parse_args()
    rows = [json.loads(l) for l in open(a.evalfile)]
    if a.limit: rows = rows[:a.limit]
    results = {}
    for label, (prov, model) in MODELS.items():
        if prov == "anthropic" and not os.environ.get("ANTHROPIC_API_KEY"):
            print(f"skip {label}: no ANTHROPIC_API_KEY", flush=True); continue
        def one(r):
            out = call(prov, model, prompt_for(r))
            ans = norm(answer_of(out))
            hit = any(norm(x) in ans for x in r["accept"])
            exact = norm(r["gold"]) in ans
            return hit, exact, (out == "")
        hit = exact = empty = 0
        with ThreadPoolExecutor(max_workers=12) as ex:
            for i, (h, e, em) in enumerate(ex.map(one, rows)):
                hit += h; exact += e; empty += em
                if (i + 1) % 100 == 0: print(f"[{label}] {i+1}/{len(rows)}", flush=True)
        results[label] = {"model": model, "n": len(rows),
                          "accept_set_accuracy": round(hit / len(rows), 3),
                          "exact_gold_accuracy": round(exact / len(rows), 3),
                          "empty_responses": empty}
        print(f"=== {label}: accept={results[label]['accept_set_accuracy']} exact={results[label]['exact_gold_accuracy']} (empty={empty}) ===", flush=True)
    json.dump(results, open(a.out, "w"), indent=2)
    print("FRONTIER GOLD:", json.dumps(results))


if __name__ == "__main__":
    raise SystemExit(main())
