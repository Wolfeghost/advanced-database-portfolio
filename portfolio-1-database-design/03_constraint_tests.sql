-- =====================================================================
-- LagosCare Clinics — Portfolio 1: Constraint tests
-- Every statement below is EXPECTED TO FAIL. Each failure proves a
-- constraint is enforced by the database rather than by the application.
--
-- In MySQL Workbench, enable "Continue SQL script execution on errors"
-- (the toggle icon in the SQL editor toolbar), or run each test on its
-- own, then screenshot the Output panel showing every error.
-- =====================================================================
USE lagoscare;

-- T1 Primary/unique key: duplicate hospital number
--    Expected: Error 1062 Duplicate entry 'LC-000001' for key 'patient.uq_patient_hospital_no'
INSERT INTO patient (hospital_no, first_name, last_name, date_of_birth, sex, phone)
VALUES ('LC-000001', 'Test', 'Duplicate', '1990-01-01', 'M', '+2340000000000');

-- T2 Trigger: date of birth in the future
--    Expected: Error 1644 date_of_birth cannot be in the future
INSERT INTO patient (hospital_no, first_name, last_name, date_of_birth, sex, phone)
VALUES ('LC-999001', 'Test', 'Future', '2099-01-01', 'F', '+2340000000001');

-- T3 CHECK: HMO supplied without a membership number
--    Expected: Error 3819 Check constraint 'chk_patient_hmo_pair' is violated
INSERT INTO patient (hospital_no, first_name, last_name, date_of_birth, sex, phone, hmo_id, hmo_member_no)
VALUES ('LC-999002', 'Test', 'NoMemberNo', '1990-01-01', 'M', '+2340000000002', 1, NULL);

-- T4 CHECK: appointment ends before it starts
--    Expected: Error 3819 Check constraint 'chk_appt_time' is violated
INSERT INTO appointment (patient_id, doctor_id, branch_id, scheduled_start, scheduled_end)
VALUES (2, 1, 1, '2026-11-20 10:00:00', '2026-11-20 09:30:00');

-- T5 UNIQUE: double-booking a doctor for the same start time
--    Expected: Error 1062 Duplicate entry for key 'appointment.uq_appt_doctor_slot'
INSERT INTO appointment (patient_id, doctor_id, branch_id, scheduled_start, scheduled_end)
VALUES (7, 1, 1, '2026-11-16 09:00:00', '2026-11-16 09:30:00');

-- T6 Foreign key: appointment for a patient who does not exist
--    Expected: Error 1452 Cannot add or update a child row: a foreign key constraint fails (fk_appt_patient)
INSERT INTO appointment (patient_id, doctor_id, branch_id, scheduled_start, scheduled_end)
VALUES (9999, 1, 1, '2026-11-20 10:00:00', '2026-11-20 10:30:00');

-- T7 Trigger: a receptionist (staff_id 5) cannot be registered as a doctor
--    Expected: Error 1644 Staff member must have role DOCTOR ...
INSERT INTO doctor (staff_id, specialty, mdcn_licence_no, consultation_fee)
VALUES (5, 'General Practice', 'MDCN/R/99999', 10000.00);

-- T8 CHECK: stock cannot go negative (protects against over-dispensing)
--    Expected: Error 3819 Check constraint 'chk_stock_qty' is violated
UPDATE pharmacy_stock SET quantity_on_hand = quantity_on_hand - 1000
WHERE branch_id = 1 AND medication_id = 5;

-- T9 CHECK: zero or negative payment
--    Expected: Error 3819 Check constraint 'chk_payment_amount' is violated
INSERT INTO payment (invoice_id, amount, method, reference)
VALUES (4, 0, 'CASH', 'PAY-TEST-0001');

-- T10 Referential integrity: a patient with clinical history cannot be deleted
--    Expected: Error 1451 Cannot delete or update a parent row: a foreign key constraint fails (fk_appt_patient)
DELETE FROM patient WHERE patient_id = 1;

-- T11 Composite PK: the same diagnosis recorded twice on one encounter
--    Expected: Error 1062 Duplicate entry '4-I10' for key 'encounter_diagnosis.PRIMARY'
INSERT INTO encounter_diagnosis (encounter_id, icd10_code) VALUES (4, 'I10');

-- T12 ENUM domain: invalid appointment status
--    Expected: Error 1265 Data truncated for column 'status' (strict SQL mode, MySQL 8 default)
UPDATE appointment SET status = 'POSTPONED' WHERE appointment_id = 6;

-- ---------------------------------------------------------------------
-- Confirm nothing was changed by the failed statements
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS patients      FROM patient;        -- expect 8
SELECT COUNT(*) AS appointments  FROM appointment;    -- expect 7
SELECT quantity_on_hand FROM pharmacy_stock WHERE branch_id = 1 AND medication_id = 5; -- expect 40
