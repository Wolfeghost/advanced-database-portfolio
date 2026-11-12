# Portfolio 3 — Transactions and Concurrency

**Case study:** LagosCare Clinics (same database as Portfolios 1 and 2)
**DBMS:** MySQL 8.0, InnoDB storage engine, default isolation level REPEATABLE READ

This portfolio shows how the clinic database keeps data correct when work is split into several statements and when several staff use it at the same time. It covers:
- COMMIT, ROLLBACK and SAVEPOINT;
- what MySQL does (and does not do) when a statement fails inside a transaction;
- three isolation levels;
- three classic concurrency problems (lost update, double payment, double booking) with the locking fix for each;
- a deadlock.

It also fixes the two booking limitations recorded in Portfolio 1.

---

## 1. Files

| File | Purpose |
|---|---|
| `01_setup.sql` | Schema change for appointment slots; creates the transactional stored procedures and a demo-reset procedure. **Run once.** |
| `02_commit_rollback.sql` | Single-session demos 2.1–2.6: COMMIT, ROLLBACK, error inside a transaction, atomic failure, SAVEPOINT, payment rules |
| `03_session_A.sql` / `03_session_B.sql` | Two-session concurrency demos 3.1–3.6, run step by step in two connections |
| `evidence/` | Screenshots and captured output |

## 2. How to run

1. The database must already contain Portfolio 1 (`01_schema`, `02_seed_data`) and Portfolio 2 (`01_bulk_data`, `03_create_indexes`).
2. Run `01_setup.sql` once. Running it again fails at the `ALTER TABLE`, because the column already exists. The procedures can be recreated on their own if needed.
3. Run `02_commit_rollback.sql`. Some statements fail on purpose, so either switch on Workbench's **"Continue on SQL script error"** toggle or use the command line:
   `mysql -u root -p --force --raw -vvv lagoscare < 02_commit_rollback.sql > evidence\commit_rollback.txt`
4. For demos 3.1–3.6, open **two connections** in Workbench (*Database → Connect to Database…* twice). Two query tabs are not enough: they would share one connection. Load `03_session_A.sql` in one and `03_session_B.sql` in the other, then follow the step numbers (A1 → B1 → B2 → A2 …). To run a step, highlight all its lines and press **Ctrl+Shift+Enter**. Step A0/B0 prints each connection's ID to prove there are two sessions.
5. Every demo begins with `CALL sp_p3_reset_demo()`, so any demo can be repeated.

## 3. Schema change: fixing the Portfolio 1 booking limitations

Portfolio 1 recorded two weaknesses in `UNIQUE (doctor_id, scheduled_start)`:
- **(a)** A cancelled booking still occupied its slot, so nobody else could book 10:00 after a 10:00 cancellation.
- **(b)** It only stopped identical start times. 10:00–10:30 and 10:15–10:45 could both be booked.

**Fix for (a).** I added a stored generated column:

```sql
active_start DATETIME GENERATED ALWAYS AS (IF(status = 'CANCELLED', NULL, scheduled_start)) STORED
```

The unique key is now `UNIQUE (doctor_id, active_start)`. A unique index allows any number of NULLs, so cancelled bookings drop out of the key while live bookings at the same start time are still rejected. Demo 3.5 step B18 books 10:00 again after a cancellation.

**Fix for (b).** Overlap is a rule about ranges, which a unique key cannot express. It is enforced by `sp_book_appointment` (section 4) under a lock. A new CHECK constraint, `chk_appt_max_duration` (no appointment longer than 8 hours), lets the overlap search scan only a short index range.

The old key `uq_appt_doctor_slot` was dropped after the new one existed, because the foreign key `fk_appt_doctor` needs an index that starts with `doctor_id`.

## 4. Transactional stored procedures

The three procedures follow the same pattern:

```
DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
START TRANSACTION;
  lock the row that represents the resource   (SELECT ... FOR UPDATE)
  check the business rules                    (SIGNAL an error if broken)
  make all the changes
COMMIT;
```

The handler matters because MySQL does **not** roll back a transaction when a statement fails (demo 2.3). Without the handler, a failed procedure would leave earlier changes pending.

| Procedure | Row locked | Rule protected | Demo |
|---|---|---|---|
| `sp_dispense_prescription(rx, branch)` | The prescription, plus this branch's stock rows for every item, in medication_id order | No double dispensing; never dispense part of a prescription; stock never negative | 2.1, 2.4 |
| `sp_record_payment(invoice, amount, method, ref)` | The invoice | No overpayment; status (PART_PAID/PAID) always matches the payments | 2.6, 3.4 |
| `sp_book_appointment(patient, doctor, branch, start, end, reason, OUT id)` | The doctor | A doctor never has two live bookings that overlap | 3.5 |

The locks are taken **before** the balance or overlap is read. Under REPEATABLE READ, a transaction's snapshot is created by its first ordinary (non-locking) read. Taking the lock first means that snapshot is created after any earlier holder of the lock has committed, so the check sees that holder's work.

`DO SLEEP(IFNULL(@p3_demo_delay, 0))` is a demo hook only. In normal use the variable is unset and the pause is 0 seconds. The demos set it to 15 seconds to hold a lock long enough to start the second session by hand.

## 5. ACID in this database

| Property | Where it is shown |
|---|---|
| **Atomicity** | 2.2 (ROLLBACK undoes an update); 2.4 (a prescription with one unavailable item changes nothing); 2.5 (SAVEPOINT undoes part of a transaction) |
| **Consistency** | CHECK, FK and UNIQUE constraints (2.3 rejects negative stock); procedure rules (2.6 refuses overpayment) |
| **Isolation** | Demos 3.1–3.6: what another session can see, and how locks serialise conflicting work |
| **Durability** | After COMMIT, InnoDB has written the change to its redo log. 2.6 suggests restarting the MySQL service and re-reading the payments. |

## 6. Demo results

### Single session (`02_commit_rollback.sql`)

| Demo | What happens | Result observed |
|---|---|---|
| 2.1 COMMIT | Dispense amlodipine ×30 + metformin ×60 at Lekki | Stock 450→420, 700→640; prescription DISPENSED; second attempt refused |
| 2.2 ROLLBACK | Subtract 100, look, roll back | 1900 inside the transaction, 2000 after ROLLBACK |
| 2.3 Error mid-transaction | 1st UPDATE succeeds, 2nd breaks `chk_stock_qty` (error 3819) | First change **still pending** (1490) until an explicit ROLLBACK restores 1500 |
| 2.4 Atomic failure | Prescription: paracetamol ×30 (in stock) + amoxicillin ×40 (only 25) | Error "Insufficient stock"; both stock rows unchanged; prescription still ISSUED |
| 2.5 SAVEPOINT | Add dressing line, savepoint, add wrong line, roll back to savepoint, commit | Only the dressing line kept; invoice 4 total 27,100 → 28,600 |
| 2.6 Payment rules | Pay 50,000 / 20,000 / 8,600 / 100 on invoice 4 | Overpayment refused; PART_PAID then PAID; late payment refused |

### Two sessions (`03_session_A.sql` + `03_session_B.sql`)

| Demo | Problem | Without protection | With protection |
|---|---|---|---|
| 3.1 Dirty read | B reads A's uncommitted stock change | READ UNCOMMITTED: B sees **1500**, a value that is then rolled back and never existed | READ COMMITTED: B sees 2000 |
| 3.2 Non-repeatable read | A records a payment while B reads the balance twice in one transaction | READ COMMITTED: 6,750 then **4,750** | REPEATABLE READ: 4,750 then **4,750** (snapshot); 3,750 after B commits |
| 3.3 Lost update | Two pharmacists read 2000, subtract 100 and 50 in the application, write back | Final **1950**: A's 100 tablets vanish from the record | `SELECT … FOR UPDATE`: B **waits** (seen in `sys.innodb_lock_waits`), then reads 1900; final **1850** |
| 3.4 Double payment | Two cashiers settle the 6,750 balance of invoice 2 | Both succeed: paid 29,250 on a 22,500 bill (**−6,750**) | `sp_record_payment`: B waits ~15 s, then "Invoice is already PAID or VOID"; balance 0 |
| 3.5 Double booking | A books 10:00–10:30, B books 10:15–10:45 for the same doctor; both checked first | Both inserted: the doctor is **double-booked** | `sp_book_appointment`: B waits, then "Doctor already has an overlapping appointment". After A's booking is cancelled, B books 10:00 successfully |
| 3.6 Deadlock | A locks stock row 1 then 2; B locks row 2 then 1 | InnoDB detects the cycle at once, rolls back B with **ERROR 1213**; A completes. `SHOW ENGINE INNODB STATUS` lists both transactions under "LATEST DETECTED DEADLOCK" | Prevented in `sp_dispense_prescription` by always locking stock rows in the same (medication_id) order |

## 7. Analysis

**Isolation levels.** InnoDB uses MVCC (multi-version concurrency control): a normal SELECT reads a consistent snapshot built from undo records and never blocks writers.

| Level | Dirty read | Non-repeatable read | Phantom | Shown in |
|---|---|---|---|---|
| READ UNCOMMITTED | possible | possible | possible | 3.1 |
| READ COMMITTED | prevented | possible (fresh snapshot per statement) | possible | 3.1, 3.2 |
| REPEATABLE READ (default) | prevented | prevented (one snapshot per transaction) | prevented for plain reads by the snapshot; for locking reads by next-key locks | 3.2 |
| SERIALIZABLE | prevented | prevented | prevented (plain SELECTs become shared-lock reads) | not demonstrated |

**Why REPEATABLE READ alone did not prevent 3.3–3.5.** In these anomalies each transaction reads one thing and then writes something else based on what it read:
- In 3.3, B wrote a value computed from a stale read.
- In 3.4 and 3.5, each session inserted a *new* row, so the two transactions never touched the same row and no write–write conflict occurred.

Snapshot isolation does not stop this kind of read-then-write anomaly (*write skew*). The fix is to make the read a **locking read** on a row that every competing transaction must also lock. The invoice row acts as the "lock" for its payments, and the doctor row for that doctor's bookings. These are *pessimistic* locks: the second transaction waits instead of failing later.

**Alternatives considered.**
- Atomic `UPDATE … SET quantity_on_hand = quantity_on_hand - 50` would also fix 3.3, because InnoDB locks the row and reads the current value. This is the simplest fix for a single counter. But dispensing must check several rows before changing any, so the procedure locks first.
- SERIALIZABLE, or a locking range read on the appointment index (next-key/gap locks), could stop 3.5. Locking the single doctor row is easier to reason about and only serialises bookings for the same doctor.
- Optimistic locking (a version column checked in the UPDATE, retry on conflict) suits low-contention web apps. A clinic front desk has real contention on popular doctors, so waiting a few milliseconds is preferable.

**Deadlocks** cannot be fully ruled out in a busy system. InnoDB detects them immediately and rolls back the transaction that is cheaper to undo. The application must therefore treat error 1213 (and 1205, lock wait timeout) as "retry the whole transaction". Locking resources in a fixed order, as `sp_dispense_prescription` does with stock rows, removes the most common cause.

**Cost.** Locks reduce concurrency only for the same invoice, the same doctor or the same stock rows. Different invoices, doctors and medications proceed in parallel, because InnoDB locks individual index records, not tables.

## 8. Effect on earlier portfolios

- Portfolio 1 `03_constraint_tests.sql`, test "double-booking", is still rejected, now by `uq_appt_doctor_active`.
- If Portfolio 2's baseline is re-run after this setup, Q4's *before* plan may scan `uq_appt_doctor_active` instead of the dropped `uq_appt_doctor_slot`. The after-index results are unchanged.

## 9. Evidence checklist (`evidence/`)

- [x] `commit_rollback.txt`: output of `02_commit_rollback.sql` (run on my laptop, MySQL 8.0.46)
- [x] `setup_output.txt`: routine list at the end of `01_setup.sql` (4 procedures)
- [ ] `3_0_two_sessions.png`: A0 and B0 showing different connection IDs
- [ ] `3_1_dirty_read.png`: B1 (1500) and B2 (2000)
- [ ] `3_2_nonrepeatable_read.png`: B5 (RC: value changed) and B7 (RR: value unchanged)
- [ ] `3_3_lost_update.png` and `3_3_lock_wait.png`: A8 (1950); A10 (`sys.innodb_lock_waits`) while B10 spins; A12 (1850)
- [ ] `3_4_double_payment.png`: A15 (−6,750) and B14 error after waiting
- [ ] `3_5_double_booking.png`: A20 (overlap), B17 error, A23 (rebooked cancelled slot)
- [ ] `3_6_deadlock.png`: B20 error 1213 and the LATEST DETECTED DEADLOCK section from A27

## 10. My notes

<!-- In your own words: which anomaly surprised you, why the lock is taken
     before the balance/overlap is read, and what the application should do
     when it receives error 1213. -->
