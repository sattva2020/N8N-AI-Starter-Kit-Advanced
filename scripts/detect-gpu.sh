#!/bin/bash

# =============================================================================
# GPU Detection and Configuration Script for N8N AI Starter Kit
# =============================================================================
# This script automatically detects available GPUs and configures the environment
# for optimal performance with NVIDIA or AMD hardware.

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Utility functions
print_header() { echo -e "${BLUE}=== $1 ===${NC}"; }
print_info() { echo -e "${BLUE}ℹ  $1${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠  $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/.env"

# GPU detection functions
detect_nvidia_gpu() {
    print_info "Checking for NVIDIA GPUs..."
    
    # Check if nvidia-smi is available
    if command -v nvidia-smi >/dev/null 2>&1; then
        local gpu_count=$(nvidia-smi --query-gpu=count --format=csv,noheader,nounits | head -1)
        if [[ "$gpu_count" -gt 0 ]]; then
            print_success "Found $gpu_count NVIDIA GPU(s)"
            
            # Get GPU information
            echo "GPU Details:"
            nvidia-smi --query-gpu=index,name,memory.total,driver_version --format=csv,noheader | while read -r line; do
                echo "  - $line"
            done
            
            return 0
        fi
    fi
    
    # Check if Docker can access NVIDIA runtime
    if docker run --rm --gpus all nvidia/cuda:11.8-base-ubuntu22.04 nvidia-smi >/dev/null 2>&1; then
        print_success "NVIDIA Docker runtime is working"
        return 0
    fi
    
    print_warning "NVIDIA GPUs not detected or not accessible"
    return 1
}

detect_amd_gpu() {
    print_info "Checking for AMD GPUs..."
    
    # Check if rocm-smi is available
    if command -v rocm-smi >/dev/null 2>&1; then
        if rocm-smi --showid >/dev/null 2>&1; then
            local gpu_count=$(rocm-smi --showid | grep -c "GPU" || echo "0")
            if [[ "$gpu_count" -gt 0 ]]; then
                print_success "Found $gpu_count AMD GPU(s)"
                
                # Get GPU information
                echo "GPU Details:"
                rocm-smi --showproductname --showvram
                
                return 0
            fi
        fi
    fi
    
    # Check for AMD GPUs in lspci
    if lspci | grep -i amd | grep -i vga >/dev/null 2>&1; then
        print_warning "AMD GPU detected but ROCm not installed/configured"
        echo "AMD GPUs found in system:"
        lspci | grep -i amd | grep -i vga
        return 1
    fi
    
    print_warning "AMD GPUs not detected"
    return 1
}

check_docker_gpu_support() {
    print_info "Checking Docker GPU support..."
    
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker is not running"
        return 1
    fi
    
    # Check NVIDIA Docker support
    if docker run --rm --gpus all nvidia/cuda:11.8-base-ubuntu22.04 echo "NVIDIA Docker OK" >/dev/null 2>&1; then
        print_success "NVIDIA Docker runtime available"
        return 0
    fi
    
    print_warning "NVIDIA Docker runtime not available"
    print_info "To install NVIDIA Docker support:"
    echo "  1. Install nvidia-docker2: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html"
    echo "  2. Restart Docker daemon"
    echo "  3. Test with: docker run --rm --gpus all nvidia/cuda:11.8-base-ubuntu22.04 nvidia-smi"
    
    return 1
}

get_gpu_memory_info() {
    local gpu_type="$1"
    
    if [[ "$gpu_type" == "nvidia" ]]; then
        print_info "Getting NVIDIA GPU memory information..."
        
        # Get memory for each GPU
        nvidia-smi --query-gpu=index,memory.total --format=csv,noheader,nounits | while read -r line; do
            local gpu_id=$(echo "$line" | cut -d',' -f1 | tr -d ' ')
            local memory_mb=$(echo "$line" | cut -d',' -f2 | tr -d ' ')
            local memory_gb=$((memory_mb / 1024))
            
            echo "GPU $gpu_id: ${memory_gb}GB VRAM"
            
            # Suggest memory fraction based on available VRAM
            if [[ "$memory_gb" -ge 24 ]]; then
                echo "  Recommended GPU_MEMORY_FRACTION: 0.9"
            elif [[ "$memory_gb" -ge 12 ]]; then
                echo "  Recommended GPU_MEMORY_FRACTION: 0.8"
            elif [[ "$memory_gb" -ge 8 ]]; then
                echo "  Recommended GPU_MEMORY_FRACTION: 0.7"
            else
                echo "  Recommended GPU_MEMORY_FRACTION: 0.6"
            fi
        done
    fi
}

configure_gpu_environment() {
    local gpu_type="$1"
    
    print_info "Configuring GPU environment variables..."
    
    if [[ ! -f "$ENV_FILE" ]]; then
        print_error "Environment file not found: $ENV_FILE"
        print_info "Run setup.sh first to create the environment file"
        return 1
    fi
    
    # Update GPU_TYPE
    if grep -q "^GPU_TYPE=" "$ENV_FILE"; then
        sed -i "s/^GPU_TYPE=.*/GPU_TYPE=$gpu_type/" "$ENV_FILE"
    else
        echo "GPU_TYPE=$gpu_type" >> "$ENV_FILE"
    fi
    
    # Configure CUDA settings for NVIDIA
    if [[ "$gpu_type" == "nvidia" ]]; then
        if ! grep -q "^CUDA_VISIBLE_DEVICES=" "$ENV_FILE"; then
            echo "CUDA_VISIBLE_DEVICES=0" >> "$ENV_FILE"
        fi
        
        # Get recommended memory fraction
        local memory_gb=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
        memory_gb=$((memory_gb / 1024))
        
        local memory_fraction
        if [[ "$memory_gb" -ge 24 ]]; then
            memory_fraction="0.9"
        elif [[ "$memory_gb" -ge 12 ]]; then
            memory_fraction="0.8"
        elif [[ "$memory_gb" -ge 8 ]]; then
            memory_fraction="0.7"
        else
            memory_fraction="0.6"
        fi
        
        if grep -q "^GPU_MEMORY_FRACTION=" "$ENV_FILE"; then
            sed -i "s/^GPU_MEMORY_FRACTION=.*/GPU_MEMORY_FRACTION=$memory_fraction/" "$ENV_FILE"
        else
            echo "GPU_MEMORY_FRACTION=$memory_fraction" >> "$ENV_FILE"
        fi
    fi
    
    # Configure ROCm settings for AMD
    if [[ "$gpu_type" == "amd" ]]; then
        if ! grep -q "^ROCR_VISIBLE_DEVICES=" "$ENV_FILE"; then
            echo "ROCR_VISIBLE_DEVICES=0" >> "$ENV_FILE"
        fi
    fi
    
    print_success "GPU environment configured for $gpu_type"
}

suggest_gpu_profile() {
    local gpu_type="$1"
    
    print_info "GPU Profile Recommendations:"
    
    if [[ "$gpu_type" == "nvidia" ]] || [[ "$gpu_type" == "amd" ]]; then
        echo "To use GPU-accelerated services, add 'gpu' to your COMPOSE_PROFILES:"
        echo ""
        echo "  Current profiles: $(grep COMPOSE_PROFILES "$ENV_FILE" | cut -d'=' -f2)"
        echo "  Recommended: default,developer,monitoring,gpu"
        echo ""
        echo "Start with GPU support:"
        echo "  ./start.sh --profile default,developer,gpu"
        echo ""
        echo "Available GPU services:"
        echo "  - document-processor-gpu (port 8011): GPU-accelerated document processing"
        echo "  - lightrag-gpu (port 8013): Local AI models with GPU acceleration"
        echo "  - gpu-monitor (port 8014): Real-time GPU monitoring"
    else
        echo "No compatible GPUs detected. Use standard CPU profiles:"
        echo "  ./start.sh --profile default,developer,monitoring"
    fi
}

run_gpu_benchmark() {
    local gpu_type="$1"
    
    if [[ "$gpu_type" != "nvidia" ]]; then
        print_warning "GPU benchmark only available for NVIDIA GPUs currently"
        return 0
    fi
    
    print_info "Running GPU benchmark..."
    
    # Simple PyTorch GPU test
    docker run --rm --gpus all \
        pytorch/pytorch:2.1.0-cuda11.8-cudnn8-runtime \
        python -c "
import torch
if torch.cuda.is_available():
    print(f'CUDA devices: {torch.cuda.device_count()}')
    for i in range(torch.cuda.device_count()):
        print(f'GPU {i}: {torch.cuda.get_device_name(i)}')
    
    # Simple benchmark
    device = torch.device('cuda:0')
    x = torch.randn(1000, 1000).to(device)
    import time
    start = time.time()
    for _ in range(100):
        y = torch.mm(x, x)
    torch.cuda.synchronize()
    end = time.time()
    print(f'GPU benchmark: {(end-start)*1000:.2f}ms for 100 matrix multiplications')
else:
    print('CUDA not available')
" 2>/dev/null || print_warning "GPU benchmark failed"
}

main() {
    print_header "GPU Detection and Configuration"
    
    # Detect GPU type
    local gpu_type="none"
    
    if detect_nvidia_gpu; then
        gpu_type="nvidia"
        get_gpu_memory_info "$gpu_type"
        check_docker_gpu_support
        run_gpu_benchmark "$gpu_type"
    elif detect_amd_gpu; then
        gpu_type="amd"
        print_warning "AMD GPU support is experimental"
    else
        print_warning "No compatible GPUs detected"
        print_info "The system will use CPU-only mode"
    fi
    
    # Configure environment if GPU detected
    if [[ "$gpu_type" != "none" ]] && [[ -f "$ENV_FILE" ]]; then
        configure_gpu_environment "$gpu_type"
    fi
    
    # Show recommendations
    suggest_gpu_profile "$gpu_type"
    
    print_header "GPU Detection Complete"
    echo "Detected GPU type: $gpu_type"
    
    if [[ "$gpu_type" != "none" ]]; then
        print_success "Your system is ready for GPU acceleration!"
        print_info "Next steps:"
        echo "  1. ./start.sh --profile default,developer,gpu"
        echo "  2. Check GPU status: curl http://localhost:8014/gpu/info"
        echo "  3. Monitor usage: docker logs n8n-gpu-monitor"
    else
        print_info "Continue with CPU-only setup:"
        echo "  ./start.sh --profile default,developer,monitoring"
    fi
}

# Handle script arguments
case "${1:-}" in
    --nvidia)
        detect_nvidia_gpu && configure_gpu_environment "nvidia"
        ;;
    --amd)
        detect_amd_gpu && configure_gpu_environment "amd"
        ;;
    --benchmark)
        gpu_type=$(grep "^GPU_TYPE=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 || echo "nvidia")
        run_gpu_benchmark "$gpu_type"
        ;;
    --help|-h)
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --nvidia      Force NVIDIA GPU detection and configuration"
        echo "  --amd         Force AMD GPU detection and configuration"
        echo "  --benchmark   Run GPU performance benchmark"
        echo "  --help        Show this help message"
        echo ""
        echo "Without options, the script will auto-detect available GPUs."
        ;;
    *)
        main
        ;;
esac