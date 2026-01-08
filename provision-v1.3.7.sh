#!/bin/bash

# AI-Dock ComfyUI Provisioning Script v1.3.7
# Updated with PyTorch 2.7.1, SageAttention, and Triton 3.1.0
# Based on AI-Dock ComfyUI provisioning

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Determine Python executable path
PYTHON="${PYTHON:-python3}"
PIP="${PYTHON} -m pip"

echo -e "${BLUE}=== AI-Dock ComfyUI Provisioning v1.3.7 ===${NC}"
echo -e "${BLUE}PyTorch 2.7.1 + SageAttention + Triton 3.1.0${NC}\n"

# ============================================================================
# PYTORCH VERSION CHECK AND INSTALLATION
# ============================================================================
echo -e "${BLUE}Checking PyTorch version...${NC}"

# Get current torch version
CURRENT_TORCH_VERSION=$($PYTHON -c "import torch; print(torch.__version__)" 2>/dev/null || echo "0.0.0")
REQUIRED_TORCH_VERSION="2.7.1"

echo -e "Current PyTorch version: ${YELLOW}${CURRENT_TORCH_VERSION}${NC}"
echo -e "Required PyTorch version: ${YELLOW}${REQUIRED_TORCH_VERSION}${NC}"

# Compare versions (simple string comparison for X.Y.Z format)
CURRENT_MAJOR=$(echo $CURRENT_TORCH_VERSION | cut -d. -f1)
CURRENT_MINOR=$(echo $CURRENT_TORCH_VERSION | cut -d. -f2)
CURRENT_PATCH=$(echo $CURRENT_TORCH_VERSION | cut -d. -f3 | cut -d+ -f1)  # Remove +cu part

REQUIRED_MAJOR=$(echo $REQUIRED_TORCH_VERSION | cut -d. -f1)
REQUIRED_MINOR=$(echo $REQUIRED_TORCH_VERSION | cut -d. -f2)
REQUIRED_PATCH=$(echo $REQUIRED_TORCH_VERSION | cut -d. -f3)

# Check if upgrade is needed
TORCH_UPGRADE_NEEDED=false

if [ "$CURRENT_MAJOR" -lt "$REQUIRED_MAJOR" ]; then
    TORCH_UPGRADE_NEEDED=true
elif [ "$CURRENT_MAJOR" -eq "$REQUIRED_MAJOR" ]; then
    if [ "$CURRENT_MINOR" -lt "$REQUIRED_MINOR" ]; then
        TORCH_UPGRADE_NEEDED=true
    elif [ "$CURRENT_MINOR" -eq "$REQUIRED_MINOR" ]; then
        if [ "${CURRENT_PATCH:-0}" -lt "$REQUIRED_PATCH" ]; then
            TORCH_UPGRADE_NEEDED=true
        fi
    fi
fi

if [ "$TORCH_UPGRADE_NEEDED" = true ]; then
    echo -e "${YELLOW}PyTorch upgrade needed. Installing ${REQUIRED_TORCH_VERSION}...${NC}"
    
    # Uninstall existing PyTorch packages
    echo -e "${YELLOW}Uninstalling old PyTorch packages...${NC}"
    $PIP uninstall -y torch torchvision torchaudio 2>/dev/null || true
    
    # Install PyTorch 2.7.1 with CUDA 12.8
    echo -e "${YELLOW}Installing PyTorch ${REQUIRED_TORCH_VERSION}...${NC}"
    $PIP install torch==2.7.1 torchvision==0.22.1 torchaudio==2.7.1 \
        --index-url https://download.pytorch.org/whl/cu128 \
        --force-reinstall --no-cache-dir
    
    echo -e "${GREEN}PyTorch upgraded successfully${NC}\n"
else
    echo -e "${GREEN}PyTorch version is acceptable${NC}\n"
fi

# ============================================================================
# TRITON VERSION CHECK AND INSTALLATION
# ============================================================================
echo -e "${BLUE}Checking Triton version...${NC}"

CURRENT_TRITON_VERSION=$($PYTHON -c "import triton; print(triton.__version__)" 2>/dev/null || echo "0.0.0")
REQUIRED_TRITON_VERSION="3.1.0"

echo -e "Current Triton version: ${YELLOW}${CURRENT_TRITON_VERSION}${NC}"
echo -e "Required Triton version: ${YELLOW}${REQUIRED_TRITON_VERSION}${NC}"

TRITON_INSTALL_NEEDED=false

if [ "$CURRENT_TRITON_VERSION" = "0.0.0" ]; then
    TRITON_INSTALL_NEEDED=true
else
    CURRENT_TRITON_MAJOR=$(echo $CURRENT_TRITON_VERSION | cut -d. -f1)
    CURRENT_TRITON_MINOR=$(echo $CURRENT_TRITON_VERSION | cut -d. -f2)
    CURRENT_TRITON_PATCH=$(echo $CURRENT_TRITON_VERSION | cut -d. -f3 | cut -d+ -f1)
    
    REQUIRED_TRITON_MAJOR=$(echo $REQUIRED_TRITON_VERSION | cut -d. -f1)
    REQUIRED_TRITON_MINOR=$(echo $REQUIRED_TRITON_VERSION | cut -d. -f2)
    REQUIRED_TRITON_PATCH=$(echo $REQUIRED_TRITON_VERSION | cut -d. -f3)
    
    if [ "$CURRENT_TRITON_MAJOR" -lt "$REQUIRED_TRITON_MAJOR" ]; then
        TRITON_INSTALL_NEEDED=true
    elif [ "$CURRENT_TRITON_MAJOR" -eq "$REQUIRED_TRITON_MAJOR" ]; then
        if [ "$CURRENT_TRITON_MINOR" -lt "$REQUIRED_TRITON_MINOR" ]; then
            TRITON_INSTALL_NEEDED=true
        elif [ "$CURRENT_TRITON_MINOR" -eq "$REQUIRED_TRITON_MINOR" ]; then
            if [ "${CURRENT_TRITON_PATCH:-0}" -lt "$REQUIRED_TRITON_PATCH" ]; then
                TRITON_INSTALL_NEEDED=true
            fi
        fi
    fi
fi

if [ "$TRITON_INSTALL_NEEDED" = true ]; then
    echo -e "${YELLOW}Installing Triton ${REQUIRED_TRITON_VERSION}...${NC}"
    $PIP install "triton==${REQUIRED_TRITON_VERSION}" --no-cache-dir
    echo -e "${GREEN}Triton installed successfully${NC}\n"
else
    echo -e "${GREEN}Triton version is acceptable${NC}\n"
fi

# ============================================================================
# SAGEATTENTION INSTALLATION CHECK
# ============================================================================
echo -e "${BLUE}Checking SageAttention installation...${NC}"

if $PYTHON -c "import sageattention" 2>/dev/null; then
    CURRENT_SAGE_VERSION=$($PYTHON -c "import sageattention; print(getattr(sageattention, '__version__', 'unknown'))")
    echo -e "${GREEN}SageAttention is installed (version: ${CURRENT_SAGE_VERSION})${NC}\n"
else
    echo -e "${YELLOW}SageAttention not found. Installing...${NC}"
    $PIP install sageattention --no-cache-dir
    echo -e "${GREEN}SageAttention installed successfully${NC}\n"
fi

# ============================================================================
# VERIFICATION
# ============================================================================
echo -e "${BLUE}=== VERIFICATION ===${NC}"

echo -e "${BLUE}PyTorch:${NC}"
$PYTHON -c "import torch; print(f'  Version: {torch.__version__}'); print(f'  CUDA available: {torch.cuda.is_available()}')"

echo -e "\n${BLUE}Triton:${NC}"
$PYTHON -c "import triton; print(f'  Version: {triton.__version__}')" 2>/dev/null || echo "  Not found (this may be expected)"

echo -e "\n${BLUE}SageAttention:${NC}"
$PYTHON -c "import sageattention; print(f'  Installed: True')" 2>/dev/null || echo "  Not found"

echo -e "\n${GREEN}=== Provisioning Complete ===${NC}"
echo -e "${GREEN}Your system is ready for WAN 2.2 SVI workflows!${NC}"
