library(wpm)

df <- data.frame(
  Sample = paste0("s", 1:8),
  Type = rep(c("A", "B"), each = 4),
  Treatment = rep(c("trt1", "Ctrl"), times = 4)
)

write.table(df, file = "path-to-CSV-file", sep = ";", row.names = FALSE, quote = FALSE)