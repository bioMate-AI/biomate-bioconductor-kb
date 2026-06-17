#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PADOG — benchmark_gene_set_analysis
// Compare a custom gene set analysis method against PADOG using benchmark datasets.
// Input: custom_method_function, datasets
// Container: quay.io/biocontainers/bioconductor-padog:1.52.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, PADOG, doParallel
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define a custom method function that loads datasets, filters annotations using filteranot, and returns a formatted dataframe. 2. R

nextflow.enable.dsl = 2

process BIOC_PADOG_BENCHMARK_GENE_SET_ANALYSIS {
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
    .bm_deps <- c("PADOG", "Biobase", "doParallel")
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
        library(PADOG)
        library(Biobase)
        library(doParallel)
        
        # Set up parallel backend
        num_cores <- parallel::detectCores() - 1
        if (num_cores < 1) num_cores <- 1
        cl <- parallel::makeCluster(num_cores)
        registerDoParallel(cl)
        
        # Define getdataaslist exactly as documented in the vignette
        getdataaslist = function(x) {
            x = get(x)
            exp = experimentData(x)
            dataset = exp@name
            disease = notes(exp)\$disease
            dat.m = exprs(x)
            ano = pData(x)
            design = notes(exp)\$design
            annotation = paste(x@annotation, ".db", sep = "")
            targetGeneSets = notes(exp)\$targetGeneSets
            list = list(dataset, disease, dat.m, ano, design, annotation, targetGeneSets)
            names(list) = c("dataset", "disease", "dat.m", "ano", "design", "annotation", 
                "targetGeneSets")
            return(list)
        }
        
        # Read USER INPUT files from the working directory
        if (!file.exists("custom_method_function")) {
            stop("Required input file 'custom_method_function' is missing from the working directory.")
        }
        if (!file.exists("datasets")) {
            stop("Required input file 'datasets' is missing from the working directory.")
        }
        
        # Load the custom method function
        custom_method <- tryCatch({
            readRDS("custom_method_function")
        }, error = function(e) {
            # Fallback if stored as an R script
            temp_env <- new.env()
            source("custom_method_function", local = temp_env)
            funcs <- Filter(is.function, mget(ls(temp_env), envir = temp_env))
            if (length(funcs) > 0) {
                funcs[[1]]
            } else {
                stop("No valid R function found in 'custom_method_function'.")
            }
        })
        
        # Ensure the custom method can access getdataaslist
        environment(custom_method) <- globalenv()
        
        # Load the datasets vector
        mysets <- tryCatch({
            readRDS("datasets")
        }, error = function(e) {
            readLines("datasets")
        })
        
        # Run compPADOG to compare the custom method against PADOG
        # Capture diagnostic plots in a PDF file
        pdf("compPADOG_plots.pdf", width = 10, height = 8)
        
        out = compPADOG(
            datasets = mysets, 
            existingMethods = c("PADOG"),
            mymethods = list(myRand = custom_method), 
            gslist = "KEGGRESTpathway", 
            Nmin = 3, 
            NI = 40, 
            plots = TRUE, 
            verbose = FALSE, 
            parallel = TRUE, 
            dseed = 1, 
            pkgs = NULL
        )
        
        dev.off()
        
        # Save meaningful results to output files
        saveRDS(out, "compPADOG_results.rds")
        
        if (!is.null(out\$summary)) {
            write.csv(out\$summary, "compPADOG_summary.csv", row.names = TRUE)
        }
        
        if (!is.null(out\$ranks)) {
            ranks_df <- as.data.frame(out\$ranks)
            write.csv(ranks_df, "compPADOG_ranks.csv", row.names = TRUE)
        }
        
        if (!is.null(out\$pvalues)) {
            pvalues_df <- as.data.frame(out\$pvalues)
            write.csv(pvalues_df, "compPADOG_pvalues.csv", row.names = TRUE)
        }
        
        if (!is.null(out\$qvalues)) {
            qvalues_df <- as.data.frame(out\$qvalues)
            write.csv(qvalues_df, "compPADOG_qvalues.csv", row.names = TRUE)
        }
        
        # Clean up parallel cluster
        stopCluster(cl)

    writeLines(c(
        '"BIOC_PADOG_BENCHMARK_GENE_SET_ANALYSIS":',
        paste0('    PADOG: ', as.character(packageVersion('PADOG')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_benchmark_gene_set_analysis.csv versions.yml
    """
}

workflow BIOC_PADOG_BENCHMARK_GENE_SET_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ custom_method_function, datasets ] ]

    main:
    BIOC_PADOG_BENCHMARK_GENE_SET_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_PADOG_BENCHMARK_GENE_SET_ANALYSIS.out.tables
    plots    = BIOC_PADOG_BENCHMARK_GENE_SET_ANALYSIS.out.plots
    objects  = BIOC_PADOG_BENCHMARK_GENE_SET_ANALYSIS.out.objects
    versions = BIOC_PADOG_BENCHMARK_GENE_SET_ANALYSIS.out.versions
}
