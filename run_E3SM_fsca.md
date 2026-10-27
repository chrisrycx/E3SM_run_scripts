
# Guide to run E3SM in NERSC

Enrico Zorzetto, mostly based on conversations with Dalei Hao.



## Getting the E3SM source code:

git clone https://github.com/EnricoZorzetto/E3SM.git E3SM_FSCA
cd E3SM_FSCA
git fetch origin
git checkout origin/ez/fsca
git config --global url."https://github.com/".insteadOf 'git@github.com:'
git submodule update --init --recursive

Note: How do I get the git submodules? I just cloned the sub-repository here
The following seems to work only using https:
git config --global url."https://github.com/".insteadOf 'git@github.com:'

Note: I have been working on branch ez/fsca to add fSCA param on E3SM.

## Creating surface data for the ELM model run over a given domain

The surface data preprocessing code can be obtained at 
https://github.com/EnricoZorzetto/build_surface_dataset_for_ELM

module load matlab

```
cd build_surface_dataset_for_ELM/code_for_develop_regional_dataset/
```

Example for a 4 x 4 grid cell domain around Tony Grove, Utah:
```
matlab -nodisplay -nosplash -nodesktop -r "run('ceate_surfdata_TG.m'); exit;"
```

Example for Western US domain:
```
matlab -nodisplay -nosplash -nodesktop -r "run('ceate_surfdata_WUS_FSCA.m '); exit;"
matlab -nodisplay -nosplash -nodesktop -r "run('ez_merge_netcdfs.m'); exit;"
```

## Scripts to run ELM


./scripts/E3SM-running-scripts/run_Utah_site_fsca.sh
./scripts/E3SM-running-scripts/run_Utah_site_fsca1.sh

./scripts/E3SM-running-scripts/run_WUS_fsca.sh





salloc --nodes 1 --qos interactive --time 01:00:00 --constraint cpu --account m4986

