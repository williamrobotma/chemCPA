# Predicting Cellular Responses to Novel Drug Perturbations at a Single-Cell Resolution

Code accompanying the [NeurIPS 2022 paper](https://neurips.cc/virtual/2022/poster/53227) ([PDF](https://openreview.net/pdf?id=vRrFVHxFiXJ)).

![architecture of CCPA](docs/chemCPA.png)

Our talk on chemCPA at the M2D2 reading club is available [here](https://m2d2.io/talks/m2d2/predicting-single-cell-perturbation-responses-for-unseen-drugs/).
A [previous version](https://arxiv.org/abs/2204.13545) of this work was a spotlight paper at ICLR MLDD 2022.
Code for this previous version can be found under the `v1.0` git tag.

## Codebase overview

- `chemCPA/`: contains the code for the model, the data, and the training loop.
- `embeddings`: There is one folder for each molecular embedding model we benchmarked. Each contains an `environment.yml` with dependencies. We generated the embeddings using the provided notebooks and saved them to disk, to load them during the main training loop.
- `experiments`: Each folder contains a `README.md` with the experiment description, a `.yaml` file with the seml configuration, and a notebook to analyze the results.
- `notebooks`: Example analysis notebooks.
- `preprocessing`: Notebooks for processing the data. For each dataset there is one notebook that loads the raw data.
- `tests`: A few very basic tests.

All experiments where run through [seml](https://github.com/TUM-DAML/seml).
The entry function is `ExperimentWrapper.__init__` in `chemCPA/seml_sweep_icb.py`.
For convenience, we provide a script to run experiments manually for debugging purposes at `chemCPA/manual_seml_sweep.py`.
The script expects a `manual_run.yaml` file containing the experiment configuration.

All notebooks also exist as Python scripts (converted through [jupytext](https://github.com/mwouts/jupytext)) to make them easier to review.

## Getting started

#### Environment
The easiest way to get started is to use a docker image we provide
```
docker run -it -p 8888:8888 --platform=linux/amd64 registry.hf.space/b1ro-chemcpa:latest
```
this image contains the source code and all dependencies to run the experiments.
By default it runs a jupyter server on port 8888.

Alternatively you may clone this repository and setup your own environment by running:

```python
conda env create -f environment.yml
python setup.py install -e .
```

#### Datasets
The datasets are not included in the docker image, but get automatically downloaded when you run the notebooks that require them. The datasets may alternatively be downloaded manually using the python tool in the `raw_data/dataset.py` folder. Usage is:
```
python raw_data/dataset.py --list
python raw_data/dataset.py --dataset <dataset_name>
```

or you may use the following links:
- [weight checkpoints](https://f003.backblazeb2.com/file/chemCPA-models/chemCPA_models.zip)
- [hyperparameter configuration](https://f003.backblazeb2.com/file/chemCPA-models/finetuning_num_genes.json)
- [raw datasets](https://dl.fbaipublicfiles.com/dlp/cpa_binaries.tar)
- [processed datasets](https://f003.backblazeb2.com/file/chemCPA-datasets/)
- [embeddings](https://drive.google.com/drive/folders/1KzkhYptcW3uT3j4GQpDdAC1DXEuXe49J?usp=share_link)

Some of the notebooks use a *drugbank_all.csv* file, which can be downloaded from [here](https://go.drugbank.com/) (registration needed).

#### Data preparation
To train the models, first the raw data needs to be processed.
This can be done by running the notebooks inside the `preprocessing/` folder in a sequential order.
Alternatively, you may run 

```
python preprocessing/run_notebooks.py
```
A description of the preprocessing steps is given in the `preprocessing/README.md` file and in the headers
of individual notebooks. Section 4 of the paper is also highly relevant.

##### Local checkout notes

This branch keeps only a small set of local environment fixes in `environment.yml`: compatibility pins for the working Torch/DeepChem/Seml stack, plus `gdown`, `descriptastorus`, and `sfaira`, which upstream Docker installed after environment creation.

The repository expects all generated datasets, embeddings, and checkpoints under `project_folder/`. In this checkout that path may be a lab-specific symlink that is not valid locally. If so, replace it locally with a writable directory or symlink before preprocessing. For example:

```bash
rm project_folder
mkdir -p /path/to/chemcpa-data
ln -s /path/to/chemcpa-data project_folder
```

Keep that as a local setup step; do not commit the replacement.

If any required dataset is still missing, run the preprocessing scripts manually from an interactive terminal instead of relying on `python preprocessing/run_notebooks.py`, because the upstream runner launches child scripts through pipes and download prompts may fail with `EOFError`.

For the GPU preprocessing step in `preprocessing/5_sciplex_ood_splits.py`, install the RAPIDS dependency separately before running that script:

```bash
python -m pip install --extra-index-url https://pypi.nvidia.com 'rapids-singlecell[rapids11]==0.10.10'
```

`preprocessing/4_sciplex_SMILES.py` needs to be run twice, once with `LINCS_GENES = True` and once with `LINCS_GENES = False`.

`preprocessing/6_baseline_sciplex_dataset.py` expects `project_folder/datasets/sciplex_complete_middle_subset_lincs_genes.h5ad`, while step 5 writes `sciplex_complete_middle_subset_lincs_genes_v2.h5ad`. If needed, create a local compatibility symlink before running step 6:

```bash
ln -s sciplex_complete_middle_subset_lincs_genes_v2.h5ad project_folder/datasets/sciplex_complete_middle_subset_lincs_genes.h5ad
```

In this checkout, training should be launched with an explicit dataset override because `config/main.yaml` points to a missing dataset config:

```bash
python chemCPA/train_hydra.py dataset=sciplex
```

#### Training the models
Run 
```
python chemCPA/train_hydra.py
```

## Citation

You can cite our work as:

```
@inproceedings{hetzel2022predicting,
  title={Predicting Cellular Responses to Novel Drug Perturbations at a Single-Cell Resolution},
  author={Hetzel, Leon and Böhm, Simon and Kilbertus, Niki and Günnemann, Stephan and Lotfollahi, Mohammad and Theis, Fabian J},
  booktitle={NeurIPS 2022},
  year={2022}
}
```
