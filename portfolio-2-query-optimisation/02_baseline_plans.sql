-- =====================================================================
-- LagosCare Clinics — Portfolio 2: Baseline queries and execution plans
-- Run AFTER 01_bulk_data.sql and BEFORE 03_create_indexes.sql.
--
-- Each workload query is run twice:
--   (a) the query itself, to show the result
--   (b) EXPLAIN ANALYZE, which executes the query and reports the real
--       plan, the optimiser's row/cost ESTIMATES and the ACTUAL rows and time.
--
-- Capture to a text file (Windows Command Prompt, from this folder):
--   mysql -u root -p --raw -vvv lagoscare < 02_baseline_plans.sql > evidence\baseline_plans.txt
-- In Workbench, EXPLAIN ANALYZE output appears in one cell: right-click it >
-- "Open Value in Viewer". For screenshots, also use Query > Explain Current
-- Statement (Visual Explain).
-- =====================================================================
USE lagoscare;

-- ---------------------------------------------------------------------
-- Q1. Front desk: find a returning patient by surname and start of first name
--     (patient forgot their card). Runs many times a day at both branches.
-- ---------------------------------------------------------------------
SELECT '== Q1 baseline: patient name search ==' AS step;

SELECT patient_id, hospital_no, first_name, last_name, date_of_birth, phone
FROM   patient
WHERE  last_name = 'Okafor' AND first_name LIKE 'Chi%'
ORDER  BY first_name
LIMIT  10;

EXPLAIN ANALYZE
SELECT patient_id, hospital_no, first_name, last_name, date_of_birth, phone
FROM   patient
WHERE  last_name = 'Okafor' AND first_name LIKE 'Chi%'
ORDER  BY first_name;

-- ---------------------------------------------------------------------
-- Q2. Front desk: one branch's clinic list for one day, as first written
--     by a developer (uses DATE() on the column).
-- ---------------------------------------------------------------------
SELECT '== Q2 baseline: branch daily clinic list (DATE() on column) ==' AS step;

SELECT a.appointment_id, a.scheduled_start, a.status, p.hospital_no,
       CONCAT(p.first_name, ' ', p.last_name) AS patient,
       CONCAT(s.first_name, ' ', s.last_name) AS doctor
FROM   appointment a
JOIN   patient p ON p.patient_id = a.patient_id
JOIN   staff   s ON s.staff_id   = a.doctor_id
WHERE  a.branch_id = 2
  AND  DATE(a.scheduled_start) = '2026-09-15'
ORDER  BY a.scheduled_start, s.last_name
LIMIT  10;

EXPLAIN ANALYZE
SELECT a.appointment_id, a.scheduled_start, a.status, p.hospital_no,
       CONCAT(p.first_name, ' ', p.last_name) AS patient,
       CONCAT(s.first_name, ' ', s.last_name) AS doctor
FROM   appointment a
JOIN   patient p ON p.patient_id = a.patient_id
JOIN   staff   s ON s.staff_id   = a.doctor_id
WHERE  a.branch_id = 2
  AND  DATE(a.scheduled_start) = '2026-09-15'
ORDER  BY a.scheduled_start, s.last_name;

-- ---------------------------------------------------------------------
-- Q3. Management: revenue for one month by branch and item type
--     (consultation / lab / medication). 5-table join + GROUP BY.
-- ---------------------------------------------------------------------
SELECT '== Q3 baseline: monthly revenue by branch and item type ==' AS step;

SELECT b.branch_code, il.item_type,
       COUNT(DISTINCT i.invoice_id)   AS invoices,
       SUM(il.quantity * il.unit_price) AS revenue
FROM   invoice i
JOIN   invoice_line il ON il.invoice_id    = i.invoice_id
JOIN   encounter    e  ON e.encounter_id   = i.encounter_id
JOIN   appointment  a  ON a.appointment_id = e.appointment_id
JOIN   branch       b  ON b.branch_id      = a.branch_id
WHERE  i.issued_at >= '2026-09-01' AND i.issued_at < '2026-10-01'
  AND  i.status <> 'VOID'
GROUP  BY b.branch_code, il.item_type
ORDER  BY b.branch_code, revenue DESC;

EXPLAIN ANALYZE
SELECT b.branch_code, il.item_type,
       COUNT(DISTINCT i.invoice_id)   AS invoices,
       SUM(il.quantity * il.unit_price) AS revenue
FROM   invoice i
JOIN   invoice_line il ON il.invoice_id    = i.invoice_id
JOIN   encounter    e  ON e.encounter_id   = i.encounter_id
JOIN   appointment  a  ON a.appointment_id = e.appointment_id
JOIN   branch       b  ON b.branch_id      = a.branch_id
WHERE  i.issued_at >= '2026-09-01' AND i.issued_at < '2026-10-01'
  AND  i.status <> 'VOID'
GROUP  BY b.branch_code, il.item_type
ORDER  BY b.branch_code, revenue DESC;

-- ---------------------------------------------------------------------
-- Q4. Management: no-show rate per doctor for the last quarter (Jul–Sep 2026).
-- ---------------------------------------------------------------------
SELECT '== Q4 baseline: no-show rate per doctor, Q3 2026 ==' AS step;

SELECT a.doctor_id,
       COUNT(*)                                          AS appointments,
       SUM(a.status = 'NO_SHOW')                         AS no_shows,
       ROUND(100 * SUM(a.status = 'NO_SHOW') / COUNT(*), 1) AS no_show_pct
FROM   appointment a
WHERE  a.scheduled_start >= '2026-07-01' AND a.scheduled_start < '2026-10-01'
GROUP  BY a.doctor_id
ORDER  BY no_show_pct DESC
LIMIT  5;

EXPLAIN ANALYZE
SELECT a.doctor_id,
       COUNT(*)                                          AS appointments,
       SUM(a.status = 'NO_SHOW')                         AS no_shows,
       ROUND(100 * SUM(a.status = 'NO_SHOW') / COUNT(*), 1) AS no_show_pct
FROM   appointment a
WHERE  a.scheduled_start >= '2026-07-01' AND a.scheduled_start < '2026-10-01'
GROUP  BY a.doctor_id
ORDER  BY no_show_pct DESC;

-- ---------------------------------------------------------------------
-- Q5. Laboratory: oldest 50 lab orders still waiting for a sample/result
--     more than 24 hours after ordering (as at 22 Oct 2026, 00:00).
-- ---------------------------------------------------------------------
SELECT '== Q5 baseline: overdue lab orders worklist ==' AS step;

SELECT lo.lab_order_id, lo.ordered_at, lt.test_code, p.hospital_no,
       TIMESTAMPDIFF(HOUR, lo.ordered_at, '2026-10-22 00:00:00') AS hours_waiting
FROM   lab_order lo
JOIN   lab_test    lt ON lt.lab_test_id   = lo.lab_test_id
JOIN   encounter   e  ON e.encounter_id   = lo.encounter_id
JOIN   appointment a  ON a.appointment_id = e.appointment_id
JOIN   patient     p  ON p.patient_id     = a.patient_id
WHERE  lo.status = 'ORDERED'
  AND  lo.ordered_at < '2026-10-21 00:00:00'
ORDER  BY lo.ordered_at
LIMIT  10;

EXPLAIN ANALYZE
SELECT lo.lab_order_id, lo.ordered_at, lt.test_code, p.hospital_no,
       TIMESTAMPDIFF(HOUR, lo.ordered_at, '2026-10-22 00:00:00') AS hours_waiting
FROM   lab_order lo
JOIN   lab_test    lt ON lt.lab_test_id   = lo.lab_test_id
JOIN   encounter   e  ON e.encounter_id   = lo.encounter_id
JOIN   appointment a  ON a.appointment_id = e.appointment_id
JOIN   patient     p  ON p.patient_id     = a.patient_id
WHERE  lo.status = 'ORDERED'
  AND  lo.ordered_at < '2026-10-21 00:00:00'
ORDER  BY lo.ordered_at
LIMIT  50;

-- ---------------------------------------------------------------------
-- Indexes that exist before optimisation (PKs, UNIQUE keys and the
-- indexes InnoDB creates automatically for foreign keys)
-- ---------------------------------------------------------------------
SELECT '== Indexes before optimisation ==' AS step;

SELECT table_name, index_name,
       GROUP_CONCAT(column_name ORDER BY seq_in_index) AS columns
FROM   information_schema.statistics
WHERE  table_schema = 'lagoscare'
  AND  table_name IN ('patient', 'appointment', 'invoice', 'lab_order')
GROUP  BY table_name, index_name
ORDER  BY table_name, index_name;
