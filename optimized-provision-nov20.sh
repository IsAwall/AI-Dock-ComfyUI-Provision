#!/bin/bash
# FIXED Optimized AI-Dock ComfyUI Provisioning Script
# Fixes: Missing 'av' package, pip accessibility, xformers compatibility

set -e  # Exit on error

# Color output for readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Set virtual environment path
VENV_PATH="${VENV_PATH:-/opt/environments/python/comfyui}"
WORKSPACE="${WORKSPACE:-/workspace}"
COMFYUI_PATH="${WORKSPACE}/ComfyUI"

log_info "#################################################"
log_info "#                                               #"
log_info "# FIXED Optimized ComfyUI Provisioning          #"
log_info "#                                               #"
log_info "# Checking existing installations...            #"
log_info "#                                               #"
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
# FUNCTION: Check if PyTorch version meets requirements
# ==============================================================================
check_pytorch_version() {
    local required_version="2.7.0"
    local required_cuda="12.8"
    
    if python -c "import torch" 2>/dev/null; then
        local current_version=$(python -c "import torch; print(torch.__version__)" 2>/dev/null | cut -d'+' -f1)
        local current_cuda=$(python -c "import torch; print(torch.version.cuda)" 2>/dev/null)
        
        log_info "Current PyTorch version: ${current_version} (CUDA ${current_cuda})"
        
        # Simple version comparison - checks if versions match
        if [[ "$current_version" == "$required_version"* ]] && [[ "$current_cuda" == "$required_cuda"* ]]; then
            log_info "PyTorch ${required_version} with CUDA ${required_cuda} already installed. Skipping upgrade."
            return 0
        else
            log_warn "PyTorch upgrade needed: ${current_version} -> ${required_version}"
            return 1
        fi
    else
        log_warn "PyTorch not found. Installing..."
        return 1
    fi
}

# ==============================================================================
# FUNCTION: Upgrade PyTorch
# ==============================================================================
upgrade_pytorch() {
    log_info "Upgrading PyTorch to 2.7.0 with CUDA 12.8 support..."
    
    # Uninstall existing PyTorch packages
    log_info "Uninstalling existing PyTorch packages..."
    pip uninstall -y torch torchvision torchaudio xformers 2>/dev/null || true
    
    # Upgrade pip, setuptools, wheel first
    log_info "Upgrading pip, setuptools, and wheel..."
    python -m pip install --upgrade pip setuptools wheel
    
    # Install PyTorch 2.7.0 with CUDA 12.8
    log_info "Installing PyTorch 2.7.0+cu128..."
    pip install torch==2.7.0 torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
    
    # Install xformers compatible with PyTorch 2.7.0
    log_info "Installing xformers for PyTorch 2.7.0..."
    pip install xformers --index-url https://download.pytorch.org/whl/cu128 || log_warn "xformers installation failed, will continue without it"
    
    log_info "PyTorch upgrade complete!"
}

# ==============================================================================
# FUNCTION: Check and install pip packages
# ==============================================================================
install_if_missing() {
    local package=$1
    local import_name=${2:-$1}  # Use package name if import name not provided
    
    if python -c "import ${import_name}" 2>/dev/null; then
        log_info "${package} already installed. Skipping."
        return 0
    else
        log_info "Installing ${package}..."
        pip install "${package}"
        return 1
    fi
}

# ==============================================================================
# MAIN PROVISIONING LOGIC
# ==============================================================================

# Check and upgrade PyTorch if needed
if ! check_pytorch_version; then
    upgrade_pytorch
fi

# ==============================================================================
# Install missing core dependencies
# ==============================================================================
log_info "Checking core dependencies..."

# Critical: av (PyAV) package for video input support
install_if_missing "av"

# These are dependencies that were missing according to logs
install_if_missing "pydantic-settings" "pydantic_settings"
install_if_missing "accelerate"
install_if_missing "requirements-parser" "requirements_parser"
install_if_missing "alembic"
install_if_missing "segment-anything" "segment_anything"

# ==============================================================================
# Verify pip is accessible
# ==============================================================================
log_info "Verifying pip accessibility..."
if python -m pip --version > /dev/null 2>&1; then
    log_info "pip is accessible via 'python -m pip'"
else
    log_warn "pip not accessible, attempting to reinstall..."
    python -m ensurepip --upgrade
fi

# ==============================================================================
# Install/Update ComfyUI Manager if not present
# ==============================================================================
MANAGER_PATH="${COMFYUI_PATH}/custom_nodes/ComfyUI-Manager"
if [ ! -d "${MANAGER_PATH}" ]; then
    log_info "Installing ComfyUI Manager..."
    cd "${COMFYUI_PATH}/custom_nodes"
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git
    cd ComfyUI-Manager
    pip install -r requirements.txt
else
    log_info "ComfyUI Manager already installed. Checking for updates..."
    cd "${MANAGER_PATH}"
    
    # Check if there are updates available
    git fetch
    LOCAL=$(git rev-parse @)
    REMOTE=$(git rev-parse @{u})
    
    if [ $LOCAL != $REMOTE ]; then
        log_info "Updates available for ComfyUI Manager. Pulling..."
        git pull
        pip install -r requirements.txt --upgrade
    else
        log_info "ComfyUI Manager is up to date."
    fi
fi

# ==============================================================================
# Fix broken custom nodes (from logs)
# ==============================================================================
log_info "Checking for broken custom nodes..."

# Fix NSFW_MMaudio if directory exists but __init__.py is missing
NSFW_MMAUDIO_PATH="${COMFYUI_PATH}/custom_nodes/NSFW_MMaudio"
if [ -d "${NSFW_MMAUDIO_PATH}" ] && [ ! -f "${NSFW_MMAUDIO_PATH}/__init__.py" ]; then
    log_warn "NSFW_MMaudio directory exists but __init__.py is missing. Creating empty __init__.py..."
    touch "${NSFW_MMAUDIO_PATH}/__init__.py"
fi

# Install dependencies for ComfyUI-MMAudio if it exists
MMAUDIO_PATH="${COMFYUI_PATH}/custom_nodes/ComfyUI-MMAudio"
if [ -d "${MMAUDIO_PATH}" ]; then
    if [ -f "${MMAUDIO_PATH}/requirements.txt" ]; then
        log_info "Installing ComfyUI-MMAudio dependencies..."
        pip install -r "${MMAUDIO_PATH}/requirements.txt" || log_warn "Some MMAudio dependencies may have failed"
    fi
fi

# ==============================================================================
# Install requirements for comfy-mtb if present
# ==============================================================================
MTB_PATH="${COMFYUI_PATH}/custom_nodes/comfy-mtb"
if [ -d "${MTB_PATH}" ] && [ -f "${MTB_PATH}/requirements.txt" ]; then
    log_info "Installing comfy-mtb dependencies..."
    pip install -r "${MTB_PATH}/requirements.txt" || log_warn "Some comfy-mtb dependencies may have failed"
fi

# ==============================================================================
# Reinstall ComfyUI requirements to ensure compatibility
# ==============================================================================
if [ -f "${COMFYUI_PATH}/requirements.txt" ]; then
    log_info "Reinstalling ComfyUI requirements for compatibility..."
    pip install -r "${COMFYUI_PATH}/requirements.txt" --upgrade
fi

# ==============================================================================
# Optional: Update all custom nodes (DISABLED BY DEFAULT)
# ==============================================================================
# Uncomment the following block if you want to auto-update all custom nodes
# This can be slow, so it's disabled by default

# log_info "Updating all custom nodes..."
# cd "${COMFYUI_PATH}/custom_nodes"
# for dir in */; do
#     if [ -d "${dir}/.git" ]; then
#         log_info "Updating ${dir}..."
#         cd "${dir}"
#         git pull || log_warn "Failed to update ${dir}"
#         if [ -f "requirements.txt" ]; then
#             pip install -r requirements.txt --upgrade || log_warn "Some dependencies failed for ${dir}"
#         fi
#         cd ..
#     fi
# done

# ==============================================================================
# Create marker file to indicate successful provisioning
# ==============================================================================
PROVISION_MARKER="${WORKSPACE}/.provisioned"
PROVISION_DATE=$(date +%Y-%m-%d_%H-%M-%S)

echo "Last provisioned: ${PROVISION_DATE}" > "${PROVISION_MARKER}"
echo "PyTorch version: $(python -c 'import torch; print(torch.__version__)')" >> "${PROVISION_MARKER}"
echo "CUDA version: $(python -c 'import torch; print(torch.version.cuda)')" >> "${PROVISION_MARKER}"
echo "PyAV installed: $(python -c 'import av; print(av.__version__)' 2>/dev/null || echo 'Not found')" >> "${PROVISION_MARKER}"
echo "pip accessible: $(python -m pip --version 2>/dev/null || echo 'No')" >> "${PROVISION_MARKER}"

log_info "#################################################"
log_info "#                                               #"
log_info "# Provisioning Complete!                        #"
log_info "#                                               #"
log_info "# FIXES APPLIED:                                #"
log_info "# - Added PyAV (av) package                     #"
log_info "# - Fixed pip accessibility                     #"
log_info "# - Installed xformers for PyTorch 2.7.0        #"
log_info "#                                               #"
log_info "#################################################"

log_info "Provisioning details saved to: ${PROVISION_MARKER}"
