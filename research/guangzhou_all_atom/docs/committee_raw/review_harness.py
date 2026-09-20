#!/usr/bin/env python3
"""Cyclic-Peptide Engine Review Board — 3 independent flagship reviewers via OpenRouter.
Bundles the manuscript + design docs + key code, sends to each with a distinct adversarial mandate,
saves each review. Chair (the calling agent) synthesizes afterward."""
import json, os, sys, time, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor

OUT='/private/tmp/claude-501/-Users-kky/fe27dcb8-94cd-46b4-88e0-58267c555707/scratchpad/committee'
KEY=open(os.path.join(OUT,'.inference_key')).read().strip()   # minted inference key (provisioning key can't do completions)
REPO='/Users/kky/biomate-review/research/guangzhou_all_atom'
OUT='/private/tmp/claude-501/-Users-kky/fe27dcb8-94cd-46b4-88e0-58267c555707/scratchpad/committee'

DOCS=['docs/MANUSCRIPT.md','docs/PERMEABILITY_DRIVEN_GENERATION.md','docs/PROGRAM_STATE_20260918.md']
CODE=['perm_redesign_v1.py','perm_generation_v3.py','peptide_nmethyl_mmgbsa.sh','peptide_mmgbsa_v3verify.sh']

def bundle():
    parts=["# CYCLIC-PEPTIDE DRUG-DESIGN ENGINE — WORK + CODE FOR REVIEW\n",
           "The engine: BoltzGen generate -> MM-GBSA physics verify + permeability model -> multi-objective "
           "select -> N-methyl redesign -> re-verify. Below: the manuscript, design docs, and key source.\n"]
    for f in DOCS:
        parts.append(f"\n\n===== DOC: {f} =====\n"+open(os.path.join(REPO,f)).read())
    for f in CODE:
        parts.append(f"\n\n===== CODE: {f} =====\n```\n"+open(os.path.join(REPO,f)).read()+"\n```")
    return "".join(parts)

RUBRIC=("Return your review in this exact markdown structure:\n"
        "## VERDICT: <ACCEPT / MINOR REVISION / MAJOR REVISION / REJECT> (confidence 0-1)\n"
        "## TOP 3 THINGS THAT ARE RIGHT\n"
        "## CRITICAL ISSUES (must-fix; each: claim/location -> problem -> concrete fix)\n"
        "## MAJOR CONCERNS\n"
        "## MINOR ISSUES\n"
        "## SPECIFIC CODE BUGS (file:approx-location -> bug -> fix; write 'none found' if so)\n"
        "## WHAT WOULD MAKE THIS PUBLISHABLE / PRODUCTION-READY\n"
        "Be a demanding, adversarial peer reviewer. Cite specific numbers/claims/lines. Do NOT be agreeable "
        "for its own sake. If a claim is over-stated relative to its evidence, say so explicitly.")

REVIEWERS=[
 {"id":"A_rigor","model":"anthropic/claude-opus-5",
  "system":"You are Reviewer A: a rigorous computational-biology peer reviewer and CLAIMS AUDITOR. Your job: "
           "verify EVERY quantitative claim is supported by the data shown; hunt overclaiming; check that the "
           "honesty caveats are correct AND complete (MM-GBSA is relative-only with size bias; the single-"
           "trajectory strain artifact where ddG is a 1-4% residual of ~300 kcal/mol near-cancelling terms; "
           "iptm being orthogonal to physics dG; the approximate N-methyl charges; small n=4 targets). Flag any "
           "conclusion the data does not support, and any place the writing is more confident than warranted."},
 {"id":"B_methodology","model":"openai/gpt-6-astra-pro",
  "system":"You are Reviewer B: a demanding methodology & statistics critic (think adversarial Reviewer 2). "
           "Scrutinize experimental design, controls, sample sizes, confounds (e.g. peptide size/MW confounding "
           "permeability headroom; the single-trajectory cancellation; MM-GBSA vs FEP), statistical validity, "
           "alternative explanations, and reproducibility. For each major result state whether the experiment "
           "actually supports the stated conclusion, and what additional control/experiment would be required."},
 {"id":"C_compchem_code","model":"google/gemini-3.1-pro-preview",
  "system":"You are Reviewer C: a computational-chemistry SOTA expert AND a senior code reviewer. Judge the "
           "force-field/physics choices against field standards (CHARMM36m, psfgen patches, GBn2 implicit "
           "solvent, MM-GBSA protocol, permeability modeling), and SCRUTINIZE the borrowed N-methyl NMET patch "
           "parameters and approximate charges for physical correctness. Separately, do a real CODE REVIEW of "
           "the scripts: bugs, edge cases, incorrect assumptions (chain splitting, atom slicing for MM-GBSA, "
           "cyclization/patch application, RDKit usage), and reproducibility/infra risks."},
]

def call(rv, packet):
    body=json.dumps({"model":rv["model"],
        "messages":[{"role":"system","content":rv["system"]+"\n\n"+RUBRIC},
                    {"role":"user","content":"Review this work and code.\n\n"+packet}],
        "max_tokens":6000,"temperature":0.3}).encode()
    req=urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", data=body,
        headers={"Authorization":f"Bearer {KEY}","Content-Type":"application/json",
                 "HTTP-Referer":"https://biomate.ai","X-Title":"Cyclic-Peptide Review Board"})
    t0=time.time()
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            d=json.load(r)
        txt=d["choices"][0]["message"]["content"]; usage=d.get("usage",{})
        open(os.path.join(OUT,f"review_{rv['id']}.md"),"w").write(
            f"# Reviewer {rv['id']} — {rv['model']}\n_(elapsed {time.time()-t0:.0f}s; usage {usage})_\n\n"+txt)
        return rv['id'], True, f"{time.time()-t0:.0f}s tokens={usage.get('total_tokens')}"
    except urllib.error.HTTPError as e:
        msg=e.read().decode()[:400]; open(os.path.join(OUT,f"review_{rv['id']}.ERR"),"w").write(msg)
        return rv['id'], False, f"HTTP {e.code}: {msg[:200]}"
    except Exception as e:
        return rv['id'], False, f"{type(e).__name__}: {e}"

if __name__=="__main__":
    os.makedirs(OUT, exist_ok=True)
    pk=bundle(); print(f"packet chars={len(pk)} (~{len(pk)//4} tokens)")
    with ThreadPoolExecutor(max_workers=3) as ex:
        for rid,ok,info in ex.map(lambda rv: call(rv,pk), REVIEWERS):
            print(("OK  " if ok else "FAIL")+f" {rid}: {info}")
    print("reviews written to", OUT)
