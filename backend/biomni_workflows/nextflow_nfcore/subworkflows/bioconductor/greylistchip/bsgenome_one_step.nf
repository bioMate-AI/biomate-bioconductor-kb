#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: greylistchip — bsgenome_one_step
// Generate a grey list in a single step using a BSgenome package and a BAM file.
// Input: myBamFile.bam
// Container: quay.io/biocontainers/bioconductor-greylistchip:1.42.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GREYLISTCHIP_BSGENOME_ONE_STEP {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-greylistchip:1.42.0--r45hdfd78af_0"

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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg19", "GreyListChIP", "rtracklayer")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(GreyListChIP)
    library(BSgenome.Hsapiens.UCSC.hg19)
    library(rtracklayer)
    
    # Define input file path
    bam_file <- "myBamFile.bam"
    
    # Validate that the required input file exists
    if (!file.exists(bam_file)) {
      stop(paste("Error: Required input file '", bam_file, "' not found in the working directory.", sep=""))
    }
    
    # Step 1 & 2: Generate the grey list in a single step using the BSgenome package and the BAM file
    message("Generating grey list from ", bam_file, "...")
    gl <- greyListBS(BSgenome.Hsapiens.UCSC.hg19, "myBamFile.bam")
    
    # Step 3: Export the grey list to a BED file
    message("Exporting grey list to myGreyList.bed...")
    export(gl, con="myGreyList.bed")
    
    # Save the GreyList S4 object as an RDS file for downstream analysis
    message("Saving GreyList object to greylist_object.rds...")
    saveRDS(gl, file="greylist_object.rds")
    
    # Print summary statistics of the generated grey list
    message("Grey List Generation Complete. Summary:")
    print(gl)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_GREYLISTCHIP_BSGENOME_ONE_STEP":
        greylistchip: \$(Rscript -e 'cat(as.character(packageVersion("greylistchip")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bsgenome_one_step.csv versions.yml
    """
}

workflow BIOC_GREYLISTCHIP_BSGENOME_ONE_STEP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ myBamFile.bam ] ]

    main:
    BIOC_GREYLISTCHIP_BSGENOME_ONE_STEP(ch_input)

    emit:
    tables   = BIOC_GREYLISTCHIP_BSGENOME_ONE_STEP.out.tables
    plots    = BIOC_GREYLISTCHIP_BSGENOME_ONE_STEP.out.plots
    objects  = BIOC_GREYLISTCHIP_BSGENOME_ONE_STEP.out.objects
    versions = BIOC_GREYLISTCHIP_BSGENOME_ONE_STEP.out.versions
}
