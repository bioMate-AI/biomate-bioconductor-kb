#!/usr/bin/env Rscript
# Extract REAL IMvigor210 patient-level clinical + CD8 T-effector score for the
# Stream-3 Cox self-correction demo, producing patient_clinical_naive.csv and
# patient_clinical_adjusted.csv (the exact inputs the survival Cox workflow stages).
#
# Data: Genentech IMvigor210CoreBiologies R package (CC-BY 3.0), Mariathasan 2018.
# Only Biobase is needed (the package itself depends on the removed DESeq; we read
# the saved objects directly, exactly as the public reanalysis does).
#
#   Rscript extract_imvigor210.R            # writes the two CSVs next to this script
#
# The BioMate bioc container (bioc-domain-general:3.20-slim) ships R+Biobase, so
# this runs there unmodified; locally it needs R + Biobase installed.

suppressPackageStartupMessages(library(Biobase))
out <- dirname(sub("--file=", "", grep("--file=", commandArgs(FALSE), value = TRUE)[1]))
if (is.na(out) || out == "") out <- "."

url <- "http://research-pub.gene.com/IMvigor210CoreBiologies/packageVersions/IMvigor210CoreBiologies_1.0.1.tar.gz"
md5 <- "347b390baf2f375f383726fa1157db29"
tgz <- file.path(out, basename(url))
if (!file.exists(tgz)) download.file(url, tgz, mode = "wb")
stopifnot(unname(tools::md5sum(tgz)) == md5)
untar(tgz, files = c("IMvigor210CoreBiologies/data/cds.RData",
                     "IMvigor210CoreBiologies/data/human_gene_signatures.RData"),
      exdir = out)
pkg <- file.path(out, "IMvigor210CoreBiologies", "data")
load(file.path(pkg, "cds.RData"))                      # cds: DESeq CountDataSet
counts <- get("counts", envir = attr(cds, "assayData"))
pheno  <- attr(attr(cds, "phenoData"), "data")
feat   <- attr(attr(cds, "featureData"), "data")
load(file.path(pkg, "human_gene_signatures.RData"))    # human_gene_signatures

# --- CD8 T-effector signature score (log2-CPM, z-scored mean over signature genes)
cpm   <- sweep(counts, 2, colSums(counts), "/") * 1e6
logcpm <- log2(cpm + 1)
sym   <- feat[rownames(counts), "symbol"]
teff_genes <- as.character(human_gene_signatures[["CD8 T effector"]])
idx <- which(sym %in% teff_genes)
score <- colMeans(logcpm[idx, , drop = FALSE])
teff_z <- as.numeric(scale(score))

# --- clinical covariates (column names per the package pData)
os     <- suppressWarnings(as.numeric(pheno[["os"]]))
cens   <- suppressWarnings(as.numeric(pheno[["censOS"]]))        # 1 = death
ecog   <- suppressWarnings(as.numeric(pheno[["Baseline ECOG Score"]]))
metsts <- tolower(as.character(pheno[["Met Disease Status"]]))
tmb    <- suppressWarnings(as.numeric(pheno[["FMOne mutation burden per MB"]]))

df <- data.frame(
  patient_id   = rownames(pheno),
  time         = os,
  status       = cens,
  cd8teffector = round(teff_z, 4),
  log_tmb      = round(as.numeric(scale(log2(tmb + 1))), 4),
  ecog_ge1     = as.integer(ecog >= 1),
  liver_mets   = as.integer(grepl("liver", metsts)),
  stringsAsFactors = FALSE
)
df <- df[is.finite(df$time) & is.finite(df$status), ]
cat(sprintf("IMvigor210: N=%d, deaths=%d\n", nrow(df), sum(df$status == 1, na.rm = TRUE)))

write.csv(df[, c("patient_id","time","status","cd8teffector")],
          file.path(out, "patient_clinical_naive.csv"), row.names = FALSE)
write.csv(df[, c("patient_id","time","status","cd8teffector","log_tmb","ecog_ge1","liver_mets")],
          file.path(out, "patient_clinical_adjusted.csv"), row.names = FALSE)
cat("Wrote patient_clinical_naive.csv and patient_clinical_adjusted.csv\n")
