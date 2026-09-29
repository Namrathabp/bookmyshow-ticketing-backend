# High-Throughput Ticket Booking Backend (BookMyShow Scale)

This repository contains the architectural specification, database schema, concurrency controls, and operational queries for a BookMyShow-scale movie ticketing backend. The system is engineered to handle extreme booking spikes without lost holds or double-booked seats.

---

## 1. System Entities & Attributes

The data architecture strictly separates persistent theater infrastructure (theaters, auditoriums, physical seat blueprints) from ephemeral event inventory and booking state transitions.

### Core Entities

1. **`cities`**: Geographic partition.
   * `city_id` (INT, PK, Auto-Increment): Unique identifier for the city.
   * `name` (VARCHAR(100)): City name (e.g., Bengaluru).
   * `state` (VARCHAR(100)): State name (e.g., Karnataka).
   * `created_at` (TIMESTAMP): Record creation timestamp.

2. **`theaters`**: Physical movie house or multiplex venue.
   * `theater_id` (INT, PK, Auto-Increment): Unique theater identifier.
   * `city_id` (INT, FK -> `cities.city_id`): Parent city reference.
   * `name` (VARCHAR(150)): Commercial name of the multiplex.
   * `address` (VARCHAR(255)): Street address.
   * `created_at` (TIMESTAMP): Record creation timestamp.

3. **`screens`**: Individual auditorium inside a theater.
   * `screen_id` (INT, PK, Auto-Increment): Unique screen identifier.
   * `theater_id` (INT, FK -> `theaters.theater_id`): Host theater reference.
   * `screen_name` (VARCHAR(50)): Identifier within venue (e.g., Audi 1 IMAX).
   * `sound_type` (VARCHAR(50)): Audio spec (e.g., Dolby Atmos 7.1).
   * `display_type` (VARCHAR(50)): Projection spec (e.g., 4K Laser IMAX).

4. **`seats`**: Immutable physical seat blueprint for a screen.
   * `seat_id` (INT, PK, Auto-Increment): Unique physical seat layout record.
   * `screen_id` (INT, FK -> `screens.screen_id`): Screen location.
   * `seat_row` (CHAR(2)): Row designator (e.g., A, B, AA).
   * `seat_number` (INT): Seat position along the row.
   * `seat_tier` (ENUM('NORMAL', 'EXECUTIVE', 'VIP')): Base tier categorization.
   * *Constraint*: Composite Unique `(screen_id, seat_row, seat_number)` prevents blueprint collisions.

5. **`movies`**: Canonical motion picture metadata.
   * `movie_id` (INT, PK, Auto-Increment): Unique movie identifier.
   * `title` (VARCHAR(200)): Movie title.
   * `duration_minutes` (INT): Duration in minutes.
   * `language` (VARCHAR(50)): Audio language.
   * `certificate` (VARCHAR(10)): Film certification rating (e.g., U, UA, A).
   * `release_date` (DATE): Theatrical release date.
   * `created_at` (TIMESTAMP): Record creation timestamp.

6. **`shows`**: Scheduled runtime slot combining a movie and an auditorium.
   * `show_id` (BIGINT, PK, Auto-Increment): Unique show instance.
   * `screen_id` (INT, FK -> `screens.screen_id`): Auditorium assigned.
   * `movie_id` (INT, FK -> `movies.movie_id`): Movie being exhibited.
   * `start_time` (DATETIME): Scheduled commencement timestamp.
   * `end_time` (DATETIME): Estimated conclusion timestamp.
   * `base_price` (DECIMAL(10, 2)): Baseline show admission cost.
   * `created_at` (TIMESTAMP): Record creation timestamp.

7. **`bookings`**: Order record managing user reservation state.
   * `booking_id` (BIGINT, PK, Auto-Increment): Unique reservation identifier.
   * `user_id` (BIGINT): User account identifier.
   * `show_id` (BIGINT, FK -> `shows.show_id`): Targeted show.
   * `total_amount` (DECIMAL(10, 2)): Final price charged.
   * `status` (ENUM('PENDING', 'CONFIRMED', 'CANCELLED', 'EXPIRED')): Order lifecycle state.
   * `expires_at` (DATETIME): Absolute deadline for payment before release.
   * `created_at` (TIMESTAMP): Booking initiation time.
   * `updated_at` (TIMESTAMP): Automatic audit timestamp.

8. **`show_seat_inventory`**: Real-time state machine per seat for a given show.
   * `inventory_id` (BIGINT, PK, Auto-Increment): Unique seat-state record.
   * `show_id` (BIGINT, FK -> `shows.show_id`): Active show reference.
   * `seat_id` (INT, FK -> `seats.seat_id`): Physical seat reference.
   * `booking_id` (BIGINT, FK -> `bookings.booking_id`, Nullable): Linked pending or confirmed order.
   * `status` (ENUM('AVAILABLE', 'LOCKED', 'BOOKED')): Concurrency control state.
   * `locked_until` (DATETIME, Nullable): Seat hold expiry deadline.
   * `price` (DECIMAL(10, 2)): Dynamic seat-specific price.
   * `version` (INT): Monotonic counter for optimistic locking.
   * `updated_at` (TIMESTAMP): Last state-transition timestamp.
   * *Constraint*: Composite Unique `(show_id, seat_id)` prevents multi-instantiation.

9. **`payments`**: Transaction log with idempotency controls for webhook ingestion.
   * `payment_id` (BIGINT, PK, Auto-Increment): Internal payment record.
   * `booking_id` (BIGINT, FK -> `bookings.booking_id`): Associated reservation.
   * `idempotency_key` (VARCHAR(128), UNIQUE): Unique provider token preventing duplicate execution.
   * `gateway_transaction_id` (VARCHAR(128), Nullable): External PG identifier.
   * `amount` (DECIMAL(10, 2)): Amount processed.
   * `status` (ENUM('INITIATED', 'SUCCESS', 'FAILED')): Transaction state.
   * `created_at` (TIMESTAMP): Transaction event timestamp.

---

## 2. Normalization Analysis (1NF through BCNF)

* **First Normal Form (1NF)**: All attributes contain strictly atomic scalar values. There are no repeating groups, comma-separated lists of seats, or unparsed JSON columns storing relational keys. Primary keys are explicitly defined on every table.
* **Second Normal Form (2NF)**: All tables use surrogate single-column primary keys. Any composite business keys (e.g., `screens(screen_id, seat_row, seat_number)` and `show_seat_inventory(show_id, seat_id)`) are bound by explicit unique constraints where all non-key attributes depend fully on the complete key. No partial dependencies exist.
* **Third Normal Form (3NF)**: Transitive dependencies are removed. For instance, `shows` does not store `theater_id` or `city_id`; it strictly references `screen_id`, and `screen_id` links to `theater_id`. Movie metadata (duration, title) is not duplicated in `shows`.
* **Boyce-Codd Normal Form (BCNF)**: For every non-trivial functional dependency $X \rightarrow Y$, the determinant $X$ is a superkey. There are no overlapping candidate keys with cross-dependent non-prime attributes.

---

## 3. Concurrency & High-Throughput Strategy

Handling high concurrency during blockbuster releases requires multi-layered race protection:

```
[User Request] 
      │
      ▼
[Redis Distributed Lock] ──(Lock Failed / Held)──> 409 Conflict: Seat Currently Held
      │
      ▼ (Lock Acquired: SET seat_lock:<show>:<seat> NX EX 600)
[MySQL Conditional Row Update]
      │
      ├─> UPDATE show_seat_inventory 
      │   SET status = 'LOCKED', locked_until = DATE_ADD(NOW(), INTERVAL 10 MINUTE), version = version + 1
      │   WHERE show_id = ? AND seat_id IN (?, ?) AND status = 'AVAILABLE';
      │
      ├─(Affected Rows == Requested Count)──> Proceed to Booking Creation
      └─(Affected Rows != Requested Count)──> Rollback & Release Redis Lock
```

1. **Atomic Guardrails**:
   * The unique constraint `uq_show_seat` on `(show_id, seat_id)` prevents the physical duplication of seat records per show.
   * Atomicity during state transitions is enforced by evaluating the seat's current status inside the update condition:
     ```sql
     UPDATE show_seat_inventory 
     SET status = 'LOCKED', 
         booking_id = ?, 
         locked_until = DATE_ADD(NOW(), INTERVAL 10 MINUTE),
         version = version + 1
     WHERE show_id = ? AND seat_id = ? AND status = 'AVAILABLE';
     ```
2. **Automated Hold Expiration**:
   * An asynchronous background worker reconciles timed-out holds every 15–30 seconds:
     ```sql
     UPDATE show_seat_inventory
     SET status = 'AVAILABLE', locked_until = NULL, booking_id = NULL
     WHERE status = 'LOCKED' AND locked_until < NOW();
     ```
3. **Idempotent Webhook Processing**:
   * The `payments` table features a strict unique constraint on `idempotency_key`. Payment providers retrying webhooks under high network latency hit `ON DUPLICATE KEY UPDATE` or return HTTP 200 without executing duplicate inventory confirmations.

---

## 4. P1: Database DDL & Seed Data (MySQL 8.0+)

The following SQL script is directly executable on any MySQL 8.0+ instance.

```sql
-- ============================================================================
-- BOOKMYSHOW DATABASE SCHEMA DEFINITION & SEED DATA
-- Target DBMS: MySQL 8.0+
-- ============================================================================

SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS show_seat_inventory;
DROP TABLE IF EXISTS bookings;
DROP TABLE IF EXISTS seats;
DROP TABLE IF EXISTS shows;
DROP TABLE IF EXISTS screens;
DROP TABLE IF EXISTS theaters;
DROP TABLE IF EXISTS movies;
DROP TABLE IF EXISTS cities;

SET FOREIGN_KEY_CHECKS = 1;

-- 1. Cities Table
CREATE TABLE cities (
    city_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    state VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 2. Theaters Table
CREATE TABLE theaters (
    theater_id INT AUTO_INCREMENT PRIMARY KEY,
    city_id INT NOT NULL,
    name VARCHAR(150) NOT NULL,
    address VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_theaters_city FOREIGN KEY (city_id) REFERENCES cities (city_id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 3. Screens Table
CREATE TABLE screens (
    screen_id INT AUTO_INCREMENT PRIMARY KEY,
    theater_id INT NOT NULL,
    screen_name VARCHAR(50) NOT NULL,
    sound_type VARCHAR(50) DEFAULT 'Dolby Atmos 7.1',
    display_type VARCHAR(50) DEFAULT '4K Laser',
    CONSTRAINT fk_screens_theater FOREIGN KEY (theater_id) REFERENCES theaters (theater_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 4. Seats Table (Auditorium layout blueprints)
CREATE TABLE seats (
    seat_id INT AUTO_INCREMENT PRIMARY KEY,
    screen_id INT NOT NULL,
    seat_row CHAR(2) NOT NULL,
    seat_number INT NOT NULL,
    seat_tier ENUM('NORMAL', 'EXECUTIVE', 'VIP') DEFAULT 'NORMAL',
    CONSTRAINT fk_seats_screen FOREIGN KEY (screen_id) REFERENCES screens (screen_id) ON DELETE CASCADE,
    CONSTRAINT uq_screen_seat UNIQUE (screen_id, seat_row, seat_number)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 5. Movies Table
CREATE TABLE movies (
    movie_id INT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(200) NOT NULL,
    duration_minutes INT NOT NULL,
    language VARCHAR(50) NOT NULL,
    certificate VARCHAR(10) DEFAULT 'UA',
    release_date DATE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 6. Shows Table
CREATE TABLE shows (
    show_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    screen_id INT NOT NULL,
    movie_id INT NOT NULL,
    start_time DATETIME NOT NULL,
    end_time DATETIME NOT NULL,
    base_price DECIMAL(10, 2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_shows_screen FOREIGN KEY (screen_id) REFERENCES screens (screen_id) ON DELETE RESTRICT,
    CONSTRAINT fk_shows_movie FOREIGN KEY (movie_id) REFERENCES movies (movie_id) ON DELETE RESTRICT,
    INDEX idx_screen_time (screen_id, start_time),
    INDEX idx_movie_time (movie_id, start_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 7. Bookings Table
CREATE TABLE bookings (
    booking_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    show_id BIGINT NOT NULL,
    total_amount DECIMAL(10, 2) NOT NULL,
    status ENUM('PENDING', 'CONFIRMED', 'CANCELLED', 'EXPIRED') DEFAULT 'PENDING',
    expires_at DATETIME NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_bookings_show FOREIGN KEY (show_id) REFERENCES shows (show_id) ON DELETE RESTRICT,
    INDEX idx_user_bookings (user_id),
    INDEX idx_status_expires (status, expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 8. Show Seat Inventory Table
CREATE TABLE show_seat_inventory (
    inventory_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    show_id BIGINT NOT NULL,
    seat_id INT NOT NULL,
    booking_id BIGINT NULL,
    status ENUM('AVAILABLE', 'LOCKED', 'BOOKED') NOT NULL DEFAULT 'AVAILABLE',
    locked_until DATETIME NULL,
    price DECIMAL(10, 2) NOT NULL,
    version INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_ssi_show FOREIGN KEY (show_id) REFERENCES shows (show_id) ON DELETE CASCADE,
    CONSTRAINT fk_ssi_seat FOREIGN KEY (seat_id) REFERENCES seats (seat_id) ON DELETE RESTRICT,
    CONSTRAINT fk_ssi_booking FOREIGN KEY (booking_id) REFERENCES bookings (booking_id) ON DELETE SET NULL,
    CONSTRAINT uq_show_seat UNIQUE (show_id, seat_id),
    INDEX idx_show_status (show_id, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 9. Payments Table
CREATE TABLE payments (
    payment_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    booking_id BIGINT NOT NULL,
    idempotency_key VARCHAR(128) NOT NULL,
    gateway_transaction_id VARCHAR(128) NULL,
    amount DECIMAL(10, 2) NOT NULL,
    status ENUM('INITIATED', 'SUCCESS', 'FAILED') NOT NULL DEFAULT 'INITIATED',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_payments_booking FOREIGN KEY (booking_id) REFERENCES bookings (booking_id) ON DELETE RESTRICT,
    CONSTRAINT uq_idempotency_key UNIQUE (idempotency_key),
    INDEX idx_gateway_tx (gateway_transaction_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- SEED DATA INSERTION
-- ============================================================================

INSERT INTO cities (city_id, name, state) VALUES 
(1, 'Bengaluru', 'Karnataka');

INSERT INTO theaters (theater_id, city_id, name, address) VALUES 
(101, 1, 'PVR: Forum Mall, Koramangala', 'Hosur Road, Koramangala, Bengaluru');

INSERT INTO screens (screen_id, theater_id, screen_name, sound_type, display_type) VALUES 
(1001, 101, 'Audi 1 (IMAX)', 'Dolby Atmos', 'IMAX Laser'),
(1002, 101, 'Audi 2', 'Dolby Digital 7.1', '4K Digital');

INSERT INTO seats (seat_id, screen_id, seat_row, seat_number, seat_tier) VALUES 
(1, 1001, 'A', 1, 'NORMAL'),
(2, 1001, 'A', 2, 'NORMAL'),
(3, 1001, 'B', 1, 'EXECUTIVE'),
(4, 1001, 'B', 2, 'EXECUTIVE'),
(5, 1001, 'C', 1, 'VIP');

INSERT INTO movies (movie_id, title, duration_minutes, language, certificate, release_date) VALUES 
(501, 'Dune: Part Two', 166, 'English', 'UA', '2026-03-01'),
(502, 'Kantara: A Legend Chapter-1', 150, 'Kannada', 'UA', '2026-10-02');

INSERT INTO shows (show_id, screen_id, movie_id, start_time, end_time, base_price) VALUES 
(2001, 1001, 501, '2026-10-05 10:00:00', '2026-10-05 12:46:00', 350.00),
(2002, 1001, 501, '2026-10-05 14:00:00', '2026-10-05 16:46:00', 400.00),
(2003, 1001, 501, '2026-10-05 18:30:00', '2026-10-05 21:16:00', 450.00),
(2004, 1002, 502, '2026-10-05 11:30:00', '2026-10-05 14:00:00', 250.00),
(2005, 1002, 502, '2026-10-05 16:00:00', '2026-10-05 18:30:00', 250.00);

INSERT INTO show_seat_inventory (inventory_id, show_id, seat_id, booking_id, status, locked_until, price, version) VALUES 
(1, 2001, 1, NULL, 'AVAILABLE', NULL, 350.00, 0),
(2, 2001, 2, NULL, 'AVAILABLE', NULL, 350.00, 0),
(3, 2001, 3, NULL, 'AVAILABLE', NULL, 420.00, 0),
(4, 2001, 4, NULL, 'AVAILABLE', NULL, 420.00, 0),
(5, 2001, 5, NULL, 'AVAILABLE', NULL, 550.00, 0);
```

---

## 5. Sample Rows Representation

### Table: `theaters`
| theater_id | city_id | name | address | created_at |
| :--- | :--- | :--- | :--- | :--- |
| `101` | `1` | PVR: Forum Mall, Koramangala | Hosur Road, Koramangala, Bengaluru | 2026-09-28 10:00:00 |

### Table: `screens`
| screen_id | theater_id | screen_name | sound_type | display_type |
| :--- | :--- | :--- | :--- | :--- |
| `1001` | `101` | Audi 1 (IMAX) | Dolby Atmos | IMAX Laser |
| `1002` | `101` | Audi 2 | Dolby Digital 7.1 | 4K Digital |

### Table: `seats`
| seat_id | screen_id | seat_row | seat_number | seat_tier |
| :--- | :--- | :--- | :--- | :--- |
| `1` | `1001` | A | 1 | NORMAL |
| `2` | `1001` | A | 2 | NORMAL |
| `3` | `1001` | B | 1 | EXECUTIVE |

### Table: `movies`
| movie_id | title | duration_minutes | language | certificate | release_date |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `501` | Dune: Part Two | 166 | English | UA | 2026-03-01 |
| `502` | Kantara: A Legend Chapter-1 | 150 | Kannada | UA | 2026-10-02 |

### Table: `shows`
| show_id | screen_id | movie_id | start_time | end_time | base_price |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `2001` | `1001` | `501` | 2026-10-05 10:00:00 | 2026-10-05 12:46:00 | 350.00 |
| `2002` | `1001` | `501` | 2026-10-05 14:00:00 | 2026-10-05 16:46:00 | 400.00 |
| `2004` | `1002` | `502` | 2026-10-05 11:30:00 | 2026-10-05 14:00:00 | 250.00 |

### Table: `show_seat_inventory`
| inventory_id | show_id | seat_id | booking_id | status | locked_until | price | version |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `1` | `2001` | `1` | `NULL` | AVAILABLE | `NULL` | 350.00 | 0 |
| `2` | `2001` | `2` | `NULL` | AVAILABLE | `NULL` | 350.00 | 0 |
| `3` | `2001` | `3` | `NULL` | AVAILABLE | `NULL` | 420.00 | 0 |

---

## 6. P2: Theater Schedule Query

### Objective
Retrieve all shows running at a specific theater (`theater_id = 101`) for a selected date (`2026-10-05`), listing the movie details, screens, sound/projection specs, and start timings.

### Production Query (Direct Execution)
```sql
SELECT 
    m.movie_id,
    m.title AS movie_title,
    m.certificate,
    m.language,
    sc.screen_id,
    sc.screen_name,
    sc.display_type,
    sc.sound_type,
    s.show_id,
    s.start_time,
    DATE_FORMAT(s.start_time, '%h:%i %p') AS formatted_start_time,
    s.base_price
FROM shows s
JOIN screens sc ON s.screen_id = sc.screen_id
JOIN movies m ON s.movie_id = m.movie_id
WHERE sc.theater_id = 101
  AND s.start_time >= '2026-10-05 00:00:00'
  AND s.start_time < '2026-10-06 00:00:00'
ORDER BY m.title ASC, sc.screen_name ASC, s.start_time ASC;
```

### Aggregated Query (BookMyShow UI Grouping)
This query rolls up individual showtimes into an aggregated list matching the horizontal time chips seen on BookMyShow movie cards:

```sql
SELECT 
    m.movie_id,
    m.title AS movie_title,
    m.certificate,
    m.language,
    GROUP_CONCAT(
        CONCAT(DATE_FORMAT(s.start_time, '%h:%i %p'), ' (', sc.screen_name, ')') 
        ORDER BY s.start_time ASC 
        SEPARATOR '  |  '
    ) AS available_showtimes
FROM shows s
JOIN screens sc ON s.screen_id = sc.screen_id
JOIN movies m ON s.movie_id = m.movie_id
WHERE sc.theater_id = 101
  AND s.start_time >= '2026-10-05 00:00:00'
  AND s.start_time < '2026-10-06 00:00:00'
GROUP BY m.movie_id, m.title, m.certificate, m.language
ORDER BY m.title ASC;
```

### Sample Query Result
| movie_id | movie_title | certificate | language | available_showtimes |
| :--- | :--- | :--- | :--- | :--- |
| `501` | Dune: Part Two | UA | English | 10:00 AM (Audi 1 (IMAX))  \|  02:00 PM (Audi 1 (IMAX))  \|  06:30 PM (Audi 1 (IMAX)) |
| `502` | Kantara: A Legend Chapter-1 | UA | Kannada | 11:30 AM (Audi 2)  \|  04:00 PM (Audi 2) |