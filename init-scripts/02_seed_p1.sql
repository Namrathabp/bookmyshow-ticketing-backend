-- ============================================================================
-- 02_seed_p1.sql: Seed Data for Theaters, Screens, Seats, Movies, Shows & Seats
-- ============================================================================

USE bookmyshow;

-- Cities
INSERT INTO cities (city_id, name, state) VALUES 
(1, 'Bengaluru', 'Karnataka');

-- Theaters
INSERT INTO theaters (theater_id, city_id, name, address) VALUES 
(101, 1, 'PVR: Forum Mall, Koramangala', 'Hosur Road, Koramangala, Bengaluru');

-- Screens for Theater 101
INSERT INTO screens (screen_id, theater_id, screen_name, sound_type, display_type) VALUES 
(1001, 101, 'Audi 1 (IMAX)', 'Dolby Atmos', 'IMAX Laser'),
(1002, 101, 'Audi 2', 'Dolby Digital 7.1', '4K Digital');

-- Physical Seats for Screen 1001 (Audi 1)
INSERT INTO seats (seat_id, screen_id, seat_row, seat_number, seat_tier) VALUES 
(1, 1001, 'A', 1, 'NORMAL'),
(2, 1001, 'A', 2, 'NORMAL'),
(3, 1001, 'B', 1, 'EXECUTIVE'),
(4, 1001, 'B', 2, 'EXECUTIVE'),
(5, 1001, 'C', 1, 'VIP');

-- Physical Seats for Screen 1002 (Audi 2)
INSERT INTO seats (seat_id, screen_id, seat_row, seat_number, seat_tier) VALUES 
(6, 1002, 'A', 1, 'NORMAL'),
(7, 1002, 'A', 2, 'NORMAL');

-- Movies
INSERT INTO movies (movie_id, title, duration_minutes, language, certificate, release_date) VALUES 
(501, 'Dune: Part Two', 166, 'English', 'UA', '2024-03-01'),
(502, 'Kantara: A Legend Chapter-1', 150, 'Kannada', 'UA', '2024-10-02');

-- Shows scheduled for 2026-10-05 at Theater 101
INSERT INTO shows (show_id, screen_id, movie_id, start_time, end_time, base_price) VALUES 
(2001, 1001, 501, '2026-10-05 10:00:00', '2026-10-05 12:50:00', 350.00),
(2002, 1001, 501, '2026-10-05 14:00:00', '2026-10-05 16:50:00', 400.00),
(2003, 1001, 501, '2026-10-05 18:30:00', '2026-10-05 21:20:00', 450.00),
(2004, 1002, 502, '2026-10-05 11:30:00', '2026-10-05 14:00:00', 250.00),
(2005, 1002, 502, '2026-10-05 16:00:00', '2026-10-05 18:30:00', 250.00);

-- Inventory initialization for Show 2001 (Audi 1)
INSERT INTO show_seat_inventory (show_id, seat_id, status, price) VALUES 
(2001, 1, 'AVAILABLE', 350.00),
(2001, 2, 'AVAILABLE', 350.00),
(2001, 3, 'AVAILABLE', 420.00),
(2001, 4, 'AVAILABLE', 420.00),
(2001, 5, 'AVAILABLE', 550.00);