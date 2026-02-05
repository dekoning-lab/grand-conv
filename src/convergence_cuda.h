/*
 * convergence_cuda.h - CUDA backend for Grand-Convergence GPU acceleration
 *
 * This header declares the CUDA-specific functions for GPU-accelerated
 * convergence/divergence calculations on NVIDIA GPUs.
 *
 * Copyright (c) 2026 de Koning Lab, University of Calgary
 */

#ifndef CONVERGENCE_CUDA_H
#define CONVERGENCE_CUDA_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Check if CUDA is available on this system */
int cuda_available(void);

/* Initialize CUDA context
 * Returns: 0 on success, -1 on failure
 * device_name: buffer to receive device name (should be at least 256 bytes)
 * globalMem: receives available GPU memory in bytes
 */
int cuda_init(char *device_name, size_t *globalMem);

/* Main convergence calculation on CUDA
 *
 * Parameters:
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
int cuda_convergence(
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

/* Cleanup CUDA resources */
void cuda_cleanup(void);

#ifdef __cplusplus
}
#endif

#endif /* CONVERGENCE_CUDA_H */
