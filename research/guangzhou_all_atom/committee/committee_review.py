#!/usr/bin/env python3
"""committee_review.py -- multi-LLM review board (OpenRouter), 8 reviewers from distinct labs, one adversarial mandate each.

Packet = COMMITTEE_BRIEF + findings docs + the loop/LLM code. DELIBERATELY EXCLUDES candidate sequences, CRO panels and keys
(this goes to external services). The chair (the calling agent) synthesises afterwards and must VERIFY reviewer claims --
reviewers can hallucinate numbers and citations; their output is evidence to check, not truth.

Usage: python3 committee_review.py [--dry]      key is read from ~/.config/biomate/openrouter.key and is never printed.
"""
import json, os, sys, time, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))          # biomate-review
GA = os.path.join(REPO, "research", "guangzhou_all_atom")
OUT = os.path.join(GA, "docs", "committee_raw", "20261025")
KEY = open(os.path.expanduser("~/.config/biomate/openrouter.key")).read().strip()

DOCS = [os.path.join(HERE, "COMMITTEE_BRIEF_20261025.md"),
        os.path.join(REPO, "docs", "20261025_SESSION_REVEAL_WORKS_RESOURCES_PERF_ERRORS.md"),
        os.path.join(REPO, "docs", "20261025_CADA_MN_METAL_MODEL_VALIDATION.md"),
        os.path.join(REPO, "docs", "20261025_PEPTIDE_AVAILABILITY_MODEL.md")]
CODE = [os.path.join(GA, "cyclic_llm", f) for f in
        ("loop.py", "reward.py", "score.py", "neural_generator.py", "peptide_availability.py", "methodology_close.py")]
CAP = 30000   # chars per code file

RUBRIC = (
    "Use EXACTLY this markdown structure:\n"
    "## 1. VERDICT ON OUR FINDINGS\n(what is right / wrong / overclaimed / missing; cite brief section numbers; each item: claim -> problem -> evidence needed)\n"
    "## 2. YOUR PROPOSAL FOR YOUR MANDATE AREA\n(concrete and implementable in THIS codebase; name the files/functions you would change or add)\n"
    "## 3. THE ONE INNOVATION YOU WOULD BET ON\n(novel AND defensible; name the prior art you know, marking anything you are unsure of [UNVERIFIED]; state the result that would FALSIFY it)\n"
    "## 4. 30-DAY PLAN\n(numbered; every step has a measurable go/no-go gate; assume NO wet lab; say what is cheap vs expensive)\n"
    "## 5. STOP DOING\n(efforts that waste time or risk misleading claims)\n"
    "## 6. BIGGEST RISK WE ARE MISSING\n"
    "Be specific, quantitative where you can, and honest. Do not invent citations or numbers. Keep it under ~2,500 words.")

COMMON = ("You are a member of an independent AI review committee advising a small team building a knowledge + rules + computation LLM "
          "system for cyclic-peptide design (targets: alpha-v-beta-6 integrin, PD-L1, GRPR). The team wants a BETTER LLM, a BETTER "
          "optimisation loop and a BETTER output, with genuine innovation. Your specific mandate: ")

REVIEWERS = [
 {"id": "A_claims_audit", "model": "openai/gpt-6.1-sol-pro", "fallback": "openai/gpt-6.1-sol",
  "mandate": "CLAIMS AUDITOR. Check every quantitative claim and every 'validated / fixed / confirmed' statement in the brief and docs against the evidence "
             "shown. Find places where the writing is more confident than the data, internal contradictions, and conclusions drawn from too little. "
             "Also check whether the corrected FEP story (measured -0.95 vs computed -0.18; metal never at the site) is itself stated too strongly."},
 {"id": "B_methodology", "model": "google/gemini-4-argon", "fallback": "google/gemini-3.8-flash",
  "mandate": "METHODOLOGY AND GENERALISATION. Diagnose the cross-context generalisation wall: is it data scarcity, label circularity, distribution shift, "
             "or evaluation design? Judge the leave-one-domain-out / cluster-disjoint protocols used here, what controls are missing, and design the "
             "evaluation that would convince a hostile statistician. Propose how to turn ~10 measured alpha-v-beta-6 SAR points into a valid test."},
 {"id": "C_physics_code", "model": "anthropic/claude-opus-5.5", "fallback": "anthropic/claude-sonnet-5.5",
  "mandate": "PHYSICS AND CODE. Judge the FEP + CaDA cationic-dummy Mn setup (bonded vs virtual-site, dt 0.5 fs, LJ on the centre only, a 3x-Mn site), "
             "the restraint/relaxation design, the unrestrained validation stage, MM-GBSA inadmissibility, and sampling (independent lambda windows, no HREX, "
             "0.5 ns/window, analytic BAR error). Review the loop/reward/score code for real bugs. State what a metal-aware relative-FEP validation must show "
             "before any ddG is trusted, and whether a different physics route (e.g. QM/MM or ML potentials for the site) is warranted."},
 {"id": "D_llm_architecture", "model": "moonshotai/kimi-k3.1-pro", "fallback": "moonshotai/kimi-k3",
  "mandate": "LLM ARCHITECTURE. Decide what the LLM in this system should BE and how it should integrate knowledge, rules and computation: edit-policy "
             "proposer (SynCraft-style), constrained generator, verifier-conditioned reasoning agent, a small domain LM, or a hybrid. Specify inputs, "
             "outputs/action space, how rules become hard constraints vs soft rewards, how retrieved SAR knowledge enters, and a training recipe that "
             "works with ~10 binding anchors + ~6.5k in-cell + ~7k permeability labels without circularity."},
 {"id": "E_loop_rlvr", "model": "deepseek/deepseek-v4-pro-0813", "fallback": "deepseek/deepseek-v4.1-flash",
  "mandate": "LOOP, VERIFIABLE REWARDS AND ACTIVE LEARNING. Design the optimisation loop for the case where the binding oracle is NOT yet validated: "
             "multi-fidelity oracle ladder, calibration against measured anchors, uncertainty-aware reward, selection of which expensive FEP edges to run, "
             "reward-hacking detection, placebo/shuffled-reward controls, and when the loop is allowed to claim an improvement. Say what the reward should "
             "be and what it must NOT be."},
 {"id": "F_innovation", "model": "x-ai/grok-4.7", "fallback": "x-ai/grok-4.6",
  "mandate": "INNOVATION. Ignore incrementalism. Propose the most novel direction that is still defensible and testable without a wet lab, using what the team "
             "uniquely has (a corrected audit trail of failures, measured anchors, in-cell availability data, a verified-reward DPO harness, a physics pipeline). "
             "Challenge the assumption that the target must be a better binder predictor; consider benchmarks, calibrated-abstention systems, adversarial "
             "evaluation, or physics-ML hybrids. Be concrete about the first experiment."},
 {"id": "G_medchem_output", "model": "z-ai/glm-5.3-prime", "fallback": "z-ai/glm-5.3",
  "mandate": "MEDICINAL CHEMISTRY, TRANSLATION AND OUTPUT. Judge what the system should DELIVER to a medicinal chemist / CRO / clinician team: the format of a "
             "decision-grade candidate dossier (calibrated uncertainty, provenance, pre-registered falsifiable predictions), the cheapest informative "
             "wet-lab experiment for alpha-v-beta-6 and PD-L1 (assay, n, controls), radioligand-specific concerns (renal retention, chelator effects, "
             "selectivity vs alpha-v-beta-3/5/8), and FTO realism. Also what the open-source community could use from this work."},
 {"id": "H_red_team", "model": "qwen/qwen3.8-max-prime", "fallback": "qwen/qwen3.8-max-0902",
  "mandate": "RED TEAM. Argue the strongest case that the current direction should be stopped, narrowed or pivoted. Identify the most likely way this program "
             "produces a confident, wrong result; the cheapest decisive experiment that would expose it; and what you would do with the same resources "
             "instead. Then say what would change your mind."},
]


def bundle():
    parts = ["# REVIEW PACKET (2026-10-25)\nEverything below is the team's own material. Candidate sequences, CRO panels and credentials are excluded.\n"]
    for f in DOCS:
        parts.append(f"\n\n===== DOC: {os.path.relpath(f, REPO)} =====\n" + open(f).read())
    for f in CODE:
        t = open(f).read()
        if len(t) > CAP:
            t = t[:CAP] + f"\n... [truncated at {CAP} chars]"
        parts.append(f"\n\n===== CODE: {os.path.relpath(f, REPO)} =====\n```python\n{t}\n```")
    return "".join(parts)


ARGS = dict(a.lstrip("-").split("=", 1) for a in sys.argv[1:] if "=" in a)   # --only=ID,ID --tokens=N --effort=low --workers=N


def _post(model, rv, packet):
    payload = {"model": model,
                       "messages": [{"role": "system", "content": COMMON + rv["mandate"] + "\n\n" + RUBRIC},
                                    {"role": "user", "content": "Review this work and answer in the required structure.\n\n" + packet}],
                       "max_tokens": int(ARGS.get("tokens", 12000)), "temperature": 0.4}
    if ARGS.get("effort"):   # cap hidden reasoning so the visible answer is not starved (Kimi/GLM burned 11.5k of 12k on reasoning)
        payload["reasoning"] = {"effort": ARGS["effort"]}
    body = json.dumps(payload).encode()
    req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", data=body,
                                 headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json",
                                          "HTTP-Referer": "https://biomate.ai", "X-Title": "Cyclic-Peptide Review Committee"})
    with urllib.request.urlopen(req, timeout=900) as r:
        return json.load(r)


def call(rv, packet):
    t0 = time.time(); last = ""
    for model in (rv["model"], rv["fallback"]):
        for attempt in (1, 2):
            try:
                d = _post(model, rv, packet)
                txt = d["choices"][0]["message"]["content"] or ""
                if len(txt) < 400:
                    raise RuntimeError(f"suspiciously short answer ({len(txt)} chars)")
                u = d.get("usage", {})
                fn = os.path.join(OUT, f"review_{rv['id']}.md")
                if os.path.exists(fn):
                    os.replace(fn, fn.replace(".md", ".attempt1_truncated.md"))
                open(fn, "w").write(
                    f"# Reviewer {rv['id']} -- {model}\n_(elapsed {time.time()-t0:.0f}s; usage {u})_\n\n" + txt)
                return rv["id"], True, f"{model} {time.time()-t0:.0f}s tokens={u.get('total_tokens')} chars={len(txt)}"
            except urllib.error.HTTPError as e:
                last = f"{model} HTTP {e.code}: {e.read().decode()[:200]}"
                if e.code in (400, 404):      # bad slug / unsupported -> go to fallback model
                    break
            except Exception as e:
                last = f"{model} {type(e).__name__}: {str(e)[:160]}"
            time.sleep(5)
    open(os.path.join(OUT, f"review_{rv['id']}.ERR"), "w").write(last)
    return rv["id"], False, last


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    pk = bundle()
    print(f"packet chars={len(pk)} (~{len(pk)//4} tokens); reviewers={len(REVIEWERS)}")
    open(os.path.join(OUT, "PACKET_SENT.md"), "w").write(pk)
    if "--dry" in sys.argv:
        print("dry run: packet written, nothing sent"); sys.exit(0)
    todo = [r for r in REVIEWERS if not ARGS.get("only") or r["id"] in ARGS["only"].split(",")]
    with ThreadPoolExecutor(max_workers=int(ARGS.get("workers", len(todo)))) as ex:
        for rid, ok, info in ex.map(lambda rv: call(rv, pk), todo):
            print(("OK   " if ok else "FAIL ") + f"{rid}: {info}")
    print("reviews written to", OUT)
