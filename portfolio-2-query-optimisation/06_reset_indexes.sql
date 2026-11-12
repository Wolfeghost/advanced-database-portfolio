-- =====================================================================
-- LagosCare Clinics — Portfolio 2: Remove the optimisation indexes
-- Use this to return to the baseline and re-run 02_baseline_plans.sql.
-- =====================================================================
USE lagoscare;

-- idx_appt_branch_start is currently the index supporting the foreign key
-- fk_appt_branch, so MySQL refuses to drop it ("needed in a foreign key
-- constraint") until another index on branch_id exists. Recreate the
-- original FK index first, then drop.
-- Note: this recreated fk_appt_branch is an ordinary index, so it is NOT
-- dropped automatically when 03_create_indexes.sql is run again. After
-- re-running 03, remove the duplicate with:
--   DROP INDEX fk_appt_branch ON appointment;
CREATE INDEX fk_appt_branch ON appointment (branch_id);

DROP INDEX idx_patient_name             ON patient;
DROP INDEX idx_appt_branch_start        ON appointment;
DROP INDEX idx_invoice_issued           ON invoice;
DROP INDEX idx_appt_start_doctor_status ON appointment;
DROP INDEX idx_laborder_status_ordered  ON lab_order;

ANALYZE TABLE patient, appointment, invoice, lab_order;
