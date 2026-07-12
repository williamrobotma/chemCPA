#!/usr/bin/env bash
# Local-only bootstrap for a fresh machine.
set -euo pipefail

cd "$(dirname "$0")"

usage() {
    cat <<'EOF'
Usage: ./bootstrap_local.sh [data_root]

Local-only setup for this checkout:
- replace project_folder with a writable local symlink
- create the chemCPA conda environment if missing
- install the repo in editable mode
- install the RAPIDS dependency needed for preprocessing step 5
- mark project_folder skip-worktree locally so git ignores the local symlink target
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ "$#" -gt 1 ]]; then
    usage >&2
    exit 1
fi

data_root="${1:-../chemCPA-data}"
if [[ "$data_root" != /* ]]; then
    data_root="$PWD/$data_root"
fi

mkdir -p "$data_root"/{datasets,embeddings,checkpoints,figures,wandb,binaries}

if [[ -L project_folder || ! -e project_folder ]]; then
    rm -f project_folder
    ln -s "$data_root" project_folder
elif [[ -d project_folder ]]; then
    :
else
    echo "project_folder exists and is not a directory or symlink" >&2
    exit 1
fi

if git rev-parse --git-dir >/dev/null 2>&1; then
    git update-index --skip-worktree project_folder || true
fi

if ! command -v conda >/dev/null 2>&1; then
    echo "conda is not on PATH" >&2
    exit 1
fi

eval "$(conda shell.bash hook)"

if ! conda env list | awk '{print $1}' | grep -qx chemCPA; then
    conda env create -f environment.yml
fi

conda activate chemCPA

python -m pip install -e .
python -m pip install --extra-index-url https://pypi.nvidia.com "rapids-singlecell[rapids11]==0.10.10"

cat <<'EOF'
Local bootstrap complete.

Continue from here:
1. Run the preprocessing scripts manually from an interactive terminal.
2. Run preprocessing/4_sciplex_SMILES.py twice by toggling LINCS_GENES.
3. After step 5, if needed, create:
   ln -s sciplex_complete_middle_subset_lincs_genes_v2.h5ad project_folder/datasets/sciplex_complete_middle_subset_lincs_genes.h5ad
4. Then run preprocessing/6_baseline_sciplex_dataset.py and preprocessing/7_compute_embeddings.py.
5. Training command for this checkout:
   python chemCPA/train_hydra.py dataset=sciplex

To make git track project_folder again later:
   git update-index --no-skip-worktree project_folder
EOF