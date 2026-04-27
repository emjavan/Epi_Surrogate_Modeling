# Epidemic Surrogate Modeling
TACC [Pandemic Exercise Simulator](https://github.com/TACC/PandemicExerciseSimulator/) code used to generate data for training surrogate models. Each state was chosen to represent a range of nodes/counties in the network. Epidemics do not cross state boundaries and are based on a single set of initial exposures leading to influenza-like infections. We chose the simplest model, SEIR, because it's A) less computationally intensive and B) without interventions (e.g. vaccinations and antivirals) we don't need to track the reduction in hospitalizations and deaths.

---

## Parameter Sweep Summary

- **States & County Networks**:
  - **District of Columbia** — 1 county-equivalent (Washington, DC)
  - **New Jersey** — 21 counties
  - **North Dakota** — 53 counties
  - **Wisconsin** — 72 counties
  - **North Carolina** — 100 counties
- **Transmission $R_0$**: 0.5 to 5.0 (step size 0.5)
- **Initial Infected Population**: 1, 10, 100, 1,000 individuals
- **Simulation Duration**: 500 days per run
- **Simulations per scenario**: 100
- **Spatial Structure**: each combination of top 5 most populous counties within each state seeded, except for DC
**Total Scenarios**: 5,000
  - 125 county-set configurations × 10 $R_0$ × 4 initial infected values
  - County sets are generated as unordered combinations
  - District of Columbia contributes only 1 county set
  - Each of the other 4 states contribute all non-empty subsets of its top 5 most populous counties:
    - C(5,1) + C(5,2) + C(5,3) + C(5,4) + C(5,5) = 31 county sets per state
    - 4 states × 31 = 124 county sets
  - Total county sets: 124 + 1 = 125
  - Total scenarios: 125 × 10 × 4 = 5,000

---

## Set-up

1. Open the `scripts.Rproj` or command line to run the sweep script `SEIR_multi-county_sweep.R` in R to generate:
   - input_files/
   - <STATE>_commands.txt
   - <STATE>_launcher.sh
The files will be added to `SEIR-STOCH_Param_Sweep/`

2. Submit jobs per state inside `SEIR-STOCH_Param_Sweep/`:
`sbatch Texas_launcher.sh`

3. Process metadata & visualize with:
 - 7a_process_output_to_db.R
 - 7b_sim_dashboard_app.R

The app can be viewed on TACC with TAP:  `https://tap.tacc.utexas.edu/` or if needed moving files to local machine with `scp` or `rsync`.
