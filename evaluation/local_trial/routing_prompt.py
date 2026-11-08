"""Shared routing prompt — imported by both the SFT formatter and the eval harness
so training and evaluation use a byte-identical in-format protocol."""
SYS = ("You are BioMate, a bioinformatics workflow router. Given a user request and a list "
       "of candidate workflows, choose the single best-matching workflow. "
       "Reply with ONLY its exact name from the candidate list.")

# 2 fixed few-shot exemplars (generic; drawn from training-domain conventions, not test items)
FEWSHOT = [
    ("Align paired-end bulk RNA-seq reads and quantify gene expression for a human cohort.",
     ["nf-core/sarek", "nf-core/rnaseq", "nf-core/atacseq", "nf-core/ampliseq"], "nf-core/rnaseq"),
    ("Call germline SNVs and indels from whole-genome sequencing BAMs against GRCh38.",
     ["nf-core/rnaseq", "nf-core/sarek", "nf-core/chipseq", "nf-core/taxprofiler"], "nf-core/sarek"),
]

def _cand_block(cands):
    return "\n".join(f"- {c}" for c in cands)

def user_turn(query, candidates, in_format=True):
    if not in_format:  # "starved" control: no candidate list
        return f"Request: {query}\nReply with ONLY the exact workflow name."
    return (f"Request: {query}\nCandidate workflows:\n{_cand_block(candidates)}\n"
            f"Reply with ONLY the exact workflow name from the list above.")

def build_messages(query, candidates, in_format=True, few_shot=True):
    msgs = [{"role": "system", "content": SYS}]
    if in_format and few_shot:
        for q, cands, ans in FEWSHOT:
            msgs.append({"role": "user", "content": user_turn(q, cands, True)})
            msgs.append({"role": "assistant", "content": ans})
    msgs.append({"role": "user", "content": user_turn(query, candidates, in_format)})
    return msgs
