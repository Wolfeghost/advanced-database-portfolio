-- =====================================================================
-- LagosCare Clinics — Portfolio 2: Bulk data generation
-- Target: MySQL 8.0 (run AFTER Portfolio 1 01_schema.sql and 02_seed_data.sql)
--
-- Adds about 13 months of realistic activity (Oct 2025 – Oct 2026) so that
-- execution plans and timings are meaningful:
--   16 extra doctors, 20,000 patients, 120,000 appointments,
--   ~96,000 encounters, ~134,000 diagnoses, ~38,000 lab orders,
--   ~96,000 invoices, ~201,000 invoice lines, ~126,000 payments.
--
-- The data is DETERMINISTIC: pseudo-random choices come from CRC32() of the
-- row number, not RAND(), so every run produces exactly the same rows and
-- the same execution plans. All names and numbers are fictional.
--
-- MySQL Workbench: before running, set
--   Edit > Preferences > SQL Editor > DBMS connection read timeout = 600
-- otherwise the larger INSERTs can be cut off after 30 seconds.
-- =====================================================================
USE lagoscare;

-- ---------------------------------------------------------------------
-- 0. Helper: a numbers table 0 .. 199,999 (cross join of digits)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS p2_digits, p2_numbers, p2_doctor_map, p2_dx_map;

CREATE TABLE p2_digits (d TINYINT UNSIGNED PRIMARY KEY);
INSERT INTO p2_digits VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9);

CREATE TABLE p2_numbers (n INT UNSIGNED PRIMARY KEY);
INSERT INTO p2_numbers (n)
SELECT a.d + 10*b.d + 100*c.d + 1000*d.d + 10000*e.d + 100000*f.d
FROM p2_digits a, p2_digits b, p2_digits c, p2_digits d, p2_digits e, p2_digits f
WHERE a.d + 10*b.d + 100*c.d + 1000*d.d + 10000*e.d + 100000*f.d < 200000;

-- ---------------------------------------------------------------------
-- 1. Reference data: more doctors and more ICD-10 codes
-- ---------------------------------------------------------------------
INSERT INTO staff (department_id, first_name, last_name, role, email, phone, hire_date) VALUES
 (1,'Kehinde','Afolabi','DOCTOR','k.afolabi@lagoscare.ng','+2348021000010','2020-02-03'),
 (1,'Uche','Nnamdi','DOCTOR','u.nnamdi@lagoscare.ng','+2348021000011','2021-06-14'),
 (1,'Zainab','Sule','DOCTOR','z.sule@lagoscare.ng','+2348021000012','2022-03-21'),
 (1,'Femi','Ogundipe','DOCTOR','f.ogundipe@lagoscare.ng','+2348021000013','2019-08-05'),
 (2,'Ifeoma','Chukwu','DOCTOR','i.chukwu@lagoscare.ng','+2348021000014','2021-01-18'),
 (2,'Bola','Fashola','DOCTOR','b.fashola@lagoscare.ng','+2348021000015','2023-04-10'),
 (2,'Musa','Garba','DOCTOR','m.garba@lagoscare.ng','+2348021000016','2020-10-26'),
 (2,'Nkechi','Ibe','DOCTOR','n.ibe@lagoscare.ng','+2348021000017','2022-09-12'),
 (6,'Olumide','Coker','DOCTOR','o.coker@lagoscare.ng','+2348021000018','2018-05-07'),
 (6,'Amina','Lawan','DOCTOR','a.lawan@lagoscare.ng','+2348021000019','2021-11-29'),
 (6,'Tobi','Ojo','DOCTOR','t.ojo@lagoscare.ng','+2348021000020','2023-01-09'),
 (6,'Chidi','Anyanwu','DOCTOR','c.anyanwu@lagoscare.ng','+2348021000021','2020-04-20'),
 (7,'Folake','Ayoola','DOCTOR','f.ayoola@lagoscare.ng','+2348021000022','2019-03-11'),
 (7,'Hauwa','Abubakar','DOCTOR','h.abubakar@lagoscare.ng','+2348021000023','2022-07-04'),
 (7,'Ebere','Okeke','DOCTOR','e.okeke@lagoscare.ng','+2348021000024','2021-10-01'),
 (7,'Ronke','Adewale','DOCTOR','r.adewale@lagoscare.ng','+2348021000025','2023-06-19');

INSERT INTO doctor (staff_id, specialty, mdcn_licence_no, consultation_fee)
SELECT s.staff_id,
       CASE s.department_id WHEN 1 THEN 'General Practice' WHEN 2 THEN 'Paediatrics'
                            WHEN 6 THEN 'Internal Medicine' ELSE 'Obstetrics & Gynaecology' END,
       CONCAT('MDCN/R/5', LPAD(s.staff_id, 4, '0')),
       CASE s.department_id WHEN 1 THEN 15000 WHEN 2 THEN 20000 WHEN 6 THEN 18000 ELSE 25000 END
FROM staff s
WHERE s.role = 'DOCTOR' AND s.staff_id NOT IN (SELECT staff_id FROM doctor);

INSERT INTO diagnosis_code (icd10_code, description) VALUES
 ('A01.0', 'Typhoid fever'),
 ('J18.9', 'Pneumonia, unspecified organism'),
 ('J45.9', 'Asthma, unspecified'),
 ('K29.7', 'Gastritis, unspecified'),
 ('N39.0', 'Urinary tract infection, site not specified'),
 ('M54.5', 'Low back pain'),
 ('R51',   'Headache'),
 ('D64.9', 'Anaemia, unspecified'),
 ('L30.9', 'Dermatitis, unspecified'),
 ('H10.9', 'Conjunctivitis, unspecified'),
 ('E66.9', 'Obesity, unspecified'),
 ('O21.0', 'Mild hyperemesis gravidarum'),
 ('Z00.0', 'General adult medical examination'),
 ('Z23',   'Encounter for immunisation');

-- Index → doctor (with the doctor's branch) and index → ICD-10 code
CREATE TABLE p2_doctor_map AS
SELECT ROW_NUMBER() OVER (ORDER BY d.staff_id) - 1 AS idx, d.staff_id, dp.branch_id
FROM doctor d JOIN staff s ON s.staff_id = d.staff_id
JOIN department dp ON dp.department_id = s.department_id;

CREATE TABLE p2_dx_map AS
SELECT ROW_NUMBER() OVER (ORDER BY icd10_code) - 1 AS idx, icd10_code
FROM diagnosis_code;

SET @doctor_count = (SELECT COUNT(*) FROM p2_doctor_map);   -- 20
SET @dx_count     = (SELECT COUNT(*) FROM p2_dx_map);       -- 20

-- ---------------------------------------------------------------------
-- 2. Patients (20,000)
-- ---------------------------------------------------------------------
INSERT INTO patient (hospital_no, first_name, last_name, date_of_birth, sex, phone, email,
                     address, blood_group, hmo_id, hmo_member_no, registered_at)
SELECT CONCAT('LC-', LPAD(n + 9, 6, '0')),
       ELT(1 + CRC32(CONCAT('fn', n)) % 20,
           'Adebayo','Chinedu','Fatima','Oluwaseun','Ngozi','Ibrahim','Funke','Emeka','Aisha','Tolu',
           'Chiamaka','Yusuf','Bimpe','Ikechukwu','Hadiza','Segun','Adaora','Kabiru','Yemisi','Obinna'),
       ELT(1 + CRC32(CONCAT('ln', n)) % 30,
           'Adeyemi','Okafor','Bello','Okonkwo','Abdullahi','Balogun','Eze','Mohammed','Ogunbiyi','Nwachukwu',
           'Ibrahim','Adekunle','Obi','Usman','Oyelaran','Chukwuma','Danjuma','Akinola','Onyeka','Salami',
           'Lawal','Okoro','Aliyu','Fagbemi','Uzor','Garba','Ogunleye','Nnaji','Shittu','Adeleke'),
       DATE_SUB('2026-01-01', INTERVAL CRC32(CONCAT('dob', n)) % 31000 DAY),
       IF(CRC32(CONCAT('sx', n)) % 2 = 0, 'M', 'F'),
       CONCAT('+23480', LPAD(50000000 + n, 8, '0')),
       IF(CRC32(CONCAT('em', n)) % 3 = 0, NULL, CONCAT('patient', n + 9, '@example.com')),
       ELT(1 + CRC32(CONCAT('ad', n)) % 10,
           'Ikeja, Lagos','Yaba, Lagos','Surulere, Lagos','Lekki, Lagos','Ajah, Lagos',
           'Ikorodu, Lagos','Gbagada, Lagos','Victoria Island','Festac, Lagos','Ogba, Lagos'),
       ELT(1 + CRC32(CONCAT('bg', n)) % 8, 'O+','O+','O+','A+','B+','O-','AB+','A-'),
       CASE WHEN CRC32(CONCAT('hm', n)) % 5 < 2 THEN NULL
            ELSE CRC32(CONCAT('hm', n)) % 5 - 1 END,
       CASE WHEN CRC32(CONCAT('hm', n)) % 5 < 2 THEN NULL
            ELSE CONCAT('MBR-', LPAD(n, 6, '0')) END,
       TIMESTAMP('2024-01-01') + INTERVAL CRC32(CONCAT('rg', n)) % 640 DAY
FROM p2_numbers
WHERE n < 20000;

SET @first_bulk_patient = (SELECT MIN(patient_id) FROM patient WHERE hospital_no = 'LC-000009');

-- ---------------------------------------------------------------------
-- 3. Appointments (120,000)
--    20 doctors x 6,000 slots each; 16 x 30-minute slots per day from 08:00,
--    every day from 12 Oct 2025 to 21 Oct 2026. Because each (doctor, slot)
--    pair is used once, the unique key uq_appt_doctor_slot is respected.
--    Status mix: 80% COMPLETED, 10% CANCELLED, 10% NO_SHOW.
-- ---------------------------------------------------------------------
INSERT INTO appointment (patient_id, doctor_id, branch_id, scheduled_start, scheduled_end,
                         status, reason, created_at)
SELECT @first_bulk_patient + CRC32(CONCAT('ap', x.n)) % 20000,
       dm.staff_id,
       dm.branch_id,
       x.start_at,
       x.start_at + INTERVAL 30 MINUTE,
       CASE WHEN CRC32(CONCAT('st', x.n)) % 100 < 80 THEN 'COMPLETED'
            WHEN CRC32(CONCAT('st', x.n)) % 100 < 90 THEN 'CANCELLED'
            ELSE 'NO_SHOW' END,
       ELT(1 + CRC32(CONCAT('rs', x.n)) % 10,
           'Fever','Cough','Headache','Body pains','Antenatal visit','Follow-up',
           'Blood pressure review','Stomach pain','Skin rash','Routine check-up'),
       x.start_at - INTERVAL (1 + CRC32(CONCAT('cr', x.n)) % 14) DAY
FROM (
  SELECT n,
         n % @doctor_count AS doc_idx,
         TIMESTAMP('2025-10-12 08:00:00')
           + INTERVAL ((n DIV @doctor_count) DIV 16) DAY
           + INTERVAL (((n DIV @doctor_count) % 16) * 30) MINUTE AS start_at
  FROM p2_numbers
  WHERE n < 120000
) x
JOIN p2_doctor_map dm ON dm.idx = x.doc_idx;

-- ---------------------------------------------------------------------
-- 4. Encounters: one for every bulk COMPLETED appointment
-- ---------------------------------------------------------------------
INSERT INTO encounter (appointment_id, started_at, ended_at, chief_complaint, clinical_notes)
SELECT a.appointment_id,
       a.scheduled_start + INTERVAL CRC32(CONCAT('es', a.appointment_id)) % 10 MINUTE,
       a.scheduled_start + INTERVAL (15 + CRC32(CONCAT('ee', a.appointment_id)) % 15) MINUTE,
       a.reason,
       NULL
FROM appointment a
WHERE a.status = 'COMPLETED'
  AND a.scheduled_start < '2026-10-22'
  AND a.scheduled_start >= '2025-10-12'
  AND NOT EXISTS (SELECT 1 FROM encounter e WHERE e.appointment_id = a.appointment_id);

SET @first_bulk_encounter = (SELECT MIN(e.encounter_id) FROM encounter e
                             JOIN appointment a ON a.appointment_id = e.appointment_id
                             WHERE a.scheduled_start >= '2025-10-12' AND a.scheduled_start < '2026-10-22');

-- ---------------------------------------------------------------------
-- 5. Diagnoses: one primary for every encounter, a secondary for ~40%
-- ---------------------------------------------------------------------
INSERT INTO encounter_diagnosis (encounter_id, icd10_code, is_primary)
SELECT e.encounter_id, dx.icd10_code, TRUE
FROM encounter e
JOIN p2_dx_map dx ON dx.idx = CRC32(CONCAT('dx', e.encounter_id)) % @dx_count
WHERE e.encounter_id >= @first_bulk_encounter;

INSERT INTO encounter_diagnosis (encounter_id, icd10_code, is_primary)
SELECT e.encounter_id, dx.icd10_code, FALSE
FROM encounter e
JOIN p2_dx_map dx
  ON dx.idx = (CRC32(CONCAT('dx', e.encounter_id)) % @dx_count
               + 1 + CRC32(CONCAT('d2', e.encounter_id)) % (@dx_count - 1)) % @dx_count
WHERE e.encounter_id >= @first_bulk_encounter
  AND CRC32(CONCAT('sec', e.encounter_id)) % 10 < 4;

-- ---------------------------------------------------------------------
-- 6. Laboratory: an order for ~40% of encounters; 97% have a result,
--    3% are still waiting (status ORDERED) — used by query Q5.
-- ---------------------------------------------------------------------
INSERT INTO lab_order (encounter_id, lab_test_id, ordered_at, status)
SELECT e.encounter_id,
       1 + CRC32(CONCAT('lt', e.encounter_id)) % 5,
       e.started_at + INTERVAL 10 MINUTE,
       IF(CRC32(CONCAT('lo', e.encounter_id)) % 100 < 3, 'ORDERED', 'COMPLETED')
FROM encounter e
WHERE e.encounter_id >= @first_bulk_encounter
  AND CRC32(CONCAT('lab', e.encounter_id)) % 10 < 4;

INSERT INTO lab_result (lab_order_id, result_value, is_abnormal, performed_by, resulted_at)
SELECT lo.lab_order_id,
       CAST(3 + CRC32(CONCAT('rv', lo.lab_order_id)) % 40 / 4 AS CHAR),
       CRC32(CONCAT('ab', lo.lab_order_id)) % 4 = 0,
       IF(a.branch_id = 1, 3, 8),                 -- Ngozi Eze (IKJ) / Segun Alabi (LEK)
       lo.ordered_at + INTERVAL (30 + CRC32(CONCAT('tt', lo.lab_order_id)) % 240) MINUTE
FROM lab_order lo
JOIN encounter e   ON e.encounter_id = lo.encounter_id
JOIN appointment a ON a.appointment_id = e.appointment_id
WHERE lo.encounter_id >= @first_bulk_encounter
  AND lo.status = 'COMPLETED';

-- ---------------------------------------------------------------------
-- 7. Billing: one invoice per encounter.
--    Payment plan per invoice: 70% PAID, 20% PART_PAID, 10% OPEN.
-- ---------------------------------------------------------------------
INSERT INTO invoice (encounter_id, issued_at, status)
SELECT e.encounter_id,
       e.ended_at + INTERVAL 10 MINUTE,
       CASE WHEN CRC32(CONCAT('pp', e.encounter_id)) % 10 < 7 THEN 'PAID'
            WHEN CRC32(CONCAT('pp', e.encounter_id)) % 10 < 9 THEN 'PART_PAID'
            ELSE 'OPEN' END
FROM encounter e
WHERE e.encounter_id >= @first_bulk_encounter;

-- Line 1: consultation fee (price snapshot from doctor)
INSERT INTO invoice_line (invoice_id, line_no, item_type, description, quantity, unit_price)
SELECT i.invoice_id, 1, 'CONSULTATION', CONCAT('Consultation - ', d.specialty), 1, d.consultation_fee
FROM invoice i
JOIN encounter e   ON e.encounter_id = i.encounter_id
JOIN appointment a ON a.appointment_id = e.appointment_id
JOIN doctor d      ON d.staff_id = a.doctor_id
WHERE e.encounter_id >= @first_bulk_encounter;

-- Line 2: lab test, where one was ordered (price snapshot from lab_test)
INSERT INTO invoice_line (invoice_id, line_no, item_type, description, quantity, unit_price)
SELECT i.invoice_id, 2, 'LAB', lt.name, 1, lt.price
FROM invoice i
JOIN lab_order lo ON lo.encounter_id = i.encounter_id
JOIN lab_test lt  ON lt.lab_test_id = lo.lab_test_id
WHERE i.encounter_id >= @first_bulk_encounter;

-- Line 3: medication for ~70% of visits (price snapshot from medication)
INSERT INTO invoice_line (invoice_id, line_no, item_type, description, quantity, unit_price)
SELECT i.invoice_id, 3, 'MEDICATION',
       CONCAT(m.generic_name, ' ', m.strength),
       IF(m.form = 'TABLET', 10 + CRC32(CONCAT('mq', i.invoice_id)) % 30, 1),
       m.unit_price
FROM invoice i
JOIN medication m ON m.medication_id = 1 + CRC32(CONCAT('md', i.invoice_id)) % 7
WHERE i.encounter_id >= @first_bulk_encounter
  AND CRC32(CONCAT('med', i.invoice_id)) % 10 < 7;

-- Invoice totals and the HMO share, used to create consistent payments
DROP TABLE IF EXISTS p2_invoice_split;
CREATE TABLE p2_invoice_split AS
SELECT i.invoice_id, i.status, i.issued_at, p.hmo_id,
       t.total,
       ROUND(t.total * COALESCE(h.coverage_percent, 0) / 100, 2) AS hmo_share
FROM invoice i
JOIN (SELECT invoice_id, SUM(quantity * unit_price) AS total
      FROM invoice_line GROUP BY invoice_id) t ON t.invoice_id = i.invoice_id
JOIN encounter e   ON e.encounter_id = i.encounter_id
JOIN appointment a ON a.appointment_id = e.appointment_id
JOIN patient p     ON p.patient_id = a.patient_id
LEFT JOIN hmo h    ON h.hmo_id = p.hmo_id
WHERE i.encounter_id >= @first_bulk_encounter;

-- HMO payment: for PAID and PART_PAID invoices of HMO patients
INSERT INTO payment (invoice_id, amount, method, reference, paid_at)
SELECT invoice_id, hmo_share, 'HMO', CONCAT('PAY-B-', invoice_id, '-H'), issued_at + INTERVAL 5 MINUTE
FROM p2_invoice_split
WHERE hmo_id IS NOT NULL AND status IN ('PAID', 'PART_PAID');

-- Patient payment: the remainder for PAID invoices; half the bill for
-- PART_PAID invoices of patients without an HMO
INSERT INTO payment (invoice_id, amount, method, reference, paid_at)
SELECT invoice_id,
       CASE WHEN status = 'PAID' THEN total - hmo_share ELSE ROUND(total / 2, 2) END,
       ELT(1 + CRC32(CONCAT('pm', invoice_id)) % 3, 'CASH', 'CARD', 'TRANSFER'),
       CONCAT('PAY-B-', invoice_id, '-P'),
       issued_at + INTERVAL 7 MINUTE
FROM p2_invoice_split
WHERE (status = 'PAID' AND total - hmo_share > 0)
   OR (status = 'PART_PAID' AND hmo_id IS NULL);

-- ---------------------------------------------------------------------
-- 8. Clean up helpers and refresh optimiser statistics
-- ---------------------------------------------------------------------
DROP TABLE p2_digits, p2_numbers, p2_doctor_map, p2_dx_map, p2_invoice_split;

ANALYZE TABLE patient, appointment, encounter, encounter_diagnosis,
              lab_order, lab_result, invoice, invoice_line, payment;

-- ---------------------------------------------------------------------
-- 9. Verification (capture as evidence: bulk_data_counts.png)
-- ---------------------------------------------------------------------
SELECT 'doctor' AS table_name, COUNT(*) AS row_count FROM doctor
UNION ALL SELECT 'patient',             COUNT(*) FROM patient
UNION ALL SELECT 'appointment',         COUNT(*) FROM appointment
UNION ALL SELECT 'encounter',           COUNT(*) FROM encounter
UNION ALL SELECT 'encounter_diagnosis', COUNT(*) FROM encounter_diagnosis
UNION ALL SELECT 'lab_order',           COUNT(*) FROM lab_order
UNION ALL SELECT 'lab_result',          COUNT(*) FROM lab_result
UNION ALL SELECT 'invoice',             COUNT(*) FROM invoice
UNION ALL SELECT 'invoice_line',        COUNT(*) FROM invoice_line
UNION ALL SELECT 'payment',             COUNT(*) FROM payment;

-- Every invoice status must agree with its balance (expect zero rows)
SELECT invoice_id, status, total_amount, amount_paid, balance_due
FROM v_invoice_balance
WHERE (status = 'PAID'      AND balance_due <> 0)
   OR (status = 'OPEN'      AND amount_paid <> 0)
   OR (status = 'PART_PAID' AND (amount_paid = 0 OR balance_due <= 0))
LIMIT 10;
