#!/bin/bash
# ComfyUI Provisioning Script
# Version: 1.3.0
# Date: 2025-11-20
#
# CHANGELOG:
# v1.3.0 (2025-11-20):
#   - CRITICAL FIX: Aggressive frontend package installation with verification
#   - CRITICAL FIX: Force reinstall pip if broken
#   - CRITICAL FIX: Install frontend MULTIPLE ways to ensure it works
#   - Added explicit import test for frontend package
#   - Added fallback pip installation methods
#
# v1.2.0 (2025-11-20):
#   - Robust custom node verification
#   - Only clone nodes if missing
#
# v1.1.0 (2025-11-20):
#   - Stop ComfyUI during provisioning
#   - Install requirements.txt
#
# v1.0.0 (2025-11-20):
#   - Initial release

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
log_info "#  ComfyUI Provisioning v1.3.0                  #"
log_info "#  AGGRESSIVE Frontend Fix                      #"
log_info "#################################################"

# ==============================================================================
# CRITICAL: Stop ComfyUI
# ==============================================================================
log_info "Stopping ComfyUI for safe provisioning..."
supervisorctl stop comfyui 2>/dev/null || log_warn "ComfyUI not running"
sleep 2

# Activate virtual environment
if [ -f "${VENV_PATH}/bin/activate" ]; then
    source "${VENV_PATH}/bin/activate"
    log_info "Virtual environment activated: ${VENV_PATH}"
else
    log_error "Virtual environment not found at ${VENV_PATH}"
    exit 1
fi

# ==============================================================================
# FUNCTION: Aggressive pip fix
# ==============================================================================
fix_pip_aggressively() {
    log_info "=== AGGRESSIVE PIP FIX ==="
    
    # Method 1: Try python -m pip
    if python -m pip --version > /dev/null 2>&1; then
        log_info "pip accessible via python -m pip"
        return 0
    fi
    
    log_warn "pip not accessible, trying fixes..."
    
    # Method 2: ensurepip
    log_info "Attempting ensurepip..."
    python -m ensurepip --upgrade 2>/dev/null || true
    
    if python -m pip --version > /dev/null 2>&1; then
        log_info "pip fixed via ensurepip ✓"
        return 0
    fi
    
    # Method 3: get-pip.py
    log_warn "ensurepip failed, downloading get-pip.py..."
    cd /tmp
    curl -sS https://bootstrap.pypa.io/get-pip.py -o get-pip.py
    python get-pip.py --force-reinstall
    
    if python -m pip --version > /dev/null 2>&1; then
        log_info "pip fixed via get-pip.py ✓"
        return 0
    fi
    
    log_error "All pip fix attempts FAILED"
    return 1
}

# ==============================================================================
# FUNCTION: Clear pip cache
# ==============================================================================
clear_pip_cache() {
    log_info "Clearing pip cache..."
    python -m pip cache purge 2>/dev/null || true
    
    if [ -d "${WORKSPACE}/.cache/pip" ]; then
        rm -rf "${WORKSPACE}/.cache/pip"
        log_info "Cleared workspace pip cache"
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
            log_info "PyTorch ${required_version}+cu${required_cuda} already installed"
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

# ==============================================================================
# FUNCTION: Upgrade PyTorch
# ==============================================================================
upgrade_pytorch() {
    log_info "Upgrading to PyTorch 2.7.0+cu128..."
    
    clear_pip_cache
    
    python -m pip uninstall -y torch torchvision torchaudio xformers 2>/dev/null || true
    
    python -m pip install --no-cache-dir --upgrade pip setuptools wheel
    
    python -m pip install --no-cache-dir \
        torch==2.7.0+cu128 \
        torchvision==0.22.0+cu128 \
        torchaudio==2.7.0+cu128 \
        --index-url https://download.pytorch.org/whl/cu128
    
    log_info "PyTorch installation complete"
}

# ==============================================================================
# MAIN PROVISIONING
# ==============================================================================

# FIX PIP FIRST - AGGRESSIVELY
fix_pip_aggressively || {
    log_error "Cannot proceed without working pip"
    exit 1
}

# Verify pip works
log_info "Verifying pip: $(python -m pip --version)"

# Check and upgrade PyTorch if needed
if ! check_pytorch_version; then
    upgrade_pytorch
    # Fix pip AGAIN after PyTorch (it can break)
    fix_pip_aggressively || {
        log_error "pip broken after PyTorch upgrade"
        exit 1
    }
else
    clear_pip_cache
fi

# ==============================================================================
# Install core dependencies
# ==============================================================================
log_info "Installing core dependencies..."

python -m pip install --no-cache-dir av
python -m pip install --no-cache-dir pydantic-settings
python -m pip install --no-cache-dir accelerate
python -m pip install --no-cache-dir requirements-parser
python -m pip install --no-cache-dir alembic
python -m pip install --no-cache-dir segment-anything

# ==============================================================================
# CRITICAL: AGGRESSIVE FRONTEND INSTALLATION
# ==============================================================================
log_info "###################################################"
log_info "#  AGGRESSIVE FRONTEND PACKAGE INSTALLATION       #"
log_info "###################################################"

# Method 1: Install from requirements.txt
if [ -f "${COMFYUI_PATH}/requirements.txt" ]; then
    log_info "Method 1: Installing from requirements.txt..."
    python -m pip install --no-cache-dir -r "${COMFYUI_PATH}/requirements.txt" --force-reinstall || \
        log_warn "requirements.txt install had issues"
fi

# Method 2: Direct package install
log_info "Method 2: Direct comfyui-frontend-package install..."
python -m pip install --no-cache-dir comfyui-frontend-package --force-reinstall || \
    log_warn "Direct frontend install had issues"

# Method 3: Upgrade to latest
log_info "Method 3: Upgrading to latest frontend..."
python -m pip install --no-cache-dir comfyui-frontend-package --upgrade || \
    log_warn "Frontend upgrade had issues"

# Method 4: Install specific version if others failed
log_info "Method 4: Installing specific frontend version..."
python -m pip install --no-cache-dir "comfyui-frontend-package>=0.3.0" --force-reinstall || \
    log_warn "Specific version install had issues"

# ==============================================================================
# CRITICAL: VERIFY FRONTEND ACTUALLY WORKS
# ==============================================================================
log_info "Verifying frontend package installation..."

if python -c "import comfyui_frontend; print(f'Version: {comfyui_frontend.__version__}')" 2>/dev/null; then
    FRONTEND_VERSION=$(python -c "import comfyui_frontend; print(comfyui_frontend.__version__)" 2>/dev/null)
    log_info "✓✓✓ FRONTEND PACKAGE VERIFIED: ${FRONTEND_VERSION} ✓✓✓"
else
    log_error "✗✗✗ FRONTEND PACKAGE STILL NOT WORKING ✗✗✗"
    log_error "Attempting emergency fix..."
    
    # Emergency fix: reinstall pip and try again
    python -m pip install --upgrade --force-reinstall pip
    python -m pip install --no-cache-dir --force-reinstall comfyui-frontend-package
    
    if python -c "import comfyui_frontend" 2>/dev/null; then
        log_info "Emergency fix succeeded ✓"
    else
        log_error "FRONTEND INSTALLATION FAILED COMPLETELY"
        log_error "ComfyUI will not start until this is fixed"
    fi
fi

# ==============================================================================
# Verify pip still works
# ==============================================================================
log_info "Final pip verification..."
if ! python -m pip --version > /dev/null 2>&1; then
    log_warn "pip broken again, fixing..."
    fix_pip_aggressively
fi

# ==============================================================================
# Install/verify ComfyUI Manager
# ==============================================================================
MANAGER_PATH="${COMFYUI_PATH}/custom_nodes/ComfyUI-Manager"
if [ ! -d "${MANAGER_PATH}" ]; then
    log_info "Installing ComfyUI Manager..."
    cd "${COMFYUI_PATH}/custom_nodes"
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git
    cd ComfyUI-Manager
    python -m pip install --no-cache-dir -r requirements.txt
else
    log_info "ComfyUI Manager exists, verifying..."
    if [ -f "${MANAGER_PATH}/requirements.txt" ]; then
        cd "${MANAGER_PATH}"
        python -m pip install --no-cache-dir -r requirements.txt
    fi
fi

# ==============================================================================
# Fix other custom nodes
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
        
        # Install requirements if present
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
# Create provision marker
# ==============================================================================
PROVISION_MARKER="${WORKSPACE}/.provisioned"
PROVISION_DATE=$(date +%Y-%m-%d_%H-%M-%S)

echo "Script version: 1.3.0" > "${PROVISION_MARKER}"
echo "Last provisioned: ${PROVISION_DATE}" >> "${PROVISION_MARKER}"
echo "PyTorch: $(python -c 'import torch; print(torch.__version__)')" >> "${PROVISION_MARKER}"
echo "CUDA: $(python -c 'import torch; print(torch.version.cuda)')" >> "${PROVISION_MARKER}"
echo "Frontend: $(python -c 'import comfyui_frontend; print(comfyui_frontend.__version__)' 2>/dev/null || echo 'FAILED')" >> "${PROVISION_MARKER}"
echo "pip: $(python -m pip --version 2>/dev/null || echo 'FAILED')" >> "${PROVISION_MARKER}"
echo "All verified: ${ALL_OK}" >> "${PROVISION_MARKER}"

# ==============================================================================
# Start ComfyUI
# ==============================================================================
if [ "$ALL_OK" = true ]; then
    log_info "All verifications passed ✓"
    log_info "Starting ComfyUI..."
    supervisorctl start comfyui
else
    log_warn "Some packages failed verification"
    log_warn "Starting ComfyUI anyway (may fail)..."
    supervisorctl start comfyui
fi

log_info "###################################################"
log_info "#  Provisioning Complete! v1.3.0                  #"
log_info "#                                                 #"
log_info "#  Critical Fixes:                                #"
log_info "#  ✓ Aggressive pip fixing (3 methods)            #"
log_info "#  ✓ Frontend installed 4 different ways          #"
log_info "#  ✓ Import verification for frontend             #"
log_info "#  ✓ Emergency fixes if installation fails        #"
log_info "#                                                 #"
log_info "###################################################"

log_info "Provisioning details: ${PROVISION_MARKER}"
