# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

<!-- FORK(williamrobotma/chemCPA): file added by this fork (not in upstream theislab/chemCPA). -->

chemCPA predicts single-cell transcriptional responses to drug perturbations
(NeurIPS 2022). This checkout is a fork focused on getting the model to run and
reproduce; read the caveats — several documented paths in the upstream README are
stale here.

## Start here

- **Docker "out of the box" does not work.** The README's
  `docker run registry.hf.space/b1ro-chemcpa:latest` cannot succeed: the Hugging
  Face Space build is OOM-killed (`exit code 137`), so no image is ever published
  to that registry. **Build locally instead.** Full explanation and the
  environment/config decisions still open for the target machine are in
  [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) — read it before touching the
  Dockerfile or environment files.
- **The working training entry point is `chemCPA/train_hydra.py` (Hydra).** The
  README and `manual_seml_sweep.py` reference `chemCPA/seml_sweep_icb.py` /
  `chemCPA.experiments_run` (the seml/sacred path) — **both files are absent in
  this checkout**, so that path is broken. Use the Hydra entry point.

## Environment setup

Two mutually-exclusive paths; pick one.

**Docker (reproducible, GPU required):**
```bash
docker build -t chemcpa .
docker run -it --gpus all -p 8888:8888 chemcpa   # serves Jupyter Lab on :8888
```
Caveat: the CUDA 11.3 base image and `device="cuda"` hardcoded in
`chemCPA/lightning_module.py` mean an NVIDIA GPU + `nvidia-container-toolkit` are
required to run anything; there is no CPU fallback.

**Conda / bare metal:**
```bash
./bootstrap_local.sh [/path/to/data]   # symlinks project_folder, creates env, installs RAPIDS
# or manually:
conda env create -f environment.yml && pip install -e .
```
Caveat: `environment.yml` (loose, torch 1.12 / CUDA 11.3) and `environment.yaml`
(a full hash-pinned export, torch 2.1 / CUDA 12.1) describe **different** stacks
and the pin decision is deliberately unresolved — see `TROUBLESHOOTING.md` §2
before standardizing on either.

## Data layout

All datasets, embeddings, and checkpoints resolve under `project_folder/` via
`chemCPA/paths.py` (`DATA_DIR`, `EMBEDDING_DIR`, `CHECKPOINT_DIR`, `WB_DIR`).
Caveat: in a fresh clone `project_folder` is a **lab-specific symlink that is not
valid locally** — replace it with a writable dir/symlink (this is what
`bootstrap_local.sh` does) and do not commit the replacement. Datasets
auto-download when notebooks need them, or fetch manually:
`python raw_data/datasets.py --list` / `--dataset <name>`.

## Common commands

```bash
# Tests
pytest                                        # full suite
pytest tests/test_dosers.py::test_drug_embedding   # single test
```
Caveat: `tests/test_dosers.py` is self-contained, but `test_embedding.py` and
`test_dataset.py` load the trapnell subset `.h5ad` from `project_folder/datasets`
and will error without it.

```bash
# Train (Hydra; default dataset config is `sciplex`)
python chemCPA/train_hydra.py
python chemCPA/train_hydra.py dataset=lincs   # override; names are files in config/dataset/
```
Caveat: `config/main.yaml`'s dataset default was repointed from the upstream
`sciplex_lincs_genes` (which has no config file and errors on startup) to the
existing `sciplex`. Available overrides are the filenames in `config/dataset/`.

```bash
# Preprocessing (run scripts in numeric order)
python preprocessing/4_sciplex_SMILES.py      # edit LINCS_GENES flag, run once True + once False
```
Caveat: prefer running preprocessing scripts individually from an interactive
terminal — `preprocessing/run_notebooks.py` pipes child scripts and download
prompts can fail with `EOFError`. Step 5 needs a separate RAPIDS install
(`bootstrap_local.sh` handles it). See the README "Local checkout notes".

```bash
# Formatting (enforced via pre-commit: black -l 120, isort black profile, jupytext)
pre-commit run --all-files
```

## Architecture

Training data flows: **`.h5ad` → data loaders → `PerturbationDataModule` →
`ChemCPA` LightningModule → `ComPert` model**.

- `chemCPA/model.py` — `ComPert`, the CPA autoencoder: an `MLP` encoder/decoder
  with adversarial classifiers that disentangle drug and covariate signals from
  the basal cell state, a `GeneralizedSigmoid` doser for dose-response, and
  count losses (`NBLoss`, `GaussianLoss`, `FocalLoss`). This is pure PyTorch.
- `chemCPA/lightning_module.py` — `ChemCPA`, a Lightning wrapper around `ComPert`
  using **manual optimization** (`automatic_optimization = False`) to alternate
  the model and adversary steps. It builds drug embeddings at init via
  `get_chemical_representation`.
- `chemCPA/embedding.py` — maps SMILES to precomputed molecular embeddings. The
  `embeddings/` directory has one subfolder per benchmarked embedding model, each
  with its own `environment.yml` and notebooks; embeddings are generated offline
  and loaded at train time (not computed in the main loop).
- `chemCPA/data/` — `data.py:load_dataset_splits` reads `.h5ad` (genes, drugs,
  covariates, splits) into the `Dataset`/`SubDataset` classes defined in
  `data/dataset/dataset.py`; `perturbation_data_module.py` wraps them in a
  `LightningDataModule` with a `custom_collate`.
- `chemCPA/train.py` — evaluation utilities (`compute_r2`,
  `evaluate_disentanglement`, `evaluate_r2`) used by the Lightning module.
- `config/` — Hydra config tree. `main.yaml` composes `model` / `dataset` /
  `training` / `wandb` / `hydra` groups; the finetune vs. pretrain distinction and
  the embedding choice are selected through `config/model/`.

Fine-tuning flow: `train_hydra.py` can load a pretrained checkpoint and remap it
onto a new dataset — it strips drug-specific weights (embeddings, adversary,
dosers) to retrain from scratch and **re-indexes covariate embeddings by cell-type
name** so a model pretrained on one covariate set transfers to another.

## Conventions

- **Tag every fork change.** This is the `williamrobotma/chemCPA` fork of upstream
  `theislab/chemCPA`. Any edit to a file that also exists upstream must carry a
  `FORK(williamrobotma/chemCPA):` marker at the change site — `# FORK(williamrobotma/chemCPA): <reason>`
  in code/YAML/shell/gitignore, `<!-- FORK(williamrobotma/chemCPA): <reason> -->`
  in Markdown. Wholly-new fork files carry a single such note at the top instead
  of per-line tags; files restored verbatim from upstream (e.g. `packages.txt`,
  `on_startup.sh`) stay untagged. Keep it to one tag per change site — do not
  spread tags onto unrelated lines. `grep -rn "FORK(williamrobotma/chemCPA)" .`
  lists every fork change.
- **Mark restored-upstream files too.** Files brought back verbatim from the
  upstream Docker build context (not authored by the fork) carry a
  `RESTORED-UPSTREAM(williamrobotma/chemCPA):` note instead of a `FORK` tag —
  e.g. `on_startup.sh`. Exception: `packages.txt` is consumed by
  `xargs ... apt-get install`, so a `#` line would be parsed as a package name and
  break the build; it stays uncommented and is recorded as restored-upstream here
  in prose. `grep -rn "RESTORED-UPSTREAM(williamrobotma/chemCPA)" .` lists the rest.
- Notebooks are **jupytext-paired**: every `.ipynb` has a `.py` (percent format)
  counterpart. Edit the `.py`; the pre-commit jupytext hook keeps them in sync.
  Review `.py` versions, not the large `.ipynb` files.
- Stale/superseded experiments from an earlier attempt live on the `origin/env`
  branch (hand-pinned env, formatting-only churn) and are intentionally kept out
  of this branch — see `TROUBLESHOOTING.md` §6–§8 rather than resurrecting them.
