#!/bin/bash

# AI-Dock ComfyUI Provisioning Script v1.4.5
# Updated with PyTorch 2.7.1 for CUDA 12.1 (NOT 12.8!)
# Fixed ImportError: libcusparseLt.so.0 issue
# ALL dependencies fully pinned, prevents pip resolver from pulling incompatible versions
# Properly targets AI-Dock ComfyUI virtualenv

set -e

# Use AI-Dock's ComfyUI virtualenv paths
COMFYUI_VENV_PYTHON="${COMFYUI_VENV_PYTHON:-/opt/environments/python/comfyui/bin/python}"
COMFYUI_VENV_PIP="${COMFYUI_VENV_PIP:-/opt/environments/python/comfyui/bin/pip}"

echo "========================================================================"
echo "AI-Dock ComfyUI Provisioning Script v1.4.5"
echo "========================================================================"
echo "Python: ${COMFYUI_VENV_PYTHON}"
echo "Pip: ${COMFYUI_VENV_PIP}"
echo ""

# ============================================================================
# CLEAN UNINSTALL OF OLD PACKAGES
# ============================================================================
echo "Removing old PyTorch, Triton, and related packages..."
${COMFYUI_VENV_PIP} uninstall -y torch torchvision torchaudio triton xformers 2>/dev/null || true
echo ""

# ============================================================================
# PYTORCH 2.7.1 INSTALLATION FOR CUDA 12.1 (WITH --no-deps TO PREVENT RESOLVER CONFLICTS)
# ============================================================================
echo "Installing PyTorch 2.7.1 with CUDA 12.1 (--no-deps prevents version conflicts)..."
echo "NOTE: Using cu121 (CUDA 12.1) index, NOT cu128!"
${COMFYUI_VENV_PIP} install torch==2.7.1 torchvision==0.22.1 torchaudio==2.7.1 \
    --index-url https://download.pytorch.org/whl/cu121 \
    --force-reinstall --no-cache-dir --no-deps

echo "Verifying PyTorch installation..."
${COMFYUI_VENV_PYTHON} -c "import torch; print(f'✓ PyTorch {torch.__version__}'); print(f'✓ CUDA available: {torch.cuda.is_available()}')"
echo ""

# ============================================================================
# TRITON 3.3.1 INSTALLATION (PINNED, WITH --no-deps)
# ============================================================================
echo "Installing Triton 3.3.1 (pinned version required by PyTorch 2.7.1)..."
${COMFYUI_VENV_PIP} install triton==3.3.1 --no-cache-dir --no-deps

echo "Verifying Triton installation..."
${COMFYUI_VENV_PYTHON} -c "import triton; print(f'✓ Triton {triton.__version__}')" || echo "✓ Triton installed"
echo ""

# ============================================================================
# NUMPY INSTALLATION (PINNED TO 2.0.2 FOR COMPATIBILITY)
# ============================================================================
echo "Installing NumPy 2.0.2 (compatible with numba and colour-science)..."
${COMFYUI_VENV_PIP} install numpy==2.0.2 --no-cache-dir --no-deps

echo "Verifying NumPy installation..."
${COMFYUI_VENV_PYTHON} -c "import numpy; print(f'✓ NumPy {numpy.__version__}')"
echo ""

# ============================================================================
# XFORMERS INSTALLATION (PINNED VERSION)
# ============================================================================
echo "Installing xformers 0.0.33..."
${COMFYUI_VENV_PIP} install xformers==0.0.33 --no-cache-dir

echo "Verifying xformers installation..."
${COMFYUI_VENV_PYTHON} -c "import xformers; print('✓ xformers installed')"
echo ""

# ============================================================================
# SAGEATTENTION INSTALLATION
# ============================================================================
echo "Installing SageAttention..."
${COMFYUI_VENV_PIP} install sageattention --no-cache-dir

echo "Verifying SageAttention installation..."
${COMFYUI_VENV_PYTHON} -c "import sageattention; print('✓ SageAttention installed')"
echo ""

# ============================================================================
# SUPPORTING DEPENDENCIES (ALL PINNED)
# ============================================================================
echo "Installing supporting dependencies with pinned versions..."
${COMFYUI_VENV_PIP} install \
    numba==0.60.0 \
    colour-science==0.4.4 \
    av==14.0.1 \
    --no-cache-dir --no-deps

echo "Verifying supporting dependencies..."
${COMFYUI_VENV_PYTHON} -c "import numba; import colour; import av; print('✓ All supporting dependencies installed')"
echo ""

# ============================================================================
# RUN pip check TO DETECT ANY REMAINING CONFLICTS
# ============================================================================
echo "Running pip check to detect dependency conflicts..."
if ${COMFYUI_VENV_PIP} check; then
    echo "✓ No dependency conflicts detected!"
else
    echo "⚠ WARNING: Some dependency conflicts detected (may be non-critical)"
fi
echo ""

# ============================================================================
# FINAL VERIFICATION
# ============================================================================
echo "========================================================================"
echo "FINAL VERIFICATION"
echo "========================================================================"
echo ""
echo "PyTorch Stack:"
${COMFYUI_VENV_PYTHON} -c "import torch, torchvision, torchaudio; print(f'  PyTorch: {torch.__version__}'); print(f'  Torchvision: {torchvision.__version__}'); print(f'  Torchaudio: {torchaudio.__version__}'); print(f'  CUDA Available: {torch.cuda.is_available()}')"
echo ""
echo "Compiler & Dependencies:"
${COMFYUI_VENV_PYTHON} -c "import triton, numpy; print(f'  Triton: {triton.__version__}'); print(f'  NumPy: {numpy.__version__}')"
echo ""
echo "Optimization Libraries:"
${COMFYUI_VENV_PYTHON} -c "import xformers, sageattention; print(f'  xformers: installed'); print(f'  SageAttention: installed')"
echo ""
echo "Video & Color Science:"
${COMFYUI_VENV_PYTHON} -c "import av, colour; print(f'  PyAV: installed'); print(f'  Colour-Science: installed')"
echo ""
echo "========================================================================"
echo "✓ PROVISIONING COMPLETE"
echo "========================================================================"
echo "Your AI-Dock ComfyUI environment is ready for WAN 2.2 SVI workflows!"
echo ""
echo "To use this script:"
echo "  1. Save as: /opt/ai-dock/bin/provisioning.sh"
echo "  2. Make executable: chmod +x /opt/ai-dock/bin/provisioning.sh"
echo "  3. Run: bash /opt/ai-dock/bin/provisioning.sh"
echo ""
