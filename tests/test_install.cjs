const version = JSON.parse(require('node:fs').readFileSync('manifest.json')).version;
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const {spawnSync} = require('node:child_process');
const template = fs.readFileSync(path.resolve(__dirname, '../install.sh'), 'utf8');
const sourceSha = 'bda1ec617966b11fb8470788c74019350b38838f';
let passed = 0;
function run({existing=false, dirty=false, repair=false, failRepair=false, missing=false, style='mac', fault='', arch='x86_64', noCompiler=false, badAbi=false, titlebarFault='', lifecycle='', oldVersion='0.1.0', ignored='', flaky='', official=false }={}) {
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'familiar-install-'));
 try {
  // Adapt nixfred's official-package fixture to v0.1.6's supported renderer.
  const officialLibrary=path.join(root,'official/titlebars.so');
  if(official){fs.mkdirSync(path.dirname(officialLibrary));fs.writeFileSync(officialLibrary,'official package');}
  const withOfficial=source=>source.replaceAll('/usr/lib/omarchy-hyprland-titlebars/titlebars.so',officialLibrary);
  const installer=path.join(root,'install.sh');fs.writeFileSync(installer,withOfficial(template.replace('@SOURCE_SHA@',sourceSha)));
  const bin=path.join(root,'bin');fs.mkdirSync(bin);
  const plugin=path.join(root,'.config/omarchy/plugins/io.github.tcballard.familiar-desktop');
  // Bar placement reads XDG paths; keep them inside this fixture home, never the developer's desktop.
  fs.mkdirSync(path.join(root,'.config/omarchy'),{recursive:true});
  fs.writeFileSync(path.join(root,'.config/omarchy/shell.json'),JSON.stringify({bar:{layout:{right:['omarchy.tray','omarchy.agents']}}}));
  const fixture=path.join(root,'fixture');fs.mkdirSync(path.join(fixture,'.git'),{recursive:true});fs.mkdirSync(path.join(fixture,'bin'));
  fs.writeFileSync(path.join(fixture,'manifest.json'),'{}');
  fs.copyFileSync('bar-placement.sh',path.join(fixture,'bar-placement.sh'));
  fs.copyFileSync(path.resolve(__dirname,'../install-backend.sh'),path.join(fixture,'install-backend.sh'));
  fs.writeFileSync(path.join(fixture,'install-titlebars.sh'),withOfficial(fs.readFileSync(path.resolve(__dirname,'../install-titlebars.sh'),'utf8')));
  fs.writeFileSync(path.join(fixture,'build.sh'),'echo forbidden-build >> "$LOG"; exit 99\n');
  const old='previous backend';fs.writeFileSync(path.join(fixture,'bin/familiar-desktop'),old);
  const asset=path.join(root,'asset');
  fs.writeFileSync(asset,`#!/bin/bash\necho "helper $*" >> "$LOG"\nif [[ "$*" == *setup* ]]; then\n if [[ "$*" == *--install-dependency* ]]; then exit "$FAIL_REPAIR"; fi\n exit "$REPAIR"\nfi\necho familiar-desktop ${fault==='version'?'0.0.2':version}\n`);
  const titlebar=path.join(root,'hyprbars');fs.writeFileSync(titlebar,'fixture shared library');
  const titlebarHash=crypto.createHash('sha256').update(fs.readFileSync(titlebar)).digest('hex');
  const abi='efb50993780079460b0cbed1363e2166a2de1d9f_aq_0.15_hu_0.14_hg_0.5_hc_0.1_hlg_0.6';
  const hash=crypto.createHash('sha256').update(fs.readFileSync(asset)).digest('hex');
  fs.writeFileSync(path.join(root,'sums'),`${fault==='corrupt'?'0'.repeat(64):hash}  familiar-desktop-linux-x86_64\n`+(fault==='duplicate'?`${hash}  familiar-desktop-linux-x86_64\n`:''));
  fs.appendFileSync(path.join(root,'sums'),`${titlebarFault==='corrupt'?'0'.repeat(64):titlebarHash}  hyprbars-linux-x86_64-${abi}.so\n`);
  fs.copyFileSync(path.join(root,'sums'),path.join(fixture,'release-binaries.sha256'));
  // An attacker replaces both the release binary and its matching remote checksum.
  if(fault==='substitution') {
   fs.appendFileSync(asset,'echo attacker-executed >> "$LOG"\n');
   fs.writeFileSync(path.join(root,'sums'),crypto.createHash('sha256').update(fs.readFileSync(asset)).digest('hex')+'  familiar-desktop-linux-x86_64\n');
  }
  if(titlebarFault==='substitution') {
   fs.appendFileSync(titlebar,'substituted library');
   fs.writeFileSync(path.join(root,'sums'),crypto.createHash('sha256').update(fs.readFileSync(titlebar)).digest('hex')+'  hyprbars-linux-x86_64-'+abi+'.so\n');
  }
  if(existing)fs.cpSync(fixture,plugin,{recursive:true});
  if(lifecycle==='unmanaged') {fs.rmSync(path.join(plugin,'.git'),{recursive:true});}
  if(lifecycle)fs.writeFileSync(path.join(plugin,'bin/familiar-desktop'),`#!/bin/bash\necho "old-helper $*" >> "$LOG"\nif [[ "$1" == --version ]]; then echo 'familiar-desktop ${oldVersion}'; fi\nif [[ "$*" == 'desktop restore' && "$LIFECYCLE" == restore-failure ]]; then exit 1; fi\nif [[ "$*" == 'titlebars disable' && "$LIFECYCLE" == unload-failure ]]; then exit 1; fi\n`,{mode:0o755});
  if(lifecycle)fs.chmodSync(path.join(plugin,'bin/familiar-desktop'),0o755);
  const mock=`#!/bin/bash\nname="$(basename "$0")"\necho "$name $*" >> "$LOG"\ncase "$name" in\nomarchy) if [[ "$*" == plugin\\ add* ]]; then mkdir -p "$(dirname "$PLUGIN")"; cp -r "$FIXTURE" "$PLUGIN"; fi;;\ngit) case "$*" in\n *status*) if [[ "$LIFECYCLE" == status-failure ]]; then exit 1; fi; if [[ "$DIRTY" == 1 ]]; then echo ' M README.md'; elif [[ "$LIFECYCLE" == untracked || ( "$LIFECYCLE" == dirty-after-checkout && -f "$HOME/checked-out" ) ]]; then echo '?? user.qml'; fi;;\n *ls-files*) [[ "$LIFECYCLE" != ignored-failure ]] || exit 1; printf '%s' "$IGNORED";;\n *rev-parse*) if [[ \"$LIFECYCLE\" == wrong-source || ( \"$LIFECYCLE\" == wrong-checkout && -f \"$HOME/checked-out\" ) ]]; then echo bad; else echo '${sourceSha}'; fi;;\n *fetch*) [[ "$LIFECYCLE" != fetch-failure ]] || exit 1;;\n *checkout*) [[ "$LIFECYCLE" != checkout-failure ]] || exit 1; touch "$HOME/checked-out";;\n esac;;\nomarchy-shell) n="$(cat "$HOME/shell-calls" 2>/dev/null || echo 0)"; if [[ "$FLAKY" == always || ( "$FLAKY" == reload && $n -lt 3 ) ]]; then echo $((n+1)) > "$HOME/shell-calls"; echo 'Target not found.' >&2; exit 1; fi;;\nhyprctl) [[ "$MISSING" != 1 ]] || exit 1; echo "Version ABI string: $ABI";;\nuname) if [[ "$*" == -m ]]; then echo "$ARCH"; else echo Linux; fi;;\ncurl) [[ "$FAULT" != download ]] || exit 22; if [[ "$*" == *SHA256SUMS* ]]; then cp "$SUMS" "\${@: -1}"; elif [[ "$*" == *hyprbars-linux* ]]; then [[ "$TITLEBAR_FAULT" != download ]] || exit 22; cp "$TITLEBAR" "\${@: -1}"; else cp "$ASSET" "\${@: -1}"; fi;;\ncargo|rustup|clippy|make|cc) exit 99;;\nesac\n`;
  for(const name of ['omarchy','omarchy-shell','hyprctl','hyprpm','cargo','rustup','clippy','git','sudo','curl','uname',...(!noCompiler?['make','cc']:[])])fs.writeFileSync(path.join(bin,name),mock,{mode:0o755});
  const log=path.join(root,'calls');
  const p=spawnSync('/bin/bash',[installer,style],{encoding:'utf8',env:{...process.env,HOME:root,XDG_CONFIG_HOME:path.join(root,'.config'),XDG_STATE_HOME:path.join(root,'.local/state'),PATH:bin+':/usr/bin:/bin',LOG:log,PLUGIN:plugin,FIXTURE:fixture,ASSET:asset,SUMS:path.join(root,'sums'),FAULT:fault,LIFECYCLE:lifecycle,IGNORED:ignored,TITLEBAR_FAULT:titlebarFault,TITLEBAR:titlebar,ABI:badAbi?'unsupported':abi,ARCH:arch,DIRTY:+dirty+'',REPAIR:+repair+'',FAIL_REPAIR:+failRepair+'',MISSING:+missing+'',FLAKY:flaky}});
  const binary=path.join(plugin,'bin/familiar-desktop');
  if(official)assert.equal(fs.readFileSync(officialLibrary,'utf8'),'official package');
  return {...p,log:fs.existsSync(log)?fs.readFileSync(log,'utf8'):'',binary:fs.existsSync(binary)?fs.readFileSync(binary,'utf8'):null,staging:fs.existsSync(path.dirname(binary))?fs.readdirSync(path.dirname(binary)).filter(n=>n.startsWith('.download')):[]};
 }finally{fs.rmSync(root,{recursive:true,force:true});}
}
for(const existing of [false,true]){
 const r=run({existing});assert.equal(r.status,0,r.stderr);if(!existing)assert.match(r.log,/omarchy bar move io\.github\.tcballard\.familiar-desktop --after omarchy\.agents/);assert.equal(r.log.includes('omarchy plugin add'),!existing);assert.ok(r.log.includes(`checkout --detach ${sourceSha}\n`));assert.doesNotMatch(r.log,/--install-dependency|cargo|rustup|clippy|forbidden-build|sudo/);assert.ok(r.log.indexOf('helper --version')<r.log.indexOf('omarchy plugin enable'));assert.deepEqual(r.staging,[]);assert.doesNotMatch(r.log,/SHA256SUMS/);passed++;
}
let r=run({style:'windows'});assert.equal(r.status,0,r.stderr);assert.match(r.log,/setup --library .*hyprbars.so --enable --style windows/);passed++;
r=run({existing:true,dirty:true});assert.notEqual(r.status,0);assert.doesNotMatch(r.log,/checkout|helper|plugin enable/);passed++;
r=run({repair:true,failRepair:true});assert.notEqual(r.status,0);assert.doesNotMatch(r.log,/plugin enable/);passed++;
r=run({missing:true});assert.notEqual(r.status,0);assert.doesNotMatch(r.log,/plugin add|checkout/);passed++;
// The shell unloads the plugin while reloading after enable; refresh must retry, not abort.
r=run({flaky:'reload'});assert.equal(r.status,0,r.stderr);assert.match(r.log,/omarchy-shell io.github.tcballard.familiar-desktop refreshTitlebars/);passed++;
r=run({flaky:'always'});assert.notEqual(r.status,0);assert.match(r.stderr,/did not respond to 'refresh'/);passed++;
r=run({style:'bogus'});assert.notEqual(r.status,0);assert.equal(r.log,'');passed++;
for(const fault of ['download','corrupt','duplicate','version','substitution']){
 r=run({existing:true,fault});assert.notEqual(r.status,0);assert.equal(r.binary,'previous backend');assert.doesNotMatch(r.log,/setup|plugin enable|cargo|rustup|clippy|forbidden-build/);assert.deepEqual(r.staging,[]);if(fault==='corrupt'||fault==='substitution')assert.doesNotMatch(r.log,/helper/);
 // A failed download must report the exact release URL so setup logs are actionable (issue #79).
 if(fault==='download')assert.match(r.stderr,new RegExp(`Backend download failed: https://github\\.com/tcballard/omarchy-plugin-familiar-desktop/releases/download/v${version}/familiar-desktop-linux-x86_64`));
 passed++;
}
r=run({existing:true,arch:'aarch64'});assert.notEqual(r.status,0);assert.equal(r.binary,'previous backend');assert.match(r.stderr,/Linux x86_64/);assert.doesNotMatch(r.log,/curl|plugin enable/);passed++;
// The settings repair action must use the release installer, never a source build.
const widget=fs.readFileSync(path.resolve(__dirname,'../BarWidget.qml'),'utf8');assert.doesNotMatch(widget + fs.readFileSync("components/SettingsContent.qml", "utf8"), /Qt.resolvedUrl\("build.sh"\)/);
console.log(`${passed} installer scenarios passed (mock host; real SHA-256 verification).`);

for(const options of [{badAbi:true},{titlebarFault:'corrupt'},{titlebarFault:'substitution'},{titlebarFault:'download'},{repair:true}]) {
 const result=run(options);assert.notEqual(result.status,0);
 assert.doesNotMatch(result.log,/hyprpm|cargo|rustup|clippy|sudo|plugin enable/);
 if(!options.repair)assert.doesNotMatch(result.log,/helper titlebars setup/);
 if(options.badAbi)assert.doesNotMatch(result.log,/curl/);
 if(options.titlebarFault==='download')assert.match(result.stderr,new RegExp(`Window-controls download failed: https://github\\.com/tcballard/omarchy-plugin-familiar-desktop/releases/download/v${version}/hyprbars-linux-x86_64-`));
}
console.log('ABI mismatch, corrupt/missing Hyprbars, and loader rejection fail without source-build fallback.');

// Update ordering and refusal paths: old windows/controls must be recovered
// before source checkout; failures must not enable a partial installation.
// Every helper since 0.1.0 has `desktop restore`; only 0.0.x predates it.
for (const oldVersion of ['0.1.0', '0.1.4', '0.0.6']) {
 const result=run({existing:true,lifecycle:'success',oldVersion,ignored:'bin/familiar-desktop\nbin/hyprbars/abi/hyprbars.so\nbackend/target/debug/build-output'});
 assert.equal(result.status,0,result.stderr);
 const events=['old-helper titlebars disable','omarchy plugin disable','checkout --detach','helper titlebars setup','omarchy plugin enable'];
 if(oldVersion!=='0.0.6')events.unshift('old-helper desktop restore');
 else assert.doesNotMatch(result.log,/old-helper desktop restore/);
 for(const event of events)assert.ok(result.log.includes(event),`${oldVersion}: missing ${event}`);
 for(let i=1;i<events.length;i++)assert.ok(result.log.indexOf(events[i-1])<result.log.indexOf(events[i]),events.join(' -> '));
}
for (const lifecycle of ['unmanaged','untracked','status-failure','ignored-failure','fetch-failure','wrong-source','wrong-checkout','restore-failure','unload-failure','checkout-failure','dirty-after-checkout']) {
 const result=run({existing:true,lifecycle});
 assert.notEqual(result.status,0,lifecycle);
 assert.doesNotMatch(result.log,/helper titlebars setup|omarchy plugin enable/,lifecycle);
 if(!['checkout-failure','wrong-checkout','dirty-after-checkout'].includes(lifecycle))assert.doesNotMatch(result.log,/checkout --detach/,lifecycle);
 if(['checkout-failure','wrong-checkout','dirty-after-checkout'].includes(lifecycle))assert.match(result.stderr,/disabled for this update/);
}
for(const ignored of ['notes.qml','bin/.download.old/asset']) {
 const result=run({existing:true,lifecycle:'success',ignored});
 assert.notEqual(result.status,0);assert.match(result.stderr,/Unexpected ignored file/);
 assert.doesNotMatch(result.log,/plugin disable|checkout --detach|plugin enable/);
}
const incompatible=run({existing:true,lifecycle:'success',badAbi:true});
assert.doesNotMatch(incompatible.log,/plugin add|old-helper|plugin disable|checkout/);
console.log('14 update lifecycle scenarios passed: old-version migration, restore/unload ordering, unmanaged/untracked/ignored files, Git errors, ABI refusal and failed checkout.');
// Official hosts use the verified Familiar helper and leave Core's renderer
// alone, including when its ABI differs from Familiar's private release.
for(const existing of [false,true]) {
 const result=run({existing,lifecycle:existing?'success':'',oldVersion:'0.1.5',official:true,badAbi:true});
 assert.equal(result.status,0,result.stderr);
 assert.match(result.log,/plugin enable/);
 assert.doesNotMatch(result.log,/hyprbars-linux|helper titlebars setup/);
 assert.match(result.stdout,/Choose Use Familiar controls/);
 if(existing)assert.match(result.log,/old-helper desktop restore\nold-helper titlebars disable/);
 const failed=run({existing,official:true,badAbi:true,fault:'corrupt'});
 assert.notEqual(failed.status,0);
 assert.doesNotMatch(failed.log,/plugin enable|hyprbars-linux|helper titlebars setup/);
}
console.log('Official renderer: fresh/update success across private ABI mismatch, unchanged package and corrupt-backend refusal passed.');
