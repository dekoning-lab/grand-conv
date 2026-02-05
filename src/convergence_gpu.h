/*
 * convergence_gpu.h - Unified GPU interface for Grand-Convergence
 *
 * This header provides a backend-agnostic interface for GPU-accelerated
 * convergence/divergence calculations. Supports CUDA (NVIDIA) and Metal (Apple).
 *
 * Copyright (c) 2026 de Koning Lab, University of Calgary
 */

#ifndef CONVERGENCE_GPU_H
#define CONVERGENCE_GPU_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* GPU backend types */
typedef enum {
    GPU_BACKEND_NONE = 0,
    GPU_BACKEND_CUDA = 1,
    GPU_BACKEND_METAL = 2
} gpu_backend_t;

/* Check which GPU backend is available (returns best available) */
gpu_backend_t gpu_available(void);

/* Get backend name as string */
const char* gpu_backend_name(gpu_backend_t backend);

/* Initialize GPU context
 * Returns: 0 on success, -1 on failure
 * device_name: buffer to receive device name (should be at least 256 bytes)
 * globalMem: receives available GPU memory in bytes
 */
int gpu_init(gpu_backend_t backend, char *device_name, size_t *globalMem);

/* Main convergence calculation on GPU
 *
 * Parameters:
 *   backend         - GPU backend to use
 *   h_conP_part1    - Host pointer to posterior substitution probability matrices
 *   conP_part1_size - Size of conP_part1 in bytes
 *   h_offsets       - Host pointer to per-node offsets into conP_part1
 *   numNodes        - Number of nodes in the tree
 *   h_nodePairs     - Host pointer to node pairs array [inode, jnode, selected] x numPairs
 *   numPairs        - Number of branch pairs to process
 *   numSites        - Number of sites in the alignment
 *   n               - State space size (20 for amino acids)
 *   h_pConvergent   - Host output array for convergence probabilities
 *   h_pDivergent    - Host output array for divergence probabilities
 *
 * Returns: 0 on success, -1 on failure
 */
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
    double *h_pDivergent
);

/* Cleanup GPU resources */
void gpu_cleanup(gpu_backend_t backend);

#ifdef __cplusplus
}
#endif

#endif /* CONVERGENCE_GPU_H */
