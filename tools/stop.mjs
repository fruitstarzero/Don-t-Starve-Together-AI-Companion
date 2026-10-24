import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
import {loadConfig,instanceId} from '../bridge/config.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
try{
  const config=loadConfig(root);const info=JSON.parse(fs.readFileSync(path.join(root,'state/service.json'),'utf8'));
  const health=await(await fetch(`http://127.0.0.1:${config.port}/health`,{signal:AbortSignal.timeout(1500)})).json();
  if(health.service!=='wendy-ai'||health.instanceId!==instanceId(config.token)||info.instanceId!==health.instanceId||!Number.isInteger(info.pid))throw Error('Unexpected service identity; refusing to stop');
  const expected=path.join(root,'bridge/server.mjs');
  if(process.platform==='win32'){
    const quoted=expected.replaceAll("'","''");
    execFileSync('powershell.exe',['-NoProfile','-Command',`$p=Get-CimInstance Win32_Process -Filter 'ProcessId=${info.pid}'; if($p -and $p.CommandLine.Contains('${quoted}')){Stop-Process -Id ${info.pid}}else{throw 'Process path does not match this bridge'}`],{windowsHide:true});
  }else{
    if(!fs.readFileSync(`/proc/${info.pid}/cmdline`,'utf8').includes(expected))throw Error('Process does not match this bridge');
    process.kill(info.pid,'SIGTERM');
  }
  console.log('Stopped this AI bridge only.');
}catch(error){console.error(error.message);process.exitCode=1;}
