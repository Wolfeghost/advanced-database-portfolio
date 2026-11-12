-- =====================================================================
-- LagosCare Clinics — Portfolio 2: Optimisation indexes
-- Each index is designed for one workload query (see README).
-- Composite index rule used throughout: equality columns first,
-- then the range / ORDER BY column, then any extra columns needed to
-- make the index "covering" (so the table row never has to be read).
-- =====================================================================
USE lagoscare;

-- Q1: name search. Equality on last_name, prefix range on first_name.
CREATE INDEX idx_patient_name
  ON patient (last_name, first_name);

-- Q2: branch daily list. Equality on branch_id, range on scheduled_start.
-- Note: this index starts with branch_id, so it can also support the
-- foreign key fk_appt_branch. InnoDB therefore silently DROPS the index it
-- had created automatically for that FK (check SHOW INDEX afterwards).
CREATE INDEX idx_appt_branch_start
  ON appointment (branch_id, scheduled_start);

-- Q3: monthly revenue. Range on issued_at.
CREATE INDEX idx_invoice_issued
  ON invoice (issued_at);

-- Q4: no-show rate. Covering index: the range column first, then every
-- other column the query reads (doctor_id for GROUP BY, status for SUM),
-- so the query is answered from the index alone ("Covering index range scan").
CREATE INDEX idx_appt_start_doctor_status
  ON appointment (scheduled_start, doctor_id, status);

-- Q5: overdue lab worklist. Equality on status, then ordered_at, which is
-- both the range filter and the ORDER BY — so no sort is needed and the
-- LIMIT 50 can stop after the first 50 index entries.
CREATE INDEX idx_laborder_status_ordered
  ON lab_order (status, ordered_at);

-- Refresh optimiser statistics for the changed tables
ANALYZE TABLE patient, appointment, invoice, lab_order;

SELECT '== Indexes after optimisation ==' AS step;

SELECT table_name, index_name,
       GROUP_CONCAT(column_name ORDER BY seq_in_index) AS columns
FROM   information_schema.statistics
WHERE  table_schema = 'lagoscare'
  AND  table_name IN ('patient', 'appointment', 'invoice', 'lab_order')
GROUP  BY table_name, index_name
ORDER  BY table_name, index_name;
