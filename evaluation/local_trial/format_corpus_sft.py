"""Format the assembled corpus_train.jsonl (input/target per task) into the SFT message format the
trainer consumes, with task-appropriate production prompts. Emits multitask_sft_v2.jsonl (train split
only; eval stays held out for eval_corpus.py). Run AFTER the final assemble, then stage to S3 and launch
the SPOT retrain (MODEL_SIZE=small STAGE=full using this file).
"""
import json, os
P = "/Users/kky/biomate-review/docs/20260912_onprem_llm/data_pool_v2"

SYS = "You are BioMate, an agentic bioinformatics workflow assistant."
USER = {
    "routing": lambda r: f"Name the single best workflow for this request. Reply ONLY the workflow name.\n\nRequest: {r['input']}",
    "param": lambda r: f"Extract the parameters this request implies as key: value lines. Do not invent.\n\nRequest: {r['input']}",
    "wfgen": lambda r: f"Name the workflow category/domain for this request. Reply ONLY the category.\n\nRequest: {r['input']}",
    "decompose": lambda r: f'Decompose into an ordered sub-task plan. Reply ONLY a JSON list of {{"sub_task":...,"order":N}}.\n\nRequest: {r["input"]}',
    "autofix": lambda r: f"Classify this pipeline failure into ONE fix category. Reply ONLY the category.\n\nError:\n{r['input'][:1200]}",
    "clarification": lambda r: f"If a required parameter is missing, ask the user for it (name it).\n\nRequest: {r['input']}",
    "conditional_param": lambda r: f"Extract only the parameters the user overrides from defaults.\n\nRequest: {r['input']}",
    "chaining": lambda r: f'Decompose into an ordered workflow chain. Reply ONLY a JSON list of {{"workflow":...,"order":N}}.\n\nRequest: {r["input"]}',
    "diagnosis": lambda r: f'Diagnose this pipeline failure. Reply ONLY JSON {{"root_cause":...,"fix":...}}.\n\nError:\n{r["input"][:1200]}',
    "dataset_compatibility": lambda r: f"Is this dataset compatible with the target workflow's inputs? Reply YES or NO + one-line reason.\n\nDataset: {r['input']}",
    "knowledge_qa": lambda r: f"Answer concisely and factually.\n\nQuestion: {r['input']}",
}


def tgt(r):
    t = r["target"]
    return t if isinstance(t, str) else json.dumps(t, ensure_ascii=False)


def main():
    rows = [json.loads(l) for l in open(f"{P}/corpus_train.jsonl")]
    n = 0
    with open(f"{P}/multitask_sft_v2.jsonl", "w") as f:
        for r in rows:
            mk = USER.get(r["task"])
            if not mk or not r.get("target"): continue
            f.write(json.dumps({"messages": [
                {"role": "system", "content": SYS},
                {"role": "user", "content": mk(r)},
                {"role": "assistant", "content": tgt(r)}],
                "task": r["task"], "weight": r.get("weight", 1.0)}) + "\n")
            n += 1
    print(f"multitask_sft_v2.jsonl: {n} SFT examples (train split; eval held out)")
    print("next: stage to S3 sft/multitask_sft_enriched.jsonl, then MODEL_SIZE=small STAGE=full spot_launch.sh (SPOT)")


if __name__ == "__main__":
    raise SystemExit(main())
