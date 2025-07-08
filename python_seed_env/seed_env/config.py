DEFAULT_PROJECT_COMMIT = "main"
DEFAULT_SEED_FRAMEWORK = "jax"
DEFAULT_PYTHON_VERSION = "3.12"
DEFAULT_HARDWARE = "tpu"
DEFAULT_BUILD_PROJECT = False
SUPPORTED_HARDWARE = ["tpu", "gpu"]
SUPPORTED_SEED_PROJECTS = ["jax"]
DEFAULT_SEED_PROJECT = "jax"

DEPS_EXCLUDED_FROM_TPU_ENV = [
    "nvidia-cublas-cu12",
    "nvidia-cuda-cupti-cu12",
    "nvidia-cuda-nvcc-cu12",
    "nvidia-cuda-nvrtc-cu12", # Remove?
    "nvidia-cuda-runtime-cu12",
    "nvidia-cudnn-cu12",
    "nvidia-cufft-cu12",
    "nvidia-cusolver-cu12",
    "nvidia-cusparse-cu12",
    "nvidia-nccl-cu12",
    "nvidia-nvjitlink-cu12",
    "nvidia-nvshmem-cu12",
    "jax-cuda12-plugin",
    "jax-cuda12-pjrt",
]

DEPS_EXCLUDED_FROM_GPU_ENV = [
    "libtpu",
]
