# Test workflow for ELM development

How to check changes to ELM source code, from fastest to slowest. Paths are relative to
the E3SM root (`../E3SM`), on the local `fsca` branch.

| Tier | Question it answers | Where | Time |
|---|---|---|---|
| 1. Unit tests | Does this subroutine compute what I intended? | laptop | seconds |
| 2. Short ELM run | Does it build, run and restart in the full model? | Perlmutter | minutes |
| 3. Namelist sweep | What effect does a namelist setting have? | Perlmutter | minutes–hours |

## 1. Unit tests

### What exists

ELM has no working official unit-test framework:
- `components/elm/src/README.unit_testing` is a CLM leftover. It points to a script on
  NCAR's retired yellowstone machine.
- The pFUnit test directories were removed in E3SM commit `05472001c0` ("Deletes test
  directories that are not used by E3SM").

Instead, standalone tests are compiled with a small Makefile and plain `gfortran`. You
don't need CIME, Perlmutter or NetCDF. The tests for the snow cover fraction module are in

```
components/elm/src/biogeophys/test/SnowCoverFraction_test/
├── Makefile                    build and run rules
├── stubs.F90                   fake versions of the modules SnowCoverFractionMod `use`s
└── test_SnowCoverFraction.F90  the tests
```

- `stubs.F90` stands in for the rest of ELM: `shr_kind_mod` (`r8`), `elm_varctl`
  (`snow_fsca_param`), `elm_varcon`, etc. That's why the module compiles on its own.
- The Makefile compiles the real source file `../../SnowCoverFractionMod.F90`, not a
  copy, so whatever you edit there is what gets tested.

### Running

```bash
cd ../E3SM/components/elm/src/biogeophys/test/SnowCoverFraction_test
make          # compile and run the tests (same as `make test`)
make clean    # delete .o, .mod and the executable
```

`make` compiles `stubs.F90`, then `SnowCoverFractionMod.F90`, links
`test_SnowCoverFraction` and runs it. Each check prints `PASS` or `FAIL`, and the run
ends with `all checks passed` or `N check(s) FAILED`. A failure exits with a nonzero
status (`error stop 1`), so `make` reports an error and scripts can detect it.

`make` compares file timestamps: after an edit it recompiles only what changed. If
nothing changed, it just reruns the tests.

Options:
- Another compiler: `make FC=ifort`
- Debug checks (array bounds, uninitialized values, like ELM's `ERS_D` tests):
  `make clean && make FFLAGS="-cpp -g -O0 -fcheck=all -ffree-line-length-none"`

### Edit–test loop

1. Edit `components/elm/src/biogeophys/SnowCoverFractionMod.F90`.
2. Run `make` in the test directory.
3. Once the tests pass, build and run on Perlmutter (tier 2).

The tests cover only `SnowCoverFractionMod`. Changes to code that calls it
(`CanopyHydrologyMod`, `WaterStateType`) still need the full ELM build.

To see the tests at work, change a coefficient in the module, run `make`, see which
tests fail, then undo the change.

### Adding a test

1. In `test_SnowCoverFraction.F90`, copy an existing `test_*` subroutine inside
   `contains`, rename it and change the inputs and expected result. Report the result
   with `call check(ok, 'description')`.
2. Add `call test_yourname()` to the list at the top of the program.
3. Run `make`.

If the module starts to `use` another ELM module or variable, the compile fails with
something like "Cannot open module file". Add a minimal fake version of it to
`stubs.F90`.

Useful kinds of test:
- **Physical bounds**: fSCA in [0, 1], depth ≥ 0, for every scheme.
- **Limiting cases**: no snow on the ground and none falling.
- **Known values**: hand-computed from the paper's equations.
- **Bit-for-bit with old code**: e.g. `SL12_legacy` reproduces the original
  CanopyHydrology code exactly. This proves the default behavior hasn't changed by
  accident.

### Writing testable code

Unit tests are easiest when the physics is a plain subroutine that takes scalars or
arrays. Keep the ELM plumbing (`bounds`, filters, derived types like
`waterstate_vars`) in a thin wrapper that unpacks the data and calls the physics.
Test the physics here; the wrapper gets tested in the full model run.

### Housekeeping

The `.o` and `.mod` files are gitignored by E3SM's `.gitignore`, but the executable
`test_SnowCoverFraction` isn't. It shows up as untracked in `git status` until you run
`make clean`.

## 2. Short ELM run

A 5-day run at Tony Grove with `run_scripts/testing/TG_NLDAS2_5d_2000.sh` checks that
the code builds and runs in the full model. To check that a change *didn't* alter the
model's answers, run a **regression test**: run the same case from two commits and
compare the output bit for bit.

### The idea

```
reference code (commit you trust)  →  run case "baseline"  →  output A
your modified code                 →  run case "new"       →  output B
                                       cprnc A B  →  identical?
```

Identical output is what you want for a refactor, or for a new option that's switched
off. If you switch a new scheme on, the answers *should* differ. Judging that difference
is tier 3, not a regression test.

### Choosing the reference commit

| What you want to show | Reference |
|---|---|
| "This edit changed nothing" (the usual case) | your last commit, before you start editing |
| "My refactor kept the old results" | the commit before the refactor, e.g. `edcbdcd34c` before `fe85f116b9` |
| "My branch matches upstream when the option is off" | `master` (only if the case doesn't set options `master` lacks, like `snow_fsca_param`) |

A commit hash is already a permanent name, so a git tag isn't needed. For a
reference you'll use often, a tag can help: `git tag fsca-pre-refactor edcbdcd34c`.
Tags are local to each clone, so create it on Perlmutter, where you build.

### Script options

```bash
[TAG=<tag>] [FSCA=<value>] ./TG_NLDAS2_5d_2000.sh [path/to/machine.env]
```
- `TAG`: case-name suffix, default `quicktest`. The case is
  `$OUTPUT_ROOT/TG_NLDAS2_5d_2000_<TAG>`. An existing case with the same name is
  deleted first, so use a different tag for each case you want to keep.
- `FSCA`: the `snow_fsca_param` value, default `SL12`. Give it without quotes; the script
  quotes strings and leaves integers as they are.

All other settings must be identical between the two cases: compiler, `NTASKS`,
dates, forcing and history fields. The script keeps them fixed.

The namelist can differ between commits. For the SL12 refactor:

| Commit | `snow_fsca_param` | Old Swenson & Lawrence (2012) scheme |
|---|---|---|
| `edcbdcd34c` (before) | integer: `0` SL12, `1` NY07, `2` Helbig21 | `FSCA=0` |
| `fe85f116b9` (after) | string: `SL12`, `SL12_legacy`, `NY07`, `Helbig21`, `CZ26` | `FSCA=SL12_legacy` |

Use `SL12_legacy`, not `SL12`, on the new code. `SL12` removes the fSCA drop on first
melt after snowfall on purpose, so it isn't expected to match.

### Steps (on Perlmutter)

1. **Get a compute node:**
   ```bash
   salloc --nodes 1 --qos interactive --time 01:00:00 --constraint cpu --account m4986
   ```
2. **Check out the reference commit, with a clean tree:**
   ```bash
   cd $E3SM_ROOT
   git status --short                 # should print nothing
   git checkout edcbdcd34c            # "detached HEAD" warning is expected
   git submodule update --init --recursive
   ```
3. **Build and run the baseline case:**
   ```bash
   cd ~/.../E3SM_run_scripts/run_scripts/testing
   TAG=baseline FSCA=0 ./TG_NLDAS2_5d_2000.sh
   ```
4. **Check out the new commit, then build and run the new case:**
   ```bash
   cd $E3SM_ROOT && git checkout fe85f116b9 && git submodule update --init --recursive
   cd -
   TAG=new FSCA=SL12_legacy ./TG_NLDAS2_5d_2000.sh
   ```
   Don't run `./case.build` in the baseline case after this. It would recompile from
   the new code.
5. **Check that both runs finished:** `tail case_scripts/CaseStatus` in each case should
   show `case.run success`.
6. **Compare the output with cprnc:**
   See /tools/cprnc_compare.sh
   ```bash
   CPRNC=/global/cfs/cdirs/e3sm/tools/cprnc/cprnc
   B=$OUTPUT_ROOT/TG_NLDAS2_5d_2000_baseline/run
   N=$OUTPUT_ROOT/TG_NLDAS2_5d_2000_new/run
   $CPRNC -m $B/*.elm.r.*.nc  $N/*.elm.r.*.nc  | tail -20    # restart: full model state
   $CPRNC -m $B/*.elm.h1.*.nc $N/*.elm.h1.*.nc | tail -20    # hourly history
   ```
   `-m` compares records by position. Restart files have no time dimension, so
   without it cprnc stops with "These files don't have a time dimension, use cprnc
   with -m" before it compares anything.
7. **Return to your branch:**
   ```bash
   cd $E3SM_ROOT && git checkout fsca && git submodule update --init --recursive
   ```

### Reading the result

- The summary at the end of the cprnc output says whether the files are identical. If
  they differ, it lists the fields that differ and the largest difference. Those
  fields show where to start looking.
- **Compare the restart file (`*.elm.r.*.nc`) first.** The history files hold only the
  fields in `hist_fincl` (18 here), but the restart file holds the whole model state:
  every snow layer, temperature and water store. Any difference anywhere shows up
  there.
- A variable in only one file ("Could not find match for file2 variable ...") is
  skipped, not counted as a difference. It's expected when the new code adds a
  restart field, e.g. `SWE_MAX_EFF` in `fe85f116b9`.
- Compare matching files only (`r` with `r`, `h1` with `h1`). Ignore the logs, since
  they contain timestamps and timings.

### Which commit built a case?

The script writes `case_scripts/E3SM_COMMIT.txt` just before it builds. The file holds
the commit, branch, date, `TAG`, `FSCA`, `git status` and `git submodule status`.
- If `E3SM_ROOT` has uncommitted edits to tracked files, the commit is recorded as
  `<hash>-dirty` and the script warns. Don't use a dirty case as a baseline.
- In `git submodule status`, a `+` before a hash means that submodule doesn't match the
  commit.
- **One case = one commit.** The record goes stale if you check out another commit and
  run `./case.build` in the same case by hand. For a new commit, make a new case.

### Later: CIME's `create_test`

CIME's `create_test` automates the same comparison and adds a restart-exactness check.
An `ERS` test runs 5 days straight through, then again with a restart partway, and
checks that both give identical results. That catches variables missing from the restart
file.
- `-g` saves a run's output as a baseline, and `-c` compares a new run against it.
  Use your own `--baseline-root` (e.g. `$PSCRATCH/e3sm_baselines`). The default
  `/global/cfs/cdirs/e3sm/baselines` belongs to E3SM's nightly testing.
- The TG domain, surface data and forcing would go in a *testmod* under
  `components/elm/cime_config/testdefs/testmods_dirs/elm/`, a directory of
  `user_nl_elm` and `shell_commands`. See `extrasnowlayers/` or `koch_snowflake/` for
  examples.
- Not set up yet. Check the exact flags with `./create_test --help` on Perlmutter.

## 3. Namelist sweep

TODO
