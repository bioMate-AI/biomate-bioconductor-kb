#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: destiny — censored_and_missing_data
// Create a diffusion map incorporating censoring and missing value models to handle limit of detection and missing values in qPCR data.
// Input: raw_ct.xls, mmc6.xls
// Container: quay.io/biocontainers/bioconductor-destiny:3.24.0--r45ha27e39d_0
// R packages: Biobase, destiny, readxl
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, destiny, readxl
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Preprocess and normalize data
//  * 2. [Core Analysis] Determine Limit of Detection (LoD)
//  * 3. [Core Analysis] Set censored values
//  * 4. [Core Analysis] Run DiffusionMap with censoring and missing range parameters
//  * 5. [Visualization & Output] Plot the resulting map

nextflow.enable.dsl = 2

process BIOC_DESTINY_CENSORED_AND_MISSING_DATA {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("Biobase", "destiny", "readxl")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
        # Load required libraries
        library(readxl)
        library(destiny)
        library(Biobase)
        
        # 1. Preprocess and normalize data
        # Read the raw qPCR Ct values from the user-specified file
        raw_ct <- read_xls('raw_ct.xls')
        
        # Convert to ExpressionSet
        ct <- as.ExpressionSet(as.data.frame(raw_ct))
        
        # Extract the number of cells from the Cell annotation
        num_cells <- gsub('^(\\\\d+)C.*\$', '\\1', ct\$Cell)
        ct\$num_cells <- as.integer(num_cells)
        
        # Filter out single cells (keep 2+ cell embryos) and cells with all values <= 28
        have_duplications <- ct\$num_cells > 1
        normal_vals <- apply(exprs(ct), 2, function(smp) all(smp <= 28))
        cleaned_ct <- ct[, have_duplications & normal_vals]
        
        # Normalize using housekeeping genes
        housekeepers <- c('Actb', 'Gapdh')
        normalizations <- colMeans(exprs(cleaned_ct)[housekeepers, ])
        guo_norm <- cleaned_ct
        exprs(guo_norm) <- exprs(guo_norm) - normalizations
        
        # 2. Determine Limit of Detection (LoD)
        # Read the dilution series from the user-specified file
        dilutions <- read_xls('mmc6.xls', 1L)
        dilutions\$Cell <- NULL
        
        # Calculate gene-wise and global LoD
        get_lod <- function(gene) gene[[max(which(gene != 28))]]
        lods <- apply(dilutions, 2, get_lod)
        lod <- ceiling(median(lods))
        lod_norm <- ceiling(median(lods) - mean(normalizations))
        max_cycles_norm <- ceiling(40 - mean(normalizations))
        
        # 3. Set censored values
        guo <- guo_norm
        exprs(guo)[exprs(cleaned_ct) >= 28 ] <- lod_norm
        
        # 4. Run DiffusionMap with censoring parameters
        thresh_dm <- DiffusionMap(guo, censor_val = lod_norm, censor_range = c(lod_norm, max_cycles_norm), verbose = FALSE)
        
        # Save the first plot to PDF
        pdf("diffusion_map_censored.pdf", width = 7, height = 6)
        print(plot(thresh_dm, 1 : 2, col_by = 'num_cells', legend_main = 'Cell stage'))
        dev.off()
        
        # 5. Handle missing values and run DiffusionMap with missing range parameters
        ct_w_missing <- ct[, ct\$num_cells > 1L]
        exprs(ct_w_missing)[exprs(ct_w_missing) > 28] <- NA
        
        housekeep <- colMeans(exprs(ct_w_missing)[housekeepers, ], na.rm = TRUE)
        w_missing <- ct_w_missing
        exprs(w_missing) <- exprs(w_missing) - housekeep
        exprs(w_missing)[is.na(exprs(ct_w_missing))] <- lod_norm
        
        dif_w_missing <- DiffusionMap(w_missing, censor_val = lod_norm, censor_range = c(lod_norm, max_cycles_norm), missing_range = c(1, 40), verbose = FALSE)
        
        # Save the second plot to PDF
        pdf("diffusion_map_missing.pdf", width = 7, height = 6)
        print(plot(dif_w_missing, 1 : 2, col_by = 'num_cells', legend_main = 'Cell stage'))
        dev.off()
        
        # Save meaningful results to files
        saveRDS(thresh_dm, "thresh_dm.rds")
        saveRDS(dif_w_missing, "dif_w_missing.rds")
        
        # Export eigenvectors (diffusion components) to CSV
        write.csv(as.data.frame(eigenvectors(thresh_dm)), "thresh_dm_eigenvectors.csv", row.names = TRUE)
        write.csv(as.data.frame(eigenvectors(dif_w_missing)), "dif_w_missing_eigenvectors.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_DESTINY_CENSORED_AND_MISSING_DATA":',
        paste0('    destiny: ', as.character(packageVersion('destiny')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_censored_and_missing_data.csv versions.yml
    """
}

workflow BIOC_DESTINY_CENSORED_AND_MISSING_DATA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_ct.xls, mmc6.xls ] ]

    main:
    BIOC_DESTINY_CENSORED_AND_MISSING_DATA(ch_input)

    emit:
    tables   = BIOC_DESTINY_CENSORED_AND_MISSING_DATA.out.tables
    plots    = BIOC_DESTINY_CENSORED_AND_MISSING_DATA.out.plots
    objects  = BIOC_DESTINY_CENSORED_AND_MISSING_DATA.out.objects
    versions = BIOC_DESTINY_CENSORED_AND_MISSING_DATA.out.versions
}
