#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: branchpointer — intronic_branchpoint_annotation
// Predict and annotate branchpoint probabilities within specified intronic regions.
// Input: gencode.v26.annotation.gtf, intron_example.txt
// Container: quay.io/biocontainers/bioconductor-branchpointer:1.32.0--r44hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BRANCHPOINTER_INTRONIC_BRANCHPOINT_ANNOTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-branchpointer:1.32.0--r44hdfd78af_0"

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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg38", "biomart", "branchpointer")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(branchpointer)
    library(BSgenome.Hsapiens.UCSC.hg38)
    
    # Define input files
    gtf_file <- "gencode.v26.annotation.gtf"
    query_file <- "intron_example.txt"
    
    # Verify input files exist
    if (!file.exists(gtf_file)) {
      stop("Required input file 'gencode.v26.annotation.gtf' not found in the working directory.")
    }
    if (!file.exists(query_file)) {
      stop("Required input file 'intron_example.txt' not found in the working directory.")
    }
    
    # Load the BSgenome object
    g <- BSgenome.Hsapiens.UCSC.hg38::BSgenome.Hsapiens.UCSC.hg38
    
    # 1. Convert GTF annotations to an exon GRanges object
    message("Converting GTF annotations to exons...")
    exons <- gtfToExons(gtf_file)
    
    # 2. Read query regions and calculate location attributes
    message("Reading query file...")
    queryIntron <- readQueryFile(query_file, queryType = "region", exons = exons)
    
    # Generate windows from GTF using makeBranchpointWindowForExons
    message("Generating branchpoint windows from GTF...")
    # Use the documented ID if present, otherwise fallback to the first available exon ID
    exon_id_query <- "ENSE00000939171.1"
    if (!is.null(exons\$exon_id) && !(exon_id_query %in% exons\$exon_id)) {
      exon_id_query <- head(exons\$exon_id, 1)
    }
    
    queryIntronFromGTF <- tryCatch({
      makeBranchpointWindowForExons(exon_id_query, idType = "exon_id", exons = exons)
    }, error = function(e) {
      message("Warning: makeBranchpointWindowForExons failed: ", e\$message)
      NULL
    })
    
    # 3. Predict branchpoint probabilities
    message("Predicting branchpoint probabilities...")
    branchpointPredictionsIntron <- predictBranchpoints(queryIntron, queryType = "region", BSgenome = g)
    
    # 4. Visualize the branchpoint window
    message("Plotting branchpoint window...")
    # Use the second query ID as documented, fallback to the first if not available
    query_id <- if (length(queryIntron\$id) >= 2) queryIntron\$id[2] else queryIntron\$id[1]
    
    pdf("branchpoint_window_plot.pdf", width = 10, height = 8)
    plotBranchpointWindow(query_id, 
                          branchpointPredictionsIntron, 
                          probabilityCutoff = 0.52, 
                          plotMutated = FALSE, 
                          plotStructure = TRUE, 
                          exons = exons)
    dev.off()
    
    # Save outputs
    message("Saving output files...")
    write.csv(as.data.frame(branchpointPredictionsIntron), "branchpoint_predictions.csv", row.names = FALSE)
    saveRDS(branchpointPredictionsIntron, "branchpoint_predictions.rds")
    
    if (!is.null(queryIntronFromGTF)) {
      saveRDS(queryIntronFromGTF, "query_intron_from_gtf.rds")
    }
    
    message("Pipeline completed successfully!")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_BRANCHPOINTER_INTRONIC_BRANCHPOINT_ANNOTATION":
        branchpointer: \$(Rscript -e 'cat(as.character(packageVersion("branchpointer")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_intronic_branchpoint_annotation.csv versions.yml
    """
}

workflow BIOC_BRANCHPOINTER_INTRONIC_BRANCHPOINT_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gencode.v26.annotation.gtf, intron_example.txt ] ]

    main:
    BIOC_BRANCHPOINTER_INTRONIC_BRANCHPOINT_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_BRANCHPOINTER_INTRONIC_BRANCHPOINT_ANNOTATION.out.tables
    plots    = BIOC_BRANCHPOINTER_INTRONIC_BRANCHPOINT_ANNOTATION.out.plots
    objects  = BIOC_BRANCHPOINTER_INTRONIC_BRANCHPOINT_ANNOTATION.out.objects
    versions = BIOC_BRANCHPOINTER_INTRONIC_BRANCHPOINT_ANNOTATION.out.versions
}
