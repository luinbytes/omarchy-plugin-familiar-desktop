const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),assert=require('node:assert/strict'),{spawnSync}=require('node:child_process');
const tmp=fs.mkdtempSync(path.join(os.tmpdir(),'familiar-repair-'));
try {
 const root=path.join(tmp,'.config/omarchy/plugins/io.github.tcballard.familiar-desktop'),bin=path.join(tmp,'mock'),log=path.join(tmp,'log');
 fs.mkdirSync(path.join(root,'.git'),{recursive:true});fs.mkdirSync(path.join(root,'bin'));fs.mkdirSync(bin);
 const officialLibrary=path.join(tmp,'official/titlebars.so');
 fs.writeFileSync(path.join(root,'repair.sh'),fs.readFileSync('repair.sh','utf8').replaceAll('/usr/lib/omarchy-hyprland-titlebars/titlebars.so',officialLibrary));
 const mock=`#!/bin/bash\necho "$(basename "$0") $*" >> "$LOG"\n[[ "$(basename "$0") $*" != "$FAIL" ]] || exit 7\ncase "$(basename "$0")" in\ngit) [[ "$*" == *status* ]] || exit 99; [[ "$DIRTY" != 1 ]] || echo ' M README.md';;\ninstall-titlebars.sh) [[ "$*" == --check ]] || echo /fixture/hyprbars.so;;\nesac\n`;
 for(const name of ['install-backend.sh','install-titlebars.sh','bin/familiar-desktop'])fs.writeFileSync(path.join(root,name),mock,{mode:0o755});
 for(const name of ['git','omarchy','omarchy-shell'])fs.writeFileSync(path.join(bin,name),mock,{mode:0o755});
 for(const failure of ['', 'install-backend.sh ', 'install-titlebars.sh --check', 'familiar-desktop titlebars disable']) {
  fs.writeFileSync(log,'');const r=spawnSync('bash',[path.join(root,'repair.sh'),'mac'],{encoding:'utf8',env:{...process.env,HOME:tmp,PATH:bin+':'+process.env.PATH,LOG:log,FAIL:failure}});
  assert.equal(r.status===0,failure==='',r.stderr);const calls=fs.readFileSync(log,'utf8');assert.doesNotMatch(calls,/fetch|checkout|clone/);
  if(failure)assert.doesNotMatch(calls,/plugin enable/);else assert.match(calls,/setup --library \/fixture\/hyprbars.so --enable --style mac/);
 }
 fs.writeFileSync(log,'');const r=spawnSync('bash',[path.join(root,'repair.sh')],{env:{...process.env,HOME:tmp,PATH:bin+':'+process.env.PATH,LOG:log,DIRTY:'1'}});assert.notEqual(r.status,0);assert.doesNotMatch(fs.readFileSync(log,'utf8'),/install-backend|plugin disable/);
 // Reached through a symlinked home, the installed checkout is still this checkout (as uninstall.sh accepts).
 const link=path.join(tmp,'home-link');fs.symlinkSync(tmp,link);
 {
  fs.writeFileSync(log,'');const linked=spawnSync('bash',[path.join(link,'.config/omarchy/plugins/io.github.tcballard.familiar-desktop/repair.sh'),'mac'],{encoding:'utf8',env:{...process.env,HOME:link,PATH:bin+':'+process.env.PATH,LOG:log,FAIL:''}});
  assert.equal(linked.status,0,linked.stderr);assert.match(fs.readFileSync(log,'utf8'),/setup --library \/fixture\/hyprbars.so --enable --style mac/);
 }
 fs.mkdirSync(path.dirname(officialLibrary));fs.writeFileSync(officialLibrary,'official package');
 for(const failure of ['', 'install-backend.sh ']) {
  fs.writeFileSync(log,'');
  const result=spawnSync('bash',[path.join(root,'repair.sh'),'mac'],{encoding:'utf8',env:{...process.env,HOME:tmp,PATH:bin+':'+process.env.PATH,LOG:log,FAIL:failure}});
  assert.equal(result.status===0,failure==='',result.stderr);
  const calls=fs.readFileSync(log,'utf8');
  assert.doesNotMatch(calls,/install-titlebars|titlebars setup/);
  assert.equal(/plugin enable/.test(calls),failure==='');
  assert.equal(fs.readFileSync(officialLibrary,'utf8'),'official package');
 }
 console.log('Repair: same checkout, setup success, failure stops and dirty source refusal passed.');
}finally{fs.rmSync(tmp,{recursive:true,force:true});}
