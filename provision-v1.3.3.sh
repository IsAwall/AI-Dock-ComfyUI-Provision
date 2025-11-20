#!/bin/bash
# ComfyUI Provisioning Script
# Version: 1.3.3
# Date: 2025-11-20
#
# CHANGELOG:
# v1.3.3 (2025-11-20):
#   - CRITICAL FIX: Remove .ipynb_checkpoints directory (breaks node loading!)
#   - CRITICAL FIX: Remove __pycache__ directories
#   - CRITICAL FIX: Skip hidden directories when processing nodes
#   - This fixes the "unsupported nodes" error you were seeing
#
# v1.3.2 (2025-11-20):
#   - Efficiency fixes for startup time
#   - Pin frontend to 1.32.1
#
# v1.3.1 (2025-11-20):
#   - Removed --force-reinstall from requirements.txt
#
# v1.3.0 (2025-11-20):
#   - Aggressive frontend installation
#
# v1.2.0-v1.0.0: Previous versions

set -e

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
log_info "#  ComfyUI Provisioning v1.3.3                  #"
log_info "#  Node Loading Fix (.ipynb_checkpoints)        #"
log_info "#################################################"

# Stop ComfyUI
log_info "Stopping ComfyUI..."
supervisorctl stop comfyui 2>/dev/null || log_warn "ComfyUI not running"
sleep 2

# Activate venv
if [ -f "${VENV_PATH}/bin/activate" ]; then
    source "${VENV_PATH}/bin/activate"
    log_info "Virtual environment activated"
else
    log_error "Virtual environment not found at ${VENV_PATH}"
    exit 1
fi

# ==============================================================================
# FUNCTION: Fix pip
# ==============================================================================
fix_pip_aggressively() {
    log_info "Checking pip..."
    
    if python -m pip --version > /dev/null 2>&1; then
        log_info "pip accessible"
        return 0
    fi
    
    log_warn "pip not accessible, fixing..."
    python -m ensurepip --upgrade 2>/dev/null || true
    
    if python -m pip --version > /dev/null 2>&1; then
        log_info "pip fixed ✓"
        return 0
    fi
    
    log_warn "Downloading get-pip.py..."
    cd /tmp
    curl -sS https://bootstrap.pypa.io/get-pip.py -o get-pip.py
    python get-pip.py --force-reinstall
    
    if python -m pip --version > /dev/null 2>&1; then
        log_info "pip fixed ✓"
        return 0
    fi
    
    log_error "pip fix FAILED"
    return 1
}

# ==============================================================================
# FUNCTION: Clear caches
# ==============================================================================
clear_caches() {
    log_info "Clearing caches..."
    python -m pip cache purge 2>/dev/null || true
    
    if [ -d "${WORKSPACE}/.cache/pip" ]; then
        rm -rf "${WORKSPACE}/.cache/pip"
    fi
    
    # Clear ComfyUI frontend cache
    if [ -d "${COMFYUI_PATH}/web/cache" ]; then
        log_info "Clearing ComfyUI frontend cache..."
        rm -rf "${COMFYUI_PATH}/web/cache"
    fi
    
    if [ -d "${COMFYUI_PATH}/.cache" ]; then
        rm -rf "${COMFYUI_PATH}/.cache"
    fi
}

# ==============================================================================
# FUNCTION: Check PyTorch
# ==============================================================================
check_pytorch_version() {
    local required_version="2.7.0"
    local required_cuda="12.8"
    
    if python -c "import torch" 2>/dev/null; then
        local current_version=$(python -c "import torch; print(torch.__version__)" 2>/dev/null | cut -d'+' -f1)
        local current_cuda=$(python -c "import torch; print(torch.version.cuda)" 2>/dev/null)
        
        log_info "Current PyTorch: ${current_version} (CUDA ${current_cuda})"
        
        if [[ "$current_version" == "$required_version"* ]] && [[ "$current_cuda" == "$required_cuda"* ]]; then
            log_info "PyTorch ${required_version}+cu${required_cuda} ✓"
            return 0
        else
            log_warn "Wrong PyTorch: ${current_version} (need ${required_version})"
            return 1
        fi
    else
        log_warn "PyTorch not found"
        return 1
    fi
}

# ==============================================================================
# FUNCTION: Upgrade PyTorch
# ==============================================================================
upgrade_pytorch() {
    log_info "Installing PyTorch 2.7.0+cu128..."
    
    clear_caches
    
    python -m pip uninstall -y torch torchvision torchaudio xformers 2>/dev/null || true
    
    python -m pip install --no-cache-dir --upgrade pip setuptools wheel
    
    python -m pip install --no-cache-dir \
        torch==2.7.0+cu128 \
        torchvision==0.22.0+cu128 \
        torchaudio==2.7.0+cu128 \
        --index-url https://download.pytorch.org/whl/cu128
    
    log_info "PyTorch 2.7.0+cu128 installed ✓"
}

# ==============================================================================
# MAIN PROVISIONING
# ==============================================================================

# Fix pip
fix_pip_aggressively || {
    log_error "Cannot proceed without pip"
    exit 1
}

log_info "pip: $(python -m pip --version)"

# Check/upgrade PyTorch
if ! check_pytorch_version; then
    upgrade_pytorch
    fix_pip_aggressively || {
        log_error "pip broken after PyTorch upgrade"
        exit 1
    }
else
    clear_caches
fi

# Install core dependencies
log_info "Installing core dependencies..."
python -m pip install --no-cache-dir av pydantic-settings accelerate requirements-parser alembic segment-anything

# ==============================================================================
# SMART REQUIREMENTS.TXT INSTALL
# ==============================================================================
log_info "###################################################"
log_info "#  SMART REQUIREMENTS INSTALLATION                #"
log_info "###################################################"

if [ -f "${COMFYUI_PATH}/requirements.txt" ]; then
    CURRENT_PYTORCH=$(python -c "import torch; print(torch.__version__)" 2>/dev/null | cut -d'+' -f1)
    
    if [[ "$CURRENT_PYTORCH" == "2.7.0"* ]]; then
        log_info "PyTorch correct (2.7.0), installing requirements normally..."
        python -m pip install --no-cache-dir -r "${COMFYUI_PATH}/requirements.txt"
    else
        log_info "Filtering torch from requirements to prevent upgrade..."
        grep -v "^torch" "${COMFYUI_PATH}/requirements.txt" > /tmp/requirements_no_torch.txt || true
        python -m pip install --no-cache-dir -r /tmp/requirements_no_torch.txt
        rm -f /tmp/requirements_no_torch.txt
    fi
fi

# ==============================================================================
# FRONTEND INSTALLATION
# ==============================================================================
log_info "Installing ComfyUI frontend (stable version)..."

python -m pip install --no-cache-dir "comfyui-frontend-package==1.32.1" || {
    log_warn "Specific version failed, trying latest..."
    python -m pip install --no-cache-dir comfyui-frontend-package
}

if python -c "import comfyui_frontend; print(f'Frontend: {comfyui_frontend.__version__}')" 2>/dev/null; then
    FRONTEND_VERSION=$(python -c "import comfyui_frontend; print(comfyui_frontend.__version__)" 2>/dev/null)
    log_info "✓ Frontend package: ${FRONTEND_VERSION}"
else
    log_error "✗ Frontend package failed"
    python -m pip install --upgrade --force-reinstall pip
    python -m pip install --no-cache-dir --force-reinstall comfyui-frontend-package
fi

# ==============================================================================
# VERIFY PYTORCH STILL 2.7.0
# ==============================================================================
log_info "Verifying PyTorch version..."
PYTORCH_VERSION=$(python -c "import torch; print(torch.__version__)" 2>/dev/null | cut -d'+' -f1)
if [[ "$PYTORCH_VERSION" != "2.7.0"* ]]; then
    log_error "✗ PyTorch changed to ${PYTORCH_VERSION}! Reverting..."
    python -m pip uninstall -y torch torchvision torchaudio 2>/dev/null || true
    python -m pip install --no-cache-dir \
        torch==2.7.0+cu128 \
        torchvision==0.22.0+cu128 \
        torchaudio==2.7.0+cu128 \
        --index-url https://download.pytorch.org/whl/cu128
    log_info "✓ PyTorch reverted to 2.7.0"
else
    log_info "✓ PyTorch still at 2.7.0"
fi

if ! python -m pip --version > /dev/null 2>&1; then
    log_warn "pip broken again, fixing..."
    fix_pip_aggressively
fi

# ==============================================================================
# Install ComfyUI Manager
# ==============================================================================
MANAGER_PATH="${COMFYUI_PATH}/custom_nodes/ComfyUI-Manager"
if [ ! -d "${MANAGER_PATH}" ]; then
    log_info "Installing ComfyUI Manager..."
    cd "${COMFYUI_PATH}/custom_nodes"
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git
    cd ComfyUI-Manager
    python -m pip install --no-cache-dir -r requirements.txt
else
    log_info "ComfyUI Manager exists ✓"
    if [ -f "${MANAGER_PATH}/requirements.txt" ]; then
        cd "${MANAGER_PATH}"
        python -m pip install --no-cache-dir -r requirements.txt
    fi
fi

# ==============================================================================
# CRITICAL: Clean up problematic directories
# ==============================================================================
log_info "###################################################"
log_info "#  CLEANING PROBLEMATIC DIRECTORIES               #"
log_info "###################################################"

# Remove .ipynb_checkpoints (Jupyter auto-save, breaks node loading)
if [ -d "${COMFYUI_PATH}/custom_nodes/.ipynb_checkpoints" ]; then
    log_warn "Removing .ipynb_checkpoints (breaks node loading)..."
    rm -rf "${COMFYUI_PATH}/custom_nodes/.ipynb_checkpoints"
fi

# Remove __pycache__ directories
find "${COMFYUI_PATH}/custom_nodes" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true

# Remove any other hidden directories that aren't nodes
for hidden_dir in "${COMFYUI_PATH}/custom_nodes"/.*/ ; do
    if [ -d "${hidden_dir}" ]; then
        dir_name=$(basename "${hidden_dir}")
        if [[ "$dir_name" != "." && "$dir_name" != ".." ]]; then
            log_warn "Removing hidden directory: ${dir_name}"
            rm -rf "${hidden_dir}"
        fi
    fi
done

log_info "Problematic directories cleaned ✓"

# ==============================================================================
# Fix custom nodes (skip hidden directories)
# ==============================================================================
log_info "Checking custom nodes..."

for node_dir in "${COMFYUI_PATH}/custom_nodes"/*/ ; do
    if [ -d "${node_dir}" ]; then
        node_name=$(basename "${node_dir}")
        
        # Skip hidden directories (start with .)
        if [[ "$node_name" == .* ]]; then
            log_info "Skipping hidden directory: ${node_name}"
            continue
        fi
        
        # Create __init__.py if missing
        if [ ! -f "${node_dir}/__init__.py" ]; then
            touch "${node_dir}/__init__.py"
            log_info "Created __init__.py for ${node_name}"
        fi
        
        # Install requirements
        if [ -f "${node_dir}/requirements.txt" ]; then
            log_info "Installing requirements for ${node_name}..."
            python -m pip install --no-cache-dir -r "${node_dir}/requirements.txt" || \
                log_warn "${node_name} requirements had issues"
        fi
    fi
done

# ==============================================================================
# Final verification
# ==============================================================================
log_info "###################################################"
log_info "#  FINAL VERIFICATION                              #"
log_info "###################################################"

CRITICAL_IMPORTS=("torch" "torchvision" "torchaudio" "av" "comfyui_frontend")
ALL_OK=true

for pkg in "${CRITICAL_IMPORTS[@]}"; do
    if python -c "import ${pkg}" 2>/dev/null; then
        VERSION=$(python -c "import ${pkg}; print(getattr(${pkg}, '__version__', 'unknown'))" 2>/dev/null || echo "installed")
        log_info "✓ ${pkg} ${VERSION}"
    else
        log_error "✗ ${pkg} MISSING"
        ALL_OK=false
    fi
done

# ==============================================================================
# Create marker
# ==============================================================================
PROVISION_MARKER="${WORKSPACE}/.provisioned"
PROVISION_DATE=$(date +%Y-%m-%d_%H-%M-%S)

echo "Script version: 1.3.3" > "${PROVISION_MARKER}"
echo "Last provisioned: ${PROVISION_DATE}" >> "${PROVISION_MARKER}"
echo "PyTorch: $(python -c 'import torch; print(torch.__version__)')" >> "${PROVISION_MARKER}"
echo "CUDA: $(python -c 'import torch; print(torch.version.cuda)')" >> "${PROVISION_MARKER}"
echo "Frontend: $(python -c 'import comfyui_frontend; print(comfyui_frontend.__version__)' 2>/dev/null || echo 'FAILED')" >> "${PROVISION_MARKER}"
echo "pip: $(python -m pip --version 2>/dev/null || echo 'FAILED')" >> "${PROVISION_MARKER}"
echo "All verified: ${ALL_OK}" >> "${PROVISION_MARKER}"

# ==============================================================================
# Start ComfyUI
# ==============================================================================
log_info "Starting ComfyUI..."
supervisorctl start comfyui

log_info "###################################################"
log_info "#  Provisioning Complete! v1.3.3                  #"
log_info "#                                                 #"
log_info "#  CRITICAL FIX APPLIED:                          #"
log_info "#  ✓ Removed .ipynb_checkpoints directory         #"
log_info "#  ✓ Removed __pycache__ directories              #"
log_info "#  ✓ Skip hidden directories in node processing   #"
log_info "#  ✓ This fixes 'unsupported nodes' error!        #"
log_info "#                                                 #"
log_info "#  Your nodes should now load correctly!          #"
log_info "#                                                 #"
log_info "###################################################"

log_info "Details: ${PROVISION_MARKER}"
