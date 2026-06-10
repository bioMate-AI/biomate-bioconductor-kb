#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chicago — chicago_interaction_calling
// Run the core CHiCAGO pipeline on Capture Hi-C data to call significant interactions and export results to disk.
// Input: GM_rep1.chinput, h19_chr20and21.rmap, h19_chr20and21.baitmap, h19_chr20and21.npb, h19_chr20and21.nbpb, h19_chr20and21.poe
// Container: quay.io/biocontainers/bioconductor-chicago:1.38.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHICAGO_CHICAGO_INTERACTION_CALLING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-chicago:1.38.0--r45hdfd78af_0"

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
    .bm_deps <- c("annotationhub", "chicago", "genomicinteractions", "genomicranges", "pchicdata")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load the required Bioconductor package
    library(Chicago)
    
    # Define input files and directories from the working directory
    testDesignDir <- "."
    settingsFile <- NULL
    files <- "GM_rep1.chinput"
    
    # 1. Initialize the chicagoData object with design files and settings
    cd <- setExperiment(designDir = testDesignDir, settingsFile = settingsFile)
    
    # 2. Read and merge replicate input files
    cd <- readAndMerge(files=files, cd=cd)
    
    # 3. Run the core statistical pipeline
    cd <- chicagoPipeline(cd)
    
    # Create output directory for results
    outputDirectory <- "chicago_output"
    dir.create(outputDirectory, showWarnings = FALSE, recursive = TRUE)
    
    # 4. Export interaction calls to disk in ibed, seqmonk, and washU formats
    exportResults(cd, file.path(outputDirectory, "vignetteOutput"))
    
    # Save the processed chicagoData object to disk
    saveRDS(cd, file = file.path(outputDirectory, "chicago_object.rds"))

    cat <<-END_VERSIONS > versions.yml
    "BIOC_CHICAGO_CHICAGO_INTERACTION_CALLING":
        chicago: \$(Rscript -e 'cat(as.character(packageVersion("chicago")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chicago_interaction_calling.csv versions.yml
    """
}

workflow BIOC_CHICAGO_CHICAGO_INTERACTION_CALLING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ GM_rep1.chinput, h19_chr20and21.rmap, h19_chr20and21.baitmap, h19_chr20and21.npb, h19_chr20and21.nbpb, h19_chr20and21.poe ] ]

    main:
    BIOC_CHICAGO_CHICAGO_INTERACTION_CALLING(ch_input)

    emit:
    tables   = BIOC_CHICAGO_CHICAGO_INTERACTION_CALLING.out.tables
    plots    = BIOC_CHICAGO_CHICAGO_INTERACTION_CALLING.out.plots
    objects  = BIOC_CHICAGO_CHICAGO_INTERACTION_CALLING.out.objects
    versions = BIOC_CHICAGO_CHICAGO_INTERACTION_CALLING.out.versions
}
