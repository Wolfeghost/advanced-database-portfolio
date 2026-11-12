# LagosCare Clinics — ER Diagram

Crow's-foot notation. GitHub renders this diagram automatically. A second version reverse-engineered from the live database in MySQL Workbench is saved as `evidence/eer_diagram_workbench.png`.

```mermaid
erDiagram
    BRANCH ||--o{ DEPARTMENT : contains
    DEPARTMENT ||--o{ STAFF : employs
    STAFF ||--o| DOCTOR : "is a"
    HMO |o--o{ PATIENT : covers
    PATIENT ||--o{ APPOINTMENT : books
    DOCTOR ||--o{ APPOINTMENT : attends
    BRANCH ||--o{ APPOINTMENT : hosts
    APPOINTMENT ||--o| ENCOUNTER : "results in"
    ENCOUNTER ||--o{ ENCOUNTER_DIAGNOSIS : records
    DIAGNOSIS_CODE ||--o{ ENCOUNTER_DIAGNOSIS : classifies
    ENCOUNTER ||--o{ PRESCRIPTION : generates
    PRESCRIPTION ||--|{ PRESCRIPTION_ITEM : contains
    MEDICATION ||--o{ PRESCRIPTION_ITEM : "prescribed as"
    BRANCH ||--o{ PHARMACY_STOCK : stocks
    MEDICATION ||--o{ PHARMACY_STOCK : "held as"
    ENCOUNTER ||--o{ LAB_ORDER : requests
    LAB_TEST ||--o{ LAB_ORDER : "ordered as"
    LAB_ORDER ||--o| LAB_RESULT : produces
    STAFF ||--o{ LAB_RESULT : performs
    ENCOUNTER ||--o| INVOICE : "billed by"
    INVOICE ||--|{ INVOICE_LINE : itemises
    INVOICE ||--o{ PAYMENT : "settled by"

    BRANCH {
        smallint branch_id PK
        char branch_code UK
        varchar name
    }
    DEPARTMENT {
        smallint department_id PK
        smallint branch_id FK
        varchar name
    }
    STAFF {
        int staff_id PK
        smallint department_id FK
        enum role
        varchar email UK
    }
    DOCTOR {
        int staff_id PK, FK
        varchar specialty
        varchar mdcn_licence_no UK
        decimal consultation_fee
    }
    HMO {
        smallint hmo_id PK
        varchar name UK
        decimal coverage_percent
    }
    PATIENT {
        int patient_id PK
        varchar hospital_no UK
        date date_of_birth
        smallint hmo_id FK
        varchar hmo_member_no
    }
    APPOINTMENT {
        bigint appointment_id PK
        int patient_id FK
        int doctor_id FK
        smallint branch_id FK
        datetime scheduled_start
        enum status
    }
    ENCOUNTER {
        bigint encounter_id PK
        bigint appointment_id FK, UK
        varchar chief_complaint
    }
    DIAGNOSIS_CODE {
        varchar icd10_code PK
        varchar description
    }
    ENCOUNTER_DIAGNOSIS {
        bigint encounter_id PK, FK
        varchar icd10_code PK, FK
        boolean is_primary
    }
    MEDICATION {
        int medication_id PK
        varchar generic_name
        enum form
        decimal unit_price
    }
    PHARMACY_STOCK {
        smallint branch_id PK, FK
        int medication_id PK, FK
        int quantity_on_hand
    }
    PRESCRIPTION {
        bigint prescription_id PK
        bigint encounter_id FK
        enum status
    }
    PRESCRIPTION_ITEM {
        bigint prescription_id PK, FK
        int medication_id PK, FK
        smallint quantity
    }
    LAB_TEST {
        smallint lab_test_id PK
        varchar test_code UK
        varchar reference_range
        decimal price
    }
    LAB_ORDER {
        bigint lab_order_id PK
        bigint encounter_id FK
        smallint lab_test_id FK
        enum status
    }
    LAB_RESULT {
        bigint lab_order_id PK, FK
        varchar result_value
        int performed_by FK
    }
    INVOICE {
        bigint invoice_id PK
        bigint encounter_id FK, UK
        enum status
    }
    INVOICE_LINE {
        bigint invoice_id PK, FK
        smallint line_no PK
        enum item_type
        decimal unit_price
    }
    PAYMENT {
        bigint payment_id PK
        bigint invoice_id FK
        decimal amount
        enum method
        varchar reference UK
    }
```
