-- =====================================================================
-- LagosCare Clinics — Portfolio 2: Optimised queries and execution plans
-- Run AFTER 03_create_indexes.sql.
--
-- Capture to a text file (Windows Command Prompt, from this folder):
--   mysql -u root -p --raw -vvv lagoscare < 04_optimised_plans.sql > evidence\optimised_plans.txt
-- =====================================================================
USE lagoscare;

-- ---------------------------------------------------------------------
-- Q1 after: same SQL, new index idx_patient_name
-- ---------------------------------------------------------------------
SELECT '== Q1 optimised: patient name search ==' AS step;

EXPLAIN ANALYZE
SELECT patient_id, hospital_no, first_name, last_name, date_of_birth, phone
FROM   patient
WHERE  last_name = 'Okafor' AND first_name LIKE 'Chi%'
ORDER  BY first_name;

-- Counter-example: a LEADING wildcard cannot use the index (B-tree indexes
-- are sorted from the first character), so this is a full scan again.
SELECT '== Q1 counter-example: leading wildcard ==' AS step;

EXPLAIN ANALYZE
SELECT patient_id, hospital_no, first_name, last_name
FROM   patient
WHERE  last_name LIKE '%kafor';

-- ---------------------------------------------------------------------
-- Q2 after (step 1): ORIGINAL SQL with the new index.
-- The index is chosen, but DATE(scheduled_start) hides the column inside a
-- function, so MySQL can only use the branch_id part: it still reads every
-- branch-2 index entry and tests DATE() on each one.
-- ---------------------------------------------------------------------
SELECT '== Q2 optimised step 1: original SQL + index (still not sargable) ==' AS step;

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
-- Q2 after (step 2): REWRITTEN as a half-open range on the bare column
-- ("sargable"). Same result, but now both index columns are used.
-- ---------------------------------------------------------------------
SELECT '== Q2 optimised step 2: sargable rewrite + index ==' AS step;

SELECT a.appointment_id, a.scheduled_start, a.status, p.hospital_no,
       CONCAT(p.first_name, ' ', p.last_name) AS patient,
       CONCAT(s.first_name, ' ', s.last_name) AS doctor
FROM   appointment a
JOIN   patient p ON p.patient_id = a.patient_id
JOIN   staff   s ON s.staff_id   = a.doctor_id
WHERE  a.branch_id = 2
  AND  a.scheduled_start >= '2026-09-15'
  AND  a.scheduled_start <  '2026-09-16'
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
  AND  a.scheduled_start >= '2026-09-15'
  AND  a.scheduled_start <  '2026-09-16'
ORDER  BY a.scheduled_start, s.last_name;

-- ---------------------------------------------------------------------
-- Q3 after (step 1): original SQL with idx_invoice_issued.
-- The invoice access becomes a range scan, but total time barely moves:
-- the optimiser still joins branch with a "hash join (no condition)",
-- which doubles the rows flowing through the plan.
-- ---------------------------------------------------------------------
SELECT '== Q3 optimised step 1: original SQL + index ==' AS step;

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
-- Q3 after (step 2): REWRITTEN to aggregate by a.branch_id first in a
-- derived table, then join the 2-row branch table to the 6 summary rows.
-- ---------------------------------------------------------------------
SELECT '== Q3 optimised step 2: aggregate first, then join branch ==' AS step;

SELECT b.branch_code, r.item_type, r.invoices, r.revenue
FROM  (SELECT a.branch_id, il.item_type,
              COUNT(DISTINCT i.invoice_id)   AS invoices,
              SUM(il.quantity * il.unit_price) AS revenue
       FROM   invoice i
       JOIN   invoice_line il ON il.invoice_id    = i.invoice_id
       JOIN   encounter    e  ON e.encounter_id   = i.encounter_id
       JOIN   appointment  a  ON a.appointment_id = e.appointment_id
       WHERE  i.issued_at >= '2026-09-01' AND i.issued_at < '2026-10-01'
         AND  i.status <> 'VOID'
       GROUP  BY a.branch_id, il.item_type) r
JOIN   branch b ON b.branch_id = r.branch_id
ORDER  BY b.branch_code, r.revenue DESC;

EXPLAIN ANALYZE
SELECT b.branch_code, r.item_type, r.invoices, r.revenue
FROM  (SELECT a.branch_id, il.item_type,
              COUNT(DISTINCT i.invoice_id)   AS invoices,
              SUM(il.quantity * il.unit_price) AS revenue
       FROM   invoice i
       JOIN   invoice_line il ON il.invoice_id    = i.invoice_id
       JOIN   encounter    e  ON e.encounter_id   = i.encounter_id
       JOIN   appointment  a  ON a.appointment_id = e.appointment_id
       WHERE  i.issued_at >= '2026-09-01' AND i.issued_at < '2026-10-01'
         AND  i.status <> 'VOID'
       GROUP  BY a.branch_id, il.item_type) r
JOIN   branch b ON b.branch_id = r.branch_id
ORDER  BY b.branch_code, r.revenue DESC;

-- ---------------------------------------------------------------------
-- Q4 after: same SQL, covering index idx_appt_start_doctor_status
-- ---------------------------------------------------------------------
SELECT '== Q4 optimised: no-show rate (covering index) ==' AS step;

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
-- Q5 after: same SQL, index idx_laborder_status_ordered (no sort needed)
-- ---------------------------------------------------------------------
SELECT '== Q5 optimised: overdue lab worklist ==' AS step;

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
-- Q6. Query processing: three ways to write "registered patients who
-- have never booked an appointment" (data-quality / marketing list).
-- The optimiser transforms all three into the same anti-join plan.
-- ---------------------------------------------------------------------
SELECT '== Q6: anti-join, three formulations ==' AS step;

SELECT COUNT(*) AS patients_never_booked
FROM   patient p
WHERE  NOT EXISTS (SELECT 1 FROM appointment a WHERE a.patient_id = p.patient_id);

-- (a) NOT IN
EXPLAIN ANALYZE
SELECT p.patient_id, p.hospital_no
FROM   patient p
WHERE  p.patient_id NOT IN (SELECT a.patient_id FROM appointment a);

-- (b) NOT EXISTS
EXPLAIN ANALYZE
SELECT p.patient_id, p.hospital_no
FROM   patient p
WHERE  NOT EXISTS (SELECT 1 FROM appointment a WHERE a.patient_id = p.patient_id);

-- (c) LEFT JOIN ... IS NULL
EXPLAIN ANALYZE
SELECT p.patient_id, p.hospital_no
FROM   patient p
LEFT   JOIN appointment a ON a.patient_id = p.patient_id
WHERE  a.appointment_id IS NULL;

-- (d) NOT EXISTS with the foreign-key index hidden: the optimiser falls back
-- to scanning appointment once and building a de-duplicated temporary table.
EXPLAIN ANALYZE
SELECT p.patient_id, p.hospital_no
FROM   patient p
WHERE  NOT EXISTS (SELECT 1 FROM appointment a IGNORE INDEX (fk_appt_patient)
                   WHERE a.patient_id = p.patient_id);
