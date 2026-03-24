#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: annotationTools
// Functions to annotate microarrays, find orthologs, and integrate heterogeneous gene expression profi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/annotationTools/inst/doc/annotationTools.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("annotationTools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ANNOTATIONTOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-annotationtools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-annotationtools:1.80.0--r44_0' :
        'quay.io/biocontainers/bioconductor-annotationtools:1.80.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_annotationtools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_annotationtools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_annotationtools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(I)
    library(jsonlite)

    # --- Csv [] ---
    # Key functions: csv
    ## annotation_HGU133Plus2<-read.csv('HG-U133_Plus_2_annot.csv',
    ## 	colClasses='character',comment.char='#')
    # --- Getgenesymbol [] ---
    # Key functions: getGENESYMBOL
    getGENESYMBOL(myPS,annotation_HGU133Plus2)
    # --- Getgeneontology [] ---
    # Key functions: getGENEONTOLOGY
    getGENEONTOLOGY(myPS,annotation_HGU133Plus2)
    # --- Ls [] ---
    # Key functions: search
    ls(grep('annotationTools',search()))
    # --- Getgeneid [] ---
    # Key functions: getGENEID, getHOMOLOG, csv, unlist, getPROBESET
    ps_human<-'1053_at'
    geneID_human<-getGENEID(ps_human,annotation_HGU133Plus2)
    geneID_mouse<-getHOMOLOG(geneID_human,10090,homologene)
    annotationFile<-system.file('extdata','Mouse430_2_annot_part.csv',
    	package='annotationTools')
    # --- Gethomolog [] ---
    # Key functions: getHOMOLOG
    getHOMOLOG(myGenes,10090,gene_orthologs,tableType="gene_orthologs")
    # --- ps2ps [] ---
    # Key functions: ps2ps
    ## orthoTable<-ps2ps(annotation_HGU133Plus2,annotation_Mouse4302,homologene,10090)
    # --- Csv [] ---
    # Key functions: csv, delim, getGENEID, getHOMOLOG, unlist
    ## annotation_HGU133Plus2<-read.csv('HG-U133_Plus_2_annot.csv',
    ## 	colClasses='character',comment.char='#')
    ## annotation_Mouse4302<-read.csv('Mouse430_2_annot.csv',
    ## 	colClasses='character',comment.char='#')
    ## homologene<-read.delim('homologene.data',header=F)
    # --- Lapply [] ---
    # Key functions: omit
    ## ps_Mouse4302_2<-lapply(ps_Mouse4302_2,function(x) {unique(x)})
    ## ps_Mouse4302_2<-lapply(ps_Mouse4302_2,function(x) {
    ## 	if (length(x)>1) na.omit(x) else x})
    ## gid_Mouse4302_1<-lapply(gid_Mouse4302_1,function(x) {unique(x)})
    ## gid_Mouse4302_1<-lapply(gid_Mouse4302_1,function(x) {
    # --- ps2ps [] ---
    # Key functions: ps2ps
    ## orthoTable<-ps2ps(annotation_HGU133Plus2,annotation_Mouse4302,homologene,10090)
    ## write.table(orthoTable,file='HGU133Plus2_Mouse4302.txt',sep='\t',
    ## 	col.names=T,row.names=F)
    # --- Data [] ---
    # Key functions: data
    data(orthologs_example)
    # --- Getorthologousprobesets [] ---
    # Key functions: getOrthologousProbesets
    orthops<-getOrthologousProbesets(ps_mouse,table_human,ortho)
    orthops[[1]]
    # --- Frame [] ---
    # Key functions: frame, I
    table_human_absM<-data.frame(I(table_human[,1]),I(abs(table_human[,2])))
    # --- Getorthologousprobesets [] ---
    # Key functions: getOrthologousProbesets
    orthops_maxAbsM<-getOrthologousProbesets(ps_mouse,table_human_absM,
    	ortho,max,forceProbesetSelection=TRUE)
    orthops_maxAbsM[[1]]
    # --- Selectortho [] ---
    # Key functions: frame, I, getOrthologousProbesets, unlist
    table_human_absT<-data.frame(I(table_human[,1]),I(abs(table_human[,3])))
    orthops_maxAbsT<-getOrthologousProbesets(ps_mouse,table_human_absT,
    	ortho,max,forceProbesetSelection=TRUE)
    orthops_maxAbsT_ind<-match(unlist(orthops_maxAbsT[[1]]),table_human[,1])
    plot(table_mouse[selection,2],table_human[orthops_maxAbsM_ind,2],

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_annotationtools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_annotationtools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_annotationtools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ANNOTATIONTOOLS:", paste0("    annotationtools: ", packageVersion("annotationTools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_annotationtools_results.csv
    touch ${prefix}_annotationtools_output.rds
    echo "BIOC_ANNOTATIONTOOLS:" > versions.yml
    echo "    annotationtools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ANNOTATIONTOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ANNOTATIONTOOLS(ch_input)

    emit:
    results  = BIOC_ANNOTATIONTOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ANNOTATIONTOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ANNOTATIONTOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ANNOTATIONTOOLS.out.versions  // channel: path(versions.yml)
}
