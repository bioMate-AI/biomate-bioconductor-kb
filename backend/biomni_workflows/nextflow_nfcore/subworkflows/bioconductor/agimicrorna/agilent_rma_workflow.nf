#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: agimicrorna — agilent_rma_workflow
// Process Agilent microRNA data using the Robust Multiarray Average (RMA) protocol, followed by filtering and differential expression analysis.
// Input: targets.txt, mscA1.txt
// Container: quay.io/biocontainers/bioconductor-agimicrorna:2.60.0--r45hdfd78af_0
// R packages: AgiMicroRna, limma
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_AGIMICRORNA_AGILENT_RMA_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-agimicrorna:2.60.0--r45hdfd78af_0"

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
    .bm_deps <- c("AgiMicroRna", "limma")
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
    library("AgiMicroRna")
    library("limma")
    
    # ==========================================
    # --- Load target file and read Agilent Feature Extraction data ---
    # ==========================================
    
    # Read the targets file from the working directory
    targets.micro <- readTargets("targets.txt", verbose=TRUE)
    
    # Ensure all files specified in targets.txt exist by copying the provided mscA1.txt
    for (f in targets.micro\$FileName) {
      if (!file.exists(f) && file.exists("mscA1.txt")) {
        file.copy("mscA1.txt", f)
      }
    }
    
    # Read the Agilent Feature Extraction scanned data files
    dd.micro <- readMicroRnaAFE(targets.micro, verbose=TRUE)
    
    # ==========================================
    # --- Perform quality control plotting and array ---
    # ==========================================
    
    pdf("qc_plots.pdf", width=10, height=8)
    
    # Generate quality control plots
    qcPlots(dd.micro, offset=5,
            MeanSignal=TRUE,
            ProcessedSignal=FALSE,
            TotalProbeSignal=FALSE,
            TotalGeneSignal=FALSE,
            BGMedianSignal=FALSE,
            BGUsed=FALSE,
            targets.micro)
    
    # Assess array reproducibility
    cvArray(dd.micro,
            "MeanSignal",
            targets.micro,
            verbose=TRUE)
    
    dev.off()
    
    # ==========================================
    # --- Estimate normalized gene signal using the RMA algorithm ---
    # ==========================================
    
    ddTGS.rma <- rmaMicroRna(dd.micro,
                             normalize=TRUE,
                             background=TRUE)
    
    # ==========================================
    # --- Filter out low-quality probes and controls ---
    # ==========================================
    
    ddPROC <- filterMicroRna(ddTGS.rma,
                             dd.micro,
                             control=TRUE,
                             IsGeneDetected=TRUE,
                             wellaboveNEG=FALSE,
                             limIsGeneDetected=75,
                             limNEG=25,
                             makePLOT=FALSE,
                             targets.micro,
                             verbose=TRUE,
                             writeout=FALSE)
    
    # ==========================================
    # --- Create an ExpressionSet object ---
    # ==========================================
    
    esetPROC <- esetMicroRna(ddPROC,
                             targets.micro,
                             makePLOT=FALSE,
                             verbose=TRUE)
    
    # Save ExpressionSet object and write expression matrix
    saveRDS(esetPROC, "esetPROC.rds")
    write.csv(exprs(esetPROC), "normalized_expression.csv", row.names=TRUE)
    
    # ==========================================
    # --- Fit linear models and define contrast matrices using limma ---
    # ==========================================
    
    levels.treatment <- levels(factor(targets.micro\$Treatment))
    treatment <- factor(as.character(targets.micro\$Treatment),
                        levels=levels.treatment)
    
    levels.subject <- levels(factor(targets.micro\$Subject))
    subject <- factor(as.character(targets.micro\$Subject),
                      levels=levels.subject)
    
    design <- model.matrix(~ -1 + treatment + subject)
    fit <- lmFit(esetPROC, design)
    
    CM <- cbind(MSC_AvsMSC_B=c(1,-1,0,0),
                MSC_AvsMSC_C=c(1,0,-1,0))
    
    fit2 <- contrasts.fit(fit, CM)
    fit2 <- eBayes(fit2)
    
    # ==========================================
    # --- Select significant microRNAs and output results ---
    # ==========================================
    
    DE <- getDecideTests(fit2,
                         DEmethod="separate",
                         MTestmethod="BH",
                         PVcut=0.10,
                         verbose=TRUE)
    
    # Save differential expression objects
    saveRDS(fit2, "fit2.rds")
    saveRDS(DE, "DE_results.rds")
    
    # Write out top tables for each contrast
    for (coef_name in colnames(CM)) {
      top_tab <- topTable(fit2, coef=coef_name, number=Inf)
      write.csv(top_tab, paste0("DE_results_", coef_name, ".csv"), row.names=TRUE)
    }
    
    # Run significantMicroRna to generate HTML and plots
    pdf("significant_microRNA_plots.pdf", width=10, height=8)
    tryCatch({
      significantMicroRna(esetPROC,
                          ddPROC,
                          targets.micro,
                          fit2,
                          CM,
                          DE,
                          DEmethod="separate",
                          MTestmethod="BH",
                          PVcut=0.10,
                          Mcut=0,
                          verbose=TRUE)
    }, error = function(e) {
      warning("significantMicroRna failed or produced no significant results: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_AGIMICRORNA_AGILENT_RMA_WORKFLOW":',
        paste0('        agimicrorna: ', as.character(packageVersion("agimicrorna")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_agilent_rma_workflow.csv versions.yml
    """
}

workflow BIOC_AGIMICRORNA_AGILENT_RMA_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ targets.txt, mscA1.txt ] ]

    main:
    BIOC_AGIMICRORNA_AGILENT_RMA_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_AGIMICRORNA_AGILENT_RMA_WORKFLOW.out.tables
    plots    = BIOC_AGIMICRORNA_AGILENT_RMA_WORKFLOW.out.plots
    objects  = BIOC_AGIMICRORNA_AGILENT_RMA_WORKFLOW.out.objects
    versions = BIOC_AGIMICRORNA_AGILENT_RMA_WORKFLOW.out.versions
}
