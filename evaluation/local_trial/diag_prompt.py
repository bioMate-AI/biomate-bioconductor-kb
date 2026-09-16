"""Shared T18 log-diagnosis prompt (train==eval)."""
import json
TAXONOMY=["input_mismatch","missing_input","wrong_format","reference_mismatch","resource_limit",
 "timeout","container_error","dependency_error","parameter_error","code_error","empty_output","permission_error"]
SYS=("You are BioMate. A workflow run failed. From the error log, classify the failure into exactly one "
     f"category from {TAXONOMY}, state the root cause grounded in the log, and give a concrete fix. "
     'Reply ONLY JSON: {"category":"...","root_cause":"...","fix":"..."}.')
FEWSHOT=[("nf-core/rnaseq","Error: No common samples found between counts.csv and coldata.csv. Execution halted",
          {"category":"input_mismatch","root_cause":"Sample IDs in counts.csv do not match coldata.csv.","fix":"Align sample identifiers so column names in counts.csv match rownames in coldata.csv."})]
def user_turn(workflow, error_log):
    return f"Workflow: {workflow}\nError log:\n{error_log[:1200]}\nReturn the JSON diagnosis."
def build_messages(workflow, error_log, few_shot=True):
    msgs=[{"role":"system","content":SYS}]
    if few_shot:
        for wf,log,ans in FEWSHOT:
            msgs.append({"role":"user","content":user_turn(wf,log)}); msgs.append({"role":"assistant","content":json.dumps(ans)})
    msgs.append({"role":"user","content":user_turn(workflow,error_log)}); return msgs
