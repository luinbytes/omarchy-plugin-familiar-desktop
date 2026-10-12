const fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const assert = require('node:assert/strict');
const {spawnSync, spawn} = require('node:child_process');
const {createHash} = require('node:crypto');
const architecture = process.argv.includes('--arm') ? 'aarch64' : 'x86_64';
const abi = architecture === 'aarch64' ? '5c9377c15f85c50648f35ca5a213754f95b93ca0_aq_0.14_hu_0.14_hg_0.5_hc_0.1_hlg_0.6' : 'efb50993780079460b0cbed1363e2166a2de1d9f_aq_0.15_hu_0.14_hg_0.5_hc_0.1_hlg_0.6';
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'familiar-ui-setup-'));
const home = path.join(tmp,'home'), root = path.join(home,'.config/omarchy/plugins/io.github.tcballard.familiar-desktop');
const mock = path.join(tmp,'mock'), log = path.join(tmp,'calls');
fs.mkdirSync(path.join(root,'.git'), {recursive:true}); fs.mkdirSync(mock);
const officialLibrary = path.join(tmp,'system/titlebars.so');
fs.writeFileSync(path.join(root,'setup-in-app.sh'),fs.readFileSync('setup-in-app.sh','utf8').replaceAll('/usr/lib/omarchy-hyprland-titlebars/titlebars.so',officialLibrary));
fs.copyFileSync('bar-placement.sh',path.join(root,'bar-placement.sh'));
function write(p, s) { fs.mkdirSync(path.dirname(p),{recursive:true}); fs.writeFileSync(p,s,{mode:0o755}); }
const helper = `#!/bin/bash
set -e
printf '%s\\n' "$*" >> "$CALLS"
[[ "$*" != "$FAIL" ]] || { echo 'fixture failure' >&2; exit 1; }
if [[ "$*" == titlebars\\ setup* ]]; then
 mkdir -p "$HOME/.config/omarchy/familiar-titlebars" "$HOME/.config/hypr"
 jq -n --arg source "$ROOT" --arg library "$ROOT/bin/hyprbars/$ABI/hyprbars.so" '{source:$source,library:$library,hookVersion:2}' > "$HOME/.config/omarchy/familiar-titlebars/owner.json"
 echo '-- BEGIN Familiar Desktop title bars' > "$HOME/.config/hypr/looknfeel.lua"
 echo '{"state":"ready"}'
elif [[ "$*" == titlebars\\ apply* ]]; then echo '{"state":"active"}'; fi
`;
const library='fixture library';
const sha=s=>createHash('sha256').update(s).digest('hex');
write(path.join(root,'release-binaries.sha256'),`${sha(helper)}  familiar-desktop-linux-${architecture}\n${sha(library)}  hyprbars-linux-${architecture}-${abi}.so\n`);
write(path.join(tmp,'helper'),helper); write(path.join(tmp,'library'),library);
write(path.join(root,'install-backend.sh'),`#!/bin/bash\necho download-backend >> "$CALLS"\n[[ "$STALL" != 1 ]] || sleep 30\n[[ "$FAIL" != download ]] || exit 1\nmkdir -p "$ROOT/bin"\ncp "$FIXTURE/helper" "$ROOT/bin/familiar-desktop"\n[[ "$CORRUPT" != 1 ]] || echo corrupt >> "$ROOT/bin/familiar-desktop"\n`);
write(path.join(root,'install-titlebars.sh'),`#!/bin/bash\n[[ "$FAIL" != abi ]] || exit 1\n[[ "$1" != --check ]] || exit 0\necho download-titlebars >> "$CALLS"\nmkdir -p "$ROOT/bin/hyprbars/$ABI"\ncp "$FIXTURE/library" "$ROOT/bin/hyprbars/$ABI/hyprbars.so"\n`);
write(path.join(mock,'git'),'#!/bin/bash\nif [[ "$*" == *rev-parse* ]]; then printf "%040d\\n" 1; elif [[ "$DIRTY" == 1 ]]; then echo " M file"; fi\n');
write(path.join(mock,'uname'),`#!/bin/bash\nif [[ "$1" == -m ]]; then echo ${architecture}; else echo Linux; fi\n`);
for (const n of ['omarchy-shell','sudo','pkexec','foot','kitty']) write(path.join(mock,n),'#!/bin/bash\necho forbidden >> "$CALLS"\nexit 99\n');
write(path.join(mock,'omarchy'),'#!/bin/bash\n[[ "$1 $2 $3" == "bar move io.github.tcballard.familiar-desktop" ]] || { echo forbidden >> "$CALLS"; exit 99; }\necho "omarchy $*" >> "$CALLS"\n');
const env={...process.env,HOME:home,XDG_STATE_HOME:path.join(home,'.local/state'),XDG_CONFIG_HOME:path.join(home,'.config'),PATH:mock+':'+process.env.PATH,ROOT:root,FIXTURE:tmp,ABI:abi,CALLS:log};
write(path.join(mock,'hyprctl'),`#!/bin/bash\necho 'Version ABI string: ${abi}'\n`);
function run(mode, extra={}) { return spawnSync('bash',[path.join(root,'setup-in-app.sh'),mode,'mac'],{env:{...env,...extra},encoding:'utf8'}); }
(async () => {
try {
 assert.equal(run('status').status,3);
 let r=run('install'); assert.equal(r.status,0,r.stdout+r.stderr); assert.equal(run('status').status,0);
 let calls=fs.readFileSync(log,'utf8'); assert.match(calls,/titlebars setup .*--style mac/); assert.doesNotMatch(calls,/forbidden/);
 // Existing reviewed backend is recovered before replacement.
 r=run('install'); assert.equal(r.status,0,r.stdout+r.stderr); calls=fs.readFileSync(log,'utf8'); assert.match(calls,/desktop restore\ntitlebars disable\ndownload-backend/);
 // Failed/interrupted setup remains incomplete even when old assets exist.
 for(const failure of ['abi','download','titlebars apply --style mac --mode mac']) {
   r=run('install',{FAIL:failure}); assert.notEqual(r.status,0); assert.equal(run('status').status,3);
   assert.equal(run('install').status,0);
 }
 fs.writeFileSync(log,''); r=run('install',{CORRUPT:'1'}); assert.notEqual(r.status,0); assert.doesNotMatch(fs.readFileSync(log,'utf8'),/titlebars setup/); assert.equal(run('status').status,3);
 // A tampered existing binary is never executed, and successful retry replaces it.
 fs.writeFileSync(log,''); assert.equal(run('install').status,0); assert.doesNotMatch(fs.readFileSync(log,'utf8'),/desktop restore/);
 fs.writeFileSync(log,''); assert.notEqual(run('install',{DIRTY:'1'}).status,0); assert.equal(fs.readFileSync(log,'utf8'),'');
 fs.writeFileSync(path.join(home,'.local/state/familiar-desktop/setup-pending'),'interrupted'); assert.equal(run('status').status,3);
 // Real flock exclusion prevents duplicate setup, including after shell reload.
 const lock=spawnSync('flock',[path.join(home,'.local/state/familiar-desktop/setup.lock'),'bash',path.join(root,'setup-in-app.sh'),'install'],{env,encoding:'utf8'});
 assert.equal(lock.status,4,lock.stdout+lock.stderr);
 // TERM delivered through the same timeout supervisor used by QML must leave no active partial setup.
 fs.writeFileSync(log,'');
 const cancelled = await new Promise((resolve, reject) => {
   const child = spawn('timeout',['--kill-after=2','10','bash',path.join(root,'setup-in-app.sh'),'install','mac'],{env:{...env,STALL:'1'},stdio:'ignore'});
   const stop = setTimeout(() => child.kill('SIGTERM'), 200);
   child.on('error', reject);
   child.on('exit', code => { clearTimeout(stop); resolve(code); });
 });
 assert.notEqual(cancelled,0);
 let stopped = run('status').status;
 for(let i=0; stopped===4 && i<30; i++) { await new Promise(resolve=>setTimeout(resolve,100)); stopped=run('status').status; }
 assert.equal(stopped,3);
 assert.doesNotMatch(fs.readFileSync(log,'utf8'),/titlebars apply/);
 assert.equal(run('install').status,0);
 // Through a symlinked home, the checkout and the helper's canonical ownership
 // record (the backend derives it from its own executable path) still match.
 const link=path.join(tmp,'home-link');fs.symlinkSync(home,link);
 const linked={...env,HOME:link,XDG_STATE_HOME:path.join(link,'.local/state'),XDG_CONFIG_HOME:path.join(link,'.config')};
 const viaLink=mode=>spawnSync('bash',[path.join(link,'.config/omarchy/plugins/io.github.tcballard.familiar-desktop/setup-in-app.sh'),mode,'mac'],{env:linked,encoding:'utf8'});
 r=viaLink('install');assert.equal(r.status,0,r.stdout+r.stderr);assert.equal(viaLink('status').status,0);
 // Source-bound development setup uses local bytes and never release downloads.
 const state=path.join(home,'.local/state/familiar-desktop');
 write(path.join(state,'dev-build.json'),JSON.stringify({schemaVersion:1,channel:'development',sourceDirectory:root,commit:'1'.padStart(40,'0'),assets:{[`familiar-desktop-linux-${architecture}`]:sha(helper),[`hyprbars-linux-${architecture}-${abi}.so`]:sha(library)}}));
 assert.equal(run('status').status,0);
 assert.notEqual(run('install').status,0); // Ready development installs use their bundle for repair.
 write(path.join(state,'setup-pending'),'pending');write(log,'');
 r=run('install');assert.equal(r.status,0,r.stdout+r.stderr);assert.equal(run('status').status,0);
 assert.doesNotMatch(fs.readFileSync(log,'utf8'),/download-/);
 write(path.join(state,'setup-pending'),'pending');write(path.join(root,`bin/hyprbars/${abi}/hyprbars.so`),'corrupt');write(log,'');
 assert.notEqual(run('install').status,0);assert.equal(fs.readFileSync(log,'utf8'),'');
 fs.rmSync(path.join(state,'dev-build.json'));
 fs.rmSync(path.join(state,'setup-pending'));
 // Official hosts install only Familiar's helper; controls opt-in happens in UI.
 write(officialLibrary,'official');fs.writeFileSync(log,'');
 fs.rmSync(path.join(root,'bin/hyprbars'),{recursive:true,force:true});
 assert.equal(run('status').status,0);
 r=run('install');assert.equal(r.status,0,r.stdout+r.stderr);
 assert.doesNotMatch(fs.readFileSync(log,'utf8'),/download-titlebars|titlebars setup|titlebars apply/);
 // First-run development setup also accepts only the official-host backend.
 write(path.join(state,'dev-build.json'),JSON.stringify({schemaVersion:1,channel:'development',sourceDirectory:root,commit:'1'.padStart(40,'0'),renderer:'omarchy',assets:{[`familiar-desktop-linux-${architecture}`]:sha(helper)}}));
 write(path.join(state,'setup-pending'),'pending');write(log,'');
 r=run('install');assert.equal(r.status,0,r.stdout+r.stderr);assert.equal(run('status').status,0);
 assert.doesNotMatch(fs.readFileSync(log,'utf8'),/download-|titlebars setup|titlebars apply/);
 assert.equal(fs.readFileSync(officialLibrary,'utf8'),'official');
 console.log('In-app setup: fresh install, existing install, failure/retry, interrupted state, source refusal, corrupt bytes, and concurrency passed.');
} finally { fs.rmSync(tmp,{recursive:true,force:true}); }

})().catch(error => { console.error(error); process.exitCode = 1; });
