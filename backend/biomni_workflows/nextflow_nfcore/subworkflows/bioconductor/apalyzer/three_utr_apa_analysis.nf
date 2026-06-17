#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: APAlyzer — three_utr_apa_analysis
// Analyze alternative polyadenylation (APA) in 3'UTRs to identify lengthening or shortening events between conditions.
// Input: flsall, mm9_REF.RData
// Container: quay.io/biocontainers/bioconductor-apalyzer:1.20.0--r44hdfd78af_0
// R packages: APAlyzer
// Bioconductor: 3.20 | R: 4.4
// Requires: APAlyzer
// Visualizations: volcano plot, box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load or build the PAS reference regions
//  * 2. [Input & Preparation] Define the aUTR and cUTR genomic ranges using REF3UTR
//  * 3. [Core Analysis] Calculate relative expression of 3'UTR APA using PASEXP_3UTR
//  * 4. [Core Analysis] Perform differential APA analysis between groups using APAdiff
//  * 5. [Visualization & Output] Visualize results using APAVolcano and APABox

nextflow.enable.dsl = 2

process BIOC_APALYZER_THREE_UTR_APA_ANALYSIS {
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
    .bm_deps <- c("APAlyzer")
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
        library(APAlyzer)
        
        # 1. Load the PAS reference regions from the user-provided mm9_REF.RData
        if (!file.exists("mm9_REF.RData")) {
          stop("Error: mm9_REF.RData not found in the working directory.")
        }
        load("mm9_REF.RData")
        
        # 2. Identify BAM files in the working directory to construct flsall
        bam_files <- list.files(path = ".", pattern = "\\\\.bam\$", full.names = TRUE)
        if (length(bam_files) < 2) {
          stop("Error: At least 2 BAM files are required in the working directory.")
        }
        flsall <- bam_files
        names(flsall) <- gsub("\\\\.bam\$", "", basename(bam_files))
        
        # Define the aUTR and cUTR genomic ranges
        UTRdbraw=REF3UTR(refUTRraw)
        
        # 3. Calculate relative expression of 3'UTR APA
        DFUTRraw=PASEXP_3UTR(UTRdbraw, flsall, Strandtype="forward")
        
        # Save relative expression results
        write.csv(DFUTRraw, "DFUTRraw_expression.csv", row.names = FALSE)
        
        # 4. Perform differential APA analysis between groups
        # Construct sampleTable2 dynamically using all detected BAM names
        n_samples <- length(flsall)
        n_NT <- floor(n_samples / 2)
        n_KD <- n_samples - n_NT
        
        sampleTable2 = data.frame(samplename = names(flsall),
                            condition = c(rep("NT", n_NT), rep("KD", n_KD))) 
        
        test_3UTRsing=APAdiff(sampleTable2,DFUTRraw, 
                                conKET='NT',
                                trtKEY='KD',
                                PAS='3UTR',
                                CUTreads=0,
                                p_adjust_methods="fdr")
        
        # Save differential analysis results
        write.csv(test_3UTRsing, "test_3UTRsing_diff_APA.csv", row.names = FALSE)
        saveRDS(test_3UTRsing, "test_3UTRsing.rds")
        
        # 5. Visualize results
        pdf("APA_Volcano_Plot.pdf", width = 8, height = 8)
        APAVolcano(test_3UTRsing, PAS='3UTR', Pcol = "pvalue", top=5, main='3UTR APA')
        dev.off()
        
        pdf("APA_Box_Plot.pdf", width = 6, height = 6)
        APABox(test_3UTRsing, xlab = "APAreg", ylab = "RED", plot_title = NULL)
        dev.off()

    writeLines(c(
        '"BIOC_APALYZER_THREE_UTR_APA_ANALYSIS":',
        paste0('    APAlyzer: ', as.character(packageVersion('APAlyzer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_three_utr_apa_analysis.csv versions.yml
    """
}

workflow BIOC_APALYZER_THREE_UTR_APA_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ flsall, mm9_REF.RData ] ]

    main:
    BIOC_APALYZER_THREE_UTR_APA_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_APALYZER_THREE_UTR_APA_ANALYSIS.out.tables
    plots    = BIOC_APALYZER_THREE_UTR_APA_ANALYSIS.out.plots
    objects  = BIOC_APALYZER_THREE_UTR_APA_ANALYSIS.out.objects
    versions = BIOC_APALYZER_THREE_UTR_APA_ANALYSIS.out.versions
}
