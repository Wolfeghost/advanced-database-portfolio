-- =====================================================================
-- LagosCare Clinics — Portfolio 4: Export PHARMACY STOCK as MongoDB
-- documents. Used by the multi-document transaction demo (05_updates.js).
--
--   mysql -u root -p -N -r lagoscare < 01_export_stock.sql > data\pharmacy_stock.json
--
-- _id is a readable compound key "<branch>-<medication_id>", e.g. "LEK-5",
-- equivalent to the composite primary key (branch_id, medication_id).
-- =====================================================================
USE lagoscare;

SELECT JSON_OBJECT(
  '_id',    CONCAT(b.branch_code, '-', m.medication_id),
  'branch', b.branch_code,
  'medication', JSON_OBJECT('medication_id', m.medication_id,
                            'name',          CONCAT(m.generic_name, ' ', m.strength),
                            'form',          m.form,
                            'unit_price',    JSON_OBJECT('$numberDecimal', CAST(m.unit_price AS CHAR))),
  'quantity_on_hand', ps.quantity_on_hand,
  'reorder_level',    ps.reorder_level
) AS doc
FROM   pharmacy_stock ps
JOIN   branch b     ON b.branch_id     = ps.branch_id
JOIN   medication m ON m.medication_id = ps.medication_id
ORDER  BY b.branch_code, m.medication_id;
