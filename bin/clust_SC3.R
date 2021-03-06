#!/usr/bin/env Rscript

# Run SC3 clustering. For integrated expression matrices. 

suppressPackageStartupMessages(library("optparse"))

option_list = list(
  make_option(
    c("-i", "--input_object"),
    action = "store",
    default = NA,
    type = 'character',
    help = 'Path to rds input file'
  ),
  make_option(
    c("-f", "--input_features"),
    action = "store",
    default = NA,
    type = 'character',
    help = 'Features names subsetted by coefficient of variation'
  ),
  make_option(
    c("-a", "--assay_name"),
    action = "store",
    default = "logcounts",
    type = 'character',
    help = 'Counts assay to add to the h5ad object'
  ),
  make_option(
    c("-c", "--corrected_assay"),
    action = "store",
    default = "corrected",
    type = 'character',
    help = 'Corrected counts assay name'
  ),
  make_option(
    c("-m", "--method"),
    action = "store",
    default = NA,
    type = 'character',
    help = 'Batch correction method the input file comes from'
  ),
  make_option(
    c("-t", "--celltype_key"),
    action = "store",
    default = "cell_type1",
    type = 'character',
    help = 'Cell type key in cell metadata'
  ),
  make_option(
    c("-b", "--biology"),
    action = "store",
    default = FALSE,
    type = 'logical',
    help = 'Wether to calculate biological features based on the identified cell clusters (DE genes, marker genes etc).'
  ),
  make_option(
    c("-s", "--save_SCE"),
    action = "store",
    default = NA,
    type = 'character',
    help = 'Output path for SC3 SCE object'
  ),
  make_option(
    c("-o", "--output_clusters"),
    action = "store",
    default = NA,
    type = 'character',
    help = 'Output dataframe with cluster annotation'
  ), 
  make_option(
    c("-r", "--output_rowdata"),
    action = "store",
    default = NA,
    type = 'character',
    help = 'Output dataframe with gene-based analysis'
  )
)

opt <- parse_args(OptionParser(option_list=option_list))

suppressPackageStartupMessages(library(SingleCellExperiment))


# FUNCTIONS #

# Remove items with zero variance
rm_zero_var <- function(dataset, assay, axis){
  if(!(axis %in% c(1, 2))){stop("Axis provided must be 1 or 2!")}
  ax_zero_var <- as.numeric(which(apply(assay(dataset, assay), axis, var) == 0))
  print(paste0("Removing ", length(ax_zero_var), " items with zero variance in axis = ", axis))
  if(length(ax_zero_var) > 0){
    if(axis == 1) dataset <- dataset[-ax_zero_var, ]
    if(axis == 2) dataset <- dataset[, -ax_zero_var]
  } 
  dataset
}
# build custom SCE object
exp_sce <- function(dataset, assay_name){
  counts_mat <- as.matrix(assay(dataset, assay_name))
  col_data <- dataset@colData
  sce <- SingleCellExperiment(assays = list(logcounts = counts_mat),
                              colData = col_data)
  sce
}

# common modifications applied to SCE object
common_modif_sc3 <- function(sce){
  rowData(sce)$feature_symbol <- rownames(sce)
  counts(sce) <- logcounts(sce)
  sce
}
#run SC3 function
run_SC3 <- function(sce, celltype_key, biology){
  k <- length(table(sce[[celltype_key]])[table(sce[[celltype_key]]) > 0])
  k_vec <- c(k)
  print(paste0("k values on clustering:", k_vec))
  # biology = T enables calculation of DE genes, and marker genes
  sce_sc3 <- SC3::sc3(sce, ks = k_vec, gene_filter = FALSE, biology = FALSE)
  # Extract annotation of NAs-assigned cells (when dataset > 5000 cells)
  if(ncol(sce_sc3) > 5000){
	  print("Dataset with > 5000 cells. Running SVM to predict labels of all the other cells.")
          sce_sc3 <- sc3_run_svm(sce_sc3, ks = k)
  }
  return(sce_sc3)
}

# args
assay_name <- opt$assay_name
corrected_assay <- opt$corrected_assay
method <- opt$method
if(is.null(method) || is.na(method)){ stop("Please provide the batch correction method the input file comes from") }
# consider only valid methods
if(!(method %in% c("logcounts", "Logcounts", "mnnCorrect", "mnncorrect", "limma", "Limma", "ComBat", "combat", "Seurat3", "seurat3", "Scanorama", "scanorama"))){
  stop("Only batch correction methods correcting counts matrix can be clustered by SC3") }
celltype_key <- opt$celltype_key
biology <- opt$biology

print("A")
# read input files
dataset <- readRDS(opt$input_object)
print("B")
features <- as.character(read.csv(opt$input_features, row.names =1, header = T)$x)
print("C")
# subset input object by features
dataset <- dataset[features, ]

# Select assay to cluster depending on method
if( method %in% c("Logcounts", "logcounts")){ clust_assay <- assay_name 
  }else{ clust_assay <- corrected_assay }
## 1. Remove items with zero variance (this introduces NA values in correlation matrix and clustering is aborted!)
# Remove cells with zero variance
dataset <- rm_zero_var(dataset, assay = clust_assay, axis = 1)
# Remove genes with zero variance
dataset <- rm_zero_var(dataset, assay = clust_assay, axis = 2)
print("D")

# 1. Build SC3 custom SCE object
if(method %in% c("logcounts", "Logcounts")){
  sce <- exp_sce(dataset, assay_name = assay_name)
  }else{
  sce <- exp_sce(dataset, assay_name = corrected_assay)
}
print("E")
# 2. Add modifications to make SCE object required by SC3
sce <- common_modif_sc3(sce)
print("F")
# 3. Run SC3
suppressPackageStartupMessages(library(SC3))
sce_sc3 <- run_SC3(sce, celltype_key, biology = biology)
print("G")
# 3.2 save SC3 SCE object
#saveRDS(sce_sc3, file = opt$save_SCE)
print("H")
# 4. Extract cluster annotation
sc3_clust_annot <- sce_sc3@colData[, grep("sc3_", colnames(sce_sc3@colData))]
print(head(sc3_clust_annot))
# 5. Save cluster annotation
write.csv(sc3_clust_annot, file = opt$output_clusters, row.names = colnames(sce_sc3))
print("SC3 Cluster annotation saved")

if(biology == TRUE) {
  # Extract gene 
  gene_annot <- rowData(sce_sc3)
  # Save 
  write.csv(gene_annot, file = opt$output_rowdata, row.names = rownames(sce_sc3))
  print("SC3 Gene annotation saved")
}
