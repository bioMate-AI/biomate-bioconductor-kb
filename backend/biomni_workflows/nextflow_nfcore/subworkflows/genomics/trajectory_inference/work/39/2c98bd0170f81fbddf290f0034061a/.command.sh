#!/bin/bash -ue
touch run_velocity_umap.png
touch run_velocity_anndata.h5ad
echo "SCVELO_DYNAMICS:" > versions.yml
echo "    scvelo: 0.3.2" >> versions.yml
echo "    scanpy: 1.10.0" >> versions.yml
echo "    anndata: 0.10.8" >> versions.yml
