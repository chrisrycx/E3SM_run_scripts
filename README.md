# Scripts to run E3SM in NERSC
This repository is used to preprocess data and run the E3SM model.
It is being developed from a mix of notes and demo scripts from Enrico Zorzetto and Dalei Hao.

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

Example for a 12 x 8 grid cell (0.125 deg, 41.0-42.5N, 248-249E) domain around Tony Grove, Utah:
```
matlab -nodisplay -nosplash -nodesktop -r "run('ceate_surfdata_TG.m'); exit;"
```

Example for Western US domain:
```
matlab -nodisplay -nosplash -nodesktop -r "run('ceate_surfdata_WUS_FSCA.m '); exit;"
matlab -nodisplay -nosplash -nodesktop -r "run('ez_merge_netcdfs.m'); exit;"
```

## Scripts to run ELM

Current run scripts are in `run_scripts/testing/`. Each script creates, builds and
submits one case.

### One-time setup

Create a machine settings file from the template and fill in the paths:

```
cp run_scripts/config/machine.env.example run_scripts/config/pm-cpu.env
```

It sets `E3SM_ROOT` (your E3SM checkout), `DATA_ROOT` (domain and surface files),
`OUTPUT_ROOT` (where cases are created), and `MACH`, `COMPILER` and `PROJECT`.
`*.env` files are gitignored.

`E3SM_ROOT` must be on the right E3SM branch for the namelist options a script uses.
For example, `snow_fsca_param` requires `ez/fsca`.

### Running a case

```
cd run_scripts/testing
./TG_NLDAS2_2000-2002.sh                      # uses ../config/pm-cpu.env
./TG_NLDAS2_2000-2002.sh path/to/other.env    # or a different machine file
```

The script runs `case.setup`, then `preview_namelists`, which stops early if a namelist
option is invalid. It then runs `case.build` and `case.submit`, which submits a batch
job. Check the job with `squeue -u $USER`.

The case files go to `$OUTPUT_ROOT/<case>/`:
- `case_scripts/`: the case directory, where you run `xmlquery`, `preview_namelists`
  and `case.submit`; also holds `CaseDocs/` and `user_nl_elm`
- `bld/`: build output
- `run/`: run directory, holding model output (`*.elm.h0.*`, `*.elm.h1.*`) and logs
  (`lnd.log.*`, `cpl.log.*`)

**Warning:** a script deletes any existing case directory with the same name before
creating the case. Change `TAG` or the year range to keep earlier results.

### Naming and new scripts

Scripts and cases are named `<region>_<forcing>_<startyear>-<endyear>`, with an
inclusive year range (e.g. `TG_NLDAS2_2000-2002`). Setting `TAG` in the script adds a
suffix for variants, e.g. `TG_NLDAS2_2000-2002_fsca1`.

To make a new script, copy an existing one and edit the sections at the top:
- experiment: region, forcing, years, tag
- site input data: domain and surface files
- forcing: `DATM_MODE`
- ELM namelist: physics options and history fields

### Other folders

- `run_scripts/ezdemo/`: Enrico Zorzetto's original scripts (spinup, WUS, Utah,
  Brazil). Reference only.
- `run_scripts/various/`: example scripts from others, e.g. custom DATM forcing (see
  `custom_forcing.txt`).
- `run_scripts/config/user_nl_elm_*`: older namelist templates. Current scripts write
  the namelist inline.

### Interactive node

For interactive work on Perlmutter, e.g. testing or post-processing:

```
salloc --nodes 1 --qos interactive --time 01:00:00 --constraint cpu --account m4986
```

## Finding model configuration options and namelist variables

A case is configured in two places:

- **`./xmlchange`** edits the case's `env_*.xml` files, which CIME reads. These set the
  case-level configuration: run length and dates, restarts, processor layout, forcing
  mode, domain files and the batch job.
- **`user_nl_elm`** adds entries to ELM's Fortran namelist (`lnd_in`), which ELM reads at
  startup. These set ELM's physics options, input datasets (e.g. `fsurdat`) and history
  output.

If a setting exists as an XML variable, set it with `xmlchange`, not `user_nl_elm`.
`user_nl_elm` is applied on top of the namelist generated from the XML settings.
Never edit `run/lnd_in` directly, because it is regenerated on every submit.

When an XML change takes effect:

| File | Examples | Takes effect |
|---|---|---|
| `env_case.xml` | compset, grid, machine | Fixed when the case is created |
| `env_mach_pes.xml` | `NTASKS` | After `./case.setup --reset` and a rebuild |
| `env_build.xml` | compiler, debug flags | After a rebuild |
| `env_run.xml` | `STOP_N`, `RUN_STARTDATE`, `DATM_MODE`, `LND_DOMAIN_FILE` | Next submit |
| `env_batch.xml` | `JOB_WALLCLOCK_TIME` | Next submit |

### Case (XML) variables

Run these in a case directory:

```
./xmlquery --listall                      # every variable and its current value
./xmlquery -p DATM                        # variables whose names contain "DATM"
./xmlquery DATM_MODE --valid-values       # allowed values
./xmlquery STOP_OPTION --description      # what a variable does
```

Their definitions live in the E3SM source:

- DATM (forcing) variables: `components/data_comps/datm/cime_config/config_component.xml`
- ELM variables: `components/elm/cime_config/config_component.xml`
- Compsets (e.g. `IELMBC`): `components/elm/cime_config/config_compsets.xml`
- Grids (e.g. `ELM_USRDAT`): `cime_config/config_grids.xml`
- Machines (e.g. `pm-cpu`): `cime_config/machines/config_machines.xml`

### ELM namelist variables

Valid `user_nl_elm` variables, with their types and descriptions, are listed in
`components/elm/bld/namelist_files/namelist_definition.xml`. Defaults are in
`namelist_defaults.xml` in the same directory.

Which options exist depends on the E3SM branch. For example, `snow_fsca_param` only
exists on `ez/fsca`. To check a variable on a given branch:

```
git -C $E3SM_ROOT grep -A10 'id="snow_fsca_param"' origin/ez/fsca -- \
    components/elm/bld/namelist_files/namelist_definition.xml
```

To see the complete namelist a case will use, including every default, run
`./preview_namelists` in the case directory and read `CaseDocs/lnd_in`. This also
reports invalid options before you spend time building. The run scripts do this
automatically after `./case.setup`.

### History output fields

These are the variables that can be listed in `hist_fincl1`, `hist_fincl2`, etc.

- Without a run, list every field defined on a branch, with units, its default on/off
  status and a description:
  ```
  python3 tools/list_hist_fields.py $E3SM_ROOT origin/ez/fsca | grep -i sno | column -t -s $'\t'
  ```
  Fields marked `inactive` are only written if you list them in `hist_fincl*`.
- From a run, ELM prints all fields available for that configuration near the top of
  `run/lnd.log.*`. Search for `ELM_hist_printflds`.

With `hist_empty_htapes = .true.`, only the fields listed in `hist_fincl*` are written.

### Documentation

- ELM docs: https://docs.e3sm.org/E3SM/ELM/user-guide/ (source: `components/elm/docs/`)
- E3SM docs: https://docs.e3sm.org/E3SM/ (source: `docs/`)
- CIME (`create_newcase`, `xmlchange`, `case.setup`, ...): https://esmci.github.io/cime/
- ELM physics: the CLM4.5 Technical Note (Oleson et al. 2013, NCAR/TN-503+STR). ELM was
  forked from CLM4.5. The CLM5 docs (https://escomp.github.io/CTSM/release-clm5.0/)
  explain general concepts well, but CLM5's physics and namelist variables differ from
  ELM's.

