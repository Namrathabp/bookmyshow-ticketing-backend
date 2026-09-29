-- ============================================================================
-- 03_queries_p2.sql: P2 Task Queries
-- Lists all shows on a given date at a given theatre with show timings
-- ============================================================================

USE bookmyshow;

-- Target parameters for demonstration:
-- Theater ID: 101 (PVR: Forum Mall, Koramangala)
-- Date: 2026-10-05

-- ----------------------------------------------------------------------------
-- Option A: BookMyShow Aggregated UI View
-- Groups showtimes into horizontal chips per movie card
-- ----------------------------------------------------------------------------
SELECT 
    m.movie_id,
    m.title AS movie_title,
    m.certificate,
    m.language,
    GROUP_CONCAT(
        CONCAT(
            DATE_FORMAT(s.start_time, '%h:%i %p'),
            ' (', sc.screen_name, ' - ', sc.display_type, ')'
        ) 
        ORDER BY s.start_time ASC 
        SEPARATOR '   |   '
    ) AS available_showtimes
FROM shows s
JOIN screens sc ON s.screen_id = sc.screen_id
JOIN movies m   ON s.movie_id = m.movie_id
WHERE sc.theater_id = 101
  AND s.start_time >= '2026-10-05 00:00:00'
  AND s.start_time < '2026-10-06 00:00:00'
GROUP BY m.movie_id, m.title, m.certificate, m.language
ORDER BY m.title ASC;

-- ----------------------------------------------------------------------------
-- Option B: Granular Tabular View
-- Returns each scheduled show slot as an individual row
-- ----------------------------------------------------------------------------
SELECT 
    m.title AS movie_title,
    m.language,
    m.certificate,
    sc.screen_name,
    sc.display_type,
    sc.sound_type,
    s.show_id,
    DATE_FORMAT(s.start_time, '%h:%i %p') AS start_time,
    DATE_FORMAT(s.end_time, '%h:%i %p') AS end_time,
    s.base_price
FROM shows s
JOIN screens sc ON s.screen_id = sc.screen_id
JOIN movies m   ON s.movie_id = m.movie_id
WHERE sc.theater_id = 101
  AND s.start_time >= '2026-10-05 00:00:00'
  AND s.start_time < '2026-10-06 00:00:00'
ORDER BY m.title ASC, s.start_time ASC;