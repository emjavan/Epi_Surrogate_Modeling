# Epidemic Surrogate Modeling
TACC PES code used to generate data for training surrogate models.

Database wire diagrams of proposed PostgreSQL DB to link with a CKAN public data portal (work in progress), so we don't need so many subdirs of input/output data.

```mermaid
erDiagram
    direction LR

    SCENARIO ||--o{ INGEST_EVENT : has
    SCENARIO ||--o{ RUN : defines
    INGEST_EVENT ||--o{ RUN : loads
    RUN ||--o{ NETWORK_TS_LONG : produces
    RUN ||--o{ NODE_TS_LONG : produces
```


```mermaid
erDiagram
  SCENARIO ||--o{ INGEST_EVENT : has
  SCENARIO ||--o{ RUN : defines
  INGEST_EVENT ||--o{ RUN : loads
  RUN ||--o{ NETWORK_TS_LONG : produces
  RUN ||--o{ NODE_TS_LONG : produces

  SCENARIO {
    uuid scenario_id PK
    text scenario_hash "sha256 of identity payload"
    text state_fips
    jsonb config_json
    timestamptz created_at
  }

  INGEST_EVENT {
    uuid ingest_id PK
    uuid scenario_id FK
    text source_dir "unique dir path"
    timestamptz ingested_at
    text status
    text notes
  }

  RUN {
    uuid run_id PK
    uuid scenario_id FK
    uuid ingest_id FK
    int sim_id "stochastic realization id"
    int batch_num
    timestamptz started_at
    timestamptz finished_at
    text status
  }

  NETWORK_TS_LONG {
    uuid run_id FK
    int t
    text compartment
    text risk
    text vax
    text age_group
    double value
  }

  NODE_TS_LONG {
    uuid run_id FK
    text node_id "county fips"
    int t
    text compartment
    text risk
    text vax
    text age_group
    double value
  }
```
