#!/bin/bash

# AI-Dock ComfyUI Provisioning Script v1.4.2
# Updated with PyTorch 2.7.1, SageAttention, and Triton 3.3.1
# Properly targets AI-Dock ComfyUI virtualenv
# Also rebuilds xformers and installs missing dependencies

set -e

# Use AI-Dock's ComfyUI virtualenv paths
COMFYUI_VENV_PYTHON="${COMFYUI_VENV_PYTHON:-/opt/environments/python/comfyui/bin/python}"
COMFYUI_VENV_PIP="${COMFYUI_VENV_PIP:-/opt/environments/python/comfyui/bin/pip}"

echo "Updating PyTorch, SageAttention, and Triton in AI-Dock ComfyUI environment..."
echo "Python: ${COMFYUI_VENV_PYTHON}"
echo "Pip: ${COMFYUI_VENV_PIP}"
echo ""

# ============================================================================
# PYTORCH 2.7.1 INSTALLATION WITH PINNED DEPENDENCIES
# ============================================================================
echo "Installing PyTorch 2.7.1 with CUDA 12.8 and pinned dependencies..."
${COMFYUI_VENV_PIP} uninstall -y torch torchvision torchaudio triton 2>/dev/null || true
${COMFYUI_VENV_PIP} install torch==2.7.1 torchvision==0.22.1 torchaudio==2.7.1 \
    --index-url https://download.pytorch.org/whl/cu128 \
    --force-reinstall --no-cache-dir

# Verify installation
echo "Verifying PyTorch installation..."
${COMFYUI_VENV_PYTHON} -c "import torch; print(f'PyTorch {torch.__version__} installed successfully')"
echo ""

# ============================================================================
# TRITON 3.3.1 INSTALLATION (REQUIRED BY PYTORCH 2.7.1)
# ============================================================================
echo "Installing Triton 3.3.1 (required by PyTorch 2.7.1)..."
${COMFYUI_VENV_PIP} install "triton==3.3.1" --no-cache-dir

# Verify installation
echo "Verifying Triton installation..."
${COMFYUI_VENV_PYTHON} -c "import triton; print(f'Triton {triton.__version__} installed successfully')" || echo "Triton import check completed"
echo ""

# ============================================================================
# SAGEATTENTION INSTALLATION
# ============================================================================
echo "Installing SageAttention..."
${COMFYUI_VENV_PIP} install sageattention --no-cache-dir

# Verify installation
echo "Verifying SageAttention installation..."
${COMFYUI_VENV_PYTHON} -c "import sageattention; print('SageAttention installed successfully')"
echo ""

# ============================================================================
# XFORMERS REBUILD
# ============================================================================
echo "Rebuilding xformers for new PyTorch version..."
${COMFYUI_VENV_PIP} uninstall -y xformers 2>/dev/null || true
${COMFYUI_VENV_PIP} install xformers --no-cache-dir --force-reinstall

echo "Verifying xformers installation..."
${COMFYUI_VENV_PYTHON} -c "import xformers; print('xformers rebuilt successfully')"
echo ""

# ============================================================================
# MISSING DEPENDENCIES
# ============================================================================
echo "Installing missing dependencies..."
${COMFYUI_VENV_PIP} install av --no-cache-dir

echo "Verifying av installation..."
${COMFYUI_VENV_PYTHON} -c "import av; print('PyAV (av) installed successfully')"
echo ""

# ============================================================================
# FINAL VERIFICATION
# ============================================================================
echo "=== FINAL VERIFICATION ==="
echo ""
echo "PyTorch version:"
${COMFYUI_VENV_PYTHON} -c "import torch; print(f'  {torch.__version__}'); print(f'  CUDA available: {torch.cuda.is_available()}')"
echo ""
echo "Triton version:"
${COMFYUI_VENV_PYTHON} -c "import triton; print(f'  {triton.__version__}')"
echo ""
echo "Torchvision version:"
${COMFYUI_VENV_PYTHON} -c "import torchvision; print(f'  {torchvision.__version__}')"
echo ""
echo "SageAttention:"
${COMFYUI_VENV_PYTHON} -c "import sageattention; print('  Installed')"
echo ""
echo "xformers:"
${COMFYUI_VENV_PYTHON} -c "import xformers; print('  Installed')"
echo ""
echo "PyAV (av):"
${COMFYUI_VENV_PYTHON} -c "import av; print('  Installed')"
echo ""
echo "=== PROVISIONING COMPLETE ==="
echo "Your AI-Dock ComfyUI environment is ready for WAN 2.2 SVI workflows!"
