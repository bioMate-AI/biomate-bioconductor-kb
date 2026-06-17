#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SAIGEgds — saige_association_analysis
// Perform single-variant association testing using generalized linear mixed models (GLMM) with SPA, including GRM preparation, null model fitting, and p-value cal
// Input: geno_fn.gds, pheno
// Container: quay.io/biocontainers/bioconductor-saigegds:2.10.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SAIGEgds, SNPRelate, SeqArray, ggmanh, ggplot2
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Open GDS file and perform LD pruning using SNPRelate::snpgdsLDpruning
//  * 2. [Visualization & Output] Filter variants and export to a new GDS file for GRM using SeqArray::seqSetFilter and SeqArray::seqExport
//  * 3. [Core Analysis] Fit the null GLMM model using SAIGEgds::seqFitNullGLMM_SPA
//  * 4. [Core Analysis] Calculate association p-values using SAIGEgds::seqAssocGLMM_SPA
//  * 5. [Input & Preparation] Load and inspect results using SAIGEgds::seqSAIGE_LoadPval

nextflow.enable.dsl = 2

process BIOC_SAIGEGDS_SAIGE_ASSOCIATION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("SeqArray", "SAIGEgds", "SNPRelate", "ggmanh", "ggplot2")
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
        library(SeqArray)
        library(SAIGEgds)
        library(SNPRelate)
        
        # Define input file paths
        geno_fn <- "geno_fn.gds"
        
        # Check if genotype file exists
        if (!file.exists(geno_fn)) {
          stop(paste("Error: Genotype file", geno_fn, "not found in the working directory."))
        }
        
        # Read phenotype data frame from the working directory
        # Supports 'pheno' (no extension), 'pheno.csv', or 'pheno.rds'
        pheno_path <- NULL
        possible_paths <- c("pheno", "pheno.csv", "pheno.rds")
        for (path in possible_paths) {
          if (file.exists(path)) {
            pheno_path <- path
            break
          }
        }
        
        if (is.null(pheno_path)) {
          stop("Error: Phenotype file ('pheno', 'pheno.csv', or 'pheno.rds') not found in the working directory.")
        }
        
        message("Reading phenotype data from: ", pheno_path)
        pheno <- tryCatch({
          if (grepl("\\\\.rds\$", pheno_path, ignore.case = TRUE)) {
            readRDS(pheno_path)
          } else {
            # Try reading as CSV, fallback to table
            tryCatch(
              read.csv(pheno_path, stringsAsFactors = FALSE),
              error = function(e) read.table(pheno_path, header = TRUE, stringsAsFactors = FALSE)
            )
          }
        }, error = function(e) {
          stop("Error reading phenotype file: ", e\$message)
        })
        
        # Ensure required columns exist in pheno
        if (!"sample.id" %in% colnames(pheno)) {
          stop("Error: Phenotype data frame is missing required column: sample.id")
        }
        
        pheno_cols <- setdiff(colnames(pheno), "sample.id")
        if (length(pheno_cols) == 0) {
          stop("Error: Phenotype data frame must contain at least one phenotype column.")
        }
        
        y_col <- pheno_cols[1]
        covar_cols <- pheno_cols[-1]
        
        if (length(covar_cols) > 0) {
          form <- as.formula(paste(y_col, "~", paste(covar_cols, collapse = " + ")))
        } else {
          form <- as.formula(paste(y_col, "~ 1"))
        }
        
        # Determine trait type
        if (length(na.omit(unique(pheno[[y_col]]))) == 2) {
          trait_type <- "binary"
        } else {
          trait_type <- "quantitative"
        }
        
        # 1. Open GDS file and perform LD pruning
        message("Opening GDS file and performing LD pruning...")
        gds <- seqOpen(geno_fn)
        set.seed(1000)
        snpset <- snpgdsLDpruning(gds)
        snpset.id <- unlist(snpset, use.names=FALSE)
        
        # 2. Filter variants and export to a new GDS file for GRM
        message("Filtering variants and exporting to GRM GDS file...")
        grm_fn <- "grm_geno.gds"
        seqSetFilter(gds, variant.id=snpset.id)
        seqExport(gds, grm_fn, info.var=character(), fmt.var=character(), samp.var=character())
        seqClose(gds)
        
        # 3. Fit the null GLMM model
        message("Fitting the null GLMM model...")
        glmm <- seqFitNullGLMM_SPA(form, pheno, grm_fn, trait.type=trait_type, sample.col="sample.id")
        
        # Save the fitted null model object
        saveRDS(glmm, "null_glmm_model.rds")
        
        # 4. Calculate association p-values
        message("Calculating association p-values...")
        assoc <- seqAssocGLMM_SPA(geno_fn, glmm, mac=10, parallel=2, res.savefn="assoc.gds")
        
        # 5. Load and inspect results
        message("Loading association results from GDS...")
        res <- seqSAIGE_LoadPval("assoc.gds")
        
        # Write the final association results to a CSV file
        write.csv(res, "association_results.csv", row.names = FALSE)
        message("Association results saved to 'association_results.csv'")
        
        # Generate Manhattan and QQ plots if ggmanh and ggplot2 are available
        pdf("association_plots.pdf", width = 8, height = 6)
        tryCatch({
          library(ggmanh)
          library(ggplot2)
          
          message("Generating Manhattan and QQ plots...")
          g <- manhattan_plot(assoc, pval.colname="pval", chr.colname="chr", 
                              pos.colname="pos", x.label="Chromosome")
          print(g)
          
          qqunif(assoc\$pval)
          message("Plots saved to 'association_plots.pdf'")
        }, error = function(e) {
          warning("Visualization failed or ggmanh/ggplot2 packages not available: ", e\$message)
          # Fallback to base R QQ-plot
          if (exists("assoc") && "pval" %in% colnames(assoc)) {
            pvals <- sort(na.omit(assoc\$pval))
            expected <- -log10(ppoints(length(pvals)))
            observed <- -log10(pvals)
            plot(expected, observed, main = "Q-Q Plot of P-values",
                 xlab = "Expected -log10(P)", ylab = "Observed -log10(P)",
                 pch = 19, col = "blue")
            abline(0, 1, col = "red")
          }
        })
        dev.off()
        
        message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_SAIGEGDS_SAIGE_ASSOCIATION_ANALYSIS":',
        paste0('    SAIGEgds: ', as.character(packageVersion('SAIGEgds')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_saige_association_analysis.csv versions.yml
    """
}

workflow BIOC_SAIGEGDS_SAIGE_ASSOCIATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ geno_fn.gds, pheno ] ]

    main:
    BIOC_SAIGEGDS_SAIGE_ASSOCIATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SAIGEGDS_SAIGE_ASSOCIATION_ANALYSIS.out.tables
    plots    = BIOC_SAIGEGDS_SAIGE_ASSOCIATION_ANALYSIS.out.plots
    objects  = BIOC_SAIGEGDS_SAIGE_ASSOCIATION_ANALYSIS.out.objects
    versions = BIOC_SAIGEGDS_SAIGE_ASSOCIATION_ANALYSIS.out.versions
}
