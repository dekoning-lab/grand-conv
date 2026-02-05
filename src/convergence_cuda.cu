/*
 * convergence_cuda.cu - CUDA kernel implementation for Grand-Convergence
 *
 * This file contains the CUDA kernel for GPU-accelerated convergence/divergence
 * calculations on NVIDIA GPUs (targeting V100, A100).
 *
 * Copyright (c) 2026 de Koning Lab, University of Calgary
 */

#include "convergence_cuda.h"
#include <cuda_runtime.h>
#include <stdio.h>
#include <string.h>

/* Block size for kernel launch - optimized for V100/A100 */
#define BLOCK_SIZE 256

/* Error checking macro */
#define CUDA_CHECK(call) do { \
    cudaError_t err = call; \
    if (err != cudaSuccess) { \
        fprintf(stderr, "CUDA error in %s:%d: %s\n", __FILE__, __LINE__, \
                cudaGetErrorString(err)); \
        return -1; \
    } \
} while(0)

/* Static device pointers for persistent allocations */
static double *d_conP_part1 = NULL;
static unsigned int *d_offsets = NULL;
static int *d_nodePairs = NULL;
static double *d_pConvergent = NULL;
static double *d_pDivergent = NULL;
static size_t allocated_conP_size = 0;
static size_t allocated_output_size = 0;

/*
 * CUDA Kernel: convergence_kernel
 *
 * Computes convergent and divergent substitution probabilities for each
 * (site, branch_pair) combination.
 *
 * Grid: (numPairs, ceil(numSites / BLOCK_SIZE))
 * Block: (BLOCK_SIZE, 1, 1)
 *
 * Each thread handles one (site, pair) combination.
 */
__global__ void convergence_kernel(
    const double* __restrict__ conP_part1,
    const unsigned int* __restrict__ offsets,
    const int* __restrict__ nodePairs,
    double* __restrict__ pConvergent,
    double* __restrict__ pDivergent,
    int numSites,
    int numPairs,
    int n)
{
    int pairIdx = blockIdx.x;
    int siteIdx = blockIdx.y * blockDim.x + threadIdx.x;

    if (pairIdx >= numPairs || siteIdx >= numSites) return;

    /* Get node indices for this pair */
    int inode = nodePairs[pairIdx * 3];
    int jnode = nodePairs[pairIdx * 3 + 1];

    /* Pointers to this site's matrices (n x n each) */
    const double* P1 = conP_part1 + offsets[inode] + siteIdx * n * n;
    const double* P2 = conP_part1 + offsets[jnode] + siteIdx * n * n;

    /* Local arrays for column sums */
    double sumcK[20];
    double sumdK[20];
    double sumdforJ = 0.0;

    /* Initialize sumcK to zero */
    #pragma unroll
    for (int k = 0; k < 20; k++) {
        sumcK[k] = 0.0;
    }

    /* Compute sumcK (convergence component) - sum over rows for each column
     * sumcK[k] = sum over j of P2[j,k] excluding diagonal
     * Also compute total sum for divergence
     */
    for (int j = 0; j < n; j++) {
        #pragma unroll
        for (int k = 0; k < n; k++) {
            double val = P2[j * n + k];
            sumcK[k] += val;
            sumdforJ += val;
        }
        /* Subtract diagonal from sumcK */
        sumcK[j] -= P2[j * n + j];
        /* Subtract diagonal from total */
        sumdforJ -= P2[j * n + j];
    }

    /* Compute sumdK (divergence component)
     * sumdK[k] = total - sumcK[k]
     */
    #pragma unroll
    for (int k = 0; k < n; k++) {
        sumdK[k] = sumdforJ - sumcK[k];
    }

    /* Compute convergence and divergence probabilities
     * probC = sum over i,j of P1[i,j] * sumcK[j] (excluding diagonal)
     * probD = sum over i,j of P1[i,j] * sumdK[j] (excluding diagonal)
     */
    double probC = 0.0;
    double probD = 0.0;

    for (int j = 0; j < n; j++) {
        #pragma unroll
        for (int k = 0; k < n; k++) {
            double p1_val = P1[j * n + k];
            probC += sumcK[k] * p1_val;
            probD += sumdK[k] * p1_val;
        }
        /* Subtract diagonal contributions */
        double p1_diag = P1[j * n + j];
        probC -= sumcK[j] * p1_diag;
        probD -= sumdK[j] * p1_diag;
    }

    /* Write output - layout: [pair][site] */
    int outIdx = pairIdx * numSites + siteIdx;
    pConvergent[outIdx] = probC;
    pDivergent[outIdx] = probD;
}

/* Check if CUDA is available */
extern "C" int cuda_available(void)
{
    int deviceCount = 0;
    cudaError_t err = cudaGetDeviceCount(&deviceCount);
    if (err != cudaSuccess || deviceCount == 0) {
        return 0;
    }
    return 1;
}

/* Initialize CUDA context */
extern "C" int cuda_init(char *device_name, size_t *globalMem)
{
    int deviceCount = 0;
    cudaError_t err = cudaGetDeviceCount(&deviceCount);
    if (err != cudaSuccess || deviceCount == 0) {
        if (device_name) strcpy(device_name, "None");
        if (globalMem) *globalMem = 0;
        return -1;
    }

    /* Use device 0 (could be made configurable) */
    CUDA_CHECK(cudaSetDevice(0));

    cudaDeviceProp prop;
    CUDA_CHECK(cudaGetDeviceProperties(&prop, 0));

    if (device_name) {
        strncpy(device_name, prop.name, 255);
        device_name[255] = '\0';
    }
    if (globalMem) {
        *globalMem = prop.totalGlobalMem;
    }

    /* Print device info */
    printf("CUDA device: %s\n", prop.name);
    printf("  Compute capability: %d.%d\n", prop.major, prop.minor);
    printf("  Global memory: %.2f GB\n", prop.totalGlobalMem / (1024.0 * 1024.0 * 1024.0));
    printf("  Multiprocessors: %d\n", prop.multiProcessorCount);
    printf("  Max threads per block: %d\n", prop.maxThreadsPerBlock);

    return 0;
}

/* Main convergence calculation on CUDA */
extern "C" int cuda_convergence(
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
    size_t output_size = (size_t)numPairs * numSites * sizeof(double);
    size_t offsets_size = (size_t)(numNodes + 1) * sizeof(unsigned int);
    size_t pairs_size = (size_t)numPairs * 3 * sizeof(int);

    /* Allocate or reallocate device memory as needed */
    if (d_conP_part1 == NULL || allocated_conP_size < conP_part1_size) {
        if (d_conP_part1) cudaFree(d_conP_part1);
        CUDA_CHECK(cudaMalloc(&d_conP_part1, conP_part1_size));
        allocated_conP_size = conP_part1_size;
    }

    if (d_pConvergent == NULL || allocated_output_size < output_size) {
        if (d_pConvergent) cudaFree(d_pConvergent);
        if (d_pDivergent) cudaFree(d_pDivergent);
        CUDA_CHECK(cudaMalloc(&d_pConvergent, output_size));
        CUDA_CHECK(cudaMalloc(&d_pDivergent, output_size));
        allocated_output_size = output_size;
    }

    /* Allocate temporary buffers for offsets and pairs */
    if (d_offsets) cudaFree(d_offsets);
    if (d_nodePairs) cudaFree(d_nodePairs);
    CUDA_CHECK(cudaMalloc(&d_offsets, offsets_size));
    CUDA_CHECK(cudaMalloc(&d_nodePairs, pairs_size));

    /* Copy input data to device */
    CUDA_CHECK(cudaMemcpy(d_conP_part1, h_conP_part1, conP_part1_size, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_offsets, h_offsets, offsets_size, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_nodePairs, h_nodePairs, pairs_size, cudaMemcpyHostToDevice));

    /* Configure grid and block dimensions
     * Grid: (numPairs, ceil(numSites / BLOCK_SIZE))
     * Block: (BLOCK_SIZE, 1, 1)
     */
    dim3 blockDim(BLOCK_SIZE, 1, 1);
    dim3 gridDim(numPairs, (numSites + BLOCK_SIZE - 1) / BLOCK_SIZE, 1);

    /* Launch kernel */
    convergence_kernel<<<gridDim, blockDim>>>(
        d_conP_part1,
        d_offsets,
        d_nodePairs,
        d_pConvergent,
        d_pDivergent,
        numSites,
        numPairs,
        n
    );

    /* Check for kernel launch errors */
    CUDA_CHECK(cudaGetLastError());

    /* Wait for kernel to complete */
    CUDA_CHECK(cudaDeviceSynchronize());

    /* Copy results back to host */
    CUDA_CHECK(cudaMemcpy(h_pConvergent, d_pConvergent, output_size, cudaMemcpyDeviceToHost));
    CUDA_CHECK(cudaMemcpy(h_pDivergent, d_pDivergent, output_size, cudaMemcpyDeviceToHost));

    return 0;
}

/* Cleanup CUDA resources */
extern "C" void cuda_cleanup(void)
{
    if (d_conP_part1) {
        cudaFree(d_conP_part1);
        d_conP_part1 = NULL;
    }
    if (d_offsets) {
        cudaFree(d_offsets);
        d_offsets = NULL;
    }
    if (d_nodePairs) {
        cudaFree(d_nodePairs);
        d_nodePairs = NULL;
    }
    if (d_pConvergent) {
        cudaFree(d_pConvergent);
        d_pConvergent = NULL;
    }
    if (d_pDivergent) {
        cudaFree(d_pDivergent);
        d_pDivergent = NULL;
    }
    allocated_conP_size = 0;
    allocated_output_size = 0;

    cudaDeviceReset();
}
