#!/usr/bin/env python3
"""External committee round 2 (2026-10-30) via OpenRouter under a hard budget.
Guards: balance read before every call; a call is skipped if (balance - worst-case estimate) < RESERVE or running counted total + worst > CAP.
Anthropic costs are counted x1.5 (observed overcharge). One attempt per reviewer, no rewording. Every call is logged to ext_cost_log.csv.
The key is read from ~/.config/biomate/openrouter.key and never printed."""
import json, os, sys, time, csv, urllib.request, urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
PACKET = open(os.path.join(REPO, "docs", "20261030_COMMITTEE2_PACKET.md"), encoding="utf-8").read()
KEY = open(os.path.expanduser("~/.config/biomate/openrouter.key")).read().strip()
CAP, RESERVE, MAXTOK = 2.00, 0.75, 9000
LOG = os.path.join(HERE, "ext_cost_log.csv")

COMMON = ("You are an independent external reviewer on an AI review committee (three reviewers from three different labs; each covers ALL THREE roles as separate sections so views can be cross-checked). "
          "The packet is the team's own material: a manuscript draft, a claims table, verbatim code excerpts and data-audit headlines for a retrospective study of closed-loop learning for cyclic-peptide permeability and binding ranking. "
          "No wet-lab data exists; the central comparison of the paper (in-house hybrid model vs larger pretrained peptide models in the loop) has NOT been run. Be demanding, specific and honest; do not be agreeable. "
          "Mark anything you are unsure of as [UNVERIFIED]; never invent citations, authors, venues or numbers; cite only works you are confident exist. "
          "Use EXACTLY this structure, at most ~3,000 words in total, and finish every section:\n"
          "## ROLE 1. MANUSCRIPT REFEREE\nWhat the paper can and cannot claim given the evidence; overclaims; internal inconsistencies between sections; missing analyses a referee would demand; interval-type and multiplicity issues; whether the framing (evaluation instrument + audited nulls, planned Aim A) is honest and publishable, and where; ranked list of required revisions.\n"
          "## ROLE 2. CODE / STATISTICS REVIEWER\nRead the code excerpts line by line. Name CONCRETE defects (file, function, line-level reasoning): resampling unit errors, ties, leakage, statistic mismatches, wrong denominators, seeds, bias in the bootstrap, permutation nulls, fusion/reliability estimators, fold construction. State for each whether it changes a reported number or only its interpretation. Say explicitly if you find none in an excerpt.\n"
          "## ROLE 3. DATA / EVALUATION REVIEWER\nLeakage routes (corpora of pretrained comparators, fold filters, series and laboratory leakage, stereoisomer siblings), validity gates and the control-adjusted rule, family-disjoint folds, regime definitions (including the leave-laboratories-out set sizes), power, multiple comparisons, selection of arms, whether public CycPeptMPDB-style data can support the claims at all.\n"
          "## THE SINGLE MOST DAMAGING FLAW\nOne flaw, why it is the most damaging, and the cheapest test that would confirm or refute it within a day.\n\n")

REVIEWERS = [  # id, model, $/M in, $/M out, counting factor
    ("GPT", "openai/gpt-5.5", 5.00, 30.00, 1.0),
    ("GEMINI", "google/gemini-3.1-pro-preview", 2.00, 12.00, 1.0),
    ("SONNET", "anthropic/claude-sonnet-4.6", 3.00, 15.00, 1.5),
]

def balance():
    r = urllib.request.Request("https://openrouter.ai/api/v1/credits", headers={"Authorization": "Bearer " + KEY})
    d = json.load(urllib.request.urlopen(r, timeout=30))["data"]
    return d["total_credits"] - d["total_usage"]

def log(row):
    new = not os.path.exists(LOG)
    with open(LOG, "a", newline="") as f:
        w = csv.writer(f)
        if new: w.writerow(["ts", "reviewer", "model", "attempt", "prompt_tokens", "completion_tokens", "reasoning_tokens", "reported_cost_usd", "counted_cost_usd", "finish", "balance_before", "balance_after", "note"])
        w.writerow(row)

def call(model, prompt):
    body = {"model": model, "messages": [{"role": "user", "content": prompt}], "max_tokens": MAXTOK,
            "reasoning": {"effort": "low"}, "usage": {"include": True}, "temperature": 0.3}
    req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Authorization": "Bearer " + KEY, "Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=900))

def main(only=None):
    total = 0.0
    for rid, model, pin, pout, factor in REVIEWERS:
        if only and rid not in only: continue
        outp = os.path.join(HERE, f"ext_review_{rid}.md")
        if os.path.exists(outp):
            print("skip existing", rid); continue
        prompt = COMMON + PACKET
        in_tok = len(prompt) / 3.4
        worst = (in_tok * pin + MAXTOK * pout) / 1e6 * factor
        b0 = balance()
        print(f"{rid}: est_worst=${worst:.3f} (in~{in_tok:.0f} tok) balance=${b0:.3f} running=${total:.3f}", flush=True)
        if total + worst > CAP or b0 - worst < RESERVE:
            print("  SKIP: budget guard", flush=True)
            log([time.strftime("%FT%T"), rid, model, 0, "", "", "", "", "", "skipped", round(b0, 3), "", f"guard worst={worst:.3f}"]); continue
        try:
            d = call(model, prompt)
        except urllib.error.HTTPError as e:
            msg = e.read().decode()[:300]; print("  HTTP", e.code, msg, flush=True)
            log([time.strftime("%FT%T"), rid, model, 1, "", "", "", "", "", f"http{e.code}", round(b0, 3), "", msg]); continue
        except Exception as e:
            print("  ERR", repr(e)[:200], flush=True)
            log([time.strftime("%FT%T"), rid, model, 1, "", "", "", "", "", "error", round(b0, 3), "", repr(e)[:200]]); continue
        u = d.get("usage", {}); ch = d["choices"][0]
        cost = float(u.get("cost") or 0.0); counted = cost * factor; total += counted
        rt = (u.get("completion_tokens_details") or {}).get("reasoning_tokens", "")
        content = ch["message"].get("content") or ""; fin = ch.get("finish_reason"); b1 = balance()
        log([time.strftime("%FT%T"), rid, model, 1, u.get("prompt_tokens"), u.get("completion_tokens"), rt, round(cost, 4), round(counted, 4), fin, round(b0, 3), round(b1, 3), "" if content else "EMPTY content"])
        if not content.strip():
            open(os.path.join(HERE, f"ext_review_{rid}.REFUSED_or_empty.json"), "w").write(json.dumps({k: d.get(k) for k in ("id", "model", "choices", "usage")}, indent=1)[:6000])
            print(f"  EMPTY content finish={fin}; recorded, no retry", flush=True); continue
        open(outp, "w").write(f"<!-- model={model} finish={fin} tokens_in={u.get('prompt_tokens')} out={u.get('completion_tokens')} reasoning={rt} cost={cost} -->\n# External reviewer {rid} ({model})\n\n{content}\n")
        print(f"  done finish={fin} out={u.get('completion_tokens')} cost=${cost:.4f} counted=${counted:.4f} total=${total:.3f} bal=${b1:.3f}", flush=True)
    print("TOTAL_COUNTED", round(total, 4), "BALANCE_END", round(balance(), 3))

if __name__ == "__main__":
    main(sys.argv[1:] or None)
