PRGS =  baseml codeml basemlg mcmctree pamp evolver yn00 chi2 
CC = icc # cc, gcc, cl

#For icc:
CFLAGS = -O3 -m64 -openmp -funroll-loops -fomit-frame-pointer -finline-functions

#Original:
#CFLAGS = -O4 -fopenmp -funroll-loops -fomit-frame-pointer -finline-functions

#MAC OSX G5:
#CFLAGS = -mcpu=G5 -O4 -funroll-loops -fomit-frame-pointer -finline-functions

#MAC OSX intel:
#CFLAGS = -march=pentium-m -O4 -funroll-loops -fomit-frame-pointer -finline-functions

#CFLAGS = -O4
#CFLAGS = -fast
#CFLAGS = -m64 -march=opteron -mtune=opteron -ansi -O3 -funroll-loops -fomit-frame-pointer -finline-functions 
#CFLAGS = -march=athlon -mcpu=athlon -O4 -funroll-loops -fomit-frame-pointer -finline-functions
#CFLAGS = -march=pentiumpro -mcpu=pentiumpro -O4 -funroll-loops -fomit-frame-pointer -finline-functions 

LIBS = -lm # -lM

all : $(PRGS)
grand-conv : codeml.c  tools.c treesub.c treespace.c paml.h 
	$(CC) $(CFLAGS) -D JDKLAB -D PARA_ON_SITE -o $@ codeml.c tools.c $(LIBS) # if data has more sites than branch pairs
#	$(CC) $(CFLAGS) -D JDKLAB -D PARA_ON_NODE -o $@ codeml.c tools.c $(LIBS) # if data has less sites than branch pairs

baseml : baseml.c tools.c treesub.c treespace.c paml.h 
	$(CC) $(CFLAGS) -o $@ baseml.c tools.c $(LIBS)
basemlg : basemlg.c  tools.c treesub.c treespace.c paml.h 
	$(CC) $(CFLAGS) -o $@ basemlg.c tools.c $(LIBS)
codeml : codeml.c  tools.c treesub.c treespace.c paml.h 
	$(CC) $(CFLAGS) -D PARA_ON_NODE=1 -o $@ codeml.c tools.c $(LIBS)
evolver : evolver.c  tools.c treesub.c treespace.c paml.h 
	$(CC) $(CFLAGS) -o $@ evolver.c tools.c $(LIBS)
pamp : pamp.c  tools.c treesub.c treespace.c paml.h 
	$(CC) $(CFLAGS) -o $@ pamp.c tools.c $(LIBS)
mcmctree : mcmctree.c  tools.c treesub.c treespace.c paml.h 
	$(CC) $(CFLAGS) -o $@ mcmctree.c tools.c $(LIBS)
	$(CC) $(CFLAGS) -o infinitesites -D INFINITESITES mcmctree.c tools.c $(LIBS)
yn00: yn00.c tools.c paml.h
	$(CC) $(CFLAGS) -o $@ yn00.c tools.c $(LIBS)
chi2 : chi2.c
	$(CC) $(CFLAGS) -o $@ chi2.c $(LIBS)
