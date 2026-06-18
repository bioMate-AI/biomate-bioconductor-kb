#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MesKit — metastatic_routes_and_neutrality
// Infer metastatic seeding patterns (monoclonal vs. polyclonal) and evaluate neutral evolution.
// Input: maf, driverGene
// Container: quay.io/biocontainers/bioconductor-meskit:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MesKit, RColorBrewer, ggplot2
// Visualizations: smooth scatter, scatter plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read User Input Files
//  * 2. [Core Analysis] Execute Documented Workflow Steps

nextflow.enable.dsl = 2

process BIOC_MESKIT_METASTATIC_ROUTES_AND_NEUTRALITY {
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
    .bm_deps <- c("MesKit", "RColorBrewer", "ggplot2")
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
    library(MesKit)
    library(graphics)
    library(RColorBrewer)
    library(ggplot2)
    
    # --- Read User Input Files ---
    if (file.exists("maf.rds")) {
      maf <- readRDS("maf.rds")
    } else {
      stop("Error: 'maf.rds' not found in the working directory.")
    }
    
    if (file.exists("driverGene.rds")) {
      driverGene <- readRDS("driverGene.rds")
    } else if (file.exists("driverGene.txt")) {
      driverGene <- readLines("driverGene.txt")
    } else {
      stop("Error: 'driverGene.rds' or 'driverGene.txt' not found in the working directory.")
    }
    
    # --- Execute Documented Workflow Steps ---
    
    # Step 2.1: Pairwise CCF comparison of mutations between sample pairs
    ccf.list <- compareCCF(maf, pairByTumor = TRUE, min.ccf = 0.02,
                           use.adjVAF = TRUE, use.indel = FALSE)
    
    # Dynamically extract the first patient and their first tumor pair
    patient_id <- names(ccf.list)[1]
    patient_ccf <- ccf.list[[patient_id]]
    pair_name <- names(patient_ccf)[1]
    ccf_pair <- patient_ccf[[pair_name]]
    
    # Step 2.2: Calculate the Jaccard similarity index (JSI)
    # (Calculated here to dynamically use the JSI value in the plot title)
    JSI.res <- calJSI(maf, patient.id = patient_id, pairByTumor = TRUE, min.ccf = 0.02, 
                      use.adjVAF = TRUE, use.indel = FALSE, use.tumorSampleLabel = TRUE)
    
    jsi_val <- JSI.res\$JSI.multi
    if (is.list(jsi_val)) {
      jsi_val <- jsi_val[[1]]
    } else {
      jsi_val <- jsi_val[1]
    }
    
    # Visualize via smoothScatter and save to PDF
    pdf("ccf_comparison_smoothscatter.pdf", width = 6, height = 6)
    graphics::smoothScatter(matrix(c(ccf_pair[, 3], ccf_pair[, 4]), ncol = 2),
                    xlim = c(0, 1), ylim = c(0, 1),
                    colramp = colorRampPalette(c("white", RColorBrewer::brewer.pal(9, "BuPu"))),
                    xlab = colnames(ccf_pair)[3], ylab = colnames(ccf_pair)[4])
      
    ## show driver genes
    gene.idx <- which(ccf_pair\$Hugo_Symbol %in% driverGene) 
    if (length(gene.idx) > 0) {
      points(ccf_pair[gene.idx, 3:4], cex = 0.6, col = 2, pch = 2)
      text(ccf_pair[gene.idx, 3:4], cex = 0.7, pos = 1,
           ccf_pair\$Hugo_Symbol[gene.idx])
    }
    title(paste0(patient_id, " JSI = ", round(jsi_val, 3)), cex.main = 1.5)
    dev.off()
    
    # Save JSI results
    write.csv(data.frame(JSI_multi = JSI.res\$JSI.multi), "jsi_multi.csv", row.names = FALSE)
    write.csv(as.data.frame(JSI.res\$JSI.pair), "jsi_pair.csv", row.names = TRUE)
    
    # Step 2.3: Test whether tumor subclonal mutant allele frequencies follow neutral evolution
    neutralResult <- testNeutral(maf, min.mut.count = 10, patient.id = patient_id, use.tumorSampleLabel = TRUE)
    
    # Save neutrality metrics
    write.csv(as.data.frame(neutralResult\$neutrality.metrics), "neutrality_metrics.csv", row.names = FALSE)
    
    # Save model fitting plot dynamically for the first available sample
    plot_names <- names(neutralResult\$model.fitting.plot)
    if (length(plot_names) > 0 && !is.null(neutralResult\$model.fitting.plot[[plot_names[1]]])) {
      ggplot2::ggsave("neutral_model_fitting_P_1.pdf", plot = neutralResult\$model.fitting.plot[[plot_names[1]]], width = 6, height = 6)
    }

    writeLines(c(
        '"BIOC_MESKIT_METASTATIC_ROUTES_AND_NEUTRALITY":',
        paste0('    MesKit: ', as.character(packageVersion('MesKit')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metastatic_routes_and_neutrality.csv versions.yml
    """
}

workflow BIOC_MESKIT_METASTATIC_ROUTES_AND_NEUTRALITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ maf, driverGene ] ]

    main:
    BIOC_MESKIT_METASTATIC_ROUTES_AND_NEUTRALITY(ch_input)

    emit:
    tables   = BIOC_MESKIT_METASTATIC_ROUTES_AND_NEUTRALITY.out.tables
    plots    = BIOC_MESKIT_METASTATIC_ROUTES_AND_NEUTRALITY.out.plots
    objects  = BIOC_MESKIT_METASTATIC_ROUTES_AND_NEUTRALITY.out.objects
    versions = BIOC_MESKIT_METASTATIC_ROUTES_AND_NEUTRALITY.out.versions
}
