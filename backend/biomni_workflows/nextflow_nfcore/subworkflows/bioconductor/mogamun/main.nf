#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mogamun — active_module_identification
// Identify active modules in a multiplex biological network using differential expression data and multi-objective genetic optimization.
// Input: Sample_DE.csv, Sample_NodesScore.csv, NetworkLayersDir
// Container: quay.io/biocontainers/bioconductor-mogamun:1.20.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOGAMUN_ACTIVE_MODULE_IDENTIFICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-mogamun:1.20.0--r45hdfd78af_0"

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
    .bm_deps <- c("mogamun")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    library(MOGAMUN)
    
    # Define input paths based on user-provided files in the working directory
    dePath <- "Sample_DE.csv"
    scoresPath <- "Sample_NodesScore.csv"
    layersPath <- "NetworkLayersDir/"
    
    # Validate that the required inputs exist
    if (!file.exists(dePath)) {
      stop("Required input file 'Sample_DE.csv' not found in the working directory.")
    }
    if (!dir.exists(layersPath)) {
      stop("Required input directory 'NetworkLayersDir' not found in the working directory.")
    }
    
    # Dynamically identify the unique starting characters of the network layer files
    layer_files <- list.files("NetworkLayersDir", full.names = FALSE)
    layer_files <- layer_files[grep("^[a-zA-Z0-9]", layer_files)]
    if (length(layer_files) == 0) {
      stop("No valid network layer files found in NetworkLayersDir.")
    }
    first_chars <- unique(substr(layer_files, 1, 1))
    layers_string <- paste(first_chars, collapse = "")
    
    # 1. Initialize evolution and general parameters
    parameters <- mogamun_init(Generations = 1, PopSize = 10)
    
    # 2. Load differential expression data and multiplex network layers
    loadedData <-
        mogamun_load_data(
            EvolutionParameters = parameters,
            DifferentialExpressionPath = dePath,
            NodesScoresPath = scoresPath,
            NetworkLayersDir = layersPath,
            Layers = layers_string
        )
    
    # Save the loaded data object for reproducibility
    saveRDS(loadedData, file = "mogamun_loaded_data.rds")
    
    # 3. Run the genetic algorithm
    mogamun_run(LoadedData = loadedData, ResultsDir = '.')
    
    # 4. Post-process the results
    mogamun_postprocess(
        LoadedData = loadedData, 
        ExperimentDir = '.', 
        VisualizeInCytoscape = FALSE
    )

    cat <<-END_VERSIONS > versions.yml
    "BIOC_MOGAMUN_ACTIVE_MODULE_IDENTIFICATION":
        mogamun: \$(Rscript -e 'cat(as.character(packageVersion("mogamun")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_active_module_identification.csv versions.yml
    """
}

workflow BIOC_MOGAMUN_ACTIVE_MODULE_IDENTIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Sample_DE.csv, Sample_NodesScore.csv, NetworkLayersDir ] ]

    main:
    BIOC_MOGAMUN_ACTIVE_MODULE_IDENTIFICATION(ch_input)

    emit:
    tables   = BIOC_MOGAMUN_ACTIVE_MODULE_IDENTIFICATION.out.tables
    plots    = BIOC_MOGAMUN_ACTIVE_MODULE_IDENTIFICATION.out.plots
    objects  = BIOC_MOGAMUN_ACTIVE_MODULE_IDENTIFICATION.out.objects
    versions = BIOC_MOGAMUN_ACTIVE_MODULE_IDENTIFICATION.out.versions
}
