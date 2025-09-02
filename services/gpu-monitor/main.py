"""
GPU Monitor Service - Real-time GPU monitoring and management for N8N AI Starter Kit

This service provides:
- GPU utilization monitoring (NVIDIA, AMD)
- Memory usage tracking
- Temperature monitoring
- Process management
- Prometheus metrics export
"""

import asyncio
import logging
import os
import platform
import subprocess
import time
from typing import Dict, List, Optional, Any
from datetime import datetime
import json

import psutil
from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
import structlog

# Configure structured logging
logging.basicConfig(
    format="%(timestamp)s %(level)s %(message)s",
    level=logging.INFO
)
logger = structlog.get_logger()

# Prometheus metrics
gpu_utilization = Gauge('gpu_utilization_percent', 'GPU utilization percentage', ['gpu_id', 'gpu_name'])
gpu_memory_used = Gauge('gpu_memory_used_bytes', 'GPU memory used in bytes', ['gpu_id', 'gpu_name'])
gpu_memory_total = Gauge('gpu_memory_total_bytes', 'GPU memory total in bytes', ['gpu_id', 'gpu_name'])
gpu_temperature = Gauge('gpu_temperature_celsius', 'GPU temperature in Celsius', ['gpu_id', 'gpu_name'])
gpu_power_draw = Gauge('gpu_power_draw_watts', 'GPU power draw in watts', ['gpu_id', 'gpu_name'])

# API metrics
request_count = Counter('http_requests_total', 'Total HTTP requests', ['method', 'endpoint', 'status'])
request_duration = Histogram('http_request_duration_seconds', 'HTTP request duration')

app = FastAPI(
    title="GPU Monitor Service",
    description="Real-time GPU monitoring for N8N AI Starter Kit",
    version="1.0.0"
)

class GPUInfo(BaseModel):
    """GPU information model"""
    id: int
    name: str
    utilization: float
    memory_used: int
    memory_total: int
    memory_percent: float
    temperature: Optional[float] = None
    power_draw: Optional[float] = None
    driver_version: Optional[str] = None

class SystemInfo(BaseModel):
    """System information model"""
    gpu_type: str
    gpu_count: int
    gpus: List[GPUInfo]
    system_memory_used: int
    system_memory_total: int
    cpu_percent: float
    timestamp: datetime

class GPUMonitor:
    """GPU monitoring class with support for NVIDIA and AMD"""
    
    def __init__(self):
        self.gpu_type = self._detect_gpu_type()
        self.nvidia_available = False
        self.amd_available = False
        
        if self.gpu_type == "nvidia":
            self._init_nvidia()
        elif self.gpu_type == "amd":
            self._init_amd()
        
        logger.info(f"GPU Monitor initialized for {self.gpu_type} GPUs")
    
    def _detect_gpu_type(self) -> str:
        """Auto-detect GPU type"""
        gpu_type = os.getenv("GPU_TYPE", "auto").lower()
        
        if gpu_type != "auto":
            return gpu_type
        
        # Try NVIDIA first
        try:
            import pynvml
            pynvml.nvmlInit()
            return "nvidia"
        except:
            pass
        
        # Try AMD ROCm
        try:
            result = subprocess.run(['rocm-smi', '--showid'], capture_output=True, text=True)
            if result.returncode == 0:
                return "amd"
        except:
            pass
        
        return "none"
    
    def _init_nvidia(self):
        """Initialize NVIDIA monitoring"""
        try:
            import pynvml
            pynvml.nvmlInit()
            self.nvidia_available = True
            logger.info("NVIDIA GPU monitoring initialized")
        except Exception as e:
            logger.error(f"Failed to initialize NVIDIA monitoring: {e}")
    
    def _init_amd(self):
        """Initialize AMD monitoring"""
        try:
            # Check if rocm-smi is available
            result = subprocess.run(['rocm-smi', '--version'], capture_output=True, text=True)
            if result.returncode == 0:
                self.amd_available = True
                logger.info("AMD GPU monitoring initialized")
        except Exception as e:
            logger.error(f"Failed to initialize AMD monitoring: {e}")
    
    def get_nvidia_gpus(self) -> List[GPUInfo]:
        """Get NVIDIA GPU information"""
        if not self.nvidia_available:
            return []
        
        try:
            import pynvml
            
            gpus = []
            device_count = pynvml.nvmlDeviceGetCount()
            
            for i in range(device_count):
                handle = pynvml.nvmlDeviceGetHandleByIndex(i)
                name = pynvml.nvmlDeviceGetName(handle).decode('utf-8')
                
                # Get utilization
                util = pynvml.nvmlDeviceGetUtilizationRates(handle)
                
                # Get memory info
                mem_info = pynvml.nvmlDeviceGetMemoryInfo(handle)
                
                # Get temperature (may not be available on all GPUs)
                try:
                    temp = pynvml.nvmlDeviceGetTemperature(handle, pynvml.NVML_TEMPERATURE_GPU)
                except:
                    temp = None
                
                # Get power draw (may not be available on all GPUs)
                try:
                    power = pynvml.nvmlDeviceGetPowerUsage(handle) / 1000.0  # Convert to watts
                except:
                    power = None
                
                gpu_info = GPUInfo(
                    id=i,
                    name=name,
                    utilization=util.gpu,
                    memory_used=mem_info.used,
                    memory_total=mem_info.total,
                    memory_percent=(mem_info.used / mem_info.total) * 100,
                    temperature=temp,
                    power_draw=power
                )
                
                gpus.append(gpu_info)
                
                # Update Prometheus metrics
                gpu_utilization.labels(gpu_id=i, gpu_name=name).set(util.gpu)
                gpu_memory_used.labels(gpu_id=i, gpu_name=name).set(mem_info.used)
                gpu_memory_total.labels(gpu_id=i, gpu_name=name).set(mem_info.total)
                if temp is not None:
                    gpu_temperature.labels(gpu_id=i, gpu_name=name).set(temp)
                if power is not None:
                    gpu_power_draw.labels(gpu_id=i, gpu_name=name).set(power)
            
            return gpus
            
        except Exception as e:
            logger.error(f"Error getting NVIDIA GPU info: {e}")
            return []
    
    def get_amd_gpus(self) -> List[GPUInfo]:
        """Get AMD GPU information"""
        if not self.amd_available:
            return []
        
        try:
            # Use rocm-smi to get GPU information
            result = subprocess.run(['rocm-smi', '--showid', '--showuse', '--showmemuse', '--showtemp'], 
                                  capture_output=True, text=True)
            
            if result.returncode != 0:
                return []
            
            # Parse rocm-smi output (this is a simplified parser)
            gpus = []
            lines = result.stdout.split('\n')
            
            for i, line in enumerate(lines):
                if 'GPU' in line and 'card' in line:
                    # This is a simplified parser - real implementation would be more robust
                    gpu_info = GPUInfo(
                        id=i,
                        name=f"AMD GPU {i}",
                        utilization=0.0,  # Would need to parse actual values
                        memory_used=0,
                        memory_total=0,
                        memory_percent=0.0
                    )
                    gpus.append(gpu_info)
            
            return gpus
            
        except Exception as e:
            logger.error(f"Error getting AMD GPU info: {e}")
            return []
    
    def get_system_info(self) -> SystemInfo:
        """Get complete system information"""
        if self.gpu_type == "nvidia":
            gpus = self.get_nvidia_gpus()
        elif self.gpu_type == "amd":
            gpus = self.get_amd_gpus()
        else:
            gpus = []
        
        # Get system memory and CPU info
        memory = psutil.virtual_memory()
        cpu_percent = psutil.cpu_percent(interval=1)
        
        return SystemInfo(
            gpu_type=self.gpu_type,
            gpu_count=len(gpus),
            gpus=gpus,
            system_memory_used=memory.used,
            system_memory_total=memory.total,
            cpu_percent=cpu_percent,
            timestamp=datetime.now()
        )

# Global GPU monitor instance
gpu_monitor = GPUMonitor()

@app.middleware("http")
async def metrics_middleware(request, call_next):
    """Middleware to collect request metrics"""
    start_time = time.time()
    
    response = await call_next(request)
    
    duration = time.time() - start_time
    request_duration.observe(duration)
    request_count.labels(
        method=request.method,
        endpoint=request.url.path,
        status=response.status_code
    ).inc()
    
    return response

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "gpu_type": gpu_monitor.gpu_type,
        "nvidia_available": gpu_monitor.nvidia_available,
        "amd_available": gpu_monitor.amd_available,
        "timestamp": datetime.now().isoformat()
    }

@app.get("/gpu/info", response_model=SystemInfo)
async def get_gpu_info():
    """Get GPU and system information"""
    try:
        return gpu_monitor.get_system_info()
    except Exception as e:
        logger.error(f"Error getting GPU info: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/gpu/processes")
async def get_gpu_processes():
    """Get processes using GPU"""
    if gpu_monitor.gpu_type != "nvidia" or not gpu_monitor.nvidia_available:
        return {"processes": []}
    
    try:
        import pynvml
        
        all_processes = []
        device_count = pynvml.nvmlDeviceGetCount()
        
        for i in range(device_count):
            handle = pynvml.nvmlDeviceGetHandleByIndex(i)
            processes = pynvml.nvmlDeviceGetComputeRunningProcesses(handle)
            
            for proc in processes:
                try:
                    process_info = {
                        "gpu_id": i,
                        "pid": proc.pid,
                        "used_gpu_memory": proc.usedGpuMemory,
                    }
                    
                    # Get process name if possible
                    try:
                        ps_proc = psutil.Process(proc.pid)
                        process_info["name"] = ps_proc.name()
                        process_info["cmdline"] = " ".join(ps_proc.cmdline())
                    except:
                        process_info["name"] = "Unknown"
                        process_info["cmdline"] = ""
                    
                    all_processes.append(process_info)
                except:
                    continue
        
        return {"processes": all_processes}
        
    except Exception as e:
        logger.error(f"Error getting GPU processes: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

@app.get("/stats")
async def get_stats():
    """Get service statistics"""
    system_info = gpu_monitor.get_system_info()
    
    return {
        "service": "gpu-monitor",
        "version": "1.0.0",
        "uptime": time.time() - start_time,
        "gpu_count": system_info.gpu_count,
        "gpu_type": system_info.gpu_type,
        "total_gpu_memory": sum(gpu.memory_total for gpu in system_info.gpus),
        "used_gpu_memory": sum(gpu.memory_used for gpu in system_info.gpus),
    }

# Background task to update metrics
async def update_metrics():
    """Background task to continuously update metrics"""
    while True:
        try:
            gpu_monitor.get_system_info()  # This updates Prometheus metrics
            await asyncio.sleep(10)  # Update every 10 seconds
        except Exception as e:
            logger.error(f"Error updating metrics: {e}")
            await asyncio.sleep(30)  # Wait longer on error

# Store startup time
start_time = time.time()

@app.on_event("startup")
async def startup_event():
    """Startup event handler"""
    logger.info("Starting GPU Monitor Service")
    # Start background metrics collection
    asyncio.create_task(update_metrics())

if __name__ == "__main__":
    import uvicorn
    
    port = int(os.getenv("PORT", 8014))
    
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=port,
        reload=False
    )