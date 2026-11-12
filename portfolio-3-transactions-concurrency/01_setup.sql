-- =====================================================================
-- LagosCare Clinics — Portfolio 3: Transactions and concurrency — setup
-- Run ONCE, after Portfolio 1 (01, 02) and Portfolio 2 (01, 03).
--
-- 1. Fixes the two booking limitations recorded in Portfolio 1:
--      (a) a cancelled appointment still held its time slot;
--      (b) the unique (doctor, start) key did not stop OVERLAPPING times.
-- 2. Creates three transactional stored procedures used by the clinic:
--      sp_dispense_prescription, sp_record_payment, sp_book_appointment
-- 3. Creates sp_p3_reset_demo, which puts the demo rows back to a known
--    state so every demo can be re-run.
-- =====================================================================
USE lagoscare;

-- ---------------------------------------------------------------------
-- 1. Appointment slot rules
-- ---------------------------------------------------------------------
-- active_start = scheduled_start while the booking is live, NULL once it is
-- cancelled. A UNIQUE index allows many NULLs, so a cancelled booking no
-- longer blocks the slot, while two live bookings at the same start time
-- are still rejected. STORED, so it can be indexed and is computed once.
-- chk_appt_max_duration (no appointment longer than 8 hours) lets the
-- overlap check in sp_book_appointment search a bounded index range.
ALTER TABLE appointment
  ADD COLUMN active_start DATETIME
      GENERATED ALWAYS AS (IF(status = 'CANCELLED', NULL, scheduled_start)) STORED,
  ADD CONSTRAINT chk_appt_max_duration
      CHECK (scheduled_end <= scheduled_start + INTERVAL 8 HOUR),
  ADD CONSTRAINT uq_appt_doctor_active UNIQUE (doctor_id, active_start);

-- The new unique index also starts with doctor_id, so it can support the
-- foreign key fk_appt_doctor and the old key can be removed.
ALTER TABLE appointment DROP INDEX uq_appt_doctor_slot;

DELIMITER $$

-- ---------------------------------------------------------------------
-- 2a. Dispense a prescription at a branch pharmacy.
--     One unit of work: check status, check stock for EVERY item, reduce
--     stock for every item, mark the prescription DISPENSED. Either all of
--     it happens or none of it does.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_dispense_prescription $$
CREATE PROCEDURE sp_dispense_prescription(IN p_prescription_id BIGINT UNSIGNED,
                                          IN p_branch_id       SMALLINT UNSIGNED)
BEGIN
  DECLARE v_status   VARCHAR(20) DEFAULT NULL;
  DECLARE v_items    INT DEFAULT 0;
  DECLARE v_stocked  INT DEFAULT 0;
  DECLARE v_short    INT DEFAULT 0;

  -- Any error inside the transaction: undo everything, then pass the
  -- original error back to the caller.
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  START TRANSACTION;

  -- Lock the prescription so two pharmacists cannot dispense it twice.
  SELECT status INTO v_status
  FROM   prescription
  WHERE  prescription_id = p_prescription_id
  FOR UPDATE;

  IF v_status IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Prescription not found';
  END IF;
  IF v_status <> 'ISSUED' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Prescription is not in ISSUED status';
  END IF;

  -- Lock this branch's stock rows for every medication on the prescription.
  -- Rows are locked in medication_id order (the primary-key order), so two
  -- dispensing transactions always request locks in the same order and
  -- cannot deadlock each other (see demo 6).
  SELECT COUNT(*) INTO v_stocked
  FROM   prescription_item i
  JOIN   pharmacy_stock s
         ON s.branch_id = p_branch_id AND s.medication_id = i.medication_id
  WHERE  i.prescription_id = p_prescription_id
  FOR UPDATE OF s;

  SELECT COUNT(*) INTO v_items
  FROM   prescription_item
  WHERE  prescription_id = p_prescription_id;

  IF v_stocked < v_items THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A medication on this prescription is not stocked at this branch';
  END IF;

  SELECT COUNT(*) INTO v_short
  FROM   prescription_item i
  JOIN   pharmacy_stock s
         ON s.branch_id = p_branch_id AND s.medication_id = i.medication_id
  WHERE  i.prescription_id = p_prescription_id
    AND  s.quantity_on_hand < i.quantity;

  IF v_short > 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient stock: prescription not dispensed';
  END IF;

  -- Optional pause used only in the concurrency demos (0 in normal use).
  DO SLEEP(IFNULL(@p3_demo_delay, 0));

  UPDATE pharmacy_stock s
  JOIN   prescription_item i
         ON i.medication_id = s.medication_id
  SET    s.quantity_on_hand = s.quantity_on_hand - i.quantity
  WHERE  i.prescription_id = p_prescription_id
    AND  s.branch_id = p_branch_id;

  UPDATE prescription
  SET    status = 'DISPENSED'
  WHERE  prescription_id = p_prescription_id;

  COMMIT;
END $$

-- ---------------------------------------------------------------------
-- 2b. Record a payment against an invoice.
--     Locks the invoice row first, so two cashiers paying the same bill are
--     serialised: the second one sees the first payment and cannot overpay.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_record_payment $$
CREATE PROCEDURE sp_record_payment(IN p_invoice_id BIGINT UNSIGNED,
                                   IN p_amount     DECIMAL(12,2),
                                   IN p_method     VARCHAR(10),
                                   IN p_reference  VARCHAR(40))
BEGIN
  DECLARE v_status  VARCHAR(20) DEFAULT NULL;
  DECLARE v_total   DECIMAL(12,2) DEFAULT 0;
  DECLARE v_paid    DECIMAL(12,2) DEFAULT 0;
  DECLARE v_balance DECIMAL(12,2) DEFAULT 0;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  START TRANSACTION;

  SELECT status INTO v_status
  FROM   invoice
  WHERE  invoice_id = p_invoice_id
  FOR UPDATE;

  IF v_status IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invoice not found';
  END IF;
  IF v_status IN ('PAID', 'VOID') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invoice is already PAID or VOID';
  END IF;

  DO SLEEP(IFNULL(@p3_demo_delay, 0));

  -- These reads happen AFTER the lock is held, so (under REPEATABLE READ)
  -- the transaction's snapshot is taken now and includes every payment
  -- committed by a cashier who held the lock before us.
  SELECT COALESCE(SUM(quantity * unit_price), 0) INTO v_total
  FROM   invoice_line WHERE invoice_id = p_invoice_id;

  SELECT COALESCE(SUM(amount), 0) INTO v_paid
  FROM   payment WHERE invoice_id = p_invoice_id;

  SET v_balance = v_total - v_paid;

  IF p_amount > v_balance THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Payment exceeds outstanding balance';
  END IF;

  INSERT INTO payment (invoice_id, amount, method, reference)
  VALUES (p_invoice_id, p_amount, p_method, p_reference);

  UPDATE invoice
  SET    status = IF(p_amount = v_balance, 'PAID', 'PART_PAID')
  WHERE  invoice_id = p_invoice_id;

  COMMIT;
END $$

-- ---------------------------------------------------------------------
-- 2c. Book an appointment without overlapping the doctor's other bookings.
--     The doctor row is locked as a "booking mutex": all bookings for one
--     doctor queue behind each other, so the overlap check and the INSERT
--     act as one step. Bookings for different doctors do not block.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_book_appointment $$
CREATE PROCEDURE sp_book_appointment(IN  p_patient_id INT UNSIGNED,
                                     IN  p_doctor_id  INT UNSIGNED,
                                     IN  p_branch_id  SMALLINT UNSIGNED,
                                     IN  p_start      DATETIME,
                                     IN  p_end        DATETIME,
                                     IN  p_reason     VARCHAR(255),
                                     OUT p_appointment_id BIGINT UNSIGNED)
BEGIN
  DECLARE v_doctor  INT UNSIGNED DEFAULT NULL;
  DECLARE v_overlap INT DEFAULT 0;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  START TRANSACTION;

  SELECT staff_id INTO v_doctor
  FROM   doctor
  WHERE  staff_id = p_doctor_id
  FOR UPDATE;

  IF v_doctor IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Doctor not found';
  END IF;

  DO SLEEP(IFNULL(@p3_demo_delay, 0));

  -- Two bookings overlap when each starts before the other ends.
  -- active_start IS NOT NULL ignores cancelled bookings; the 8-hour lower
  -- bound (guaranteed by chk_appt_max_duration) keeps this a short range
  -- scan on uq_appt_doctor_active.
  SELECT COUNT(*) INTO v_overlap
  FROM   appointment
  WHERE  doctor_id    = p_doctor_id
    AND  active_start >  p_start - INTERVAL 8 HOUR
    AND  active_start <  p_end
    AND  scheduled_end > p_start;

  IF v_overlap > 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Doctor already has an overlapping appointment';
  END IF;

  INSERT INTO appointment (patient_id, doctor_id, branch_id, scheduled_start, scheduled_end, reason)
  VALUES (p_patient_id, p_doctor_id, p_branch_id, p_start, p_end, p_reason);

  SET p_appointment_id = LAST_INSERT_ID();

  COMMIT;
END $$

-- ---------------------------------------------------------------------
-- 3. Reset the rows used by the demos to a known starting state.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_p3_reset_demo $$
CREATE PROCEDURE sp_p3_reset_demo()
BEGIN
  -- Stock rows used in the demos
  UPDATE pharmacy_stock SET quantity_on_hand = 480  WHERE branch_id = 1 AND medication_id = 1;
  UPDATE pharmacy_stock SET quantity_on_hand = 2000 WHERE branch_id = 1 AND medication_id = 2;
  UPDATE pharmacy_stock SET quantity_on_hand = 1500 WHERE branch_id = 2 AND medication_id = 2;
  UPDATE pharmacy_stock SET quantity_on_hand = 450  WHERE branch_id = 2 AND medication_id = 3;
  UPDATE pharmacy_stock SET quantity_on_hand = 700  WHERE branch_id = 2 AND medication_id = 4;
  UPDATE pharmacy_stock SET quantity_on_hand = 25   WHERE branch_id = 2 AND medication_id = 5;

  -- Payments and invoice lines added by the demos (reference / line_no
  -- ranges that the real data never uses)
  DELETE FROM payment      WHERE reference LIKE 'P3-%';
  DELETE FROM invoice_line WHERE invoice_id = 4 AND line_no >= 5;
  UPDATE invoice SET status = 'PART_PAID' WHERE invoice_id = 2;
  UPDATE invoice SET status = 'OPEN'      WHERE invoice_id = 4;

  -- Demo bookings: Dr Adaeze Okonkwo (staff 1) on 1 Dec 2026
  DELETE FROM appointment
  WHERE  doctor_id = 1
    AND  scheduled_start >= '2026-12-01' AND scheduled_start < '2026-12-02';

  SET @p3_demo_delay = 0;
END $$

DELIMITER ;

CALL sp_p3_reset_demo();

SELECT routine_name, routine_type
FROM   information_schema.routines
WHERE  routine_schema = 'lagoscare'
ORDER  BY routine_name;
