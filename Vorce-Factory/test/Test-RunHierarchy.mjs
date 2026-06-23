import assert from 'assert/strict';
import path from 'path';
import { fileURLToPath } from 'url';
import { getRunHierarchy } from '../web/Dashboard/src/runHierarchy.js';

const moduleDir = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = process.argv[2] ? path.resolve(process.argv[2]) : path.resolve(moduleDir, '..');

const hierarchy = getRunHierarchy({ vorceRoot: projectRoot });

assert.equal(hierarchy.schema_version, 1);
assert.equal(hierarchy.main_runs.length, 5, 'exactly 5 MAIN-RUN roots are required');
assert.equal(hierarchy.main_runs.reduce((sum, main) => sum + main.sub_runs.length, 0), 17, 'exactly 17 SUB-RUNs are required');
assert.equal(
  hierarchy.main_runs.reduce((sum, main) => sum + main.sub_runs.reduce((subSum, sub) => subSum + sub.part_runs.length, 0), 0),
  18,
  'exactly 18 PART-RUNs are required'
);

const canonicalPartState = hierarchy.legacy_orphan_states.find(state => state.source_file === 'PART_PART-RUN-01_MR-01_Planning__Strategy__CreateProposal.json');
assert.equal(canonicalPartState, undefined, 'canonical PART states must not be listed as legacy orphans');

const legacyPartState = hierarchy.legacy_orphan_states.find(state => state.source_file === 'PART_FetchIssues.json');
assert.ok(legacyPartState, 'legacy PART states must remain listed as legacy orphans');

for (const main of hierarchy.main_runs) {
  assert.ok(main.latest_state_path === null || typeof main.latest_state_path === 'string');
  assert.equal(main.sub_runs.length > 0, true, `${main.name} must have sub-runs`);
  for (const sub of main.sub_runs) {
    assert.equal(sub.parent_main_name, main.name);
    assert.ok(sub.latest_state_path === null || typeof sub.latest_state_path === 'string');
    for (const part of sub.part_runs) {
      assert.equal(part.parent_main_name, main.name);
      assert.equal(part.parent_sub_name, sub.name);
      assert.ok(part.latest_state_path === null || typeof part.latest_state_path === 'string');
    }
  }
}

console.log(JSON.stringify({
  passed: true,
  main_runs: hierarchy.main_runs.length,
  sub_runs: hierarchy.main_runs.reduce((sum, main) => sum + main.sub_runs.length, 0),
  part_runs: hierarchy.main_runs.reduce((sum, main) => sum + main.sub_runs.reduce((subSum, sub) => subSum + sub.part_runs.length, 0), 0),
  legacy_orphans: hierarchy.legacy_orphan_states.length
}, null, 2));
