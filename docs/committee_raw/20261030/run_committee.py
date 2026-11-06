#!/usr/bin/env python3
"""Run the 2026-10-30 review committee (novelty + evaluation) via OpenRouter under a hard budget.
Guards: balance read before every call; skip a call if (balance - worst-case estimate) < RESERVE; running total (Anthropic x1.5) must stay <= CAP.
Logs every call to cost_log.csv. Key is read from ~/.config/biomate/openrouter.key and never printed."""
import json, os, sys, time, csv, urllib.request, urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
PACKET = open(os.path.join(REPO, "docs", "20261030_COMMITTEE_PACKET.md"), encoding="utf-8").read()
KEY = open(os.path.expanduser("~/.config/biomate/openrouter.key")).read().strip()
CAP, RESERVE, MAXTOK = 6.00, 3.00, 14000
LOG = os.path.join(HERE, "cost_log.csv")

COMMON = ("You are an independent reviewer on an AI review committee (three reviewers from three different labs; each covers ALL THREE roles so views can be cross-checked). "
          "Read the packet carefully. Be demanding, specific and honest; do not be agreeable. Mark anything you are unsure of as [UNVERIFIED]; never invent citations, "
          "authors, venues or numbers; cite only works you are confident exist. Use EXACTLY this structure, max ~3,000 words total, and finish every section:\n"
          "## PART A. NOVELTY\nFor each candidate claim — (a) in-house hybrid loop-native cyclic-peptide LM with modules M1-M5 (evidence-weighted knowledge-prior fusion, anchor-based lab offset, stereo-aware analog retrieval, edit-space head, dual-memory loop); "
          "(b) family-disjoint matched-decoy cyclic-peptide benchmark with typicality/no-target validity gates; (c) stereo-resolved within-scaffold ranking protocol; (d) in-house hybrid vs larger pretrained peptide LMs compared inside a feedback loop — give: closest real prior art, what is genuinely new, what must NOT be claimed, how to make it more novel/innovative.\n"
          "## PART B. EVALUATION\nLeakage routes (pretrained comparators' corpora, fold filters, series/label leakage), validity gates and the control-adjusted rule, family-disjoint folds, leave-labs-out, H4b few-label design, statistics (source-cluster bootstrap, multiple comparisons, selecting the best ladder rung on dev seeds, the 90 % non-inferiority margin, power), retrospective-only limits, missing controls, what a skeptical reviewer would reject. Ranked issues with concrete fixes.\n"
          "## PART C. RED TEAM\nWhat will go wrong; simpler explanations of our results (analog lookup, lab effects, typicality); what we are overclaiming; results that will not replicate; the cheapest decisive experiment that could falsify our central claim.\n"
          "## PART D. THREE HIGHEST-VALUE CHANGES FOR THE NEXT WEEK\n\n")

REVIEWERS = [
 ("GEMINI", "google/gemini-3.1-pro-preview", 2.00, 12.00, 1.0, ""),
 ("GPT", "openai/gpt-5.5", 5.00, 30.00, 1.0, ""),
 ("OPUS", "anthropic/claude-opus-5.5", 4.00, 20.00, 1.5, ""),
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
    for rid, model, pin, pout, factor, mandate in REVIEWERS:
        if only and rid not in only: continue
        outp = os.path.join(HERE, f"review_{rid}.md")
        if os.path.exists(outp) and "finish=stop" in open(outp).read()[:400]:
            print("skip existing", rid); continue
        prompt = COMMON + mandate + "\n\n" + PACKET
        in_tok = len(prompt) / 3.6
        worst = (in_tok * pin + MAXTOK * pout) / 1e6 * factor
        b0 = balance()
        print(f"{rid}: est_worst=${worst:.3f} balance=${b0:.3f} running=${total:.3f}", flush=True)
        if total + worst > CAP or b0 - worst < RESERVE:
            print("  SKIP: budget guard", flush=True); log([time.strftime("%FT%T"), rid, model, 0, "", "", "", "", "", "skipped", round(b0, 3), "", f"guard worst={worst:.3f}"]); continue
        try:
            d = call(model, prompt)
        except urllib.error.HTTPError as e:
            msg = e.read().decode()[:300]; print("  HTTP", e.code, msg, flush=True)
            log([time.strftime("%FT%T"), rid, model, 1, "", "", "", "", "", f"http{e.code}", round(b0, 3), "", msg]); continue
        except Exception as e:
            print("  ERR", repr(e)[:200], flush=True)
            log([time.strftime("%FT%T"), rid, model, 1, "", "", "", "", "", "error", round(b0, 3), "", repr(e)[:200]]); continue
        u = d.get("usage", {}); ch = d["choices"][0]
        cost = float(u.get("cost") or 0.0); counted = cost * factor
        total += counted
        rt = (u.get("completion_tokens_details") or {}).get("reasoning_tokens", "")
        content = ch["message"].get("content") or ""
        fin = ch.get("finish_reason")
        b1 = balance()
        log([time.strftime("%FT%T"), rid, model, 1, u.get("prompt_tokens"), u.get("completion_tokens"), rt, round(cost, 4), round(counted, 4), fin, round(b0, 3), round(b1, 3), ""])
        open(outp, "w").write(f"<!-- model={model} finish={fin} tokens_in={u.get('prompt_tokens')} out={u.get('completion_tokens')} reasoning={rt} cost={cost} -->\n# Reviewer {rid} ({model})\n\n{content}\n")
        print(f"  done finish={fin} out={u.get('completion_tokens')} cost=${cost:.4f} counted=${counted:.4f} total=${total:.3f} bal=${b1:.3f}", flush=True)
    print("TOTAL_COUNTED", round(total, 4), "BALANCE_END", round(balance(), 3))

if __name__ == "__main__":
    main(sys.argv[1:] or None)
