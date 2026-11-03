# ELM code architecture: a reading guide for the snow code

How ELM is organized, and where the snow / fractional snow cover (fSCA) code sits in it.
Paths are relative to the E3SM root (`../E3SM`). Line numbers are from the local `fsca`
branch (which has `SnowCoverFractionMod.F90` with the `snow_fsca_param` options) and will
drift. Other branches (`master`, `origin/ez/fsca`) organize the snow cover code
differently, so re-check there.

> **⚠ Open issue (to discuss with colleagues, no code changed):** the depth-based fSCA
> scheme `NY07`/`AR25` on the `fsca` branch appears to store a column-mean snow depth in
> `snow_depth`, which the rest of ELM treats as depth over the snow-covered area. Found by
> reading the code; not yet confirmed in a run. See
> [section 6, "Concern"](#concern-fsca-parameterizations-use-column-mean-depth).

## 1. The subgrid hierarchy

ELM inherited CLM4.5's nested subgrid structure and added a **topounit** level:

```
gridcell                 (g)  atmospheric forcing arrives here; history output is averaged to here
 └─ topounit             (t)  ELM-only: topographic subunits (Tesfa & Leung 2017, GMD)
     └─ landunit         (l)  vegetated (soil), crop, urban, lake, glacier, wetland
         └─ column       (c)  snow, soil, and surface water state
             └─ patch    (p)  PFT: vegetation and canopy state (called "veg" in ELM code)
```

Rule of thumb:
- **Snow and soil state live on columns.** `frac_sno`, `h2osno`, `snow_depth`, `snl`,
  and the snow layer arrays are column variables.
- **Canopy and vegetation state live on patches.** For example, canopy interception and
  LAI/SAI.
- **Forcing lives on the gridcell or topounit.** Columns look up the parent's value
  through index maps.

Each column covers a fraction of its gridcell (`col_pp%wtgcell`). Gridcell-level output
is an area-weighted average over columns.

## 2. Code idioms

| Idiom | Meaning |
|---|---|
| `do fc = 1, num_nolakec; c = filter_nolakec(fc)` | Loop over a **filter**: a precomputed list of column indices meeting a condition (non-lake, snow-covered, ...). Defined in `main/filterMod.F90`. |
| Loop index `c` / `p` / `g` / `t` / `l` | Tells you which level the routine works at |
| `col_pp%gridcell(c)`, `col_pp%topounit(c)`, `col_pp%landunit(c)` | Go *up* from a column to its parent |
| `veg_pp%column(p)` | Go from a patch to its column |
| `associate(frac_sno => col_ws%frac_sno, ...)` | Local alias only. The real data is in the derived type. |
| `bounds%begc : bounds%endc` | Index range of columns this process/clump owns (`main/decompMod.F90`) |
| `col_pp` / `col_ws` / `col_es` / `col_wf` / `col_ef` | Column physical properties / water state / energy state / water flux / energy flux |
| `veg_pp`, `veg_ws`, ... ; `grc_pp`, ... ; `top_pp`, `top_as` ... | Same pattern for patch, gridcell, and topounit (`top_as` = atmospheric state on topounits) |

## 3. Where things are defined

All under `components/elm/src/`:

| To understand... | Read |
|---|---|
| Timestep call sequence and parallelization ("clumps" of gridcells per MPI rank, looped with OpenMP) | `main/elm_driver.F90` (header comment lines 3–8, then `elm_drv`) |
| What exists at each level (index maps, weights, types) | `data_types/GridcellType.F90`, `TopounitType.F90`, `LandunitType.F90`, `ColumnType.F90`, `VegetationType.F90` |
| State/flux variables at each level | `data_types/ColumnDataType.F90` (e.g. `frac_sno` declared line 160, allocated `begc:endc`), `VegetationDataType.F90`, `GridcellDataType.F90`, `TopounitDataType.F90` |
| How the hierarchy is built from the surface dataset | `main/initGridCellsMod.F90`, `initSubgridMod.F90`, `subgridMod.F90`, `surfrdMod.F90` |
| Averaging up the hierarchy (`p2c`, `c2l`, `c2g`, `c2t`, `t2g`, ...) | `main/subgridAveMod.F90` |
| Filters | `main/filterMod.F90` |
| Namelist → Fortran control variables | `main/controlMod.F90`, `main/elm_varctl.F90` |

## 4. Snow code path (one timestep, simplified)

From `main/elm_driver.F90`:

1. **`CanopyHydrology`** (driver line ~705) → `biogeophys/CanopyHydrologyMod.F90`
   - Partitions precipitation into canopy interception and throughfall (patch level),
     then rain and snow reaching the ground (column level).
   - Updates fSCA: loops over non-lake columns and calls `UpdateSnowCoverFraction`
     (line ~557) from **`biogeophys/SnowCoverFractionMod.F90`**. The scheme is chosen
     with `snow_fsca_param` (default `SL12`, Swenson & Lawrence 2012). This is the main
     place to look for fSCA work.
   - Then `FracH2oSfc` (line ~645), which can change `frac_sno` via the surface water fraction.
2. **Surface energy fluxes / temperatures** (`CanopyTemperature`, `CanopyFluxes`,
   `SoilTemperatureMod`, ...). Snow and bare-ground fluxes are weighted by `frac_sno`.
3. **`HydrologyNoDrainage`** (driver line ~902) → `biogeophys/HydrologyNoDrainageMod.F90`
   - `SnowWater`, `SnowCompaction`, `CombineSnowLayers`, `DivideSnowLayers`
     (in `biogeophys/SnowHydrologyMod.F90`). These work on snow-covered columns (`filter_snowc`).
4. **`SurfaceAlbedo`** (driver line ~1373) → `biogeophys/SurfaceAlbedoMod.F90`
   - Calls `SNICAR_RT` (`biogeophys/SnowSnicarMod.F90`) for snow albedo/absorption by layer.
   - Ground albedo blends snow and bare-soil albedo using `frac_sno`.
   - Computed at the end of a step, for use in the next step's radiation.

## 5. When fSCA is updated within a timestep

ELM updates state one process at a time. Each process reads the state as it stands, updates
it, and passes it on; nothing is recalculated at the end of the step. So "first thing in
step n+1" is the same point in time as "last thing in step n", except that step n+1's
snowfall is also known.

### Step n+1, in the order the code runs

Start of step n+1. Stored state: **SWE_n**, **fSCA_n**.

1. **`CanopyHydrology` → `UpdateSnowCoverFraction`** (`CanopyHydrologyMod.F90:540–570`)
   - **Melt:** if snow melted in step n (`snowmelt = qflx_snow_melt*dtime > 0`, commented
     "snowmelt from previous time step"), fSCA is recalculated from the melt curve using
     `swe = h2osno = SWE_n`. This brings fSCA up to date with SWE_n.
   - **Snowfall:** if snow falls in step n+1 (`newsnow > 0`), fSCA is increased.
   - The result is **fSCA\***. Only after this is new snow added: `h2osno = SWE_n + newsnow`.
     Snow depth for the new snow is spread over fSCA\*
     (`update_snow_depth_from_fsca`: `newsnow/(bifall*frac_sno)`).
2. **Energy balance, snow layers, soil** (`CanopyTemperature`, `CanopyFluxes`, `SoilFluxes`,
   `SoilTemperature`, `HydrologyNoDrainage`) all use **fSCA\*** (via `frac_sno_eff`).
3. **Melt and sublimation** in step n+1 reduce SWE to **SWE_{n+1}**. fSCA is *not*
   changed in response; it stays at fSCA\*. Exceptions: `FracH2oSfc` caps it at
   `1 - frac_h2osfc` (`CanopyHydrologyMod.F90:823–831`), and `SnowHydrologyMod.F90:475`,
   `:1024` set it to 0 when the snow is completely gone.
4. **`SurfaceAlbedo`** uses fSCA\* to compute the albedo for step n+2's radiation.

End of step n+1. Stored state: **SWE_{n+1}**, **fSCA_{n+1} = fSCA\***.

```
          stored at end of n            start of n+1                     end of n+1
          ──────────────────     ───────────────────────────     ──────────────────────
SWE:      SWE_n  ──────────────────────────► +newsnow ──► −melt_{n+1} ──►  SWE_{n+1}
fSCA:     fSCA_n ──► deplete(SWE_n, melt_n) ──► +newsnow ═► fSCA* ═══════► fSCA_{n+1} = fSCA*
                                                            ║
                                         used by all fluxes in step n+1
```

### Summary

| | Depends on |
|---|---|
| fSCA used by all fluxes in step n+1 (fSCA\*) | SWE_n, melt in step n, snowfall in step n+1 |
| SWE_{n+1} | SWE_n + snowfall in step n+1 − melt in step n+1 |
| fSCA stored at end of step n+1 | same as fSCA\*: does **not** yet reflect melt in step n+1 |

Consequences:
- **Fluxes use the right snow cover for the start of the step.** fSCA\* matches SWE_n and
  includes the new snow, which is the snow present while the step's fluxes are calculated.
- **The stored/output pair (SWE_{n+1}, fSCA_{n+1}) is off by one step of melt.** fSCA catches
  up at the start of step n+2, so `FSNO` can lag `H2OSNO` by one timestep during melt.
  With 30-minute steps this is small, but keep it in mind when comparing to observations.
- **SL12 depends on snow history, not just current SWE.** `frac_sno` and `swe_max_eff` carry
  over between steps: snowfall increases fSCA from its previous value, and the melt curve
  is applied only when `snowmelt > 0`, relative to `swe_max_eff` (reset after each snowfall).
  This is why fSCA is updated in increments at one fixed point in the step.
- **A new scheme that depends only on current SWE or depth** and is calculated from `h2osno`
  at this point is effectively an end-of-previous-step calculation. It still has to account
  for `newsnow`, since new snow is added to `h2osno` only after the call.

## 6. What snow depth means: snow-covered area vs. column mean

With subgrid snow cover on (`subgridflag = 1`, the default, `main/elm_varctl.F90:203`),
ELM's snow **mass** and snow **depth** are measured over different areas:

| Quantity | Measured over | Where |
|---|---|---|
| `h2osno`, `h2osoi_ice(c,j)`, `h2osoi_liq(c,j)` (kg/m² = mm) | whole column | |
| `snow_depth`, layer thicknesses `dz(c,j)` (m) | **snow-covered fraction only** | history `SNOW_DEPTH`: "snow height of snow covered area" (`ColumnDataType.F90:1666`) |
| `snowdp = snow_depth * frac_sno_eff` (m) | whole column | `HydrologyNoDrainageMod.F90:377`; history `SNOWDP`: "gridcell mean snow height" (`ColumnDataType.F90:1671`) |

So density and layer depth always put fSCA back in:
- Layer density: `h2osoi_ice/(frac_sno*dz)` (`SnowHydrologyMod.F90:662`, compaction), and
  `vol_ice = h2osoi_ice/(dz*frac_sno_eff*denice)` (`:279`).
- Thin-snow / low-density removal: `frac_sno_eff*snow_depth < 0.01` or
  `h2osno/(frac_sno_eff*snow_depth) < 50 kg/m³` (`SnowHydrologyMod.F90:991–992`; similarly
  `:1049–1050` per layer).
- New snow layer starts when `frac_sno*snow_depth >= 0.01` (`CanopyHydrologyMod.F90:598`).
- SNICAR uses `frac_sno*dz` as the layer depth (`SnowSnicarMod.F90:1325`).
- The layer temperature and compaction physics act on the snowpack in the snow-covered patch.

### How new snow is added to depth

New-snow density is still used: `bifall` (kg/m³), from Anderson (1976) as a function of
air temperature (`CanopyHydrologyMod.F90:527–535`). fSCA converts the column-mean snowfall
into depth over the snow-covered area (`update_snow_depth_from_fsca`,
`SnowCoverFractionMod.F90:692`, used by SL12 and CZ26):

```fortran
snow_depth = snow_depth + newsnow/(bifall*frac_sno)
!            newsnow/bifall  : depth if spread evenly over the whole column (uses density)
!            /frac_sno       : put it all on the snow-covered area
```

Details:
- `frac_sno` here has already been increased for this step's snowfall, so new snow is
  spread over the post-snowfall fSCA.
- The existing `snow_depth` is not rescaled when fSCA grows. The old snow is effectively
  assumed to cover the larger area at the same depth, so the implied density
  `h2osno/(frac_sno*snow_depth)` can jump when fSCA changes quickly. How much this matters
  hasn't been checked.
- After layers form, `snow_depth` is recalculated as `sum(dz)` (`SnowHydrologyMod.F90:976`),
  so these depths are carried through compaction and layer combining.
- A 2015 comment flags a related inconsistency: "in CanopyHydrologyMod, snow_depth is scaled
  with frac_sno. Here we do not apply scaling to snow_depth, so inconsistent? TODO"
  (`SnowHydrologyMod.F90:2178`, in the snow layer initialization).

### Concern: fSCA parameterizations use column-mean depth

Depth-based fSCA parameterizations (Niu & Yang 2007, Abolafia-Rosenzweig et al. 2025, and
similar) are fitted to **mean snow depth over a region or grid cell**, including the
snow-free parts. In ELM that quantity is `snowdp` (`= snow_depth*frac_sno`), *not*
`snow_depth`.

**NY07/AR25 on the `fsca` branch** (`fsca_NY07_update`, `SnowCoverFractionMod.F90:207`):
- It adds new snow as `snow_depth + newsnow/bifall` (no division by fSCA; the comment says
  "assuming uniform snow cover"), then computes `fSCA = tanh(snow_depth/...)` and
  `rho_bulk = (swe+newsnow)/snow_depth`. Inside the routine, `snow_depth` is treated as a
  column mean, which matches how the parameterization was fitted.
- But it is stored in the same `snow_depth` variable that the rest of ELM treats as depth
  over the snow-covered area. From reading the code (not tested), when fSCA < 1:
  - layer densities `h2osoi_ice/(frac_sno*dz)` come out too high by a factor of 1/fSCA
    compared with the routine's own `rho_bulk`, and the `< 50 kg/m³` removal checks don't
    match what the routine assumes;
  - `SNOWDP = snow_depth*frac_sno` under-counts the mean depth by a factor of fSCA;
  - on the next step, NY07 reads back a `snow_depth` that compaction and layer combining
    (`sum(dz)`) have updated as if it were depth over the snow-covered area.
- **SL12** avoids this because it computes fSCA from SWE and snowfall, not depth, and then
  puts depth over the snow-covered area. **CZ26** does the same (it calls
  `update_snow_depth_from_fsca`).

**Status: open, pending discussion with colleagues. No code has been changed.**

Possible ways to make a depth-based scheme consistent (not decided, not tried):
1. Inside the routine, work in column-mean depth (`hs_mean = snow_depth*frac_sno` coming
   in), compute fSCA from `hs_mean`, then store `snow_depth = hs_mean/frac_sno` on the way
   out. This keeps the rest of ELM's meaning unchanged.
2. Compare `SNOWDP` (not `SNOW_DEPTH`) with observed mean depth, and run with
   `hist_dov2xy = .false.` to check `SNOW_DEPTH`, `SNOWDP`, `FSNO`, `H2OSNO` per column for
   implied densities outside ~50–550 kg/m³.

## 7. Checking subgrid behavior in output

History files average to the gridcell by default. To see column- or patch-level values
(e.g. `FSNO` per column), set this in `user_nl_elm`:

```fortran
hist_dov2xy = .false.   ! write 1-D (column/patch) output instead of gridcell averages
```

It is set per history tape, so it can be a list, e.g. `.true., .false.` with a second tape
that uses `hist_type1d_pertape`. See `components/elm/bld/namelist_files/namelist_definition.xml`.

## 8. Further reading

- **CLM4.5 Technical Note** (Oleson et al. 2013, NCAR/TN-503+STR), §1.2 "Surface
  Heterogeneity and Data Structure" (Fig. 1.2 shows the hierarchy) and Ch. 7 (snow
  hydrology, fSCA). It's the closest reference for ELM, which was forked from CLM4.5
  around 2014.
- **CLM5 Technical Note**, "Surface Heterogeneity": a newer write-up of the same idea.
  Use it for concepts only; CLM5's snow physics and names differ from ELM's.
- **Tesfa & Leung (2017), GMD**: topounits.
- **Golaz et al. (2019), JAMES**: E3SM v1 overview, with a short ELM description.
- Local ELM docs (`components/elm/docs/`) cover radiation and TOP physics, but not
  code architecture.
