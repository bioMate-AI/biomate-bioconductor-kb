# BIOMATE AI | Commercial Case Brief | Prepared by BizBildr LLC
*Confidential*

## CASE BRIEF
# Ask in Plain English, Get the Right Pipeline the First Time

### THE PROBLEM
A biologist knows what they want to *find* ("open chromatin," "cell types," "drug-target binding") but not the name of the tool that does it. Searching a catalog of thousands of workflows by keyword misses these, so users pick the wrong pipeline, waste a run, and start over — minutes of friction on every request, multiplied across a whole institution.

### THE BIOMATE AI WORKFLOW
BioMate reads the user's plain-language request, infers the missing technical vocabulary (e.g., "open chromatin" → "ATAC-seq"), and adds those terms to its search *without throwing away the user's own words* — so specific tool names the user did mention still count. The right workflow surfaces at the top, from a catalog of 2,455 pipelines across 34 fields.

### TIME, COST & QUALITY COMPARISON

| Metric | Manual Pipeline | BioMate AI |
|---|---|---|
| Time to the right workflow | 5–15 min (search, compare, resubmit) | ~3 seconds |
| Cost per query | Analyst time | Fractions of a cent |
| Top-1 accuracy (benchmark) | 46–82% keyword only | 100% on the 54-case benchmark |
| Vs. asking a frontier AI directly | — | +15 points more accurate (and no invented tool names) |

### OUTCOME
Users stop guessing which pipeline to run and stop losing time on wrong turns. Requests route to the correct workflow on the first try, which means fewer wasted compute runs, faster time-to-analysis, and less support load — while being measurably more accurate than asking a general-purpose AI, because BioMate retrieves from a real, indexed catalog instead of relying on the AI's memory.

### TECHNICAL VALIDATION NOTE
On a 54-case benchmark spanning six failure modes, BioMate's key-term-injection retrieval reached 100% top-1 precision, versus 81.5% for keyword search alone and 85.2% for a frontier LLM (Claude Sonnet 4.6) answering the same queries without catalog access. A destructive alternative that rewrote the whole query regressed to 26%, confirming the value of preserving the user's own words. Full technical validation report available on request.

### COMMERCIAL TIER & HOSTING MOAT
Large-DB-search tier. The moat is the hosted index: LLM-augmented routing over a 2,455-workflow catalog that is impractical to build, host, and keep current locally.

*Design constraint: readable in ~90 seconds by a platform or data-science lead. Depth lives in the companion Scientific & Technical Validation Report.*
