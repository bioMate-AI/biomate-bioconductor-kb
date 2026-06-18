# [biomate] structured fixture (rule: interp_dataload) — deterministic, no LLM

data("inputCaseA")
.obj <- get("inputCaseA")
# Workflow reads this with read.csv(stringsAsFactors=FALSE) (no row.names); write a
# plain CSV of the data frame (a saveRDS blob is not parseable by read.csv).
write.csv(as.data.frame(.obj), "inputCaseA", row.names=FALSE)
