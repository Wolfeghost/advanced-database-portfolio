-- =====================================================================
-- LagosCare Clinics — Portfolio 1: Relational Schema
-- Target: MySQL 8.0.16+ (CHECK constraints are enforced from 8.0.16)
-- =====================================================================

DROP DATABASE IF EXISTS lagoscare;
CREATE DATABASE lagoscare CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE lagoscare;

-- ---------------------------------------------------------------------
-- Organisation structure
-- ---------------------------------------------------------------------
CREATE TABLE branch (
  branch_id    SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  branch_code  CHAR(3)      NOT NULL,
  name         VARCHAR(100) NOT NULL,
  address      VARCHAR(255) NOT NULL,
  city         VARCHAR(60)  NOT NULL DEFAULT 'Lagos',
  phone        VARCHAR(20)  NOT NULL,
  CONSTRAINT uq_branch_code UNIQUE (branch_code)
) ENGINE=InnoDB;

CREATE TABLE department (
  department_id SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  branch_id     SMALLINT UNSIGNED NOT NULL,
  name          VARCHAR(80) NOT NULL,
  CONSTRAINT uq_department_branch_name UNIQUE (branch_id, name),
  CONSTRAINT fk_department_branch FOREIGN KEY (branch_id) REFERENCES branch (branch_id)
) ENGINE=InnoDB;

-- Branch is reached through department (staff -> department -> branch),
-- so staff deliberately has no branch_id column (avoids a transitive dependency).
CREATE TABLE staff (
  staff_id      INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  department_id SMALLINT UNSIGNED NOT NULL,
  first_name    VARCHAR(50)  NOT NULL,
  last_name     VARCHAR(50)  NOT NULL,
  role          ENUM('DOCTOR','NURSE','LAB_SCIENTIST','PHARMACIST','RECEPTIONIST','ADMIN') NOT NULL,
  email         VARCHAR(120) NOT NULL,
  phone         VARCHAR(20)  NOT NULL,
  hire_date     DATE         NOT NULL,
  is_active     BOOLEAN      NOT NULL DEFAULT TRUE,
  CONSTRAINT uq_staff_email UNIQUE (email),
  CONSTRAINT fk_staff_department FOREIGN KEY (department_id) REFERENCES department (department_id)
) ENGINE=InnoDB;

-- Subtype of staff (1:0..1). Shares the staff primary key.
CREATE TABLE doctor (
  staff_id         INT UNSIGNED PRIMARY KEY,
  specialty        VARCHAR(80)   NOT NULL,
  mdcn_licence_no  VARCHAR(20)   NOT NULL,   -- Medical and Dental Council of Nigeria licence
  consultation_fee DECIMAL(10,2) NOT NULL,
  CONSTRAINT uq_doctor_licence UNIQUE (mdcn_licence_no),
  CONSTRAINT chk_doctor_fee CHECK (consultation_fee >= 0),
  CONSTRAINT fk_doctor_staff FOREIGN KEY (staff_id) REFERENCES staff (staff_id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Patients and HMOs
-- ---------------------------------------------------------------------
CREATE TABLE hmo (
  hmo_id           SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name             VARCHAR(100) NOT NULL,
  phone            VARCHAR(20),
  coverage_percent DECIMAL(5,2) NOT NULL,
  CONSTRAINT uq_hmo_name UNIQUE (name),
  CONSTRAINT chk_hmo_coverage CHECK (coverage_percent BETWEEN 0 AND 100)
) ENGINE=InnoDB;

CREATE TABLE patient (
  patient_id    INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  hospital_no   VARCHAR(12)  NOT NULL,           -- natural key printed on patient card
  first_name    VARCHAR(50)  NOT NULL,
  last_name     VARCHAR(50)  NOT NULL,
  date_of_birth DATE         NOT NULL,
  sex           ENUM('M','F') NOT NULL,
  phone         VARCHAR(20)  NOT NULL,
  email         VARCHAR(120),
  address       VARCHAR(255),
  blood_group   ENUM('A+','A-','B+','B-','AB+','AB-','O+','O-'),
  hmo_id        SMALLINT UNSIGNED NULL,
  hmo_member_no VARCHAR(30)  NULL,
  registered_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT uq_patient_hospital_no UNIQUE (hospital_no),
  CONSTRAINT uq_patient_email UNIQUE (email),
  CONSTRAINT uq_patient_hmo_member UNIQUE (hmo_id, hmo_member_no),
  -- An HMO and a membership number must be supplied together or not at all
  CONSTRAINT chk_patient_hmo_pair CHECK (
    (hmo_id IS NULL AND hmo_member_no IS NULL) OR
    (hmo_id IS NOT NULL AND hmo_member_no IS NOT NULL)
  ),
  CONSTRAINT fk_patient_hmo FOREIGN KEY (hmo_id) REFERENCES hmo (hmo_id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Appointments and encounters
-- ---------------------------------------------------------------------
-- branch_id is kept on appointment because a doctor may consult at more
-- than one branch; the location is a fact about the appointment itself.
CREATE TABLE appointment (
  appointment_id  BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  patient_id      INT UNSIGNED      NOT NULL,
  doctor_id       INT UNSIGNED      NOT NULL,
  branch_id       SMALLINT UNSIGNED NOT NULL,
  scheduled_start DATETIME          NOT NULL,
  scheduled_end   DATETIME          NOT NULL,
  status          ENUM('BOOKED','CHECKED_IN','COMPLETED','CANCELLED','NO_SHOW') NOT NULL DEFAULT 'BOOKED',
  reason          VARCHAR(255),
  created_at      DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT uq_appt_doctor_slot UNIQUE (doctor_id, scheduled_start),
  CONSTRAINT chk_appt_time CHECK (scheduled_end > scheduled_start),
  CONSTRAINT fk_appt_patient FOREIGN KEY (patient_id) REFERENCES patient (patient_id),
  CONSTRAINT fk_appt_doctor  FOREIGN KEY (doctor_id)  REFERENCES doctor (staff_id),
  CONSTRAINT fk_appt_branch  FOREIGN KEY (branch_id)  REFERENCES branch (branch_id)
) ENGINE=InnoDB;

-- One consultation per attended appointment (1:0..1).
CREATE TABLE encounter (
  encounter_id    BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  appointment_id  BIGINT UNSIGNED NOT NULL,
  started_at      DATETIME        NOT NULL,
  ended_at        DATETIME        NULL,
  chief_complaint VARCHAR(255)    NOT NULL,
  clinical_notes  TEXT,
  CONSTRAINT uq_encounter_appointment UNIQUE (appointment_id),
  CONSTRAINT chk_encounter_time CHECK (ended_at IS NULL OR ended_at >= started_at),
  CONSTRAINT fk_encounter_appointment FOREIGN KEY (appointment_id) REFERENCES appointment (appointment_id)
) ENGINE=InnoDB;

CREATE TABLE diagnosis_code (
  icd10_code  VARCHAR(8)   PRIMARY KEY,
  description VARCHAR(255) NOT NULL
) ENGINE=InnoDB;

-- Resolves the M:N between encounter and diagnosis code.
CREATE TABLE encounter_diagnosis (
  encounter_id BIGINT UNSIGNED NOT NULL,
  icd10_code   VARCHAR(8)      NOT NULL,
  is_primary   BOOLEAN         NOT NULL DEFAULT FALSE,
  PRIMARY KEY (encounter_id, icd10_code),
  CONSTRAINT fk_encdx_encounter FOREIGN KEY (encounter_id) REFERENCES encounter (encounter_id),
  CONSTRAINT fk_encdx_code      FOREIGN KEY (icd10_code)   REFERENCES diagnosis_code (icd10_code)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Pharmacy
-- ---------------------------------------------------------------------
CREATE TABLE medication (
  medication_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  generic_name  VARCHAR(100)  NOT NULL,
  form          ENUM('TABLET','CAPSULE','SYRUP','INJECTION','CREAM','POWDER','INFUSION') NOT NULL,
  strength      VARCHAR(30)   NOT NULL,
  unit_price    DECIMAL(10,2) NOT NULL,          -- price per dispensing unit (tablet, bottle, sachet)
  CONSTRAINT uq_medication UNIQUE (generic_name, form, strength),
  CONSTRAINT chk_medication_price CHECK (unit_price >= 0)
) ENGINE=InnoDB;

CREATE TABLE pharmacy_stock (
  branch_id        SMALLINT UNSIGNED NOT NULL,
  medication_id    INT UNSIGNED      NOT NULL,
  quantity_on_hand INT               NOT NULL,
  reorder_level    INT               NOT NULL DEFAULT 20,
  PRIMARY KEY (branch_id, medication_id),
  CONSTRAINT chk_stock_qty     CHECK (quantity_on_hand >= 0),
  CONSTRAINT chk_stock_reorder CHECK (reorder_level >= 0),
  CONSTRAINT fk_stock_branch     FOREIGN KEY (branch_id)     REFERENCES branch (branch_id),
  CONSTRAINT fk_stock_medication FOREIGN KEY (medication_id) REFERENCES medication (medication_id)
) ENGINE=InnoDB;

CREATE TABLE prescription (
  prescription_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  encounter_id    BIGINT UNSIGNED NOT NULL,
  prescribed_at   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  status          ENUM('ISSUED','DISPENSED','CANCELLED') NOT NULL DEFAULT 'ISSUED',
  CONSTRAINT fk_rx_encounter FOREIGN KEY (encounter_id) REFERENCES encounter (encounter_id)
) ENGINE=InnoDB;

CREATE TABLE prescription_item (
  prescription_id BIGINT UNSIGNED   NOT NULL,
  medication_id   INT UNSIGNED      NOT NULL,
  dosage          VARCHAR(50)       NOT NULL,
  frequency       VARCHAR(50)       NOT NULL,
  duration_days   SMALLINT UNSIGNED NOT NULL,
  quantity        SMALLINT UNSIGNED NOT NULL,
  PRIMARY KEY (prescription_id, medication_id),
  CONSTRAINT chk_rxitem_duration CHECK (duration_days > 0),
  CONSTRAINT chk_rxitem_qty      CHECK (quantity > 0),
  CONSTRAINT fk_rxitem_rx         FOREIGN KEY (prescription_id) REFERENCES prescription (prescription_id),
  CONSTRAINT fk_rxitem_medication FOREIGN KEY (medication_id)   REFERENCES medication (medication_id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Laboratory
-- ---------------------------------------------------------------------
-- unit and reference_range describe the TEST, not an individual result,
-- so they live here (3NF) rather than on lab_result.
CREATE TABLE lab_test (
  lab_test_id     SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  test_code       VARCHAR(10)   NOT NULL,
  name            VARCHAR(100)  NOT NULL,
  unit            VARCHAR(20),
  reference_range VARCHAR(50),
  price           DECIMAL(10,2) NOT NULL,
  CONSTRAINT uq_lab_test_code UNIQUE (test_code),
  CONSTRAINT chk_lab_test_price CHECK (price >= 0)
) ENGINE=InnoDB;

CREATE TABLE lab_order (
  lab_order_id BIGINT UNSIGNED   AUTO_INCREMENT PRIMARY KEY,
  encounter_id BIGINT UNSIGNED   NOT NULL,
  lab_test_id  SMALLINT UNSIGNED NOT NULL,
  ordered_at   DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
  status       ENUM('ORDERED','SAMPLE_COLLECTED','COMPLETED','CANCELLED') NOT NULL DEFAULT 'ORDERED',
  CONSTRAINT uq_lab_order_test UNIQUE (encounter_id, lab_test_id),
  CONSTRAINT fk_laborder_encounter FOREIGN KEY (encounter_id) REFERENCES encounter (encounter_id),
  CONSTRAINT fk_laborder_test      FOREIGN KEY (lab_test_id)  REFERENCES lab_test (lab_test_id)
) ENGINE=InnoDB;

CREATE TABLE lab_result (
  lab_order_id BIGINT UNSIGNED PRIMARY KEY,      -- 1:0..1 with lab_order
  result_value VARCHAR(50)     NOT NULL,
  is_abnormal  BOOLEAN         NOT NULL DEFAULT FALSE,
  performed_by INT UNSIGNED    NOT NULL,
  resulted_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_labresult_order FOREIGN KEY (lab_order_id) REFERENCES lab_order (lab_order_id),
  CONSTRAINT fk_labresult_staff FOREIGN KEY (performed_by) REFERENCES staff (staff_id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Billing
-- ---------------------------------------------------------------------
CREATE TABLE invoice (
  invoice_id   BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  encounter_id BIGINT UNSIGNED NOT NULL,
  issued_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  status       ENUM('OPEN','PART_PAID','PAID','VOID') NOT NULL DEFAULT 'OPEN',
  CONSTRAINT uq_invoice_encounter UNIQUE (encounter_id),
  CONSTRAINT fk_invoice_encounter FOREIGN KEY (encounter_id) REFERENCES encounter (encounter_id)
) ENGINE=InnoDB;

-- unit_price is a deliberate snapshot of the price at billing time
-- (medication/test prices change; historical invoices must not).
CREATE TABLE invoice_line (
  invoice_id  BIGINT UNSIGNED   NOT NULL,
  line_no     SMALLINT UNSIGNED NOT NULL,
  item_type   ENUM('CONSULTATION','LAB','MEDICATION','OTHER') NOT NULL,
  description VARCHAR(150)      NOT NULL,
  quantity    SMALLINT UNSIGNED NOT NULL DEFAULT 1,
  unit_price  DECIMAL(10,2)     NOT NULL,
  PRIMARY KEY (invoice_id, line_no),
  CONSTRAINT chk_invline_qty   CHECK (quantity > 0),
  CONSTRAINT chk_invline_price CHECK (unit_price >= 0),
  CONSTRAINT fk_invline_invoice FOREIGN KEY (invoice_id) REFERENCES invoice (invoice_id)
) ENGINE=InnoDB;

CREATE TABLE payment (
  payment_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  invoice_id BIGINT UNSIGNED NOT NULL,
  amount     DECIMAL(12,2)   NOT NULL,
  method     ENUM('CASH','CARD','TRANSFER','HMO') NOT NULL,
  reference  VARCHAR(40)     NOT NULL,
  paid_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT uq_payment_reference UNIQUE (reference),
  CONSTRAINT chk_payment_amount CHECK (amount > 0),
  CONSTRAINT fk_payment_invoice FOREIGN KEY (invoice_id) REFERENCES invoice (invoice_id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Business rules a CHECK constraint cannot express (MySQL does not allow
-- CHECK to reference other tables or non-deterministic functions such as
-- CURRENT_DATE), so they are enforced with triggers.
-- ---------------------------------------------------------------------
DELIMITER $$

CREATE TRIGGER trg_doctor_role_check
BEFORE INSERT ON doctor
FOR EACH ROW
BEGIN
  IF (SELECT role FROM staff WHERE staff_id = NEW.staff_id) <> 'DOCTOR' THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Staff member must have role DOCTOR to be added to doctor table';
  END IF;
END$$

CREATE TRIGGER trg_patient_dob_insert
BEFORE INSERT ON patient
FOR EACH ROW
BEGIN
  IF NEW.date_of_birth > CURRENT_DATE THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'date_of_birth cannot be in the future';
  END IF;
END$$

CREATE TRIGGER trg_patient_dob_update
BEFORE UPDATE ON patient
FOR EACH ROW
BEGIN
  IF NEW.date_of_birth > CURRENT_DATE THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'date_of_birth cannot be in the future';
  END IF;
END$$

DELIMITER ;

-- ---------------------------------------------------------------------
-- Derived data is computed, not stored: invoice totals and balances.
-- ---------------------------------------------------------------------
CREATE VIEW v_invoice_balance AS
SELECT  i.invoice_id,
        i.encounter_id,
        i.status,
        COALESCE(l.total_amount, 0)                            AS total_amount,
        COALESCE(p.amount_paid, 0)                             AS amount_paid,
        COALESCE(l.total_amount, 0) - COALESCE(p.amount_paid, 0) AS balance_due
FROM    invoice i
LEFT JOIN (SELECT invoice_id, SUM(quantity * unit_price) AS total_amount
           FROM invoice_line GROUP BY invoice_id) l ON l.invoice_id = i.invoice_id
LEFT JOIN (SELECT invoice_id, SUM(amount) AS amount_paid
           FROM payment GROUP BY invoice_id)      p ON p.invoice_id = i.invoice_id;
