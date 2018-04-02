# Grand-Convergence
#### Rapid Discovery of Convergent Molecular Evolution Across Entire Phylogenies
#### Chenzhe Qian, Nathan Bryans, and Jason de Koning
##### April 2015

de Koning Lab, University of Calgary <BR>
Biochemisty and Molecular Biology Graduate Program in Bioinformatics <BR>
http://lab.jasondk.io  <BR>

---
__This software is in beta release. Please help us improve it by [opening an issue](https://github.com/dekoning-lab/grand-conv/issues) or by reporting your experience to [Jason](mailto:jason.dekoning@ucalgary.ca).__

Prior to publication please cite: Qian C and APJ de Koning (2018). Rapid Discovery of Convergent Molecular Evolution Across Entire Phylogenies. University of Calgary. http://lab.jasondk.io

and: Qian C\*, Bryans N\*, Kruykov I, and APJ de Koning (2018). Visualization and analysis of statistical signatures of convergent molecular evolution. University of Calgary. http://lab.jasondk.io

Also see Castoe\*, de Koning\* et al 2009. "Evidence for an ancient adaptive episode of convergent molecular evolution." PNAS v106(22): 8986-8991. http://www.pnas.org/content/106/22/8986.abstract

---

<p align="center"><img src ="http://lab.jasondk.io/data/Grand-Conv-demo.jpg" /></p>

### About

Grand Convergence (`grand-conv`) calculates the posterior expected numbers of convergent and divergent substitutions across all pairs of indendent branches of a phylogeny. **The program uses a multi-threaded implementation of our new exact algorithm, which is about 4,000X faster than our original approach when run on a multi-core desktop computer.** We also include many-core versions optimized for offloading calculations to Intel Xeon Phi coprocessors, but we found that this is not likely to be very useful except for unrealistically large datasets (see Qian and de Koning, 2015).

All calculations are integrated over the posterior distribution of ancestral states and posterior substitutions. `grand-conv` will output site-specific convergence and divergence posterior probabilities for branch-pairs of interest (specified in `grand-conv.ctl`). Rate variation across sites is accommodated in the calculations and Yang's node scaling scheme is preserved to facilitate analysis on large phylogenies. `grand-conv` also automatically calculates a robust, non-parametric errors in variables regression to estimate a reliable null model from the data. Estimates of *excess convergence* are produced by comparing this null model to the data.

**When run with the Data Explorer, `grand-conv` will generate an HTML file (`$output/User/UI/index.html`) which provides several interactive visualizations of the results.** Pairs of branches with high excess convergence can thus be readily identified, and publication quality figures can be produced automatically. Interactive versions of all figures from our 2009 PNAS paper (Castoe, de Koning, et al. 2009) can be automatically generated using the Data Explorer.

*COMING SOON:* We have also included a pipeline that hooks into our evolutionary simulator, Palantír (Kryukov et al., 2015). This pipeline allows a more rigorous analysis of the random expected amount of convergent evolution between each pair of branches. It generates simulated data sets possessing *only* random convergence under a site-heterogeneous model of mutation-selection codon substitution that is roughly based on the real data. The pipeline will then calculate the random expected distribution of excess convergence for every pair of branches in the tree. This allows a more rigorous assessment of excess convergence by providing an empirical P-value that is specific to each pair of branches of interest.

---
### Getting Started

#### 1. Prerequisites

To compile Grand Convergence you will need only a standard C compiler with OpenMP support. Most Linux systems will already meet this requirement.

For **Mac users**, there are three options for compiling `grand-conv`:

1. For best performance, install **Intel's C++ compiler** (`icc`). There is a free academic license [available here](https://software.intel.com/en-us/qualify-for-free-software/student).
2. Install a recent version of `gcc` that includes OpenMP support. This is likely to be laborious.
3. The quickest way to get up and running is probably to use Apple's Developer Tools, which include the `clang` compiler. Unfortunately, **this requires an additional step of installing a recent port of OpenMP** that will work with Apple's compiler. This can be done easily using the package manager, [Homebrew](http://brew.sh).

If you don't already have homebrew installed, install it. In a Terminal window, run:
```
ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
```

Now install *clang-omp*:
```
brew install clang-omp
```

If homebrew reports no such package, you may need to run `brew update` first.

#### 2. Quick Start

To compile, run `make` in the root folder. This will build the library dependency and will separately build `codeml` and `grand-conv` from the same source files.

To run, we recommend the automated pair of scripts `gc-estimate` (to estimate branch-lengths and gamma shape parameter) and `gc-discover` (to run `grand-conv`). You may also create control files yourself using the templates in `./assets` and then run `grand-conv` directly.

Inputs are a multiple sequence alignment in Phylip format, either in codons (default) or in amino-acids (`--seqtype=aa`), and a phylogenetic tree. You can provide branchlengths in the tree definition or you can have them be estimated in Phase 1 below using `--free-bl=1`.

Results are output in HTML format in `$output/UI/user/index.html`, where `$output` is a user-defined variable indicated by `--dir=$output` (the default value is `output`).

#### Example usage

```
# Download and compile
git clone https://github.com/dekoning-lab/grand-conv.git
cd grand-conv
make

# Phase 1, estimate parameters and generate control file for gc-discover
./gc-estimate --in=dat/squamateMtCDS.phy --tree=dat/NUC.tree --gencode=1 --aa-model=lg --dir=output --free-bl=0

# Phase 2, run Grand Convergence
./gc-discover --dir=output --nthreads=4

# (Optional) Phase 3, run Grand Convergence requesting site-specific data for branch-pairs of interest
./gc-discover --dir=output --nthreads=4 --branch-pairs="(53,56)" --visualize=1
```

**NOTE:** If you don't have branchlengths under the desired model, you should run Phase 1 with the setting `--free-bl=1`.

To view the results, use `--visualize=1` to open a web browser automatically with the results or you can manually open `$output/User/UI/index.html` in a standards-compliant web browser like Firefox.

---

### Tips and Warnings

To be completed.

---
### Technical notes

We have implemented `grand-conv` through extensive modification of Ziheng Yang's PAML4.8 (all modifications can be turned off by undefining the macro `#JDKLAB`).

Technical details on the calculations can be found in the Methods and Supplementary info from our paper.

To get site-specific data for more than one pair of sites, use format `--branch-pairs="(53,56),(4,37)"`

Colouring on the Rate vs. Diversity plot is such that red denotes for `p(convergence) > 0.8` and orange denotes `p(convergence) > 0.5`. Colouring is given only for the *first* pair of branches specified via `--branch-pairs` input parameter.

Changes that were made to the original PAML code include:
* A number of additions modifications were made to the ```AncestralMarginal()``` function in treesub.c
* Other changes and additions made to support this function in both treesub.c and codeml.c:
- global data structure for tree nodes modified to store "conP_part1", "prior", and "conP_byCat", which are components of the posterior substitution probability calculations
- most other code changes are found in the ```PostProbNode()``` and ```PointconPnodes()``` function
- a few functions added to source code:
 1. ```isNodeDescendent()``` function in treesub.c
 2. ```getSelectedBraches()``` function in codem.c
* A forward-backward algorithm was added, which makes ancestral state probability calculations much faster than PAML's scheme of rerooting the tree and performing a complete pruning calculation at each node. 
* A variety of additional code that is specific to `grand-conv` was added to `JDKLabUtility.c`

* A new control file was created, `grand-conv.ctl`, to specifically store and load parameters for grand-convergence 
* A new ```Makefile``` target was created to compile the program: ```make grand-conv```
* All modifications and additions were defined in preprocessor block: ```#ifdef //code #endif```
* Two compiler macros were defined in ```Makefile``` to turn on/off the functionality built in grand-convergence
  - If Macro ```JDKLAB``` is defined, the program will run grand-convergence, otherwise run native PAML code
  - If Macro ```PARA_ON_SITE``` is defined, the program will parallel based on the length of input sequence alignment when executing ```AncestralMarginal()```
  - If Macro ```PARA_ON_NODE``` is defined, the program will parallel based on the sizes of input phylogenetic tree when executing ```AncestralMarginal()```
* One compiler optimization flag ```-m64``` was added and used as default in ```Makefile```. If running on 32-bit machine, this flag should be turned off
* For shallow phylogenies it may be useful to use a previously determined metric of divergence rather than relying on those estimated by grand-conv. This can be done by supplying a second tree with pre-determined measures for each branch length. To do this, include the flag ```--divdistfile=dat/NUC2.tree``` when calling gc-discover.
* Both sequential and interleaved phylip files are supported. Interleaved phylip files must have an 'I' on the first line (i.e. ```20 1000 I```).
