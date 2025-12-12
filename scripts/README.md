# PES Scripts

R is easiest to work with in Rstudio. Opening the .Rproj opens an Rstudio instance with this dir set at the working directory and let's you run each script by either `source` or line by line.

# Surrogate Modeling Input Data
The epidemic surrogate models take in the model `.json` specifying all the parameters and the output files in `../Surrogate_Sims/` to train. The surrogate model scripts generate many different scenarios ideal for training, testing, and validating models built for each state.

## Scenarios
### Vary Initial Infected
* Increase initial people infected within a single county.
    * Train & Test: 1, 3, 4, 5, 6, 7, 9, 10
    * Validate: 2, 8
    * These differ per state based on their initial infected per 1M state population
* Distribute initial people infected across the state by population flow.
    * Train & Test: 0.001%, 0.005%, 0.01% state population per 1% of counties with highest node centrality, equally distributed as possible
    * Validate: 0.0025%, 0.0075% state population in same counties

### Increase R0
* H1N1 parameterized SEIHRD model with 1 init inf in county with highest node centrality
    * Train & Test: R0 = 0.5, 1.0, 1.5, 2.0, 3.0, 4.0
    * Validate: R0 = 0.75, 1.25, 2.2, 3.5



