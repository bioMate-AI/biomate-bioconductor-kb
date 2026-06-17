# Real user-style input for ClusterJudge:
#   clusters.csv      - the user's clustering result: entity (gene id) -> cluster id
#                       (e.g. from k-means or cutting a hierarchical tree)
#   associations.csv  - entity-attribute associations: gene -> functional attribute
#                       (e.g. a gene -> GO-term mapping the user downloaded)
#
# We build a clustering of 120 genes into 6 clusters where each cluster is
# enriched for a distinct set of attributes (so the clustering genuinely agrees
# with the attribute system and clusterJudge sees a real mutual-information
# signal). This is exactly the table shape a user supplies; no package demo data.

set.seed(42)
n_clusters <- 6
genes_per  <- 20
n_genes    <- n_clusters * genes_per

gene_ids <- sprintf("GENE%04d", seq_len(n_genes))
cluster  <- rep(seq_len(n_clusters), each = genes_per)

clusters_df <- data.frame(entity = gene_ids, cluster = cluster,
                          stringsAsFactors = FALSE)
write.csv(clusters_df, "clusters.csv", row.names = FALSE)

# Attribute pools: each cluster has a few "signature" attributes most of its
# members carry, plus shared housekeeping attributes, plus light noise.
signature <- lapply(seq_len(n_clusters), function(k)
    sprintf("ATTR_C%d_%d", k, 1:4))
housekeeping <- sprintf("ATTR_HK_%d", 1:3)

rows <- list()
add <- function(g, a) rows[[length(rows) + 1]] <<- data.frame(entity = g, attribute = a,
                                                              stringsAsFactors = FALSE)
for (i in seq_len(n_genes)) {
    g <- gene_ids[i]
    k <- cluster[i]
    # signature attributes for this cluster (each carried with high probability)
    for (a in signature[[k]]) if (runif(1) < 0.85) add(g, a)
    # housekeeping attributes shared across all clusters
    for (a in housekeeping) if (runif(1) < 0.5) add(g, a)
    # occasional cross-cluster attribute (noise)
    if (runif(1) < 0.15) {
        ok <- sample(setdiff(seq_len(n_clusters), k), 1)
        add(g, sample(signature[[ok]], 1))
    }
}
assoc_df <- unique(do.call(rbind, rows))
write.csv(assoc_df, "associations.csv", row.names = FALSE)
