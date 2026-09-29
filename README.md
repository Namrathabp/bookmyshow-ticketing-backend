# BookMyShow Ticketing Backend

A high-concurrency movie ticketing backend designed to prevent double-booking, support automated timed seat holds, process payment webhooks idempotently, and serve fast schedule queries.

---

## Project Overview & Tasks

* **P1 — Relational Schema & Concurrency Strategy**: Normalized database schema (1NF, 2NF, 3NF, BCNF) designed to handle race conditions during flash seat reservations.
* **P2 — Theater Schedule Query**: Date-filtered query retrieving all shows running at a specific theater with human-readable timings and screen formats matching the BookMyShow UI.

---

## Repository Layout

```text
.
├── docker-compose.yml
├── init-scripts/
│   ├── 01_schema_p1.sql      # Database DDL, indexes, and foreign keys
│   └── 02_seed_p1.sql        # Realistic sample data (theaters, screens, shows, seats)
├── queries/
│   └── queries_p2.sql        # P2 date-picker schedule queries (aggregated & tabular)
└── README.md
```

## Setup & Execution Guide
### Prerequisites
- WSL 2 (Ubuntu)
- Podman & podman-compose (or Docker & docker-compose)

### Step 1: Start Services
```
# Launch MySQL 8.0 and Redis containers
podman-compose up -d

# Verify container statuses
podman ps
```

### Step 2: Execute P2 Query
```
podman exec -i bms_mysql mysql -ubms_user -pbms_password bookmyshow < queries/queries_p2.sql
```

## Sample Output
<img width="1561" height="353" alt="image" src="https://github.com/user-attachments/assets/b0396a0a-6543-4adc-b1e8-2c7f8c169a58" />

