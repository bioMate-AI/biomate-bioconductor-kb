# Real user-style input for aggregateBioVar: a single-cell RNA-seq
# SingleCellExperiment of raw counts spanning several SUBJECTS and CELL TYPES,
# with a genotype/condition label per subject -- the exact shape required for
# subject-level pseudobulk aggregation followed by DESeq2 differential
# expression. colData carries:
#   orig.ident - subject identifier (the aggregation unit)
#   celltype   - cell-type label (must include "Secretory cell")
#   Genotype   - per-subject condition with levels "WT" and "CFTRKO"
# Several subjects per genotype (so pseudobulk DESeq2 has replicates) and a real
# WT-vs-CFTRKO expression difference in a marker-gene subset. No demo data.

suppressPackageStartupMessages({
  library(SingleCellExperiment)
})

set.seed(2024)
n_genes <- 400
cell_types <- c("Secretory cell", "Ciliated cell", "Basal cell")
# 3 WT + 3 CFTRKO subjects
subjects <- data.frame(
    id = sprintf("subj%d", 1:6),
    Genotype = rep(c("WT", "CFTRKO"), each = 3),
    stringsAsFactors = FALSE
)

cells_per_subject_type <- 25
de_genes <- 1:40                          # genes that differ WT vs CFTRKO in secretory cells

rows <- list()
meta <- list()
for (s in seq_len(nrow(subjects))) {
    geno <- subjects$Genotype[s]
    for (ct in cell_types) {
        base <- rep(2, n_genes)
        # cell-type identity programme
        ct_block <- (match(ct, cell_types) - 1) * 50 + (1:50)
        base[ct_block] <- 10
        # genotype effect, only in secretory cells, on the DE-gene block
        if (ct == "Secretory cell" && geno == "CFTRKO") base[de_genes] <- base[de_genes] + 8
        m <- matrix(rpois(n_genes * cells_per_subject_type, lambda = base),
                    nrow = n_genes)
        rows[[length(rows) + 1]] <- m
        meta[[length(meta) + 1]] <- data.frame(
            orig.ident = rep(subjects$id[s], cells_per_subject_type),
            Genotype = rep(geno, cells_per_subject_type),
            celltype = rep(ct, cells_per_subject_type),
            stringsAsFactors = FALSE
        )
    }
}
counts <- do.call(cbind, rows)
cd <- do.call(rbind, meta)
rownames(counts) <- sprintf("Gene%03d", seq_len(n_genes))
colnames(counts) <- sprintf("cell%05d", seq_len(ncol(counts)))
rownames(cd) <- colnames(counts)
cd$Genotype <- factor(cd$Genotype, levels = c("WT", "CFTRKO"))
cd$celltype <- factor(cd$celltype, levels = cell_types)

small_airway <- SingleCellExperiment(
    assays = list(counts = counts),
    colData = DataFrame(cd)
)

saveRDS(small_airway, "small_airway.rds")
file.copy("small_airway.rds", "small_airway", overwrite = TRUE)
