# Seed-Env CLI Tool

The seed-env CLI tool's design centers around a seed-env methodology, prioritizing JAX as the foundational "seed" for reproducible Python environments. The tool will take project-specific dependencies (e.g., MaxText's requirements.txt) and intelligently layer them on top of the JAX seed, resolving conflicts to create a stable final environment.

Example commands:
```
cd python_seed_env
# Build the seed-env CLI tool by running
pip install .
# Or run the following command if you want to edit and run pytest
# pip install -e . [dev]

# See all the arguments of the tool
seed-env --help
# Run the following command with minimal arguments needed to generate requirement lock files for maxtext based on the latest release jax as seed.
seed-env --host-repo=AI-Hypercomputer/maxtext --host-requirements=requirements.txt
# Run the following command to build lock files and a pypi package for maxtext at a specific commit and use jax at a specific commit/tag.
seed-env --host-repo=AI-Hypercomputer/maxtext --host-requirements=requirements.txt --host-commit=<a maxtext commit> --seed-config=jax_seed.yaml --seed-commit="jax-v0.6.2" --python-version="3.12" --hardware="tpu" --build-pypi-package
# Run the following command build lock files and a pypi package based on a local host requirement file and use the latest release jax as seed.
seed-env --local-requirements=<local path to a requirements.txt file> --build-pypi-package
```
