-- =====================================================================
-- LagosCare Clinics — Portfolio 1: Sample data
-- All people, HMOs and licence numbers are fictional.
-- Bulk data for performance testing is generated in Portfolio 2.
-- =====================================================================
USE lagoscare;

INSERT INTO branch (branch_code, name, address, phone) VALUES
 ('IKJ', 'LagosCare Ikeja', '14 Allen Avenue, Ikeja',          '+2348011110001'),
 ('LEK', 'LagosCare Lekki', '7 Admiralty Way, Lekki Phase 1',  '+2348011110002');

INSERT INTO department (branch_id, name) VALUES
 (1, 'General Medicine'), (1, 'Paediatrics'), (1, 'Laboratory'), (1, 'Pharmacy'), (1, 'Front Desk'),
 (2, 'Internal Medicine'), (2, 'Obstetrics & Gynaecology'), (2, 'Laboratory'), (2, 'Pharmacy');

INSERT INTO staff (department_id, first_name, last_name, role, email, phone, hire_date) VALUES
 (1, 'Adaeze',     'Okonkwo',  'DOCTOR',        'a.okonkwo@lagoscare.ng', '+2348021000001', '2021-03-01'),
 (2, 'Tunde',      'Bakare',   'DOCTOR',        't.bakare@lagoscare.ng',  '+2348021000002', '2020-07-15'),
 (3, 'Ngozi',      'Eze',      'LAB_SCIENTIST', 'n.eze@lagoscare.ng',     '+2348021000003', '2022-01-10'),
 (4, 'Ibrahim',    'Musa',     'PHARMACIST',    'i.musa@lagoscare.ng',    '+2348021000004', '2021-09-01'),
 (5, 'Funmi',      'Adeyemi',  'RECEPTIONIST',  'f.adeyemi@lagoscare.ng', '+2348021000005', '2023-02-20'),
 (6, 'Chukwuemeka','Obi',      'DOCTOR',        'c.obi@lagoscare.ng',     '+2348021000006', '2019-11-04'),
 (7, 'Aisha',      'Bello',    'DOCTOR',        'a.bello@lagoscare.ng',   '+2348021000007', '2022-05-16'),
 (8, 'Segun',      'Alabi',    'LAB_SCIENTIST', 's.alabi@lagoscare.ng',   '+2348021000008', '2023-08-01'),
 (1, 'Bisi',       'Ogunleye', 'NURSE',         'b.ogunleye@lagoscare.ng','+2348021000009', '2021-04-12');

INSERT INTO doctor (staff_id, specialty, mdcn_licence_no, consultation_fee) VALUES
 (1, 'General Practice',          'MDCN/R/40112', 15000.00),
 (2, 'Paediatrics',               'MDCN/R/38765', 20000.00),
 (6, 'Internal Medicine',         'MDCN/R/35590', 18000.00),
 (7, 'Obstetrics & Gynaecology',  'MDCN/R/41233', 25000.00);

INSERT INTO hmo (name, phone, coverage_percent) VALUES
 ('Harbour Health HMO', '+2348031000001', 80.00),
 ('Lagoon Care HMO',    '+2348031000002', 70.00),
 ('Crestline HMO',      '+2348031000003', 90.00);

INSERT INTO patient (hospital_no, first_name, last_name, date_of_birth, sex, phone, email, address, blood_group, hmo_id, hmo_member_no) VALUES
 ('LC-000001', 'Oluwaseun', 'Adebayo', '1988-04-12', 'M', '+2348041000001', 'seun.adebayo@example.com', 'Ogba, Lagos',      'O+',  1,    'HH-10021'),
 ('LC-000002', 'Chiamaka',  'Nwosu',   '1995-09-03', 'F', '+2348041000002', 'chiamaka.n@example.com',   'Yaba, Lagos',      'A+',  NULL, NULL),
 ('LC-000003', 'Emeka',     'Okafor',  '2019-02-20', 'M', '+2348041000003', NULL,                       'Maryland, Lagos',  'B+',  2,    'LG-55012'),
 ('LC-000004', 'Halima',    'Yusuf',   '1990-11-30', 'F', '+2348041000004', 'halima.y@example.com',     'Ajah, Lagos',      'O-',  3,    'CR-77001'),
 ('LC-000005', 'Kunle',     'Ajayi',   '1972-06-15', 'M', '+2348041000005', 'kunle.ajayi@example.com',  'Victoria Island',  'AB+', NULL, NULL),
 ('LC-000006', 'Grace',     'Etim',    '1985-01-08', 'F', '+2348041000006', 'grace.etim@example.com',   'Ikeja GRA, Lagos', 'A-',  1,    'HH-10088'),
 ('LC-000007', 'Yetunde',   'Lawal',   '2016-07-22', 'F', '+2348041000007', NULL,                       'Surulere, Lagos',  'O+',  NULL, NULL),
 ('LC-000008', 'Daniel',    'Udo',     '1979-03-05', 'M', '+2348041000008', 'daniel.udo@example.com',   'Lekki, Lagos',     'B-',  2,    'LG-55100');

INSERT INTO diagnosis_code (icd10_code, description) VALUES
 ('B54',   'Unspecified malaria'),
 ('I10',   'Essential (primary) hypertension'),
 ('E11.9', 'Type 2 diabetes mellitus without complications'),
 ('J06.9', 'Acute upper respiratory infection, unspecified'),
 ('A09',   'Infectious gastroenteritis and colitis, unspecified'),
 ('Z34.9', 'Supervision of normal pregnancy, unspecified');

INSERT INTO medication (generic_name, form, strength, unit_price) VALUES
 ('Artemether/Lumefantrine', 'TABLET', '20mg/120mg', 150.00),
 ('Paracetamol',             'TABLET', '500mg',       20.00),
 ('Amlodipine',              'TABLET', '5mg',        100.00),
 ('Metformin',               'TABLET', '500mg',       60.00),
 ('Amoxicillin',             'SYRUP',  '125mg/5ml', 2500.00),
 ('Oral Rehydration Salts',  'POWDER', '20.5g',      300.00),
 ('Folic Acid',              'TABLET', '5mg',         10.00);

INSERT INTO pharmacy_stock (branch_id, medication_id, quantity_on_hand, reorder_level) VALUES
 (1, 1, 480, 100), (1, 2, 2000, 300), (1, 3, 600, 120), (1, 4, 900, 150), (1, 5, 40, 10), (1, 6, 150, 30), (1, 7, 1000, 200),
 (2, 1, 360, 100), (2, 2, 1500, 300), (2, 3, 450, 120), (2, 4, 700, 150), (2, 5, 25, 10), (2, 6, 90, 30),  (2, 7, 1200, 200);

INSERT INTO lab_test (test_code, name, unit, reference_range, price) VALUES
 ('MPS', 'Malaria Parasite Smear',  NULL,     'Not seen',  3000.00),
 ('FBC', 'Full Blood Count',        NULL,     'See report',8000.00),
 ('FBS', 'Fasting Blood Sugar',     'mmol/L', '3.9-5.5',   2500.00),
 ('PCV', 'Packed Cell Volume',      '%',      '36-50',     1500.00),
 ('URN', 'Urinalysis',              NULL,     'See report',2000.00);

-- Appointments: 4 completed, 1 cancelled, 2 upcoming
INSERT INTO appointment (patient_id, doctor_id, branch_id, scheduled_start, scheduled_end, status, reason) VALUES
 (1, 1, 1, '2026-11-02 09:00:00', '2026-11-02 09:30:00', 'COMPLETED', 'Fever and body aches'),
 (3, 2, 1, '2026-11-02 10:00:00', '2026-11-02 10:30:00', 'COMPLETED', 'Cough and runny nose'),
 (4, 7, 2, '2026-11-03 11:00:00', '2026-11-03 11:30:00', 'COMPLETED', 'Antenatal visit'),
 (5, 6, 2, '2026-11-04 09:00:00', '2026-11-04 09:30:00', 'COMPLETED', 'Blood pressure review'),
 (2, 1, 1, '2026-11-05 14:00:00', '2026-11-05 14:30:00', 'CANCELLED', 'Routine check-up'),
 (6, 1, 1, '2026-11-16 09:00:00', '2026-11-16 09:30:00', 'BOOKED',    'Headache'),
 (8, 6, 2, '2026-11-16 10:00:00', '2026-11-16 10:30:00', 'BOOKED',    'Follow-up');

INSERT INTO encounter (appointment_id, started_at, ended_at, chief_complaint, clinical_notes) VALUES
 (1, '2026-11-02 09:05:00', '2026-11-02 09:28:00', 'Fever for 3 days',           'Temp 38.6C. MPS requested.'),
 (2, '2026-11-02 10:02:00', '2026-11-02 10:20:00', 'Productive cough, 5 days',   'Chest clear. Likely viral URTI with secondary infection risk.'),
 (3, '2026-11-03 11:04:00', '2026-11-03 11:35:00', 'Routine antenatal, 20 weeks','Fundal height appropriate. PCV requested.'),
 (4, '2026-11-04 09:03:00', '2026-11-04 09:25:00', 'BP review, polyuria',        'BP 158/96. FBS requested.');

INSERT INTO encounter_diagnosis (encounter_id, icd10_code, is_primary) VALUES
 (1, 'B54',   TRUE),
 (2, 'J06.9', TRUE),
 (3, 'Z34.9', TRUE),
 (4, 'I10',   TRUE),
 (4, 'E11.9', FALSE);

INSERT INTO prescription (encounter_id, prescribed_at, status) VALUES
 (1, '2026-11-02 09:27:00', 'DISPENSED'),
 (2, '2026-11-02 10:19:00', 'DISPENSED'),
 (3, '2026-11-03 11:34:00', 'DISPENSED'),
 (4, '2026-11-04 09:24:00', 'ISSUED');

INSERT INTO prescription_item (prescription_id, medication_id, dosage, frequency, duration_days, quantity) VALUES
 (1, 1, '4 tablets', 'Twice daily',     3,  24),
 (1, 2, '2 tablets', 'Three times daily',3, 18),
 (2, 5, '5ml',       'Three times daily',5,  1),
 (3, 7, '1 tablet',  'Once daily',      30, 30),
 (4, 3, '1 tablet',  'Once daily',      30, 30),
 (4, 4, '1 tablet',  'Twice daily',     30, 60);

INSERT INTO lab_order (encounter_id, lab_test_id, ordered_at, status) VALUES
 (1, 1, '2026-11-02 09:15:00', 'COMPLETED'),
 (1, 2, '2026-11-02 09:15:00', 'COMPLETED'),
 (3, 4, '2026-11-03 11:20:00', 'COMPLETED'),
 (4, 3, '2026-11-04 09:15:00', 'COMPLETED'),
 (3, 5, '2026-11-03 11:20:00', 'ORDERED');

INSERT INTO lab_result (lab_order_id, result_value, is_abnormal, performed_by, resulted_at) VALUES
 (1, 'Seen (++)', TRUE,  3, '2026-11-02 09:45:00'),
 (2, 'WBC 7.2, Hb 13.1', FALSE, 3, '2026-11-02 10:30:00'),
 (3, '34',        TRUE,  8, '2026-11-03 12:10:00'),
 (4, '7.8',       TRUE,  8, '2026-11-04 10:00:00');

-- Invoices (one per encounter)
INSERT INTO invoice (encounter_id, issued_at, status) VALUES
 (1, '2026-11-02 09:50:00', 'PAID'),
 (2, '2026-11-02 10:25:00', 'PART_PAID'),
 (3, '2026-11-03 12:15:00', 'PAID'),
 (4, '2026-11-04 10:05:00', 'OPEN');

INSERT INTO invoice_line (invoice_id, line_no, item_type, description, quantity, unit_price) VALUES
 (1, 1, 'CONSULTATION', 'Consultation - General Practice',     1, 15000.00),
 (1, 2, 'LAB',          'Malaria Parasite Smear',              1,  3000.00),
 (1, 3, 'LAB',          'Full Blood Count',                    1,  8000.00),
 (1, 4, 'MEDICATION',   'Artemether/Lumefantrine 20mg/120mg', 24,   150.00),
 (1, 5, 'MEDICATION',   'Paracetamol 500mg',                  18,    20.00),
 (2, 1, 'CONSULTATION', 'Consultation - Paediatrics',          1, 20000.00),
 (2, 2, 'MEDICATION',   'Amoxicillin 125mg/5ml syrup',         1,  2500.00),
 (3, 1, 'CONSULTATION', 'Consultation - Obstetrics & Gynaecology', 1, 25000.00),
 (3, 2, 'LAB',          'Packed Cell Volume',                  1,  1500.00),
 (3, 3, 'MEDICATION',   'Folic Acid 5mg',                     30,    10.00),
 (4, 1, 'CONSULTATION', 'Consultation - Internal Medicine',    1, 18000.00),
 (4, 2, 'LAB',          'Fasting Blood Sugar',                 1,  2500.00),
 (4, 3, 'MEDICATION',   'Amlodipine 5mg',                     30,   100.00),
 (4, 4, 'MEDICATION',   'Metformin 500mg',                    60,    60.00);

-- Invoice 1 total 29,960 : HMO 80% + patient cash 20%
-- Invoice 2 total 22,500 : HMO 70% paid, patient balance outstanding
-- Invoice 3 total 26,800 : HMO 90% + patient transfer 10%
-- Invoice 4 total 27,100 : no payment yet
INSERT INTO payment (invoice_id, amount, method, reference, paid_at) VALUES
 (1, 23968.00, 'HMO',      'PAY-2026-000001', '2026-11-02 09:55:00'),
 (1,  5992.00, 'CASH',     'PAY-2026-000002', '2026-11-02 09:56:00'),
 (2, 15750.00, 'HMO',      'PAY-2026-000003', '2026-11-02 10:30:00'),
 (3, 24120.00, 'HMO',      'PAY-2026-000004', '2026-11-03 12:20:00'),
 (3,  2680.00, 'TRANSFER', 'PAY-2026-000005', '2026-11-03 12:22:00');

-- ---------------------------------------------------------------------
-- Quick verification (capture this output as evidence)
-- ---------------------------------------------------------------------
SELECT 'branch' AS table_name, COUNT(*) AS row_count FROM branch
UNION ALL SELECT 'department', COUNT(*) FROM department
UNION ALL SELECT 'staff', COUNT(*) FROM staff
UNION ALL SELECT 'doctor', COUNT(*) FROM doctor
UNION ALL SELECT 'patient', COUNT(*) FROM patient
UNION ALL SELECT 'appointment', COUNT(*) FROM appointment
UNION ALL SELECT 'encounter', COUNT(*) FROM encounter
UNION ALL SELECT 'prescription_item', COUNT(*) FROM prescription_item
UNION ALL SELECT 'lab_order', COUNT(*) FROM lab_order
UNION ALL SELECT 'invoice_line', COUNT(*) FROM invoice_line
UNION ALL SELECT 'payment', COUNT(*) FROM payment;

SELECT * FROM v_invoice_balance;
