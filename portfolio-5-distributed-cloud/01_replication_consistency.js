// =====================================================================
// LagosCare Clinics — Portfolio 5: Replication, consistency and availability
// on the MongoDB Atlas replica set used in Portfolio 4.
//
// Run:  mongosh "%ATLAS%" --username adebowale_db_user --password %MONGO_PW% 01_replication_consistency.js > evidence\replication_output.txt
//
// R1  Topology: the three members of the replica set and which is primary
// R2  Write concern: acknowledgement latency for w:1, w:"majority", w:3
// R3  Write concern that cannot be satisfied (w:5 on a 3-node set)
// R4  Read preference: which member actually serves a read
// R5  Stale reads: write w:1 then read immediately from a secondary
// R6  Read-your-writes on a secondary with a causally consistent session
// R7  Retryable writes / failover behaviour (what the driver does)
//
// Uses its own scratch collection (p5_replication_test), dropped at the end.
// =====================================================================
db = db.getSiblingDB("lagoscare");
const coll = db.getCollection("p5_replication_test");
coll.drop();
function heading(t) { print("\n" + "=".repeat(70) + "\n" + t + "\n" + "=".repeat(70)); }
function hostOf(explainResult) {
  const s = explainResult && explainResult.serverInfo;
  return s ? `${s.host}:${s.port}` : "(not reported)";
}
const median = a => { const s = [...a].sort((x, y) => x - y); return s[Math.floor(s.length / 2)]; };

// =====================================================================
// R1  Topology
// =====================================================================
heading("R1 Replica set topology");
const h = db.hello();
print(`replica set name : ${h.setName}`);
print(`primary          : ${h.primary}`);
print(`this connection  : ${h.me}`);
print(`data-bearing members (${h.hosts.length}):`);
h.hosts.forEach(x => print(`  ${x}${x === h.primary ? "   <- PRIMARY" : "   (secondary)"}`));
if (h.passives) h.passives.forEach(x => print(`  ${x}   (passive)`));
if (h.arbiters) h.arbiters.forEach(x => print(`  ${x}   (arbiter)`));
print(`majority = ${Math.floor(h.hosts.length / 2) + 1} of ${h.hosts.length} members`);
print(`server version   : ${db.version()}`);

// rs.status() gives member health and replication lag, but shared/free
// tiers may not allow it; skip gracefully if not permitted.
try {
  const st = rs.status();
  print("\nrs.status() members:");
  st.members.forEach(m => print(`  ${m.name}  ${m.stateStr}  health=${m.health}  optime=${m.optimeDate ? m.optimeDate.toISOString() : "-"}`));
} catch (e) {
  print(`\n(rs.status() not permitted on this tier: ${e.codeName || e.message})`);
}

// =====================================================================
// R2  Write concern latency
// w:1         acknowledged by the primary only
// w:"majority" acknowledged once 2 of 3 members have the write (durable
//              through a failover — it cannot be rolled back)
// w:3         acknowledged once ALL members have it (slowest; a single
//              slow or down member blocks the write)
// =====================================================================
heading("R2 Write concern: acknowledgement latency (60 inserts each)");
const N = 60;
const wcResults = [];
for (const w of [1, "majority", 3]) {
  const times = [];
  try {
    for (let i = 0; i < N; i++) {
      const t0 = Date.now();
      coll.insertOne({ kind: "wc", w: String(w), i, at: new Date() },
                     { writeConcern: { w, wtimeout: 5000 } });
      times.push(Date.now() - t0);
    }
  } catch (e) {
    print(`  w:${w} failed: ${e.codeName || e.message}`);
    continue;
  }
  const row = { writeConcern: String(w), median_ms: median(times),
                min_ms: Math.min(...times), max_ms: Math.max(...times) };
  wcResults.push(row);
  printjson(row);
}
print("Note: timings include the network round trip from this PC to Atlas;");
print("compare the DIFFERENCES between levels, not the absolute values.");

// =====================================================================
// R3  Unsatisfiable write concern
// =====================================================================
heading("R3 Write concern w:5 on a 3-member replica set");
try {
  coll.insertOne({ kind: "w5" }, { writeConcern: { w: 5, wtimeout: 3000 } });
  print("unexpected: write acknowledged");
} catch (e) {
  print(`refused: code ${e.code} ${e.codeName || ""} — ${e.errmsg || e.message}`);
  print("The server cannot promise acknowledgement from 5 members that do not exist.");
}

// =====================================================================
// R4  Read preference — which member serves the read?
// explain() reports the host that actually executed the query.
// =====================================================================
heading("R4 Read preference routing");
const q = { kind: "wc" };
for (const pref of ["primary", "primaryPreferred", "secondary", "secondaryPreferred", "nearest"]) {
  const served = [];
  db.getMongo().setReadPref(pref);                  // route the whole connection
  for (let i = 0; i < 5; i++) {
    try { served.push(hostOf(coll.find(q).readPref(pref).explain("queryPlanner"))); }
    catch (e) { served.push(`error: ${e.codeName || e.message}`); }
  }
  db.getMongo().setReadPref("primary");
  const distinct = [...new Set(served)];
  print(`  ${pref.padEnd(20)} served by: ${distinct.join(", ")}` +
        (distinct.includes(h.primary) ? "   (includes PRIMARY)" : ""));
}

// =====================================================================
// R5  Stale reads (replication lag made visible)
// Write with w:1 (primary only) and IMMEDIATELY read the same document
// from a secondary. If the secondary has not applied the write yet, the
// read returns nothing: a stale read. Repeat with w:"majority".
// =====================================================================
heading("R5 Stale reads from a secondary immediately after a write (200 tries each)");
const TRIES = 200;
for (const w of [1, "majority"]) {
  let stale = 0;
  for (let i = 0; i < TRIES; i++) {
    const id = `${w}-${i}`;
    coll.insertOne({ _id: id, kind: "stale-test" }, { writeConcern: { w } });
    const found = coll.find({ _id: id }).readPref("secondary").limit(1).toArray().length;
    if (found === 0) stale++;
  }
  print(`  write w:${String(w).padEnd(9)} -> secondary missed the write ${stale} of ${TRIES} times (${(100 * stale / TRIES).toFixed(1)}%)`);
}
print("w:'majority' only guarantees 2 of 3 members; the secondary that serves");
print("the read may be the third member, so stale reads are reduced, not removed.");

// =====================================================================
// R6  Read-your-writes on a secondary: causally consistent session
// The session carries the write's cluster time; a secondary read with
// readConcern "majority" waits until that secondary has caught up.
// =====================================================================
heading("R6 Causally consistent session: read-your-writes from a secondary");
const session = db.getMongo().startSession({ causalConsistency: true });
const scoll = session.getDatabase("lagoscare").getCollection("p5_replication_test");
let missed = 0;
for (let i = 0; i < TRIES; i++) {
  const id = `causal-${i}`;
  scoll.insertOne({ _id: id, kind: "causal" }, { writeConcern: { w: "majority" } });
  let found = 0;
  try {
    found = scoll.find({ _id: id }).readPref("secondary").readConcern("majority").limit(1).toArray().length;
  } catch (e) {
    if (i === 0) print(`  readConcern on cursor not supported here (${e.message}); using session default`);
    found = scoll.find({ _id: id }).readPref("secondary").limit(1).toArray().length;
  }
  if (found === 0) missed++;
}
session.endSession();
print(`  causal session: secondary missed the write ${missed} of ${TRIES} times`);
print("Expected 0: the driver makes the secondary wait until it has the write.");

// =====================================================================
// R7  Failover behaviour
// =====================================================================
heading("R7 Failover readiness");
const uriInfo = (() => { try { return db.getMongo()._uri || ""; } catch (e) { return ""; } })();
print(`retryWrites in connection string: ${/retryWrites=false/i.test(uriInfo) ? "false" : "true (driver default)"}`);
print("If the primary fails, the remaining two members (a majority) elect a new");
print("primary, typically within ~10-12 seconds. With retryable writes the driver");
print("re-sends an interrupted write once to the new primary, and writes made");
print("with w:'majority' are never rolled back. A w:1 write that reached only the");
print("old primary CAN be rolled back. (The free M0 tier cannot trigger a test");
print("failover; see README section 4.)");

// =====================================================================
heading("Summary");
wcResults.forEach(r => print(`  w:${r.writeConcern.padEnd(9)} median ${r.median_ms} ms (min ${r.min_ms}, max ${r.max_ms})`));
coll.drop();
print("\nScratch collection p5_replication_test dropped.");
