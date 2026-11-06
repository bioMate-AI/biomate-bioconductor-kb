#!/usr/bin/env python3
"""Owner-requested single attempt with anthropic/claude-opus-5.5 on the round-2 packet. Same three-role brief as ext_run.py.
reasoning={'max_tokens':2000} so reasoning cannot consume the output; max_tokens=12000. No retry, no rewording, no substitution.
If content is empty (refusal/filter/length): record full metadata (finish_reason, native_finish_reason, usage) and stop."""
import json, os, sys, time, csv, urllib.request, urllib.error
HERE = os.path.dirname(os.path.abspath(__file__))
sys.argv = [sys.argv[0]]
import importlib.util
spec = importlib.util.spec_from_file_location("extrun", os.path.join(HERE, "ext_run.py")); X = importlib.util.module_from_spec(spec); spec.loader.exec_module(X)
MODEL, PIN, POUT, FACTOR, MAXTOK, CAP_THIS, RESERVE = "anthropic/claude-opus-5.5", 4.00, 20.00, 1.5, 12000, 0.60, 0.75
prompt = X.COMMON + X.PACKET
in_tok = len(prompt) / 3.4
worst = (in_tok * PIN + MAXTOK * POUT) / 1e6 * FACTOR
b0 = X.balance()
print(f"est_in~{in_tok:.0f} tok worst=${worst:.3f} (x1.5 included) balance=${b0:.3f}", flush=True)
if worst > CAP_THIS or b0 - worst < RESERVE:
    print("SKIP: guard"); sys.exit(1)
body = {"model": MODEL, "messages": [{"role": "user", "content": prompt}], "max_tokens": MAXTOK, "reasoning": {"max_tokens": 2000}, "usage": {"include": True}, "temperature": 0.3}
req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", data=json.dumps(body).encode(), headers={"Authorization": "Bearer " + X.KEY, "Content-Type": "application/json"})
try:
    d = json.load(urllib.request.urlopen(req, timeout=900))
except urllib.error.HTTPError as e:
    msg = e.read().decode()[:500]; print("HTTP", e.code, msg); X.log([time.strftime("%FT%T"), "OPUS", MODEL, 1, "", "", "", "", "", f"http{e.code}", round(b0, 3), "", msg]); sys.exit(2)
u = d.get("usage", {}); ch = d["choices"][0]; cost = float(u.get("cost") or 0.0); counted = cost * FACTOR
rt = (u.get("completion_tokens_details") or {}).get("reasoning_tokens", "")
content = ch["message"].get("content") or ""; fin = ch.get("finish_reason"); nfin = ch.get("native_finish_reason"); b1 = X.balance()
meta = dict(id=d.get("id"), model=d.get("model"), provider=d.get("provider"), finish_reason=fin, native_finish_reason=nfin, usage=u, message_keys=list(ch["message"].keys()), refusal=ch["message"].get("refusal"), content_len=len(content))
X.log([time.strftime("%FT%T"), "OPUS", MODEL, 1, u.get("prompt_tokens"), u.get("completion_tokens"), rt, round(cost, 4), round(counted, 4), f"{fin}/{nfin}", round(b0, 3), round(b1, 3), "" if content.strip() else "EMPTY content"])
json.dump(meta, open(os.path.join(HERE, "ext_review_OPUS.meta.json"), "w"), indent=1, default=str)
if content.strip():
    open(os.path.join(HERE, "ext_review_OPUS.md"), "w").write(f"<!-- model={MODEL} finish={fin} native_finish={nfin} tokens_in={u.get('prompt_tokens')} out={u.get('completion_tokens')} reasoning={rt} cost={cost} -->\n# External reviewer OPUS ({MODEL})\n\n{content}\n")
print(json.dumps(meta, indent=1, default=str)); print("counted", round(counted, 4), "balance_after", round(b1, 3))
