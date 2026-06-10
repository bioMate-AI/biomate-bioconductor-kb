library(NetSAM)

files_to_copy <- c(
  "exampleGeneList.txt",
  "exampleNetwork_nonsymbol.net",
  "exampleExpressionData_nonsymbol.cct",
  "exampleSBT.sbt",
  "exampleSCT.sct"
)

for (f in files_to_copy) {
  src <- system.file("extdata", f, package = "NetSAM")
  if (src != "" && file.exists(src)) {
    file.copy(src, f, overwrite = TRUE)
  } else {
    # Fallback to synthetic data if the file is missing from the installation
    if (f == "exampleGeneList.txt") {
      write.table(data.frame(V1 = c("100008586", "10000")), f, sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
    } else if (f == "exampleNetwork_nonsymbol.net") {
      write.table(data.frame(V1 = c("100008586"), V2 = c("10000")), f, sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
    } else if (f == "exampleExpressionData_nonsymbol.cct") {
      write.table(data.frame(ID = c("100008586", "10000"), S1 = c(1.5, 2.5), S2 = c(1.1, 2.2)), f, sep = "\t", row.names = FALSE, col.names = TRUE, quote = FALSE)
    } else if (f == "exampleSBT.sbt") {
      write.table(data.frame(V1 = c("100008586", "10000"), V2 = c(1, 2)), f, sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
    } else if (f == "exampleSCT.sct") {
      write.table(data.frame(V1 = c("100008586", "10000"), V2 = c(1, 2)), f, sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
    }
  }
}