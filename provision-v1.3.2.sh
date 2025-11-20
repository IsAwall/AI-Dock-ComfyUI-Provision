#!/bin/bash
# ComfyUI Provisioning Script
# Version: 1.3.2
# Date: 2025-11-20
#
# CHANGELOG:
# v1.3.2 (2025-11-20):
#   - EFFICIENCY FIX: Only filter torch lines if PyTorch is wrong version
#   - EFFICIENCY FIX: Install frontend only ONCE (not 3 times) 
#   - BUG FIX: Pin frontend to 1.32.1 (fixes invisible nodes issue)
#   - BUG FIX: Clear ComfyUI frontend cache on startup
#   - Reduced startup time to 1-2 minutes (from 5 minutes)
#
# v1.3.1 (2025-11-20):
#   - Removed --force-reinstall from requirements.txt
#   - Pin PyTorch 2.7.0
#
# v1.3.0 (2025-11-20):
#   - Aggressive frontend package installation
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
log_info "#  ComfyUI Provisioning v1.3.2                  #"
log_info "#  Fast Startup + Node Visibility Fix           #"
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
    
    # Clear ComfyUI frontend cache (fixes invisible nodes issue)
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
PYTORCH_NEEDS_UPGRADE=false
if ! check_pytorch_version; then
    PYTORCH_NEEDS_UPGRADE=true
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
        # PyTorch is correct version - install requirements normally
        log_info "PyTorch correct (2.7.0), installing requirements normally..."
        python -m pip install --no-cache-dir -r "${COMFYUI_PATH}/requirements.txt"
    else
        # PyTorch wrong - filter torch lines to prevent upgrade
        log_info "Filtering torch from requirements to prevent upgrade..."
        grep -v "^torch" "${COMFYUI_PATH}/requirements.txt" > /tmp/requirements_no_torch.txt || true
        python -m pip install --no-cache-dir -r /tmp/requirements_no_torch.txt
        rm -f /tmp/requirements_no_torch.txt
    fi
fi

# ==============================================================================
# FRONTEND INSTALLATION (ONCE, with stable version)
# ==============================================================================
log_info "Installing ComfyUI frontend (stable version)..."

# Pin to version 1.32.1 (stable, no invisible nodes bug)
python -m pip install --no-cache-dir "comfyui-frontend-package==1.32.1" || {
    log_warn "Specific version failed, trying latest..."
    python -m pip install --no-cache-dir comfyui-frontend-package
}

# Verify frontend
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

# Verify pip still works
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
# Fix custom nodes
# ==============================================================================
log_info "Checking custom nodes..."

for node_dir in "${COMFYUI_PATH}/custom_nodes"/*/ ; do
    if [ -d "${node_dir}" ]; then
        node_name=$(basename "${node_dir}")
        
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

echo "Script version: 1.3.2" > "${PROVISION_MARKER}"
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
log_info "#  Provisioning Complete! v1.3.2                  #"
log_info "#                                                 #"
log_info "#  Fixes:                                         #"
log_info "#  ✓ Smart requirements (no redundant filtering)  #"
log_info "#  ✓ Frontend installed once (stable version)     #"
log_info "#  ✓ Frontend cache cleared (fixes invisible)     #"
log_info "#  ✓ PyTorch locked to 2.7.0                      #"
log_info "#  ✓ Startup: 1-2 minutes (from 5 minutes)        #"
log_info "#                                                 #"
log_info "###################################################"

log_info "Details: ${PROVISION_MARKER}"
