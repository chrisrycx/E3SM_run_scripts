# fSCA development status

Status of the snow cover fraction (fSCA) work in ELM. Code is on the E3SM fork, branch
`fsca` (`../E3SM`, pushed to `origin/fsca`). Paths below are relative to
`components/elm/src/biogeophys/` unless given in full.

Related notes: [elm_code_architecture.md](elm_code_architecture.md) (where fSCA sits in
the time step, what snow depth means), [test_workflow.md](test_workflow.md) (unit tests,
regression runs, sweeps).

## Goal

Implement new fSCA algorithms in ELM behind an architecture that is easy to read and
maintain, while keeping the legacy behavior available for comparison:

- one module, `SnowCoverFractionMod.F90`, holds every fSCA scheme;
- each scheme is one routine that takes only the inputs it uses and is unit-testable on
  its own;
- the scheme is chosen with the `snow_fsca_param` namelist variable;
- legacy E3SM behavior (`SL12_legacy`) stays bit-for-bit reproducible, so new schemes
  can be compared with it.

## Current status (2026-11-06)

| Item | State |
|---|---|
| Latest commit | `2f00a8dd4a` "Simplify fSCA interfaces to make algorithm clear" |
| Unit tests (laptop) | 15/15 pass |
| Builds on Perlmutter | **not yet checked** for `2f00a8dd4a` |
| Regression runs (tier 2) | **pending**, see [Next: Perlmutter tests](#next-perlmutter-tests) |
| Season runs / sweeps (tier 3) | not started for the new SL12 |

## Commit history

| Commit | Date | Change |
|---|---|---|
| `edcbdcd34c` | 2026-09-30 | NY07 subroutine. Last commit with fSCA inline in CanopyHydrology and integer `snow_fsca_param` (`0` SL12, `1` NY07, `2` Helbig21) |
| `fe85f116b9` | 2026-10-30 | All schemes moved into `SnowCoverFractionMod`; string `snow_fsca_param`; `SL12_legacy` added; separate `swe_max_eff` state for SL12/CZ26 |
| `2f00a8dd4a` | 2026-11-06 | Simplified interface (below). Schemes no longer change snow depth; SL12 follows one curve per step; legacy sequence moved into CanopyHydrology |

## Architecture (as of `2f00a8dd4a`)

Per column, per time step, in `CanopyHydrology` (`CanopyHydrologyMod.F90`), before new
snow is added to `h2osno`:

```
if snow_fsca_param == SL12_legacy:
    if melt last step:  fsca_SL12_update(newsnow = 0)       ! depletion
    if new snow:        fsca_SL12_update(newsnow)           ! accumulation
    (state: int_snow, exponent: col_pp%n_melt)
else:
    snow_depth_unif = depth with new snow spread over the whole cell
    UpdateSnowCoverFraction(swe, newsnow, snow_depth_unif, frac_sno,
                            sigma_elev, swe_max_eff)        ! dispatches on fsca_method
    NY07: new-snow depth is uniform (subgrid_snow = .false.)
UpdateSnowDepthNewSnow(swe, newsnow, bifall, subgrid_snow, frac_sno, snow_depth)
h2osno += newsnow; int_snow += newsnow
```

Design rules:
- **Schemes update fSCA and their own state only.** Snow depth is an input, updated
  afterwards by `UpdateSnowDepthNewSnow`. `bifall`, `subgrid`, `snowmelt` and `int_snow`
  are not part of the scheme interface.
- **One curve per step:** accumulation if `newsnow > 0`, otherwise depletion from the
  current SWE state. There is no "melt, then accumulate" within a step, since fSCA
  parameterizations aren't fitted that way. Only `SL12_legacy` keeps that sequence, and it
  lives in CanopyHydrology, not in the module.
- **Legacy quirks stay in the caller.** The module has no legacy-only arguments.

### Schemes

| `snow_fsca_param` | Routine | Uses | State | Notes |
|---|---|---|---|---|
| `SL12` (default) | `fsca_SL12_update(swe, newsnow, n_melt, frac_sno, swe_max_eff)` | `n_melt = 200/max(10, sigma_elev)`, set in the dispatcher | `swe_max_eff` | **Results differ from legacy** (see below) |
| `SL12_legacy` | same routine, called twice from CanopyHydrology | `col_pp%n_melt`, `snowmelt` | `int_snow` | Bit-for-bit with original E3SM code |
| `NY07` | `fsca_NY07_update(swe, newsnow, snow_depth, frac_sno [, dx])` | `snow_depth_unif` | none | `dx` present selects AR25 (Abolafia-Rosenzweig et al. 2025); not wired up |
| `CZ26` | `fsca_CZ26_update(swe, newsnow, sigma_elev, frac_sno, swe_max_eff)` | `sigma_elev`; `n_melt = 200/max(1, sigma)` inside | `swe_max_eff` | `swe_max_eff` reset Aug 1 / Feb 1 in CanopyHydrology |
| `Helbig21` | `fsca_Helbig21_update(...)` | many | `col_ws%helbig_*` | Preserved, **disabled** (stops the model) |

`sigma_elev` is the gridcell field `fsca_stdev_elev`, read from the surface file variable
`fsca_stddev_elev`. The read is unconditional: a surface file without it (or without
`fsca_slope_mu`) stops the model (`components/elm/src/main/surfrdMod.F90`, `surfrd_get_grid`).

Why SL12 takes `n_melt` as an argument instead of deriving it from sigma like CZ26: the
legacy path uses `col_pp%n_melt` (per column, `200/max(10, topo_std)`, fixed at 10 on
`istice_mec` columns, `components/elm/src/main/initVerticalMod.F90`), which can't be
rebuilt from `sigma_elev`.

### What changed in the new SL12 vs. legacy

Intended changes, so `SL12` is **not** expected to match `SL12_legacy`:
1. No fSCA drop on the first melt after snowfall (`swe_max_eff` is separate from
   `int_snow`, which CanopyHydrology also adds snowfall to). Since `fe85f116b9`.
2. A step with snowfall only accumulates; no depletion first. Since `2f00a8dd4a`.
3. Depletion runs on every step without snowfall, not only after melt, so SWE loss by
   sublimation now lowers fSCA. Since `2f00a8dd4a`.
4. `n_melt` comes from the gridcell `fsca_stdev_elev` instead of the column `topo_std`.
   Since `2f00a8dd4a`.

## Verification

| Check | How | Result |
|---|---|---|
| `SL12_legacy` = original inline CanopyHydrology code | unit test `test_SL12_legacy_matches_original`, 200k random cases, exact comparison | pass |
| NY07, CZ26, SL12_legacy unchanged by `2f00a8dd4a` | old and new module compiled side by side, 2M random cases each, exact comparison of `frac_sno`, `snow_depth`, CZ26 `swe_max_eff` (one-off, scratch program) | 0 mismatches |
| New SL12 behavior (items 2–4 above) | unit tests `test_SL12_one_curve_per_step`, `test_SL12_sublimation`, `test_SL12_n_melt_from_sigma` | pass |
| fSCA in [0,1], depth >= 0 | unit test `test_bounds`, all schemes | pass |
| CanopyHydrology compiles | only on Perlmutter | **pending** |
| Full-model bit-for-bit | regression runs | **pending** |

The unit tests run the CanopyHydrology sequence through a copy, `ch_step` in
`test/SnowCoverFraction_test/test_SnowCoverFraction.F90`. Keep it in sync when the
sequence in CanopyHydrology changes.

## Next: Perlmutter tests

With `run_scripts/testing/TG_NLDAS2_5d_2000.sh` and `cprnc` (see
[test_workflow.md, section 2](test_workflow.md#2-short-elm-run)):

| # | Reference | New (`2f00a8dd4a`) | Expect |
|---|---|---|---|
| 1 | — | build | builds |
| 2 | `fe85f116b9`, `FSCA=SL12_legacy` (or `edcbdcd34c`, `FSCA=0`) | `FSCA=SL12_legacy` | identical |
| 3 | `fe85f116b9`, `FSCA=NY07` | `FSCA=NY07` | identical |
| 4 | `fe85f116b9`, `FSCA=CZ26` | `FSCA=CZ26` | identical |
| 5 | `fe85f116b9`, `FSCA=SL12` | `FSCA=SL12` | differs; check that the differences are plausible (tier 3) |

A 5-day run only exercises the code paths that occur in those 5 days. For melt and
season reset, repeat 2–4 with the water-year run `TG_NLDAS2_WY20XX.sh`.

## Open issues

- **Compaction uses legacy state.** `SnowHydrologyMod.F90` (`SnowCompaction`, melt
  compaction with `subgridflag == 1`) recomputes a melt fSCA from `int_snow` and
  `col_pp%n_melt`. For `SL12` and `CZ26` this doesn't match their own `swe_max_eff` and
  `n_melt`. To be handled outside this module.
- **Different `n_melt` floors.** SL12 uses `max(10, sigma)`, CZ26 `max(1, sigma)`. For
  sigma < 10 m CZ26's exponent goes up to 200 (very steep depletion). Decide whether this
  is intended.
- **NY07 depth meaning.** NY07 works from column-mean depth, but `snow_depth` elsewhere in
  ELM is depth over the snow-covered area. See
  [elm_code_architecture.md, section 6](elm_code_architecture.md#concern-fsca-parameterizations-use-column-mean-depth).
  NY07 here also differs from `master`'s `oldfflag = 1` NY07, which adds depth with the
  subgrid formula and then recomputes fSCA from it.
- **`subgrid_snow` in CanopyHydrology.** Possibly remove later. `subgridflag` is also used
  for `frac_sno_eff` in CanopyHydrology and in `SnowHydrologyMod.F90`, so snow-depth
  meaning must stay consistent across all of them.
- **CZ26 season reset** of `swe_max_eff` is done in CanopyHydrology. Could move into the
  module.
- **Helbig21** is disabled. To re-enable, call it from `UpdateSnowCoverFraction` and pass
  the `col_ws%helbig_*` state.
- **elm_code_architecture.md sections 4–6** describe the code before `2f00a8dd4a`
  (melt-then-accumulate for SL12, `update_snow_depth_from_fsca`, old line numbers). Update
  them.

## Log

- **2026-11-06** Simplified the scheme interface (`2f00a8dd4a`). Moved snow depth out of
  the schemes (`UpdateSnowDepthNewSnow`), made SL12 one curve per step, moved the legacy
  two-call sequence into CanopyHydrology, made NY07 take depth as input. Updated unit
  tests (15 pass).
- **2026-10-30** Moved all schemes into `SnowCoverFractionMod` (`fe85f116b9`).
