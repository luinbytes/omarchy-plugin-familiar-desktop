// Architecture/ABI selection with real SHA-256 and fake download/compositor tools.
const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const assert=require('node:assert/strict'),{spawnSync}=require('node:child_process');
const {createHash}=require('node:crypto');
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'familiar-arm-assets-'));
const abi='5c9377c15f85c50648f35ca5a213754f95b93ca0_aq_0.14_hu_0.14_hg_0.5_hc_0.1_hlg_0.6';
const version=JSON.parse(fs.readFileSync('manifest.json')).version;
const write=(p,s)=>{fs.mkdirSync(path.dirname(p),{recursive:true});fs.writeFileSync(p,s,{mode:0o755});};
const sha=s=>createHash('sha256').update(s).digest('hex');
try {
 const root=path.join(temp,'plugin'),tools=path.join(temp,'tools');fs.mkdirSync(root);fs.mkdirSync(tools);
 for(const script of ['install-backend.sh','install-titlebars.sh'])fs.copyFileSync(script,path.join(root,script));
 const backend=`#!/bin/bash\necho executed >> "$CALLS"\necho familiar-desktop ${version}\n`,library='ARM library';
 write(path.join(temp,'backend'),backend);write(path.join(temp,'library'),library);
 write(path.join(tools,'uname'),'#!/bin/bash\nif [[ "$1" == -m ]]; then echo "$ARCH"; else echo Linux; fi\n');
 write(path.join(tools,'hyprctl'),'#!/bin/bash\necho "Version ABI string: $ABI"\n');
 write(path.join(tools,'curl'),'#!/bin/bash\necho "$*" >> "$CALLS"\nif [[ "$*" == *hyprbars-linux* ]]; then cp "$FIXTURE/library" "${@: -1}"; else cp "$FIXTURE/backend" "${@: -1}"; fi\n');
 const calls=path.join(temp,'calls'),pins=path.join(root,'release-binaries.sha256');
 const env={...process.env,ARCH:'aarch64',ABI:abi,CALLS:calls,FIXTURE:temp,PATH:tools+':'+process.env.PATH};
 const run=(script,args=[],extra={})=>spawnSync('bash',[path.join(root,script),...args],{env:{...env,...extra},encoding:'utf8'});
 const good=`${sha(backend)}  familiar-desktop-linux-aarch64\n${sha(library)}  hyprbars-linux-aarch64-${abi}.so\n`;
 write(pins,good);write(calls,'');
 let r=run('install-titlebars.sh',['--check']);assert.equal(r.status,0,r.stderr);assert.ok(!fs.existsSync(path.join(root,'bin')));
 r=run('install-backend.sh');assert.equal(r.status,0,r.stderr);
 r=run('install-titlebars.sh');assert.equal(r.status,0,r.stderr);
 assert.match(fs.readFileSync(calls,'utf8'),/familiar-desktop-linux-aarch64/);
 assert.match(fs.readFileSync(calls,'utf8'),new RegExp(`hyprbars-linux-aarch64-${abi}\\.so`));
 const installedLibrary=path.join(root,`bin/hyprbars/${abi}/hyprbars.so`);
 assert.equal(fs.readFileSync(installedLibrary,'utf8'),library);
 for(const badPins of ['',good+good,good.replace(sha(library),'bad')]) {
   write(pins,badPins);write(calls,'');assert.notEqual(run('install-titlebars.sh',['--check']).status,0);
   assert.equal(fs.readFileSync(calls,'utf8'),'');assert.equal(fs.readFileSync(installedLibrary,'utf8'),library);
 }
 write(pins,good);write(calls,'');
 for(const extra of [{ARCH:'x86_64'},{ARCH:'armv7l'},{ABI:'unsupported'},{ABI:'../../escape'}]) {
   assert.notEqual(run('install-titlebars.sh',['--check'],extra).status,0);assert.equal(fs.readFileSync(calls,'utf8'),'');
 }
 write(pins,good.replace(sha(backend),'0'.repeat(64)));write(calls,'');
 assert.notEqual(run('install-backend.sh').status,0);assert.doesNotMatch(fs.readFileSync(calls,'utf8'),/executed/);
 assert.equal(fs.readFileSync(path.join(root,'bin/familiar-desktop'),'utf8'),backend);
 console.log('ARM asset selection: architecture, exact ABI, independent pins, corrupt bytes and unsupported targets passed.');
} finally {fs.rmSync(temp,{recursive:true,force:true});}
