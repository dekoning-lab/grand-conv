/*
 * convergence_gpu.c - Unified GPU interface dispatcher for Grand-Convergence
 *
 * This file dispatches GPU calls to the appropriate backend (CUDA or Metal).
 *
 * Copyright (c) 2026 de Koning Lab, University of Calgary
 */

#include "convergence_gpu.h"
#include <stdio.h>
#include <string.h>

/* Include backend-specific headers based on compile flags */
#ifdef USE_CUDA
#include "convergence_cuda.h"
#endif

#ifdef USE_METAL
#include "convergence_metal.h"
#endif

/* Check which GPU backend is available */
gpu_backend_t gpu_available(void) {
#ifdef USE_CUDA
    if (cuda_available()) {
        return GPU_BACKEND_CUDA;
    }
#endif

#ifdef USE_METAL
    if (metal_available()) {
        return GPU_BACKEND_METAL;
    }
#endif

    return GPU_BACKEND_NONE;
}

/* Get backend name as string */
const char* gpu_backend_name(gpu_backend_t backend) {
    switch (backend) {
        case GPU_BACKEND_CUDA:
            return "CUDA";
        case GPU_BACKEND_METAL:
            return "Metal";
        case GPU_BACKEND_NONE:
        default:
            return "None";
    }
}

/* Initialize GPU context */
int gpu_init(gpu_backend_t backend, char *device_name, size_t *globalMem) {
    switch (backend) {
#ifdef USE_CUDA
        case GPU_BACKEND_CUDA:
            return cuda_init(device_name, globalMem);
#endif

#ifdef USE_METAL
        case GPU_BACKEND_METAL:
            return metal_init(device_name, globalMem);
#endif

        case GPU_BACKEND_NONE:
        default:
            if (device_name) strcpy(device_name, "None");
            if (globalMem) *globalMem = 0;
            return -1;
    }
}

/* Main convergence calculation on GPU */
int gpu_convergence(
    gpu_backend_t backend,
    const double *h_conP_part1,
    size_t conP_part1_size,
    const unsigned int *h_offsets,
    int numNodes,
    const int *h_nodePairs,
    int numPairs,
    int numSites,
    int n,
    double *h_pConvergent,
    double *h_pDivergent)
{
    switch (backend) {
#ifdef USE_CUDA
        case GPU_BACKEND_CUDA:
            return cuda_convergence(
                h_conP_part1, conP_part1_size,
                h_offsets, numNodes,
                h_nodePairs, numPairs,
                numSites, n,
                h_pConvergent, h_pDivergent
            );
#endif

#ifdef USE_METAL
        case GPU_BACKEND_METAL:
            return metal_convergence(
                h_conP_part1, conP_part1_size,
                h_offsets, numNodes,
                h_nodePairs, numPairs,
                numSites, n,
                h_pConvergent, h_pDivergent
            );
#endif

        case GPU_BACKEND_NONE:
        default:
            fprintf(stderr, "Error: No GPU backend available\n");
            return -1;
    }
}

/* Cleanup GPU resources */
void gpu_cleanup(gpu_backend_t backend) {
    switch (backend) {
#ifdef USE_CUDA
        case GPU_BACKEND_CUDA:
            cuda_cleanup();
            break;
#endif

#ifdef USE_METAL
        case GPU_BACKEND_METAL:
            metal_cleanup();
            break;
#endif

        case GPU_BACKEND_NONE:
        default:
            break;
    }
}
