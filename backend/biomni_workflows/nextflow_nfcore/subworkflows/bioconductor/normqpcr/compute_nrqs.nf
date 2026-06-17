#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: normqpcr — compute_nrqs
// Compute normalized relative quantities (NRQs) taking amplification efficiencies and their standard errors into account.
// Input: qPCR.example.txt, Efficiencies.txt
// Container: quay.io/biocontainers/bioconductor-normqpcr:1.56.0--r45h575d39b_0
// R packages: NormqPCR, ReadqPCR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NORMQPCR_COMPUTE_NRQS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-normqpcr:1.56.0--r45h575d39b_0"

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
    .bm_deps <- c("NormqPCR", "ReadqPCR")
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
    library(ReadqPCR)
    library(NormqPCR)
    
    # --- Read raw qPCR data ---
    qPCR.example <- "qPCR.example.txt"
    if (!file.exists(qPCR.example)) {
      stop(paste("Required input file missing:", qPCR.example))
    }
    Cq.data <- read.qPCR(qPCR.example)
    
    # --- Combine technical replicates and compute standard ---
    Cq.data1 <- combineTechRepsWithSD(Cq.data)
    
    # --- Load and assign amplification efficiencies and their ---
    Effs <- "Efficiencies.txt"
    if (!file.exists(Effs)) {
      stop(paste("Required input file missing:", Effs))
    }
    Cq.effs <- read.table(file = Effs, row.names = 1, header = TRUE)
    rownames(Cq.effs) <- featureNames(Cq.data1)
    effs(Cq.data1) <- as.matrix(Cq.effs[,"efficiency",drop = FALSE])
    se.effs(Cq.data1) <- as.matrix(Cq.effs[,"SD.efficiency",drop = FALSE])
    
    # --- Compute NRQs using specified housekeeping genes ---
    res <- ComputeNRQs(Cq.data1, hkgs = c("gene_az", "gene_gx"))
    
    # Extract results
    nrqs <- exprs(res)
    se_nrqs <- se.exprs(res)
    
    # Write outputs to files
    write.csv(nrqs, file = "nrqs_exprs.csv", row.names = TRUE)
    write.csv(se_nrqs, file = "nrqs_se.csv", row.names = TRUE)
    saveRDS(res, file = "nrqs_results.rds")
    
    # Generate a visualization of the NRQs
    tryCatch({
      pdf("nrqs_heatmap.pdf", width = 8, height = 8)
      heatmap(nrqs, 
              main = "Normalized Relative Quantities (NRQs)", 
              Colv = NA, 
              Rowv = NA, 
              scale = "none", 
              margins = c(8, 8),
              col = heat.colors(256))
      dev.off()
    }, error = function(e) {
      warning("Could not generate PDF plot: ", e\$message)
    })

    writeLines(c(
        '"BIOC_NORMQPCR_COMPUTE_NRQS":',
        paste0('        normqpcr: ', as.character(packageVersion("normqpcr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_compute_nrqs.csv versions.yml
    """
}

workflow BIOC_NORMQPCR_COMPUTE_NRQS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ qPCR.example.txt, Efficiencies.txt ] ]

    main:
    BIOC_NORMQPCR_COMPUTE_NRQS(ch_input)

    emit:
    tables   = BIOC_NORMQPCR_COMPUTE_NRQS.out.tables
    plots    = BIOC_NORMQPCR_COMPUTE_NRQS.out.plots
    objects  = BIOC_NORMQPCR_COMPUTE_NRQS.out.objects
    versions = BIOC_NORMQPCR_COMPUTE_NRQS.out.versions
}
