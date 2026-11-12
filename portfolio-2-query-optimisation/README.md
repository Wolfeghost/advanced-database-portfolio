# Portfolio 2 — Query Processing and Optimisation

**Case study:** LagosCare Clinics (same schema as Portfolio 1)
**DBMS:** MySQL 8.0 (InnoDB), MySQL Workbench 8.0 / MySQL command-line client

This portfolio loads a realistic volume of clinic activity, runs six queries taken from the clinic's day-to-day operations, reads their execution plans with `EXPLAIN ANALYZE`, and then improves them with targeted indexes and query rewrites. The cost of those indexes (storage and slower writes) is measured too.

---

## 1. Files

| File | Purpose |
|---|---|
| `01_bulk_data.sql` | Generates ~13 months of activity (Oct 2025 – Oct 2026) on top of the Portfolio 1 sample data |
| `02_baseline_plans.sql` | Runs queries Q1–Q5 and their `EXPLAIN ANALYZE` plans **before** optimisation |
| `03_create_indexes.sql` | Creates five indexes, each designed for one query |
| `04_optimised_plans.sql` | Plans **after** optimisation, including the Q2 and Q3 rewrites and the Q6 anti-join comparison |
| `05_index_cost.sql` | Measures index storage size and the extra cost of maintaining indexes on INSERT |
| `06_reset_indexes.sql` | Removes the optimisation indexes so the baseline can be re-run |
| `evidence/` | Captured plan output and screenshots |

## 2. How to run

1. Run Portfolio 1 `01_schema.sql` and `02_seed_data.sql` first (fresh database).
2. In Workbench, set **Edit → Preferences → SQL Editor → DBMS connection read timeout** to `600` seconds, then run `01_bulk_data.sql`. It finishes in under a minute. The final check must return **zero rows**, meaning every invoice status matches its balance.
3. Run scripts `02` → `03` → `04` → `05` in order.
4. To capture the full plans as text (MySQL 8.0 Command Line Client or Command Prompt, from this folder):

```
mysql -u root -p --raw -vvv lagoscare < 02_baseline_plans.sql  > evidence\baseline_plans.txt
mysql -u root -p           lagoscare < 03_create_indexes.sql
mysql -u root -p --raw -vvv lagoscare < 04_optimised_plans.sql > evidence\optimised_plans.txt
mysql -u root -p --raw -vvv lagoscare < 05_index_cost.sql      > evidence\index_cost.txt
```

The generator uses `CRC32()` of the row number instead of `RAND()`, so every run creates **identical data**. Plan shapes and row counts are reproducible; only millisecond timings vary by machine.

## 3. Dataset

| Table | Rows |
|---|---:|
| doctor | 20 |
| patient | 20,008 |
| appointment | 120,007 |
| encounter | 95,744 |
| encounter_diagnosis | 133,930 |
| lab_order | 38,241 |
| lab_result | 37,134 |
| invoice | 95,744 |
| invoice_line | 200,936 |
| payment | 126,302 |

Appointment mix: 80% completed, 10% cancelled, 10% no-show. Of the patients, 60% are HMO members. 3% of lab orders are still waiting for a result.

## 4. Workload queries

| # | User | Business question | SQL feature tested |
|---|---|---|---|
| Q1 | Front desk | Find a patient by surname and first-name prefix | Composite index, `LIKE 'prefix%'` |
| Q2 | Front desk | One branch's clinic list for one day | Sargability (function on an indexed column) |
| Q3 | Management | Revenue for one month by branch and item type | 5-table join, `GROUP BY`, join order |
| Q4 | Management | No-show rate per doctor for the last quarter | Covering index, aggregation |
| Q5 | Laboratory | Oldest 50 lab orders still waiting after 24 hours | Index for filter + `ORDER BY` + `LIMIT` |
| Q6 | Admin / data quality | Patients registered who never booked | Subquery → anti-join transformation |

## 5. Results summary

Timings are the top-level `actual time` from `EXPLAIN ANALYZE` (ms, last row produced). They come from a test run on MySQL 8.0.46. **Replace them with the figures from your own run** (`evidence/baseline_plans.txt` and `evidence/optimised_plans.txt`); run each script 2–3 times and use the median.

| Query | Before: access path | Before (ms) | After: access path | After (ms) | Change |
|---|---|---:|---|---:|---|
| Q1 | Full table scan of 20,008 patients + sort | 6.6 | Index range scan on `idx_patient_name`, 62 rows, no sort | 0.34 | ~19× faster |
| Q2 | Reads all 60,003 branch-2 rows via FK index, applies `DATE()` to each | 60 | Rewrite + `idx_appt_branch_start`: range scan of exactly 160 rows | 1.0 | ~60× faster |
| Q3 | Full scan of 95,744 invoices; hash join with no condition | 94 | Range scan on `idx_invoice_issued` + aggregate-first rewrite | 71 | ~25% faster |
| Q4 | Full index scan of 120,007 entries + row lookups | 111 | Covering index range scan, 29,440 entries, no row lookups | 17 | ~6× faster |
| Q5 | Full scan of 38,241 orders + sort of 1,104 rows | 8.6 | Index range scan, stops after 50 rows, no sort | 0.8 | ~10× faster |
| Q6 | — | — | All three formulations → same nested-loop anti-join | 23–25 | No difference |

## 6. Analysis

### Q1 — Composite index for a search with a prefix
**Before.** No index starts with `last_name`, so MySQL reads all 20,008 patient rows, filters them down to 62 and then sorts them (`Table scan` → `Filter` → `Sort`).
**Fix.** `idx_patient_name (last_name, first_name)`. The equality column comes first, then the column used for the prefix range and the `ORDER BY`.
**After.** `Index range scan ... over (last_name = 'Okafor' AND 'Chi' <= first_name <= 'Chi…')`. Only the 62 matching index entries are read, and the sort step disappears because the index is already in `first_name` order.
**Counter-example.** `LIKE '%kafor'` still causes a full scan, even with the index. A B-tree is sorted from the first character, so a leading wildcard gives the optimiser no starting point.

### Q2 — A function on the column defeats the index (sargability)
**Before.** The only usable index is the foreign-key index on `branch_id`. MySQL fetches all 60,003 branch-2 appointments and evaluates `DATE(scheduled_start)` on each to keep 160.
**Step 1, index only.** After adding `idx_appt_branch_start (branch_id, scheduled_start)`, the original SQL uses the new index but still reads all branch-2 entries (estimate ≈ 59,893 rows). The `scheduled_start` part of the index is useless because the column is wrapped in `DATE()`. Index Condition Pushdown made the per-row test cheaper (60 ms → 8 ms), but the amount of work is the same.
**Step 2, rewrite.** `scheduled_start >= '2026-09-15' AND scheduled_start < '2026-09-16'` returns the same rows (the half-open range also covers times such as 23:59:59). The plan becomes `Index range scan over (branch_id = 2 AND '2026-09-15' <= scheduled_start < '2026-09-16')`, and the estimate falls from ~60,000 rows to exactly 160.
**Lesson.** An index only helps if the predicate is written so the optimiser can use it. Here the rewrite mattered more than the index.
**Side effect.** Because the new index starts with `branch_id`, InnoDB silently dropped its automatic FK index `fk_appt_branch`, which `SHOW INDEX` confirms. `06_reset_indexes.sql` therefore recreates it before dropping the new index.

### Q3 — An index alone did not help much
**Before.** A full scan of 95,744 invoices keeps 7,672 for September. The optimiser badly underestimated the join size (estimated 1,333 rows; actual 15,344). It joined `branch` early with a **hash join with no join condition**, which pairs every invoice with both branches before discarding half the rows.
**Step 1, index.** `idx_invoice_issued` turned the invoice access into a range scan (7,672 rows read instead of 95,744), but total time did not improve (94 → 116 ms). The join still pushed 32,326 rows through the plan, double the 16,163 needed.
**Step 2, rewrite.** Aggregating by `a.branch_id` in a derived table first, then joining the 2-row `branch` table to the 6 summary rows, removes the cross join: 16,163 rows flow through and the total falls to ~71 ms.
**Lesson.** The bottleneck was join order, not data access. Reading the plan, not just adding an index, found the real problem. The remaining cost is ~16,000 primary-key lookups through `encounter` → `appointment` to find the branch. Storing `branch_id` on `invoice` would remove that, but it would introduce a transitive dependency that Portfolio 1 deliberately avoided. For one month of data the normalised design is the better trade-off.

### Q4 — Covering index
**Before.** MySQL scanned the whole `uq_appt_doctor_slot` index (120,007 entries) because it is ordered by doctor, which suits the `GROUP BY`. It still had to fetch every table row to read `status` and test the date (111 ms).
**Fix.** `idx_appt_start_doctor_status (scheduled_start, doctor_id, status)` contains every column the query reads.
**After.** `Covering index range scan` reads only the 29,440 entries for the quarter and never touches the table rows (17 ms). Grouping now uses a small temporary table of 20 doctors, which costs far less than the row lookups it replaces.

### Q5 — Index that satisfies filter, ORDER BY and LIMIT together
**Before.** A full scan of 38,241 orders finds the 1,104 that are overdue and sorts them all to return 50.
**Fix.** `idx_laborder_status_ordered (status, ordered_at)`. Within `status = 'ORDERED'`, the entries are already in `ordered_at` order.
**After.** MySQL reads index entries in order and stops after 50 (`Limit` sits directly above the `Index range scan`; no `Sort`). The work no longer grows with table size.

### Q6 — The optimiser rewrites subqueries
`NOT IN`, `NOT EXISTS` and `LEFT JOIN … IS NULL` all produce the same **Nested loop antijoin**: for each patient, probe `fk_appt_patient` and stop at the first match (23–25 ms, 39 patients). This only works because `appointment.patient_id` is `NOT NULL`. If it were nullable, `NOT IN` would return no rows whenever the subquery contained a NULL, so `NOT EXISTS` is the safer habit. When the FK index is hidden with `IGNORE INDEX`, the optimiser switches strategy: it scans all 120,007 appointments once, builds a de-duplicated temporary table (`Materialize with deduplication`), then probes that (~58 ms).

### Cost of the indexes (`05_index_cost.sql`)
| Measure | Result (test run) |
|---|---|
| Space: the two new `appointment` indexes | 3.5 MB each (table's PK/clustered data 8.5 MB) |
| Space: `idx_patient_name`, `idx_invoice_issued`, `idx_laborder_status_ordered` | 0.5 MB, 2.5 MB, 1.5 MB |
| Insert 120,007 appointments, with Portfolio 2 indexes | ≈ 1,550 ms |
| Insert 120,007 appointments, without them | ≈ 1,200 ms |

The two extra appointment indexes make bulk inserts roughly **25–30% slower**. The clinic writes one appointment row per booking but reads appointment lists constantly, so the trade-off is worthwhile. A low-write, high-read workload is exactly where secondary indexes pay off. Indexes I considered and did **not** add:
- An index on `invoice.status`: only 4 values, so it is too unselective to help.
- A second index on `encounter.started_at`: no workload query needed it.

## 7. Key lessons

1. **Read the plan, not just the clock.** `EXPLAIN ANALYZE` shows both the optimiser's estimates and the actual rows. The large gap in Q3 (1,333 estimated vs 15,344 actual) explained its poor join choice.
2. **Write predicates the optimiser can use.** Q2 improved 60× mostly because of a rewrite, not because of an index.
3. **Design indexes for queries:** equality columns first, then the range/sort column, then any columns that make the index covering.
4. **Indexes have a cost.** They use extra disk space and slow inserts by roughly a quarter, so each one must be justified by a real query.

## 8. Evidence checklist (`evidence/`)

- [ ] `bulk_data_counts.png`: row counts and the zero-row invoice check from `01_bulk_data.sql`
- [ ] `baseline_plans.txt`: full output of `02_baseline_plans.sql`
- [ ] `optimised_plans.txt`: full output of `04_optimised_plans.sql`
- [ ] `index_cost.txt`: output of `05_index_cost.sql`
- [ ] `q2_visual_explain_before.png` / `q2_visual_explain_after.png`: Workbench Visual Explain for Q2 (original vs rewritten)
- [ ] `indexes_after.png`: index list from the end of `03_create_indexes.sql`, showing `fk_appt_branch` has gone

## 9. My notes

<!-- Write in your own words: which result surprised you, what you would
     check first next time a report is slow, and anything that behaved
     differently on your machine. -->
