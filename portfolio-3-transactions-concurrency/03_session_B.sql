-- =====================================================================
-- LagosCare Clinics — Portfolio 3: Concurrency demos — SESSION B
-- Use together with 03_session_A.sql (read the instructions at the top
-- of that file). Run each step only when session A tells you to.
-- =====================================================================

-- [B0] Must show a DIFFERENT number from session A's A0
USE lagoscare;
SET SESSION sql_safe_updates = 0;
SET SESSION innodb_lock_wait_timeout = 60;
SELECT CONNECTION_ID() AS session_b_connection_id;

-- =====================================================================
-- DEMO 3.1  DIRTY READ
-- =====================================================================
-- [B1] SCREENSHOT: B sees A's UNCOMMITTED change
SET SESSION TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT quantity_on_hand AS read_uncommitted
FROM   pharmacy_stock WHERE branch_id = 1 AND medication_id = 2;      -- 1500 (dirty)

-- [B2] SCREENSHOT: at READ COMMITTED, B sees only committed data
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
SELECT quantity_on_hand AS read_committed
FROM   pharmacy_stock WHERE branch_id = 1 AND medication_id = 2;      -- 2000

--   -> now run A2

-- [B3] The 1500 that B1 saw was never committed — it never existed
SELECT quantity_on_hand AS after_a_rollback
FROM   pharmacy_stock WHERE branch_id = 1 AND medication_id = 2;      -- 2000

-- =====================================================================
-- DEMO 3.2  NON-REPEATABLE READ
-- =====================================================================
-- [B4] Billing officer opens a READ COMMITTED transaction
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
START TRANSACTION;
SELECT balance_due AS rc_first_read FROM v_invoice_balance WHERE invoice_id = 2;   -- 6750

--   -> now run A4

-- [B5] SCREENSHOT: same query, same transaction, different answer
SELECT balance_due AS rc_second_read FROM v_invoice_balance WHERE invoice_id = 2;  -- 4750
COMMIT;

-- [B6] Now at REPEATABLE READ (the InnoDB default)
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
START TRANSACTION;
SELECT balance_due AS rr_first_read FROM v_invoice_balance WHERE invoice_id = 2;   -- 4750

--   -> now run A5

-- [B7] SCREENSHOT: the snapshot does not move until the transaction ends
SELECT balance_due AS rr_second_read FROM v_invoice_balance WHERE invoice_id = 2;  -- still 4750
COMMIT;
SELECT balance_due AS after_commit FROM v_invoice_balance WHERE invoice_id = 2;    -- 3750

-- =====================================================================
-- DEMO 3.3  LOST UPDATE
-- =====================================================================
-- [B8]
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
START TRANSACTION;
SELECT quantity_on_hand INTO @qty FROM pharmacy_stock WHERE branch_id = 1 AND medication_id = 2;
SELECT @qty AS b_read;                                                -- 2000

--   -> now run A7

-- [B9] B dispensed 50 tablets — and overwrites A's update
UPDATE pharmacy_stock SET quantity_on_hand = @qty - 50 WHERE branch_id = 1 AND medication_id = 2;
COMMIT;

--   -> now run A8, then A9

-- [B10] Locking read: WAITS until A commits, then reads the new value
START TRANSACTION;
SELECT quantity_on_hand INTO @qty FROM pharmacy_stock
WHERE  branch_id = 1 AND medication_id = 2
FOR UPDATE;
SELECT @qty AS b_read_after_wait;                                     -- 1900

--   -> while B10 is waiting, run A10 and A11

-- [B11]
UPDATE pharmacy_stock SET quantity_on_hand = @qty - 50 WHERE branch_id = 1 AND medication_id = 2;
COMMIT;

--   -> now run A12

-- =====================================================================
-- DEMO 3.4  DOUBLE PAYMENT
-- =====================================================================
-- [B12]
START TRANSACTION;
SELECT balance_due INTO @due FROM v_invoice_balance WHERE invoice_id = 2;
SELECT @due AS b_sees_balance;                                        -- 6750

--   -> now run A14

-- [B13]
INSERT INTO payment (invoice_id, amount, method, reference) VALUES (2, @due, 'CARD', 'P3-NAIVE-B');
UPDATE invoice SET status = 'PAID' WHERE invoice_id = 2;
COMMIT;

--   -> now run A15, then A16

-- [B14] SCREENSHOT: WAITS for A, then is refused
-- ERROR 1644: Invoice is already PAID or VOID
CALL sp_record_payment(2, 6750.00, 'CARD', 'P3-SAFE-B');

--   -> now run A17

-- =====================================================================
-- DEMO 3.5  OVERLAPPING BOOKINGS
-- =====================================================================
-- [B15]
START TRANSACTION;
SELECT COUNT(*) AS b_overlaps
FROM   appointment
WHERE  doctor_id = 1
  AND  active_start  < '2026-12-01 10:45'
  AND  scheduled_end > '2026-12-01 10:15';                            -- 0

--   -> now run A19

-- [B16]
INSERT INTO appointment (patient_id, doctor_id, branch_id, scheduled_start, scheduled_end, reason)
VALUES (5, 1, 1, '2026-12-01 10:15', '2026-12-01 10:45', 'Naive booking B');
COMMIT;

--   -> now run A20, then A21

-- [B17] SCREENSHOT: WAITS for A, then is refused
-- ERROR 1644: Doctor already has an overlapping appointment
CALL sp_book_appointment(5, 1, 1, '2026-12-01 10:15', '2026-12-01 10:45', 'Safe booking B', @b_id);

--   -> now run A22

-- [B18] Book the 10:00 slot that A's patient cancelled — same start time
CALL sp_book_appointment(5, 1, 1, '2026-12-01 10:00', '2026-12-01 10:30', 'Rebooked cancelled slot', @b_id);
SELECT @b_id AS b_appointment_id;

--   -> now run A23

-- =====================================================================
-- DEMO 3.6  DEADLOCK
-- =====================================================================
-- [B19]
START TRANSACTION;
UPDATE pharmacy_stock SET quantity_on_hand = quantity_on_hand - 1
WHERE  branch_id = 1 AND medication_id = 2;           -- B locks paracetamol

--   -> now run A25

-- [B20] SCREENSHOT: B needs the row A holds -> cycle -> ERROR 1213
-- "Deadlock found when trying to get lock; try restarting transaction"
UPDATE pharmacy_stock SET quantity_on_hand = quantity_on_hand - 1
WHERE  branch_id = 1 AND medication_id = 1;

-- [B21] B's transaction has already been rolled back by InnoDB;
-- this ROLLBACK just tidies the session.
ROLLBACK;

--   -> now run A26, A27, A28
