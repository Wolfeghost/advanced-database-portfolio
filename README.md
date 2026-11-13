# Advanced Database Systems Portfolio — MIT 8103

**Student:** Adebowale Ademosu (Student ID 301901129)

**Programme:** Master of Information Technology, MIVA Open University

**Session:** 2026/2027, First Semester

---

## Selected Case Study: LagosCare Clinics (simulated organisation)

**Organisation / scenario.** LagosCare Clinics is a simulated private outpatient clinic group operating two branches in Lagos, Nigeria (Ikeja and Lekki). It provides general medicine, paediatrics, internal medicine and obstetrics & gynaecology consultations, with an on-site laboratory and pharmacy at each branch. Many patients are covered by Health Maintenance Organisations (HMOs), which pay an agreed percentage of each bill.

**Nature of the business / system.** A clinical and administrative database that records the full outpatient journey: patient registration, appointment booking, the consultation (encounter), diagnoses, prescriptions, laboratory tests and results, pharmacy stock, billing and payment (patient and HMO portions).

**Users of the database.**

| User | Main use |
|---|---|
| Front-desk staff | Register patients, book and cancel appointments, check patients in |
| Doctors | Record consultations, diagnoses, prescriptions and lab requests; view patient history |
| Nurses | Record vitals and support consultations |
| Lab scientists | Receive lab orders and enter results |
| Pharmacists | Dispense prescriptions and manage branch stock |
| Billing / accounts | Generate invoices, record cash, card, transfer and HMO payments |
| Management | Reports on patient volume, revenue, HMO receivables and stock levels |

**Major data stored.** Branches, departments, staff and doctors, HMOs, patients, appointments, encounters, ICD-10 diagnosis codes, medications and branch stock, prescriptions, lab tests, lab orders and results, invoices, invoice lines and payments.

**Key operations supported.** Register patient; book appointment without double-booking a doctor; record consultation and diagnoses; issue prescription and dispense against stock; order lab test and record result; retrieve full patient history; generate invoice and split payment between patient and HMO; report outstanding balances and low stock.

## Technology Stack

| Area | Technology |
|---|---|
| Relational database | MySQL 8.0.46 (InnoDB), run locally |
| Client / modelling | MySQL Workbench 8.0 |
| NoSQL | MongoDB Atlas 8.0 (free M0 three-member replica set), mongosh, MongoDB Database Tools |
| Cloud / distributed | MongoDB Atlas replica set (tested); Azure Database for MySQL Flexible Server (design) |
| Version control | Git / GitHub (private repository) |

## Portfolios

| # | Portfolio | What it contains |
|---|---|---|
| 1 | [Database design](portfolio-1-database-design/) | ER model, normalised schema, seed data, constraint and trigger tests |
| 2 | [Query processing and optimisation](portfolio-2-query-optimisation/) | 20,000-patient bulk data, six workload queries, EXPLAIN ANALYZE before and after indexing, index write cost |
| 3 | [Transactions and concurrency](portfolio-3-transactions-concurrency/) | Stored procedures, commit/rollback/savepoint, two-session demos of dirty read, non-repeatable read, lost update, double payment, double booking and deadlock |
| 4 | [NoSQL (MongoDB)](portfolio-4-nosql/) | Document model with validators, indexed queries, updates and transactions, time-series blood pressure readings |
| 5 | [Distributed and cloud design](portfolio-5-distributed-cloud/) | Replication and consistency tests on Atlas, shard key simulation, Azure deployment and security design |

Each portfolio folder has its own README (design decisions, results, evidence checklist and my notes) and an `evidence/` folder with the outputs and screenshots from my own runs.

## Repository Structure

```
advanced-database-portfolio/
├── portfolio-1-database-design/          ER model, schema, constraints, normalisation
├── portfolio-2-query-optimisation/       Queries, EXPLAIN plans, indexing, performance analysis
├── portfolio-3-transactions-concurrency/ Commit, rollback, isolation, locking demos
├── portfolio-4-nosql/                    MongoDB model for the same clinic
├── portfolio-5-distributed-cloud/        Replication, sharding, Azure design
└── README.md
```

## Progress Log

| Date | Portfolio | Work completed |
|---|---|---|
| 12–13 Nov 2026 | Portfolio 1 | Case study, ER diagram, schema, seed data, constraint tests; run on MySQL 8.0.46 with evidence and EER diagram |
| 12–13 Nov 2026 | Portfolio 2 | Bulk data, baseline and optimised EXPLAIN ANALYZE plans, index cost test, Visual Explain screenshots |
| 12–13 Nov 2026 | Portfolio 3 | Procedures, commit/rollback demos and six two-session concurrency demos with 30 screenshots |
| 12–13 Nov 2026 | Portfolio 4 | MySQL export, Atlas import, validators, queries and indexes, updates and transactions, time series |
| 12–13 Nov 2026 | Portfolio 5 | Replication and consistency tests, shard key simulation, Azure architecture and security design |
| 13 Nov 2026 | All | Final documentation submitted on the LMS (Ademosu_Adebowale_301901129_Documentation) |
