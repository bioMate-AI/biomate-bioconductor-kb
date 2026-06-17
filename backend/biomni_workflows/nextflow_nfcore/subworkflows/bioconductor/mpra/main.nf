#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mpra — tissue_comparison
// Perform differential activity analysis of regulatory elements between independent groups (e.g., tissues or cell types).
// Input: dna.txt, rna.txt, eid.txt, eseq.txt
// Container: quay.io/biocontainers/bioconductor-mpra:1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: limma, mpra
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create an MPRASet object using MPRASet()
//  * 2. [Input & Preparation] Define the design matrix
//  * 3. [Core Analysis] Fit the model using mpralm() with model_type = "indep_groups"
//  * 4. [Core Analysis] Extract top differential elements using topTable()
//  * 5. [Core Analysis] Optionally run mpralm() with endomorphic = TRUE to return results directly inside the MPRASet object

nextflow.enable.dsl = 2

process BIOC_MPRA_TISSUE_COMPARISON {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("mpra", "limma", "SummarizedExperiment")
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
        library(mpra)
        library(SummarizedExperiment)
        library(limma)
        
        # 1. Read User Input Files
        # Read DNA and RNA count matrices
        dna <- as.matrix(read.table("dna.txt", header = TRUE, row.names = 1, sep = ""))
        rna <- as.matrix(read.table("rna.txt", header = TRUE, row.names = 1, sep = ""))
        
        # Read element IDs
        eid_data <- read.table("eid.txt", header = FALSE, stringsAsFactors = FALSE)
        eid <- as.character(eid_data[[1]])
        
        # Read optional element sequences if file exists and is not empty
        if (file.exists("eseq.txt") && file.info("eseq.txt")\$size > 0) {
            eseq_data <- read.table("eseq.txt", header = FALSE, stringsAsFactors = FALSE)
            eseq <- as.character(eseq_data[[1]])
        } else {
            eseq <- NULL
        }
        
        # 2. Create MPRASet object
        mpraset_example <- MPRASet(DNA = dna, RNA = rna, eid = eid, eseq = eseq, barcode = NULL)
        mpraSetExample <- mpraset_example
        
        # 3. Define the design matrix
        # Infer conditions from column names by removing trailing numbers and punctuation
        cond <- gsub("[0-9]+\$", "", colnames(mpraSetExample))
        cond <- gsub("[_\\\\.]+\$", "", cond)
        
        # Ensure exactly two groups for the differential analysis to prevent out-of-bounds errors
        if (length(unique(cond)) != 2) {
            half <- floor(ncol(mpraSetExample) / 2)
            cond <- rep(c("Group1", "Group2"), c(half, ncol(mpraSetExample) - half))
        }
        condition <- factor(cond)
        
        design <- data.frame(intcpt = 1, condition2 = (condition == levels(condition)[2]))
        
        # 4. Fit the model using mpralm (with plot = TRUE, redirected to PDF)
        pdf("mpralm_plot.pdf")
        mpralm_fit <- mpralm(object = mpraSetExample, design = design, aggregate = "mean", normalize = TRUE, model_type = "indep_groups", plot = TRUE)
        dev.off()
        
        # 5. Extract top differential elements
        toptab <- topTable(mpralm_fit, coef = 2, number = Inf)
        toptab6 <- head(toptab)
        
        # 6. Run mpralm with endomorphic = TRUE
        efit <- mpralm(object = mpraSetExample, design = design, aggregate = "sum", normalize = TRUE, model_type = "indep_groups", plot = FALSE, endomorphic = TRUE, coef = 2)
        
        # Extract rowData and scaled assays
        efit_rowdata <- rowData(efit)
        sdna <- assay(efit, "scaledDNA")
        srna <- assay(efit, "scaledRNA")
        
        # 7. Save Outputs
        write.csv(toptab, "toptab_results.csv", row.names = TRUE)
        write.csv(as.data.frame(efit_rowdata), "efit_rowdata.csv", row.names = TRUE)
        write.csv(sdna, "scaled_dna.csv", row.names = TRUE)
        write.csv(srna, "scaled_rna.csv", row.names = TRUE)
        
        saveRDS(mpraset_example, "mpraset_example.rds")
        saveRDS(mpralm_fit, "mpralm_fit.rds")
        saveRDS(efit, "efit.rds")

    writeLines(c(
        '"BIOC_MPRA_TISSUE_COMPARISON":',
        paste0('    mpra: ', as.character(packageVersion('mpra')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tissue_comparison.csv versions.yml
    """
}

workflow BIOC_MPRA_TISSUE_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dna.txt, rna.txt, eid.txt, eseq.txt ] ]

    main:
    BIOC_MPRA_TISSUE_COMPARISON(ch_input)

    emit:
    tables   = BIOC_MPRA_TISSUE_COMPARISON.out.tables
    plots    = BIOC_MPRA_TISSUE_COMPARISON.out.plots
    objects  = BIOC_MPRA_TISSUE_COMPARISON.out.objects
    versions = BIOC_MPRA_TISSUE_COMPARISON.out.versions
}
