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

TODO

## 3. Namelist sweep

TODO
