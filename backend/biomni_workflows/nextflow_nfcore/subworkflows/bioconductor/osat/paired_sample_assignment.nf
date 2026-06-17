#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: OSAT — paired_sample_assignment
// Assign paired samples (e.g., pre- and post-treatment specimens from the same individual) to the same chip to eliminate chip-level batch effects on treatment dif
// Input: samples.txt
// Container: quay.io/biocontainers/bioconductor-osat:1.58.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: OSAT
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load sample metadata
//  * 2. [Input & Preparation] Define sample setup with primary and confounding variables
//  * 3. [Input & Preparation] Define custom mock chip and plate layouts to represent pairs
//  * 4. [Input & Preparation] Define container setup using the mock plate
//  * 5. [Core Analysis] Assign pairs to mock chip rows using "optimal.block"
//  * 6. [Core Analysis] Expand mock layout to real 2-column BeadChip layout
//  * 7. [Core Analysis] Shuffle specimens within chips to avoid location bias
//  * 8. [Visualization & Output] Perform quality control visualization and statistical testing

nextflow.enable.dsl = 2

process BIOC_OSAT_PAIRED_SAMPLE_ASSIGNMENT {
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
    .bm_deps <- c("OSAT")
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
    library(OSAT)
    
    # 1. Load sample metadata from the working directory
    pheno <- read.table("samples.txt", header=TRUE, sep="\t", colClasses="factor")
    
    # 2. Define sample setup with primary and confounding variables
    gs <- setup.sample(pheno, optimal=c("SampleType", "Race", "AgeGrp"),
               strata=c("SampleType"))
    
    # 3. Define custom mock chip and plate layouts to represent pairs
    newChip <- new("BeadChip",  nRows=6, nColumns=1, byrow=FALSE, 
       comment="mock chip")
    newPlate <- new("BeadPlate", chip=newChip,
       nRows=2L, nColumns=4L, 
       comment="mock plate")
    
    # 4. Define container setup using the mock plate
    gcNew <- setup.container(newPlate, 12, batch="plates")
    
    # 5. Assign pairs to mock chip rows using "optimal.block"
    set.seed(12345)
    gPaired <- create.optimized.setup("optimal.block", sample=gs, 
               container=gcNew, nSim=1000)
    
    # Save the optimized setup object
    saveRDS(gPaired, "gPaired.rds")
    
    # 6. Expand mock layout to real 2-column BeadChip layout
    set.seed(456)
    out1 <- get.experiment.setup(gPaired)
    out1\$Replica <- FALSE
    idx <- sample(nrow(out1), ceiling(nrow(out1)/2), replace=FALSE)
    out1[idx, "Replica"] <- TRUE
    out2 <- out1
    out2\$columns <- 2
    out2\$wells <- out2\$wells+6
    out2\$Replica <- !out1\$Replica
    out3 <- rbind(out1, out2)
    idx1 <- with(out3, order(plates, chips,  rows, columns, wells))
    out3 <- out3[idx1,]
    
    # Save the expanded layout
    write.csv(out3, "paired_setup_expanded.csv", row.names=FALSE)
    
    # 7. Shuffle specimens within chips to avoid location bias
    set.seed(789)
    idx2 <- with(out3, order(plates, chips, runif(nrow(out3))))
    out4 <- cbind(out3[, 1:8], out3[idx2, 9:11], Replica=out3[, 12])
    idx3 <- with(out4, order(plates,  chips, wells))
    out4 <- out4[idx3,]
    
    # Save the final shuffled layout
    write.csv(out4, "paired_setup_shuffled.csv", row.names=FALSE)
    
    # 8. Perform quality control visualization and statistical testing
    pdf("paired_sample_barplot.pdf", width=11, height=8.5)
    multi.barplot(out3, grpVar='plates', varList=c("SampleType", "Replica", 
                  "Race", "AgeGrp"), main="paired sample")
    dev.off()
    
    chisq_results <- multi.chisq.test(out3, grpVar='plates', varList=c("SampleType", "Replica", 
                  "Race", "AgeGrp"))
    
    # Save statistical test results to a text file
    sink("chisq_test_results.txt")
    print(chisq_results)
    sink()

    writeLines(c(
        '"BIOC_OSAT_PAIRED_SAMPLE_ASSIGNMENT":',
        paste0('    OSAT: ', as.character(packageVersion('OSAT')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_paired_sample_assignment.csv versions.yml
    """
}

workflow BIOC_OSAT_PAIRED_SAMPLE_ASSIGNMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ samples.txt ] ]

    main:
    BIOC_OSAT_PAIRED_SAMPLE_ASSIGNMENT(ch_input)

    emit:
    tables   = BIOC_OSAT_PAIRED_SAMPLE_ASSIGNMENT.out.tables
    plots    = BIOC_OSAT_PAIRED_SAMPLE_ASSIGNMENT.out.plots
    objects  = BIOC_OSAT_PAIRED_SAMPLE_ASSIGNMENT.out.objects
    versions = BIOC_OSAT_PAIRED_SAMPLE_ASSIGNMENT.out.versions
}
