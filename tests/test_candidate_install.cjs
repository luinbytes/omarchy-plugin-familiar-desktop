// Candidate installer lifecycle using a fictional desktop, real checksums and file operations.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const {spawnSync} = require('node:child_process');
const version = JSON.parse(fs.readFileSync('manifest.json')).version;
const sha = 'a'.repeat(40);
const abi = 'efb50993780079460b0cbed1363e2166a2de1d9f_aq_0.15_hu_0.14_hg_0.5_hc_0.1_hlg_0.6';
function run(fault='', existing=true) {
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'familiar-candidate-'));
 try {
  const bundle=path.join(root,'bundle');const tools=path.join(root,'tools');
  const plugin=path.join(root,'.config/omarchy/plugins/io.github.tcballard.familiar-desktop');
  fs.mkdirSync(bundle);fs.mkdirSync(tools);
  fs.writeFileSync(path.join(tools,'uname'),'#!/bin/bash\nif [[ "$1" == -m ]]; then echo x86_64; else echo Linux; fi\n',{mode:0o755});
  if(existing)fs.mkdirSync(path.join(plugin, fault==='unmanaged'?'other':'.git'),{recursive:true});
  fs.copyFileSync('bar-placement.sh',path.join(root,'bar-placement.sh'));
  if(existing)fs.copyFileSync('bar-placement.sh',path.join(plugin,'bar-placement.sh'));
  fs.mkdirSync(path.join(root,'.config/omarchy/familiar-titlebars'),{recursive:true});
  fs.writeFileSync(path.join(root,'.config/omarchy/shell.json'),JSON.stringify({bar:{layout:{right:['omarchy.tray',{id:'omarchy.agents'},'omarchy.network']}}}));
  if(existing)fs.writeFileSync(path.join(root,'.config/omarchy/familiar-titlebars/owner.json'),'{}');
  const script=fs.readFileSync('scripts/install-candidate.sh','utf8').replace('@SOURCE_SHA@',sha).replace('@VERSION@',version);
  fs.writeFileSync(path.join(bundle,'install-candidate.sh'),script);
  const binary=`#!/bin/bash\necho "backend $*" >> "$LOG"\nif [[ "$1" == --version ]]; then echo 'familiar-desktop ${fault==='wrong-version'?'0.0.6':version}'; fi\nif [[ "$1" == titlebars && "$FAULT" == setup ]]; then exit 1; fi\n`;
  fs.writeFileSync(path.join(bundle,'familiar-desktop-linux-x86_64'),binary);
  fs.writeFileSync(path.join(bundle,`hyprbars-linux-x86_64-${abi}.so`),'fixture library');
  const sums=fs.readdirSync(bundle).map(name=>crypto.createHash('sha256').update(fs.readFileSync(path.join(bundle,name))).digest('hex')+'  '+name+'\n').join('');
  fs.writeFileSync(path.join(bundle,'SHA256SUMS'),sums);
  fs.writeFileSync(path.join(root,'pins'),sums);
  if(fault==='substitution') {
   fs.appendFileSync(path.join(bundle,'familiar-desktop-linux-x86_64'),'echo SUBSTITUTED >> "$LOG"\n');
   const changed=fs.readdirSync(bundle).filter(n=>n!=='SHA256SUMS').map(name=>crypto.createHash('sha256').update(fs.readFileSync(path.join(bundle,name))).digest('hex')+'  '+name+'\n').join('');
   fs.writeFileSync(path.join(bundle,'SHA256SUMS'),changed);
  }
  if(fault==='checksum')fs.appendFileSync(path.join(bundle,'familiar-desktop-linux-x86_64'),'changed');
  const mock=`#!/bin/bash\nname="$(basename "$0")"\necho "$name $*" >> "$LOG"\ncase "$name" in\n hyprctl) echo 'Version ABI string: ${fault==='abi'?'unsupported':abi}';;\n omarchy) if [[ "$*" == plugin\\ add* ]]; then mkdir -p "$PLUGIN/.git"; fi;;\n git) case "$*" in\n *show*) cat "$HOME/pins";;\n *status*) [[ "$FAULT" != dirty && "$FAULT" != untracked ]] || echo '?? user.qml';;\n *ls-files*) [[ "$FAULT" != ignored ]] || echo ignored.qml;;\n *rev-parse*) [[ "$FAULT" != wrong-sha ]] && echo '${sha}' || echo bad;;\n esac;;\n cargo|rustup|clippy|cc|hyprpm) exit 99;;\nesac\nexit 0\n`;
  const candidateMock=mock.replace('mkdir -p "$PLUGIN/.git";', 'mkdir -p "$PLUGIN/.git"; cp "$HOME/bar-placement.sh" "$PLUGIN/bar-placement.sh";');
  for(const name of ['omarchy','omarchy-shell','hyprctl','git','cargo','rustup','clippy','cc','hyprpm']) fs.writeFileSync(path.join(tools,name),candidateMock,{mode:0o755});
  const log=path.join(root,'calls');
  const result=spawnSync('/bin/bash',[path.join(bundle,'install-candidate.sh'),'windows'],{encoding:'utf8',env:{...process.env,HOME:root,XDG_CONFIG_HOME:path.join(root,'.config'),XDG_STATE_HOME:path.join(root,'.local/state'),PATH:tools+':/usr/bin:/bin',FAULT:fault,PLUGIN:plugin,LOG:log}});
  return {...result,log:fs.existsSync(log)?fs.readFileSync(log,'utf8'):'',installed:fs.existsSync(path.join(plugin,'bin/familiar-desktop'))};
 }finally{fs.rmSync(root,{recursive:true,force:true});}
}
for(const existing of [false,true]) {
 const r=run('',existing);assert.equal(r.status,0,r.stderr);assert.equal(r.installed,true);
 assert.match(r.log,/checkout --detach a{40}/);assert.match(r.log,/backend titlebars setup/);
 assert.ok(r.log.indexOf('plugin disable')<r.log.lastIndexOf('checkout --detach'));
 if(!existing){
  assert.ok(r.log.indexOf('checkout --detach')<r.log.indexOf('plugin add'));
  assert.match(r.log,/omarchy bar move io.github.tcballard.familiar-desktop --after omarchy.agents/);
  assert.ok(r.log.indexOf('plugin enable')<r.log.indexOf('bar move'));
 } else assert.doesNotMatch(r.log,/bar move/);
 assert.ok(r.log.indexOf('backend titlebars setup')<r.log.indexOf('plugin enable'));
 assert.doesNotMatch(r.log,/cargo|rustup|clippy|hyprpm|sudo/);
}
for(const fault of ['abi','checksum','substitution','wrong-version','dirty','untracked','ignored','unmanaged','wrong-sha']) {
 const r=run(fault);assert.notEqual(r.status,0,fault);assert.equal(r.installed,false,fault);if(fault==='substitution')assert.doesNotMatch(r.log,/backend|SUBSTITUTED/);
 assert.doesNotMatch(r.log,/plugin disable|checkout --detach|plugin enable/,fault);
}
const failed=run('setup');assert.notEqual(failed.status,0);assert.doesNotMatch(failed.log,/plugin enable/);
console.log('11 candidate installer scenarios passed: exact source, clean checkout, checksums, compatibility, setup failure.');
