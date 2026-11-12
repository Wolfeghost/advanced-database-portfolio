// =====================================================================
// LagosCare Clinics — Portfolio 4: Updates, atomicity, transactions,
// schema evolution and validation
// Run:  mongosh "mongodb://localhost:27017" 05_updates_transactions.js > evidence\updates_output.txt
//
// U1–U3 work on a standalone server. U4 (multi-document transaction)
// needs a replica set — see README section 4 (a one-node replica set on
// your own PC is enough). If there is none, U4 explains and is skipped.
// =====================================================================
db = db.getSiblingDB("lagoscare");
function heading(t) { print("\n" + "=".repeat(70) + "\n" + t + "\n" + "=".repeat(70)); }

// =====================================================================
// U1  Single-document atomicity: record a lab result.
// Encounter 3 has a Urinalysis order (lab_order_id 5) still ORDERED.
// One updateOne changes the status AND adds the result inside the array
// element — MongoDB guarantees a single-document write is atomic, so no
// reader can ever see "COMPLETED" without its result.
// arrayFilters ($[lo]) picks the right element by its lab_order_id.
// =====================================================================
heading("U1 Record a lab result (atomic single-document update)");
printjson(db.encounters.findOne({ _id: 3 }, { lab_orders: 1 }));

const u1 = db.encounters.updateOne(
  { _id: 3, "lab_orders.lab_order_id": 5 },
  { $set: {
      "lab_orders.$[lo].status": "COMPLETED",
      "lab_orders.$[lo].result": {
        value: "Protein trace, glucose negative", abnormal: false,
        resulted_at: new Date(), performed_by: 8
      } } },
  { arrayFilters: [{ "lo.lab_order_id": 5 }] }
);
printjson(u1);
printjson(db.encounters.findOne({ _id: 3 }, { lab_orders: 1 }));

// =====================================================================
// U2  Schema evolution without a migration.
// The clinic starts telemedicine. New encounters carry a "telemedicine"
// sub-document; the 95,000 existing documents are left untouched and are
// still valid. In MySQL this needs ALTER TABLE (or a new table).
// =====================================================================
heading("U2 Schema evolution: a new field on new documents only");
db.encounters.deleteOne({ _id: 900001 });            // makes the demo re-runnable
const u2 = db.encounters.insertOne({
  _id: 900001,
  visit_type: "GENERAL",
  branch:  { code: "IKJ", name: "LagosCare Ikeja" },
  doctor:  { staff_id: 1, name: "Dr Adaeze Okonkwo", specialty: "General Practice" },
  patient: { patient_id: 6, hospital_no: "LC-000006", name: "Grace Etim", sex: "F" },
  started_at: ISODate("2026-10-21T15:00:00Z"),
  ended_at:   ISODate("2026-10-21T15:12:00Z"),
  chief_complaint: "Headache review",
  telemedicine: { platform: "Video", connection_quality: "Good", patient_location: "Home" },
  vitals: { temperature_c: 36.8, bp: { systolic: 128, diastolic: 82 } },   // patient-reported
  diagnoses: [{ icd10: "R51", description: "Headache", primary: true }],
  lab_orders: [], prescriptions: [],
  notes: "Video consultation. Headache resolving with paracetamol. Review if persists."
});
printjson(u2);
print(`encounters with telemedicine field: ${db.encounters.countDocuments({ telemedicine: { $exists: true } })}`);
print(`encounters without it:              ${db.encounters.countDocuments({ telemedicine: { $exists: false } })}`);

// Keep the computed visit_summary on the patient in step (computed pattern)
db.patients.updateOne({ _id: 6 },
  { $inc: { "visit_summary.visits": 1 }, $max: { "visit_summary.last_visit": ISODate("2026-10-21T15:00:00Z") } });
printjson(db.patients.findOne({ _id: 6 }, { hospital_no: 1, visit_summary: 1 }));

// =====================================================================
// U3  Validation: the $jsonSchema validator rejects bad documents
// =====================================================================
heading("U3 Validation rejects invalid documents");
function tryInsert(label, coll, doc) {
  try {
    db.getCollection(coll).insertOne(doc);
    print(`  ${label}: ACCEPTED (unexpected)`);
  } catch (e) {
    print(`  ${label}: REJECTED  code ${e.code} ${e.codeName || ""}`);
    const d = e.errInfo && e.errInfo.details;
    if (d) printjson(d.schemaRulesNotSatisfied);
  }
}
tryInsert("visit_type 'SURGERY' (not in enum)", "encounters", {
  _id: 900002, visit_type: "SURGERY", branch: { code: "IKJ" }, doctor: { staff_id: 1, name: "x" },
  patient: { patient_id: 1, hospital_no: "LC-000001", name: "x" }, started_at: new Date(),
  chief_complaint: "x", diagnoses: [{ icd10: "R51", primary: true }] });
tryInsert("no diagnosis (minItems 1)", "encounters", {
  _id: 900003, visit_type: "GENERAL", branch: { code: "IKJ" }, doctor: { staff_id: 1, name: "x" },
  patient: { patient_id: 1, hospital_no: "LC-000001", name: "x" }, started_at: new Date(),
  chief_complaint: "x", diagnoses: [] });
tryInsert("temperature 52 C (maximum 45)", "encounters", {
  _id: 900004, visit_type: "GENERAL", branch: { code: "IKJ" }, doctor: { staff_id: 1, name: "x" },
  patient: { patient_id: 1, hospital_no: "LC-000001", name: "x" }, started_at: new Date(),
  chief_complaint: "x", diagnoses: [{ icd10: "R51", primary: true }], vitals: { temperature_c: 52 } });
tryInsert("hospital_no 'ABC123' (pattern)", "patients", {
  _id: 999999, hospital_no: "ABC123", name: { first: "A", last: "B" },
  date_of_birth: ISODate("1990-01-01"), sex: "M", contact: { phone: "+234" } });
tryInsert("negative stock", "pharmacy_stock", {
  _id: "IKJ-99", branch: "IKJ", medication: { name: "Test" }, quantity_on_hand: -5 });

// =====================================================================
// U4  Multi-document ACID transaction: dispense prescription 4.
// Prescription 4 (encounter 4, Lekki) is still ISSUED: amlodipine x30,
// metformin x60. Dispensing changes THREE documents: two stock documents
// and the encounter. Each stock update only matches if enough stock
// remains (a guard in the filter — the same rule as the MySQL CHECK).
// If any step fails, abortTransaction() undoes all of them.
// =====================================================================
heading("U4 Multi-document transaction: dispense prescription 4");

const hello = db.hello();
if (!hello.setName) {
  print("This server is a standalone, not a replica set, so multi-document");
  print("transactions are not available. Convert it to a one-node replica set");
  print("(README section 4) and run this script again. Skipping U4.");
} else {
  print(`Replica set: ${hello.setName}`);

  function dispense(rxId, branch, items, label) {
    const session = db.getMongo().startSession();
    const sdb = session.getDatabase("lagoscare");
    session.startTransaction({ readConcern: { level: "snapshot" }, writeConcern: { w: "majority" } });
    try {
      for (const it of items) {
        const r = sdb.pharmacy_stock.updateOne(
          { _id: `${branch}-${it.medication_id}`, quantity_on_hand: { $gte: it.quantity } },
          { $inc: { quantity_on_hand: -it.quantity } });
        if (r.modifiedCount !== 1) throw new Error(`Insufficient stock for medication ${it.medication_id}`);
      }
      const r = sdb.encounters.updateOne(
        { prescriptions: { $elemMatch: { prescription_id: rxId, status: "ISSUED" } } },
        { $set: { "prescriptions.$[rx].status": "DISPENSED" } },
        { arrayFilters: [{ "rx.prescription_id": rxId }] });
      if (r.modifiedCount !== 1) throw new Error(`Prescription ${rxId} is not ISSUED`);
      session.commitTransaction();
      print(`  ${label}: COMMITTED`);
    } catch (e) {
      session.abortTransaction();
      print(`  ${label}: ABORTED — ${e.message}`);
    } finally {
      session.endSession();
    }
  }
  const showStock = () => db.pharmacy_stock.find({ _id: { $in: ["LEK-3", "LEK-4", "LEK-5"] } },
    { quantity_on_hand: 1 }).forEach(d => print(`    ${d._id}: ${d.quantity_on_hand}`));

  print("  stock before:"); showStock();

  // (a) succeeds
  dispense(4, "LEK", [{ medication_id: 3, quantity: 30 }, { medication_id: 4, quantity: 60 }], "(a) prescription 4");
  print("  stock after (a):"); showStock();
  printjson(db.encounters.findOne({ "prescriptions.prescription_id": 4 }, { _id: 1, "prescriptions.prescription_id": 1, "prescriptions.status": 1 }));

  // (b) fails on the SECOND item: the first item's stock change is rolled back
  dispense(4, "LEK", [{ medication_id: 3, quantity: 30 }, { medication_id: 5, quantity: 500 }], "(b) impossible quantity");
  print("  stock after (b) — unchanged from (a):"); showStock();

  // Put prescription 4 and the stock back so the demo can be repeated
  db.pharmacy_stock.updateOne({ _id: "LEK-3" }, { $inc: { quantity_on_hand: 30 } });
  db.pharmacy_stock.updateOne({ _id: "LEK-4" }, { $inc: { quantity_on_hand: 60 } });
  db.encounters.updateOne({ "prescriptions.prescription_id": 4 },
    { $set: { "prescriptions.$[rx].status": "ISSUED" } }, { arrayFilters: [{ "rx.prescription_id": 4 }] });
}
