#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: marray — two_color_microarray_preprocessing
// Load raw two-color microarray data, assign layout and plate metadata, perform diagnostic plotting, and normalize intensity data.
// Input: SwirlSample.txt, fish.gal, Spot/raw intensity files
// Container: quay.io/biocontainers/bioconductor-marray:1.88.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MARRAY_TWO_COLOR_MICROARRAY_PREPROCESSING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-marray:1.88.0--r45hdfd78af_0"

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
    .bm_deps <- c("marray")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required library
    library(marray)
    
    # 1. Read target information
    # The pipeline assumes SwirlSample.txt, fish.gal, and raw spot files are in the working directory.
    datadir <- "."
    swirlTargets <- read.marrayInfo(file.path(datadir, "SwirlSample.txt"))
    
    # 2. Read raw intensity data
    mraw <- read.Spot(targets = swirlTargets, path=datadir)
    
    # 3. Read layout and gene information from GAL file and assign to raw object
    galinfo <- read.Galfile("fish.gal", path=datadir)
    mraw@maLayout <- galinfo\$layout
    mraw@maGnames <- galinfo\$gnames
    
    # Assign the raw object to 'swirl' to match the documented vignette workflow
    swirl <- mraw
    
    # 4. Compute and assign plate metadata
    maPlate(swirl)<-maCompPlate(swirl,n=384)
    
    # 5. Perform pre-normalization diagnostic plotting
    pdf("pre_normalization_diagnostics.pdf", width=10, height=8)
    par(mfrow=c(2,2))
    boxplot(swirl[,3], xvar="maPrintTip", yvar="maM", main="Swirl array 93: pre--normalization")
    boxplot(swirl, yvar="maM", main="Swirl arrays: pre--normalization")
    plot(swirl[,3], main="Swirl array 93: pre--normalization MA--plot")
    dev.off()
    
    # 6. Normalize intensity data
    swirl.norm <- maNorm(swirl, norm="p")
    summary(swirl.norm)
    
    swirl.norm1 <- maNorm(swirl, norm="p")
    swirl.norm2 <- maNormScale(swirl.norm1, norm="p")
    
    # 7. Perform post-normalization diagnostic plotting
    pdf("post_normalization_diagnostics.pdf", width=10, height=8)
    par(mfrow=c(2,2))
    boxplot(swirl.norm[,3], xvar="maPrintTip", yvar="maM", main="Swirl array 93: post--normalization")
    boxplot(swirl.norm, yvar="maM", main="Swirl arrays: post--normalization")
    plot(swirl.norm[,3], main="Swirl array 93: post--normalization MA--plot")
    dev.off()
    
    # Save meaningful results to output files
    saveRDS(swirl.norm, file="swirl_normalized_location.rds")
    saveRDS(swirl.norm2, file="swirl_normalized_scale.rds")
    
    # Export normalized log-ratios (M-values) and average log-intensities (A-values) to CSV
    write.csv(as.data.frame(swirl.norm@maM), file="normalized_log_ratios_M.csv", row.names=TRUE)
    write.csv(as.data.frame(swirl.norm@maA), file="normalized_average_intensities_A.csv", row.names=TRUE)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_MARRAY_TWO_COLOR_MICROARRAY_PREPROCESSING":
        marray: \$(Rscript -e 'cat(as.character(packageVersion("marray")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_two_color_microarray_preprocessing.csv versions.yml
    """
}

workflow BIOC_MARRAY_TWO_COLOR_MICROARRAY_PREPROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SwirlSample.txt, fish.gal, Spot/raw intensity files ] ]

    main:
    BIOC_MARRAY_TWO_COLOR_MICROARRAY_PREPROCESSING(ch_input)

    emit:
    tables   = BIOC_MARRAY_TWO_COLOR_MICROARRAY_PREPROCESSING.out.tables
    plots    = BIOC_MARRAY_TWO_COLOR_MICROARRAY_PREPROCESSING.out.plots
    objects  = BIOC_MARRAY_TWO_COLOR_MICROARRAY_PREPROCESSING.out.objects
    versions = BIOC_MARRAY_TWO_COLOR_MICROARRAY_PREPROCESSING.out.versions
}
