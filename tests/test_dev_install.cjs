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
const architecture = process.argv.includes('--arm') ? 'aarch64' : 'x86_64';
const abi = architecture === 'aarch64' ? '5c9377c15f85c50648f35ca5a213754f95b93ca0_aq_0.14_hu_0.14_hg_0.5_hc_0.1_hlg_0.6' : 'efb50993780079460b0cbed1363e2166a2de1d9f_aq_0.15_hu_0.14_hg_0.5_hc_0.1_hlg_0.6';
const backendAsset = `familiar-desktop-linux-${architecture}`;
const asset = `hyprbars-linux-${architecture}-${abi}.so`;
const realGit = execFileSync('bash',['-c','command -v git'],{encoding:'utf8'}).trim();
const sha = s => createHash('sha256').update(s).digest('hex');
const write = (p,s) => {fs.mkdirSync(path.dirname(p),{recursive:true});fs.writeFileSync(p,s,{mode:0o755});};
const env = {...process.env, HOME:home, XDG_CONFIG_HOME:path.join(home,'.config'), XDG_STATE_HOME:path.join(home,'.local/state'), PATH:tools+':'+process.env.PATH, CALLS:path.join(temp,'calls'), LOADED:path.join(temp,'loaded'), PLUGIN:plugin, ABI:abi};
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
  echo '{"state":"ready"}'
elif [[ "$1 $2" == 'titlebars apply' ]]; then echo '{"state":"active"}'
elif [[ "$1 $2" == 'titlebars remove' ]]; then
  # Like the real helper, keep Core delegation even after removing our hook.
  if ! jq -e '.backend == "omarchy"' "$HOME/.config/omarchy/familiar-titlebars/owner.json" >/dev/null 2>&1; then
    rm -f "$HOME/.config/omarchy/familiar-titlebars/owner.json"
  fi
  echo '' > "$HOME/.config/hypr/looknfeel.lua"
fi
`;
function sums(dir) {
  fs.writeFileSync(path.join(dir,'SHA256SUMS'),fs.readdirSync(dir).filter(n=>n!=='SHA256SUMS').map(n=>`${sha(fs.readFileSync(path.join(dir,n)))}  ${n}\n`).join(''));
}
function bundle(commit, label, official=false) {
  const dir = path.join(temp,label);fs.mkdirSync(dir);
  write(path.join(dir,backendAsset),helper(label));
  if(!official) write(path.join(dir,asset),label+' library');
  write(path.join(dir,'install-dev.sh'),fs.readFileSync('scripts/install-dev.sh','utf8').replace('@SOURCE_SHA@',commit).replaceAll('/usr/lib/omarchy-hyprland-titlebars/titlebars.so',officialLibrary));
  write(path.join(dir,'DEV-BUILD.json'),JSON.stringify({schemaVersion:1,channel:'development',repository:'tcballard/omarchy-plugin-familiar-desktop',commit,runId:'123',runAttempt:'1',renderer:official?'omarchy':'private',assets:{[backendAsset]:sha(helper(label)),...(!official?{[asset]:sha(label+' library')}:{})}}));
  sums(dir);return dir;
}
function run(dir,args=[],extra={}) {return spawnSync('bash',[path.join(dir,'install-dev.sh'),...args],{env:{...env,...extra},encoding:'utf8'});}
function ok(result) {assert.equal(result.status,0,result.stdout+result.stderr);}
function status() {return spawnSync('bash',[path.join(plugin,'setup-in-app.sh'),'status'],{env,encoding:'utf8'});}
function log() {return fs.existsSync(env.CALLS)?fs.readFileSync(env.CALLS,'utf8'):'';}
try {
  fs.mkdirSync(tools);fs.mkdirSync(plugin,{recursive:true});
  write(path.join(tools,'git'),`#!/bin/bash
if [[ "$3" == fetch ]]; then exec ${realGit} -C "$2" fetch --no-tags "$2" "\u0024{@: -1}"; fi
if [[ "$3" == checkout ]]; then
  [[ "$(cat "$LOADED")" == false ]] || { echo 'Source changed while loaded' >&2; exit 90; }
  echo checkout >> "$CALLS"
  [[ "\u0024{FAIL_CHECKOUT:-}" != 1 ]] || exit 7
fi
exec ${realGit} "$@"
`);
  write(path.join(tools,'install'),`#!/bin/bash
if [[ "$*" == *"$PLUGIN/bin/"* ]]; then
  [[ "$(cat "$LOADED")" == false ]] || { echo 'Binary changed while loaded' >&2; exit 90; }
  echo stage-binary >> "$CALLS"
fi
if [[ "\u0024{FAIL_STAGE:-}" == 1 && "$*" == *hyprbars-linux* ]]; then
  echo partial > "\u0024{@: -1}"
  exit 7
fi
exec /usr/bin/install "$@"
`);
  write(path.join(tools,'rm'),`#!/bin/bash
if [[ "$*" == *"$PLUGIN/bin/"* ]]; then
  [[ "$(cat "$LOADED")" == false ]] || { echo 'Binary removed while loaded' >&2; exit 90; }
  echo remove-binary >> "$CALLS"
fi
exec /usr/bin/rm "$@"
`);
  write(path.join(tools,'hyprctl'),`#!/bin/bash\necho 'Version ABI string: ${abi}'\n`);
  write(path.join(tools,'omarchy'),`#!/usr/bin/env node
const fs=require('fs'), p=process.env.HOME+'/.config/omarchy/shell.json';
fs.appendFileSync(process.env.CALLS,'omarchy '+process.argv.slice(2).join(' ')+'\\n');
if (!fs.existsSync(p)) process.exit(0);
const c=JSON.parse(fs.readFileSync(p)), id='io.github.tcballard.familiar-desktop', key=v=>typeof v==='string'?v:v.id;
const lists=[...Object.values(c.bar.layout),c.plugins];
const found=lists.find(a=>a.some(v=>key(v)===id));
if(process.argv[3]==='disable' && process.env.FAIL_DISABLE==='1') process.exit(7);
if(process.argv[3]==='disable') {
  // Cover placement removal and an explicitly configured disabledPlugins state.
  if (${architecture === 'aarch64'}) c.disabledPlugins=[...new Set([...(c.disabledPlugins||[]),id])];
  else if(found) found.splice(found.findIndex(v=>key(v)===id),1);
}
if(process.argv[3]==='enable' && !found) c.bar.layout.right.push({id});
if(process.argv[2]==='restart') {
  if(process.env.FAIL_QUIESCE==='1') process.exit(7);
  fs.writeFileSync(process.env.LOADED,String(!!found && !(c.disabledPlugins||[]).includes(id)));
  if(process.env.OTHER_EDIT==='1') c.idle.lock=900;
}
fs.writeFileSync(p,JSON.stringify(c));
`);
  write(path.join(tools,'uname'),`#!/bin/bash\nif [[ "$1" == -m ]]; then echo ${architecture}; else echo Linux; fi\n`);
  git('init');git('config','user.email','fixture@example.invalid');git('config','user.name','Fixture');
  write(path.join(plugin,'.gitignore'),'/bin/\n');
  write(path.join(plugin,'release-binaries.sha256'),`${sha(helper('stable'))}  ${backendAsset}\n${sha('stable library')}  ${asset}\n`);
  git('add','.');git('commit','-m','legacy without in-app setup');const legacy=git('rev-parse','HEAD');
  write(path.join(plugin,'setup-in-app.sh'),fs.readFileSync('setup-in-app.sh','utf8').replaceAll('/usr/lib/omarchy-hyprland-titlebars/titlebars.so',officialLibrary));
  write(path.join(plugin,'backend/src/titlebars.rs'),fs.readFileSync('backend/src/titlebars.rs'));
  write(path.join(plugin,'bar-placement.sh'),fs.readFileSync('bar-placement.sh','utf8'));
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
  const shell={version:1,plugins:[{id:'io.github.tcballard.familiar-desktop',custom:42}],disabledPlugins:[],idle:{lock:300},
    bar:{position:'top',layout:{left:[{id:'omarchy.menu'}],center:[{id:'drawer',widgets:['io.github.tcballard.familiar-desktop']}],right:[{id:'omarchy.clock',format:'HH:mm'}]}}};
  write(shellPath,JSON.stringify(shell));
  write(env.LOADED,'true');
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
  fs.appendFileSync(path.join(last,backendAsset),'bad');write(env.CALLS,'');assert.notEqual(run(a,['--rollback']).status,0);assert.equal(log(),'');
  // Shared setup lock excludes concurrent install operations.
  const locked=spawnSync('flock',[path.join(state,'setup.lock'),'bash',path.join(a,'install-dev.sh')],{env,encoding:'utf8'});assert.notEqual(locked.status,0);
  // Initial setup on a machine without release binaries stages verified bytes,
  // leaves activation to the normal setup UI, and rolls back to unfinished setup.
  git('checkout','--detach',stable);
  fs.rmSync(path.join(plugin,'bin'),{recursive:true});
  fs.rmSync(path.join(state,'dev-build.json'));
  fs.rmSync(path.join(home,'.config/omarchy/familiar-titlebars/owner.json'));
  write(path.join(home,'.config/hypr/looknfeel.lua'),'-- original');
  write(path.join(state,'setup-pending'),'original pending');
  write(env.CALLS,'');
  ok(run(a,['--initial']));assert.equal(git('rev-parse','HEAD'),first);
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(home,'.config/omarchy/familiar-desktop-settings.json'))),settings);
  assert.doesNotMatch(log(),/titlebars/);assert.equal(status().status,3);
  assert.ok(log().indexOf('plugin disable') < log().indexOf('checkout'));
  assert.deepEqual(readShell(),shell);assert.equal(fs.readFileSync(env.LOADED,'utf8'),'true');
  assert.notEqual(run(b,['--initial']).status,0);
  // Wrong target and corrupt receipt bytes stop before backend activation.
  const setup=()=>spawnSync('bash',[path.join(plugin,'setup-in-app.sh'),'install','mac'],{env,encoding:'utf8'});
  const receiptPath=path.join(state,'dev-build.json');const receiptBytes=fs.readFileSync(receiptPath);
  write(receiptPath,receiptBytes.toString().replace(asset,'hyprbars-linux-other-wrong.so'));write(env.CALLS,'');
  assert.notEqual(setup().status,0);assert.equal(log(),'');write(receiptPath,receiptBytes);
  ok(setup());ok(status());assert.doesNotMatch(log(),/download/);
  const afterSetupSettings=JSON.parse(fs.readFileSync(path.join(home,'.config/omarchy/familiar-desktop-settings.json')));
  ok(run(a,['--rollback']));assert.equal(git('rev-parse','HEAD'),stable);
  assert.ok(!fs.existsSync(path.join(plugin,'bin/familiar-desktop')));
  assert.ok(!fs.existsSync(receiptPath));assert.equal(fs.readFileSync(path.join(state,'setup-pending'),'utf8'),'original pending');
  assert.equal(status().status,3);
  assert.deepEqual(readShell(),shell);assert.equal(fs.readFileSync(env.LOADED,'utf8'),'true');
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(home,'.config/omarchy/familiar-desktop-settings.json'))),afterSetupSettings);
  // Interrupt after staging the backend but before the library/receipt. Rollback
  // verifies partial bytes without executing them and permits another initial try.
  write(env.CALLS,'');assert.notEqual(run(a,['--initial'],{FAIL_STAGE:'1'}).status,0);
  assert.ok(!fs.existsSync(receiptPath));assert.equal(fs.readFileSync(env.LOADED,'utf8'),'false');
  assert.doesNotMatch(log(),/familiar-desktop (desktop|titlebars)/);
  ok(run(a,['--rollback']));assert.equal(git('rev-parse','HEAD'),stable);
  assert.doesNotMatch(log(),/familiar-desktop (desktop|titlebars)/);
  assert.deepEqual(readShell(),shell);assert.equal(fs.readFileSync(env.LOADED,'utf8'),'true');
  ok(run(a,['--initial']));ok(run(a,['--rollback']));
  // Disable/restart/checkout failures never stage while loaded, and the saved
  // placement/activation survives recovery, including initially disabled users.
  for(const failure of ['FAIL_DISABLE','FAIL_QUIESCE','FAIL_CHECKOUT']) {
    write(env.CALLS,'');const failed=run(a,['--initial'],{[failure]:'1'});
    assert.notEqual(failed.status,0);assert.match(failed.stderr,/--rollback/);
    assert.doesNotMatch(log(),/stage-binary/);assert.equal(git('rev-parse','HEAD'),stable);
    ok(run(a,['--rollback']));assert.deepEqual(readShell(),shell);
  }
  shell.disabledPlugins.push('io.github.tcballard.familiar-desktop');
  write(shellPath,JSON.stringify(shell));write(env.LOADED,'false');
  ok(run(a,['--initial']));assert.deepEqual(readShell(),shell);
  assert.equal(fs.readFileSync(env.LOADED,'utf8'),'false');
  ok(run(a,['--rollback']));assert.deepEqual(readShell(),shell);
  assert.equal(fs.readFileSync(env.LOADED,'utf8'),'false');
  // Official ARM/x86 onboarding needs only the matching backend, with the same
  // guarded lifecycle and no private library or download. Rollback requires Core.
  shell.disabledPlugins=[];write(shellPath,JSON.stringify(shell));write(env.LOADED,'true');
  const native=bundle(first,'native','omarchy');write(env.CALLS,'');
  // CI's backend-only bundle must stop before disablement on a private host.
  assert.notEqual(run(native,['--initial']).status,0);assert.equal(log(),'');
  assert.equal(git('rev-parse','HEAD'),stable);assert.deepEqual(readShell(),shell);
  assert.equal(fs.readFileSync(env.LOADED,'utf8'),'true');
  write(officialLibrary,'official');
  ok(run(native,['--initial']));assert.deepEqual(readShell(),shell);
  assert.equal(status().status,3);ok(setup());ok(status());
  assert.ok(!fs.existsSync(path.join(plugin,'bin/hyprbars')));
  assert.doesNotMatch(log(),/titlebars setup|titlebars apply|download/);
  fs.rmSync(officialLibrary);write(env.CALLS,'');
  assert.notEqual(run(native,['--rollback']).status,0);assert.equal(log(),'');
  write(officialLibrary,'official');
  const ownerPath=path.join(home,'.config/omarchy/familiar-titlebars/owner.json');
  write(ownerPath,JSON.stringify({source:plugin,backend:'omarchy'}));
  ok(run(native,['--rollback']));assert.equal(git('rev-parse','HEAD'),stable);
  assert.match(log(),/native familiar-desktop titlebars remove/);
  assert.deepEqual(readShell(),shell);assert.equal(fs.readFileSync(env.LOADED,'utf8'),'true');
  assert.ok(!fs.existsSync(receiptPath));assert.ok(!fs.existsSync(path.join(plugin,'bin/familiar-desktop')));
  assert.equal(fs.readFileSync(officialLibrary,'utf8'),'official');
  // Core's inert delegation survives rollback and must not strand onboarding.
  const delegation=fs.readFileSync(ownerPath,'utf8');
  ok(run(native,['--initial']));ok(run(native,['--rollback']));
  assert.equal(fs.readFileSync(ownerPath,'utf8'),delegation);
  assert.notEqual(run(native,['--initial'],{FAIL_CHECKOUT:'1'}).status,0);
  const laterOwner=JSON.stringify({source:plugin,backend:'omarchy',instance:'later'});
  write(ownerPath,laterOwner);
  assert.notEqual(run(native,['--rollback']).status,0);
  assert.equal(fs.readFileSync(ownerPath,'utf8'),laterOwner);
  write(ownerPath,delegation);
  ok(run(native,['--rollback']));assert.deepEqual(readShell(),shell);
  assert.equal(fs.readFileSync(ownerPath,'utf8'),delegation);
  // An unrelated owner or any live hook is still refused before disablement.
  for(const owner of [{source:'/other',backend:'omarchy'},{source:plugin,backend:'familiar'}]) {
    write(ownerPath,JSON.stringify(owner));write(env.CALLS,'');
    assert.notEqual(run(native,['--initial']).status,0);assert.equal(log(),'');
  }
  write(ownerPath,delegation);write(path.join(home,'.config/hypr/looknfeel.lua'),'-- BEGIN Familiar Desktop title bars');
  write(env.CALLS,'');assert.notEqual(run(native,['--initial']).status,0);assert.equal(log(),'');
  console.log(`Development lifecycle (${architecture}) passed: integrity, clean source, stable/dev updates, initial setup, receipt binding, rollback, failed setup recovery and locking.`);
} finally {fs.rmSync(temp,{recursive:true,force:true});}
