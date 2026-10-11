// Release smoke check: download every pinned asset from the public onboarding
// URL and verify it against the reviewed source digests, exactly as a fresh
// install would. CI runs this after assets are published; a missing asset,
// wrong digest or half-updated release fails the run (issue #79).
const fs=require('node:fs');const path=require('node:path');const os=require('node:os');const crypto=require('node:crypto');const {spawnSync}=require('node:child_process');
const args=process.argv.slice(2);
const options={repo:'tcballard/omarchy-plugin-familiar-desktop',root:'.',curl:'curl'};
for(let i=0;i<args.length;i++){
  if(args[i]==='--tag')options.tag=args[++i];
  else if(args[i]==='--repo')options.repo=args[++i];
  else if(args[i]==='--root')options.root=args[++i];
  else if(args[i]==='--curl')options.curl=args[++i];
  else {console.error(`Unknown argument: ${args[i]}\nUsage: node scripts/verify-release-download.cjs --tag vX.Y.Z [--repo owner/name] [--root DIR] [--curl PATH]`);process.exit(2);}
}
if(!options.tag){console.error('Usage: node scripts/verify-release-download.cjs --tag vX.Y.Z [--repo owner/name] [--root DIR] [--curl PATH]');process.exit(2);}
const fail=message=>{throw new Error(message);};
function main() {
if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(options.repo)) fail("Invalid repository");
const root=path.resolve(options.root);
const read=name=>fs.readFileSync(path.join(root,name),'utf8');
// The pinned digests are the same reviewed file the installers verify against.
const pins=new Map();
for(const row of read('release-binaries.sha256').trim().split('\n')){
  const match=/^([0-9a-f]{64})  (\S+)$/.exec(row);
  if(!match||!(/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(match[2]))||pins.has(match[2]))fail(`Malformed or duplicate reviewed source digest in release-binaries.sha256: ${row}`);
  pins.set(match[2],match[1]);
}
if(!pins.size)fail('release-binaries.sha256 contains no assets');
const version=JSON.parse(read('manifest.json')).version;
if(!/^\d+\.\d+\.\d+$/.test(version)||options.tag!==`v${version}`)fail(`Tag ${options.tag} does not match manifest.json version ${version}`);
// Rebuild the exact URLs onboarding constructs; a stale installer release pin
// would download a different release than the one being checked.
for(const installer of ['install-backend.sh','install-titlebars.sh']){
  const source=read(installer);
  const base=/^\s*base="([^"]+)"/m.exec(source);
  if(!base || base[1]!==`https://github.com/${options.repo}/releases/download/$release`)
    fail(`${installer} download base differs from the public URL being checked`);
  const pattern=installer==='install-titlebars.sh' ? 'asset="hyprbars-linux-$architecture-$abi.so"' : 'asset="familiar-desktop-linux-$architecture"';
  if(!source.includes(pattern))fail(`${installer} asset pattern differs from the public URL being checked`);
  const match=/^\s*(?:local )?release='([^']+)'/m.exec(source);
  if(!match)fail(`${installer} does not declare a release`);
  if(match[1]!==options.tag)fail(`${installer} downloads ${match[1]}, not ${options.tag}; onboarding would fetch a different release than the one being published`);
}
// Source pins now define the architecture/ABI support set. Every published target
// needs both assets; an unpinned desktop is refused before onboarding downloads.
const architectures=new Set();
for(const name of pins.keys()){
  const match=/^(?:familiar-desktop-linux-(x86_64|aarch64)|hyprbars-linux-(x86_64|aarch64)-[a-zA-Z0-9_.-]+\.so)$/.exec(name);
  if(!match)fail(`Unsupported reviewed source digest asset: ${name}`);
  architectures.add(match[1]||match[2]);
}
for(const architecture of architectures){
  if(!pins.has(`familiar-desktop-linux-${architecture}`)||![...pins.keys()].some(n=>n.startsWith(`hyprbars-linux-${architecture}-`)))
    fail(`release-binaries.sha256 has no reviewed digest for a complete Linux ${architecture} backend/window-controls pair`);
}
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'familiar-smoke-'));
try{
  let verified=0;
  for(const name of [...pins.keys()].sort()){
    const url=`https://github.com/${options.repo}/releases/download/${options.tag}/${name}`;
    const destination=path.join(temp,name);
    const download=spawnSync(options.curl,['--fail','--show-error','--silent','--location','--proto','=https','--proto-redir','=https','--retry','3','--connect-timeout','20','--max-time','180',url,'-o',destination],{encoding:'utf8'});
    if(download.status!==0)fail(`Download failed (exit ${download.status}): ${url}\n${download.stderr||'The release asset is missing; publish it before onboarding can use it.'}`);
    const digest=crypto.createHash('sha256').update(fs.readFileSync(destination)).digest('hex');
    if(digest!==pins.get(name))fail(`Checksum mismatch for ${url}\nExpected ${pins.get(name)} (reviewed pin)\nDownloaded ${digest}`);
    const nativeArchitecture=process.arch==='arm64'?'aarch64':process.arch==='x64'?'x86_64':null;
    if(name===`familiar-desktop-linux-${nativeArchitecture}`){
      fs.chmodSync(destination,0o755);
      const output=spawnSync(destination,['--version'],{encoding:'utf8',timeout:10000});
      if(output.status!==0||output.stdout.trim()!==`familiar-desktop ${version}`)fail(`Downloaded backend at ${url} reports '${(output.stdout+output.stderr).trim()}', expected 'familiar-desktop ${version}'`);
    }
    verified++;
    console.log(`Verified ${url}`);
  }
  console.log(`Verified ${verified} onboarding download URLs for ${options.tag} against reviewed pins.`);
}finally{fs.rmSync(temp,{recursive:true,force:true});}

}
try { main(); } catch (error) { console.error(error.message); process.exitCode=1; }
