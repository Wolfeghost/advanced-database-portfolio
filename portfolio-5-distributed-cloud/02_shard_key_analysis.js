// =====================================================================
// LagosCare Clinics — Portfolio 5: Shard key analysis (simulation)
// Run:  mongosh "%ATLAS%" --username adebowale_db_user --password %MONGO_PW% 02_shard_key_analysis.js > evidence\sharding_output.txt
//
// Atlas M0 cannot run a sharded cluster, so this script uses the REAL
// 95,745 encounters to simulate how four candidate shard keys would spread
// data and new writes across 3 shards, and which workload queries each key
// could route to a single shard ("targeted") versus all shards
// ("scatter-gather"). Read-only: nothing is modified.
//
//   A  { "branch.code": 1 }                         range
//   B  { started_at: 1 }                            range (monotonic)
//   C  { "patient.patient_id": "hashed" }           hashed
//   D  { "branch.code": 1, "patient.patient_id": 1 } range + zones per branch
// =====================================================================
db = db.getSiblingDB("lagoscare");
const enc = db.encounters;
const SHARDS = 3;
const AS_OF = ISODate("2026-10-22T00:00:00Z");
const DAYS = n => new Date(AS_OF.getTime() - n * 864e5);
function heading(t) { print("\n" + "=".repeat(70) + "\n" + t + "\n" + "=".repeat(70)); }
function spread(counts) {                     // counts: array of docs per shard
  const total = counts.reduce((a, b) => a + b, 0);
  const pct = counts.map(c => (100 * c / total).toFixed(1) + "%");
  const max = Math.max(...counts), ideal = total / counts.length;
  return `${counts.map((c, i) => `shard${i}: ${c}`).join("  ")}   (${pct.join(" / ")})  imbalance ${(max / ideal).toFixed(2)}x`;
}

// ---------------------------------------------------------------------
// Cardinality and frequency of each candidate field
// ---------------------------------------------------------------------
heading("Cardinality (distinct values) of candidate fields");
const total = enc.countDocuments();
const nBranch  = enc.distinct("branch.code").length;
const nPatient = enc.aggregate([{ $group: { _id: "$patient.patient_id" } }, { $count: "n" }]).toArray()[0].n;
const nStart   = enc.aggregate([{ $group: { _id: "$started_at" } }, { $count: "n" }]).toArray()[0].n;
print(`documents                 : ${total}`);
print(`branch.code               : ${nBranch} distinct  -> at most ${nBranch} chunks, ever`);
print(`patient.patient_id        : ${nPatient} distinct`);
print(`started_at                : ${nStart} distinct (but always increasing)`);
const busiest = enc.aggregate([{ $group: { _id: "$patient.patient_id", n: { $sum: 1 } } }, { $sort: { n: -1 } }, { $limit: 1 }]).toArray()[0];
print(`most visits by one patient: ${busiest.n} (patient ${busiest._id}) -> no risk of a jumbo chunk`);

// Helper: run a pipeline that adds a "shard" field, return docs per shard
function perShard(addShardStage, match = {}) {
  const rows = enc.aggregate([{ $match: match }, addShardStage,
    { $group: { _id: "$shard", n: { $sum: 1 } } }]).toArray();
  const counts = Array(SHARDS).fill(0);
  rows.forEach(r => { if (r._id !== null && r._id >= 0 && r._id < SHARDS) counts[r._id] = r.n; });
  return counts;
}

// ---------------------------------------------------------------------
// A  branch.code (range): IKJ -> shard0, LEK -> shard1, shard2 gets nothing
// ---------------------------------------------------------------------
const stageA = { $addFields: { shard: { $cond: [{ $eq: ["$branch.code", "IKJ"] }, 0, 1] } } };

// ---------------------------------------------------------------------
// B  started_at (range): history split into 3 equal time ranges
// ---------------------------------------------------------------------
const span = enc.aggregate([{ $group: { _id: null, lo: { $min: "$started_at" }, hi: { $max: "$started_at" } } }]).toArray()[0];
const third = (span.hi - span.lo) / 3;
const b1 = new Date(span.lo.getTime() + third), b2 = new Date(span.lo.getTime() + 2 * third);
const stageB = { $addFields: { shard: { $switch: { branches: [
  { case: { $lt: ["$started_at", b1] }, then: 0 },
  { case: { $lt: ["$started_at", b2] }, then: 1 }], default: 2 } } } };

// ---------------------------------------------------------------------
// C  hashed patient_id: MongoDB hashes the value to a 64-bit integer and
//    splits the hash space into contiguous ranges; 3 equal ranges here.
// ---------------------------------------------------------------------
const H1 = NumberLong("-3074457345618258602"), H2 = NumberLong("3074457345618258602");
const stageC = { $addFields: { h: { $toHashedIndexKey: "$patient.patient_id" } } };
const stageC2 = { $addFields: { shard: { $switch: { branches: [
  { case: { $lt: ["$h", H1] }, then: 0 },
  { case: { $lt: ["$h", H2] }, then: 1 }], default: 2 } } } };
function perShardC(match = {}) {
  const rows = enc.aggregate([{ $match: match }, stageC, stageC2,
    { $group: { _id: "$shard", n: { $sum: 1 } } }]).toArray();
  const counts = Array(SHARDS).fill(0);
  rows.forEach(r => counts[r._id] = r.n);
  return counts;
}

// ---------------------------------------------------------------------
// D  branch.code + patient_id with zones: zone IKJ -> shard0;
//    zone LEK -> shards 1 and 2, split at the median LEK patient_id
// ---------------------------------------------------------------------
const lekIds = enc.aggregate([{ $match: { "branch.code": "LEK" } }, { $sort: { "patient.patient_id": 1 } },
  { $group: { _id: null, ids: { $push: "$patient.patient_id" } } }]).toArray()[0].ids;
const lekMedian = lekIds[Math.floor(lekIds.length / 2)];
const stageD = { $addFields: { shard: { $cond: [{ $eq: ["$branch.code", "IKJ"] }, 0,
  { $cond: [{ $lt: ["$patient.patient_id", lekMedian] }, 1, 2] }] } } };

// =====================================================================
heading(`Data distribution across ${SHARDS} shards (all ${total} encounters)`);
const distAll = { A: perShard(stageA), B: perShard(stageB), C: perShardC(), D: perShard(stageD) };
print(`A branch.code            ${spread(distAll.A)}`);
print(`B started_at (range)     ${spread(distAll.B)}`);
print(`C patient_id (hashed)    ${spread(distAll.C)}`);
print(`D branch + patient zones ${spread(distAll.D)}`);

heading("Where NEW writes land: encounters from the last 30 days");
const recent = { started_at: { $gte: DAYS(30), $lt: AS_OF } };
const distNew = { A: perShard(stageA, recent), B: perShard(stageB, recent), C: perShardC(recent), D: perShard(stageD, recent) };
print(`A branch.code            ${spread(distNew.A)}`);
print(`B started_at (range)     ${spread(distNew.B)}   <- every new visit goes to the LAST shard`);
print(`C patient_id (hashed)    ${spread(distNew.C)}`);
print(`D branch + patient zones ${spread(distNew.D)}`);

// =====================================================================
// Query routing. mongos can target a query only when the filter contains
// the shard key (or, for a compound key, its leading field). For one
// concrete patient, show where that patient's documents live.
// =====================================================================
heading("Query routing for the Portfolio 4 workload");
const PATIENT = 1234;
const homesOf = stage => enc.aggregate([{ $match: { "patient.patient_id": PATIENT } }, ...(Array.isArray(stage) ? stage : [stage]),
  { $group: { _id: "$shard" } }]).toArray().map(r => r._id).sort();
print(`patient ${PATIENT}'s encounters live on: A ${JSON.stringify(homesOf(stageA))}  B ${JSON.stringify(homesOf(stageB))}  ` +
      `C ${JSON.stringify(homesOf([stageC, stageC2]))}  D ${JSON.stringify(homesOf(stageD))}`);
print("");
print("Query (filter)                                   A branch   B date     C hashed pid  D branch+pid");
print("M1 patient history {patient_id}                  all 3      all 3      1 (targeted)  all 3*");
print("M2 Lekki, last 30 days {branch, started_at}      1          1 (hot)    all 3         LEK zone (2)");
print("M3 antenatal BP screen {visit_type, vitals}      all 3      all 3      all 3         all 3");
print("M4b malaria by month {icd10, started_at range}   all 3      all 3      all 3         all 3");
print("* D targets 1 shard if the query also includes branch.code (the front desk knows the branch).");

// =====================================================================
heading("Summary");
const imb = c => (Math.max(...c) / (c.reduce((a, b) => a + b, 0) / c.length)).toFixed(2);
print("key                       all-data imbalance   new-write imbalance");
for (const k of ["A", "B", "C", "D"]) print(`  ${k}                       ${imb(distAll[k]).padEnd(20)} ${imb(distNew[k])}`);
print("\n1.00x = perfectly even. 3.00x = everything on one shard.");
