#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ddct — ddct_step_by_step_analysis
// Perform step-by-step qRT-PCR data loading, filtering, relative expression calculation, and visualization using low-level functions.
// Input: Experiment1.txt, sampleData.txt
// Container: quay.io/biocontainers/bioconductor-ddct:1.66.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DDCT_DDCT_STEP_BY_STEP_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-ddct:1.66.0--r45hdfd78af_0"

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
    .bm_deps <- c("Biobase", "RColorBrewer", "ddCt", "lattice")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(Biobase)
    library(lattice)
    library(RColorBrewer)
    library(ddCt)
    
    # Define file paths and helper functions
    file.names <- "Experiment1.txt"
    info <- "sampleData.txt"
    warningFile <- "warnings.txt"
    savedir <- function(x) file.path(".", x)
    
    # 1. Load data into an SDMFrame object
    if (!file.exists(file.names)) {
      stop(paste("Required input file missing:", file.names))
    }
    CtData <- SDMFrame(file.names)
    
    # 2. Read sample annotation metadata
    if (file.exists(info)) {
      sampleInformation <- read.AnnotatedDataFrame(info, header=TRUE, row.names=NULL)
    } else {
      # Fallback if optional sampleData.txt is not present
      sampleInformation <- new("AnnotatedDataFrame",
                               data=data.frame(Sample=sampleNames(CtData)),
                               varMetadata=data.frame(labelDescription=c("unique identifier"), row.names=c("Sample")))
    }
    
    # Dynamically identify reference sample and housekeeping gene from the loaded data
    all_samples <- sampleNames(CtData)
    name.reference.sample <- if (length(all_samples) > 0) all_samples[1] else "Sample1"
    
    all_genes <- unique(coreData(CtData)\$Detector)
    name.reference.gene <- if (length(all_genes) > 0) all_genes[length(all_genes)] else "Gene2"
    
    # 3. Calculate relative expression using ddCtExpression
    result <- ddCtExpression(CtData, 
                             calibrationSample=name.reference.sample, 
                             housekeepingGene=name.reference.gene, 
                             sampleInformation=sampleInformation, 
                             warningStream=warningFile)
    
    # 4. Export results using elistWrite
    elistWrite(result, file=savedir("allValues.txt"))
    
    # Save R object for downstream analysis
    saveRDS(result, file=savedir("ddCt_result.rds"))
    
    # 5. Visualize results using errBarchart
    pdf(file=savedir("errBarchart_plot.pdf"), width=10, height=8)
    br <- errBarchart(result)
    print(br)
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_DDCT_DDCT_STEP_BY_STEP_ANALYSIS":
        ddct: \$(Rscript -e 'cat(as.character(packageVersion("ddct")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ddct_step_by_step_analysis.csv versions.yml
    """
}

workflow BIOC_DDCT_DDCT_STEP_BY_STEP_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Experiment1.txt, sampleData.txt ] ]

    main:
    BIOC_DDCT_DDCT_STEP_BY_STEP_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DDCT_DDCT_STEP_BY_STEP_ANALYSIS.out.tables
    plots    = BIOC_DDCT_DDCT_STEP_BY_STEP_ANALYSIS.out.plots
    objects  = BIOC_DDCT_DDCT_STEP_BY_STEP_ANALYSIS.out.objects
    versions = BIOC_DDCT_DDCT_STEP_BY_STEP_ANALYSIS.out.versions
}
