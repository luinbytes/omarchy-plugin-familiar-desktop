const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const assert=require('node:assert/strict');
const {createHash}=require('node:crypto');
const {execFileSync,spawnSync}=require('node:child_process');
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'familiar-dev-bundle-'));
const sha=execFileSync('git',['rev-parse','HEAD'],{encoding:'utf8'}).trim();
const input=path.join(temp,'downloaded'),dir=path.join(input,'familiar-desktop-packaging-validation');
fs.mkdirSync(dir,{recursive:true});
const assets=['familiar-desktop-linux-x86_64','hyprbars-linux-x86_64-fixture.so'];
const digest=n=>createHash('sha256').update(fs.readFileSync(path.join(dir,n))).digest('hex');
for(const name of assets)fs.writeFileSync(path.join(dir,name),name);
const manifest={source:{commit:sha},version:'0.1.2',artifacts:assets.map(name=>({name,sha256:digest(name)}))};
function metadata() {
 fs.writeFileSync(path.join(dir,'RELEASE-MANIFEST.json'),JSON.stringify(manifest));
 fs.writeFileSync(path.join(dir,'SHA256SUMS'),[...assets,'RELEASE-MANIFEST.json'].map(n=>`${digest(n)}  ${n}\n`).join(''));
}
const env={...process.env,BUILD_SOURCE_SHA:sha,GITHUB_RUN_ID:'123',GITHUB_RUN_ATTEMPT:'2'};
function run(label,extra={}) {return spawnSync('node',['scripts/prepare-dev-bundle.cjs',input,path.join(temp,label)],{env:{...env,...extra},encoding:'utf8'});}
try {
 metadata();const result=run('good');assert.equal(result.status,0,result.stderr);
 const receipt=JSON.parse(fs.readFileSync(path.join(temp,'good/DEV-BUILD.json')));
 assert.equal(receipt.commit,sha);assert.equal(receipt.runAttempt,'2');assert.equal(receipt.channel,'development');
 assert.equal(receipt.assets[assets[0]],digest(assets[0]));
 assert.match(fs.readFileSync(path.join(temp,'good/install-dev.sh'),'utf8'),new RegExp(`source_sha='${sha}'`));
 execFileSync('sha256sum',['--check','--strict','SHA256SUMS'],{cwd:path.join(temp,'good')});
 assert.notEqual(run('head-mismatch',{BUILD_SOURCE_SHA:'a'.repeat(40)}).status,0);
 assert.notEqual(run('no-run',{GITHUB_RUN_ID:''}).status,0);
 manifest.source.commit='b'.repeat(40);metadata();assert.notEqual(run('source-mismatch').status,0);
 manifest.source.commit=sha;metadata();fs.appendFileSync(path.join(dir,assets[0]),'corrupt');assert.notEqual(run('transport').status,0);
 metadata();assert.notEqual(run('manifest-mismatch').status,0);
 // ARM bundles must contain a matching pair, never mixed CPU architectures.
 fs.writeFileSync(path.join(dir,assets[0]),assets[0]);
 const armAssets=['familiar-desktop-linux-aarch64','hyprbars-linux-aarch64-fixture.so'];
 for(const name of armAssets)fs.writeFileSync(path.join(dir,name),name);
 manifest.artifacts=armAssets.map(name=>({name,sha256:digest(name)}));metadata();
 let arm=run('arm');assert.equal(arm.status,0,arm.stderr);
 const armReceipt=JSON.parse(fs.readFileSync(path.join(temp,'arm/DEV-BUILD.json')));
 assert.equal(armReceipt.architecture,'aarch64');assert.equal(armReceipt.abi,'fixture');
 manifest.artifacts[1]={name:assets[1],sha256:digest(assets[1])};metadata();assert.notEqual(run('mixed').status,0);
 // A single backend must explicitly declare Core ownership, never silently
 // become a private-renderer bundle whose library is missing.
 manifest.artifacts=armAssets.slice(0,1).map(name=>({name,sha256:digest(name)}));metadata();
 assert.notEqual(run('missing-library').status,0);
 manifest.renderer='omarchy';metadata();
 const official=run('official');assert.equal(official.status,0,official.stderr);
 const officialReceipt=JSON.parse(fs.readFileSync(path.join(temp,'official/DEV-BUILD.json')));
 assert.equal(officialReceipt.renderer,'omarchy');assert.equal(officialReceipt.abi,null);
 assert.equal(officialReceipt.architecture,'aarch64');assert.equal(officialReceipt.commit,sha);
 assert.equal(officialReceipt.buildKind,'github-actions');assert.equal(officialReceipt.runId,'123');assert.equal(officialReceipt.runAttempt,'2');
 assert.deepEqual(Object.keys(officialReceipt.assets),[armAssets[0]]);
 execFileSync('sha256sum',['--check','--strict','SHA256SUMS'],{cwd:path.join(temp,'official')});
 manifest.artifacts.push({name:armAssets[1],sha256:digest(armAssets[1])});metadata();
 assert.notEqual(run('official-with-private-library').status,0);
 delete manifest.renderer;
 // Local builds record their own provenance and never invent a CI run.
 const source=path.join(temp,'local-source');fs.mkdirSync(source);
 for(const name of ['scripts/install-dev.sh','docs/DEVELOPMENT.md']) {
   fs.mkdirSync(path.dirname(path.join(source,name)),{recursive:true});fs.copyFileSync(name,path.join(source,name));
 }
 execFileSync('git',['init','-q',source]);execFileSync('git',['-C',source,'add','.']);
 execFileSync('git',['-C',source,'-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','-qm','local source']);
 manifest.source.commit=execFileSync('git',['-C',source,'rev-parse','HEAD'],{encoding:'utf8'}).trim();
 manifest.artifacts=armAssets.map(name=>({name,sha256:digest(name)}));metadata();
 const localRun=label=>spawnSync(process.execPath,[path.resolve('scripts/prepare-dev-bundle.cjs'),'--local',input,path.join(temp,label)],{cwd:source,encoding:'utf8'});
 let local=localRun('local');assert.equal(local.status,0,local.stderr);
 const localReceipt=JSON.parse(fs.readFileSync(path.join(temp,'local/DEV-BUILD.json')));
 assert.equal(localReceipt.buildKind,'local');assert.equal(localReceipt.commit,manifest.source.commit);
 assert.equal(localReceipt.runId,undefined);assert.equal(localReceipt.runAttempt,undefined);
 fs.writeFileSync(path.join(source,'dirty'),'local edit');assert.notEqual(localRun('dirty-local').status,0);
 console.log('Development packaging passed: exact source/run, checksums, receipt, mismatched source and corrupt assets.');
} finally {fs.rmSync(temp,{recursive:true,force:true});}
