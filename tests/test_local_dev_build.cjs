// Real Cargo, ELF verification and packaging: redirected output plus a stale
// default-path executable must still produce the exact current source binary.
const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const assert=require('node:assert/strict');
const {execFileSync,spawnSync}=require('node:child_process');
const {createHash}=require('node:crypto');
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'familiar-local-build-'));
const source=path.join(temp,'source'),tools=path.join(temp,'tools');
function write(name,bytes) {fs.mkdirSync(path.dirname(name),{recursive:true});fs.writeFileSync(name,bytes,{mode:0o755});}
function git(...args) {return execFileSync('git',['-C',source,...args],{encoding:'utf8'}).trim();}
try {
  const official=path.join(temp,'system/titlebars.so');write(official,'Core owns this library');
  for(const name of ['scripts/build-local-dev.sh','scripts/prepare-dev-bundle.cjs','scripts/install-dev.sh','docs/DEVELOPMENT.md']) {
    write(path.join(source,name),fs.readFileSync(name,'utf8').replaceAll('/usr/lib/omarchy-hyprland-titlebars/titlebars.so',official));
  }
  write(path.join(source,'scripts/build-hyprbars.sh'),'#!/bin/bash\necho "Private renderer must not be built on an official host" >&2\nexit 99\n');
  write(path.join(source,'manifest.json'),'{"version":"0.1.5"}');
  write(path.join(source,'backend/Cargo.toml'),'[package]\nname = "familiar-desktop"\nversion = "0.1.5"\nedition = "2024"\n');
  write(path.join(source,'backend/src/main.rs'),'fn main() { println!("current source backend"); }');
  write(path.join(source,'.gitignore'),'/backend/target/\n');
  write(path.join(source,'.cargo/config.toml'),`[build]\ntarget-dir = ${JSON.stringify(path.join(temp,'configured-target'))}\n`);
  // A valid old ELF makes this a stale-byte regression, not just an ELF refusal.
  fs.mkdirSync(path.join(source,'backend/target/release'),{recursive:true});
  fs.copyFileSync('/bin/true',path.join(source,'backend/target/release/familiar-desktop'));
  write(path.join(tools,'hyprctl'),'#!/bin/bash\necho "Version ABI string: fixture-abi"\n');
  execFileSync('cargo',['generate-lockfile','--manifest-path','backend/Cargo.toml','--offline'],{cwd:source});
  git('init','-q');git('add','.');
  git('-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','-qm','current source');
  const commit=git('rev-parse','HEAD');
  for(const override of [true,false]) {
    const output=path.join(temp,override?'env-output':'config-output');
    const env={...process.env,PATH:tools+':'+process.env.PATH,CARGO_NET_OFFLINE:'true'};
    delete env.CARGO_TARGET_DIR;
    if(override) env.CARGO_TARGET_DIR=path.join(temp,'environment-target');
    const result=spawnSync('bash',['scripts/build-local-dev.sh',output],{cwd:source,env,encoding:'utf8'});
    assert.equal(result.status,0,result.stdout+result.stderr);
    const receipt=JSON.parse(fs.readFileSync(path.join(output,'DEV-BUILD.json')));
    assert.equal(receipt.commit,commit);assert.equal(receipt.buildKind,'local');
    assert.equal(receipt.renderer,'omarchy');assert.equal(receipt.runId,undefined);
    const [asset]=Object.keys(receipt.assets);assert.equal(Object.keys(receipt.assets).length,1);
    const binary=path.join(output,asset);
    assert.equal(execFileSync(binary,{encoding:'utf8'}).trim(),'current source backend');
    assert.equal(receipt.assets[asset],createHash('sha256').update(fs.readFileSync(binary)).digest('hex'));
    execFileSync('sha256sum',['--check','--strict','SHA256SUMS'],{cwd:output});
    assert.equal(git('status','--porcelain'),'');
  }
  assert.ok(!fs.existsSync(path.join(temp,'environment-target')));
  assert.ok(!fs.existsSync(path.join(temp,'configured-target')));
  console.log('Local build: real Cargo ignores redirected outputs, excludes stale default bytes and skips private renderer on official hosts.');
} finally {fs.rmSync(temp,{recursive:true,force:true});}
