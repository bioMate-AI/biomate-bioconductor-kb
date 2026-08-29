#!/usr/bin/env python3
"""Drive the whole RealBio leaderboard from models.yaml — one command, all models.

Runs every model whose key_env is SET (skips the rest with a note), across the classification
tasks, scores each with score.py, and writes leaderboard.{csv,md}. Idempotent: skips a
(model,task) whose predictions already exist.

  python3 run_all.py                       # run all available models on all classification tasks
  python3 run_all.py --task cross_domain_routing
  python3 run_all.py --models gpt-5.6,kimi-k3
  python3 run_all.py --list-provider-models --base-url https://openrouter.ai/api/v1 --key-env OPENROUTER_API_KEY
                                           # confirm the real model ids before running (fixes UNVERIFIED_SLUG)
"""
import os, sys, json, subprocess, argparse, yaml

HERE = os.path.dirname(os.path.abspath(__file__))
CLASSIFICATION_TASKS = ["cross_domain_routing", "workflow_generation", "autofix_benchmark", "protocol_thresholds"]

def load_models():
    return yaml.safe_load(open(os.path.join(HERE, "models.yaml")))["models"]

def list_provider_models(base_url, key_env):
    from openai import OpenAI
    c = OpenAI(base_url=base_url, api_key=os.environ[key_env])
    for m in sorted(x.id for x in c.models.list().data):
        print(" ", m)

def run_one(m, task):
    safe = m["name"]
    pred = os.path.join(HERE, "results", safe, f"{task}.jsonl")
    if not os.path.exists(pred):
        cmd = ["python3", os.path.join(HERE, "run_baseline.py"), task, "--model", m["model"], "--key-env", m["key_env"]]
        if m.get("base_url"): cmd += ["--base-url", m["base_url"]]
        # write to results/<name>/ by aliasing: run_baseline names dir after model id, so symlink after
        subprocess.run(cmd, check=True)
        # run_baseline writes under results/<model-id sanitized>/; normalize to results/<name>/
        src = os.path.join(HERE, "results", m["model"].replace("/", "_"), f"{task}.jsonl")
        if os.path.exists(src) and src != pred:
            os.makedirs(os.path.dirname(pred), exist_ok=True); os.replace(src, pred)
    out = subprocess.check_output(["python3", os.path.join(HERE, "score.py"), task, pred]).decode()
    return json.loads(out)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--task", default=None)
    ap.add_argument("--models", default=None)
    ap.add_argument("--list-provider-models", action="store_true")
    ap.add_argument("--base-url", default=None); ap.add_argument("--key-env", default="OPENROUTER_API_KEY")
    a = ap.parse_args()
    if a.list_provider_models:
        list_provider_models(a.base_url, a.key_env); return

    models = load_models()
    if a.models: models = [m for m in models if m["name"] in a.models.split(",")]
    tasks = [a.task] if a.task else CLASSIFICATION_TASKS

    board = {}  # model -> {task: metric}
    for m in models:
        if not os.environ.get(m["key_env"]):
            print(f"SKIP {m['name']:16} (no {m['key_env']})"); continue
        if m.get("status") == "UNVERIFIED_SLUG":
            print(f"WARN {m['name']:16} slug '{m['model']}' unverified — run --list-provider-models first")
        board[m["name"]] = {}
        for t in tasks:
            try:
                res = run_one(m, t)
                score = res.get("accuracy") or res.get("fix_category_accuracy") or res.get("param_f1")
                board[m["name"]][t] = score
                print(f"  {m['name']:16} {t:22} -> {score}")
            except Exception as e:
                board[m["name"]][t] = None; print(f"  {m['name']:16} {t:22} -> FAIL {str(e)[:60]}")

    # write leaderboard
    with open(os.path.join(HERE, "leaderboard.csv"), "w") as f:
        f.write("model," + ",".join(tasks) + "\n")
        for mdl, sc in board.items():
            f.write(mdl + "," + ",".join(str(sc.get(t, "")) for t in tasks) + "\n")
    with open(os.path.join(HERE, "leaderboard.md"), "w") as f:
        f.write("# RealBio Benchmark — Leaderboard\n\n| Model | " + " | ".join(tasks) + " |\n")
        f.write("|---|" + "---|" * len(tasks) + "\n")
        for mdl, sc in board.items():
            f.write(f"| {mdl} | " + " | ".join(f"{sc.get(t):.3f}" if isinstance(sc.get(t), float) else "—" for t in tasks) + " |\n")
    print("\nwrote leaderboard.csv + leaderboard.md")

if __name__ == "__main__":
    main()
