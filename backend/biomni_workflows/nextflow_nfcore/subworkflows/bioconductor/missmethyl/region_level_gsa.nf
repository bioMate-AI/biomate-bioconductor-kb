#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: missMethyl — region_level_gsa
// Perform gene set enrichment analysis on differentially methylated regions (DMRs) while correcting for probe-number bias.
// Input: M, design
// Container: quay.io/biocontainers/bioconductor-missmethyl:1.44.0--r45hdfd78af_0
// R packages: DMRcate, limma, missMethyl
// Bioconductor: 3.20 | R: 4.4
// Requires: DMRcate, limma, missMethyl
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read User Input Files from Working Directory
//  * 2. [Core Analysis] Annotate CpGs and find DMRs using DMRcate
//  * 3. [Core Analysis] Extract genomic ranges of DMRs
//  * 4. [Core Analysis] Perform region-level gene set testing using goregion and
//  * 5. [Core Analysis] Write named output files

nextflow.enable.dsl = 2

process BIOC_MISSMETHYL_REGION_LEVEL_GSA {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("DMRcate", "limma", "missMethyl")
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
        
        library(missMethyl)
        library(DMRcate)
        library(limma)
        
        # --- Read User Input Files from Working Directory ---
        if (file.exists("M.rds")) {
          M <- readRDS("M.rds")
        } else if (file.exists("M.csv")) {
          M <- as.matrix(read.csv("M.csv", row.names = 1))
        } else {
          stop("Error: M matrix file (M.rds or M.csv) not found in the working directory.")
        }
        
        if (file.exists("design.rds")) {
          design <- readRDS("design.rds")
        } else if (file.exists("design.csv")) {
          design <- as.matrix(read.csv("design.csv", row.names = 1))
        } else {
          stop("Error: design matrix file (design.rds or design.csv) not found in the working directory.")
        }
        
        # Load Hallmark collection for gsaregion
        if (file.exists("hallmark.rds")) {
          hallmark <- readRDS("hallmark.rds")
        } else {
          hallmark <- readRDS(url("http://bioinf.wehi.edu.au/MSigDB/v7.1/Hs.h.all.v7.1.entrez.rds"))
        }
        
        # --- Annotate CpGs and find DMRs using DMRcate ---
        myAnnotation <- cpg.annotate(object = M, datatype = "array", what = "M", arraytype = c("450K"), analysis.type = "differential", design = design, coef = ncol(design))
        DMRs <- dmrcate(myAnnotation, lambda=1000, C=2)
        
        # --- Extract genomic ranges of DMRs ---
        results.ranges <- extractRanges(DMRs)
        
        # --- Perform region-level gene set testing using goregion and ---
        # Capture the bias plot in a PDF
        pdf("region_plot_bias.pdf")
        gst.region <- goregion(results.ranges, all.cpg=rownames(M), collection="GO", array.type="450K", plot.bias=TRUE)
        dev.off()
        
        gst.region.kegg <- goregion(results.ranges, all.cpg=rownames(M), collection="KEGG", array.type="450K")
        gsa.region <- gsaregion(results.ranges, all.cpg=rownames(M), collection=hallmark)
        
        # --- Write named output files ---
        write.csv(gst.region, "gst_region_go.csv", row.names = TRUE)
        write.csv(gst.region.kegg, "gst_region_kegg.csv", row.names = TRUE)
        write.csv(gsa.region, "gsa_region_hallmark.csv", row.names = TRUE)
        
        saveRDS(results.ranges, "results_ranges.rds")
        saveRDS(gst.region, "gst_region_go.rds")
        saveRDS(gst.region.kegg, "gst_region_kegg.rds")
        saveRDS(gsa.region, "gsa_region_hallmark.rds")

    writeLines(c(
        '"BIOC_MISSMETHYL_REGION_LEVEL_GSA":',
        paste0('    missMethyl: ', as.character(packageVersion('missMethyl')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_region_level_gsa.csv versions.yml
    """
}

workflow BIOC_MISSMETHYL_REGION_LEVEL_GSA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ M, design ] ]

    main:
    BIOC_MISSMETHYL_REGION_LEVEL_GSA(ch_input)

    emit:
    tables   = BIOC_MISSMETHYL_REGION_LEVEL_GSA.out.tables
    plots    = BIOC_MISSMETHYL_REGION_LEVEL_GSA.out.plots
    objects  = BIOC_MISSMETHYL_REGION_LEVEL_GSA.out.objects
    versions = BIOC_MISSMETHYL_REGION_LEVEL_GSA.out.versions
}
