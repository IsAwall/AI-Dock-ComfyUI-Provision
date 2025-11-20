#!/bin/bash
# ComfyUI Provisioning Script
# Version: 1.0.0
# Date: 2025-11-20
# 
# CHANGELOG:
# v1.0.0 (2025-11-20):
#   - Initial stable release
#   - Locks PyTorch to 2.7.0+cu128
#   - Skips xformers (causes version conflicts)
#   - Clears pip cache to prevent storage bloat
#   - Installs comfyui-frontend-package
#   - Works with existing permanent storage installation

set -e  # Exit on error

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Environment
VENV_PATH="${VENV_PATH:-/opt/environments/python/comfyui}"
WORKSPACE="${WORKSPACE:-/workspace}"
COMFYUI_PATH="${WORKSPACE}/ComfyUI"

log_info "#################################################"
log_info "#  ComfyUI Provisioning v1.0.0                  #"
log_info "#  PyTorch 2.7.0 (NO xformers)                  #"
log_info "#################################################"

# Activate virtual environment
if [ -f "${VENV_PATH}/bin/activate" ]; then
    source "${VENV_PATH}/bin/activate"
    log_info "Virtual environment activated: ${VENV_PATH}"
else
    log_error "Virtual environment not found at ${VENV_PATH}"
    exit 1
fi

# ==============================================================================
# FUNCTION: Check PyTorch version
# ==============================================================================
check_pytorch_version() {
    local required_version="2.7.0"
    local required_cuda="12.8"
    
    if python -c "import torch" 2>/dev/null; then
        local current_version=$(python -c "import torch; print(torch.__version__)" 2>/dev/null | cut -d'+' -f1)
        local current_cuda=$(python -c "import torch; print(torch.version.cuda)" 2>/dev/null)
        
        log_info "Current PyTorch: ${current_version} (CUDA ${current_cuda})"
        
        if [[ "$current_version" == "$required_version"* ]] && [[ "$current_cuda" == "$required_cuda"* ]]; then
            log_info "PyTorch ${required_version}+cu${required_cuda} already installed. Skipping."
            return 0
        else
            log_warn "PyTorch upgrade needed: ${current_version} → ${required_version}"
            return 1
        fi
    else
        log_warn "PyTorch not found. Installing..."
        return 1
    fi
}

# ==============================================================================
# FUNCTION: Clear pip cache to free storage
# ==============================================================================
clear_pip_cache() {
    log_info "Clearing pip cache to free storage..."
    pip cache purge || log_warn "Pip cache clear failed (may not exist)"
    
    # Also clear workspace pip cache if it exists
    if [ -d "${WORKSPACE}/.cache/pip" ]; then
        log_info "Clearing workspace pip cache..."
        rm -rf "${WORKSPACE}/.cache/pip"
        log_info "Freed storage from workspace pip cache"
    fi
}

# ==============================================================================
# FUNCTION: Upgrade PyTorch (without xformers)
# ==============================================================================
upgrade_pytorch() {
    log_info "Upgrading to PyTorch 2.7.0+cu128..."
    
    # Clear pip cache BEFORE installation
    clear_pip_cache
    
    # Uninstall existing packages
    log_info "Uninstalling old PyTorch packages..."
    pip uninstall -y torch torchvision torchaudio xformers 2>/dev/null || true
    
    # Upgrade pip tools
    log_info "Upgrading pip, setuptools, wheel..."
    python -m pip install --no-cache-dir --upgrade pip setuptools wheel
    
    # Install PyTorch 2.7.0 with EXACT versions (no xformers!)
    log_info "Installing PyTorch 2.7.0+cu128 (exact versions)..."
    pip install --no-cache-dir \
        torch==2.7.0+cu128 \
        torchvision==0.22.0+cu128 \
        torchaudio==2.7.0+cu128 \
        --index-url https://download.pytorch.org/whl/cu128
    
    log_info "PyTorch installation complete!"
    log_warn "xformers SKIPPED (causes version conflicts with 2.7.0)"
}

# ==============================================================================
# FUNCTION: Install package if missing
# ==============================================================================
install_if_missing() {
    local package=$1
    local import_name=${2:-$1}
    
    if python -c "import ${import_name}" 2>/dev/null; then
        log_info "${package} already installed. Skipping."
        return 0
    else
        log_info "Installing ${package}..."
        pip install --no-cache-dir "${package}"
        return 1
    fi
}

# ==============================================================================
# MAIN PROVISIONING
# ==============================================================================

# Check and upgrade PyTorch if needed
if ! check_pytorch_version; then
    upgrade_pytorch
else
    # Even if PyTorch is correct, clear cache periodically
    clear_pip_cache
fi

# ==============================================================================
# Install core dependencies
# ==============================================================================
log_info "Checking core dependencies..."

install_if_missing "av"
install_if_missing "pydantic-settings" "pydantic_settings"
install_if_missing "accelerate"
install_if_missing "requirements-parser" "requirements_parser"
install_if_missing "alembic"
install_if_missing "segment-anything" "segment_anything"

# ==============================================================================
# Install ComfyUI frontend package (NEW REQUIREMENT)
# ==============================================================================
log_info "Installing ComfyUI frontend package..."
pip install --no-cache-dir comfyui-frontend-package || log_warn "Frontend package install failed"

# ==============================================================================
# Reinstall ComfyUI requirements
# ==============================================================================
if [ -f "${COMFYUI_PATH}/requirements.txt" ]; then
    log_info "Installing ComfyUI requirements..."
    pip install --no-cache-dir -r "${COMFYUI_PATH}/requirements.txt" --upgrade
fi

# ==============================================================================
# Verify pip accessibility
# ==============================================================================
log_info "Verifying pip accessibility..."
if python -m pip --version > /dev/null 2>&1; then
    log_info "pip is accessible ✓"
else
    log_warn "pip not accessible, reinstalling..."
    python -m ensurepip --upgrade
fi

# ==============================================================================
# Install/Update ComfyUI Manager
# ==============================================================================
MANAGER_PATH="${COMFYUI_PATH}/custom_nodes/ComfyUI-Manager"
if [ ! -d "${MANAGER_PATH}" ]; then
    log_info "Installing ComfyUI Manager..."
    cd "${COMFYUI_PATH}/custom_nodes"
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git
    cd ComfyUI-Manager
    pip install --no-cache-dir -r requirements.txt
else
    log_info "ComfyUI Manager exists. Checking for updates..."
    cd "${MANAGER_PATH}"
    git fetch
    LOCAL=$(git rev-parse @)
    REMOTE=$(git rev-parse @{u})
    
    if [ $LOCAL != $REMOTE ]; then
        log_info "Updating ComfyUI Manager..."
        git pull
        pip install --no-cache-dir -r requirements.txt --upgrade
    else
        log_info "ComfyUI Manager is up to date"
    fi
fi

# ==============================================================================
# Fix broken custom nodes
# ==============================================================================
log_info "Checking for broken custom nodes..."

NSFW_MMAUDIO_PATH="${COMFYUI_PATH}/custom_nodes/NSFW_MMaudio"
if [ -d "${NSFW_MMAUDIO_PATH}" ] && [ ! -f "${NSFW_MMAUDIO_PATH}/__init__.py" ]; then
    log_warn "Fixing NSFW_MMaudio missing __init__.py..."
    touch "${NSFW_MMAUDIO_PATH}/__init__.py"
fi

MMAUDIO_PATH="${COMFYUI_PATH}/custom_nodes/ComfyUI-MMAudio"
if [ -d "${MMAUDIO_PATH}" ] && [ -f "${MMAUDIO_PATH}/requirements.txt" ]; then
    log_info "Installing ComfyUI-MMAudio dependencies..."
    pip install --no-cache-dir -r "${MMAUDIO_PATH}/requirements.txt" || log_warn "Some MMAudio dependencies failed"
fi

MTB_PATH="${COMFYUI_PATH}/custom_nodes/comfy-mtb"
if [ -d "${MTB_PATH}" ] && [ -f "${MTB_PATH}/requirements.txt" ]; then
    log_info "Installing comfy-mtb dependencies..."
    pip install --no-cache-dir -r "${MTB_PATH}/requirements.txt" || log_warn "Some comfy-mtb dependencies failed"
fi

# ==============================================================================
# Create provision marker
# ==============================================================================
PROVISION_MARKER="${WORKSPACE}/.provisioned"
PROVISION_DATE=$(date +%Y-%m-%d_%H-%M-%S)

echo "Script version: 1.0.0" > "${PROVISION_MARKER}"
echo "Last provisioned: ${PROVISION_DATE}" >> "${PROVISION_MARKER}"
echo "PyTorch version: $(python -c 'import torch; print(torch.__version__)')" >> "${PROVISION_MARKER}"
echo "CUDA version: $(python -c 'import torch; print(torch.version.cuda)')" >> "${PROVISION_MARKER}"
echo "xformers installed: No (skipped to avoid conflicts)" >> "${PROVISION_MARKER}"
echo "PyAV version: $(python -c 'import av; print(av.__version__)' 2>/dev/null || echo 'Not found')" >> "${PROVISION_MARKER}"
echo "pip accessible: $(python -m pip --version 2>/dev/null || echo 'No')" >> "${PROVISION_MARKER}"

log_info "#################################################"
log_info "#  Provisioning Complete! v1.0.0                #"
log_info "#                                               #"
log_info "#  Changes:                                     #"
log_info "#  ✓ PyTorch 2.7.0+cu128 (locked)               #"
log_info "#  ✓ xformers SKIPPED (prevents conflicts)      #"
log_info "#  ✓ Pip cache cleared (freed storage)          #"
log_info "#  ✓ ComfyUI frontend installed                 #"
log_info "#  ✓ All dependencies verified                  #"
log_info "#                                               #"
log_info "#################################################"

log_info "Provisioning details: ${PROVISION_MARKER}"
