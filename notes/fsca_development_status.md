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

## Current status (2026-11-25)

| Item | State |
|---|---|
| Latest commit | `7a91a96a74` "Update cz26 fortran to match drop_low_bins approach" (rows below about builds and regressions were written for `2f00a8dd4a` and the column-mean change, now `7141602472`) |
| Uncommitted | SL12 and CZ26 deplete before accumulating on snowfall steps (2026-11-25, see [fSCA timing](#fsca-timing-within-the-elm-time-step-2026-11-25)) |
| Unit tests (laptop) | 22/22 pass |
| Builds on Perlmutter | `2f00a8dd4a` yes; uncommitted change **not yet checked** |
| Regression runs (tier 2) | `2f00a8dd4a` `SL12_legacy` = `edcbdcd34c` (identical history). Uncommitted change **pending** |
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
    UpdateSnowDepthNewSnow(...)                             ! new snow piled on frac_sno
else:
    area_old   = frac_sno (subgrid snow cover) or 1
    depth_mean = snow_depth*area_old + newsnow/bifall       ! column mean, uniform new snow
    UpdateSnowCoverFraction(swe, newsnow, depth_mean, frac_sno,
                            sigma_elev, swe_max_eff)        ! dispatches on fsca_method
        SL12, CZ26: if swe > 0 and newsnow > 0:
                        update(newsnow = 0)                 ! deplete to current SWE
                    update(newsnow)                         ! accumulate (or deplete if no snow)
    area_new   = frac_sno (subgrid snow cover) or 1
    snow_depth = depth_mean/area_new                        ! back to depth over snow area
    snow layers: dz *= area_old/area_new, z and zi recomputed
h2osno += newsnow; int_snow += newsnow
```

**Snow depth convention.** ELM (with `subgridflag = 1`) stores `snow_depth` and the layer
`dz` as depth over the snow-covered area (the snow "tile"); mass (`h2osno`,
`h2osoi_ice`) is per column area. The new bookkeeping keeps that storage convention for
the rest of ELM, but the fSCA schemes and the new-snow update work in column-mean depth:
new snow adds exactly `newsnow/bifall` to the column mean, and when fSCA changes the
existing pack keeps its column-mean depth (it thickens or thins). Legacy instead piles new
snow onto the snow-covered area and leaves old snow at the same depth when fSCA changes,
which adds more column-mean depth than the snow that fell.

Design rules:
- **Schemes update fSCA and their own state only.** Snow depth (column mean) is an
  input; CanopyHydrology updates the stored depth. `bifall`, `subgrid`, `snowmelt` and
  `int_snow` are not part of the scheme interface.
- **Deplete, then accumulate (SL12, CZ26).** On a step with new snow on an existing
  pack, the dispatcher first depletes to the current SWE, then accumulates. Without
  snowfall, only depletion runs. This replaces the earlier "one curve per step" rule
  (2026-11-25); the reasons are in
  [fSCA timing](#fsca-timing-within-the-elm-time-step-2026-11-25). Unlike
  `SL12_legacy`, the depletion does not depend on `snowmelt > 0`.
- **Legacy quirks stay in the caller.** The module has no legacy-only arguments.

### Schemes

| `snow_fsca_param` | Routine | Uses | State | Notes |
|---|---|---|---|---|
| `SL12` (default) | `fsca_SL12_update(swe, newsnow, n_melt, frac_sno, swe_max_eff)` | `n_melt = 200/max(10, sigma_elev)`, set in the dispatcher | `swe_max_eff` | **Results differ from legacy** (see below) |
| `SL12_legacy` | same routine, called twice from CanopyHydrology | `col_pp%n_melt`, `snowmelt` | `int_snow` | Bit-for-bit with original E3SM code |
| `NY07` | `fsca_NY07_update(swe, newsnow, snow_depth, frac_sno [, dx])` | column-mean depth | none | `dx` present selects AR25 (Abolafia-Rosenzweig et al. 2025); not wired up |
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
2. ~~A step with snowfall only accumulates; no depletion first. Since `2f00a8dd4a`.~~
   Reverted 2026-11-25 (uncommitted): SL12 depletes first, as legacy does after melt.
   The difference from legacy is now item 3 (depletion also after sublimation).
3. Depletion runs on every step without snowfall, not only after melt, so SWE loss by
   sublimation now lowers fSCA. Since `2f00a8dd4a`.
4. `n_melt` comes from the gridcell `fsca_stdev_elev` instead of the column `topo_std`.
   Since `2f00a8dd4a`.
5. Column-mean snow depth bookkeeping (above). Uncommitted. This also changes NY07 and
   CZ26 results compared with `2f00a8dd4a`.

## Verification

| Check | How | Result |
|---|---|---|
| `SL12_legacy` = original inline CanopyHydrology code | unit test `test_SL12_legacy_matches_original`, 200k random cases, exact comparison | pass |
| NY07, CZ26, SL12_legacy unchanged by `2f00a8dd4a` | old and new module compiled side by side, 2M random cases each, exact comparison of `frac_sno`, `snow_depth`, CZ26 `swe_max_eff` (one-off, scratch program) | 0 mismatches |
| New SL12 behavior (items 3–4 above) | unit tests `test_SL12_sublimation`, `test_SL12_n_melt_from_sigma` | pass |
| Deplete then accumulate (SL12, CZ26) | unit tests `test_SL12_deplete_then_accumulate` (matches legacy after melt; no-op when SWE unchanged), `test_CZ26_deplete_then_accumulate` | pass |
| fSCA in [0,1], depth >= 0 | unit test `test_bounds`, all schemes | pass |
| Column-mean depth grows by exactly `newsnow/bifall` (SL12, NY07, CZ26; subgrid on and off) | unit test `test_column_mean_depth` | pass (layer rescaling not covered: it isn't in the module) |
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
Done for `2f00a8dd4a`: build, and `SL12_legacy` identical to `edcbdcd34c` (`FSCA=0`).

For the column-mean change:

| # | Reference | New | Expect |
|---|---|---|---|
| 1 | — | build | builds |
| 2 | `2f00a8dd4a` or `edcbdcd34c` (`FSCA=0`), `SL12_legacy` | `FSCA=SL12_legacy` | identical |
| 3 | `2f00a8dd4a`, `FSCA=SL12` / `NY07` / `CZ26` | same | differ; check plausibility (tier 3) |

For #3, with `hist_dov2xy = .false.` compare per column: `SNOWDP` (= column-mean depth)
should now track `H2OSNO/bifall`-like accumulation, and implied pack density
`H2OSNO/(FSNO*SNOW_DEPTH)` should stay in a plausible range (~50–550 kg/m³).

A 5-day run only exercises the code paths that occur in those 5 days. For melt and
season reset, use the water-year run `TG_NLDAS2_WY20XX.sh`.

## fSCA timing within the ELM time step (2026-11-25)

Summary of a discussion on when fSCA is computed relative to SWE, and why SL12/CZ26
now deplete before they accumulate.

**Order in one step k** (from t_(k-1) to t_k), from `components/elm/src/main/elm_driver.F90`:

| Order | What happens | `h2osno` seen |
|---|---|---|
| `BeginColWaterBalance`, `elm_drv_init` | read only (`begwb`; `h2osno_old = h2osno`; `do_capsnow`) | SWE(t_(k-1)) |
| `CanopyHydrology` | fSCA from SWE(t_(k-1)) and `newsnow`; then `h2osno += newsnow` | SWE(t_(k-1)) |
| `SurfaceRadiation`, `CanopyTemperature`, `SoilFluxes` | fluxes weighted by that fSCA | |
| `SoilTemperature` → `PhaseChange` | melt, using that fSCA | SWE drops |
| `HydrologyNoDrainage` → `CombineSnowLayers` | `h2osno` rebuilt from the layers (`SnowHydrologyMod.F90`) | SWE(t_k) |
| step k+1, `CanopyHydrology` | fSCA from SWE(t_k) | |

- `h2osno` at the start of `CanopyHydrology` is the end of the previous step's value;
  nothing before it in the step changes it. `snowmelt` there is also last step's melt.
- fSCA is explicit in time: it is fixed for the whole step, and the step's melt changes
  it only at the next step. fSCA = f(SWE(t_k)) during step k would be implicit (melt
  needs fSCA, fSCA needs post-melt SWE) and would need iteration. `frac_sno` changes
  within a step only when the snow disappears (`SnowHydrologyMod.F90`, two places).
- **History output is offset by one step.** At the same time stamp, `H2OSNO` = SWE(t_k)
  after melt, but `FSNO` = f(SWE(t_(k-1)) + newsnow_k). Python recalculations of fSCA
  from `H2OSNO` (sweep analysis) should use the previous step's `H2OSNO` plus new snow.

**Why deplete, then accumulate.**
- SL12 and CZ26 are hysteresis schemes: accumulation and depletion follow different
  curves, so fSCA isn't a function of SWE alone. They need the gross snowfall and the SWE
  loss separately; a net ΔSWE can't say which curve to follow (5 mm snow + 6 mm melt =
  -1 mm, which would lose the fresh cover).
- In ELM the two parts arrive separately: the melt (and sublimation, frost) since the last
  call is already in `h2osno`, and `newsnow` is this step's snowfall. Depleting first
  follows the order the events happened, because of the one-step lag.
- In reality melt and snowfall happen at the same time. Applying them one after the
  other is operator splitting (Lie): first-order, and it converges to the simultaneous
  rate equation as Δt → 0. The two orders differ only by cross terms of order M·P·Δt².
  The snow mass budget already treats them together (new snow goes into the top layer
  and that step's melt acts on it); only the area is split.
- With "one curve per step", accumulation started from a stale fSCA, and the
  `swe_max_eff` reset after accumulation (inverting the melt curve) made the missed
  depletion permanent: fSCA too high whenever snow fell on a pack that had lost SWE,
  common in spring.
- The depletion call does nothing when SWE hasn't changed since the last accumulation,
  because `swe_max_eff` was set by inverting the depletion curve there. So it doesn't
  need the `snowmelt > 0` condition that legacy uses.
- NY07, AR25 and GFDL depend only on the current state (column-mean depth with new snow,
  bulk density), so melt is already included; no change.
- Possible alternative: deplete at the end of the step (after `CombineSnowLayers`)
  with SWE(t_k). Accumulate-then-deplete within one step: no lag, and `FSNO` matches
  `H2OSNO` in history. It is no more accurate in splitting terms, and needs `dz` /
  `snow_depth` rescaling there too. Not done.

**Timestep dependence of the accumulation curves** (open, see Open issues). This
matters more than the melt/accumulation order. Accumulation is not linear in the new
snow, so splitting one storm over many steps changes the result. SL12 per step:
f → 1 - (1 - tanh(k·p))(1 - f).
- one update with the daily total P: fSCA = tanh(kP)
- many small steps with total P: fSCA = 1 - ∏(1 - tanh(k·p_i)) → 1 - exp(-kP)
- kP = 1 (10 mm with k = 0.1): 0.76 vs 0.63, so sub-daily steps give less cover.

CZ26 has the same problem, and it is worse: S(dSWE) and α were fitted together on daily
SWE increments, but are applied to each 30-min `newsnow`, so both the footprint and the
overlap act on much smaller increments than they were fitted to.

## Open issues

- **Accumulation curves depend on the model timestep** (SL12, CZ26). See
  [fSCA timing](#fsca-timing-within-the-elm-time-step-2026-11-25). Options: refit S and α
  at the model timestep, or accumulate `newsnow` over an event or a day and apply the
  accumulation once (needs a new state variable and an event-end rule). First, measure
  the size of the effect in the sweep.

- **Compaction uses legacy state.** `SnowHydrologyMod.F90` (`SnowCompaction`, melt
  compaction with `subgridflag == 1`) recomputes a melt fSCA from `int_snow` and
  `col_pp%n_melt`. For `SL12` and `CZ26` this doesn't match their own `swe_max_eff` and
  `n_melt`. To be handled outside this module.
- **Different `n_melt` floors.** SL12 uses `max(10, sigma)`, CZ26 `max(1, sigma)`. For
  sigma < 10 m CZ26's exponent goes up to 200 (very steep depletion). Decide whether this
  is intended.
- **NY07 depth meaning: resolved by the column-mean change** (uncommitted). NY07 now gets
  column-mean depth and the stored depth is over the snow-covered area, like the rest of
  ELM. (Background: [elm_code_architecture.md, section 6](elm_code_architecture.md#concern-fsca-parameterizations-use-column-mean-depth).)
  NY07 still differs from `master`'s `oldfflag = 1` NY07.
- **`FracH2OSfc` can lower `frac_sno` after the depth update** (end of CanopyHydrology,
  surface water cap) without rescaling depth, so the column-mean depth drops a little.
  Same function file; could rescale there too.
- **Glacier and wetland columns:** `subgrid_snow` is true for them (only urban is
  excluded), but `frac_sno_eff = 1` there. Pre-existing ELM inconsistency, unchanged.
- **CZ26 can set fSCA to 0 while snow remains** (e.g. after the Aug 1 / Feb 1 reset of
  `swe_max_eff` on a perennial pack). The depth update then keeps the pack geometry as it
  is (before, the stored depth was set to 0 and the top layer `dz` could go negative). The
  energy balance sees no snow cover while snow exists; decide what CZ26 should do.
- **`subgridflag = 0` is not a way to get uniform depth.** It also sets `frac_sno_eff = 1`
  (energy balance as fully snow covered), and needs `h2osfcflag = 0` (deprecated;
  build-namelist's check misses it when `h2osfcflag` isn't set, because the Fortran
  default is 1).
- **CZ26 season reset** of `swe_max_eff` is done in CanopyHydrology. Could move into the
  module.
- **Helbig21** is disabled. To re-enable, call it from `UpdateSnowCoverFraction` and pass
  the `col_ws%helbig_*` state.
- **elm_code_architecture.md sections 4–6** describe the code before `2f00a8dd4a`
  (melt-then-accumulate for SL12, `update_snow_depth_from_fsca`, old line numbers). Update
  them.

## Log

- **2026-11-25** (uncommitted) SL12 and CZ26 deplete to the current SWE before
  accumulating on snowfall steps (`UpdateSnowCoverFraction`). Replaced
  `test_SL12_one_curve_per_step` with `test_SL12_deplete_then_accumulate` and
  `test_CZ26_deplete_then_accumulate`; `test_SL12_n_melt_from_sigma` reference updated
  to two calls. Unit tests 22/22. Added the fSCA timing section and the timestep
  dependence issue. Not yet built on Perlmutter.
- **2026-11-06** (uncommitted) Column-mean snow depth bookkeeping for all non-legacy
  schemes. Layer `dz`, `z`, `zi` rescaled when fSCA changes. Unit tests 16/16.
- **2026-11-06** Regression on Perlmutter: `2f00a8dd4a` `SL12_legacy` identical to
  `edcbdcd34c`.
- **2026-11-06** Simplified the scheme interface (`2f00a8dd4a`). Moved snow depth out of
  the schemes (`UpdateSnowDepthNewSnow`), made SL12 one curve per step, moved the legacy
  two-call sequence into CanopyHydrology, made NY07 take depth as input. Updated unit
  tests (15 pass).
- **2026-10-30** Moved all schemes into `SnowCoverFractionMod` (`fe85f116b9`).
