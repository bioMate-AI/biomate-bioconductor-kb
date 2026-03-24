#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GOSemSim
// The semantic comparisons of Gene Ontology (GO) annotations provide quantitative ways to compute simi
//
// Source : https://yulab-smu.top/biomedical-knowledge-mining-book/011-GOSemSim.html
// Upstream  : none
// Downstream: tRanslatome
//
// Install: BiocManager::install("GOSemSim")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GOSEMSIM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gosemsim"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gosemsim:2.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gosemsim:2.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gosemsim_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gosemsim_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gosemsim_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AnnotationHub)
    library(jsonlite)

    # --- Semantic data [] ---
    # Key functions: godata
    library(AnnotationDbi)
    library(GOSemSim)
    hsGO <- godata(annoDb = 'org.Hs.eg.db', ont="MF")
    # --- Supported organisms [] ---
    # Key functions: AnnotationHub, query
    library(AnnotationHub)
    hub <- AnnotationHub()
    q <- query(hub, "Cricetulus")
    id <- q$ah_id[length(q)]
    Cgriseus <- hub[[id]]
    # --- GO semantic similarity measurement [] ---
    # Key functions: goSim, mgoSim
    goSim("GO:0004022", "GO:0005515", semData=hsGO, measure="Jiang")
    
    goSim("GO:0004022", "GO:0005515", semData=hsGO, measure="Wang")
    
    go1 = c("GO:0004022","GO:0004024","GO:0004174")
    go2 = c("GO:0009055","GO:0005515")
    mgoSim(go1, go2, semData=hsGO, measure="Wang", combine=NULL)
    
    mgoSim(go1, go2, semData=hsGO, measure="Wang", combine="BMA")
    # --- Gene semantic similarity measurement [] ---
    # Key functions: geneSim, mgeneSim, godata
    GOSemSim::geneSim("241", "251", semData=hsGO, measure="Wang", combine="BMA")
    
    mgeneSim(genes=c("835", "5261","241", "994"),
             semData=hsGO, measure="Wang",verbose=FALSE)
    
    mgeneSim(genes=c("835", "5261","241", "994"),
           semData=hsGO, measure="Rel",verbose=FALSE)
    
    hsGO2 <- godata('org.Hs.eg.db', keytype = "SYMBOL", ont="MF", computeIC=FALSE)
    genes <- c("CDC45", "MCM10", "CDC20", "NMU", "MMP1")
    mgeneSim(genes, semData=hsGO2, measure="Wang", combine="BMA", verbose=FALSE)
    # --- Gene cluster semantic similarity measurement [] ---
    # Key functions: clusterSim, mappedkeys, sample, mclusterSim
    gs1 <- c("835", "5261","241", "994", "514", "533")
    gs2 <- c("578","582", "400", "409", "411")
    clusterSim(gs1, gs2, semData=hsGO, measure="Wang", combine="BMA")
    
    library(org.Hs.eg.db)
    x <- org.Hs.egGO
    hsEG <- mappedkeys(x)
    set.seed <- 123
    clusters <- list(a=sample(hsEG, 20), b=sample(hsEG, 20), c=sample(hsEG, 20))
    mclusterSim(clusters, semData=hsGO, measure="Wang", combine="BMA")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gosemsim_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gosemsim_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gosemsim_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GOSEMSIM:", paste0("    gosemsim: ", packageVersion("GOSemSim"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gosemsim_results.csv
    touch ${prefix}_gosemsim_output.rds
    echo "BIOC_GOSEMSIM:" > versions.yml
    echo "    gosemsim: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GOSEMSIM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GOSEMSIM(ch_input)

    emit:
    results  = BIOC_GOSEMSIM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GOSEMSIM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GOSEMSIM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GOSEMSIM.out.versions  // channel: path(versions.yml)
}
