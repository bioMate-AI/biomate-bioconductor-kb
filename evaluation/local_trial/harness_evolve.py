"""Inner-loop HARNESS EVOLUTION (ScienceBuddy-style), fully local-capable.

Evolve skills/instructions against an eval harness with the task MODEL FROZEN:
  1) run the frozen task model on a dev split under the current harness -> collect failures
  2) a proposer model diagnoses failures -> proposes ONE bounded edit (add/revise/remove a skill or
     the system instruction; size-limited)
  3) apply the edit to a candidate harness; re-score the dev split
  4) accept the edit ONLY if the grounded score improves (rubric = the scorer); else reject
  5) repeat; report val score before/after.

Model-agnostic: task + proposer are OpenAI-compatible endpoints (our served 27B, OpenRouter, etc.).
--dry-run validates the ORCHESTRATION with a deterministic stub model (no GPU/endpoint needed):
a task "passes" iff the harness contains its required skill-keyword, and the stub proposer adds the
missing keyword from a failure — so accept-on-improvement is exercised end-to-end offline.
"""
from __future__ import annotations
import argparse, json, os, re, copy, urllib.request

# ---------------- harness state ----------------
class Harness:
    def __init__(self, system_instruction="You are BioMate, a bioinformatics assistant.", skills=None):
        self.system_instruction = system_instruction
        self.skills = dict(skills or {})            # name -> body text
    def render_system(self, query):
        q = query.lower()
        picked = [f"<skill name={n!r}>\n{b}\n</skill>" for n, b in self.skills.items()
                  if any(t for t in _triggers(n, b) if t in q)]
        return self.system_instruction + ("\n" + "\n".join(picked) if picked else "")
    def clone(self): return Harness(self.system_instruction, dict(self.skills))
    def size(self): return len(self.system_instruction) + sum(len(b) for b in self.skills.values())
    def save(self, d):
        os.makedirs(d, exist_ok=True)
        json.dump({"system_instruction": self.system_instruction, "skills": self.skills},
                  open(os.path.join(d, "harness.json"), "w"), indent=2)
    @classmethod
    def load(cls, d):
        p = os.path.join(d, "harness.json")
        if os.path.exists(p):
            o = json.load(open(p)); return cls(o["system_instruction"], o["skills"])
        return cls()

def _triggers(name, body):
    # crude trigger set: skill name tokens + any 'triggers:' line in the body
    toks = re.split(r"[^a-z0-9]+", name.lower())
    m = re.search(r"triggers:\s*(.+)", body.lower())
    if m: toks += re.split(r"[,\s]+", m.group(1))
    return [t for t in toks if len(t) >= 3]

# ---------------- model call ----------------
def _call(cfg, messages, max_tokens=256):
    body = json.dumps({"model": cfg["model"], "messages": messages, "max_tokens": max_tokens,
                       "temperature": 0}).encode()
    req = urllib.request.Request(cfg["base_url"].rstrip("/") + "/chat/completions", data=body,
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {os.environ.get(cfg.get('key_env','NONE'),'x')}"})
    d = json.load(urllib.request.urlopen(req, timeout=120))
    return d["choices"][0]["message"]["content"]

# ---------------- scorers (rubric) ----------------
def _norm(s): return re.sub(r"[^a-z0-9]+", " ", str(s).lower()).strip()
def score_one(scorer, out, gold):
    if scorer == "exact":     return 1.0 if _norm(out) == _norm(gold) else 0.0
    if scorer == "contains":  return 1.0 if _norm(gold) and _norm(gold) in _norm(out) else 0.0
    if scorer == "json_keys":
        try: o = json.loads(re.search(r"\{.*\}", out, re.S).group(0))
        except Exception: return 0.0
        g = gold if isinstance(gold, dict) else json.loads(gold)
        return 1.0 if all(_norm(o.get(k)) == _norm(v) for k, v in g.items()) and len(o) == len(g) else 0.0
    return 0.0

# ---------------- task model (frozen) ----------------
def run_task(harness, task, cfg, dry_run):
    if dry_run:  # deterministic stub: pass iff harness contains the required keyword
        need = task.get("_needs_kw", "")
        blob = _norm(harness.system_instruction + " " + " ".join(harness.skills))
        return task["gold"] if (need and need in blob) else "__no_skill__"
    sysmsg = harness.render_system(task.get("input", task["prompt"]))
    return _call(cfg, [{"role": "system", "content": sysmsg}, {"role": "user", "content": task["prompt"]}])

def score_set(harness, tasks, cfg, dry_run):
    fails, tot = [], 0.0
    for t in tasks:
        out = run_task(harness, t, cfg, dry_run); s = score_one(t.get("scorer", "contains"), out, t["gold"])
        tot += s
        if s < 1.0: fails.append({"id": t["id"], "prompt": t["prompt"][:200], "gold": t["gold"], "got": str(out)[:120], "_needs_kw": t.get("_needs_kw", "")})
    return tot / max(len(tasks), 1), fails

# ---------------- proposer (bounded edit) ----------------
MAX_SKILL_LEN = 600
def propose_edit(failures, harness, cfg, dry_run):
    if dry_run:  # stub: add a skill supplying the keyword the most common failure needs
        kw = next((f["_needs_kw"] for f in failures if f.get("_needs_kw")), None)
        if not kw: return None
        return {"op": "add", "target": "skill", "name": f"auto_{kw}", "text": f"triggers: {kw}\nWhen the request concerns {kw}, apply the {kw} procedure carefully."}
    fs = "\n".join(f"- {f['prompt']} | expected: {f['gold']} | got: {f['got']}" for f in failures[:12])
    cur = "SYSTEM_INSTRUCTION:\n" + harness.system_instruction + "\nSKILLS:\n" + "\n".join(f"- {n}" for n in harness.skills)
    prompt = ("You improve a bioinformatics assistant's HARNESS (instructions + skills), the model is FIXED. "
      "Given failing cases and the current harness, propose EXACTLY ONE bounded edit that would fix a failure "
      "class without harming others. Reply ONLY JSON: "
      '{"op":"add|revise|remove","target":"skill|instruction","name":"<skill name or empty>","text":"<new/updated text, <=600 chars>","rationale":"..."}\n\n'
      f"CURRENT:\n{cur}\n\nFAILURES:\n{fs}")
    try:
        m = re.search(r"\{.*\}", _call(cfg, [{"role": "user", "content": prompt}], 500), re.S)
        return json.loads(m.group(0)) if m else None
    except Exception: return None

def apply_edit(h, edit):
    if not edit or "op" not in edit: return None
    if len(edit.get("text", "")) > MAX_SKILL_LEN: edit["text"] = edit["text"][:MAX_SKILL_LEN]
    c = h.clone(); op, tgt = edit["op"], edit.get("target")
    if tgt == "instruction":
        if op in ("add", "revise"): c.system_instruction = (c.system_instruction + "\n" + edit["text"]).strip() if op == "add" else edit["text"]
    else:
        nm = edit.get("name") or "skill"
        if op == "remove": c.skills.pop(nm, None)
        else: c.skills[nm] = edit["text"]
    return c

# ---------------- inner loop ----------------
def evolve(dev, val, harness, task_cfg, prop_cfg, rounds, dry_run, eps=1e-9):
    traj = []
    v0, _ = score_set(harness, val, task_cfg, dry_run)
    for r in range(rounds):
        acc, fails = score_set(harness, dev, task_cfg, dry_run)
        if not fails: traj.append({"round": r, "dev": round(acc, 3), "note": "no failures"}); break
        edit = propose_edit(fails, harness, prop_cfg, dry_run)
        cand = apply_edit(harness, edit)
        if cand is None: traj.append({"round": r, "dev": round(acc, 3), "note": "no valid edit"}); break
        cacc, _ = score_set(cand, dev, task_cfg, dry_run)
        accept = cacc > acc + eps
        traj.append({"round": r, "dev_before": round(acc, 3), "dev_after": round(cacc, 3),
                     "edit": {k: edit.get(k) for k in ("op", "target", "name")}, "accepted": accept})
        if accept: harness = cand
    v1, _ = score_set(harness, val, task_cfg, dry_run)
    return harness, {"val_before": round(v0, 3), "val_after": round(v1, 3), "trajectory": traj}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tasks", help="jsonl: {id,prompt,gold,scorer,input?}")
    ap.add_argument("--out", default="/tmp/evolved_harness")
    ap.add_argument("--rounds", type=int, default=8)
    ap.add_argument("--base-url", default="http://127.0.0.1:8000/v1"); ap.add_argument("--model", default="base"); ap.add_argument("--key-env", default="DUMMY_KEY")
    ap.add_argument("--proposer-model", default=None)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    if a.dry_run and not a.tasks:
        # built-in synthetic task set: each needs a distinct skill keyword the base harness lacks
        kws = ["rnaseq", "variant", "chip", "atac", "singlecell"]
        tasks = [{"id": f"t{i}", "prompt": f"Do the {k} analysis", "gold": f"{k}-OK", "scorer": "exact", "_needs_kw": k}
                 for i, k in enumerate(kws) for _ in range(4)]
    else:
        tasks = [json.loads(l) for l in open(a.tasks) if l.strip()]
    dev = tasks[::2]; val = tasks[1::2]
    task_cfg = {"base_url": a.base_url, "model": a.model, "key_env": a.key_env}
    prop_cfg = {"base_url": a.base_url, "model": a.proposer_model or a.model, "key_env": a.key_env}
    h0 = Harness()
    h, rep = evolve(dev, val, h0, task_cfg, prop_cfg, a.rounds, a.dry_run)
    h.save(a.out)
    print(json.dumps(rep, indent=2))
    print(f"skills after evolution: {list(h.skills)}")

if __name__ == "__main__":
    main()
