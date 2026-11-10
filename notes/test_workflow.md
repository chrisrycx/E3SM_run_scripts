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
   Run `tools/cprnc_compare.sh TG_NLDAS2_5d_2000_baseline TG_NLDAS2_5d_2000_new`, or by hand:
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

A sweep runs one snow season many times, changing one namelist setting at a time, e.g.
every `snow_fsca_param` scheme. At Tony Grove, the season run (1 Oct to 1 Jul, 273
days) takes about 20 min to build and about 10 min to run.

### The idea: build once, clone many

The model executable doesn't depend on `user_nl_elm`. The namelist is read when the
model starts. So cases that differ only in namelist settings can share one executable:

```
TG_NLDAS2_WY20XX.sh  →  base case (full build, ~20 min)  →  bld/e3sm.exe
                              │
clone_variant.sh  ─────────── ├─ clone _NY07      (no build, own user_nl_elm, own run/)
                              ├─ clone _Helbig21
                              └─ clone _CZ26
```

`sweep_fsca.sh` runs both steps: it builds the base case if needed, then clones each
variant.

`clone_variant.sh` uses CIME's `create_clone --keepexe` (see `CIME/case/case_clone.py`
in the `cime` submodule). `--keepexe` points the clone's `EXEROOT` at the base case's
`bld/` directory and sets `BUILD_COMPLETE=TRUE`, so `case.build` is skipped.

### Scripts

There are three scripts in `run_scripts/testing/`, one per job:

| Script | Job | Changes when |
|---|---|---|
| `TG_NLDAS2_WY20XX.sh` | create and build one case (the base) | the site, forcing, season or history output changes |
| `clone_variant.sh` | clone a built case, change its namelist, run it | rarely (it's generic) |
| `sweep_<name>.sh`, e.g. `sweep_fsca.sh` | list one experiment's variants; build the base if needed, then clone each variant | you add or change a variant |

Why three scripts instead of one script that builds and then runs every variant:
- **The base case is built only when needed.** `TG_NLDAS2_WY20XX.sh` always deletes
  and rebuilds its case. A combined script would rebuild (20 min) every time you added
  a variant, and the rebuild would delete the executable the existing clones use. The
  sweep script calls it only when the base case has no successful build.
- **Each script changes for one reason.** The base case changes with the E3SM commit or
  the run setup, and a sweep list changes with each experiment. A new experiment
  (snow shape, SNICAR settings, ...) is a new `sweep_<name>.sh` file. The tested build
  script doesn't change.
- **Each sweep file records the experiment.** It's in git, so the variant list and its
  settings show what was run.
- **Reruns pick up where they left off.** Adding a variant means adding a line and
  rerunning: finished variants are skipped and only the new one runs. A failed variant
  doesn't stop the others.
- **Each piece also works on its own.** `clone_variant.sh` is still handy for a single
  one-off variant, and `TG_NLDAS2_WY20XX.sh` for a single run.

**Base case:**
```bash
[WY=<year>] [TAG=<tag>] [FSCA=<value>] [FINIDAT=<file>] [EXTRA_NML=<lines>] ./TG_NLDAS2_WY20XX.sh
```
- `WY`: water year, default 2012 (Oct 2011 - Jun 2012). NLDAS2 allows 1981-2018.
- `TAG`: default `base`. The case is `$OUTPUT_ROOT/TG_NLDAS2_WY<WY>_<TAG>`.
- `FINIDAT`: initial conditions from a restart file. Unset = cold start.
- `EXTRA_NML`: extra `user_nl_elm` lines, appended as-is.

**Variants:**
```bash
TAG=<tag> [FSCA=<value>] [EXTRA_NML=<lines>] [BASE=<case>] [NOSUBMIT=1] ./clone_variant.sh
```
- `BASE`: the built case to clone, default `TG_NLDAS2_WY2012_base`.
- The clone is named `<BASE>_<TAG>`, e.g. `TG_NLDAS2_WY2012_base_NY07`, so the name
  shows which build it used. An existing case with that name is deleted first.
- `FSCA` replaces the base case's `snow_fsca_param` line. Any variable set in
  `EXTRA_NML` replaces that variable's line from the base case, so nothing is set twice.
- Inside `salloc`, each variant runs right away with `case.submit --no-batch`, one after
  another (about 5 per 1-hour allocation). On a login node, each is submitted as a
  batch job (debug queue), so a loop queues all of them at once. `NOSUBMIT=1` only
  creates the case.

**Sweep:**
```bash
WY=<year> BASE_TAG=<tag> [RERUN=<tags>|all] ./sweep_fsca.sh
```
- `WY` and `BASE_TAG` are required, with no defaults. If one is missing, the script
  lists the existing base cases and asks for it (or stops with an error when not run
  from a terminal).
- The variants are listed in the script, one `variant <TAG> <FSCA> [<EXTRA_NML>]` line
  each. `FSCA ""` keeps the base value. Example:
  `variant CZ26_spheroid CZ26 "snow_shape = 'spheroid'"`.
- The base case is `TG_NLDAS2_WY<WY>_<BASE_TAG>`, run with `BASE_FSCA=SL12_legacy`. It
  is the SL12_legacy run of the sweep, so SL12_legacy isn't listed as a variant. The
  sweep runs it like a variant (same skip rules; `RERUN=base` to redo it).
- The variants are `TG_NLDAS2_WY<WY>_<BASE_TAG>_<TAG>`.
- What it does with each piece on a rerun:

  | State | Action |
  |---|---|
  | Base case has no successful build | build it (`TG_NLDAS2_WY20XX.sh`) |
  | Base case built | keep it; warn if `E3SM_ROOT` is now at another commit |
  | Base case built but never run, or its run failed | run it (no rebuild) |
  | Base case finished, queued or running | skip (`RERUN=base` reruns it) |
  | Variant finished with the same settings | skip |
  | Variant finished, but its line in the script changed | redo |
  | Variant queued or running | skip, so a batch job isn't deleted under it |
  | Variant failed or never ran | redo |
  | Variant named in `RERUN` (or `RERUN=all`) | redo, whatever its state |

  The run state comes from the last `case.run` line in the clone's `CaseStatus`. The
  settings come from `sweep_variant.txt`, which the sweep writes into each clone.
- A run killed by the end of an allocation or a wall-clock limit stays marked
  `running`. If its job isn't in `squeue`, rerun it with `RERUN=<tag>`.
- It ends with a summary (finished, run or submitted, queued or running, failed) and
  exits nonzero if any variant failed.
- A new experiment: copy `sweep_fsca.sh` to `sweep_<name>.sh` and change the `variant`
  lines (and `BASE_FSCA` if needed).

### Steps (on Perlmutter)

1. **Check the source is clean:**
   ```bash
   cd $E3SM_ROOT && git status --short    # should print nothing
   ```
2. **Run the sweep.** On a login node, it builds the base case (about 20 min), then
   submits each variant as a batch job:
   ```bash
   cd ~/.../E3SM_run_scripts/run_scripts/testing
   WY=2012 BASE_TAG=base ./sweep_fsca.sh
   ```
   Inside `salloc`, the base case and the variants run one after another instead
   (20 min build + 10 min per run, so a 1-hour allocation won't fit them all). Run
   the script again in a new allocation to finish the rest.
3. **Check a clone** (first time): in `$OUTPUT_ROOT/<case>/`,
   `./xmlquery EXEROOT,RUNDIR,BUILD_COMPLETE` should show the base case's `bld/`, the
   clone's own `run/` and `TRUE`. `CaseDocs/lnd_in` should show the changed setting.
4. **Check the runs finished:** run `./sweep_fsca.sh` again. Its summary lists what's
   finished, and it reruns any variant that failed. Or look at
   `tail $OUTPUT_ROOT/<case>/CaseStatus`.

For a one-off variant outside a sweep, use `clone_variant.sh` directly, e.g.
`TAG=spheroid EXTRA_NML="snow_shape = 'spheroid'" ./clone_variant.sh`.

### Where things are

| | Base case | Clone |
|---|---|---|
| Case scripts | `$OUTPUT_ROOT/<case>/case_scripts/` | `$OUTPUT_ROOT/<case>/` |
| Run dir (output, logs) | `$OUTPUT_ROOT/<case>/run/` | `$OUTPUT_ROOT/<case>/run/` |
| Executable | `$OUTPUT_ROOT/<case>/bld/` | the base case's `bld/` |

The clones' case scripts can't use the `<case>/case_scripts` layout, because
`create_clone` takes the case name from the last part of the directory path (the case
would be named `case_scripts`). So a clone's case directory is `$OUTPUT_ROOT/<case>/`
itself, with `run/` inside it: one folder per case, as for base cases. Run
directories are in the same place for both, so analysis code finds output the same way.
(Older clones kept their scripts in `$OUTPUT_ROOT/clones/<case>/`; `clone_variant.sh`
deletes that folder when it redoes the variant.)

Each clone's `E3SM_COMMIT.txt` holds the base case's commit record, plus the clone's
`TAG`, `FSCA`, `EXTRA_NML` and `EXEROOT`.

### Limits

- **Run-time changes only:** `user_nl_elm` and `env_run.xml` settings (history,
  `STOP_N`, ...). NTASKS, the compset or source code changes need a new base case.
- **Clones depend on the base case's `bld/`.** Rerunning `TG_NLDAS2_WY20XX.sh` with
  the same `TAG` deletes the base case and rebuilds it. That breaks the clones, or
  silently gives them a new executable. For a new commit, use a new base `TAG`
  (`BASE_TAG` for the sweep script). The sweep script never rebuilds a built base case.
- **Cold start:** without `FINIDAT`, soil temperature and moisture start from arbitrary
  values. That biases the early season, the same way in every variant.

### Rerunning a sweep after a bug fix

A fix in the Fortran source means a new executable, which the old clones can't share.
Build one new base case from the fixed commit, then clone the sweep again. The old
sweep stays in place for comparison.

1. **Fix and unit-test locally** (tier 1). Add a test that would have caught the bug.
   Commit on the `fsca` branch and push.
2. **Update the source on Perlmutter:**
   ```bash
   cd $E3SM_ROOT && git pull && git status --short   # should print nothing
   ```
   A clean tree makes `E3SM_COMMIT.txt` record the exact commit, not `<hash>-dirty`.
3. **Optional regression check** (tier 2): if the bug is in one scheme (say NY07),
   the other schemes should be unchanged. Run the 5-day case with `FSCA=SL12` on the
   old and new commits and compare them with `tools/cprnc_compare.sh`. They should be
   identical, which shows the fix touched only what it was meant to.
4. **Run the sweep with a new base tag.** It builds a new base case from the fixed
   commit and clones every variant from it. Don't reuse `base`, because the old clones
   still need its `bld/`:
   ```bash
   WY=2012 BASE_TAG=fix1 ./sweep_fsca.sh
   ```
   With the same `BASE_TAG`, the script would keep the old build and only warn that
   `E3SM_ROOT` has moved.
5. **Check the runs finished** (rerun the same command; see Steps above).
6. **Compare old and new pairs**, e.g. `TG_NLDAS2_WY2012_base_NY07` with
   `TG_NLDAS2_WY2012_fix1_NY07`, and the base cases themselves (the SL12 runs). Only
   the variants that use the buggy code should differ.
7. **Clean up** the old sweep when you no longer need it. Delete its clones
   (`$OUTPUT_ROOT/<case>`) before or together with
   the old base case, since they use its executable.

### Debugging shortcut: rebuild the base case in place

While you're still trying out a fix, a full new base case each time is slow. Instead,
rebuild the existing base case and rerun its clones:

```bash
cd $E3SM_ROOT && git pull                     # or edit the source directly
cd $OUTPUT_ROOT/TG_NLDAS2_WY2012_base/case_scripts
./case.build                                  # recompiles only the changed files
cd $OUTPUT_ROOT/TG_NLDAS2_WY2012_base_NY07
./case.submit --no-batch                      # inside salloc; ./case.submit otherwise
```

- `case.build` in an already built case is incremental: `make` recompiles only the
  source files that changed (and those that depend on them), then relinks. This should
  take a few minutes, not 20.
- The clones point at the same `bld/`, so they pick up the new executable with no
  re-cloning. Just submit them again, or redo the whole sweep with
  `WY=2012 BASE_TAG=base RERUN=all ./sweep_fsca.sh`. That re-clones each variant from the rebuilt base case,
  which takes about a minute each with no build. Add the base case's own
  (SL12_legacy) run with `RERUN="base ..."` or `RERUN=all`.

What this costs:
- Each run overwrites that case's old output in `run/`, so there's nothing left to
  compare against. Copy the files you want to keep first.
- Every `E3SM_COMMIT.txt` (base case and clones) now records the old commit. It's
  wrong.
- Uncommitted edits get compiled in too, and nothing records them.

Use the shortcut for debugging only. For results you'll keep or show, build a new
base case (steps 4-5 above), so each case's record matches the code it ran.
