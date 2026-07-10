# chemCPA — Docker & Environment Troubleshooting Report

> Branch: `claude/chemcpa-docker-troubleshoot-rywrjk` (branched from `main` @ `43e830e`)
> Purpose: hand-off notes for continuing the reproduction attempt on the "big"
> machine (500 GB RAM, 4× RTX 3090, 64 logical cores). This file records *why*
> the "out of the box" Docker path fails and what the prior `env`-branch attempt
> did, so the next attempt does not re-chase dead ends.

## TL;DR

- The README's "easiest" path — `docker run ... registry.hf.space/b1ro-chemcpa:latest` —
  **cannot work for anyone**: the Hugging Face Space build fails with
  `exit code 137` (**OOM-killed**), so **no image is ever published** to that
  registry tag. A pull returns 404 / `manifest unknown`, not an auth error.
- This is a **Hugging Face build-sandbox memory limit**, not a problem with your
  hardware. On the big machine there is no OOM. The registry image is simply a
  non-asset — build locally instead of pulling.
- The registry-outage forum thread
  (<https://discuss.huggingface.co/t/registry-hf-space-down/138590>) is a *real*
  phenomenon but is **not** the cause here — the image never existed to begin with.
- A local Docker build was one step away the whole time: the GitHub clone is
  missing two trivial build-context files (`packages.txt`, `on_startup.sh`) that
  exist in the Space but were never committed to the repo.

## 1. Why the "out of the box" Docker command fails

`README.md` recommends:

```
docker run -it -p 8888:8888 --platform=linux/amd64 registry.hf.space/b1ro-chemcpa:latest
```

`registry.hf.space` is Hugging Face's registry for images built automatically
from Spaces. The image only exists if the Space `b1ro/chemCPA` builds
successfully. It does **not**:

- The Space is in a permanent **Build error** state.
- Build log: `Job failed with exit code: 137`.
- **Exit 137 = 128 + SIGKILL(9) = OOMKilled.** The build container exceeded the
  HF build sandbox's RAM ceiling and was killed.

The OOM almost certainly occurs at the `conda env create -f environment.yml`
step (`Dockerfile` lines ~104–108). The dependency solve for that environment
(pytorch + tensorflow + dgl-cuda + deepchem + rdkit + umap-learn + datashader +
bokeh + holoviews + …) on top of the `nvidia/cuda:11.3.1-devel` base is
memory-hungry, and a free/basic Space's builder cannot hold it.

**Consequence:** because the build never completes, HF never pushes an image to
`registry.hf.space/b1ro-chemcpa:latest`. `docker pull` therefore fails with
`manifest unknown` / 404. Registry authentication and the registry outage are
red herrings for this Space — there is nothing to pull.

## 2. Two environment files describe two different stacks

The repo ships **both** files, and they are **not** the same environment:

| | `environment.yml` (656 B, loose) | `environment.yaml` (15 KB, full export) |
|---|---|---|
| conda env name | `chemCPA` | `chemCPA-env` |
| Python | 3.9 | 3.10 |
| Torch / CUDA | **1.12.1 / cudatoolkit 11.3** | **2.1.0 / cuda 12.1 / cudnn 8.9** |
| Lightning | unpinned | 2.2.4 |
| rdkit | 2021.09.2 | 2022.09.5 |
| pinning | loose (names only) | fully hash-pinned lockfile |

- The **Dockerfile uses `environment.yml`** (the loose, torch-1.12/CUDA-11.3 file).
- `environment.yaml` is a **complete, hash-pinned conda export** — i.e. a real
  machine's frozen working environment, on a *newer* torch-2.1/CUDA-12.1 stack.
  Nothing in the repo references it; it appears to be an orphaned lockfile.
- The `env` branch pinned a **third** combination by hand (torch 1.12.1 +
  tensorflow 2.18 + lightning 2.0.9), matching neither file.

**Recommendation for the big machine:** diff whatever you build against
`environment.yaml`. A fully-pinned lockfile solves deterministically and is the
closest artifact to "a machine this actually ran on." Caveats: it is on
Python 3.10 / torch 2.1 (may be a later contributor's env, not necessarily
validated against the released checkpoints), whereas torch 1.12 / CUDA 11.3 is
more faithful to the 2022 paper era. Decide deliberately which base to standardize on.

## 3. Missing Docker build-context files (blocks a local build)

`Dockerfile` mounts two files that are **present in the HF Space but were never
committed to the GitHub repo**:

```dockerfile
RUN --mount=target=/root/packages.txt,source=packages.txt   ...   # line ~81
RUN --mount=target=/root/on_startup.sh,source=on_startup.sh ...   # line ~86
```

`git log --all -- packages.txt on_startup.sh` returns nothing → they were never
in the repo history. A local `docker build .` therefore fails with
`packages.txt: not found` before it even reaches the conda step.

Their exact contents (from the Space) are trivial and can be recreated verbatim:

**`packages.txt`**
```
tree
```

**`on_startup.sh`**
```bash
#!/bin/bash
# Write some commands here that will run on root user before startup.
# For example, to clone transformers and install it in dev mode:
# git clone https://github.com/huggingface/transformers.git
# cd transformers && pip install -e ".[dev]"
```

With those two files added, on the big machine:

```bash
docker build -t chemcpa .
docker run -it --gpus all -p 8888:8888 chemcpa   # --gpus all for the 3090s
```

This produces the authors' *intended* torch-1.12 / CUDA-11.3 environment
reproducibly, without any dependency on `registry.hf.space`.

## 4. Config bug: `config/main.yaml` points to a non-existent dataset config

`config/main.yaml` defaults to:

```yaml
defaults:
  - dataset: sciplex_lincs_genes
```

but `config/dataset/` contains no `sciplex_lincs_genes.yaml` (only `sciplex.yaml`,
`lincs.yaml`, `sciplex_2000_genes.yaml`, `lincs_2000_genes.yaml`, `biolord*.yaml`,
`combinatorial.yaml`, `default.yaml`). Hydra errors on startup.

Note `config/model/embedding/sciplex_lincs_genes.yaml` *does* exist — the authors
appear to have renamed/dropped the **dataset** variant and left `main.yaml` stale.

- The `env` branch **worked around** this by requiring a CLI override:
  `python chemCPA/train_hydra.py dataset=sciplex`.
- The **real fix** is one file: either add `config/dataset/sciplex_lincs_genes.yaml`
  or change the default in `main.yaml` to an existing config.

## 5. Import inconsistency in `train_hydra.py`

`chemCPA/train_hydra.py` uses a bare import:

```python
from lightning_module import ChemCPA   # bare top-level name
```

while `load_lightning.py` correctly uses the package-qualified form:

```python
from chemCPA.lightning_module import ChemCPA
```

The bare form only resolves because `python chemCPA/train_hydra.py` puts
`chemCPA/` on `sys.path[0]`. It breaks under `python -m chemCPA.train_hydra` or
if the module is imported elsewhere. Harmless for the current invocation, but
worth normalizing to `chemCPA.lightning_module`.

## 6. Inventory of the `env` branch (3 commits) + proposed merge plan

`env` branch commits: `validated and set up env` → `2` → `added bootstrap to continue`.
Diff vs `main` touches 7 files. Triage for this new attempt:

| File | What it does | Verdict |
|---|---|---|
| `bootstrap_local.sh` (new) | local setup: project_folder symlink, conda env, `pip install -e .`, RAPIDS, `skip-worktree` | **Bring in** — directly useful on the big machine |
| `README.md` "Local checkout notes" | documents project_folder, headless preprocessing (`EOFError`), RAPIDS step 5, step5→6 filename symlink, `dataset=sciplex` override | **Bring in** (lightly edited) — valuable, but note it documents *workarounds* (§4) |
| `preprocessing/4_sciplex_SMILES.py` | removes notebook-only imports (`IPythonConsole`, `Draw`) so it runs headless; hardcodes `LINCS_GENES = True` | **Split**: bring the headless import cleanup; the `LINCS_GENES` hardcode is a workaround (must be run both ways — make it a CLI/env toggle instead) |
| `.gitignore` | adds `/.ruff_cache/` | **Bring in** — trivial |
| `Dockerfile` | folds post-create pip installs (sfaira, descriptastorus, gdown, jupytext) into `environment.yml`; keeps `pip install -e .` | **Conditional** — sensible cleanup, but coupled to the env-file decision (§2) |
| `environment.yml` | hand-pinned torch 1.12.1 + tf 2.18 + lightning 2.0.9 + numpy 1.26.4 (a *third* stack) | **Quarantine / reconcile** — decide against `environment.yaml` lockfile first (§2). Latent risk: pip `tensorflow==2.18.0` expects CUDA 12/cuDNN 9 but the env is CUDA 11.3 → GPU TF won't work (fine only if TF is CPU-only / transitive) |
| `chemCPA/train_hydra.py` | ~90% ruff/black **reformatting noise**; one real import reorder; keeps the bare import (§5) | **Drop the churn** — do not carry pure formatting; adopt repo-wide formatting separately if wanted |

## 7. Recommended next steps on the big machine

1. **Pick an environment base deliberately** (§2): the pinned `environment.yaml`
   lockfile (torch 2.1 / py3.10) vs. the paper-era torch 1.12 / CUDA 11.3. Diff
   the `env`-branch hand-pins against both before committing to one.
2. **Restore a local Docker build as the reproducible fallback** (§3): add
   `packages.txt` + `on_startup.sh`, `docker build`, `docker run --gpus all`.
3. **Fix, don't work around, the config bug** (§4): add the missing dataset
   config or correct `main.yaml`.
4. **Bring in the genuinely useful `env` work** (§6): `bootstrap_local.sh`, the
   local README notes, the headless preprocessing import fixes.
5. **Leave the stale bits out** (§6): the formatting-only churn in
   `train_hydra.py`, and the hardcoded `LINCS_GENES` toggle.
</content>
</invoke>
