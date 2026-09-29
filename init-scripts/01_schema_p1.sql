-- ============================================================================
-- 01_schema_p1.sql: Database Schema Definition (MySQL 8.0+)
-- Complies with 1NF, 2NF, 3NF, BCNF and supports high-concurrency seat locking
-- ============================================================================

CREATE DATABASE IF NOT EXISTS bookmyshow;
USE bookmyshow;

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

-- 1. Cities
CREATE TABLE cities (
    city_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    state VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 2. Theaters
CREATE TABLE theaters (
    theater_id INT AUTO_INCREMENT PRIMARY KEY,
    city_id INT NOT NULL,
    name VARCHAR(150) NOT NULL,
    address VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_theaters_city FOREIGN KEY (city_id) REFERENCES cities (city_id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 3. Screens (Auditoriums)
CREATE TABLE screens (
    screen_id INT AUTO_INCREMENT PRIMARY KEY,
    theater_id INT NOT NULL,
    screen_name VARCHAR(50) NOT NULL,
    sound_type VARCHAR(50) DEFAULT 'Dolby Atmos 7.1',
    display_type VARCHAR(50) DEFAULT '4K Laser',
    CONSTRAINT fk_screens_theater FOREIGN KEY (theater_id) REFERENCES theaters (theater_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 4. Seats (Physical blueprint per screen)
CREATE TABLE seats (
    seat_id INT AUTO_INCREMENT PRIMARY KEY,
    screen_id INT NOT NULL,
    seat_row CHAR(2) NOT NULL,
    seat_number INT NOT NULL,
    seat_tier ENUM('NORMAL', 'EXECUTIVE', 'VIP') DEFAULT 'NORMAL',
    CONSTRAINT fk_seats_screen FOREIGN KEY (screen_id) REFERENCES screens (screen_id) ON DELETE CASCADE,
    CONSTRAINT uq_screen_seat UNIQUE (screen_id, seat_row, seat_number)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 5. Movies
CREATE TABLE movies (
    movie_id INT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(200) NOT NULL,
    duration_minutes INT NOT NULL,
    language VARCHAR(50) NOT NULL,
    certificate VARCHAR(10) DEFAULT 'UA',
    release_date DATE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 6. Shows (Movie schedule instances)
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

-- 7. Bookings
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

-- 8. Show Seat Inventory (Transactional seat-level concurrency target)
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

-- 9. Payments (Idempotent Webhook Target)
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