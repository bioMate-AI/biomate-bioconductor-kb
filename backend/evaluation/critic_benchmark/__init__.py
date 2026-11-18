"""
critic_benchmark — turn "BioMate self-corrects" into a measured number.

The committee's correction (04_llm_critic_eval_review.md §4): the RealBio ``autofix``
task measures failure-*classification* on runs that already **crashed** — the easy
half. The critic layer's hard job is **silent validity flaws in runs that
*succeeded***. There is no error log; the run looks clean. The only honest way to
measure that is *synthetic error-injection into clean runs*: take a representative
clean-run contract, inject a known flaw with a known ground-truth label, keep the
matched clean run as a negative, and add *hard negatives* (cases that LOOK flawed but
are valid — a mediator that must NOT be adjusted, a balanced covariate that is not a
confounder). Then run the registered critics and score them.

This package is self-contained (stdlib + the read-only critics package) and runs on
python3.9. It is packaged as a RealBio ``critic_benchmark`` task:
``data.jsonl`` (ground truth) + ``score.py`` (deterministic scorer) + a runner.
"""
