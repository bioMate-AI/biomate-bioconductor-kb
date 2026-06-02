#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BiRewire
// Fast functions for bipartite network rewiring through N consecutive switching steps (See References)
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BiRewire/inst/doc/BiRewire.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("BiRewire")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIREWIRE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-birewire"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-birewire:3.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-birewire:3.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_birewire_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_birewire_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_birewire_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(E)
    library(jsonlite)

    # --- Getabipartitegraph [] ---
    # Key functions: incidence
    data(BRCA_binary_matrix)##loads an binary genomic event matrix for the
    												##breast cancer dataset
    g=birewire.bipartite.from.incidence(BRCA_binary_matrix)##models the dataset
    																								## as igraph bipartite graph
    # --- Performanalisys [] ---
    # Key functions: bipartite
    step=5000
    max=100*sum(BRCA_binary_matrix)
    scores<-birewire.analysis.bipartite(BRCA_binary_matrix,step,
    		verbose=FALSE,max.iter=max,n.networks=5,display=F)
    # --- Performanalisysundirected [] ---
    # Key functions: game, adjacency, E, undirected
    g.und<-erdos.renyi.game(directed=F,loops=F,n=1000,p.or.m=0.01)
    m.und<-get.adjacency(g.und,sparse=FALSE)
    step=100
    max=100*length(E(g.und))
    # --- Rewire [] ---
    # Key functions: bipartite
    m2<-birewire.rewire.bipartite(BRCA_binary_matrix,verbose=FALSE)
    g2<-birewire.rewire.bipartite(g,verbose=FALSE)
    # --- Rewireundirected [] ---
    # Key functions: undirected
    m2.und<-birewire.rewire.undirected(m.und,verbose=FALSE)
    g2.und<-birewire.rewire.undirected(g.und,verbose=FALSE)
    # --- Similarity [] ---
    # Key functions: similarity
    sc=birewire.similarity(BRCA_binary_matrix,m2)
    sc=birewire.similarity(BRCA_binary_matrix,t(m2))#also works
    # --- Projections [] ---
    # Key functions: bipartite, projections
    #use a smaller graph!
    gg <- graph.bipartite( rep(0:1,length=10), c(1:10))
    result=birewire.rewire.bipartite.and.projections(gg,step=10,
            max.iter="n",accuracy=0.00005,verbose=FALSE)
    plot(result$similarity_scores.proj2,type='l',col='red',ylim=c(0,1))
    # --- Sampler Bipartite [] ---
    # Key functions: bipartite, incidence, unlink
    #use a smaller graph!
    gg <-graph.bipartite(rep(0:1,length=10), c(1:10))
     ## NOT RUN
     ##birewire.sampler.bipartite(get.incidence(g),K=10,path='TESTBIREWIRE',verbose=F)
     ##unlink('TESTBIREWIRE',recursive = T)
    # --- Monitoring [] ---
    # Key functions: bipartite, game, undirected
    ggg <- graph.bipartite( rep(0:1,length=10), c(1:10))
    tsne = birewire.visual.monitoring.bipartite(ggg,display=F,n.networks=10,perplexity=2)
    g <- erdos.renyi.game(1000,0.1)
    tsne = birewire.visual.monitoring.undirected(g,display=F,n.networks=10,perplexity=2)
    # --- Induced Bipartite And Sif Builder [] ---
    # Key functions: bipartite, dsg
    data(test_dsg)
    dsg=birewire.induced.bipartite(test_dsg,delimitators=list(negative='-',positive='+'))
    tmp=birewire.build.dsg(dsg,delimitators=list(negative='-',positive='+'))
    # --- Rewire Dsg [] ---
    # Key functions: dsg
    dsg2=birewire.rewire.dsg(dsg=dsg)
    tmp=birewire.build.dsg(dsg2,delimitators=list(negative='-',positive='+'))
    # --- Jacard Dsg [] ---
    # Key functions: dsg
    birewire.similarity.dsg(dsg,dsg2)
    # --- Sampler Dsg [] ---
    # Key functions: dsg, unlink
    ##NOT RUN
    ##birewire.sampler.dsg(dsg,K=10,path='TESTBIREWIREDSG',verbose=F,
    ##			delimitators=list(negative='-',positive='+'))
    ##unlink('TESTBIREWIREDSG',recursive = T)
    # --- Sampler Dsg V2 [] ---
    # Key functions: dsg, unlink
    ##NOT RUN
    ##birewire.sampler.dsg(dsg,K=10,path='TESTBIREWIREDSG',verbose=F,
    ##			delimitators=list(negative='-',positive='+'),check_pos_neg=T)
    ##unlink('TESTBIREWIREDSG',recursive = T)
    # --- Example General [] ---
    # Key functions: game, bipartite, incidence
    ##NOT RUN
    #ggg <- bipartite.random.game(n1=100,n2=40,p=0.2)
    #For recovering quickly the bound N we can perform a short analysis
    #N=birewire.analysis.bipartite(get.incidence(ggg,sparse=F),max.iter=2,step=1)$N
    #Now we can perform the real analysis

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_birewire_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_birewire_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_birewire_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIREWIRE:", paste0("    birewire: ", packageVersion("BiRewire"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_birewire_results.csv
    touch ${prefix}_birewire_output.rds
    echo "BIOC_BIREWIRE:" > versions.yml
    echo "    birewire: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIREWIRE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIREWIRE(ch_input)

    emit:
    results  = BIOC_BIREWIRE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIREWIRE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIREWIRE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIREWIRE.out.versions  // channel: path(versions.yml)
}
