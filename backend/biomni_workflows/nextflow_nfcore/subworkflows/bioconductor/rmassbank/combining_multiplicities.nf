#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RMassBank — combining_multiplicities
// Combine peak multiplicities from standard and confirmation spectra to prevent erroneous deletion of edge peaks.
// Input: NarcoticsDataset.csv, *.mzML
// Container: quay.io/biocontainers/bioconductor-rmassbank:3.20.0--r45ha27e39d_0
// R packages: RMassBank
// Bioconductor: 3.20 | R: 4.4
// Requires: RMassBank
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Configure settings and load compound list
//  * 2. [Input & Preparation] Initialize workspace and load files
//  * 3. [Core Analysis] Process standard spectra (steps 1-7) using msmsWorkflow
//  * 4. [Core Analysis] Process confirmation spectra (steps 1-7 with confirmMode = 1) using msmsWorkflow
//  * 5. [Core Analysis] Combine workspaces using combineMultiplicities
//  * 6. [Core Analysis] Apply multiplicity filtering (step 8) using msmsWorkflow

nextflow.enable.dsl = 2

process BIOC_RMASSBANK_COMBINING_MULTIPLICITIES {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20-deps"

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
    .bm_deps <- c("RMassBank")
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
        
        # Load required library
        library(RMassBank)
        
        # 1. Configure settings and load compound list
        RmbDefaultSettings()
        getOption("RMassBank")\$multiplicityFilter
        rmbo <- getOption("RMassBank")
        rmbo\$spectraList <- list(
            list(mode="CID", ces = "35%", ce = "35 % (nominal)", res = 7500),
            list(mode="HCD", ces = "15%", ce = "15 % (nominal)", res = 7500),
            list(mode="HCD", ces = "30%", ce = "30 % (nominal)", res = 7500)
        )
        options(RMassBank = rmbo)
        
        # Load the compound list from the working directory
        loadList("NarcoticsDataset.csv")
        
        # 2. Initialize workspace and load files
        w <- newMsmsWorkspace()
        
        # Retrieve raw LC-MS/MS data files from the working directory
        files <- list.files(".", "\\\\.mzML\$", full.names = TRUE)
        if (length(files) < 2) {
            stop("Error: At least two .mzML files are required in the working directory for this workflow.")
        }
        w@files <- files
        
        # 3. Process standard spectra (steps 1-7) using msmsWorkflow
        w1 <- msmsWorkflow(w, mode="pH", steps=c(1))
        w1 <- msmsWorkflow(w1, mode="pH", steps=c(2:7))
        
        # 4. Process confirmation spectra (steps 1-7 with confirmMode = 1) using msmsWorkflow
        w2 <- msmsWorkflow(w, mode="pH", steps=c(1), confirmMode = 1)
        w2 <- msmsWorkflow(w2, mode="pH", steps=c(2:7))
        
        # 5. Combine workspaces using combineMultiplicities
        wTotal <- combineMultiplicities(c(w1, w2))
        
        # 6. Apply multiplicity filtering (step 8) using msmsWorkflow
        wTotal <- msmsWorkflow(wTotal, steps=8, mode="pH", archivename = "output")
        
        # Initialize MbWorkspace
        mb <- newMbWorkspace(wTotal)
        
        # Save meaningful results to the working directory
        saveRDS(wTotal, "wTotal.rds")
        saveRDS(mb, "mb_workspace.rds")
        
        # Generate recalibration plot if recalibration data is available
        tryCatch({
            pdf("recalibration_plot.pdf")
            plotRecalibration(wTotal)
            dev.off()
        }, error = function(e) {
            message("Recalibration plot could not be generated: ", e\$message)
        })

    writeLines(c(
        '"BIOC_RMASSBANK_COMBINING_MULTIPLICITIES":',
        paste0('    RMassBank: ', as.character(packageVersion('RMassBank')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_combining_multiplicities.csv versions.yml
    """
}

workflow BIOC_RMASSBANK_COMBINING_MULTIPLICITIES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ NarcoticsDataset.csv, *.mzML ] ]

    main:
    BIOC_RMASSBANK_COMBINING_MULTIPLICITIES(ch_input)

    emit:
    tables   = BIOC_RMASSBANK_COMBINING_MULTIPLICITIES.out.tables
    plots    = BIOC_RMASSBANK_COMBINING_MULTIPLICITIES.out.plots
    objects  = BIOC_RMASSBANK_COMBINING_MULTIPLICITIES.out.objects
    versions = BIOC_RMASSBANK_COMBINING_MULTIPLICITIES.out.versions
}
