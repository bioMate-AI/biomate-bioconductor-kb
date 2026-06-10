#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chemminer — large_sdf_streaming
// Stream through a massive SD file to compute descriptors and index molecule positions without loading the entire file into memory.
// Input: test.sdf
// Container: quay.io/biocontainers/bioconductor-chemminer:3.62.0--r45ha27e39d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHEMMINER_LARGE_SDF_STREAMING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-chemminer:3.62.0--r45ha27e39d_0"

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
    .bm_deps <- c("ChemmineR")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required library
    library(ChemmineR)
    
    # Verify that the required input file exists in the working directory
    if (!file.exists("test.sdf")) {
      stop("Error: Required input file 'test.sdf' not found in the working directory.")
    }
    
    # Stage 1: Define a descriptor extraction function
    desc <- function(sdfset) cbind(SDFID=sdfid(sdfset), MW=MW(sdfset), groups(sdfset), APFP=desc2fp(x=sdf2ap(sdfset), descnames=1024, type="character"), AP=sdf2ap(sdfset, type="character"), rings(sdfset, type="count", upper=6, arom=TRUE) )
    
    # Stage 2: Stream through the SDF and write descriptors to a tabular file
    sdfStream(input="test.sdf", output="matrix.xls", fct=desc, Nlines=1000)
    
    # Stage 3: Filter the tabular index and retrieve specific molecules of interest
    indexDF <- read.delim("matrix.xls", row.names=1)[,1:4]
    indexDFsub <- indexDF[indexDF\$MW < 400, ]
    sdfset <- read.SDFindex(file="test.sdf", index=indexDFsub, type="SDFset")
    
    # Stage 4: Write output files for the meaningful results
    # Save the filtered index table as a CSV file
    write.csv(indexDFsub, file = "filtered_index.csv", row.names = TRUE)
    
    # Save the retrieved SDFset as an RDS object
    saveRDS(sdfset, file = "filtered_sdfset.rds")
    
    # Export the retrieved molecules to a new SD file
    write.SDF(sdfset, file = "filtered.sdf")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_CHEMMINER_LARGE_SDF_STREAMING":
        chemminer: \$(Rscript -e 'cat(as.character(packageVersion("chemminer")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_large_sdf_streaming.csv versions.yml
    """
}

workflow BIOC_CHEMMINER_LARGE_SDF_STREAMING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ test.sdf ] ]

    main:
    BIOC_CHEMMINER_LARGE_SDF_STREAMING(ch_input)

    emit:
    tables   = BIOC_CHEMMINER_LARGE_SDF_STREAMING.out.tables
    plots    = BIOC_CHEMMINER_LARGE_SDF_STREAMING.out.plots
    objects  = BIOC_CHEMMINER_LARGE_SDF_STREAMING.out.objects
    versions = BIOC_CHEMMINER_LARGE_SDF_STREAMING.out.versions
}
