---
name: bioconductor-scannotatr
description: The package comprises a set of pretrained machine learning models to predict basic immune cell types. This enables all users to quickly get a first annotation of the cell types present in their dataset without requiring prior knowledge. scAnnotatR also allows users to train their own models to predict new cell types based on specific research needs.
when_to_use: Use when: 1. Introduction to scAnnotatR; 2. Training basic model; 3. Training child model; Single-cell RNA-seq analysis (scAnnotatR). Not for: Requires R ≥ 4.1 and Bioconductor ≥ 3.16
user-invocable: false
---

# scannotatr

## Workflows

### Train Basic Classifier

Train a new SVM classifier for an independent cell type and evaluate its performance.

```r
library(scRNAseq)
library(scAnnotatR)

# Load dataset and subset
zilionis <- ZilionisLungData()
train_set <- zilionis[, 1:2500]

# Define labels
train_set$B_cell <- ifelse(is.na(train_set$`Most likely LM22 cell type`),
                           'ambiguous',
                           ifelse(train_set$`Most likely LM22 cell type` %in% c('Plasma cells', 'B cells memory', 'B cells naive'),
                                  'B cells', 'others'))

# Define marker genes
selected_marker_genes_B <- c("CD19", "MS4A1", "CD79A")

# Train classifier
classifier_B <- train_classifier(
  train_obj = train_set,
  cell_type = "B cells",
  marker_genes = selected_marker_genes_B,
  assay = 'counts',
  tag_slot = 'B_cell'
)
```
Input: A SingleCellExperiment object with cell type annotations and a vector of marker genes; Output: A trained scAnnotatR classifier object.

### Train Child Classifier

Train a classifier for a cell subtype (child model) that depends on a parent classifier.

```r
library(scAnnotatR)
library(scRNAseq)

# Load parent model
default_models <- load_models("default")

# Prepare training data
zilionis <- ZilionisLungData()
train_set <- zilionis[, 1:100]
train_set$CD4_T <- "others"

# Train child classifier
classifier_CD4 <- train_classifier(
  train_obj = train_set,
  cell_type = "CD4 T cells",
  marker_genes = c("CD4"),
  assay = "counts",
  tag_slot = "CD4_T"
)
```
Input: A training SingleCellExperiment/Seurat object and marker genes; Output: A trained child classifier.

### Standard Workflow

Classify cell types in a single-cell RNA-seq dataset using pretrained models.

```r
library(scAnnotatR)
library(Seurat)

# Load example dataset
data("tirosh_mel80_example")

# Classify cells
seurat.obj <- classify_cells(
  classify_obj = tirosh_mel80_example,
  assay = 'RNA',
  layer = 'counts',
  cell_types = c('B cells', 'NK', 'T cells'),
  path_to_models = 'default'
)

# Visualize
DimPlot(seurat.obj, group.by = "most_probable_cell_type")
FeaturePlot(seurat.obj, features = "B_cells_p")
```
Input: A Seurat or SingleCellExperiment object; Output: An annotated object with predicted cell types and probabilities in metadata.

## When to Use
- To classify cell types in single-cell RNA-seq datasets (Seurat or SingleCellExperiment objects) using pretrained models via `classify_cells`.
- To train custom SVM classifiers for specific cell types using `train_classifier`.
- To load default or custom cell type classification models using `load_models`.

## When NOT to Use
- For clustering or dimensionality reduction of single-cell data (use `Seurat` or `scater` directly).
- When marker genes for the target cell types are completely unknown.

## Data Requirements
- Single-cell RNA-seq data represented as a `Seurat` or `SingleCellExperiment` object.
- For training: Labeled cells with a metadata column specifying cell types (with unknown/unlabeled cells marked as `'ambiguous'`).

## Key Parameters
- **classify_obj**: The input Seurat or SingleCellExperiment object to classify.
- **assay** (`'RNA'` or `'counts'`): The assay to use for classification or training.
- **layer** (`'counts'`): The layer of the assay containing expression data.
- **cell_types**: Vector of cell types to classify (or `'all'`).
- **path_to_models** (`'default'`): Path to load pretrained models or a local database.
- **tag_slot**: The metadata field containing cell type annotations for training.

## Best Practices
- Label unknown or low-confidence cells as `'ambiguous'` during training so they are ignored by `scAnnotatR`.
- Set a seed (`set.seed`) before training to ensure reproducibility when the package automatically balances positive and negative cells.
- Verify classification results by plotting canonical marker genes (e.g., `CD19`, `MS4A1` for B cells) using `FeaturePlot` and comparing with `most_probable_cell_type`.

## Common Pitfalls
- Training fails if the training dataset contains zero cells of the target cell type.
- Using cell type names containing special characters (like `/`, `,`, `-`) which are automatically treated as ambiguous and removed.

## Alternatives
- `SingleR`: For reference-based single-cell cell type annotation.
- `Seurat`: For manual marker-based cell type annotation.
- `scmap`: For projecting cells onto reference datasets.

## Citations
- Zilionis et al., 2019 (for the lung dataset used in training).

## References
- Homepage: bioconductor.org/packages/scannotatr
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/scannotatr/inst/doc/scannotatr.html
