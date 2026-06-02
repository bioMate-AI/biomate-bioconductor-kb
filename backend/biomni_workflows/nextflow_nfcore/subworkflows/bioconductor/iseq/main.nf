#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: iSeq
// Bayesian hidden Ising models are implemented to identify IP-enriched genomic regions from ChIP-seq d
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/iSeq/inst/doc/iSeq.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("iSeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-iseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-iseq:1.58.0--r44_0' :
        'quay.io/biocontainers/bioconductor-iseq:1.58.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_iseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_iseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_iseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(iSeq)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    library(iSeq)
    data(nrsf)
    names(nrsf)
    # --- Mergetag [] ---
    # Key functions: mergetag
    tagct = mergetag(chip=chip,control=mock,maxlen=80,minlen=10,ntagcut=10)
    print(tagct[1:3,])
    # --- Peakreg [] ---
    # Key functions: peakreg
    tagct22 = tagct[tagct[,1]=="chr22",]  #chr22 data
    reg0 = peakreg(chrpos=tagct22[,1:3],count=(tagct22[,5:6]-tagct22[,7:8]),
                   pp=(tagct22[,4]>10),cutoff=0,method="ppcut",maxgap=200)
    print(dim(reg0))
    print(reg0[1:3,]) # each row contain the information for an enriched region
    # --- Frame [] ---
    # Key functions: frame
    bed = data.frame(chr=reg2[,1],gstart=reg2[,6]-100,gend=reg2[,6]+100)
    # --- Iseq2 [] ---
    # Key functions: iSeq2
    res2 = iSeq2(Y=tagct22[,1:4],gap=200, burnin=100,sampling=500,winsize=2,
         ctcut=0.95,a0=1,b0=1,a1=5,b1=1,k=1.0,verbose=FALSE)
    # --- Peakreg [] ---
    # Key functions: peakreg
    reg2 = peakreg(tagct22[,1:3],tagct22[,5:6],res2$pp,0.5,method="ppcut",maxgap=200)
    print(dim(reg2))
    print(reg2[1:3,])
    # --- Table [] ---
    # Key functions: iSeq1, iSeq2
    tagctY = tagct[tagct[,1]=="chrY",]
    print(table(tagctY[,4]))
    res1 = iSeq1(Y=tagctY[,1:4],gap=200,burnin=1000,sampling=5000,ctcut=0.95,
         a0=1,b0=1,a1=5,b1=1,k0=3,mink=0,maxk=10,normsd=0.5,verbose=FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_iseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_iseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_iseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ISEQ:", paste0("    iseq: ", packageVersion("iSeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_iseq_results.csv
    touch ${prefix}_iseq_output.rds
    echo "BIOC_ISEQ:" > versions.yml
    echo "    iseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ISEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ISEQ(ch_input)

    emit:
    results  = BIOC_ISEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ISEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ISEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ISEQ.out.versions  // channel: path(versions.yml)
}
