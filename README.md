# Advanced Database Systems Portfolio — MIT 8103

**Student:** Adebowale Ademosu

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
| Relational database | MySQL 8.0 (InnoDB) |
| Client / modelling | MySQL Workbench 8.0 |
| NoSQL | MongoDB |
| Cloud / distributed | Microsoft Azure (Azure Database for MySQL Flexible Server, MongoDB-compatible service) |
| Version control | Git / GitHub (private repository) |

## Repository Structure

```
advanced-database-portfolio/
├── portfolio-1-database-design/        ER model, schema, constraints, normalisation
├── portfolio-2-query-optimisation/     Queries, EXPLAIN plans, indexing, performance analysis
├── portfolio-3-transactions-concurrency/ Commit, rollback, isolation, locking demos
├── portfolio-4-nosql/                  MongoDB model for the same clinic
├── portfolio-5-distributed-cloud/      Replication, sharding, Azure deployment
└── README.md
```

## Progress Log

| Date | Portfolio | Work completed |
|---|---|---|
| | Portfolio 1 | Case study, ER diagram, schema, seed data, constraint tests |
| | Portfolio 2 | |
| | Portfolio 3 | |
| | Portfolio 4 | |
| | Portfolio 5 | |
