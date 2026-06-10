#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: destiny — qpcr_diffusion_map_and_dpt
// Preprocess single-cell qPCR Ct data, build a diffusion map with censoring, calculate diffusion pseudotime, and visualize lineage branching.
// Input: mmc4.xls, mmc6.xls
// Container: quay.io/biocontainers/bioconductor-destiny:3.24.0--r45ha27e39d_0
// R packages: Biobase, destiny, gridExtra, readxl
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DESTINY_QPCR_DIFFUSION_MAP_AND_DPT {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-destiny:3.24.0--r45ha27e39d_0"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("Biobase", "destiny", "gridExtra", "readxl")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }
    
    # Set seed for reproducibility
    set.seed(1)
    
    # Load required libraries
    library(readxl)
    library(destiny)
    library(Biobase)
    
    # 1. Import raw Ct data and convert to ExpressionSet
    raw_ct <- read_xls('mmc4.xls', 'Sheet1')
    ct <- as.ExpressionSet(as.data.frame(raw_ct))
    
    # 2. Clean data by filtering out undivided cells and high Ct values
    num_cells <- gsub('^(\\d+)C.*\$', '\\1', ct\$Cell)
    ct\$num_cells <- as.integer(num_cells)
    have_duplications <- ct\$num_cells > 1
    normal_vals <- apply(exprs(ct), 2, function(smp) all(smp <= 28))
    cleaned_ct <- ct[, have_duplications & normal_vals]
    
    # 3. Normalize data using housekeeper genes
    housekeepers <- c('Actb', 'Gapdh')
    normalizations <- colMeans(exprs(cleaned_ct)[housekeepers, ])
    guo_norm <- cleaned_ct
    exprs(guo_norm) <- exprs(guo_norm) - normalizations
    
    # 4. Calculate Limit of Detection (LoD) from dilution series
    dilutions <- read_xls('mmc6.xls', 1L)
    dilutions\$Cell <- NULL
    get_lod <- function(gene) gene[[max(which(gene != 28))]]
    lods <- apply(dilutions, 2, get_lod)
    lod <- ceiling(median(lods))
    lod_norm <- ceiling(median(lods) - mean(normalizations))
    max_cycles_norm <- ceiling(40 - mean(normalizations))
    
    guo <- guo_norm
    exprs(guo)[exprs(cleaned_ct) >= 28] <- lod_norm
    
    # 5. Create DiffusionMap with censoring model
    thresh_dm <- DiffusionMap(guo, censor_val = lod_norm, censor_range = c(lod_norm, max_cycles_norm), verbose = FALSE)
    
    # 6. Calculate Diffusion Pseudo Time (DPT)
    dpt <- DPT(thresh_dm)
    
    # 7. Plot diffusion maps and DPT branching paths to PDF
    pdf("destiny_plots.pdf", width = 10, height = 8)
    plot(thresh_dm, 1:2, col_by = 'num_cells', legend_main = 'Cell stage')
    plot(dpt)
    plot(dpt, root = 2, paths_to = c(1, 3), col_by = 'branch')
    plot(dpt, col_by = 'branch', divide = 3, dcs = c(-1, -3, 2), pch = 20)
    dev.off()
    
    # Save RDS objects for downstream analysis
    saveRDS(thresh_dm, "thresh_dm.rds")
    saveRDS(dpt, "dpt.rds")
    
    # Save meaningful results as CSV tables
    write.csv(as.data.frame(eigenvectors(thresh_dm)), "diffusion_components.csv", row.names = TRUE)
    
    dpt_df <- data.frame(
      Cell = colnames(guo),
      Branch = as.vector(dpt\$branch)
    )
    if (!is.null(dpt\$DPT1)) dpt_df\$DPT1 <- dpt\$DPT1
    if (!is.null(dpt\$DPT2)) dpt_df\$DPT2 <- dpt\$DPT2
    if (!is.null(dpt\$DPT3)) dpt_df\$DPT3 <- dpt\$DPT3
    write.csv(dpt_df, "dpt_results.csv", row.names = FALSE)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_DESTINY_QPCR_DIFFUSION_MAP_AND_DPT":
        destiny: \$(Rscript -e 'cat(as.character(packageVersion("destiny")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qpcr_diffusion_map_and_dpt.csv versions.yml
    """
}

workflow BIOC_DESTINY_QPCR_DIFFUSION_MAP_AND_DPT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mmc4.xls, mmc6.xls ] ]

    main:
    BIOC_DESTINY_QPCR_DIFFUSION_MAP_AND_DPT(ch_input)

    emit:
    tables   = BIOC_DESTINY_QPCR_DIFFUSION_MAP_AND_DPT.out.tables
    plots    = BIOC_DESTINY_QPCR_DIFFUSION_MAP_AND_DPT.out.plots
    objects  = BIOC_DESTINY_QPCR_DIFFUSION_MAP_AND_DPT.out.objects
    versions = BIOC_DESTINY_QPCR_DIFFUSION_MAP_AND_DPT.out.versions
}
