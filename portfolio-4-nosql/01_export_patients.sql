-- =====================================================================
-- LagosCare Clinics — Portfolio 4: Export PATIENTS from MySQL as
-- MongoDB documents (one JSON document per line, Extended JSON v2).
--
-- Run from the portfolio-4-nosql folder (Command Prompt):
--   mysql -u root -p -N -r lagoscare < 01_export_patients.sql > data\patients.json
--
-- Design notes
--   * The HMO is EMBEDDED (a patient has at most one plan; it is always
--     shown with the patient).
--   * Encounters are NOT embedded: a patient's visits grow without limit,
--     and MongoDB documents are capped at 16 MB. Encounters reference the
--     patient instead (see 01_export_encounters.sql).
--   * visit_summary is a COMPUTED field (computed pattern): pre-calculated
--     so the front desk does not have to count encounters on every search.
--     It must be updated whenever an encounter is added (05_updates.js).
--   * allergies: a free-form array present only for some patients — a field
--     the relational schema never had. Values are fictional.
-- =====================================================================
USE lagoscare;

SELECT JSON_MERGE_PATCH('{}', JSON_OBJECT(
  '_id',         p.patient_id,
  'hospital_no', p.hospital_no,
  'name',        JSON_OBJECT('first', p.first_name, 'last', p.last_name),
  'date_of_birth', JSON_OBJECT('$date', DATE_FORMAT(p.date_of_birth, '%Y-%m-%dT00:00:00Z')),
  'sex',         p.sex,
  'blood_group', p.blood_group,
  'contact',     JSON_MERGE_PATCH('{}', JSON_OBJECT('phone', p.phone, 'email', p.email, 'address', p.address)),
  'hmo',         IF(p.hmo_id IS NULL, NULL,
                    JSON_OBJECT('hmo_id', h.hmo_id, 'name', h.name, 'member_no', p.hmo_member_no,
                                'coverage_percent', JSON_OBJECT('$numberDecimal', CAST(h.coverage_percent AS CHAR)))),
  'allergies',   CASE CRC32(CONCAT('al', p.patient_id)) % 20
                   WHEN 0 THEN JSON_ARRAY('Penicillin')
                   WHEN 1 THEN JSON_ARRAY('Sulfonamides')
                   WHEN 2 THEN JSON_ARRAY('Penicillin', 'Peanuts')
                   ELSE NULL END,
  'registered_at', JSON_OBJECT('$date', DATE_FORMAT(p.registered_at - INTERVAL 1 HOUR, '%Y-%m-%dT%H:%i:%sZ')),
  'visit_summary', IF(v.visits IS NULL, JSON_OBJECT('visits', 0), JSON_OBJECT(
                     'visits',     v.visits,
                     'last_visit', JSON_OBJECT('$date', DATE_FORMAT(v.last_visit - INTERVAL 1 HOUR, '%Y-%m-%dT%H:%i:%sZ'))))
)) AS doc
FROM   patient p
LEFT JOIN hmo h ON h.hmo_id = p.hmo_id
LEFT JOIN (SELECT a.patient_id, COUNT(*) AS visits, MAX(e.started_at) AS last_visit
           FROM   encounter e JOIN appointment a ON a.appointment_id = e.appointment_id
           GROUP  BY a.patient_id) v ON v.patient_id = p.patient_id
ORDER  BY p.patient_id;
