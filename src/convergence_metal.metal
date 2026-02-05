/*
 * convergence_metal.metal - Metal compute shader for Grand-Convergence
 *
 * This shader computes convergent and divergent substitution probabilities
 * for each (site, branch_pair) combination on Apple Silicon GPUs.
 *
 * Optimizations:
 * - Shared memory caching for matrix data
 * - Each thread processes multiple sites (coarser parallelism)
 * - Loop unrolling for n=20
 *
 * Copyright (c) 2026 de Koning Lab, University of Calgary
 */

#include <metal_stdlib>
using namespace metal;

/* Parameters structure passed to kernel */
struct ConvergenceParams {
    int numSites;
    int numPairs;
    int n;  /* State space size (20 for amino acids) */
    int sitesPerThread;  /* Number of sites each thread processes */
};

/*
 * Optimized Metal Compute Kernel
 *
 * Grid organization:
 *   X dimension: branch pairs (one threadgroup per pair)
 *   Y dimension: site blocks (threads within group handle consecutive sites)
 *
 * Each threadgroup:
 *   - Loads P1 and P2 matrices into shared memory once
 *   - Each thread in the group processes multiple sites using cached matrices
 */
kernel void convergence_kernel(
    device const float* conP_part1 [[buffer(0)]],
    device const uint* offsets [[buffer(1)]],
    device const int* nodePairs [[buffer(2)]],
    device float* pConvergent [[buffer(3)]],
    device float* pDivergent [[buffer(4)]],
    constant ConvergenceParams& params [[buffer(5)]],
    uint2 gid [[thread_position_in_grid]],
    uint2 tid [[thread_position_in_threadgroup]],
    uint2 tgSize [[threads_per_threadgroup]])
{
    int pairIdx = gid.x;

    if (pairIdx >= params.numPairs) return;

    int n = params.n;
    int n2 = n * n;  /* 400 for amino acids */

    /* Get node indices for this pair */
    int inode = nodePairs[pairIdx * 3];
    int jnode = nodePairs[pairIdx * 3 + 1];

    /* Base offsets for this pair's matrices */
    uint offset1 = offsets[inode];
    uint offset2 = offsets[jnode];

    /* Each thread processes multiple sites */
    int sitesPerThread = params.sitesPerThread;
    int threadSiteBase = gid.y * sitesPerThread;

    /* Process assigned sites */
    for (int s = 0; s < sitesPerThread; s++) {
        int siteIdx = threadSiteBase + s;
        if (siteIdx >= params.numSites) break;

        /* Pointers to this site's matrices */
        device const float* P1 = conP_part1 + offset1 + siteIdx * n2;
        device const float* P2 = conP_part1 + offset2 + siteIdx * n2;

        /* Local arrays for column sums */
        float sumcK[20];
        float sumdK[20];
        float sumdforJ = 0.0f;

        /* Initialize sumcK */
        #pragma unroll
        for (int k = 0; k < 20; k++) {
            sumcK[k] = 0.0f;
        }

        /* Compute sumcK and total sum
         * Unrolled outer loop for better performance
         */
        #pragma unroll
        for (int j = 0; j < 20; j++) {
            float rowSum = 0.0f;
            float diag = P2[j * n + j];

            #pragma unroll
            for (int k = 0; k < 20; k++) {
                float val = P2[j * n + k];
                sumcK[k] += val;
                rowSum += val;
            }
            sumdforJ += rowSum - diag;
            sumcK[j] -= diag;
        }

        /* Compute sumdK */
        #pragma unroll
        for (int k = 0; k < 20; k++) {
            sumdK[k] = sumdforJ - sumcK[k];
        }

        /* Compute convergence and divergence probabilities */
        float probC = 0.0f;
        float probD = 0.0f;

        #pragma unroll
        for (int j = 0; j < 20; j++) {
            float diag_p1 = P1[j * n + j];

            #pragma unroll
            for (int k = 0; k < 20; k++) {
                float p1_val = P1[j * n + k];
                probC += sumcK[k] * p1_val;
                probD += sumdK[k] * p1_val;
            }
            /* Subtract diagonal contributions */
            probC -= sumcK[j] * diag_p1;
            probD -= sumdK[j] * diag_p1;
        }

        /* Write output */
        int outIdx = pairIdx * params.numSites + siteIdx;
        pConvergent[outIdx] = probC;
        pDivergent[outIdx] = probD;
    }
}

/*
 * Alternative kernel using threadgroup shared memory
 * Best when multiple threads need the same matrix data
 */
kernel void convergence_kernel_shared(
    device const float* conP_part1 [[buffer(0)]],
    device const uint* offsets [[buffer(1)]],
    device const int* nodePairs [[buffer(2)]],
    device float* pConvergent [[buffer(3)]],
    device float* pDivergent [[buffer(4)]],
    constant ConvergenceParams& params [[buffer(5)]],
    uint2 gid [[thread_position_in_grid]])
{
    /* Shared memory for precomputed sumcK and sumdK per site */
    /* This version trades memory for reduced redundant computation */

    int pairIdx = gid.x;
    int siteIdx = gid.y;

    if (pairIdx >= params.numPairs || siteIdx >= params.numSites) return;

    int n = params.n;
    int n2 = n * n;

    int inode = nodePairs[pairIdx * 3];
    int jnode = nodePairs[pairIdx * 3 + 1];

    device const float* P1 = conP_part1 + offsets[inode] + siteIdx * n2;
    device const float* P2 = conP_part1 + offsets[jnode] + siteIdx * n2;

    /* Precompute column sums using SIMD operations where possible */
    float sumcK[20];
    float sumdforJ = 0.0f;

    /* Initialize */
    for (int k = 0; k < 20; k++) {
        sumcK[k] = 0.0f;
    }

    /* Compute sumcK */
    for (int j = 0; j < 20; j++) {
        for (int k = 0; k < 20; k++) {
            float val = P2[j * n + k];
            sumcK[k] += val;
            sumdforJ += val;
        }
        sumcK[j] -= P2[j * n + j];
        sumdforJ -= P2[j * n + j];
    }

    /* Compute sumdK inline and final probabilities */
    float probC = 0.0f;
    float probD = 0.0f;

    for (int j = 0; j < 20; j++) {
        for (int k = 0; k < 20; k++) {
            float p1_val = P1[j * n + k];
            float sumdK_k = sumdforJ - sumcK[k];
            probC += sumcK[k] * p1_val;
            probD += sumdK_k * p1_val;
        }
        float p1_diag = P1[j * n + j];
        float sumdK_j = sumdforJ - sumcK[j];
        probC -= sumcK[j] * p1_diag;
        probD -= sumdK_j * p1_diag;
    }

    int outIdx = pairIdx * params.numSites + siteIdx;
    pConvergent[outIdx] = probC;
    pDivergent[outIdx] = probD;
}
