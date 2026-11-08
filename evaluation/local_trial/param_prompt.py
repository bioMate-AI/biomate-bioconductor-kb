"""Shared param-extraction prompt — imported by both the SFT formatter and eval."""
import json
SYS=("You are BioMate. Given a user request and a workflow parameter schema, extract ONLY the "
     "parameters the request explicitly implies, as a JSON object {key: value}. Use ONLY canonical "
     "keys and (for enums) allowed values from the schema. Do NOT invent keys and do NOT fill "
     "parameters the request does not imply. Reply with ONLY the JSON object.")
def render_schema(params):
    out=[]
    for p in params:
        av=p.get("allowed_values") or []
        out.append(f"- {p['name']} ({p.get('type')})"+(f" allowed={av}" if av else "")+f": {(p.get('description') or '')[:80]}")
    return "\n".join(out)
FEWSHOT=[("I have paired-end human RNA-seq FASTQs and want reverse-stranded quantification.",
          [{"name":"strandedness","type":"string","allowed_values":["forward","reverse","unstranded"],"description":"library strandedness"},
           {"name":"single_end","type":"boolean","description":"single-end reads"},
           {"name":"genome","type":"string","allowed_values":["GRCh38","GRCm39"],"description":"reference genome"}],
          {"strandedness":"reverse","single_end":False,"genome":"GRCh38"})]
def user_turn(query, params):
    return f"Request: {query}\nParameter schema:\n{render_schema(params)}\nReturn JSON of implied parameters only."
def build_messages(query, params, few_shot=True):
    msgs=[{"role":"system","content":SYS}]
    if few_shot:
        for q,ps,ans in FEWSHOT:
            msgs.append({"role":"user","content":user_turn(q,ps)})
            msgs.append({"role":"assistant","content":json.dumps(ans)})
    msgs.append({"role":"user","content":user_turn(query,params)})
    return msgs
