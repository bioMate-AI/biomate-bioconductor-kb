#!/bin/bash -ue
Rscript - <<'REOF'
# Mock mode: generate a synthetic ExpressionSet-like RDS and pData CSV
# so downstream processes can be developed and tested without network access.
set.seed(42)

n_genes   <- 200L
n_samples <- 20L

accession <- "GSE999999"

# ── Gene symbols ─────────────────────────────────────────────────────────────
landmark_genes <- c(
    "GAPDH", "TP53", "BRCA1", "BRCA2", "EGFR", "MYC", "KRAS", "PTEN",
    "RB1",   "AKT1", "VEGFA", "CDKN2A", "CDH1", "VHL", "MLH1",
    "MTOR",  "PIK3CA", "BRAF", "NRAS",  "ERBB2"
)
extra_genes <- paste0("GENE", formatC(seq_len(n_genes - length(landmark_genes)),
                                      width = 4, flag = "0"))
gene_symbols <- c(landmark_genes, extra_genes)

# ── Sample IDs (GSM-style accessions) ───────────────────────────────────────
gsm_start <- 1234567L
gsm_ids   <- paste0("GSM", seq(gsm_start, gsm_start + n_samples - 1L))

# ── Simulated count / expression matrix ─────────────────────────────────────
# Negative-binomial-like: base expression + treatment effect for half samples
set.seed(1)
base_expr <- matrix(
    rnbinom(n_genes * n_samples, mu = 500, size = 10),
    nrow = n_genes, ncol = n_samples,
    dimnames = list(gene_symbols, gsm_ids)
)
# Introduce a mild treatment effect in samples 11-20 for first 20 genes
treatment_mask <- c(rep(FALSE, 10), rep(TRUE, 10))
base_expr[1:20, treatment_mask] <- base_expr[1:20, treatment_mask] *
    round(runif(20, 1.5, 3.0), 1)

# ── pData (phenotype / sample metadata) ─────────────────────────────────────
set.seed(2)
pdata <- data.frame(
    geo_accession       = gsm_ids,
    title               = paste0("Sample_", seq_len(n_samples)),
    source_name_ch1     = rep(c("tumor", "normal"), each = n_samples / 2),
    organism_ch1        = "Homo sapiens",
    treatment_protocol_ch1 = ifelse(treatment_mask, "Drug_A_100nM", "Vehicle"),
    age                 = round(runif(n_samples, 35, 75)),
    Sex                 = sample(c("Male", "Female"), n_samples, replace = TRUE),
    overall_survival_months = round(runif(n_samples, 6, 60), 1),
    vital_status        = sample(c("Alive", "Dead"), n_samples, replace = TRUE,
                                 prob = c(0.6, 0.4)),
    platform_id         = "GPL570",
    data_processing     = "RMA normalised",
    stringsAsFactors    = FALSE,
    row.names           = gsm_ids
)

# ── Build a minimal list mimicking GEOquery's getGEO() output ────────────────
geo_obj <- list(
    accession    = accession,
    exprs        = base_expr,
    pData        = pdata,
    featureData  = data.frame(
        ID     = gene_symbols,
        Symbol = gene_symbols,
        row.names = gene_symbols,
        stringsAsFactors = FALSE
    )
)
class(geo_obj) <- "BioMateMockGEO"

saveRDS(geo_obj, "series_matrix.rds")
write.csv(pdata, "sample_metadata.csv", row.names = TRUE, quote = TRUE)

cat("Mock GEO_FETCH complete\n")
cat("  Accession :", accession, "\n")
cat("  Genes     :", n_genes,   "\n")
cat("  Samples   :", n_samples, "\n")
REOF

        cat <<-END_VERSIONS > versions.yml
        "GEO_DATA_CONNECTOR:GEO_FETCH":
            r-base: $(R --version | head -1 | awk '{print $3}')
            bioconductor-geoquery: "2.72.0 (mock)"
        END_VERSIONS
