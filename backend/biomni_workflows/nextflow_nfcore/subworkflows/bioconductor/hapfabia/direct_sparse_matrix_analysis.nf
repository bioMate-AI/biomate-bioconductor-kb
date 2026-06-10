#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: hapfabia — direct_sparse_matrix_analysis
// Run the hapFabia analysis directly on pre-existing sparse matrix, annotation, and individual files.
// Input: dataSim1fabia_mat.txt, dataSim1fabia_annot.txt, dataSim1fabia_individuals.txt
// Container: quay.io/biocontainers/bioconductor-hapfabia:1.52.0--r45h01b2380_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HAPFABIA_DIRECT_SPARSE_MATRIX_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-hapfabia:1.52.0--r45h01b2380_0"

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
    .bm_deps <- c("hapFabia")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required library
    library(hapFabia)
    
    # Define expected input files
    mat_file <- "dataSim1fabia_mat.txt"
    annot_file <- "dataSim1fabia_annot.txt"
    ind_file <- "dataSim1fabia_individuals.txt"
    
    # Verify input files exist in the working directory
    if (!file.exists(mat_file) || !file.exists(annot_file) || !file.exists(ind_file)) {
      stop(paste("Error: Missing required input files in the working directory.",
                 "Please ensure the following files are present:",
                 mat_file, annot_file, ind_file, sep = "\n"))
    }
    
    # Run hapFabia directly on the files
    hapRes <- hapFabia(fileName="dataSim1fabia",prefixPath="",
       sparseMatrixPostfix="_mat",
       annotPostfix="_annot.txt",individualsPostfix="_individuals.txt",
       labelsA=NULL,pRange="",individuals=0,lowerBP=0,upperBP=0.15,
       p=10,iter=1,quant=0.01,eps=1e-5,alpha=0.03,cyc=50,non_negative=1,
       write_file=0,norm=0,lap=100.0,IBDsegmentLength=10,Lt = 0.1,
       Zt = 0.2,thresCount=1e-5,mintagSNVsFactor=3/4,pMAF=0.1,
       haplotypes=FALSE,cut=0.8,procMinIndivids=0.1,thresPrune=1e-3,
       simv="minD",minTagSNVs=6,minIndivid=2,avSNVsDist=100,SNVclusterLength=100)
    
    # Summarize the merged IBD segment list and write to a text file
    summary_output <- capture.output(summary(hapRes\$mergedIBDsegmentList))
    writeLines(summary_output, "ibd_segment_list_summary.txt")
    
    # Extract and plot a specific IBD segment
    mergedIBDsegmentList <- hapRes\$mergedIBDsegmentList
    if (length(mergedIBDsegmentList) > 0) {
      IBDsegment <- mergedIBDsegmentList[[1]]
      new_dir <- getwd()
      plot(IBDsegment, filename=paste(new_dir, "/dataSim1fabia_mat", sep=""))
    } else {
      message("No IBD segments found in the merged list. Skipping plot.")
    }
    
    # Save the complete results object
    saveRDS(hapRes, "hapRes_results.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_HAPFABIA_DIRECT_SPARSE_MATRIX_ANALYSIS":
        hapfabia: \$(Rscript -e 'cat(as.character(packageVersion("hapfabia")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_direct_sparse_matrix_analysis.csv versions.yml
    """
}

workflow BIOC_HAPFABIA_DIRECT_SPARSE_MATRIX_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dataSim1fabia_mat.txt, dataSim1fabia_annot.txt, dataSim1fabia_individuals.txt ] ]

    main:
    BIOC_HAPFABIA_DIRECT_SPARSE_MATRIX_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_HAPFABIA_DIRECT_SPARSE_MATRIX_ANALYSIS.out.tables
    plots    = BIOC_HAPFABIA_DIRECT_SPARSE_MATRIX_ANALYSIS.out.plots
    objects  = BIOC_HAPFABIA_DIRECT_SPARSE_MATRIX_ANALYSIS.out.objects
    versions = BIOC_HAPFABIA_DIRECT_SPARSE_MATRIX_ANALYSIS.out.versions
}
