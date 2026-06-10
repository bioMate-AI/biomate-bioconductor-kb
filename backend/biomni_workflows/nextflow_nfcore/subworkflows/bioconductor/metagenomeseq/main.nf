#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: metagenomeSeq — standard_differential_abundance
// Import count data, taxonomy, and metadata, normalize using CSS or Wrench, and perform differential abundance testing using zero-inflated models.
// Input: CHK_NAME.otus.count.csv, CHK_otus.taxonomy.csv, CHK_clinical.csv
// Container: quay.io/biocontainers/bioconductor-metagenomeseq:1.52.0--r45hdfd78af_0
// R packages: biomformat, gss, interactivedisplay, metagenomeSeq
// Bioconductor: 3.20 | R: 4.4
// Requires: metagenomeSeq
// Visualizations: box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load count data, taxonomy, and metadata
//  * 2. [Input & Preparation] Create a MRexperiment object using newMRexperiment
//  * 3. [Core Analysis] Filter low-abundance features using filterData
//  * 4. [Core Analysis] Calculate normalization factors using cumNormStatFast and cumNorm (or wrenchNorm)
//  * 5. [Input & Preparation] Define the design matrix using model.matrix
//  * 6. [Core Analysis] Perform differential abundance testing using fitFeatureModel (recommended) or fitZig
//  * 7. [Visualization & Output] Extract and summarize results using MRcoefs

nextflow.enable.dsl = 2

process BIOC_METAGENOMESEQ_STANDARD_DIFFERENTIAL_ABUNDANCE {
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
    .bm_deps <- c("biomformat", "gss", "interactivedisplay", "metagenomeSeq")
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
    library(metagenomeSeq)
    
    # 1. Load count data, taxonomy, and metadata from the working directory
    lung = loadMeta("CHK_NAME.otus.count.csv") 
    taxa = read.delim("CHK_otus.taxonomy.csv", stringsAsFactors=FALSE)
    clin = loadPhenoData("CHK_clinical.csv", tran=TRUE)
    
    # Align clinical metadata with count matrix columns
    ord = match(colnames(lung\$counts), rownames(clin)) 
    clin = clin[ord,]
    
    # Create AnnotatedDataFrames
    phenotypeData = AnnotatedDataFrame(clin)
    OTUdata = AnnotatedDataFrame(taxa)
    
    # 2. Create a MRexperiment object using newMRexperiment
    obj = newMRexperiment(lung\$counts, phenoData=phenotypeData, featureData=OTUdata)
    
    # Assign to lungData to match documented workflow variables
    lungData = obj
    
    # Remove samples with missing SmokingStatus if any exist
    na_indices = which(is.na(pData(lungData)\$SmokingStatus))
    if (length(na_indices) > 0) {
      lungData = lungData[, -na_indices]
    }
    
    # 3. Filter low-abundance features using filterData
    lungData = filterData(lungData, present=30, depth=1)
    
    # 4. Calculate normalization factors using cumNormStatFast and cumNorm
    p = cumNormStatFast(lungData)
    lungData = cumNorm(lungData, p=p)
    
    # 5. Define the design matrix using model.matrix
    pd <- pData(lungData)
    mod <- model.matrix(~1+SmokingStatus, data=pd)
    
    # 6. Perform differential abundance testing using fitFeatureModel
    lungres1 = fitFeatureModel(lungData, mod)
    
    # 7. Extract and summarize results using MRcoefs
    results = MRcoefs(lungres1)
    
    # Write named output files for the meaningful results
    # Save the normalized MRexperiment object
    saveRDS(lungData, file="normalized_MRexperiment.rds")
    
    # Save the model fit object
    saveRDS(lungres1, file="fitFeatureModel_results.rds")
    
    # Save the differential abundance coefficients table
    write.csv(results, file="differential_abundance_results.csv", row.names=TRUE)
    
    # Generate a diagnostic PDF plot of the top differentially abundant feature
    pdf("top_differentially_abundant_feature.pdf", width=6, height=6)
    if (nrow(results) > 0) {
      top_feature = rownames(results)[1]
      norm_counts = MRcounts(lungData, norm=TRUE, log=TRUE)
      boxplot(norm_counts[top_feature, ] ~ pd\$SmokingStatus,
              main=paste("Log2 Normalized Counts for", top_feature),
              xlab="Smoking Status",
              ylab="Log2 Normalized Abundance",
              col=c("lightblue", "lightcoral"))
    } else {
      plot.new()
      text(0.5, 0.5, "No features tested or available for plotting.")
    }
    dev.off()

    writeLines(c(
        '"BIOC_METAGENOMESEQ_STANDARD_DIFFERENTIAL_ABUNDANCE":',
        paste0('    metagenomeSeq: ', as.character(packageVersion('metagenomeSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_differential_abundance.csv versions.yml
    """
}

workflow BIOC_METAGENOMESEQ_STANDARD_DIFFERENTIAL_ABUNDANCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ CHK_NAME.otus.count.csv, CHK_otus.taxonomy.csv, CHK_clinical.csv ] ]

    main:
    BIOC_METAGENOMESEQ_STANDARD_DIFFERENTIAL_ABUNDANCE(ch_input)

    emit:
    tables   = BIOC_METAGENOMESEQ_STANDARD_DIFFERENTIAL_ABUNDANCE.out.tables
    plots    = BIOC_METAGENOMESEQ_STANDARD_DIFFERENTIAL_ABUNDANCE.out.plots
    objects  = BIOC_METAGENOMESEQ_STANDARD_DIFFERENTIAL_ABUNDANCE.out.objects
    versions = BIOC_METAGENOMESEQ_STANDARD_DIFFERENTIAL_ABUNDANCE.out.versions
}
