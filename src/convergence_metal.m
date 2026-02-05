/*
 * convergence_metal.m - Metal host wrapper for Grand-Convergence
 *
 * This file implements the Metal backend for GPU-accelerated convergence/divergence
 * calculations on Apple Silicon (M1/M2/M3).
 *
 * Note: Metal uses single precision (float) for GPU computation. This wrapper
 * handles conversion between double (host) and float (GPU) automatically.
 *
 * Copyright (c) 2026 de Koning Lab, University of Calgary
 */

#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#import <Accelerate/Accelerate.h>
#import <mach/mach_time.h>
#include "convergence_metal.h"
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

/* Timing helper */
static double mach_time_to_ms(uint64_t elapsed) {
    mach_timebase_info_data_t info;
    mach_timebase_info(&info);
    return (double)elapsed * info.numer / info.denom / 1e6;
}

/* Static Metal objects for persistent state */
static id<MTLDevice> metalDevice = nil;
static id<MTLCommandQueue> commandQueue = nil;
static id<MTLComputePipelineState> pipelineState = nil;
static id<MTLLibrary> metalLibrary = nil;

/* Parameters structure matching the shader */
typedef struct {
    int numSites;
    int numPairs;
    int n;
    int sitesPerThread;
} ConvergenceParams;

/* Embedded shader source - used when metallib file is not available */
static const char* shaderSource =
"#include <metal_stdlib>\n"
"using namespace metal;\n"
"\n"
"struct ConvergenceParams {\n"
"    int numSites;\n"
"    int numPairs;\n"
"    int n;\n"
"    int sitesPerThread;\n"
"};\n"
"\n"
"kernel void convergence_kernel(\n"
"    device const float* conP_part1 [[buffer(0)]],\n"
"    device const uint* offsets [[buffer(1)]],\n"
"    device const int* nodePairs [[buffer(2)]],\n"
"    device float* pConvergent [[buffer(3)]],\n"
"    device float* pDivergent [[buffer(4)]],\n"
"    constant ConvergenceParams& params [[buffer(5)]],\n"
"    uint2 gid [[thread_position_in_grid]],\n"
"    uint2 tid [[thread_position_in_threadgroup]],\n"
"    uint2 tgSize [[threads_per_threadgroup]])\n"
"{\n"
"    int pairIdx = gid.x;\n"
"    if (pairIdx >= params.numPairs) return;\n"
"\n"
"    int n = params.n;\n"
"    int n2 = n * n;\n"
"\n"
"    int inode = nodePairs[pairIdx * 3];\n"
"    int jnode = nodePairs[pairIdx * 3 + 1];\n"
"\n"
"    uint offset1 = offsets[inode];\n"
"    uint offset2 = offsets[jnode];\n"
"\n"
"    int sitesPerThread = params.sitesPerThread;\n"
"    int threadSiteBase = gid.y * sitesPerThread;\n"
"\n"
"    for (int s = 0; s < sitesPerThread; s++) {\n"
"        int siteIdx = threadSiteBase + s;\n"
"        if (siteIdx >= params.numSites) break;\n"
"\n"
"        device const float* P1 = conP_part1 + offset1 + siteIdx * n2;\n"
"        device const float* P2 = conP_part1 + offset2 + siteIdx * n2;\n"
"\n"
"        float sumcK[20];\n"
"        float sumdK[20];\n"
"        float sumdforJ = 0.0f;\n"
"\n"
"        for (int k = 0; k < 20; k++) sumcK[k] = 0.0f;\n"
"\n"
"        for (int j = 0; j < 20; j++) {\n"
"            float rowSum = 0.0f;\n"
"            float diag = P2[j * n + j];\n"
"            for (int k = 0; k < 20; k++) {\n"
"                float val = P2[j * n + k];\n"
"                sumcK[k] += val;\n"
"                rowSum += val;\n"
"            }\n"
"            sumdforJ += rowSum - diag;\n"
"            sumcK[j] -= diag;\n"
"        }\n"
"\n"
"        for (int k = 0; k < 20; k++) sumdK[k] = sumdforJ - sumcK[k];\n"
"\n"
"        float probC = 0.0f;\n"
"        float probD = 0.0f;\n"
"\n"
"        for (int j = 0; j < 20; j++) {\n"
"            float diag_p1 = P1[j * n + j];\n"
"            for (int k = 0; k < 20; k++) {\n"
"                float p1_val = P1[j * n + k];\n"
"                probC += sumcK[k] * p1_val;\n"
"                probD += sumdK[k] * p1_val;\n"
"            }\n"
"            probC -= sumcK[j] * diag_p1;\n"
"            probD -= sumdK[j] * diag_p1;\n"
"        }\n"
"\n"
"        int outIdx = pairIdx * params.numSites + siteIdx;\n"
"        pConvergent[outIdx] = probC;\n"
"        pDivergent[outIdx] = probD;\n"
"    }\n"
"}\n";

/* Check if Metal is available */
int metal_available(void)
{
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (device == nil) {
            return 0;
        }
        return 1;
    }
}

/* Initialize Metal context */
int metal_init(char *device_name, size_t *globalMem)
{
    @autoreleasepool {
        /* Get the default Metal device */
        metalDevice = MTLCreateSystemDefaultDevice();
        if (metalDevice == nil) {
            fprintf(stderr, "Metal: No GPU device found\n");
            if (device_name) strcpy(device_name, "None");
            if (globalMem) *globalMem = 0;
            return -1;
        }

        /* Get device info */
        if (device_name) {
            strncpy(device_name, [[metalDevice name] UTF8String], 255);
            device_name[255] = '\0';
        }
        if (globalMem) {
            *globalMem = [metalDevice recommendedMaxWorkingSetSize];
        }

        /* Create command queue */
        commandQueue = [metalDevice newCommandQueue];
        if (commandQueue == nil) {
            fprintf(stderr, "Metal: Failed to create command queue\n");
            return -1;
        }

        /* Try to load precompiled metallib first */
        NSError *error = nil;
        NSString *libPath = nil;

        /* Try to find metallib in same directory as executable */
        NSBundle *mainBundle = [NSBundle mainBundle];
        if (mainBundle) {
            libPath = [mainBundle pathForResource:@"convergence_metal" ofType:@"metallib"];
        }

        /* Try current directory */
        if (libPath == nil) {
            NSFileManager *fm = [NSFileManager defaultManager];
            NSString *currentPath = [fm currentDirectoryPath];
            NSString *tryPath = [currentPath stringByAppendingPathComponent:@"convergence_metal.metallib"];
            if ([fm fileExistsAtPath:tryPath]) {
                libPath = tryPath;
            }
        }

        /* Try src directory */
        if (libPath == nil) {
            NSFileManager *fm = [NSFileManager defaultManager];
            NSString *currentPath = [fm currentDirectoryPath];
            NSString *tryPath = [currentPath stringByAppendingPathComponent:@"src/convergence_metal.metallib"];
            if ([fm fileExistsAtPath:tryPath]) {
                libPath = tryPath;
            }
        }

        if (libPath) {
            NSURL *libURL = [NSURL fileURLWithPath:libPath];
            metalLibrary = [metalDevice newLibraryWithURL:libURL error:&error];
        }

        /* Fall back to compiling source at runtime */
        if (metalLibrary == nil) {
            NSString *source = [NSString stringWithUTF8String:shaderSource];
            MTLCompileOptions *options = [[MTLCompileOptions alloc] init];
            metalLibrary = [metalDevice newLibraryWithSource:source options:options error:&error];

            if (metalLibrary == nil) {
                fprintf(stderr, "Metal: Failed to compile shader: %s\n",
                        [[error localizedDescription] UTF8String]);
                return -1;
            }
        }

        /* Get the kernel function */
        id<MTLFunction> kernelFunction = [metalLibrary newFunctionWithName:@"convergence_kernel"];
        if (kernelFunction == nil) {
            fprintf(stderr, "Metal: Failed to find kernel function\n");
            return -1;
        }

        /* Create compute pipeline state */
        pipelineState = [metalDevice newComputePipelineStateWithFunction:kernelFunction error:&error];
        if (pipelineState == nil) {
            fprintf(stderr, "Metal: Failed to create pipeline state: %s\n",
                    [[error localizedDescription] UTF8String]);
            return -1;
        }

        /* Print device info */
        printf("Metal device: %s\n", [[metalDevice name] UTF8String]);
        printf("  Recommended working set: %.2f GB\n",
               [metalDevice recommendedMaxWorkingSetSize] / (1024.0 * 1024.0 * 1024.0));
        printf("  Max threads per threadgroup: %lu\n",
               (unsigned long)[pipelineState maxTotalThreadsPerThreadgroup]);
        printf("  Note: Using single precision (float) for GPU computation\n");

        return 0;
    }
}

/* Main convergence calculation on Metal */
int metal_convergence(
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
    @autoreleasepool {
        if (metalDevice == nil || pipelineState == nil || commandQueue == nil) {
            fprintf(stderr, "Metal: Not initialized\n");
            return -1;
        }

        /* Calculate sizes */
        size_t numDoubles = conP_part1_size / sizeof(double);
        size_t output_count = (size_t)numPairs * numSites;
        size_t offsets_size = (size_t)(numNodes + 1) * sizeof(unsigned int);
        size_t pairs_size = (size_t)numPairs * 3 * sizeof(int);

        /* Convert input doubles to floats using parallel dispatch */
        float *conP_float = (float *)malloc(numDoubles * sizeof(float));
        if (!conP_float) {
            fprintf(stderr, "Metal: Failed to allocate conversion buffer\n");
            return -1;
        }

        /* Use Accelerate framework's vDSP for highly optimized SIMD conversion */
        uint64_t t_start = mach_absolute_time();
        vDSP_vdpsp(h_conP_part1, 1, conP_float, 1, numDoubles);
        uint64_t t_input_conv = mach_absolute_time();

        /* Create buffers with shared storage mode (Apple Silicon unified memory) */
        id<MTLBuffer> conP_buf = [metalDevice newBufferWithBytes:conP_float
                                                          length:numDoubles * sizeof(float)
                                                         options:MTLResourceStorageModeShared];
        free(conP_float);

        id<MTLBuffer> offsets_buf = [metalDevice newBufferWithBytes:h_offsets
                                                             length:offsets_size
                                                            options:MTLResourceStorageModeShared];
        id<MTLBuffer> pairs_buf = [metalDevice newBufferWithBytes:h_nodePairs
                                                           length:pairs_size
                                                          options:MTLResourceStorageModeShared];
        id<MTLBuffer> convergent_buf = [metalDevice newBufferWithLength:output_count * sizeof(float)
                                                               options:MTLResourceStorageModeShared];
        id<MTLBuffer> divergent_buf = [metalDevice newBufferWithLength:output_count * sizeof(float)
                                                              options:MTLResourceStorageModeShared];

        /* Configure coarser parallelism - each thread processes multiple sites */
        int sitesPerThread = 16;  /* Tune this for best performance */
        int numSiteBlocks = (numSites + sitesPerThread - 1) / sitesPerThread;

        /* Create parameters buffer */
        ConvergenceParams params;
        params.numSites = numSites;
        params.numPairs = numPairs;
        params.n = n;
        params.sitesPerThread = sitesPerThread;
        id<MTLBuffer> params_buf = [metalDevice newBufferWithBytes:&params
                                                            length:sizeof(params)
                                                           options:MTLResourceStorageModeShared];

        if (!conP_buf || !offsets_buf || !pairs_buf || !convergent_buf || !divergent_buf || !params_buf) {
            fprintf(stderr, "Metal: Failed to create buffers\n");
            return -1;
        }

        /* Create command buffer and encoder */
        id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
        id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];

        /* Set pipeline state and buffers */
        [encoder setComputePipelineState:pipelineState];
        [encoder setBuffer:conP_buf offset:0 atIndex:0];
        [encoder setBuffer:offsets_buf offset:0 atIndex:1];
        [encoder setBuffer:pairs_buf offset:0 atIndex:2];
        [encoder setBuffer:convergent_buf offset:0 atIndex:3];
        [encoder setBuffer:divergent_buf offset:0 atIndex:4];
        [encoder setBuffer:params_buf offset:0 atIndex:5];

        /* Calculate thread and threadgroup sizes
         * Grid: (numPairs, numSiteBlocks) - each thread handles sitesPerThread sites
         * This reduces thread count and amortizes dispatch overhead
         */
        MTLSize gridSize = MTLSizeMake(numPairs, numSiteBlocks, 1);

        /* Threadgroup size: optimize for M-series GPUs
         * Use larger threadgroups to improve occupancy
         */
        NSUInteger maxThreads = [pipelineState maxTotalThreadsPerThreadgroup];
        NSUInteger threadWidth = 32;   /* Wider for better coalescing on pairs */
        NSUInteger threadHeight = 8;   /* Each handles sitesPerThread sites */
        if (threadWidth * threadHeight > maxThreads) {
            threadHeight = maxThreads / threadWidth;
        }

        MTLSize threadgroupSize = MTLSizeMake(threadWidth, threadHeight, 1);

        /* Dispatch threads */
        [encoder dispatchThreads:gridSize threadsPerThreadgroup:threadgroupSize];

        /* End encoding and commit */
        [encoder endEncoding];
        uint64_t t_pre_gpu = mach_absolute_time();
        [commandBuffer commit];

        /* Wait for completion */
        [commandBuffer waitUntilCompleted];
        uint64_t t_post_gpu = mach_absolute_time();

        /* Check for errors */
        if ([commandBuffer status] == MTLCommandBufferStatusError) {
            fprintf(stderr, "Metal: Command buffer error: %s\n",
                    [[[commandBuffer error] localizedDescription] UTF8String]);
            return -1;
        }

        /* Convert results from float back to double using Accelerate vDSP */
        float *conv_float = (float *)[convergent_buf contents];
        float *div_float = (float *)[divergent_buf contents];
        vDSP_vspdp(conv_float, 1, h_pConvergent, 1, output_count);
        vDSP_vspdp(div_float, 1, h_pDivergent, 1, output_count);
        uint64_t t_output_conv = mach_absolute_time();

        /* Print timing breakdown */
        printf("GPU Timing breakdown:\n");
        printf("  Input conversion (double->float): %.2f ms\n", mach_time_to_ms(t_input_conv - t_start));
        printf("  Buffer setup + encoding:          %.2f ms\n", mach_time_to_ms(t_pre_gpu - t_input_conv));
        printf("  GPU kernel execution:             %.2f ms\n", mach_time_to_ms(t_post_gpu - t_pre_gpu));
        printf("  Output conversion (float->double): %.2f ms\n", mach_time_to_ms(t_output_conv - t_post_gpu));
        printf("  Total GPU path:                   %.2f ms\n", mach_time_to_ms(t_output_conv - t_start));

        return 0;
    }
}

/* Cleanup Metal resources */
void metal_cleanup(void)
{
    @autoreleasepool {
        pipelineState = nil;
        metalLibrary = nil;
        commandQueue = nil;
        metalDevice = nil;
    }
}
