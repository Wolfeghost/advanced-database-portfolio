// =====================================================================
// LagosCare Clinics — Portfolio 4: Queries, indexes and execution stats
// Run:  mongosh "mongodb://localhost:27017" 04_queries_indexes.js > evidence\queries_output.txt
//
// The same idea as Portfolio 2, on the document model: run each query
// with explain("executionStats") BEFORE and AFTER creating an index and
// compare documents examined, keys examined and time.
// Data ends on 21 Oct 2026, so "today" is fixed at 22 Oct 2026.
// =====================================================================
db = db.getSiblingDB("lagoscare");
const AS_OF   = ISODate("2026-10-22T00:00:00Z");
const DAYS    = n => new Date(AS_OF.getTime() - n * 24 * 3600 * 1000);
const results = [];

// ---- helper: pull the useful numbers out of an explain() result -------
function findKey(obj, key) {                    // depth-first search
  if (obj === null || typeof obj !== "object") return undefined;
  if (key in obj) return obj[key];
  for (const k of Object.keys(obj)) {
    const r = findKey(obj[k], key);
    if (r !== undefined) return r;
  }
  return undefined;
}
function stagesOf(plan, out = []) {             // list stage names, top-down
  if (plan === null || typeof plan !== "object") return out;
  if (plan.stage) out.push(plan.stage + (plan.indexName ? `(${plan.indexName})` : ""));
  for (const k of ["inputStage", "queryPlan"]) if (plan[k]) stagesOf(plan[k], out);
  if (Array.isArray(plan.inputStages)) plan.inputStages.forEach(p => stagesOf(p, out));
  return out;
}
function report(label, explainResult) {
  const s    = findKey(explainResult, "executionStats") || {};
  const plan = findKey(explainResult, "winningPlan") || {};
  const row = {
    query: label,
    plan: stagesOf(plan).join(" <- "),
    returned: s.nReturned,
    keysExamined: s.totalKeysExamined,
    docsExamined: s.totalDocsExamined,
    ms: s.executionTimeMillis
  };
  results.push(row);
  printjson(row);
}
function heading(t) { print("\n" + "=".repeat(70) + "\n" + t + "\n" + "=".repeat(70)); }

// Start from a clean slate: drop every index except _id
db.encounters.dropIndexes();
db.patients.dropIndexes();

heading("Collection sizes");
print(`patients:   ${db.patients.countDocuments()}`);
print(`encounters: ${db.encounters.countDocuments()}`);
// stats() is restricted on some hosted tiers (e.g. Atlas free M0), so it is optional
try { print(`avg encounter document size: ${Math.round(db.encounters.stats().avgObjSize)} bytes`); }
catch (e) { print(`(collection stats not available on this server: ${e.codeName || e.message})`); }

// =====================================================================
// M1  Patient history — everything about every visit in ONE query
//     (in MySQL this is a 9-table join: Portfolio 1 relational schema)
// =====================================================================
const PATIENT = 1234;
const m1 = () => db.encounters.find(
  { "patient.patient_id": PATIENT },
  { started_at: 1, "doctor.name": 1, "branch.code": 1, diagnoses: 1, "vitals.bp": 1, lab_orders: 1, prescriptions: 1 }
).sort({ started_at: -1 });

heading("M1 Patient history (patient_id " + PATIENT + ")");
print("Sample result (most recent visit):");
printjson(m1().limit(1).toArray());
report("M1 before index", m1().explain("executionStats"));

// =====================================================================
// M2  Lab worklist — Lekki encounters in the last 30 days with at least
//     one ABNORMAL result; show only the abnormal results ($filter)
// =====================================================================
const m2Filter = {
  "branch.code": "LEK",
  started_at: { $gte: DAYS(30), $lt: AS_OF },
  lab_orders: { $elemMatch: { "result.abnormal": true } }
};
const m2Pipeline = [
  { $match: m2Filter },
  { $sort: { started_at: -1 } },
  { $project: {
      _id: 1, started_at: 1, "patient.hospital_no": 1, "patient.name": 1, "doctor.name": 1,
      abnormal_results: { $filter: { input: "$lab_orders", as: "lo", cond: { $eq: ["$$lo.result.abnormal", true] } } }
  } }
];
heading("M2 Abnormal lab results, Lekki, last 30 days");
print(`matching encounters: ${db.encounters.countDocuments(m2Filter)}`);
printjson(db.encounters.aggregate(m2Pipeline).toArray().slice(0, 1));
report("M2 before index", db.encounters.explain("executionStats").aggregate(m2Pipeline));

// =====================================================================
// M3  Pre-eclampsia screen — antenatal visits at 20+ weeks with
//     systolic BP >= 140. These fields exist ONLY in antenatal documents.
// =====================================================================
const m3Filter = {
  visit_type: "ANTENATAL",
  "vitals.bp.systolic": { $gte: 140 },
  "vitals.gestational_age_weeks": { $gte: 20 }
};
const m3 = () => db.encounters.find(m3Filter,
  { started_at: 1, "patient.hospital_no": 1, "patient.name": 1, "vitals.bp": 1, "vitals.gestational_age_weeks": 1 })
  .sort({ "vitals.bp.systolic": -1 });
heading("M3 Antenatal high blood pressure screen");
print(`flagged visits: ${db.encounters.countDocuments(m3Filter)}`);
printjson(m3().limit(2).toArray());
report("M3 before index", m3().explain("executionStats"));

// =====================================================================
// CREATE INDEXES
// =====================================================================
heading("Creating indexes");

// M1: equality on patient, then sort key -> no in-memory SORT stage
db.encounters.createIndex({ "patient.patient_id": 1, started_at: -1 }, { name: "ix_patient_started" });

// M2: equality (branch), then range (date). lab_orders.result.abnormal is
// then checked on the few documents fetched.
db.encounters.createIndex({ "branch.code": 1, started_at: -1 }, { name: "ix_branch_started" });

// M3: PARTIAL index — only antenatal documents are indexed, so the index
// is small and contains nothing the screen does not need.
db.encounters.createIndex(
  { "vitals.bp.systolic": -1, "vitals.gestational_age_weeks": 1 },
  { name: "ix_antenatal_bp", partialFilterExpression: { visit_type: "ANTENATAL" } });

// M4: MULTIKEY index — one index entry per array element (diagnosis)
db.encounters.createIndex({ "diagnoses.icd10": 1, started_at: -1 }, { name: "ix_diagnosis_started" });

// M5: TEXT index on free-text clinical notes and complaint
db.encounters.createIndex({ notes: "text", chief_complaint: "text" },
  { name: "ix_notes_text", weights: { chief_complaint: 2, notes: 1 } });

// patients: natural key and allergy search (multikey on an array of strings)
db.patients.createIndex({ hospital_no: 1 }, { name: "ux_hospital_no", unique: true });
db.patients.createIndex({ allergies: 1 }, { name: "ix_allergies" });

db.encounters.getIndexes().forEach(ix => print(`  encounters.${ix.name}  ${JSON.stringify(ix.key)}` +
  (ix.partialFilterExpression ? `  partial: ${JSON.stringify(ix.partialFilterExpression)}` : "")));
db.patients.getIndexes().forEach(ix => print(`  patients.${ix.name}  ${JSON.stringify(ix.key)}`));

heading("Index sizes (bytes)");
try { printjson(db.encounters.stats().indexSizes); }
catch (e) { print(`(index sizes not available on this server: ${e.codeName || e.message})`); }

// =====================================================================
// AFTER indexes
// =====================================================================
heading("M1 / M2 / M3 after indexes");
report("M1 after index", m1().explain("executionStats"));
report("M2 after index", db.encounters.explain("executionStats").aggregate(m2Pipeline));
report("M3 after index", m3().explain("executionStats"));

// Partial-index rule: a query WITHOUT visit_type cannot use ix_antenatal_bp
report("M3 without visit_type (cannot use partial index)",
  db.encounters.find({ "vitals.bp.systolic": { $gte: 140 }, "vitals.gestational_age_weeks": { $gte: 20 } })
    .explain("executionStats"));

// =====================================================================
// M4  Top 5 primary diagnoses per branch, last 90 days (aggregation)
// =====================================================================
heading("M4 Top 5 primary diagnoses per branch, last 90 days");
const m4 = [
  { $match: { started_at: { $gte: DAYS(90), $lt: AS_OF } } },
  { $unwind: "$diagnoses" },
  { $match: { "diagnoses.primary": true } },
  { $group: { _id: { branch: "$branch.code", icd10: "$diagnoses.icd10" },
              description: { $first: "$diagnoses.description" },
              visits: { $sum: 1 } } },
  { $group: { _id: "$_id.branch",
              top5: { $topN: { n: 5, sortBy: { visits: -1 },
                               output: { icd10: "$_id.icd10", description: "$description", visits: "$visits" } } } } },
  { $sort: { _id: 1 } }
];
db.encounters.aggregate(m4).forEach(printjson);

// Malaria trend by month using the multikey diagnosis index
heading("M4b Monthly malaria (B54) visits — uses multikey index");
const m4b = [
  { $match: { "diagnoses.icd10": "B54", started_at: { $gte: DAYS(365), $lt: AS_OF } } },
  { $group: { _id: { $dateTrunc: { date: "$started_at", unit: "month", timezone: "Africa/Lagos" } }, visits: { $sum: 1 } } },
  { $sort: { _id: 1 } }
];
// $dateTrunc returns the month start in Lagos time, i.e. 23:00 UTC the day
// before; +1 hour gives the Lagos date, so October is not labelled September.
db.encounters.aggregate(m4b).forEach(r => print(`  ${new Date(r._id.getTime() + 3600e3).toISOString().slice(0, 7)}  ${r.visits}`));
report("M4b malaria by month", db.encounters.explain("executionStats").aggregate(m4b));

// =====================================================================
// M5  Free-text search of clinical notes (text index, relevance score)
// =====================================================================
heading("M5 Text search: 'wheeze inhaler'");
const m5 = () => db.encounters.find(
  { $text: { $search: "wheeze inhaler" } },
  { score: { $meta: "textScore" }, started_at: 1, "patient.hospital_no": 1, notes: 1 }
).sort({ score: { $meta: "textScore" } });
printjson(m5().limit(2).toArray());
report("M5 text search", m5().explain("executionStats"));

// =====================================================================
// M6  $lookup — penicillin-allergic patients seen in the last 30 days,
//     with their most recent visit (pharmacy safety list).
//     $lookup exists, but the model is designed so it is the exception.
// =====================================================================
heading("M6 Penicillin-allergic patients seen in the last 30 days ($lookup)");
const m6 = [
  { $match: { allergies: "Penicillin" } },
  { $lookup: {
      from: "encounters",
      let: { pid: "$_id" },
      pipeline: [
        { $match: { $expr: { $eq: ["$patient.patient_id", "$$pid"] }, started_at: { $gte: DAYS(30), $lt: AS_OF } } },
        { $sort: { started_at: -1 } },
        { $limit: 1 },
        { $project: { _id: 1, started_at: 1, "doctor.name": 1, "branch.code": 1, diagnoses: 1 } }
      ],
      as: "last_visit" } },
  { $match: { "last_visit.0": { $exists: true } } },
  { $project: { hospital_no: 1, name: 1, allergies: 1, last_visit: 1 } }
];
print(`patients on list: ${db.patients.aggregate([...m6, { $count: "n" }]).toArray()[0]?.n ?? 0}`);
printjson(db.patients.aggregate(m6).toArray().slice(0, 1));

// =====================================================================
heading("SUMMARY (copy into README section 6)");
print("query".padEnd(48) + "returned".padStart(9) + "keys".padStart(9) + "docs".padStart(9) + "ms".padStart(6) + "  plan");
results.forEach(r => print(
  String(r.query).padEnd(48) + String(r.returned).padStart(9) + String(r.keysExamined).padStart(9) +
  String(r.docsExamined).padStart(9) + String(r.ms).padStart(6) + "  " + r.plan));
