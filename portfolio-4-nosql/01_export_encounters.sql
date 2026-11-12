-- =====================================================================
-- LagosCare Clinics — Portfolio 4: Export ENCOUNTERS from MySQL as
-- MongoDB documents (one JSON document per line, Extended JSON v2).
--
-- Each consultation becomes ONE self-contained document: patient and
-- doctor snapshots, vitals, diagnoses, prescriptions, lab orders with
-- results, clinical notes and a billing summary — data that needs a
-- 9-table join in MySQL.
--
-- Run from the portfolio-4-nosql folder (Command Prompt):
--   mysql -u root -p -N -r lagoscare < 01_export_encounters.sql > data\encounters.json
--   (-N = no column header, -r = raw output so JSON is not escaped)
--
-- Conventions used in the output:
--   * dates  -> {"$date": "...Z"}  (MongoDB stores dates in UTC; Lagos is
--               UTC+1 with no daylight saving, so 1 hour is subtracted)
--   * money  -> {"$numberDecimal": "..."}  (exact decimal, never float)
--   * null-valued fields are omitted (JSON_MERGE_PATCH with '{}' drops
--     them), so each document only carries the fields that apply to it.
--
-- Vitals were never stored in the relational model (Portfolio 1 listed
-- them as a motivation for this portfolio). They are generated here
-- deterministically from CRC32(encounter_id), with a different SHAPE per
-- visit type: antenatal visits record gestation and fetal heart rate,
-- paediatric visits record respiratory rate but no blood pressure.
--
-- The Portfolio 2 generator assigns patients to doctors at random, so a
-- few O&G appointments belong to male patients. Those are exported as
-- GENERAL visits without pregnancy fields.
-- =====================================================================
USE lagoscare;
SET SESSION group_concat_max_len = 1000000;

SELECT JSON_MERGE_PATCH('{}', JSON_OBJECT(
  '_id',            e.encounter_id,
  'appointment_id', a.appointment_id,
  'visit_type',     CASE d.specialty
                      WHEN 'Obstetrics & Gynaecology' THEN IF(p.sex = 'F', 'ANTENATAL', 'GENERAL')
                      WHEN 'Paediatrics'              THEN 'PAEDIATRIC'
                      WHEN 'Internal Medicine'        THEN 'MEDICAL'
                      ELSE 'GENERAL' END,
  'branch',  JSON_OBJECT('code', b.branch_code, 'name', b.name),
  'doctor',  JSON_OBJECT('staff_id',  s.staff_id,
                         'name',      CONCAT('Dr ', s.first_name, ' ', s.last_name),
                         'specialty', d.specialty),
  -- Extended reference: a small, rarely-changing copy of the patient.
  -- The full patient record lives in the patients collection.
  'patient', JSON_OBJECT('patient_id',  p.patient_id,
                         'hospital_no', p.hospital_no,
                         'name',        CONCAT(p.first_name, ' ', p.last_name),
                         'sex',         p.sex,
                         'age_at_visit', TIMESTAMPDIFF(YEAR, p.date_of_birth, e.started_at),
                         'hmo',         h.name),
  'started_at', JSON_OBJECT('$date', DATE_FORMAT(e.started_at - INTERVAL 1 HOUR, '%Y-%m-%dT%H:%i:%sZ')),
  'ended_at',   IF(e.ended_at IS NULL, NULL,
                   JSON_OBJECT('$date', DATE_FORMAT(e.ended_at - INTERVAL 1 HOUR, '%Y-%m-%dT%H:%i:%sZ'))),
  'chief_complaint', e.chief_complaint,

  -- Vitals: polymorphic sub-document (shape depends on visit type)
  'vitals', JSON_MERGE_PATCH('{}', JSON_OBJECT(
      'temperature_c', ROUND(36.2 + (CRC32(CONCAT('t', e.encounter_id)) % 20) / 10
                             + IF(dx.icd10_code IN ('B54', 'A01.0', 'J18.9'), 1.2, 0), 1),
      'pulse_bpm',     60 + CRC32(CONCAT('pu', e.encounter_id)) % 45,
      'spo2_pct',      94 + CRC32(CONCAT('o2', e.encounter_id)) % 6,
      'weight_kg',     IF(d.specialty = 'Paediatrics',
                          ROUND(8 + (CRC32(CONCAT('w', e.encounter_id)) % 300) / 10, 1),
                          ROUND(52 + (CRC32(CONCAT('w', e.encounter_id)) % 450) / 10, 1)),
      'bp', IF(d.specialty = 'Paediatrics', NULL, JSON_OBJECT(
              'systolic',  105 + CRC32(CONCAT('sy', e.encounter_id)) % 35 + IF(dx.icd10_code = 'I10', 30, 0),
              'diastolic',  65 + CRC32(CONCAT('di', e.encounter_id)) % 20 + IF(dx.icd10_code = 'I10', 18, 0))),
      'resp_rate_pm',  IF(d.specialty = 'Paediatrics', 20 + CRC32(CONCAT('rr', e.encounter_id)) % 18, NULL),
      'gestational_age_weeks',
                       IF(d.specialty = 'Obstetrics & Gynaecology' AND p.sex = 'F', 8 + CRC32(CONCAT('ga', e.encounter_id)) % 32, NULL),
      'fundal_height_cm',
                       IF(d.specialty = 'Obstetrics & Gynaecology' AND p.sex = 'F'
                          AND 8 + CRC32(CONCAT('ga', e.encounter_id)) % 32 >= 20,
                          8 + CRC32(CONCAT('ga', e.encounter_id)) % 32 - 1 + CRC32(CONCAT('fh', e.encounter_id)) % 3, NULL),
      'fetal_heart_rate_bpm',
                       IF(d.specialty = 'Obstetrics & Gynaecology' AND p.sex = 'F'
                          AND 8 + CRC32(CONCAT('ga', e.encounter_id)) % 32 >= 12,
                          120 + CRC32(CONCAT('fr', e.encounter_id)) % 40, NULL))),

  -- Embedded arrays: bounded, always read with the encounter
  'diagnoses', COALESCE((
      SELECT JSON_ARRAYAGG(JSON_OBJECT('icd10', ed.icd10_code,
                                       'description', dc.description,
                                       'primary', ed.is_primary = 1))
      FROM   encounter_diagnosis ed
      JOIN   diagnosis_code dc ON dc.icd10_code = ed.icd10_code
      WHERE  ed.encounter_id = e.encounter_id), JSON_ARRAY()),

  'prescriptions', COALESCE((
      SELECT JSON_ARRAYAGG(JSON_OBJECT(
               'prescription_id', rx.prescription_id,
               'status',          rx.status,
               'items', (SELECT JSON_ARRAYAGG(JSON_OBJECT(
                                  'medication',    CONCAT(m.generic_name, ' ', m.strength),
                                  'form',          m.form,
                                  'dose',          ri.dosage,
                                  'frequency',     ri.frequency,
                                  'duration_days', ri.duration_days,
                                  'quantity',      ri.quantity))
                         FROM prescription_item ri
                         JOIN medication m ON m.medication_id = ri.medication_id
                         WHERE ri.prescription_id = rx.prescription_id)))
      FROM   prescription rx
      WHERE  rx.encounter_id = e.encounter_id), JSON_ARRAY()),

  'lab_orders', COALESCE((
      SELECT JSON_ARRAYAGG(JSON_MERGE_PATCH('{}', JSON_OBJECT(
               'lab_order_id', lo.lab_order_id,
               'test_code',    lt.test_code,
               'test_name',    lt.name,
               'status',       lo.status,
               'ordered_at',   JSON_OBJECT('$date', DATE_FORMAT(lo.ordered_at - INTERVAL 1 HOUR, '%Y-%m-%dT%H:%i:%sZ')),
               'result', IF(lr.lab_order_id IS NULL, NULL, JSON_MERGE_PATCH('{}', JSON_OBJECT(
                            'value',           lr.result_value,
                            'unit',            lt.unit,
                            'reference_range', lt.reference_range,
                            'abnormal',        lr.is_abnormal = 1,
                            'resulted_at',     JSON_OBJECT('$date', DATE_FORMAT(lr.resulted_at - INTERVAL 1 HOUR, '%Y-%m-%dT%H:%i:%sZ')),
                            'performed_by',    lr.performed_by))))))
      FROM   lab_order lo
      JOIN   lab_test lt        ON lt.lab_test_id  = lo.lab_test_id
      LEFT JOIN lab_result lr   ON lr.lab_order_id = lo.lab_order_id
      WHERE  lo.encounter_id = e.encounter_id), JSON_ARRAY()),

  -- Free-text notes (seed notes kept; generated ones for bulk encounters)
  'notes', COALESCE(e.clinical_notes,
             CONCAT(ELT(1 + CRC32(CONCAT('n1', e.encounter_id)) % 4,
                        'Patient alert and oriented. ', 'Looks unwell but stable. ',
                        'Comfortable at rest. ', 'Mildly dehydrated. '),
                    'Presented with ', LOWER(e.chief_complaint), '. ',
                    CASE dx.icd10_code
                      WHEN 'B54'   THEN 'Malaria suspected; MPS requested; started on ACT. '
                      WHEN 'A01.0' THEN 'Step-ladder fever; typhoid considered; Widal not relied on. '
                      WHEN 'I10'   THEN 'Blood pressure elevated; lifestyle advice given; review in 4 weeks. '
                      WHEN 'E11.9' THEN 'Polyuria and polydipsia; glucose monitoring discussed. '
                      WHEN 'Z34.9' THEN 'Routine antenatal care; folic acid continued. '
                      WHEN 'J06.9' THEN 'Throat inflamed; chest clear; symptomatic treatment. '
                      WHEN 'J45.9' THEN 'Expiratory wheeze; inhaler technique reviewed. '
                      ELSE 'Examined; plan discussed with patient. ' END,
                    ELT(1 + CRC32(CONCAT('n2', e.encounter_id)) % 3,
                        'Return if symptoms worsen.', 'Follow-up in two weeks.', 'Discharged home.'))),

  -- Billing summary: a read-only SNAPSHOT for the clinician's view. The
  -- source of truth for money stays in MySQL (see README, section 5).
  -- (Per-invoice sums are used rather than v_invoice_balance, because a
  -- correlated lookup on that view would re-aggregate every invoice for
  -- every exported row.)
  'billing', (SELECT JSON_OBJECT(
                'invoice_id', i.invoice_id,
                'status',     i.status,
                'total',      JSON_OBJECT('$numberDecimal', CAST(
                                (SELECT COALESCE(SUM(il.quantity * il.unit_price), 0)
                                 FROM invoice_line il WHERE il.invoice_id = i.invoice_id) AS CHAR)),
                'paid',       JSON_OBJECT('$numberDecimal', CAST(
                                (SELECT COALESCE(SUM(pm.amount), 0)
                                 FROM payment pm WHERE pm.invoice_id = i.invoice_id) AS CHAR)))
              FROM invoice i WHERE i.encounter_id = e.encounter_id)
)) AS doc
FROM   encounter e
JOIN   appointment a ON a.appointment_id = e.appointment_id
JOIN   patient p     ON p.patient_id     = a.patient_id
LEFT JOIN hmo h      ON h.hmo_id         = p.hmo_id
JOIN   doctor d      ON d.staff_id       = a.doctor_id
JOIN   staff s       ON s.staff_id       = d.staff_id
JOIN   branch b      ON b.branch_id      = a.branch_id
LEFT JOIN encounter_diagnosis dx ON dx.encounter_id = e.encounter_id AND dx.is_primary = 1
ORDER  BY e.encounter_id;
