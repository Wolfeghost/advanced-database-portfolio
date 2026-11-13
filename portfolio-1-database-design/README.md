# Portfolio 1 — Database Design and Modelling

Case study: **LagosCare Clinics** (see the root `README.md` for the full case study statement).

## Contents

| File | Purpose |
|---|---|
| `01_schema.sql` | Creates the `lagoscare` database: 20 tables, keys, constraints, triggers and a balance view |
| `02_seed_data.sql` | Loads realistic sample data and prints verification output |
| `03_constraint_tests.sql` | 12 deliberate violations that the database must reject |
| `er_diagram.md` | ER diagram (Mermaid, crow's-foot notation) |
| `evidence/` | Screenshots of execution, the Workbench EER diagram and test output |

## How to run

Requires MySQL 8.0.16 or later (CHECK constraints are only enforced from 8.0.16).

```bash
mysql -u root -p < 01_schema.sql
mysql -u root -p < 02_seed_data.sql
mysql -u root -p --force < 03_constraint_tests.sql   # --force continues past expected errors
```

In MySQL Workbench, open each file and execute it. For the test script, switch on "continue on errors" so all twelve failures appear in the Output panel.

## Design overview

The model follows the outpatient journey: a **patient** books an **appointment** with a **doctor** at a **branch**; an attended appointment becomes an **encounter**, which records **diagnoses**, generates **prescriptions** and **lab orders**, and is billed through one **invoice** settled by one or more **payments** (patient and HMO portions).

Notable modelling decisions:

- **Doctor as a subtype of staff.** All employees share `staff`; only doctors have a licence number, specialty and consultation fee. `doctor.staff_id` is both the primary key and a foreign key to `staff` (1:0..1). A trigger ensures only staff with role `DOCTOR` can be added.
- **Appointment and encounter are separate.** A booking can be cancelled or missed; only attended appointments produce clinical data. The unique key on `encounter.appointment_id` enforces at most one encounter per appointment.
- **Many-to-many relationships are resolved with associative tables:** `encounter_diagnosis`, `prescription_item` and `pharmacy_stock` (branch × medication).
- **Diagnoses use ICD-10 codes** as the natural primary key of `diagnosis_code`, so reporting is consistent with standard clinical coding.

## Keys and constraints

| Type | Examples |
|---|---|
| Surrogate primary keys | `patient_id`, `appointment_id`, `encounter_id`, `invoice_id` (AUTO_INCREMENT) |
| Natural / candidate keys (UNIQUE) | `patient.hospital_no`, `doctor.mdcn_licence_no`, `lab_test.test_code`, `payment.reference` |
| Composite primary keys | `encounter_diagnosis (encounter_id, icd10_code)`, `prescription_item (prescription_id, medication_id)`, `pharmacy_stock (branch_id, medication_id)`, `invoice_line (invoice_id, line_no)` |
| Foreign keys | 22 foreign keys, all `ON DELETE RESTRICT` (the default). Clinical and financial records must never be removed by cascade. |
| CHECK constraints | Appointment end after start; encounter end after start; non-negative stock, prices and fees; positive payment amounts and quantities; HMO coverage 0–100; HMO and member number supplied together |
| Business-rule UNIQUE | `appointment (doctor_id, scheduled_start)` blocks double-booking a doctor's slot; `lab_order (encounter_id, lab_test_id)` blocks duplicate test requests |
| Domain (ENUM) | Staff role, appointment/prescription/lab/invoice status, payment method, sex, blood group |
| Triggers | Doctor role check; date of birth not in the future (MySQL CHECK cannot use `CURRENT_DATE` or reference another table) |

## Normalisation

The starting point was the paper "visit form" a clinic would use, which holds patient details, HMO name and coverage, doctor name and specialty, several diagnoses, several drugs with prices and several lab tests with reference ranges, all on one record.

**First Normal Form.** The form contains repeating groups (multiple diagnoses, drugs and tests per visit). These were moved into their own rows in `encounter_diagnosis`, `prescription_item` and `lab_order`, so every column holds a single atomic value and every table has a primary key.

**Second Normal Form.** In tables with composite keys, no non-key attribute may depend on only part of the key. In `prescription_item (prescription_id, medication_id)`, the medication's name, form, strength and price depend only on `medication_id`, so they live in `medication`. In `pharmacy_stock (branch_id, medication_id)`, only `quantity_on_hand` and `reorder_level` depend on the full key; branch details stay in `branch`.

**Third Normal Form.** Transitive dependencies were removed:

- `patient → hmo_id → HMO name, coverage_percent`: HMO details are stored once in `hmo`.
- `staff → department_id → branch_id`: `staff` has no `branch_id`; the branch is reached through `department`.
- `lab_order → lab_test_id → unit, reference_range`: these describe the test, so they are held in `lab_test`, not repeated on every result.

**BCNF.** In every table, each determinant is a candidate key. For example, in `doctor` both `staff_id` and `mdcn_licence_no` determine all other attributes, and both are keys.

**Deliberate exceptions (justified):**

- `invoice_line.unit_price` copies the price at the time of billing. This is a historical fact, not redundancy: when a medication's price changes, past invoices must not change.
- `appointment.branch_id` is not derivable from the doctor, because a doctor may consult at more than one branch.
- Invoice totals and balances are **not** stored; they are computed by the view `v_invoice_balance`. `invoice.status` is stored for fast filtering and will be kept consistent with payments inside a transaction in Portfolio 3.

## Testing and evidence

`02_seed_data.sql` ends with a row-count summary and the `v_invoice_balance` output (expected balances: invoice 1 = 0, invoice 2 = 6,750, invoice 3 = 0, invoice 4 = 27,100).

`03_constraint_tests.sql` runs twelve invalid operations. Each one should be rejected with the error noted in the script, and the final checks confirm that no data was changed.

Evidence in `evidence/` (run on my laptop, MySQL 8.0.46, using the MySQL command-line client):

- [x] `schema_created.txt`: `SHOW TABLES;` after running the schema (20 tables + `v_invoice_balance`)
- [x] `seed_verification.txt`: row counts and invoice balances (0 / 6,750 / 0 / 27,100)
- [x] `constraint_tests_output.txt`: all 12 violations rejected, followed by the unchanged-data checks
- [x] `eer_diagram_workbench.png`: Workbench Database → Reverse Engineer → Export as PNG. It was captured after Portfolio 3, so `appointment` also shows the `active_start` generated column added there.

## Known limitations (addressed in later portfolios)

- The `uq_appt_doctor_slot` key blocks identical start times but not **overlapping** slots (for example, 09:00–09:30 and 09:15–09:45), and a cancelled booking still occupies its slot. Overlap-safe booking with row locking is implemented in Portfolio 3.
- Dispensing medication must reduce stock and update the prescription status together. This is a transaction scenario for Portfolio 3.
- Free-text clinical notes and variable vitals do not fit a fixed relational structure well. This motivates the document model in Portfolio 4.

## My notes

- **Why a clinic:** I chose a clinic because it has real day-to-day operations that need a proper database: appointments, consultations, lab tests, pharmacy stock and billing split between patients and HMOs. That gave me enough to work with for all five portfolios.
- **Hardest part:** modelling doctors as a type of staff (a subtype table sharing the staff ID), and working out invoice balances. I learned to calculate the balance in a view rather than storing it, so it can never go out of date.
- **What went wrong:** one of my constraint tests (T6) used patient ID 9999 as a "patient that doesn't exist". After I loaded the Portfolio 2 bulk data, that patient *did* exist, so the test stopped failing. I changed it to 999999. It taught me that test data has to stay valid as the database grows.
- **Evidence:** all 12 constraint tests were rejected on my own laptop, and the EER diagram Workbench reverse-engineered matched my design.
