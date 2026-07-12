Continue a previous chemCPA setup/debugging session on a new GPU machine.

Repository:
- theislab/chemCPA
- current branch: env
- default branch: main

Goal:
- Get the upstream method to run as intended.
- Do not build wrappers, helper runners, or fork-only “software around” the repo.
- Avoid functionally modifying upstream code.
- Prefer small local setup/workarounds and README notes.
- If a workaround is needed, prefer not touching upstream code. If a tiny patch is unavoidable, keep it minimal and clearly justified.

Important context from the previous machine:
1. I do NOT want run_notebooks_fork.py, run_train_fork.sh, smoke_check.sh, Dockerfile.fork, environment.fork.yml, requirements.preprocess-gpu.fork.txt, or similar helper-layer files. Those were temporary scaffolding and should not be recreated.
2. There were local uncommitted cleanup changes on the old machine. A fresh clone of branch env may not include them. First inspect git status and diff against origin/env and main before doing anything.
3. The old machine hit a CUDA OOM in preprocessing step 5. I am moving to a larger GPU machine and either want to continue from existing generated artifacts if they were copied over, or rerun cleanly from scratch if not.

What was learned already:
1. The repo expects data/artifacts under project_folder. On local clones, project_folder may be a broken lab-specific symlink. Replace it locally with a writable directory or symlink before preprocessing. This is a local setup step and should not be committed.
2. The upstream preprocessing runner preprocessing/run_notebooks.py is not reliable when datasets are missing, because it launches child scripts through pipes and upstream download prompts can fail with EOFError. So preprocessing should be run manually from an interactive terminal, script by script.
3. preprocessing/4_sciplex_SMILES.py needs to be run twice: once with LINCS_GENES = True and once with LINCS_GENES = False.
4. preprocessing/5_sciplex_ood_splits.py requires RAPIDS on GPU. The working install command we found for Python 3.9 / CUDA 11 was:
   python -m pip install --extra-index-url https://pypi.nvidia.com 'rapids-singlecell[rapids11]==0.10.10'
5. preprocessing/6_baseline_sciplex_dataset.py expects:
   project_folder/datasets/sciplex_complete_middle_subset_lincs_genes.h5ad
   but step 5 writes:
   project_folder/datasets/sciplex_complete_middle_subset_lincs_genes_v2.h5ad
   Local workaround: create a symlink before step 6 if needed.
6. On the old machine, PyTorch saw the GPU fine. The blocker was step-5 CUDA memory, not lack of CUDA.
7. Importing sfaira emits TensorFlow/CUDA startup noise. That noise is not itself a failure and should not be “fixed” with new wrapper software.

Local cleanup state from the previous machine:
1. The intent was to keep only minimal environment-layer changes plus README notes, and to avoid branch-specific behavior changes where possible.
2. README had a small “Local checkout notes” section documenting:
   - how to replace project_folder locally
   - why to run preprocessing manually in an interactive terminal
   - the RAPIDS install command for step 5
   - that step 4 must be run twice
   - the local symlink workaround before step 6
   - a training invocation workaround if config/main.yaml still points to a missing dataset config
3. The old machine was in the middle of trimming env-branch behavior diffs. In particular, inspect these files carefully on the new clone:
   - chemCPA/model.py
   - chemCPA/train_hydra.py
   - config/main.yaml
   The desired direction is: keep only what is truly required to run, avoid behavioral changes, and prefer an explicit training command-line override over changing repo behavior.
4. The only environment-layer changes that looked genuinely useful to keep were in environment.yml and Dockerfile.

Environment facts already verified:
1. These compatibility pins/additions were needed in the working local env:
   - numpy=1.26.4
   - scipy=1.12.0
   - lightning=2.0.9.post0
   - torchmetrics=1.4.0.post0
   - intel-openmp=2022.1.0
   - mkl=2022.1.0
   - descriptastorus=2.7.0.4
   - rich=13.9.4
   - sympy=1.12
   - gdown=5.2.0
   - wandb=0.16.5
2. Pip-only packages that were needed:
   - pyarrow==16.0.0
   - tensorflow==2.18.0
   - dgllife==0.3.2
   - scgen==2.1.0
   - sfaira==0.3.12
3. Dockerfile should follow environment.yml as the source of truth instead of re-installing those extras separately afterward.

What I want you to do first on the new machine:
1. Inspect the fresh clone and tell me which of the old machine’s local cleanup changes are absent.
2. Recreate only the minimal state needed to run the repo locally with upstream behavior preserved.
3. Prefer README instructions and local setup steps over new scripts/wrappers.
4. Tell me exactly where to continue from:
   - if the generated datasets from steps 1 to 4 are already present, resume from step 5
   - otherwise give me the exact manual preprocessing order to rerun interactively

Manual preprocessing order if rerunning from scratch:
1. python preprocessing/1_lincs.py
2. python preprocessing/2_lincs_SMILES.py
3. python preprocessing/3_lincs_sciplex_comb.py
4. python preprocessing/3_lincs_sciplex_gene_matching.py
5. run preprocessing/4_sciplex_SMILES.py with LINCS_GENES = True
6. run preprocessing/4_sciplex_SMILES.py again with LINCS_GENES = False
7. install RAPIDS:
   python -m pip install --extra-index-url https://pypi.nvidia.com 'rapids-singlecell[rapids11]==0.10.10'
8. python preprocessing/5_sciplex_ood_splits.py
9. if needed, create the local compatibility symlink for step 6
10. python preprocessing/6_baseline_sciplex_dataset.py
11. python preprocessing/7_compute_embeddings.py

Training note:
- If config/main.yaml still points to a missing dataset config in this checkout, prefer:
  python chemCPA/train_hydra.py dataset=sciplex
  instead of editing behavior unless absolutely necessary.

Constraints:
- Minimal diffs.
- No helper wrappers.
- No functional fork behavior changes unless strictly required.
- Do not revert unrelated user changes.
- End by telling me exactly where to continue from on this new machine.