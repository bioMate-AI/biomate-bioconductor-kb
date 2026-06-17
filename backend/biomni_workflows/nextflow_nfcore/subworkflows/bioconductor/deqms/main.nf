#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DEqMS — protein_table_tmt
// Perform differential protein expression analysis using a pre-summarized protein abundance table (e.g., TMT data).
// Input: miR_Proteintable.txt
// Container: quay.io/biocontainers/bioconductor-deqms:1.28.0--r45hdfd78af_0
// R packages: DEqMS, ExperimentHub, ggrepel, limma, LSD, matrixStats
// Bioconductor: 3.20 | R: 4.4
// Requires: DEqMS, limma, matrixStats
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read and filter protein table
//  * 2. [Core Analysis] Log2 transform and check normalization
//  * 3. [Input & Preparation] Define design matrix and contrasts
//  * 4. [Core Analysis] Fit linear model using Limma (lmFit, contrasts.fit, eBayes)
//  * 5. [Core Analysis] Assign PSM count to the fit object
//  * 6. [Core Analysis] Run DEqMS variance estimation (spectraCounteBayes)
//  * 7. [Visualization & Output] Visualize variance dependence (VarianceBoxplot, VarianceScatterplot)
//  * 8. [Visualization & Output] Extract results (outputResult)

nextflow.enable.dsl = 2

process BIOC_DEQMS_PROTEIN_TABLE_TMT {
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
    .bm_deps <- c("DEqMS", "ExperimentHub", "ggrepel", "limma", "LSD", "matrixStats")
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
    library(DEqMS)
    library(matrixStats)
    library(limma)
    
    # 1. Read and filter protein table
    df.prot = read.table("miR_Proteintable.txt", stringsAsFactors = FALSE,
                         header = TRUE, quote = "", comment.char = "", sep = "\t")
    TMT_columns = seq(15, 33, 2)
    dat = df.prot[df.prot\$miR.FASP_q.value < 0.01, TMT_columns]
    rownames(dat) = df.prot[df.prot\$miR.FASP_q.value < 0.01, ]\$Protein.accession
    
    # 2. Log2 transform and check normalization
    dat.log = log2(dat)
    dat.log = na.omit(dat.log)
    
    # 3. Define design matrix and contrasts
    cond = as.factor(c("ctrl", "miR191", "miR372", "miR519", "ctrl",
                       "miR372", "miR519", "ctrl", "miR191", "miR372"))
    design = model.matrix(~0+cond)
    colnames(design) = gsub("cond", "", colnames(design))
    x <- c("miR372-ctrl", "miR519-ctrl", "miR191-ctrl",
           "miR372-miR519", "miR372-miR191", "miR519-miR191")
    contrast = makeContrasts(contrasts=x, levels=design)
    
    # 4. Fit linear model using Limma
    fit1 <- lmFit(dat.log, design)
    fit2 <- contrasts.fit(fit1, contrasts = contrast)
    fit3 <- eBayes(fit2)
    
    # 5. Assign PSM count to the fit object
    count_columns = seq(16, 34, 2)
    psm.count.table = data.frame(count = rowMins(
      as.matrix(df.prot[, count_columns])), row.names = df.prot\$Protein.accession)
    fit3\$count = psm.count.table[rownames(fit3\$coefficients), "count"]
    
    # 6. Run DEqMS variance estimation
    fit4 = spectraCounteBayes(fit3)
    
    # 7. Visualize variance dependence
    pdf("DEqMS_variance_plots.pdf", width = 12, height = 6)
    par(mfrow = c(1, 2))
    VarianceBoxplot(fit4, n = 30, main = "TMT10plex dataset PXD004163", xlab = "PSM count")
    VarianceScatterplot(fit4, main = "TMT10plex dataset PXD004163")
    dev.off()
    
    # 8. Extract results and save
    DEqMS.results = outputResult(fit4, coef_col = 1)
    write.table(DEqMS.results, "DEqMS.results.miR372-ctrl.txt", sep = "\t",
                row.names = FALSE, quote = FALSE)
    
    # Save RDS objects for downstream analysis
    saveRDS(fit4, "DEqMS_fit4.rds")
    saveRDS(DEqMS.results, "DEqMS_results.rds")

    writeLines(c(
        '"BIOC_DEQMS_PROTEIN_TABLE_TMT":',
        paste0('    DEqMS: ', as.character(packageVersion('DEqMS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_protein_table_tmt.csv versions.yml
    """
}

workflow BIOC_DEQMS_PROTEIN_TABLE_TMT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ miR_Proteintable.txt ] ]

    main:
    BIOC_DEQMS_PROTEIN_TABLE_TMT(ch_input)

    emit:
    tables   = BIOC_DEQMS_PROTEIN_TABLE_TMT.out.tables
    plots    = BIOC_DEQMS_PROTEIN_TABLE_TMT.out.plots
    objects  = BIOC_DEQMS_PROTEIN_TABLE_TMT.out.objects
    versions = BIOC_DEQMS_PROTEIN_TABLE_TMT.out.versions
}
