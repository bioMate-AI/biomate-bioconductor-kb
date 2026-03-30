#!/bin/bash -ue
echo "sample,cluster" > test_cluster_assignments.csv
echo "k,clusterConsensus" > test_icl_scores.csv
echo "4" > test_optimal_k.txt
echo "BIOC_CONSENSUSCLUSTERPLUS:" > versions.yml
echo "    consensusclusterplus: 0.0.0" >> versions.yml
