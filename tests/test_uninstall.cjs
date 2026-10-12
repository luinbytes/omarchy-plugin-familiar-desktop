const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const id = 'io.github.tcballard.familiar-desktop';
const steps = ['desktop prepare-remove', 'taskbar reset', `plugin disable ${id}`, 'caps-lock reset', 'input-preference command reset', 'input-preference resize reset', 'gestures reset', 'window-mode reset', 'titlebars remove', `plugin remove ${id} --yes`];
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'familiar-uninstall-'));
try {
  const installed = path.join(tmp, '.config/omarchy/plugins', id);
  const mock = path.join(tmp, 'mock');
  fs.mkdirSync(path.join(installed, 'bin'), {recursive:true});
  fs.mkdirSync(mock);
  // A development receipt describes the checkout that uninstall deletes; snapshots are recovery backups.
  const stateHome = path.join(tmp, '.local/state');
  const receipt = path.join(stateHome, 'familiar-desktop/dev-build.json');
  const snapshot = path.join(stateHome, 'familiar-desktop/dev-snapshots/build-fixture/snapshot.json');
  fs.mkdirSync(path.dirname(snapshot), {recursive:true});
  fs.writeFileSync(snapshot, '{}');
  fs.copyFileSync('uninstall.sh', path.join(installed, 'uninstall.sh'));
  const stub = `#!/usr/bin/env node\nconst fs=require('node:fs');const args=process.argv.slice(2).join(' ');fs.appendFileSync(process.env.TEST_LOG,args+'\\n');if(args===process.env.FAIL_STEP)process.exit(7);\n`;
  for (const filename of [path.join(installed, 'bin/familiar-desktop'), path.join(mock, 'omarchy')]) fs.writeFileSync(filename, stub, {mode:0o755});
  for (const failure of ['', ...steps]) {
    const log = path.join(tmp, 'calls');
    fs.writeFileSync(log, '');
    fs.writeFileSync(receipt, '{"channel":"development"}');
    const result = spawnSync('bash', [path.join(installed, 'uninstall.sh')], {encoding:'utf8', env:{...process.env, HOME:tmp, XDG_STATE_HOME:stateHome, PATH:mock+':'+process.env.PATH, TEST_LOG:log, FAIL_STEP:failure}});
    assert.equal(result.status === 0, failure === '', result.stderr);
    const expected = failure ? steps.slice(0, steps.indexOf(failure)+1) : steps;
    assert.deepEqual(fs.readFileSync(log, 'utf8').trim().split('\n'), expected);
    // Removed only after the plugin itself; a stale receipt blocks a later stable setup.
    assert.equal(fs.existsSync(receipt), failure !== '', failure);
    assert.ok(fs.existsSync(snapshot));
  }
  const log = path.join(tmp, 'calls'); fs.writeFileSync(log, '');
  const wrong = spawnSync('bash', ['uninstall.sh'], {encoding:'utf8', env:{...process.env, HOME:tmp, XDG_STATE_HOME:stateHome, PATH:mock+':'+process.env.PATH, TEST_LOG:log}});
  assert.notEqual(wrong.status,0);
  assert.equal(fs.readFileSync(log,'utf8'),'');
  console.log('uninstall sequencing, failure stops and checkout identity: 8 scenarios passed');
} finally { fs.rmSync(tmp, {recursive:true, force:true}); }
