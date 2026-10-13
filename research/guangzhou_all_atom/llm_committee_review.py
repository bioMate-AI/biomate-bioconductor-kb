#!/usr/bin/env python3
"""Cross-model committee review of the v2 candidate sequences BEFORE any wet-lab.

Queries the strongest available model from each of OpenAI, Anthropic (Claude), and Google (Gemini)
via OpenRouter. Each reviews the SAME candidate table against the SAME rubric (docs/
20261013_SEQUENCE_REVIEW_KEY_POINTS.md) INDEPENDENTLY, then we consolidate consensus + dissents.
Purpose: a mechanism/first-principles sanity gate (the one round-1 lacked) — catch anything our
internal pharmacophore+liability+FTO gates miss, especially binding!=function and selectivity, which
our computational gates do NOT cover.

Honesty: this is a REVIEW layer, not validation. It does not replace docking/MM-GBSA/wet-lab; it is the
cheap cross-model check that must precede synthesis.
"""
import csv, json, os, sys, urllib.request, urllib.error

KEY = open(os.path.expanduser("~/.config/biomate/openrouter.key")).read().strip()
URL = "https://openrouter.ai/api/v1"

RUBRIC = """You are a peptide drug-discovery reviewer. Apply this rubric (靶理 / target-logic):
1. PHARMACOPHORE present? (αvβ6: RGD + the selectivity Leu 'RGDL' + a D-Pro/N-methyl conformational lock;
   PD-L1: amphipathic IgV-cleft chemotype — structure-gated, no linear motif). A candidate lacking the
   required pharmacophore is mechanism-dead regardless of any score.
2. BINDING != FUNCTION: flag where binding would not imply functional efficacy or receptor SELECTIVITY
   (bare RGD binds αvβ3/αvβ5/αvβ8 too).
3. DEVELOPABILITY liabilities (deamidation N-G/N-S, Asp-isomerization D-G/D-S, Met/Trp oxidation, free Cys,
   aggregation), and for a renally-cleared radioligand, net positive charge (kidney dose).
4. Don't over-credit a single change; activity cliffs (one residue can flip function).
These candidates ALREADY passed internal pharmacophore+liability+FTO gates — your job is an INDEPENDENT
sanity check: confirm or CHALLENGE, and surface anything the internal gates miss (especially function/
selectivity, which the computational gates do not cover)."""

TASK = """Review the candidates below. Respond ONLY as compact JSON:
{"pharmacophore_check": "<confirm or challenge, per target>",
 "function_selectivity_concerns": ["..."],
 "no_go_before_wetlab": [{"id": "...", "reason": "..."}],
 "top_picks": ["id", "..."],
 "overall": "<GO or HOLD + one sentence>"}
Be specific and terse. Do not invent data; reason from the sequences + rubric."""


def pick_models():
    req = urllib.request.Request(URL + "/models", headers={"Authorization": "Bearer " + KEY})
    ids = [m["id"] for m in json.load(urllib.request.urlopen(req, timeout=30))["data"]]
    def best(provider, prefer, avoid):
        cand = [i for i in ids if i.startswith(provider) and not i.endswith(":batch")
                and not any(a in i for a in avoid)]
        for p in prefer:
            hit = [i for i in cand if p in i]
            if hit: return sorted(hit)[-1]
        return sorted(cand)[-1] if cand else None
    return {
        "openai":  best("openai/",   ["gpt-6", "gpt-5", "gpt-4.1", "o3"], ["mini", "nano", "audio", "search", "image"]),
        "anthropic": best("anthropic/", ["opus", "sonnet"],       ["haiku", "fable"]),
        "google":  best("google/",   ["gemini-3", "gemini-2.5"], ["flash", "lite", "image", "tts"]),
    }


def ask(model, candidates_text):
    body = json.dumps({
        "model": model,
        "messages": [
            {"role": "system", "content": RUBRIC},
            {"role": "user", "content": TASK + "\n\nCANDIDATES:\n" + candidates_text},
        ],
        "temperature": 0.2,
    }).encode()
    req = urllib.request.Request(URL + "/chat/completions", data=body,
                                 headers={"Authorization": "Bearer " + KEY, "Content-Type": "application/json"})
    r = json.load(urllib.request.urlopen(req, timeout=180))
    return r["choices"][0]["message"]["content"]


def main():
    rows = list(csv.DictReader(open("../../docs/20261013_cyclic_peptide_candidates_v2_for_review.csv")))
    cols = ["id", "target", "role", "backbone_1letter", "helm", "net_charge", "gate_tier", "fto_genus_identity", "edit_or_status"]
    txt = "\n".join(" | ".join(f"{c}={r.get(c,'')}" for c in cols) for r in rows)
    models = pick_models()
    print("committee models:", models)
    out = {"models": models, "n_candidates": len(rows), "reviews": {}}
    for prov, model in models.items():
        if not model:
            out["reviews"][prov] = {"error": "no model available"}; print(prov, "NO MODEL"); continue
        try:
            raw = ask(model, txt)
            try: parsed = json.loads(raw[raw.index("{"):raw.rindex("}")+1])
            except Exception: parsed = {"raw": raw}
            out["reviews"][prov] = {"model": model, "verdict": parsed}
            print(f"\n===== {prov} ({model}) =====\n{json.dumps(parsed, indent=2)[:1800]}")
        except urllib.error.HTTPError as e:
            out["reviews"][prov] = {"model": model, "error": f"HTTP {e.code}: {e.read()[:300].decode(errors='ignore')}"}
            print(prov, "HTTP ERROR", e.code)
        except Exception as e:
            out["reviews"][prov] = {"model": model, "error": str(e)[:300]}
            print(prov, "ERROR", str(e)[:200])
    json.dump(out, open("results/llm_committee_review.json", "w"), indent=2)
    print("\nwrote results/llm_committee_review.json")


if __name__ == "__main__":
    main()
