-- =====================================================================
-- LagosCare Clinics — Portfolio 3: COMMIT, ROLLBACK, atomicity, SAVEPOINT
-- Single session. Run AFTER 01_setup.sql.
--
-- Demo 2.3 contains a statement that FAILS ON PURPOSE. To run the whole
-- file in one go:
--   * Workbench: toggle "Continue on SQL script error" (the icon next to the
--     lightning bolt), or run the file statement by statement (Ctrl+Enter).
--   * Command line: mysql -u root -p --force --raw -vvv lagoscare
--                         < 02_commit_rollback.sql > evidence\commit_rollback.txt
-- =====================================================================
USE lagoscare;
CALL sp_p3_reset_demo();

-- =====================================================================
-- Demo 2.1  COMMIT — dispensing a prescription (all-or-nothing unit)
-- A doctor at Lekki (branch 2) prescribes amlodipine x30 and metformin x60
-- for the patient seen in encounter 4. The pharmacist dispenses it.
-- =====================================================================
SELECT '== 2.1 COMMIT: dispense prescription ==' AS demo;

INSERT INTO prescription (encounter_id, status) VALUES (4, 'ISSUED');
SET @rx_ok = LAST_INSERT_ID();
INSERT INTO prescription_item (prescription_id, medication_id, dosage, frequency, duration_days, quantity) VALUES
 (@rx_ok, 3, '1 tablet', 'Once daily',  30, 30),
 (@rx_ok, 4, '1 tablet', 'Twice daily', 30, 60);

SELECT 'before' AS moment, medication_id, quantity_on_hand
FROM   pharmacy_stock WHERE branch_id = 2 AND medication_id IN (3, 4);

CALL sp_dispense_prescription(@rx_ok, 2);

SELECT 'after' AS moment, medication_id, quantity_on_hand          -- 420 and 640
FROM   pharmacy_stock WHERE branch_id = 2 AND medication_id IN (3, 4);
SELECT prescription_id, status FROM prescription WHERE prescription_id = @rx_ok;  -- DISPENSED

-- Dispensing the same prescription again is refused (no double dispensing)
CALL sp_dispense_prescription(@rx_ok, 2);   -- ERROR: Prescription is not in ISSUED status

-- =====================================================================
-- Demo 2.2  Explicit ROLLBACK — a pharmacist starts a stock adjustment
-- and then cancels it. Inside the transaction the change is visible to
-- this session; after ROLLBACK it is as if it never happened.
-- =====================================================================
SELECT '== 2.2 ROLLBACK: cancelled stock adjustment ==' AS demo;

START TRANSACTION;
UPDATE pharmacy_stock SET quantity_on_hand = quantity_on_hand - 100
WHERE  branch_id = 1 AND medication_id = 2;
SELECT 'inside transaction' AS moment, quantity_on_hand            -- 1900
FROM   pharmacy_stock WHERE branch_id = 1 AND medication_id = 2;
ROLLBACK;
SELECT 'after ROLLBACK' AS moment, quantity_on_hand                -- 2000
FROM   pharmacy_stock WHERE branch_id = 1 AND medication_id = 2;

-- =====================================================================
-- Demo 2.3  A failed statement does NOT roll back the transaction in MySQL.
-- Two stock updates are written by hand. The first succeeds; the second
-- breaks the CHECK constraint chk_stock_qty (Amoxicillin syrup at Lekki has
-- only 25 bottles). Only the failed STATEMENT is undone — the first update
-- is still pending, so the application must ROLLBACK explicitly. This is
-- why the stored procedures use an EXIT HANDLER that calls ROLLBACK.
-- =====================================================================
SELECT '== 2.3 Statement error inside a transaction ==' AS demo;

START TRANSACTION;
UPDATE pharmacy_stock SET quantity_on_hand = quantity_on_hand - 10
WHERE  branch_id = 2 AND medication_id = 2;                        -- OK: 1500 -> 1490
UPDATE pharmacy_stock SET quantity_on_hand = quantity_on_hand - 100
WHERE  branch_id = 2 AND medication_id = 5;                        -- ERROR 3819: chk_stock_qty violated
SELECT 'after the error, still inside transaction' AS moment, medication_id, quantity_on_hand
FROM   pharmacy_stock WHERE branch_id = 2 AND medication_id IN (2, 5);   -- 1490 and 25
ROLLBACK;
SELECT 'after ROLLBACK' AS moment, medication_id, quantity_on_hand
FROM   pharmacy_stock WHERE branch_id = 2 AND medication_id IN (2, 5);   -- 1500 and 25

-- =====================================================================
-- Demo 2.4  Atomicity through the procedure — a prescription whose second
-- item cannot be filled. Nothing is dispensed: stock is unchanged and the
-- prescription stays ISSUED.
-- =====================================================================
SELECT '== 2.4 Atomic failure: insufficient stock ==' AS demo;

INSERT INTO prescription (encounter_id, status) VALUES (4, 'ISSUED');
SET @rx_short = LAST_INSERT_ID();
INSERT INTO prescription_item (prescription_id, medication_id, dosage, frequency, duration_days, quantity) VALUES
 (@rx_short, 2, '2 tablets', 'Three times daily', 5, 30),   -- paracetamol: plenty
 (@rx_short, 5, '5ml',       'Three times daily', 7, 40);   -- amoxicillin syrup: only 25

CALL sp_dispense_prescription(@rx_short, 2);   -- ERROR: Insufficient stock

SELECT medication_id, quantity_on_hand                       -- 1500 and 25 (unchanged)
FROM   pharmacy_stock WHERE branch_id = 2 AND medication_id IN (2, 5);
SELECT prescription_id, status FROM prescription WHERE prescription_id = @rx_short;  -- ISSUED

-- =====================================================================
-- Demo 2.5  SAVEPOINT — a billing clerk adds two lines to invoice 4,
-- realises the second one is a mistake, and undoes only that line.
-- =====================================================================
SELECT '== 2.5 SAVEPOINT: partial rollback ==' AS demo;

START TRANSACTION;
INSERT INTO invoice_line (invoice_id, line_no, item_type, description, quantity, unit_price)
VALUES (4, 5, 'OTHER', 'Wound dressing', 1, 1500.00);
SAVEPOINT after_dressing;
INSERT INTO invoice_line (invoice_id, line_no, item_type, description, quantity, unit_price)
VALUES (4, 6, 'OTHER', 'Nebulisation (entered in error)', 1, 4000.00);
ROLLBACK TO SAVEPOINT after_dressing;
COMMIT;

SELECT line_no, description, quantity * unit_price AS amount        -- lines 1-5 only
FROM   invoice_line WHERE invoice_id = 4 ORDER BY line_no;
SELECT invoice_id, total_amount, amount_paid, balance_due            -- 28,600
FROM   v_invoice_balance WHERE invoice_id = 4;

-- =====================================================================
-- Demo 2.6  Business-rule rollback in sp_record_payment
-- =====================================================================
SELECT '== 2.6 Payments: overpayment refused, then exact settlement ==' AS demo;

CALL sp_record_payment(4, 50000.00, 'CARD', 'P3-OVER-1');   -- ERROR: exceeds outstanding balance
CALL sp_record_payment(4, 20000.00, 'CARD', 'P3-PART-1');   -- OK  -> PART_PAID
CALL sp_record_payment(4,  8600.00, 'CASH', 'P3-FULL-1');   -- OK  -> PAID
CALL sp_record_payment(4,   100.00, 'CASH', 'P3-LATE-1');   -- ERROR: already PAID

SELECT payment_id, amount, method, reference FROM payment WHERE invoice_id = 4;
SELECT i.invoice_id, i.status, b.total_amount, b.amount_paid, b.balance_due
FROM   invoice i JOIN v_invoice_balance b ON b.invoice_id = i.invoice_id
WHERE  i.invoice_id = 4;                                                  -- PAID, balance 0

-- Durability check (optional): restart the MySQL80 service
-- (Windows: services.msc > MySQL80 > Restart), reconnect and re-run the two
-- SELECTs above. The committed payments are still there because InnoDB
-- writes them to its redo log before COMMIT returns.
