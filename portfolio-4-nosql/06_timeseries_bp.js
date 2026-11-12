// =====================================================================
// LagosCare Clinics — Portfolio 4: Time-series collection
// Home blood-pressure monitoring programme
// Run:  mongosh "mongodb://localhost:27017" 06_timeseries_bp.js > evidence\timeseries_output.txt
//
// Scenario: patients diagnosed with hypertension (I10) are given a home BP
// monitor that uploads a reading every morning and evening. This is a
// different data shape from a consultation: many small, append-only,
// timestamped measurements. MongoDB's TIME-SERIES collections store them
// in compressed, column-wise buckets per patient (the metaField), similar
// in spirit to a column-family store.
// =====================================================================
db = db.getSiblingDB("lagoscare");
function heading(t) { print("\n" + "=".repeat(70) + "\n" + t + "\n" + "=".repeat(70)); }

db.bp_readings.drop();
db.createCollection("bp_readings", {
  timeseries: { timeField: "taken_at", metaField: "meta", granularity: "hours" }
});

// ---------------------------------------------------------------------
// Enrol the 40 most recent hypertensive patients
// ---------------------------------------------------------------------
const enrolled = db.encounters.aggregate([
  { $match: { diagnoses: { $elemMatch: { icd10: "I10", primary: true } } } },
  { $sort: { started_at: -1 } },
  { $group: { _id: "$patient.patient_id", hospital_no: { $first: "$patient.hospital_no" } } },
  { $sort: { _id: 1 } },
  { $limit: 40 }
]).toArray();
print(`Patients enrolled: ${enrolled.length}`);

// ---------------------------------------------------------------------
// Generate 60 days x 2 readings per patient (deterministic pseudo-random
// numbers, so every run gives the same data). Half the patients are
// "controlled" (BP drifts down); half stay high.
// ---------------------------------------------------------------------
// Park–Miller generator: products stay below 2^53, so JavaScript arithmetic is exact
let seed = 42;
const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
const START = ISODate("2026-08-23T05:00:00Z");      // 06:00 Lagos
const docs = [];
enrolled.forEach((p, i) => {
  const controlled = i % 2 === 0;
  for (let day = 0; day < 60; day++) {
    for (const hour of [0, 13]) {                     // ~06:00 and ~19:00 Lagos time
      const drift = controlled ? -0.35 * day : 0;
      docs.push({
        meta: { patient_id: p._id, hospital_no: p.hospital_no, device: `BPM-${1000 + p._id}` },
        taken_at: new Date(START.getTime() + (day * 24 + hour) * 3600e3 + Math.floor(rnd() * 40) * 60e3),
        systolic:  Math.round(152 + drift + rnd() * 16 - 8),
        diastolic: Math.round(95 + drift / 2 + rnd() * 10 - 5),
        pulse:     Math.round(70 + rnd() * 20)
      });
    }
  }
});
db.bp_readings.insertMany(docs);
print(`Readings inserted: ${db.bp_readings.countDocuments()}`);
print("One stored reading:");
printjson(db.bp_readings.findOne({}, { _id: 0 }));

// ---------------------------------------------------------------------
// T1 Weekly average per patient ($dateTrunc) — first 3 patients
// ---------------------------------------------------------------------
heading("T1 Weekly average BP, first 3 patients");
db.bp_readings.aggregate([
  { $match: { "meta.patient_id": { $in: enrolled.slice(0, 3).map(p => p._id) } } },
  { $group: {
      _id: { patient: "$meta.hospital_no",
             week: { $dateTrunc: { date: "$taken_at", unit: "week", timezone: "Africa/Lagos" } } },
      avg_sys: { $avg: "$systolic" }, avg_dia: { $avg: "$diastolic" }, readings: { $sum: 1 } } },
  { $sort: { "_id.patient": 1, "_id.week": 1 } },
  { $project: { _id: 0, patient: "$_id.patient", week: { $dateToString: { date: "$_id.week", format: "%Y-%m-%d", timezone: "Africa/Lagos" } },
                avg_sys: { $round: ["$avg_sys", 0] }, avg_dia: { $round: ["$avg_dia", 0] }, readings: 1 } }
]).forEach(r => print(`  ${r.patient}  week of ${r.week}  ${r.avg_sys}/${r.avg_dia}  (${r.readings} readings)`));

// ---------------------------------------------------------------------
// T2 Clinical alert: patients whose 7-day rolling average is still at or
// above the home-BP threshold of 135/85 at the end of the period.
// $setWindowFields computes a moving average over each patient's series.
// ---------------------------------------------------------------------
heading("T2 Patients still above 135/85 (7-day rolling average)");
const alerts = db.bp_readings.aggregate([
  { $setWindowFields: {
      partitionBy: "$meta.patient_id",
      sortBy: { taken_at: 1 },
      output: {
        sys_7d: { $avg: "$systolic",  window: { range: [-7, 0], unit: "day" } },
        dia_7d: { $avg: "$diastolic", window: { range: [-7, 0], unit: "day" } } } } },
  { $sort: { taken_at: 1 } },
  { $group: { _id: "$meta.hospital_no", sys_7d: { $last: "$sys_7d" }, dia_7d: { $last: "$dia_7d" } } },
  { $match: { $or: [{ sys_7d: { $gte: 135 } }, { dia_7d: { $gte: 85 } }] } },
  { $sort: { sys_7d: -1 } }
]).toArray();
print(`Patients needing review: ${alerts.length} of ${enrolled.length}`);
alerts.slice(0, 5).forEach(a => print(`  ${a._id}  ${Math.round(a.sys_7d)}/${Math.round(a.dia_7d)}`));

// ---------------------------------------------------------------------
// Storage: time-series buckets vs individual documents
// ---------------------------------------------------------------------
heading("Storage");
try {
  const ts = db.bp_readings.stats();
  print(`readings: ${db.bp_readings.countDocuments()}`);
  print(`storage size reported: ${ts.storageSize} bytes`);
  print("(Atlas shared tiers such as M0 may report a nominal storage size, so do not");
  print(" read this as bytes per reading; the bucket count below is the useful figure.)");
  if (ts.timeseries) print(`buckets: ${ts.timeseries.bucketCount}  (readings are grouped per patient into buckets)`);
} catch (e) {
  print(`(storage stats not available on this server: ${e.codeName || e.message})`);
}
