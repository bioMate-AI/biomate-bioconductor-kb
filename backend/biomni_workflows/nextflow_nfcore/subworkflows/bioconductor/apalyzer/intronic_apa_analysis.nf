#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: APAlyzer — intronic_apa_analysis
// Analyze intronic polyadenylation (IPA) events to identify intronic PAS usage changes between conditions.
// Input: flsall, mm9_REF.RData
// Container: quay.io/biocontainers/bioconductor-apalyzer:1.20.0--r44hdfd78af_0
// Requires: APAlyzer
// Visualizations: volcano plot, box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load or build the PAS reference regions
//  * 2. [Core Analysis] Calculate relative expression of IPA using PASEXP_IPA
//  * 3. [Core Analysis] Perform differential IPA analysis between groups using APAdiff

nextflow.enable.dsl = 2

process BIOC_APALYZER_INTRONIC_APA_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
        
        # Load required libraries
        library(APAlyzer)
        
        # 1. Load the PAS reference regions from the local working directory
        if (!file.exists("mm9_REF.RData")) {
          stop("Error: mm9_REF.RData not found in the working directory.")
        }
        load("mm9_REF.RData")
        
        # 2. Identify RNA-seq BAM files in the working directory to construct flsall
        bam_files <- list.files(pattern = "\\\\.bam\$")
        if (length(bam_files) < 2) {
          stop("Error: At least 2 BAM files are required in the working directory.")
        }
        flsall <- normalizePath(bam_files)
        names(flsall) <- gsub("\\\\.bam\$", "", bam_files)
        
        # 3. Calculate relative expression of IPA using PASEXP_IPA
        IPA_OUTraw=PASEXP_IPA(dfIPA, dfLE, flsall, Strandtype="forward", nts=1)
        
        # Save raw IPA expression results
        write.csv(IPA_OUTraw, "IPA_OUTraw.csv", row.names=FALSE)
        saveRDS(IPA_OUTraw, "IPA_OUTraw.rds")
        
        # 4. Perform differential IPA analysis between groups using APAdiff
        # Dynamically construct sampleTable2 using the detected BAM files to ensure compatibility
        n_samples <- length(flsall)
        n_NT <- floor(n_samples / 2)
        n_KD <- n_samples - n_NT
        sampleTable2 = data.frame(samplename = names(flsall),
                                  condition = c(rep("NT", n_NT), rep("KD", n_KD))) 
        
        test_IPAsing=APAdiff(sampleTable2,
                                IPA_OUTraw, 
                                conKET='NT',
                                trtKEY='KD',
                                PAS='IPA',
                                CUTreads=0,
                                p_adjust_methods="fdr")
        
        # Save differential analysis results
        write.csv(test_IPAsing, "test_IPAsing.csv", row.names=FALSE)
        saveRDS(test_IPAsing, "test_IPAsing.rds")
        
        # 5. Generate and save visualization plots
        pdf("IPA_volcano_plot.pdf")
        tryCatch({
          APAVolcano(test_IPAsing, PAS='IPA', Pcol = "pvalue", plot_title='IPA')
        }, error = function(e) {
          warning("Could not generate Volcano plot: ", e\$message)
        })
        dev.off()
        
        pdf("IPA_box_plot.pdf")
        tryCatch({
          APABox(test_IPAsing, xlab = "APAreg", ylab = "RED", plot_title = NULL)
        }, error = function(e) {
          warning("Could not generate Box plot: ", e\$message)
        })
        dev.off()

    writeLines(c(
        '"BIOC_APALYZER_INTRONIC_APA_ANALYSIS":',
        paste0('    APAlyzer: ', as.character(packageVersion('APAlyzer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_intronic_apa_analysis.csv versions.yml
    """
}

workflow BIOC_APALYZER_INTRONIC_APA_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ flsall, mm9_REF.RData ] ]

    main:
    BIOC_APALYZER_INTRONIC_APA_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_APALYZER_INTRONIC_APA_ANALYSIS.out.tables
    plots    = BIOC_APALYZER_INTRONIC_APA_ANALYSIS.out.plots
    objects  = BIOC_APALYZER_INTRONIC_APA_ANALYSIS.out.objects
    versions = BIOC_APALYZER_INTRONIC_APA_ANALYSIS.out.versions
}
