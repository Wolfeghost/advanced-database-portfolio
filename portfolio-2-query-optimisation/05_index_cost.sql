-- =====================================================================
-- LagosCare Clinics — Portfolio 2: The cost of indexes
-- Indexes speed up reads but take disk space and slow down writes,
-- because every INSERT/UPDATE must also maintain each secondary index.
-- Run AFTER 03_create_indexes.sql.
-- =====================================================================
USE lagoscare;

-- ---------------------------------------------------------------------
-- 1. Storage: size of each index (pages x page size)
-- ---------------------------------------------------------------------
SELECT '== Index sizes (MB) ==' AS step;

SELECT table_name, index_name,
       ROUND(stat_value * @@innodb_page_size / 1024 / 1024, 2) AS size_mb
FROM   mysql.innodb_index_stats
WHERE  database_name = 'lagoscare'
  AND  stat_name = 'size'
  AND  table_name IN ('patient', 'appointment', 'invoice', 'lab_order')
ORDER  BY table_name, index_name;

-- ---------------------------------------------------------------------
-- 2. Write cost: copy all appointments into an empty table, once with the
-- Portfolio 2 indexes and once without them. CREATE TABLE ... LIKE copies
-- the indexes (but not the foreign keys). Run this script 2–3 times and
-- use the median, as single timings vary.
-- ---------------------------------------------------------------------
SELECT '== Write cost: bulk insert of all appointments ==' AS step;

DROP TABLE IF EXISTS p2_write_test;
CREATE TABLE p2_write_test LIKE appointment;          -- PK + 4 secondary indexes
SET @t0 = NOW(6);
INSERT INTO p2_write_test SELECT * FROM appointment;
SELECT 'WITH Portfolio 2 indexes (4 secondary)' AS scenario,
       ROW_COUNT() AS rows_inserted,
       ROUND(TIMESTAMPDIFF(MICROSECOND, @t0, NOW(6)) / 1000) AS insert_ms;
DROP TABLE p2_write_test;

CREATE TABLE p2_write_test LIKE appointment;
ALTER TABLE p2_write_test
  DROP INDEX idx_appt_branch_start,
  DROP INDEX idx_appt_start_doctor_status;           -- PK + 2 secondary indexes
SET @t0 = NOW(6);
INSERT INTO p2_write_test SELECT * FROM appointment;
SELECT 'WITHOUT Portfolio 2 indexes (2 secondary)' AS scenario,
       ROW_COUNT() AS rows_inserted,
       ROUND(TIMESTAMPDIFF(MICROSECOND, @t0, NOW(6)) / 1000) AS insert_ms;
DROP TABLE p2_write_test;
