#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: AgiMicroRna — agilent_microrna_rma_workflow
// Process Agilent microRNA data using the Robust Multiarray Average (RMA) protocol, followed by filtering and differential expression analysis with limma.
// Input: targets.txt, Scanned Agilent image data files
// Container: quay.io/biocontainers/bioconductor-agimicrorna:2.60.0--r45hdfd78af_0
// R packages: AgiMicroRna, limma
// Bioconductor: 3.20 | R: 4.4
// Requires: AgiMicroRna, limma
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load targets file
//  * 2. [Input & Preparation] Read scanned AFE data
//  * 3. [Visualization & Output] Perform RMA background correction, normalization, and summarization
//  * 4. [Core Analysis] Filter out low-quality probes and controls
//  * 5. [Input & Preparation] Create ExpressionSet object
//  * 6. [Input & Preparation] Define experimental design and fit linear models
//  * 7. [Visualization & Output] Select significant microRNAs and generate reports

nextflow.enable.dsl = 2

process BIOC_AGIMICRORNA_AGILENT_MICRORNA_RMA_WORKFLOW {
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
    .bm_deps <- c("AgiMicroRna", "limma")
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
        
        # Load required Bioconductor packages
        library(AgiMicroRna)
        library(limma)
        
        # 1. Load targets file
        # The targets.txt file must be tab-delimited and contain columns: FileName, Treatment, GErep, Subject
        targets.micro = readTargets(infile = "targets.txt", verbose = TRUE)
        
        # 2. Read scanned Agilent Feature Extraction (AFE) data files
        dd.micro = readMicroRnaAFE(targets.micro, verbose = TRUE)
        
        # 3. Perform RMA background correction, normalization, and summarization
        ddTGS.rma = rmaMicroRna(dd.micro,
                               normalize = TRUE,
                               background = TRUE)
        
        # 4. Filter out low-quality probes and controls
        ddPROC = filterMicroRna(ddTGS.rma,
                                dd.micro,
                                control = TRUE,
                                IsGeneDetected = TRUE,
                                wellaboveNEG = FALSE,
                                limIsGeneDetected = 75,
                                limNEG = 25,
                                makePLOT = FALSE,
                                targets.micro,
                                verbose = TRUE,
                                writeout = FALSE)
        
        # 5. Create ExpressionSet object
        esetPROC = esetMicroRna(ddPROC,
                                targets.micro,
                                makePLOT = FALSE,
                                verbose = TRUE)
        
        # 6. Define experimental design and fit linear models
        levels.treatment = levels(factor(targets.micro\$Treatment))
        treatment = factor(as.character(targets.micro\$Treatment),
                           levels = levels.treatment)
        
        levels.subject = levels(factor(targets.micro\$Subject))
        subject = factor(as.character(targets.micro\$Subject),
                         levels = levels.subject)
        
        design = model.matrix(~ -1 + treatment + subject)
        
        fit = lmFit(esetPROC, design)
        
        # Define contrast matrix dynamically (comparing first treatment level vs all others)
        CM = matrix(0, nrow = ncol(design), ncol = length(levels.treatment) - 1)
        rownames(CM) = colnames(design)
        colnames(CM) = paste(levels.treatment[1], "vs", levels.treatment[-1], sep = "_")
        
        for (i in seq_along(levels.treatment[-1])) {
            CM[paste0("treatment", levels.treatment[1]), i] = 1
            CM[paste0("treatment", levels.treatment[i + 1]), i] = -1
        }
        
        fit2 = contrasts.fit(fit, CM)
        fit2 = eBayes(fit2)
        
        # 7. Select significant microRNAs and generate reports
        DE = getDecideTests(fit2,
                            DEmethod = "separate",
                            MTestmethod = "BH",
                            PVcut = 0.10,
                            verbose = TRUE)
        
        significantMicroRna(esetPROC,
                            ddPROC,
                            targets.micro,
                            fit2,
                            CM,
                            DE,
                            DEmethod = "separate",
                            MTestmethod = "BH",
                            PVcut = 0.10,
                            Mcut = 0,
                            verbose = TRUE)
        
        # Save meaningful output files
        saveRDS(esetPROC, file = "esetPROC.rds")
        write.csv(exprs(esetPROC), file = "normalized_filtered_expression.csv", row.names = TRUE)
        saveRDS(fit2, file = "limma_fit2.rds")
        saveRDS(DE, file = "decide_tests_results.rds")
        
        # Write out design and contrast matrices for reference
        write.csv(design, file = "design_matrix.csv", row.names = TRUE)
        write.csv(CM, file = "contrast_matrix.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_AGIMICRORNA_AGILENT_MICRORNA_RMA_WORKFLOW":',
        paste0('    AgiMicroRna: ', as.character(packageVersion('AgiMicroRna')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_agilent_microrna_rma_workflow.csv versions.yml
    """
}

workflow BIOC_AGIMICRORNA_AGILENT_MICRORNA_RMA_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ targets.txt, Scanned Agilent image data files ] ]

    main:
    BIOC_AGIMICRORNA_AGILENT_MICRORNA_RMA_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_AGIMICRORNA_AGILENT_MICRORNA_RMA_WORKFLOW.out.tables
    plots    = BIOC_AGIMICRORNA_AGILENT_MICRORNA_RMA_WORKFLOW.out.plots
    objects  = BIOC_AGIMICRORNA_AGILENT_MICRORNA_RMA_WORKFLOW.out.objects
    versions = BIOC_AGIMICRORNA_AGILENT_MICRORNA_RMA_WORKFLOW.out.versions
}
