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
