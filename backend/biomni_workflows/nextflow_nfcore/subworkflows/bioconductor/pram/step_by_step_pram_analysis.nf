#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pram — step_by_step_pram_analysis
// Run the individual steps of the PRAM workflow to define intergenic ranges, extract alignments, build models, select models, and evaluate them.
// Input: in_gtf, finbam, fmdl, ftgt
// Container: quay.io/biocontainers/bioconductor-pram:1.26.0--r45hdfd78af_0
// R packages: GenomicRanges, data.table, pram
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, data.table, pram
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define intergenic genomic ranges using defIgRanges(). 2. Extract intergenic RNA-seq alignments using prepIgBam(). 3. Build transcr

nextflow.enable.dsl = 2

process BIOC_PRAM_STEP_BY_STEP_PRAM_ANALYSIS {
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
    .bm_deps <- c("GenomicRanges", "data.table", "pram")
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
        library(pram)
        library(GenomicRanges)
        library(data.table)
        
        # Define input file paths from the working directory
        in_gtf  <- "in_gtf"
        finbam  <- "finbam"
        fmdl    <- "fmdl"
        ftgt    <- "ftgt"
        
        # Fallback to common extensions if exact names do not exist in the working directory
        if (!file.exists(in_gtf) && file.exists("in.gtf")) in_gtf <- "in.gtf"
        if (!file.exists(finbam) && file.exists("finbam.bam")) finbam <- "finbam.bam"
        if (!file.exists(fmdl) && file.exists("fmdl.tsv")) fmdl <- "fmdl.tsv"
        if (!file.exists(fmdl) && file.exists("fmdl.gtf")) fmdl <- "fmdl.gtf"
        if (!file.exists(ftgt) && file.exists("ftgt.tsv")) ftgt <- "ftgt.tsv"
        if (!file.exists(ftgt) && file.exists("ftgt.gtf")) ftgt <- "ftgt.gtf"
        
        # Verify that required input files exist
        if (!file.exists(in_gtf)) stop("Required input file missing: ", in_gtf)
        if (!file.exists(finbam)) stop("Required input file missing: ", finbam)
        if (!file.exists(fmdl)) stop("Required input file missing: ", fmdl)
        if (!file.exists(ftgt)) stop("Required input file missing: ", ftgt)
        
        # ==========================================
        # Step 1: Define intergenic genomic ranges
        # ==========================================
        message("Step 1: Defining intergenic genomic ranges...")
        iggrs <- pram::defIgRanges(in_gtf, genome = 'hg38')
        
        # Save the defined intergenic ranges
        saveRDS(iggrs, "intergenic_ranges.rds")
        message("Intergenic ranges saved to 'intergenic_ranges.rds'")
        
        
        # ==========================================
        # Step 2: Extract intergenic RNA-seq alignments
        # ==========================================
        message("Step 2: Extracting intergenic RNA-seq alignments...")
        foutbam <- "intergenic_alignments.bam"
        
        pram::prepIgBam(finbam, iggrs, foutbam)
        message("Extracted alignments saved to '", foutbam, "'")
        
        
        # ==========================================
        # Step 3: Build transcript models
        # ==========================================
        message("Step 3: Building transcript models...")
        fbams <- c(foutbam)
        foutgtf <- "predicted_models.gtf"
        
        # Wrap in tryCatch to handle potential issues during model building
        tryCatch({
          pram::buildModel(fbams, foutgtf, method='plst')
          message("Transcript models successfully built and saved to '", foutgtf, "'")
        }, error = function(e) {
          warning("Failed to build model: ", e\$message)
        })
        
        
        # ==========================================
        # Step 4: Select transcript models
        # ==========================================
        message("Step 4: Selecting transcript models...")
        
        if (!file.exists(foutgtf)) {
          stop("Model building failed: output GTF '", foutgtf, "' not found.")
        }
        fin_gtf <- foutgtf
        fout_gtf <- "selected_models.gtf"
        
        tryCatch({
          pram::selModel(fin_gtf, fout_gtf)
          message("Selected transcript models saved to '", fout_gtf, "'")
        }, error = function(e) {
          warning("Model selection step failed: ", e\$message)
        })
        
        
        # ==========================================
        # Step 5: Evaluate transcript models
        # ==========================================
        message("Step 5: Evaluating transcript models...")
        
        if (grepl("\\\\.gtf\$", fmdl, ignore.case = TRUE)) {
          mdldt <- fmdl
        } else {
          mdldt <- data.table::fread(fmdl, header=TRUE, sep="\t")
        }
        
        if (grepl("\\\\.gtf\$", ftgt, ignore.case = TRUE)) {
          tgtdt <- ftgt
        } else {
          tgtdt <- data.table::fread(ftgt, header=TRUE, sep="\t")
        }
        
        eval_res <- pram::evalModel(mdldt, tgtdt)
        
        # Save evaluation results
        write.csv(eval_res, "evaluation_results.csv", row.names = FALSE)
        print(eval_res)
        message("Evaluation results successfully saved to 'evaluation_results.csv'")

    writeLines(c(
        '"BIOC_PRAM_STEP_BY_STEP_PRAM_ANALYSIS":',
        paste0('    pram: ', as.character(packageVersion('pram')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_step_by_step_pram_analysis.csv versions.yml
    """
}

workflow BIOC_PRAM_STEP_BY_STEP_PRAM_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ in_gtf, finbam, fmdl, ftgt ] ]

    main:
    BIOC_PRAM_STEP_BY_STEP_PRAM_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_PRAM_STEP_BY_STEP_PRAM_ANALYSIS.out.tables
    plots    = BIOC_PRAM_STEP_BY_STEP_PRAM_ANALYSIS.out.plots
    objects  = BIOC_PRAM_STEP_BY_STEP_PRAM_ANALYSIS.out.objects
    versions = BIOC_PRAM_STEP_BY_STEP_PRAM_ANALYSIS.out.versions
}
