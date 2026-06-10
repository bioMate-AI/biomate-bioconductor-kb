#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: apalyzer — apa_analysis_workflow
// Quantify and analyze differential alternative polyadenylation (APA) in 3'UTRs and introns from RNA-seq BAM files.
// Input: flsall, refUTRraw, dfIPA, dfLE
// Container: quay.io/biocontainers/bioconductor-apalyzer:1.20.0--r44hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_APALYZER_APA_ANALYSIS_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-apalyzer:1.20.0--r44hdfd78af_0"

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
    .bm_deps <- c("GenomicRanges", "apalyzer", "genomicfeatures", "ggplot2", "knitr", "rsamtools", "tbx20bamsubset")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(APAlyzer)
    library(Rsamtools)
    library(GenomicRanges)
    
    # Helper function to load inputs robustly
    load_input <- function(base_name) {
      rds_path <- paste0(base_name, ".rds")
      csv_path <- paste0(base_name, ".csv")
      if (file.exists(rds_path)) {
        return(readRDS(rds_path))
      } else if (file.exists(csv_path)) {
        return(read.csv(csv_path, stringsAsFactors = FALSE))
      } else {
        stop(paste("Required input file not found:", rds_path, "or", csv_path))
      }
    }
    
    # 1. Read User Inputs from the working directory
    if (file.exists("flsall.rds")) {
      flsall <- readRDS("flsall.rds")
    } else if (file.exists("flsall.csv")) {
      df_fls <- read.csv("flsall.csv", stringsAsFactors = FALSE)
      if (ncol(df_fls) >= 2) {
        flsall <- df_fls[[2]]
        names(flsall) <- df_fls[[1]]
      } else {
        flsall <- df_fls[[1]]
        names(flsall) <- rownames(df_fls)
      }
    } else {
      stop("flsall file not found (flsall.rds or flsall.csv)")
    }
    
    refUTRraw <- load_input("refUTRraw")
    dfIPA <- load_input("dfIPA")
    dfLE <- load_input("dfLE")
    
    # Prepare raw variables for REF4PAS
    dfIPAraw <- dfIPA
    dfLEraw <- dfLE
    
    # 2. Build PAS reference regions using REF4PAS
    PASREF=REF4PAS(refUTRraw,dfIPAraw,dfLEraw)
    UTRdbraw=PASREF\$UTRdbraw
    dfIPA=PASREF\$dfIPA
    dfLE=PASREF\$dfLE
    
    # 3. Build 3'UTR aUTR and cUTR references using REF3UTR
    UTRdbraw=REF3UTR(refUTRraw)
    
    # 4. Calculate relative expression of 3'UTR APA using PASEXP_3UTR
    DFUTRraw=PASEXP_3UTR(UTRdbraw, flsall, Strandtype="forward")
    
    # 5. Calculate relative expression of intronic PAS (IPA) using PASEXP_IPA
    IPA_OUTraw=PASEXP_IPA(dfIPA, dfLE, flsall, Strandtype="forward", nts=1)
    
    # 6. Set up sample tables dynamically based on flsall names
    if (all(c("SRR316184", "SRR316187") %in% names(flsall))) {
      sampleTable2 = data.frame(samplename = c("SRR316184","SRR316187"), condition = c("NT","KD"))
    } else {
      nt_sample <- names(flsall)[1]
      kd_sample <- names(flsall)[length(flsall)]
      sampleTable2 = data.frame(samplename = c(nt_sample, kd_sample), condition = c("NT","KD"))
    }
    
    if (length(flsall) == 6) {
      sampleTable1 = data.frame(samplename = c(names(flsall)), condition = c(rep("NT",3),rep("KD",3)))
    } else {
      n_samples <- length(flsall)
      half_n <- ceiling(n_samples / 2)
      conds <- c(rep("NT", half_n), rep("KD", n_samples - half_n))
      sampleTable1 = data.frame(samplename = c(names(flsall)), condition = conds)
    }
    
    # 7. Perform differential APA analysis using APAdiff
    test_3UTRsing=APAdiff(sampleTable2,DFUTRraw, 
                            conKET='NT',
                            trtKEY='KD',
                            PAS='3UTR',
                            CUTreads=0,
                            p_adjust_methods="fdr")
    
    test_3UTRmuti=APAdiff(sampleTable1,
                            DFUTRraw, 
                            conKET='NT',
                            trtKEY='KD',
                            PAS='3UTR',
                            CUTreads=0,
                            p_adjust_methods="fdr",
                            MultiTest='unpaired t-test')
    
    test_IPAsing=APAdiff(sampleTable2,
                            IPA_OUTraw, 
                            conKET='NT',
                            trtKEY='KD',
                            PAS='IPA',
                            CUTreads=0,
                            p_adjust_methods="fdr") 
    
    test_IPAmuti=APAdiff(sampleTable1,
                            IPA_OUTraw, 
                            conKET='NT',
                            trtKEY='KD',
                            PAS='IPA',
                            CUTreads=0,
                            p_adjust_methods="fdr",
                            MultiTest='unpaired t-test')
    
    # 8. Visualize results using APAVolcano and APABox
    pdf("APAVolcano_3UTRsing.pdf")
    APAVolcano(test_3UTRsing, PAS='3UTR', Pcol = "pvalue", top=5, main='3UTR APA')
    dev.off()
    
    pdf("APABox_3UTRsing.pdf")
    APABox(test_3UTRsing, xlab = "APAreg", ylab = "RED", plot_title = NULL)
    dev.off()
    
    # 9. Write named output files
    write.csv(DFUTRraw, "DFUTRraw.csv", row.names = FALSE)
    write.csv(IPA_OUTraw, "IPA_OUTraw.csv", row.names = FALSE)
    write.csv(test_3UTRsing, "test_3UTRsing.csv", row.names = FALSE)
    write.csv(test_3UTRmuti, "test_3UTRmuti.csv", row.names = FALSE)
    write.csv(test_IPAsing, "test_IPAsing.csv", row.names = FALSE)
    write.csv(test_IPAmuti, "test_IPAmuti.csv", row.names = FALSE)
    
    saveRDS(PASREF, "PASREF.rds")
    saveRDS(UTRdbraw, "UTRdbraw.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_APALYZER_APA_ANALYSIS_WORKFLOW":
        apalyzer: \$(Rscript -e 'cat(as.character(packageVersion("apalyzer")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_apa_analysis_workflow.csv versions.yml
    """
}

workflow BIOC_APALYZER_APA_ANALYSIS_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ flsall, refUTRraw, dfIPA, dfLE ] ]

    main:
    BIOC_APALYZER_APA_ANALYSIS_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_APALYZER_APA_ANALYSIS_WORKFLOW.out.tables
    plots    = BIOC_APALYZER_APA_ANALYSIS_WORKFLOW.out.plots
    objects  = BIOC_APALYZER_APA_ANALYSIS_WORKFLOW.out.objects
    versions = BIOC_APALYZER_APA_ANALYSIS_WORKFLOW.out.versions
}
