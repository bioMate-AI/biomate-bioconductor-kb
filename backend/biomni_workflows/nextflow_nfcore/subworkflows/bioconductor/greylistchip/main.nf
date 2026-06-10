#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: greylistchip — step_by_step_karyotype
// Generate a grey list from a BAM file using a custom karyotype file via step-by-step execution.
// Input: karyotype_chr21.txt, myBamFile.bam
// Container: quay.io/biocontainers/bioconductor-greylistchip:1.42.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GREYLISTCHIP_STEP_BY_STEP_KARYOTYPE {
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
    .bm_deps <- c("greylistchip")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(GreyListChIP)
    
    # Define input file paths (expected in the working directory)
    karyotype_file <- "karyotype_chr21.txt"
    bam_file <- "myBamFile.bam"
    
    # Validate that input files exist
    if (!file.exists(karyotype_file)) {
      stop(paste("Required input file missing:", karyotype_file))
    }
    if (!file.exists(bam_file)) {
      stop(paste("Required input file missing:", bam_file))
    }
    
    # 1. Initialize GreyList object with the custom karyotype file
    message("Initializing GreyList object...")
    gl <- new("GreyList", karyoFile=karyotype_file)
    
    # 2. Count reads in genome tiles from the BAM file
    message("Counting reads from BAM file...")
    gl <- countReads(gl, bam_file)
    
    # 3. Calculate read-count threshold using negative binomial fitting
    message("Calculating threshold...")
    gl <- calcThreshold(gl, reps=10, sampleSize=1000, p=0.99, cores=1)
    
    # 4. Generate grey list regions
    message("Generating grey list...")
    gl <- makeGreyList(gl, maxGap=16384)
    
    # 5. Export grey list to BED file
    message("Exporting grey list to BED file...")
    export(gl, con="myGreyList.bed")
    
    # Save the final GreyList object as an RDS file for downstream R analysis
    message("Saving GreyList object to RDS...")
    saveRDS(gl, file="grey_list_object.rds")
    
    # Generate and save a summary of the results
    message("Writing summary statistics...")
    summary_df <- data.frame(
      Metric = c("Total_Tiles", "Threshold", "Regions_Count", "Coverage_Percentage"),
      Value = c(
        length(gl@tiles),
        gl@threshold,
        length(gl@regions),
        gl@coverage
      ),
      stringsAsFactors = FALSE
    )
    write.csv(summary_df, file="grey_list_summary.csv", row.names=FALSE)
    
    message("Workflow complete. Outputs generated: myGreyList.bed, grey_list_object.rds, grey_list_summary.csv")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_GREYLISTCHIP_STEP_BY_STEP_KARYOTYPE":
        greylistchip: \$(Rscript -e 'cat(as.character(packageVersion("greylistchip")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_step_by_step_karyotype.csv versions.yml
    """
}

workflow BIOC_GREYLISTCHIP_STEP_BY_STEP_KARYOTYPE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ karyotype_chr21.txt, myBamFile.bam ] ]

    main:
    BIOC_GREYLISTCHIP_STEP_BY_STEP_KARYOTYPE(ch_input)

    emit:
    tables   = BIOC_GREYLISTCHIP_STEP_BY_STEP_KARYOTYPE.out.tables
    plots    = BIOC_GREYLISTCHIP_STEP_BY_STEP_KARYOTYPE.out.plots
    objects  = BIOC_GREYLISTCHIP_STEP_BY_STEP_KARYOTYPE.out.objects
    versions = BIOC_GREYLISTCHIP_STEP_BY_STEP_KARYOTYPE.out.versions
}
