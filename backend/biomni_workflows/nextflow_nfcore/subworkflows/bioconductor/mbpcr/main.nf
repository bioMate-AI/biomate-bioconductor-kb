#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mbpcr — profile_estimation_from_text_file
// Import tab-delimited copy number data, estimate global parameters, perform mBPCR profile estimation, and export/plot the results.
// Input: rec10k.txt
// Container: quay.io/biocontainers/bioconductor-mbpcr:1.64.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MBPCR_PROFILE_ESTIMATION_FROM_TEXT_FILE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-mbpcr:1.64.0--r45hdfd78af_0"

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
    .bm_deps <- c("mbpcr", "xtable")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load the required Bioconductor library
    library(mBPCR)
    
    # 1. Import data using importCNData from the local working directory
    path <- "rec10k.txt"
    rec10k <- importCNData(path, NRowSkip=1)
    
    # Map the imported columns to match the exact names used in the documented code
    rec10k\$Chromosome <- rec10k\$chr
    rec10k\$PhysicalPosition <- rec10k\$position
    rec10k\$log2ratio <- rec10k\$logratio
    
    # 2. Estimate global parameters using estGlobParam
    global_params <- estGlobParam(rec10k\$log2ratio)
    saveRDS(global_params, file="global_parameters.rds")
    
    # 3. Verify memory allocation for maxProbeNumber
    maxProbeNumber <- 1000
    A <- array(1, dim=(maxProbeNumber+1)*(maxProbeNumber+2)/2)
    remove(A)
    
    # 4. Estimate copy number profile using estProfileWithMBPCR (mBPCR method)
    results <- estProfileWithMBPCR(rec10k\$SNPname, rec10k\$Chromosome, rec10k\$PhysicalPosition, rec10k\$log2ratio, chrToBeAnalyzed=c(3,5), maxProbeNumber=1000)
    saveRDS(results, file="mbpcr_results_chr3_5.rds")
    
    # 5. Export estimated profile and breakpoints using writeEstProfile
    # This writes 'rec10kmBPCRestimate.txt' and 'rec10kmBPCRbreakpoints.txt' to the working directory
    writeEstProfile(path='', sampleName='rec10k', rec10k\$SNPname, rec10k\$Chromosome, rec10k\$PhysicalPosition, rec10k\$log2ratio, chrToBeWritten=c(3,5), results\$estPC, results\$estBoundaries)
    
    # 6. Estimate copy number profile using estProfileWithMBPCR (BRC method)
    results <- estProfileWithMBPCR(rec10k\$SNPname, rec10k\$Chromosome, rec10k\$PhysicalPosition, rec10k\$log2ratio, chrToBeAnalyzed=3, regr='BRC', maxProbeNumber=1000)
    saveRDS(results, file="mbpcr_brc_results_chr3.rds")
    
    # 7. Plot estimated profile using plotEstProfile and save to PDF
    pdf("rec10k_profile_estimation_chr3.pdf", width=10, height=7)
    plotEstProfile(sampleName='rec10k', rec10k\$Chromosome, rec10k\$PhysicalPosition, rec10k\$log2ratio, chrToBePlotted=3, results\$estPC, maxProbeNumber=2000, regrCurve=results\$regrCurve, regr='BRC')
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_MBPCR_PROFILE_ESTIMATION_FROM_TEXT_FILE":
        mbpcr: \$(Rscript -e 'cat(as.character(packageVersion("mbpcr")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_profile_estimation_from_text_file.csv versions.yml
    """
}

workflow BIOC_MBPCR_PROFILE_ESTIMATION_FROM_TEXT_FILE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ rec10k.txt ] ]

    main:
    BIOC_MBPCR_PROFILE_ESTIMATION_FROM_TEXT_FILE(ch_input)

    emit:
    tables   = BIOC_MBPCR_PROFILE_ESTIMATION_FROM_TEXT_FILE.out.tables
    plots    = BIOC_MBPCR_PROFILE_ESTIMATION_FROM_TEXT_FILE.out.plots
    objects  = BIOC_MBPCR_PROFILE_ESTIMATION_FROM_TEXT_FILE.out.objects
    versions = BIOC_MBPCR_PROFILE_ESTIMATION_FROM_TEXT_FILE.out.versions
}
