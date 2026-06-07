---
name: bioconductor-gdsfmt
description: Provides a high-level R interface to CoreArray Genomic Data Structure (GDS) data files. GDS is portable across platforms with hierarchical structure to store multiple scalable array-oriented data sets with metadata information. It is suited
when_to_use: Use when: Storing and managing large-scale array-oriented datasets that are much larger than available random-access memory using createfn.gds.; Writing and compressing low-bit integer data (e.g., 2-bit integers for genotypes) using add.gdsn with storage="bit2".; Applying user-defined functions marginally across rows or columns of massive matrices using apply.gdsn.; Reading specific subsets of compressed da. Not for: For small datasets that easily fit in memory; use standard R matrix or data.frame objects because GDS file creation adds unnecessary overhead.; For purely sparse matrix operations without disk-backing; use the Matrix package directly (e.g., dgCMatrix
user-invocable: false
---

# gdsfmt

## When to Use
- Storing and managing large-scale array-oriented datasets that are much larger than available random-access memory using `createfn.gds`.
- Writing and compressing low-bit integer data (e.g., 2-bit integers for genotypes) using `add.gdsn` with `storage="bit2"`.
- Applying user-defined functions marginally across rows or columns of massive matrices using `apply.gdsn`.
- Reading specific subsets of compressed data efficiently using `read.gdsn` or `readex.gdsn`.

## When NOT to Use
- For small datasets that easily fit in memory; use standard R `matrix` or `data.frame` objects because GDS file creation adds unnecessary overhead.
- For purely sparse matrix operations without disk-backing; use the `Matrix` package directly (e.g., `dgCMatrix`), though `gdsfmt` can store them.

## Data Requirements
- Hierarchical structure containing multidimensional arrays, character arrays, or metadata.
- Supports various storage types: integer, floating-point number, character, logical, factor, and packed real numbers.

## Key Parameters
- **val** (NULL): The R variable or data (e.g., matrix, vector) passed to `add.gdsn` to write to the GDS node.
- **storage** ("int"): Storage type in `add.gdsn` (e.g., `"int"`, `"bit2"`, `"float"`, `"packedreal16"`, `"sp.int"`).
- **compress** (""): Compression algorithm specified in `add.gdsn` (e.g., `"ZIP"`, `"LZ4"`, `"LZMA"`, `"ZIP_ra"`).
- **start** (1): Vector specifying the starting position for subset reading/writing in `read.gdsn` or `write.gdsn`.
- **count** (-1): Vector specifying the size of the dimension to read/write in `read.gdsn` or `write.gdsn` (-1 means the full size of that dimension).
- **margin** (1): Indicates applying a function row-by-row (1) or column-by-column (2) in `apply.gdsn`.

## Best Practices
- Always close the GDS file using `closefn.gds` to ensure data integrity and release the file handle.
- When the dataset is larger than system memory, pre-define the dimension size in `add.gdsn` using `valdim` and write data in chunks using `write.gdsn`.
- If a compression algorithm is specified in `add.gdsn`, use `append.gdsn` instead of `write.gdsn` because data must be compressed sequentially.
- Use `digest.gdsn` to create hash function digests (e.g., md5) to verify data integrity.

## Common Pitfalls
- **Corrupted or locked files**: Failing to close a GDS file after writing. *Fix*: Always call `closefn.gds` when finished with the file handle.
- **Writing to compressed nodes incorrectly**: Attempting to use `write.gdsn` on a node created with `compress="ZIP"`. *Fix*: Call `append.gdsn` instead, as compressed data must be written sequentially, followed by `readmode.gdsn`.
- **Memory exhaustion**: Trying to load a massive GDS node entirely into memory with `read.gdsn`. *Fix*: Specify `start` and `count` arguments in `read.gdsn` or use `readex.gdsn` to read only a subset of the data.

## Alternatives
- `HDF5Array`: For standard HDF5-backed array storage, because it integrates deeply with the `DelayedArray` ecosystem.
- `rhdf5`: For general-purpose HDF5 file manipulation, whereas `gdsfmt` is specifically tailored with genomic-specific compression (like 2-bit).
- `bigmemory`: For shared-memory matrix representations without hierarchical node structures.

## Citations
- Zheng X, et al. (2012). "A high-performance computing toolset for relatedness and principal component analysis of SNP data." *Bioinformatics*.

## References
- Homepage: bioconductor.org/packages/gdsfmt
- Vignette: vignette_0_727c94f6.txt
