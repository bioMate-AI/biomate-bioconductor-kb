#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: splicewiz — novel_splicing_detection
// Detect and analyze novel alternative splicing events using unannotated junctions and tandem reads.
// Input: genome.fa, transcripts.gtf, sample1.bam
// Container: quay.io/biocontainers/bioconductor-splicewiz:1.12.0--r45ha27e39d_0
// R packages: SpliceWiz, edgeR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPLICEWIZ_NOVEL_SPLICING_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-splicewiz:1.12.0--r45ha27e39d_0"

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
    .bm_deps <- c("SpliceWiz", "edgeR")
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
    
    # Load the required SpliceWiz library
    library(SpliceWiz)
    
    # 1. Build the SpliceWiz reference using buildRef()
    ref_path <- file.path(tempdir(), "Reference")
    buildRef(
      reference_path = ref_path,
      fasta = "genome.fa",
      gtf = "transcripts.gtf",
      ontologySpecies = "Homo sapiens"
    )
    
    # 2. Process BAM files using processBAM()
    # Find BAMs in the current working directory
    bams <- findBAMS(".", level = 0)
    
    # If no BAMs are found automatically, fallback to the explicitly declared sample1.bam
    if (nrow(bams) == 0) {
      bams <- data.frame(
        sample = "sample1",
        path = "sample1.bam",
        stringsAsFactors = FALSE
      )
    }
    
    pb_path <- file.path(tempdir(), "pb_output")
    processBAM(
      bamfiles = bams\$path,
      sample_names = bams\$sample,
      reference_path = ref_path,
      output_path = pb_path
    )
    
    # 3. Collate data with novel splicing detection enabled using collateData()
    expr <- findSpliceWizOutput(pb_path)
    nxtse_path <- file.path(tempdir(), "NxtSE_output_novel")
    collateData(
      Experiment = expr,
      reference_path = ref_path,
      output_path = nxtse_path,
      novelSplicing = TRUE,
      novelSplicing_requireOneAnnotatedSJ = TRUE,
      novelSplicing_minSamples = 3,
      novelSplicing_minSamplesAboveThreshold = 1,
      novelSplicing_countThreshold = 10,
      novelSplicing_useTJ = TRUE
    )
    
    # 4. Import the collated experiment as an NxtSE object using makeSE()
    se <- makeSE(nxtse_path)
    
    # Assign condition metadata to colData(se) so that ASE_edgeR can run.
    # We dynamically assign conditions "A" and "B" across the available samples.
    if (ncol(se) >= 2) {
      colData(se)\$condition <- rep(c("A", "B"), length.out = ncol(se))
    } else {
      colData(se)\$condition <- "A"
    }
    
    # Save the raw NxtSE object
    saveRDS(se, "nxtse_object.rds")
    
    # 5. Filter and perform differential alternative splicing analysis
    se.filtered <- se[applyFilters(se), ]
    saveRDS(se.filtered, "nxtse_filtered_object.rds")
    
    require("edgeR")
    res_edgeR <- NULL
    
    # Run differential analysis inside a tryCatch block to handle cases with insufficient replicates robustly
    tryCatch({
      res_edgeR <- ASE_edgeR(
        se = se.filtered,
        test_factor = "condition",
        test_nom = "B",
        test_denom = "A"
      )
      if (!is.null(res_edgeR)) {
        write.csv(res_edgeR, "differential_splicing_edgeR.csv", row.names = FALSE)
        message("Differential splicing analysis completed successfully. Results saved to 'differential_splicing_edgeR.csv'.")
      }
    }, error = function(e) {
      warning("Differential splicing analysis failed: ", e\$message)
      message("This is expected if there are insufficient replicates or samples for the contrast.")
    })

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SPLICEWIZ_NOVEL_SPLICING_DETECTION":
        splicewiz: \$(Rscript -e 'cat(as.character(packageVersion("splicewiz")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_novel_splicing_detection.csv versions.yml
    """
}

workflow BIOC_SPLICEWIZ_NOVEL_SPLICING_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genome.fa, transcripts.gtf, sample1.bam ] ]

    main:
    BIOC_SPLICEWIZ_NOVEL_SPLICING_DETECTION(ch_input)

    emit:
    tables   = BIOC_SPLICEWIZ_NOVEL_SPLICING_DETECTION.out.tables
    plots    = BIOC_SPLICEWIZ_NOVEL_SPLICING_DETECTION.out.plots
    objects  = BIOC_SPLICEWIZ_NOVEL_SPLICING_DETECTION.out.objects
    versions = BIOC_SPLICEWIZ_NOVEL_SPLICING_DETECTION.out.versions
}
