// Real Git regression: a moving remote branch/tag must never reach registration
// or executable installer paths. Host services are fixtures; no desktop claims.
const fs=require('node:fs'), path=require('node:path'), os=require('node:os');
const assert=require('node:assert/strict');
const {spawnSync}=require('node:child_process');
const realGit=spawnSync('bash',['-c','command -v git'],{encoding:'utf8'}).stdout.trim();
const source=fs.readFileSync('install.sh','utf8');
const root=fs.mkdtempSync(path.join(os.tmpdir(),'familiar-source-pin-'));
function git(args,cwd){const r=spawnSync(realGit,args,{cwd,encoding:'utf8'});assert.equal(r.status,0,r.stderr);return r.stdout.trim();}
function write(p,s){fs.writeFileSync(p,s,{mode:0o755});}
try {
 const remote=path.join(root,'remote');fs.mkdirSync(remote);git(['init'],remote);
 git(['config','user.name','Fixture'],remote);git(['config','user.email','fixture@example.invalid'],remote);
 write(path.join(remote,'bar-placement.sh'),fs.readFileSync('bar-placement.sh','utf8'));
 write(path.join(remote,'install-titlebars.sh'),'#!/bin/bash\necho "trusted-titlebars $*" >> "$LOG"\necho /fixture/hyprbars.so\n');
 write(path.join(remote,'install-backend.sh'),'#!/bin/bash\necho trusted-backend >> "$LOG"\nmkdir -p "$PLUGIN/bin"\nprintf \'#!/bin/bash\\necho familiar-desktop 0.1.1\\n\' > "$PLUGIN/bin/familiar-desktop"\nchmod +x "$PLUGIN/bin/familiar-desktop"\n');
 write(path.join(remote,'manifest.json'),'{"id":"io.github.tcballard.familiar-desktop"}');
 git(['add','.'],remote);git(['commit','-m','Reviewed fixture'],remote);const pin=git(['rev-parse','HEAD'],remote);
 git(['tag','v0.1.1'],remote);
 write(path.join(remote,'install-backend.sh'),'#!/bin/bash\necho UNREVIEWED-EXECUTED >> "$LOG"\nexit 99\n');
 git(['add','.'],remote);git(['commit','-m','Unreviewed moving branch'],remote);
 git(['tag','-f','v0.1.1'],remote);const moved=git(['rev-parse','HEAD'],remote);
 for(const existing of [false,true])for(const fault of ['', 'fetch', 'checkout']){
  const home=path.join(root,`${existing}-${fault||'success'}`);fs.mkdirSync(home);
  const plugin=path.join(home,'.config/omarchy/plugins/io.github.tcballard.familiar-desktop');
  if(existing){fs.mkdirSync(path.dirname(plugin),{recursive:true});git(['clone',remote,plugin],home);git(['checkout','--detach',pin],plugin);}
  const tools=path.join(home,'tools');fs.mkdirSync(tools);const log=path.join(home,'events');
  write(path.join(tools,'uname'),'#!/bin/bash\nif [[ "$1" == -m ]]; then echo x86_64; else echo Linux; fi\n');
  write(path.join(tools,'hyprctl'),"#!/bin/bash\necho 'Version ABI string: efb50993780079460b0cbed1363e2166a2de1d9f_aq_0.15_hu_0.14_hg_0.5_hc_0.1_hlg_0.6'\n");
  write(path.join(tools,'omarchy-shell'),'#!/bin/bash\nexit 0\n');
  write(path.join(tools,'omarchy'),`#!/bin/bash\necho "omarchy $*" >> "$LOG"\nif [[ "$1 $2" == 'plugin add' ]]; then\n test "$("$REAL_GIT" -C "$3" rev-parse HEAD)" = "$PIN" || exit 97\n mkdir -p "$(dirname "$PLUGIN")"\n "$REAL_GIT" clone -- "$3" "$PLUGIN"\nfi\n`);
  write(path.join(tools,'git'),`#!/bin/bash\nif [[ "$*" == *'rev-parse --verify FETCH_HEAD^{commit}' && "$FAULT" == fetch ]]; then echo "$MOVED"; exit 0; fi\nif [[ "$*" == *'checkout --detach'* && "$FAULT" == checkout ]]; then exit 0; fi\nexec "$REAL_GIT" "$@"\n`);
  const script=path.join(home,'install.sh');
  write(script,source.replace("repository='https://github.com/tcballard/omarchy-plugin-familiar-desktop.git'",`repository='${remote}'`).replace('@SOURCE_SHA@',pin));
  // For upgrade checkout fault, begin on the wrong commit so a no-op is detected.
  if(existing&&fault==='checkout')git(['checkout','--detach',moved],plugin);
  const r=spawnSync('bash',[script,'windows'],{encoding:'utf8',env:{...process.env,HOME:home,XDG_CONFIG_HOME:path.join(home,'.config'),XDG_STATE_HOME:path.join(home,'.local/state'),PATH:tools+':/usr/bin:/bin',LOG:log,PLUGIN:plugin,REAL_GIT:realGit,PIN:pin,MOVED:moved,FAULT:fault}});
  const events=fs.existsSync(log)?fs.readFileSync(log,'utf8'):'';
  assert.doesNotMatch(events,/UNREVIEWED-EXECUTED/);
  if(fault){assert.notEqual(r.status,0,r.stderr);assert.doesNotMatch(events,/trusted-backend|trusted-titlebars|plugin enable/);if(!existing)assert.doesNotMatch(events,/plugin add/);}
  else {assert.equal(r.status,0,r.stderr);assert.equal(git(['rev-parse','HEAD'],plugin),pin);assert.equal(git(['remote','get-url','origin'],plugin),remote);assert.match(events,/trusted-backend/);assert.match(events,/plugin enable/);}
 }
 console.log('6 real-Git source identity scenarios passed: moving tag/default branch, fetch mismatch, checkout mismatch; fresh and upgrade paths.');
} finally {fs.rmSync(root,{recursive:true,force:true});}
