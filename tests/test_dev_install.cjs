// Real Git source transitions and file operations; only compositor commands and
// the network fetch are substituted. No access to the user's desktop.
const fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const assert = require('node:assert/strict');
const {spawnSync, execFileSync} = require('node:child_process');
const {createHash} = require('node:crypto');
const temp = fs.mkdtempSync(path.join(os.tmpdir(),'familiar-dev-test-'));
const home = path.join(temp,'home'), tools = path.join(temp,'tools');
const plugin = path.join(home,'.config/omarchy/plugins/io.github.tcballard.familiar-desktop');
const state = path.join(home,'.local/state/familiar-desktop');
const officialLibrary = path.join(temp,'system/titlebars.so');
const abi = 'efb50993780079460b0cbed1363e2166a2de1d9f_aq_0.15_hu_0.14_hg_0.5_hc_0.1_hlg_0.6';
const asset = `hyprbars-linux-x86_64-${abi}.so`;
const realGit = execFileSync('which',['git'],{encoding:'utf8'}).trim();
const sha = s => createHash('sha256').update(s).digest('hex');
const write = (p,s) => {fs.mkdirSync(path.dirname(p),{recursive:true});fs.writeFileSync(p,s,{mode:0o755});};
const env = {...process.env, HOME:home, XDG_CONFIG_HOME:path.join(home,'.config'), XDG_STATE_HOME:path.join(home,'.local/state'), PATH:tools+':'+process.env.PATH, CALLS:path.join(temp,'calls'), PLUGIN:plugin, ABI:abi};
const git = (...args) => execFileSync(realGit,['-C',plugin,...args],{env,encoding:'utf8',stdio:['ignore','pipe','pipe']}).trim();
const helper = label => `#!/bin/bash
set -eu
echo '${label}' "$(basename "$0") $*" >> "$CALLS"
if [[ "$1" == taskbar && "\u0024{FAIL_TASKBAR:-}" == 1 ]]; then exit 9; fi
if [[ "$1" == titlebars && "$2" == setup ]]; then
  [[ "\u0024{FAIL_SETUP:-}" != 1 ]] || exit 1
  # Like the real helper, --enable would reset user choices.
  if [[ " $* " == *' --enable '* ]]; then
    echo '{"dockEnabled":true,"titlebarMode":"windows"}' > "$HOME/.config/omarchy/familiar-desktop-settings.json"
  fi
  source="$(cd "$(dirname "$0")/.." && pwd)"
  [[ "$source" == "$PLUGIN" ]] || exit 22
  mkdir -p "$HOME/.config/omarchy/familiar-titlebars" "$HOME/.config/hypr"
  jq -n --arg source "$source" --arg library "$source/bin/hyprbars/$ABI/hyprbars.so" '{source:$source,library:$library,hookVersion:2}' > "$HOME/.config/omarchy/familiar-titlebars/owner.json"
  echo '-- BEGIN Familiar Desktop title bars' > "$HOME/.config/hypr/looknfeel.lua"
fi
`;
function sums(dir) {
  fs.writeFileSync(path.join(dir,'SHA256SUMS'),fs.readdirSync(dir).filter(n=>n!=='SHA256SUMS').map(n=>`${sha(fs.readFileSync(path.join(dir,n)))}  ${n}\n`).join(''));
}
function bundle(commit, label) {
  const dir = path.join(temp,label);fs.mkdirSync(dir);
  write(path.join(dir,'familiar-desktop-linux-x86_64'),helper(label));
  write(path.join(dir,asset),label+' library');
  write(path.join(dir,'install-dev.sh'),fs.readFileSync('scripts/install-dev.sh','utf8').replace('@SOURCE_SHA@',commit).replaceAll('/usr/lib/omarchy-hyprland-titlebars/titlebars.so',officialLibrary));
  write(path.join(dir,'DEV-BUILD.json'),JSON.stringify({schemaVersion:1,channel:'development',repository:'tcballard/omarchy-plugin-familiar-desktop',commit,runId:'123',runAttempt:'1',assets:{'familiar-desktop-linux-x86_64':sha(helper(label)),[asset]:sha(label+' library')}}));
  sums(dir);return dir;
}
function run(dir,args=[],extra={}) {return spawnSync('bash',[path.join(dir,'install-dev.sh'),...args],{env:{...env,...extra},encoding:'utf8'});}
function ok(result) {assert.equal(result.status,0,result.stdout+result.stderr);}
function status() {return spawnSync('bash',[path.join(plugin,'setup-in-app.sh'),'status'],{env,encoding:'utf8'});}
function log() {return fs.existsSync(env.CALLS)?fs.readFileSync(env.CALLS,'utf8'):'';}
try {
  fs.mkdirSync(tools);fs.mkdirSync(plugin,{recursive:true});
  write(path.join(tools,'git'),`#!/bin/bash\nif [[ "$3" == fetch ]]; then exec ${realGit} -C "$2" fetch --no-tags "$2" "\u0024{@: -1}"; fi\nexec ${realGit} "$@"\n`);
  write(path.join(tools,'hyprctl'),`#!/bin/bash\necho 'Version ABI string: ${abi}'\n`);
  write(path.join(tools,'omarchy'),`#!/usr/bin/env node
const fs=require('fs'), p=process.env.HOME+'/.config/omarchy/shell.json';
fs.appendFileSync(process.env.CALLS,'omarchy '+process.argv.slice(2).join(' ')+'\\n');
if (!fs.existsSync(p) || process.argv[2]!=='plugin') process.exit(0);
const c=JSON.parse(fs.readFileSync(p)), id=process.argv[4], key=v=>typeof v==='string'?v:v.id;
const lists=[...Object.values(c.bar.layout),c.plugins];
const found=lists.find(a=>a.some(v=>key(v)===id));
if(process.argv[3]==='disable' && found) found.splice(found.findIndex(v=>key(v)===id),1);
if(process.argv[3]==='enable' && !found) c.bar.layout.right.push({id});
if(process.argv[3]==='enable' && process.env.OTHER_EDIT==='1') c.idle.lock=900;
fs.writeFileSync(p,JSON.stringify(c));
`);
  git('init');git('config','user.email','fixture@example.invalid');git('config','user.name','Fixture');
  write(path.join(plugin,'.gitignore'),'/bin/\n');
  write(path.join(plugin,'release-binaries.sha256'),`${sha(helper('stable'))}  familiar-desktop-linux-x86_64\n${sha('stable library')}  ${asset}\n`);
  git('add','.');git('commit','-m','legacy without in-app setup');const legacy=git('rev-parse','HEAD');
  write(path.join(plugin,'setup-in-app.sh'),fs.readFileSync('setup-in-app.sh','utf8').replaceAll('/usr/lib/omarchy-hyprland-titlebars/titlebars.so',officialLibrary));
  write(path.join(plugin,'backend/src/titlebars.rs'),'// Familiar official-titlebar handoff v1');
  git('add','.');git('commit','-m','stable fixture');const stable=git('rev-parse','HEAD');
  write(path.join(plugin,'feature.txt'),'first');git('add','.');git('commit','-m','first');const first=git('rev-parse','HEAD');
  write(path.join(plugin,'feature.txt'),'second');git('add','.');git('commit','-m','second');const second=git('rev-parse','HEAD');
  git('checkout','--detach',stable);
  write(path.join(plugin,'bin/familiar-desktop'),helper('stable'));
  write(path.join(plugin,`bin/hyprbars/${abi}/hyprbars.so`),'stable library');
  const settings={titlebarStyle:'mac',titlebarMode:'off',dockEnabled:false,pinned:['preserved']};
  write(path.join(home,'.config/omarchy/familiar-desktop-settings.json'),JSON.stringify(settings));
  execFileSync(path.join(plugin,'bin/familiar-desktop'),['titlebars','setup'],{env});
  const a=bundle(first,'dev-a'), b=bundle(second,'dev-b');
  const shellPath=path.join(home,'.config/omarchy/shell.json');
  const shell={version:1,plugins:[{id:'io.github.tcballard.familiar-desktop',custom:42}],idle:{lock:300},
    bar:{position:'top',layout:{left:[{id:'omarchy.menu'}],center:[{id:'drawer',widgets:['io.github.tcballard.familiar-desktop']}],right:[{id:'omarchy.clock',format:'HH:mm'}]}}};
  write(shellPath,JSON.stringify(shell));
  const readShell=()=>JSON.parse(fs.readFileSync(shellPath));
  ok(status());
  // Official-package path supports source-matched install and rollback without
  // running private setup or changing preferences. The verified bundle helper
  // clears native actions before an older rollback helper replaces it.
  write(officialLibrary,'official');write(env.CALLS,'');
  ok(run(a)); assert.equal(git('rev-parse','HEAD'),first);ok(status());
  assert.doesNotMatch(log(),/titlebars setup/);
  assert.match(log(),/dev-a familiar-desktop titlebars disable/);
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(home,'.config/omarchy/familiar-desktop-settings.json'))),settings);
  ok(run(a,['--rollback']));assert.equal(git('rev-parse','HEAD'),stable);ok(status());
  assert.doesNotMatch(log(),/titlebars setup/);
  assert.ok(log().lastIndexOf('dev-a familiar-desktop titlebars disable') < log().lastIndexOf('stable familiar-desktop desktop restore'));
  assert.equal(fs.readFileSync(officialLibrary,'utf8'),'official');
  // Pre-guard sources cannot be installed over an official-package session.
  const unsafe=bundle(legacy,'unsafe');write(env.CALLS,'');
  assert.notEqual(run(unsafe).status,0);assert.equal(git('rev-parse','HEAD'),stable);
  assert.doesNotMatch(log(),/plugin disable/);
  fs.rmSync(officialLibrary);
  // Reject corrupted transport and source/receipt mismatch before disabling.
  write(env.CALLS,'');fs.appendFileSync(path.join(a,asset),'tamper');assert.notEqual(run(a).status,0);assert.doesNotMatch(log(),/plugin disable/);
  write(path.join(a,asset),'dev-a library');sums(a);
  const metadata=fs.readFileSync(path.join(a,'DEV-BUILD.json'),'utf8');
  write(path.join(a,'DEV-BUILD.json'),metadata.replace(first,second));sums(a);assert.notEqual(run(a).status,0);assert.doesNotMatch(log(),/plugin disable/);
  write(path.join(a,'DEV-BUILD.json'),metadata);sums(a);
  write(path.join(plugin,'personal.qml'),'local');assert.notEqual(run(a).status,0);fs.unlinkSync(path.join(plugin,'personal.qml'));
  // Stable -> development; status accepts exactly these bytes at this source.
  ok(run(a));assert.equal(git('rev-parse','HEAD'),first);ok(status());assert.equal(git('status','--porcelain'),'');
  assert.deepEqual(readShell(),shell);
  const snapA=fs.readFileSync(path.join(state,'dev-rollback'),'utf8').trim();
  assert.doesNotMatch(log(),/titlebars setup .*--enable/);
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(home,'.config/omarchy/familiar-desktop-settings.json'))),settings);
  assert.notEqual(spawnSync('bash',[path.join(plugin,'setup-in-app.sh'),'install'],{env}).status,0);
  fs.appendFileSync(path.join(plugin,'bin/familiar-desktop'),'# corruption\n');assert.notEqual(status().status,0);
  write(path.join(plugin,'bin/familiar-desktop'),helper('dev-a'));
  git('checkout','--detach',second);assert.notEqual(status().status,0);git('checkout','--detach',first);
  // Dev -> dev and rollback restores the previous receipt, not the stable pins.
  ok(run(b,[],{OTHER_EDIT:'1'}));assert.equal(git('rev-parse','HEAD'),second);ok(status());
  shell.idle.lock=900;assert.deepEqual(readShell(),shell);
  ok(run(b,['--rollback']));assert.equal(git('rev-parse','HEAD'),first);ok(status());
  assert.deepEqual(readShell(),shell);
  assert.equal(fs.readFileSync(path.join(plugin,'bin/familiar-desktop'),'utf8'),helper('dev-a'));
  // A rollback resets taskbar placement with the verified candidate helper before
  // replacing it with a pre-taskbar backend. A failure must stop the checkout.
  const taskbarRecord=path.join(state,'taskbar/placement.json');
  write(taskbarRecord,'{}');write(env.CALLS,'');
  const refused=run(a,['--rollback',snapA],{FAIL_TASKBAR:'1'});
  assert.notEqual(refused.status,0);assert.equal(git('rev-parse','HEAD'),first);
  assert.ok(log().includes('taskbar reset'));
  fs.rmSync(taskbarRecord);
  // Stable rollback restores exact bytes and removes the development receipt.
  ok(run(a,['--rollback',snapA]));assert.equal(git('rev-parse','HEAD'),stable);ok(status());assert.ok(!fs.existsSync(path.join(state,'dev-build.json')));
  assert.deepEqual(readShell(),shell);
  assert.equal(fs.readFileSync(path.join(plugin,'bin/familiar-desktop'),'utf8'),helper('stable'));
  // Failed setup leaves no enable call, with a usable recovery snapshot.
  write(env.CALLS,'');assert.notEqual(run(a,[],{FAIL_SETUP:'1'}).status,0);assert.doesNotMatch(log(),/plugin enable/);
  ok(run(a,['--rollback']));assert.equal(git('rev-parse','HEAD'),stable);ok(status());
  assert.deepEqual(readShell(),shell);
  // An inline-configured bar entry also retains its exact position/options.
  const entry=shell.plugins.pop();shell.bar.layout.left.push(entry);write(shellPath,JSON.stringify(shell));
  ok(run(a));assert.deepEqual(readShell(),shell);
  // Rollback after a completed install preserves a later personal move/edit.
  shell.bar.layout.left.pop();entry.custom=43;shell.bar.layout.center.push(entry);write(shellPath,JSON.stringify(shell));
  ok(run(a,['--rollback']));assert.deepEqual(readShell(),shell);
  // Regression: the XPS checkout predates setup-in-app.sh. Verify its original
  // pins/ownership without executing untrusted bytes, and support rollback too.
  git('checkout','--detach',legacy);assert.ok(!fs.existsSync(path.join(plugin,'setup-in-app.sh')));
  fs.appendFileSync(path.join(plugin,'bin/familiar-desktop'),'# tampered');write(env.CALLS,'');
  assert.notEqual(run(a).status,0);assert.equal(log(),'');
  write(path.join(plugin,'bin/familiar-desktop'),helper('stable'));
  ok(run(a));ok(status());ok(run(a,['--rollback']));
  assert.equal(git('rev-parse','HEAD'),legacy);assert.ok(!fs.existsSync(path.join(plugin,'setup-in-app.sh')));
  assert.equal(fs.readFileSync(path.join(plugin,'bin/familiar-desktop'),'utf8'),helper('stable'));
  git('checkout','--detach',stable);
  // Corrupt backups are never run during rollback.
  ok(run(a));const last=fs.readFileSync(path.join(state,'dev-rollback'),'utf8').trim();
  fs.appendFileSync(path.join(last,'familiar-desktop-linux-x86_64'),'bad');write(env.CALLS,'');assert.notEqual(run(a,['--rollback']).status,0);assert.equal(log(),'');
  // Shared setup lock excludes concurrent install operations.
  const locked=spawnSync('flock',[path.join(state,'setup.lock'),'bash',path.join(a,'install-dev.sh')],{env,encoding:'utf8'});assert.notEqual(locked.status,0);
  console.log('Development lifecycle passed: integrity, clean source, stable/dev updates, receipt binding, rollback, failed setup recovery and locking.');
} finally {fs.rmSync(temp,{recursive:true,force:true});}
