PRGS = ../bin/grand-conv ../bin/codeml 

NOJDKLABCODE=0

# Determine which of icc, gcc, or clang (Apple) to use
TEST1 = $(shell icc --version 2>/dev/null | head -n 1)
TEST2 = $(shell gcc --version 2>/dev/null | head -n 1)

HASICC = 0
HASGCC = 0
GCCISLVM = 0

ifeq ($(strip $(TEST1)),)
	# icc is preferred
	HASICC = 0
ifeq ($(strip $(TEST2)),)
        HASGCC = 0
	GCCISLLVM = 0
else
        HASGCC = 1
        ifeq ($(strip $(findstring LLVM,$(TEST2))),)
                GCCISLLVM = 0
                CC = gcc
        else
                GCCISLLVM = 1
                CC = clang
        endif
endif
else
	HASICC = 1
	CC = icc
endif

# Compiler-specific flags (including for OpenMP)
CFLAGS_ICC = -O3 -m64 -openmp -funroll-loops -fomit-frame-pointer -finline-functions
CFLAGS_GCC = -O4 -fopenmp -funroll-loops -fomit-frame-pointer -finline-functions -w -lm
CFLAGS_CLANG = -O3 -funroll-loops -fomit-frame-pointer -Wno-absolute-value -Wno-empty-body -Wno-pointer-sign -Wno-tautological-compare -Wno-format -Wno-implicit-function-declaration -Wno-return-type -lm -L/usr/local/lib -liomp5

ifeq ($(strip $(findstring icc,$(CC))),icc)
	CFLAGS = $(CFLAGS_ICC)
else ifeq ($(strip $(findstring clang,$(CC))),clang)
	CFLAGS = $(CFLAGS_CLANG)
else
	# default to gcc
	CFLAGS = $(CFLAGS_GCC)
endif

LIBS = -lm

all : ../bin/grand-conv ../bin/codeml 
	@-printf "\nBuild complete.\n"

clean :
	@-rm -f ../bin/grand-conv ||: > ../clean.log 2>&1 
	@-rm -f ../bin/codeml ||: > ../clean.log 2>&1
	@-rm -f *.o ||: > ../clean.log 2>&1
	@-rm -rf ../lib/jansson-2.7/build/* ||: > ../clean.log 2>&1 
	@-cd ../lib/jansson-2.7 && make clean && echo || echo ||: > ../clean.log 2>&1 
	@-cd ../lib/jansson-2.7 && make distclean && echo || echo ||L > ../clean.log 2>&1 
	@-cd .. && rm -f lnf rates rst rst1 rub codeml-output.out *.log codeml grand-conv
	@-printf "Cleaning old files complete.\n"

../bin/grand-conv : codeml.c tools.c treesub.c treespace.c JDKLabUtility.c paml.h
	@-printf "\nCompiler set to: %s\n" $(CC)
	@-printf "\n[Starting build process.]"
	@-if [ ! -d ../lib/jansson-2.7 ] ; then tar -zxf ../lib/jansson-2.7.tar.gz -C ../lib/; fi
	@-if [ ! -e ../lib/jansson-2.7/Makefile ] ; then printf "\nBuilding library dependencies." && cd ../lib/jansson-2.7 && ./configure --prefix=`pwd`/build > ../make.log 2>&1; fi
	@-cd ../lib/jansson-2.7 && make > ../make.log 2>&1 && make install > ../make.log 2>&1 && cp build/lib/libjansson.a ../ && printf "\nDone building dependencies."
	@-printf "\nBuilding grand-conv." && $(CC) $(CFLAGS) -D JDKLAB=1 -D PARA_ON_SITE -I../lib/Headers -o $@ codeml.c tools.c $(LIBS) ../lib/libjansson.a ||: > ../make.log 2>&1

../bin/codeml : codeml.c  tools.c treesub.c treespace.c paml.h
	@-printf "\nBuilding codeml." && $(CC) $(CFLAGS) -U JDKLAB -o $@ codeml.c tools.c -lm >make.log 2>&1

# ============================================================================
# GPU Acceleration Support (CUDA and Metal)
# ============================================================================

# Platform detection
UNAME_S := $(shell uname -s)

# CUDA detection (Linux/Windows - requires nvcc in PATH)
NVCC := $(shell which nvcc 2>/dev/null)
ifeq ($(NVCC),)
    CUDA_AVAILABLE := 0
else
    CUDA_AVAILABLE := 1
endif

# Metal detection (macOS only)
ifeq ($(UNAME_S),Darwin)
    METAL_AVAILABLE := 1
    METAL_COMPILE := xcrun -sdk macosx metal -O2
    METAL_LIB := xcrun -sdk macosx metallib
else
    METAL_AVAILABLE := 0
endif

# CUDA compilation flags (targeting V100: sm_70, A100: sm_80)
NVCC_FLAGS = -O3 -arch=sm_70 -gencode=arch=compute_70,code=sm_70 -gencode=arch=compute_80,code=sm_80 --compiler-options -fPIC
CUDA_LIBS = -L/usr/local/cuda/lib64 -lcudart

# Metal compilation flags (macOS)
METAL_FLAGS = -framework Metal -framework Foundation -framework CoreGraphics -framework Accelerate
# C flags for Metal helper files (no OpenMP needed, force native architecture)
METAL_CFLAGS = -O3 -funroll-loops -fomit-frame-pointer -arch arm64
# Use system clang for Metal (not Homebrew clang which may target wrong arch)
METAL_CC = /usr/bin/clang

# ============================================================================
# GPU Build Targets
# ============================================================================

# Build with Metal support (macOS Apple Silicon)
metal : ../bin/grand-conv-metal
	@-printf "\nMetal GPU build complete.\n"

# Build with CUDA support (Linux/data center)
cuda : ../bin/grand-conv-cuda
	@-printf "\nCUDA GPU build complete.\n"

# Build both GPU backends (if available)
gpu :
ifeq ($(METAL_AVAILABLE),1)
	@$(MAKE) metal
endif
ifeq ($(CUDA_AVAILABLE),1)
	@$(MAKE) cuda
endif
	@-printf "\nGPU builds complete.\n"

# Clean GPU files
clean-gpu :
	@-rm -f ../bin/grand-conv-metal ../bin/grand-conv-cuda
	@-rm -f convergence_gpu.o convergence_cuda.o convergence_metal.o
	@-rm -f convergence_metal.air convergence_metal.metallib
	@-printf "GPU build files cleaned.\n"

# ============================================================================
# Metal Build Rules (macOS)
# ============================================================================

ifeq ($(METAL_AVAILABLE),1)

# Compile Metal shader to AIR (intermediate)
convergence_metal.air : convergence_metal.metal
	@-printf "\nCompiling Metal shader."
	$(METAL_COMPILE) -c convergence_metal.metal -o convergence_metal.air

# Link to metallib
convergence_metal.metallib : convergence_metal.air
	@-printf "\nLinking Metal library."
	$(METAL_LIB) -o convergence_metal.metallib convergence_metal.air

# Compile Metal wrapper (Objective-C)
convergence_metal.o : convergence_metal.m convergence_metal.h convergence_gpu.h
	@-printf "\nCompiling Metal wrapper."
	$(METAL_CC) $(METAL_CFLAGS) -c convergence_metal.m -o convergence_metal.o

# Compile GPU dispatcher for Metal
convergence_gpu_metal.o : convergence_gpu.c convergence_gpu.h convergence_metal.h
	@-printf "\nCompiling GPU dispatcher (Metal)."
	$(METAL_CC) $(METAL_CFLAGS) -D USE_METAL=1 -c convergence_gpu.c -o convergence_gpu_metal.o

# Build grand-conv with Metal GPU support
../bin/grand-conv-metal : codeml.c tools.c treesub.c treespace.c JDKLabUtility.c paml.h \
                          convergence_gpu_metal.o convergence_metal.o convergence_metal.metallib
	@-printf "\nCompiler set to: $(METAL_CC) (Metal build)\n"
	@-printf "\n[Starting Metal GPU build process.]"
	@-if [ ! -d ../lib/jansson-2.7 ] ; then tar -zxf ../lib/jansson-2.7.tar.gz -C ../lib/; fi
	@-if [ ! -e ../lib/jansson-2.7/Makefile ] ; then printf "\nBuilding library dependencies." && cd ../lib/jansson-2.7 && ./configure --prefix=`pwd`/build > ../make.log 2>&1; fi
	@-cd ../lib/jansson-2.7 && make > ../make.log 2>&1 && make install > ../make.log 2>&1 && cp build/lib/libjansson.a ../ && printf "\nDone building dependencies."
	@-printf "\nBuilding grand-conv with Metal GPU support."
	$(METAL_CC) $(METAL_CFLAGS) -D JDKLAB=1 -D PARA_ON_SITE -D USE_GPU=1 -D USE_METAL=1 \
	    -I../lib/Headers -o $@ codeml.c tools.c $(LIBS) ../lib/libjansson.a \
	    convergence_gpu_metal.o convergence_metal.o $(METAL_FLAGS)
	@-cp convergence_metal.metallib ../bin/ 2>/dev/null || true

endif

# ============================================================================
# CUDA Build Rules (Linux/data center)
# ============================================================================

ifeq ($(CUDA_AVAILABLE),1)

# Compile CUDA kernel
convergence_cuda.o : convergence_cuda.cu convergence_cuda.h convergence_gpu.h
	@-printf "\nCompiling CUDA kernel."
	$(NVCC) $(NVCC_FLAGS) -c convergence_cuda.cu -o convergence_cuda.o

# Compile GPU dispatcher for CUDA
convergence_gpu_cuda.o : convergence_gpu.c convergence_gpu.h convergence_cuda.h
	@-printf "\nCompiling GPU dispatcher (CUDA)."
	$(CC) $(CFLAGS) -D USE_CUDA=1 -c convergence_gpu.c -o convergence_gpu_cuda.o

# Build grand-conv with CUDA GPU support
../bin/grand-conv-cuda : codeml.c tools.c treesub.c treespace.c JDKLabUtility.c paml.h \
                         convergence_gpu_cuda.o convergence_cuda.o
	@-printf "\nCompiler set to: %s\n" $(CC)
	@-printf "\n[Starting CUDA GPU build process.]"
	@-if [ ! -d ../lib/jansson-2.7 ] ; then tar -zxf ../lib/jansson-2.7.tar.gz -C ../lib/; fi
	@-if [ ! -e ../lib/jansson-2.7/Makefile ] ; then printf "\nBuilding library dependencies." && cd ../lib/jansson-2.7 && ./configure --prefix=`pwd`/build > ../make.log 2>&1; fi
	@-cd ../lib/jansson-2.7 && make > ../make.log 2>&1 && make install > ../make.log 2>&1 && cp build/lib/libjansson.a ../ && printf "\nDone building dependencies."
	@-printf "\nBuilding grand-conv with CUDA GPU support."
	$(CC) $(CFLAGS) -D JDKLAB=1 -D PARA_ON_SITE -D USE_GPU=1 -D USE_CUDA=1 \
	    -I../lib/Headers -I/usr/local/cuda/include -o $@ codeml.c tools.c $(LIBS) ../lib/libjansson.a \
	    convergence_gpu_cuda.o convergence_cuda.o $(CUDA_LIBS)

endif

# ============================================================================
# Help target
# ============================================================================

help :
	@echo "Grand-Convergence Build Targets:"
	@echo "  make all      - Build CPU version (default)"
	@echo "  make metal    - Build with Apple Metal GPU support (macOS)"
	@echo "  make cuda     - Build with NVIDIA CUDA GPU support (Linux)"
	@echo "  make gpu      - Build all available GPU backends"
	@echo "  make clean    - Clean all build files"
	@echo "  make clean-gpu - Clean GPU-specific build files"
	@echo ""
	@echo "Platform: $(UNAME_S)"
	@echo "Metal available: $(METAL_AVAILABLE)"
	@echo "CUDA available: $(CUDA_AVAILABLE)"
