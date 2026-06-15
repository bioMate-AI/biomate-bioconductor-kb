#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: regioneReloaded — multi_local_zscore
// Evaluate the positional dependency of a single genomic region set against a list of other region sets within a local genomic neighborhood.
// Input: A, Blist, genome
// Container: quay.io/biocontainers/bioconductor-regionereloaded:1.12.0--r45hdfd78af_0
// R packages: GenomicRanges, regioneReloaded
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, regioneReloaded
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Calculate local z-scores across a defined window and step
//  * 2. [Visualization & Output] Extract evaluation metrics and summary tables
//  * 3. [Visualization & Output] Generate a local z-score matrix and cluster the profiles
//  * 4. [Visualization & Output] Plot the clustered local z-score matrix
//  * 5. [Visualization & Output] Plot individual or multiple local z-score profiles

nextflow.enable.dsl = 2

process BIOC_REGIONERELOADED_MULTI_LOCAL_ZSCORE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("GenomicRanges", "regioneReloaded")
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
        library(regioneReloaded)
        library(GenomicRanges)
        
        # ==========================================
        # 1. READ USER INPUTS FROM WORKING DIRECTORY
        # ==========================================
        # The pipeline expects the following files in the working directory:
        # - 'A.rds': A single genomic region set as a GRanges object
        # - 'Blist.rds': A list of genomic region sets as GRanges objects
        # - 'genome.rds': A GRanges or Seqinfo object representing the reference genome
        
        if (!file.exists("A.rds")) {
          stop("Error: 'A.rds' (GRanges object) not found in the working directory.")
        }
        if (!file.exists("Blist.rds")) {
          stop("Error: 'Blist.rds' (list of GRanges objects) not found in the working directory.")
        }
        if (!file.exists("genome.rds")) {
          stop("Error: 'genome.rds' (GRanges or Seqinfo object) not found in the working directory.")
        }
        
        A <- readRDS("A.rds")
        Blist <- readRDS("Blist.rds")
        genome <- readRDS("genome.rds")
        
        # ==========================================
        # 2. RUN WORKFLOW (FAITHFUL TO DOCUMENTED CODE)
        # ==========================================
        
        # --- Calculate local z-scores across a defined window and step ---
        mlz_Alien_ReG <- multiLocalZscore(
          A = A, 
          Blist = Blist, 
          ranFUN = "resampleGenome", 
          evFUN = "numOverlaps", 
          window = 100, 
          step = 1, 
          max_pv = 1, 
          genome = genome
        )
        
        # Ensure the variable name matches the subsequent documented calls
        mLZ_regA_ReG <- mlz_Alien_ReG
        
        # Extract parameters
        params <- getParameters(mLZ_regA_ReG)
        write.csv(params, "mlz_parameters.csv", row.names = FALSE)
        
        # --- Extract evaluation metrics and summary tables ---
        mlz_Me <- getMultiEvaluation(rR = mLZ_regA_ReG)
        write.csv(mlz_Me\$resumeTable, "mlz_resume_table.csv", row.names = FALSE)
        print(head(mlz_Me\$resumeTable))
        
        # --- Generate a local z-score matrix and cluster the profiles ---
        mLZ_regA_ReG <- makeLZMatrix(mLZ_regA_ReG)
        saveRDS(mLZ_regA_ReG, "mLZ_regA_ReG.rds")
        
        # ==========================================
        # 3. GENERATE PLOTS (SAVED TO PDF)
        # ==========================================
        pdf("multi_local_zscore_plots.pdf", width = 10, height = 8)
        
        # Plot the clustering dendrogram
        tryCatch({
          plot(getHClust(mLZ_regA_ReG), cex = 0.8)
        }, error = function(e) {
          warning("Could not plot hclust: ", e\$message)
        })
        
        # --- Plot the clustered local z-score matrix ---
        tryCatch({
          p_mat <- plotLocalZScoreMatrix(mLZ_regA_ReG, maxVal = "max")
          if (inherits(p_mat, "ggplot")) print(p_mat)
        }, error = function(e) {
          warning("Could not plot local Z-score matrix: ", e\$message)
        })
        
        # --- Plot individual or multiple local z-score profiles ---
        # Dynamically extract region set names from the evaluation results
        rs_names <- as.character(mlz_Me\$resumeTable\$name)
        
        if (length(rs_names) > 0) {
          tryCatch({
            p_single <- plotSingleLZ(mLZ = mLZ_regA_ReG, RS = rs_names[1], smoothing = TRUE)
            if (inherits(p_single, "ggplot")) print(p_single)
          }, error = function(e) {
            warning("Could not plot single LZ: ", e\$message)
          })
          
          tryCatch({
            multi_rs <- rs_names[1:min(5, length(rs_names))]
            p_multi <- plotSingleLZ(
              mLZ = mLZ_regA_ReG, 
              RS = multi_rs, 
              smoothing = TRUE
            )
            if (inherits(p_multi, "ggplot")) print(p_multi)
          }, error = function(e) {
            warning("Could not plot multiple LZ profiles: ", e\$message)
          })
        } else {
          warning("No region set names found to plot single/multiple LZ profiles.")
        }
        
        dev.off()

    writeLines(c(
        '"BIOC_REGIONERELOADED_MULTI_LOCAL_ZSCORE":',
        paste0('    regioneReloaded: ', as.character(packageVersion('regioneReloaded')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_local_zscore.csv versions.yml
    """
}

workflow BIOC_REGIONERELOADED_MULTI_LOCAL_ZSCORE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ A, Blist, genome ] ]

    main:
    BIOC_REGIONERELOADED_MULTI_LOCAL_ZSCORE(ch_input)

    emit:
    tables   = BIOC_REGIONERELOADED_MULTI_LOCAL_ZSCORE.out.tables
    plots    = BIOC_REGIONERELOADED_MULTI_LOCAL_ZSCORE.out.plots
    objects  = BIOC_REGIONERELOADED_MULTI_LOCAL_ZSCORE.out.objects
    versions = BIOC_REGIONERELOADED_MULTI_LOCAL_ZSCORE.out.versions
}
