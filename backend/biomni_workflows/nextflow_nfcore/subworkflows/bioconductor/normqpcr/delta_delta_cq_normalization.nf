#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: normqpcr — delta_delta_cq_normalization
// Normalize qPCR data and calculate relative gene expression between two groups using the 2^-ddCq method with single or multiple housekeeping genes.
// Input: example.txt
// Container: quay.io/biocontainers/bioconductor-normqpcr:1.56.0--r45h575d39b_0
// R packages: NormqPCR, ReadqPCR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NORMQPCR_DELTA_DELTA_CQ_NORMALIZATION {
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
    
    # Load required libraries
    library(ReadqPCR)
    library(NormqPCR)
    
    # 1. Read raw qPCR data
    taqman.example <- "example.txt"
    if (!file.exists(taqman.example)) {
      stop("Required input file 'example.txt' not found in the working directory.")
    }
    qPCRBatch.taqman <- read.taqman(taqman.example)
    
    # 2. Construct contrast matrix to define case and control groups
    contM <- cbind(c(0,0,1,1,0,0,1,1), c(1,1,0,0,1,1,0,0))
    colnames(contM) <- c("interestingPhenotype", "wildTypePhenotype")
    rownames(contM) <- sampleNames(qPCRBatch.taqman)
    
    # 3. Perform delta-delta Cq normalization using single or multiple housekeeping genes
    
    # Case A: Single housekeeping gene (paired)
    hkg <- "Actb-Rn00667869_m1"
    ddCq.taqman <- deltaDeltaCq(qPCRBatch = qPCRBatch.taqman, maxNACase=1, maxNAControl=1, 
                                hkg=hkg, contrastM=contM, case="interestingPhenotype", 
                                control="wildTypePhenotype", statCalc="geom", hkgCalc="arith")
    
    # Case B: Single housekeeping gene (unpaired)
    ddCqAvg.taqman <- deltaDeltaCq(qPCRBatch = qPCRBatch.taqman, maxNACase=1, maxNAControl=1, 
                                   hkg=hkg, contrastM=contM, case="interestingPhenotype", 
                                   control="wildTypePhenotype", paired=FALSE, statCalc="geom", 
                                   hkgCalc="arith")
    
    # Case C: Multiple housekeeping genes
    hkgs <- c("Actb-Rn00667869_m1", "B2m-Rn00560865_m1", "Gapdh-Rn99999916_s1")
    ddCq.gM.taqman <- deltaDeltaCq(qPCRBatch = qPCRBatch.taqman, maxNACase=1, maxNAControl=1, 
                                   hkgs=hkgs, contrastM=contM, case="interestingPhenotype", 
                                   control="wildTypePhenotype", statCalc="arith", hkgCalc="arith")
    
    # 4. Write outputs
    write.csv(ddCq.taqman, "ddCq_single_paired.csv", row.names = FALSE)
    write.csv(ddCqAvg.taqman, "ddCq_single_unpaired.csv", row.names = FALSE)
    write.csv(ddCq.gM.taqman, "ddCq_multiple.csv", row.names = FALSE)
    
    saveRDS(ddCq.taqman, "ddCq_single_paired.rds")
    saveRDS(ddCqAvg.taqman, "ddCq_single_unpaired.rds")
    saveRDS(ddCq.gM.taqman, "ddCq_multiple.rds")
    
    # Generate a PDF plot of relative expression for the first 10 genes
    pdf("relative_expression_plot.pdf", width = 10, height = 6)
    plot_data <- ddCq.gM.taqman[1:10, ]
    vals <- plot_data[["2^-ddCt"]]
    vals[is.na(vals)] <- 0
    barplot(vals, names.arg = plot_data\$ID, las = 2, 
            main = "Relative Expression (2^-ddCt) - Top 10 Genes (Multiple HKGs)",
            ylab = "Relative Expression", col = "skyblue", cex.names = 0.8)
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_NORMQPCR_DELTA_DELTA_CQ_NORMALIZATION":
        normqpcr: \$(Rscript -e 'cat(as.character(packageVersion("normqpcr")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_delta_delta_cq_normalization.csv versions.yml
    """
}

workflow BIOC_NORMQPCR_DELTA_DELTA_CQ_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ example.txt ] ]

    main:
    BIOC_NORMQPCR_DELTA_DELTA_CQ_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_NORMQPCR_DELTA_DELTA_CQ_NORMALIZATION.out.tables
    plots    = BIOC_NORMQPCR_DELTA_DELTA_CQ_NORMALIZATION.out.plots
    objects  = BIOC_NORMQPCR_DELTA_DELTA_CQ_NORMALIZATION.out.objects
    versions = BIOC_NORMQPCR_DELTA_DELTA_CQ_NORMALIZATION.out.versions
}
