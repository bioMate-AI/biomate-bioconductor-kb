# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("samplesForChrSynthetic")
.obj <- get("samplesForChrSynthetic")
saveRDS(.obj, "samplesForChrSynthetic")
