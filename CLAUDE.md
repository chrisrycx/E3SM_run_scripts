# E3SM_run_scripts

Scripts and input-data tooling for running the E3SM Land Model (ELM) on NERSC
Perlmutter (`pm-cpu`), focused on snow (fSCA, SNICAR, snow shape) over Tony Grove,
UT (TG) and the Western US (WUS). The user is learning ELM. Explain CIME/ELM concepts
when relevant, and cite the source file or doc you used.

## Repo layout

- `run_scripts/testing/`: current, cleaned-up run scripts (e.g. `first_run_TG.sh`).
  New scripts go here and follow its pattern.
- `run_scripts/config/`: `user_nl_elm_<SITE>` namelist templates, plus
  `machine.env.example`. Real `*.env` files are gitignored and set `E3SM_ROOT`,
  `DATA_ROOT`, `OUTPUT_ROOT`, `MACH`, `COMPILER`, `PROJECT`, `MODULES`.
- `run_scripts/ezdemo/`: legacy reference scripts from Enrico Zorzetto (spinup,
  NLDAS forcing, WUS/Utah/Brazil runs). Read them for examples, but don't edit them.
- `run_scripts/various/`: other people's example scripts (custom DATM forcing).
- `build_input_data/matlab_code/`: MATLAB code to build ELM domain/surface files
  (`create_surfdata_TG.m`, `CreateELMUgrid*.m`). The `example_data/*spec.txt` files
  are `ncdump -h` headers of valid domain/surfdata files.
- `dalei_matlab/`: original surface-data scripts from Dalei Hao (reference only).
- `custom_forcing.txt`: notes on using custom DATM forcing through `user_datm.streams.txt.*`.

Run-script conventions (from `first_run_TG.sh`):
- `set -euo pipefail`
- machine paths come from a sourced `.env`
- namelist settings live in a `config/user_nl_elm_*` template, and the script appends
  only machine-dependent paths such as `fsurdat`
- compset `IELMBC` + grid `ELM_USRDAT`, with custom domain files set via `xmlchange`
- allocation is `m4986`

## E3SM source (local fork): /home/chris/Science/coding/E3SM

Fork `chrisrycx/E3SM` (upstream: E3SM-Project/E3SM). Local `master` is from about
2025-07. **Submodules (incl. `cime/`, FATES) are not initialized locally**, so cases
can't be built here. Runs happen on Perlmutter with that machine's `E3SM_ROOT`.
Use this checkout for reading code and docs.

Branches that matter (the namelist options differ by branch):
- `origin/ez/fsca`: Enrico's fSCA parameterization. Adds `snow_fsca_param`, which
  `user_nl_elm_TG` uses. **Not on master.**
- `origin/locluong/*`, `origin/ez_snow_shape`: dynamic snow shape and wind drift. Add
  `use_dynamic_snow_shape`, which `user_nl_elm_WUS` uses. **Not on master.**
- Before saying a namelist option is valid, check it on the right branch:
  `git -C ../E3SM grep <var> origin/<branch> -- components/elm/bld/namelist_files/namelist_definition.xml`

### Where to look things up (prefer these over web fetches)

| Question | File (relative to E3SM root) |
|---|---|
| What a `user_nl_elm` variable means/type/valid values | `components/elm/bld/namelist_files/namelist_definition.xml` |
| Default value / default input file for a variable | `components/elm/bld/namelist_files/namelist_defaults.xml` |
| How build-namelist sets/validates options | `components/elm/bld/ELMBuildNamelist.pm` |
| Compset definitions (e.g. `IELMBC` = `2000_DATM%QIA_ELM%SPBC_...`) | `components/elm/cime_config/config_compsets.xml` |
| ELM case XML vars (`ELM_BLDNML_OPTS`, etc.) | `components/elm/cime_config/config_component.xml` |
| DATM modes/streams (`CLMGSWP3v1`, `CLMNLDAS2`, ...) | `components/data_comps/datm/cime_config/` |
| Grid aliases (`ELM_USRDAT`, ...) | `cime_config/config_grids.xml` |
| Perlmutter machine/modules/batch | `cime_config/machines/config_machines.xml` (`MACH="pm-cpu"`), `config_batch.xml` |
| Namelist → Fortran variable | `components/elm/src/main/controlMod.F90`, `elm_varctl.F90` |
| Snow physics | `components/elm/src/biogeophys/` (`SnowSnicarMod.F90`, `SnowHydrologyMod.F90`, `SurfaceAlbedoMod.F90`, `CanopyHydrologyMod.F90`) |
| History output fields | `grep -rn "hist_addfld" components/elm/src` |

### Documentation

The docs at https://docs.e3sm.org are built with mkdocs from Markdown files in the repo:
- ELM docs: `components/elm/docs/` (user-guide: `surface_dataset.md`, `interpinic.md`,
  `fates.md`; tech-guide: shortwave/longwave/TOP solar radiation)
  → https://docs.e3sm.org/E3SM/ELM/user-guide/
- General E3SM docs: `docs/` (installation, user-guide, adding grid support, including
  `generate-lnd-input-data.md`)
- CIME (create_newcase, xmlchange, case.setup/build/submit):
  https://esmci.github.io/cime/ (not available locally, because `cime/` is not checked out)

CLM docs (secondary, use with care): ELM was forked from **CLM4.5** around 2014 and
has diverged from it since then.
- CLM4.5 Technical Note (Oleson et al. 2013, NCAR/TN-503+STR): the closest reference
  for ELM physics equations, including the snow cover fraction scheme
  (Swenson & Lawrence 2012).
- CLM5 docs (https://escomp.github.io/CTSM/release-clm5.0/): helpful for general
  concepts (CIME workflow, single-point and regional runs, history fields), but
  CLM5's physics, namelist variable names and tools (CTSM `subset_data`, NUOPC) are
  NOT ELM's.
- Before applying anything from CLM docs to ELM, check it against the ELM source.

Local docs follow local `master` (about 2025-07). If something seems missing or
outdated, fetch the live site, or run `git -C ../E3SM fetch upstream` once an upstream
remote has been added.
