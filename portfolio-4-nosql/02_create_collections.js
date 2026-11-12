// =====================================================================
// LagosCare Clinics — Portfolio 4: Create collections with validation
// Run:  mongosh "mongodb://localhost:27017" 02_create_collections.js
//
// MongoDB is "schema-flexible", not "schema-less": $jsonSchema validators
// enforce the fields the clinic relies on (identity, dates, enums, value
// ranges) while still allowing optional, type-specific fields such as
// antenatal vitals or allergies. Fields not listed are allowed.
// =====================================================================
db = db.getSiblingDB("lagoscare");

["patients", "encounters", "pharmacy_stock", "bp_readings"].forEach(c => db.getCollection(c).drop());

const number = { bsonType: ["int", "long", "double", "decimal"] };

// ---------------------------------------------------------------------
// patients
// ---------------------------------------------------------------------
db.createCollection("patients", {
  validationLevel: "strict",
  validationAction: "error",
  validator: { $jsonSchema: {
    bsonType: "object",
    required: ["_id", "hospital_no", "name", "date_of_birth", "sex", "contact"],
    properties: {
      hospital_no:   { bsonType: "string", pattern: "^LC-[0-9]{6}$" },
      name: {
        bsonType: "object", required: ["first", "last"],
        properties: { first: { bsonType: "string" }, last: { bsonType: "string" } }
      },
      date_of_birth: { bsonType: "date" },
      sex:           { enum: ["M", "F"] },
      blood_group:   { enum: ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"] },
      contact: {
        bsonType: "object", required: ["phone"],
        properties: { phone: { bsonType: "string" }, email: { bsonType: "string" } }
      },
      hmo: {
        bsonType: "object", required: ["hmo_id", "name", "member_no"],
        properties: { coverage_percent: { bsonType: "decimal" } }
      },
      allergies:     { bsonType: "array", items: { bsonType: "string" } },
      visit_summary: {
        bsonType: "object", required: ["visits"],
        properties: { visits: { bsonType: "int", minimum: 0 }, last_visit: { bsonType: "date" } }
      }
    }
  } }
});

// ---------------------------------------------------------------------
// encounters
// ---------------------------------------------------------------------
db.createCollection("encounters", {
  validationLevel: "strict",
  validationAction: "error",
  validator: { $jsonSchema: {
    bsonType: "object",
    required: ["_id", "visit_type", "branch", "doctor", "patient", "started_at", "chief_complaint", "diagnoses"],
    properties: {
      visit_type: { enum: ["GENERAL", "PAEDIATRIC", "MEDICAL", "ANTENATAL"] },
      branch: {
        bsonType: "object", required: ["code"],
        properties: { code: { enum: ["IKJ", "LEK"] } }
      },
      doctor:  { bsonType: "object", required: ["staff_id", "name"] },
      patient: { bsonType: "object", required: ["patient_id", "hospital_no", "name"] },
      started_at: { bsonType: "date" },
      ended_at:   { bsonType: "date" },
      vitals: {
        bsonType: "object",
        properties: {
          temperature_c: { ...number, minimum: 30, maximum: 45 },
          pulse_bpm:     { ...number, minimum: 20, maximum: 250 },
          spo2_pct:      { ...number, minimum: 50, maximum: 100 },
          bp: {
            bsonType: "object", required: ["systolic", "diastolic"],
            properties: {
              systolic:  { ...number, minimum: 50, maximum: 260 },
              diastolic: { ...number, minimum: 30, maximum: 160 }
            }
          },
          gestational_age_weeks: { ...number, minimum: 4, maximum: 44 }
        }
      },
      diagnoses: {
        bsonType: "array", minItems: 1,
        items: {
          bsonType: "object", required: ["icd10", "primary"],
          properties: { icd10: { bsonType: "string" }, primary: { bsonType: "bool" } }
        }
      },
      lab_orders: {
        bsonType: "array",
        items: {
          bsonType: "object", required: ["lab_order_id", "test_code", "status"],
          properties: { status: { enum: ["ORDERED", "SAMPLE_COLLECTED", "COMPLETED", "CANCELLED"] } }
        }
      },
      prescriptions: {
        bsonType: "array",
        items: {
          bsonType: "object", required: ["prescription_id", "status", "items"],
          properties: { status: { enum: ["ISSUED", "DISPENSED", "CANCELLED"] } }
        }
      }
    }
  } }
});

// ---------------------------------------------------------------------
// pharmacy_stock — same rule as MySQL CHECK (quantity_on_hand >= 0)
// ---------------------------------------------------------------------
db.createCollection("pharmacy_stock", {
  validator: { $jsonSchema: {
    bsonType: "object",
    required: ["_id", "branch", "medication", "quantity_on_hand"],
    properties: {
      branch:           { enum: ["IKJ", "LEK"] },
      quantity_on_hand: { bsonType: "int", minimum: 0 },
      reorder_level:    { bsonType: "int", minimum: 0 }
    }
  } }
});

print("Collections created:");
db.getCollectionInfos({}, { nameOnly: false }).forEach(c =>
  print(`  ${c.name.padEnd(16)} validator: ${c.options.validator ? "yes" : "no"}`));
print("\nNext: run 03_import.cmd to load the JSON exported from MySQL.");
