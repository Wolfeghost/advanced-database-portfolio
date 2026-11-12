-- =====================================================================
-- LagosCare Clinics — Portfolio 3: Concurrency demos — SESSION A
-- Use together with 03_session_B.sql. Run AFTER 01_setup.sql.
--
-- HOW TO RUN (MySQL Workbench)
-- 1. Open TWO separate connections: Database > Connect to Database...
--    twice (two connection tabs at the top, not two query tabs).
--    Open this file in the first connection, 03_session_B.sql in the second.
-- 2. Arrange the two windows side by side.
-- 3. Follow the step numbers in order across both files:
--    A1 -> B1 -> A2 -> B2 ... Highlight ALL the lines of one step and press
--    Ctrl+Shift+Enter (execute selection). Take a screenshot at each
--    "SCREENSHOT" marker.
-- 4. A step marked "WAITS" will keep running (spinner) until the other
--    session does its next step. That waiting IS the evidence.
-- =====================================================================

-- [A0] Confirm this is a different connection from session B
USE lagoscare;
SET SESSION sql_safe_updates = 0;
SET SESSION innodb_lock_wait_timeout = 60;
SELECT CONNECTION_ID() AS session_a_connection_id;

-- =====================================================================
-- DEMO 3.1  DIRTY READ (READ UNCOMMITTED vs READ COMMITTED)
-- Pharmacist A starts removing 500 paracetamol tablets (Ikeja) but has not
-- committed yet.
-- =====================================================================
-- [A1]
CALL sp_p3_reset_demo();
START TRANSACTION;
UPDATE pharmacy_stock SET quantity_on_hand = quantity_on_hand - 500
WHERE  branch_id = 1 AND medication_id = 2;

--   -> now run B1, B2

-- [A2] A changes its mind
ROLLBACK;

--   -> now run B3

-- =====================================================================
-- DEMO 3.2  NON-REPEATABLE READ (READ COMMITTED vs REPEATABLE READ)
-- A cashier takes payments on invoice 2 while a billing officer (B) is
-- reading the balance inside one transaction.
-- =====================================================================
-- [A3]
CALL sp_p3_reset_demo();

--   -> now run B4

-- [A4]
CALL sp_record_payment(2, 2000.00, 'CASH', 'P3-NRR-1');

--   -> now run B5, B6

-- [A5]
CALL sp_record_payment(2, 1000.00, 'CASH', 'P3-NRR-2');

--   -> now run B7

-- =====================================================================
-- DEMO 3.3  LOST UPDATE on pharmacy stock, and the fix (SELECT ... FOR UPDATE)
-- Two pharmacists each read the stock level, subtract what they dispensed
-- in the application, and write the new value back.
-- =====================================================================
-- [A6]  Part (a): naive read-modify-write
CALL sp_p3_reset_demo();
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
START TRANSACTION;
SELECT quantity_on_hand INTO @qty FROM pharmacy_stock WHERE branch_id = 1 AND medication_id = 2;
SELECT @qty AS a_read;                                                -- 2000

--   -> now run B8

-- [A7] A dispensed 100 tablets
UPDATE pharmacy_stock SET quantity_on_hand = @qty - 100 WHERE branch_id = 1 AND medication_id = 2;
COMMIT;

--   -> now run B9

-- [A8] SCREENSHOT: 150 tablets left the shelf, but the stock fell by only 50
SELECT quantity_on_hand AS after_naive FROM pharmacy_stock WHERE branch_id = 1 AND medication_id = 2;  -- 1950 (should be 1850)

-- [A9]  Part (b): the same, with a locking read
CALL sp_p3_reset_demo();
START TRANSACTION;
SELECT quantity_on_hand INTO @qty FROM pharmacy_stock
WHERE  branch_id = 1 AND medication_id = 2
FOR UPDATE;
SELECT @qty AS a_read;                                                -- 2000

--   -> now run B10 (it WAITS)

-- [A10] SCREENSHOT: who is waiting for whom
SELECT waiting_pid, waiting_query, blocking_pid, locked_table,
       locked_index, locked_type, wait_age
FROM   sys.innodb_lock_waits;

-- [A11]
UPDATE pharmacy_stock SET quantity_on_hand = @qty - 100 WHERE branch_id = 1 AND medication_id = 2;
COMMIT;

--   -> B10 finishes by itself (it now reads 1900). Run B11.

-- [A12] SCREENSHOT: both deductions kept
SELECT quantity_on_hand AS after_locking FROM pharmacy_stock WHERE branch_id = 1 AND medication_id = 2;  -- 1850

-- =====================================================================
-- DEMO 3.4  DOUBLE PAYMENT, and the fix (sp_record_payment locks the invoice)
-- Invoice 2 has 6,750 outstanding. Two cashiers try to settle it at the
-- same time.
-- =====================================================================
-- [A13]  Part (a): naive — read the balance, then insert a payment for it
CALL sp_p3_reset_demo();
START TRANSACTION;
SELECT balance_due INTO @due FROM v_invoice_balance WHERE invoice_id = 2;
SELECT @due AS a_sees_balance;                                        -- 6750

--   -> now run B12

-- [A14]
INSERT INTO payment (invoice_id, amount, method, reference) VALUES (2, @due, 'CASH', 'P3-NAIVE-A');
UPDATE invoice SET status = 'PAID' WHERE invoice_id = 2;
COMMIT;

--   -> now run B13

-- [A15] SCREENSHOT: the patient has been charged twice
SELECT invoice_id, total_amount, amount_paid, balance_due
FROM   v_invoice_balance WHERE invoice_id = 2;                        -- balance -6750

-- [A16]  Part (b): through the procedure. The 15-second pause holds the
-- invoice lock long enough for you to start B14 while A is still running.
CALL sp_p3_reset_demo();
SET @p3_demo_delay = 15;
CALL sp_record_payment(2, 6750.00, 'CASH', 'P3-SAFE-A');

--   -> IMMEDIATELY run B14 (it WAITS, then fails)

-- [A17] SCREENSHOT
SET @p3_demo_delay = 0;
SELECT invoice_id, total_amount, amount_paid, balance_due
FROM   v_invoice_balance WHERE invoice_id = 2;                        -- balance 0
SELECT reference, amount, method FROM payment WHERE invoice_id = 2;

-- =====================================================================
-- DEMO 3.5  OVERLAPPING BOOKINGS (write skew), and the fix
-- Two receptionists book Dr Adaeze Okonkwo (staff 1) for 1 Dec 2026:
-- A for 10:00–10:30, B for 10:15–10:45. Both first check she is free.
-- =====================================================================
-- [A18]  Part (a): naive — check, then insert
CALL sp_p3_reset_demo();
START TRANSACTION;
SELECT COUNT(*) AS a_overlaps
FROM   appointment
WHERE  doctor_id = 1
  AND  active_start  < '2026-12-01 10:30'
  AND  scheduled_end > '2026-12-01 10:00';                            -- 0

--   -> now run B15

-- [A19]
INSERT INTO appointment (patient_id, doctor_id, branch_id, scheduled_start, scheduled_end, reason)
VALUES (2, 1, 1, '2026-12-01 10:00', '2026-12-01 10:30', 'Naive booking A');
COMMIT;

--   -> now run B16

-- [A20] SCREENSHOT: the doctor is double-booked from 10:15 to 10:30
SELECT appointment_id, patient_id, scheduled_start, scheduled_end, status, reason
FROM   appointment
WHERE  doctor_id = 1 AND scheduled_start >= '2026-12-01' AND scheduled_start < '2026-12-02';

-- [A21]  Part (b): through sp_book_appointment (locks the doctor row)
CALL sp_p3_reset_demo();
SET @p3_demo_delay = 15;
CALL sp_book_appointment(2, 1, 1, '2026-12-01 10:00', '2026-12-01 10:30', 'Safe booking A', @a_id);

--   -> IMMEDIATELY run B17 (it WAITS, then fails)

-- [A22] The patient cancels the 10:00 booking
SET @p3_demo_delay = 0;
SELECT @a_id AS a_appointment_id;
UPDATE appointment SET status = 'CANCELLED' WHERE appointment_id = @a_id;

--   -> now run B18

-- [A23] SCREENSHOT: the cancelled booking no longer holds the 10:00 slot
SELECT appointment_id, patient_id, scheduled_start, scheduled_end, status, active_start, reason
FROM   appointment
WHERE  doctor_id = 1 AND scheduled_start >= '2026-12-01' AND scheduled_start < '2026-12-02';

-- =====================================================================
-- DEMO 3.6  DEADLOCK
-- A and B each update two stock rows, but in OPPOSITE order.
-- =====================================================================
-- [A24]
CALL sp_p3_reset_demo();
START TRANSACTION;
UPDATE pharmacy_stock SET quantity_on_hand = quantity_on_hand - 1
WHERE  branch_id = 1 AND medication_id = 1;           -- A locks Artemether/Lumefantrine

--   -> now run B19

-- [A25] A now needs paracetamol, which B holds  (WAITS)
UPDATE pharmacy_stock SET quantity_on_hand = quantity_on_hand - 1
WHERE  branch_id = 1 AND medication_id = 2;

--   -> now run B20. InnoDB detects the cycle within a moment, rolls back
--      one transaction (usually B) with ERROR 1213, and A25 completes.

-- [A26]
COMMIT;
SELECT medication_id, quantity_on_hand FROM pharmacy_stock
WHERE  branch_id = 1 AND medication_id IN (1, 2);    -- 479 and 1999: only A's work survived

-- [A27] SCREENSHOT: InnoDB's own record of the deadlock. In Workbench,
-- right-click the Status cell > Open Value in Viewer, and find the section
-- "LATEST DETECTED DEADLOCK".
SHOW ENGINE INNODB STATUS;

-- [A28] Tidy up
CALL sp_p3_reset_demo();
