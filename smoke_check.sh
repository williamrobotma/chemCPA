#!/usr/bin/env bash
# Fork patch (williamrobotma): local post-clone validation helper for this fork.
set -euo pipefail

cd "$(dirname "$0")"

export TF_CPP_MIN_LOG_LEVEL=3

echo "[1/2] Checking core imports"
python -W ignore::FutureWarning -W ignore::UserWarning -W ignore::DeprecationWarning - <<'PY' \
  2> >(grep -v -E '^(WARNING: All log messages before absl::InitializeLog\(\) is called are written to STDERR|E[0-9]{4} .*cuda_(dnn|blas)\.cc:)' >&2)
import gdown
import sfaira
from descriptastorus.descriptors.DescriptorGenerator import MakeGenerator

print("gdown", gdown.__version__)
print("sfaira", sfaira.__version__)
print("descriptastorus", callable(MakeGenerator))
PY

echo "[2/2] Checking training entrypoint"
PYTHONWARNINGS=ignore::UserWarning python -m chemCPA.train_hydra --help >/dev/null