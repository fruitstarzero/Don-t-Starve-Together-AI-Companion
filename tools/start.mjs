import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawn,execFileSync} from 'node:child_process';
import {loadConfig,instanceId} from '../bridge/config.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
try{
  const config=loadConfig(root);let running=false;
  try{
    const data=await (await fetch(`http://127.0.0.1:${config.port}/health`,{signal:AbortSignal.timeout(1500)})).json();
    if(data.service!=='wendy-ai'||data.instanceId!==instanceId(config.token))throw Error('Port belongs to another service or installation. Choose a different port with setup.');
    running=data.ready===true;
  }catch(error){if(error.cause?.code!=='ECONNREFUSED')throw error;}
  if(!running){
    fs.mkdirSync(path.join(root,'state'),{recursive:true});
    const stdout=fs.openSync(path.join(root,'state/service.stdout.log'),'a'),stderr=fs.openSync(path.join(root,'state/service.stderr.log'),'a');
    const child=spawn(process.execPath,[path.join(root,'bridge/server.mjs')],{cwd:root,detached:true,windowsHide:true,stdio:['ignore',stdout,stderr]});
    child.unref();fs.closeSync(stdout);fs.closeSync(stderr);
    fs.writeFileSync(path.join(root,'state/service.json'),JSON.stringify({pid:child.pid,instanceId:instanceId(config.token)}));
    let ready=false;
    for(let i=0;i<20&&!ready;i++){
      await new Promise(r=>setTimeout(r,200));
      try{const health=await(await fetch(`http://127.0.0.1:${config.port}/health`,{signal:AbortSignal.timeout(1000)})).json();ready=health.instanceId===instanceId(config.token)&&health.ready===true;}catch{}
    }
    if(!ready)throw Error('Bridge did not become ready; check the local state/service.stderr.log');
  }
  console.log(`AI bridge ready on 127.0.0.1:${config.port}`);
  if(process.argv.includes('--game')){
    if(process.platform!=='win32')throw Error('Automatic Steam launch is provided for Windows only');
    execFileSync('powershell.exe',['-NoProfile','-Command',"Start-Process -FilePath 'steam://rungameid/322330' -WindowStyle Hidden"],{windowsHide:true});
  }
}catch(error){console.error(error.message);process.exitCode=1;}
