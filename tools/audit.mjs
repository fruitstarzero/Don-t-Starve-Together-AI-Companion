import fs from 'node:fs';import path from 'node:path';import {spawnSync} from 'node:child_process';
const root=process.cwd(),release=process.argv.includes('--release'),files=[],findings=[];
const runtime=new Set(['node_modules','state','backups','reference','release']);
const forbidden=/(^|\/)(state|backups|node_modules|reference|release|\.git)(\/|$)|(^|\/)(config\.json|ai_private\.lua|auth\.json|role\.md|\.env(?:\..*)?)$|\.(pem|key|log|zip|png|jpg|jpeg)$/i;
const patterns=[['credential',/\b(?:gh[pousr]_[A-Za-z0-9]{25,}|github_pat_[A-Za-z0-9_]{30,}|sk-[A-Za-z0-9_-]{24,})\b/],['private-key',/-----BEGIN [A-Z ]*PRIVATE KEY-----/],['personal-path',/[A-Z]:[\\/]Users[\\/](?!Public\b|Default\b|<|USER\b|LOCAL_USER\b)[^\s\\/]+/i],['email',/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i]];
function walk(dir){for(const e of fs.readdirSync(dir,{withFileTypes:true})){const f=path.join(dir,e.name),rel=path.relative(root,f).replaceAll('\\','/');
 if(e.name==='.git'&&!release)continue;if(!release&&e.isDirectory()&&runtime.has(e.name))continue;
 if(e.isSymbolicLink()){findings.push({file:rel,kind:'symlink'});continue;}
 if(e.isDirectory()){if(release&&forbidden.test(rel+'/'))findings.push({file:rel,kind:'forbidden-runtime-directory'});else walk(f);}else files.push(rel);
}}
walk(root);
const tracked=spawnSync('git',['ls-files','-z'],{encoding:'utf8',windowsHide:true,stdio:['ignore','pipe','ignore']});
if(tracked.status===0)for(const f of tracked.stdout.split('\0').filter(Boolean))if(forbidden.test(f))findings.push({file:f,kind:'tracked-runtime-file'});
for(const file of files){if(forbidden.test(file))findings.push({file,kind:'forbidden-runtime-file'});const text=fs.readFileSync(path.join(root,file),'utf8');for(const [kind,p]of patterns)if(p.test(text)&&!(kind==='email'&&file==='LICENSE'))findings.push({file,kind});}
console.log(JSON.stringify({mode:release?'clean-upload-directory':'source-and-git',files:files.length,findings},null,2));if(findings.length)process.exitCode=1;
