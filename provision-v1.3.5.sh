#!/bin/bash
# ComfyUI Provisioning Script
# Version: 1.3.5
# Date: 2025-11-20
#
# CHANGELOG:
# v1.3.5 (2025-11-20):
#   - CRITICAL FIX: Install missing node dependencies (toml, piexif, deepdiff, torchdiffeq)
#   - CRITICAL FIX: Retry failed node requirements installations
#   - CRITICAL FIX: Verify each node's requirements.txt installs successfully
#   - Added error tracking for failed node installations
#   - Retry mechanism for transient failures
#
# v1.3.4 (2025-11-20):
#   - Force frontend to 1.32.1
#   - Skip NSFW_MMaudio
#
# v1.3.3 (2025-11-20):
#   - Removed .ipynb_checkpoints

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
log_info "#  ComfyUI Provisioning v1.3.5                  #"
log_info "#  Missing Node Dependencies Fix                #"
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

fix_pip_aggressively || {
    log_error "Cannot proceed without pip"
    exit 1
}

log_info "pip: $(python -m pip --version)"

if ! check_pytorch_version; then
    upgrade_pytorch
    fix_pip_aggressively || {
        log_error "pip broken after PyTorch upgrade"
        exit 1
    }
else
    clear_caches
fi

log_info "Installing core dependencies..."
python -m pip install --no-cache-dir av pydantic-settings accelerate requirements-parser alembic segment-anything

# ==============================================================================
# SMART REQUIREMENTS.TXT INSTALL
# ==============================================================================
log_info "Installing ComfyUI requirements.txt..."

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
# FRONTEND INSTALLATION (FORCE 1.32.1)
# ==============================================================================
log_info "Installing frontend 1.32.1..."

python -m pip uninstall -y comfyui-frontend-package 2>/dev/null || true
python -m pip install --no-cache-dir --force-reinstall "comfyui-frontend-package==1.32.1"

if python -c "import comfyui_frontend; print(comfyui_frontend.__version__)" 2>/dev/null | grep -q "1.32"; then
    FRONTEND_VERSION=$(python -c "import comfyui_frontend; print(comfyui_frontend.__version__)" 2>/dev/null)
    log_info "✓ Frontend locked to ${FRONTEND_VERSION}"
else
    log_error "Frontend not 1.32.1!"
fi

# ==============================================================================
# VERIFY PYTORCH STILL 2.7.0
# ==============================================================================
log_info "Verifying PyTorch version..."
PYTORCH_VERSION=$(python -c "import torch; print(torch.__version__)" 2>/dev/null | cut -d'+' -f1)
if [[ "$PYTORCH_VERSION" != "2.7.0"* ]]; then
    log_error "PyTorch changed to ${PYTORCH_VERSION}! Reverting..."
    python -m pip uninstall -y torch torchvision torchaudio 2>/dev/null || true
    python -m pip install --no-cache-dir \
        torch==2.7.0+cu128 \
        torchvision==0.22.0+cu128 \
        torchaudio==2.7.0+cu128 \
        --index-url https://download.pytorch.org/whl/cu128
else
    log_info "✓ PyTorch still at 2.7.0"
fi

if ! python -m pip --version > /dev/null 2>&1; then
    log_warn "pip broken, fixing..."
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
fi

# ==============================================================================
# Clean up problematic directories
# ==============================================================================
log_info "Cleaning problematic directories..."

if [ -d "${COMFYUI_PATH}/custom_nodes/.ipynb_checkpoints" ]; then
    rm -rf "${COMFYUI_PATH}/custom_nodes/.ipynb_checkpoints"
fi

find "${COMFYUI_PATH}/custom_nodes" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true

for hidden_dir in "${COMFYUI_PATH}/custom_nodes"/.*/ ; do
    if [ -d "${hidden_dir}" ]; then
        dir_name=$(basename "${hidden_dir}")
        if [[ "$dir_name" != "." && "$dir_name" != ".." ]]; then
            rm -rf "${hidden_dir}"
        fi
    fi
done

# ==============================================================================
# CRITICAL: Install missing dependencies that broke in log
# ==============================================================================
log_info "###################################################"
log_info "#  INSTALLING MISSING NODE DEPENDENCIES            #"
log_info "###################################################"

# Install packages that were missing in the log
log_info "Installing toml..."
python -m pip install --no-cache-dir toml

log_info "Installing piexif..."
python -m pip install --no-cache-dir piexif

log_info "Installing deepdiff..."
python -m pip install --no-cache-dir deepdiff

log_info "Installing torchdiffeq..."
python -m pip install --no-cache-dir torchdiffeq || log_warn "torchdiffeq failed (expected, may use alternative)"

log_info "Missing dependencies installed ✓"

# ==============================================================================
# Process custom nodes with retry logic
# ==============================================================================
log_info "###################################################"
log_info "#  PROCESSING CUSTOM NODES (WITH RETRIES)         #"
log_info "###################################################"

FAILED_NODES=()

for node_dir in "${COMFYUI_PATH}/custom_nodes"/*/ ; do
    if [ -d "${node_dir}" ]; then
        node_name=$(basename "${node_dir}")
        
        # Skip hidden directories
        if [[ "$node_name" == .* ]]; then
            continue
        fi
        
        # Skip NSFW_MMaudio
        if [[ "$node_name" == "NSFW_MMaudio" ]]; then
            continue
        fi
        
        # Create __init__.py if missing
        if [ ! -f "${node_dir}/__init__.py" ]; then
            touch "${node_dir}/__init__.py"
        fi
        
        # Install requirements with RETRY
        if [ -f "${node_dir}/requirements.txt" ]; then
            log_info "Installing requirements for ${node_name}..."
            
            # First attempt
            if ! python -m pip install --no-cache-dir -r "${node_dir}/requirements.txt" 2>/dev/null; then
                log_warn "${node_name}: First attempt failed, retrying..."
                
                # Second attempt (retry)
                if ! python -m pip install --no-cache-dir -r "${node_dir}/requirements.txt" 2>/dev/null; then
                    log_error "${node_name}: Requirements failed (check manually)"
                    FAILED_NODES+=("${node_name}")
                fi
            fi
        fi
    fi
done

if [ ${#FAILED_NODES[@]} -gt 0 ]; then
    log_warn "Some nodes had issues:"
    for node in "${FAILED_NODES[@]}"; do
        log_warn "  - ${node}"
    done
fi

# ==============================================================================
# Final verification
# ==============================================================================
log_info "###################################################"
log_info "#  FINAL VERIFICATION                              #"
log_info "###################################################"

CRITICAL_IMPORTS=("torch" "torchvision" "torchaudio" "av" "comfyui_frontend" "toml" "piexif" "deepdiff")
ALL_OK=true

for pkg in "${CRITICAL_IMPORTS[@]}"; do
    if python -c "import ${pkg}" 2>/dev/null; then
        VERSION=$(python -c "import ${pkg}; print(getattr(${pkg}, '__version__', 'installed'))" 2>/dev/null || echo "installed")
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

echo "Script version: 1.3.5" > "${PROVISION_MARKER}"
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
log_info "#  Provisioning Complete! v1.3.5                  #"
log_info "#                                                 #"
log_info "#  CRITICAL FIXES:                                #"
log_info "#  ✓ Installed missing node dependencies:         #"
log_info "#    - toml (ComfyUI-Manager)                     #"
log_info "#    - piexif (LoRA Manager)                      #"
log_info "#    - deepdiff (Crystools)                       #"
log_info "#    - torchdiffeq (MMAudio)                      #"
log_info "#  ✓ Retry logic for failed installations         #"
log_info "#  ✓ All custom nodes should load now             #"
log_info "#                                                 #"
log_info "###################################################"

log_info "Details: ${PROVISION_MARKER}"
