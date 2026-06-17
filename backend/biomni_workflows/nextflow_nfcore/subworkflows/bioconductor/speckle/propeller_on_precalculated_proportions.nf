#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: speckle — propeller_on_precalculated_proportions
// Run propeller analysis starting from a pre-calculated cell type proportions matrix (e.g., from deconvolution or other platforms).
// Input: pbmc.props, pbmc.sample.info, tot.cells
// Container: quay.io/biocontainers/bioconductor-speckle:1.10.0--r45hdfd78af_0
// R packages: limma, speckle
// Bioconductor: 3.20 | R: 4.4
// Requires: limma, speckle
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read the declared user input files
//  * 2. [Input & Preparation] Convert the proportions matrix into a
//  * 3. [Input & Preparation] Set up the design matrix with covariates dynamically
//  * 4. [Input & Preparation] Define contrasts and run propeller.ttest
//  * 5. [Input & Preparation] Write named output files for the meaningful results

nextflow.enable.dsl = 2

process BIOC_SPECKLE_PROPELLER_ON_PRECALCULATED_PROPORTIONS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("limma", "speckle")
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
        library(speckle)
        library(limma)
        
        # Helper function to robustly read user input files from the working directory
        read_input <- function(base_name) {
          # Check for RDS format first
          if (file.exists(paste0(base_name, ".rds"))) {
            return(readRDS(paste0(base_name, ".rds")))
          } else if (file.exists(base_name) && grepl("\\\\.rds\$", base_name, ignore.case = TRUE)) {
            return(readRDS(base_name))
          }
          
          # Check for CSV format
          if (file.exists(paste0(base_name, ".csv"))) {
            return(read.csv(paste0(base_name, ".csv"), row.names = 1, check.names = FALSE))
          } else if (file.exists(base_name) && grepl("\\\\.csv\$", base_name, ignore.case = TRUE)) {
            return(read.csv(base_name, row.names = 1, check.names = FALSE))
          }
          
          # Check for TSV or plain text format
          if (file.exists(paste0(base_name, ".tsv"))) {
            return(read.delim(paste0(base_name, ".tsv"), row.names = 1, check.names = FALSE))
          } else if (file.exists(paste0(base_name, ".txt"))) {
            return(read.table(paste0(base_name, ".txt"), header = TRUE, row.names = 1, check.names = FALSE))
          }
          
          # Fallback to reading the exact filename if it exists
          if (file.exists(base_name)) {
            res <- tryCatch({
              readRDS(base_name)
            }, error = function(e) {
              tryCatch({
                read.table(base_name, header = TRUE, row.names = 1, check.names = FALSE)
              }, error = function(e2) {
                # If it's a simple vector (like tot.cells)
                scan(base_name, quiet = TRUE)
              })
            })
            return(res)
          }
          
          stop(paste("Required input file not found in the working directory:", base_name))
        }
        
        # --- Read the declared user input files ---
        pbmc.props <- read_input("pbmc.props")
        pbmc.sample.info <- read_input("pbmc.sample.info")
        tot.cells <- read_input("tot.cells")
        
        # Ensure correct data types
        pbmc.props <- as.matrix(pbmc.props)
        pbmc.sample.info <- as.data.frame(pbmc.sample.info)
        if (is.list(tot.cells) || is.data.frame(tot.cells)) {
          tot.cells <- unlist(tot.cells)
        }
        tot.cells <- as.numeric(tot.cells)
        
        # --- Convert the proportions matrix into a ---
        # Dynamically handle scale.fac: if scalar, divide by number of samples; if vector, use directly
        scale_factor <- if (length(tot.cells) == 1) tot.cells / ncol(pbmc.props) else tot.cells
        prop.list <- convertDataToList(pbmc.props, data.type="proportions", transform="logit", scale.fac=scale_factor)
        
        # --- Set up the design matrix with covariates dynamically ---
        # Clean up column names to ensure valid variable names in the formula
        colnames(pbmc.sample.info) <- make.names(colnames(pbmc.sample.info))
        
        # Convert character columns to factors and ensure the first column is a factor
        pbmc.sample.info[] <- lapply(pbmc.sample.info, function(x) if(is.character(x)) as.factor(x) else x)
        pbmc.sample.info[[1]] <- as.factor(pbmc.sample.info[[1]])
        
        group_col <- colnames(pbmc.sample.info)[1]
        levels_group <- levels(pbmc.sample.info[[1]])
        
        if (length(levels_group) < 2) {
          stop("The primary group (first column of sample info) must have at least two levels.")
        }
        
        # Build the design matrix using all provided metadata columns
        designAS <- model.matrix(~ 0 + ., data = pbmc.sample.info)
        colnames(designAS) <- make.names(colnames(designAS))
        
        # --- Define contrasts and run propeller.ttest ---
        # Compare the second level to the first level of the primary group
        lvl1 <- make.names(paste0(group_col, levels_group[1]))
        lvl2 <- make.names(paste0(group_col, levels_group[2]))
        contr_str <- paste(lvl2, lvl1, sep="-")
        
        mycontr <- makeContrasts(contrasts = contr_str, levels=designAS)
        results <- propeller.ttest(prop.list = prop.list, design = designAS, contrasts = mycontr, robust=TRUE, trend=FALSE, sort=TRUE)
        
        # --- Write named output files for the meaningful results ---
        # Save the statistical results table
        write.csv(results, file = "propeller_ttest_results.csv", row.names = TRUE)
        
        # Save the converted prop.list object
        saveRDS(prop.list, file = "prop_list.rds")
        
        # Generate and save a barplot of the cell type proportions
        pdf("cell_type_proportions_barplot.pdf", width = 10, height = 6)
        par(mfrow = c(1, 1))
        # Replaced non-standard ggplotColors with base R rainbow palette
        barplot(as.matrix(pbmc.props), col = rainbow(nrow(pbmc.props)),
                ylab = "Cell type proportions", xlab = "Samples", las = 2)
        dev.off()

    writeLines(c(
        '"BIOC_SPECKLE_PROPELLER_ON_PRECALCULATED_PROPORTIONS":',
        paste0('    speckle: ', as.character(packageVersion('speckle')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_propeller_on_precalculated_proportions.csv versions.yml
    """
}

workflow BIOC_SPECKLE_PROPELLER_ON_PRECALCULATED_PROPORTIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pbmc.props, pbmc.sample.info, tot.cells ] ]

    main:
    BIOC_SPECKLE_PROPELLER_ON_PRECALCULATED_PROPORTIONS(ch_input)

    emit:
    tables   = BIOC_SPECKLE_PROPELLER_ON_PRECALCULATED_PROPORTIONS.out.tables
    plots    = BIOC_SPECKLE_PROPELLER_ON_PRECALCULATED_PROPORTIONS.out.plots
    objects  = BIOC_SPECKLE_PROPELLER_ON_PRECALCULATED_PROPORTIONS.out.objects
    versions = BIOC_SPECKLE_PROPELLER_ON_PRECALCULATED_PROPORTIONS.out.versions
}
