library(NoRCE)
library(RSQLite)

# 1. mirna_list.txt: List of miRNA names in miRBase format
mirnas <- c("hsa-let-7a-5p", "hsa-let-7b-5p", "hsa-let-7c-5p", "hsa-miR-155-5p")
writeLines(mirnas, "mirna_list.txt")

# 2. mirna_expr.csv: miRNA expression matrix (patient by gene data)
mirna_expr <- data.frame(
  "hsa-let-7a-5p" = c(1.2, 2.3, 3.4, 4.5),
  "hsa-let-7b-5p" = c(2.1, 3.2, 4.3, 5.4),
  "hsa-let-7c-5p" = c(3.1, 4.2, 5.3, 6.4),
  "hsa-miR-155-5p" = c(4.1, 5.2, 6.3, 7.4),
  check.names = FALSE
)
write.csv(mirna_expr, "mirna_expr.csv", row.names = FALSE)

# 3. mrna_expr.csv: mRNA expression matrix (patient by gene data)
mrna_expr <- data.frame(
  "ENSG00000100001" = c(5.2, 6.3, 7.4, 8.5),
  "ENSG00000100002" = c(6.1, 7.2, 8.3, 9.4),
  "ENSG00000100003" = c(7.1, 8.2, 9.3, 10.4),
  check.names = FALSE
)
write.csv(mrna_expr, "mrna_expr.csv", row.names = FALSE)

# 4. miRCancer.db: Local SQLite database for pre-computed correlations
# Creating a minimal valid SQLite database file
con <- dbConnect(RSQLite::SQLite(), "miRCancer.db")
# Create a dummy table to ensure the file is a valid SQLite database
dbWriteTable(con, "correlation_data", data.frame(
  miRNA = "hsa-let-7a-5p",
  mRNA = "ENSG00000100001",
  correlation = 0.85
))
dbDisconnect(con)