import fs from 'node:fs';
import path from 'node:path';
import {randomBytes} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {validateConfig} from '../bridge/config.mjs';
import {resolveCodex} from '../bridge/model.mjs';

function ensureGameStopped(){
  if(process.platform!=='win32')return;
  const script="$ErrorActionPreference='Stop'; $running=@(Get-Process dontstarve_steam_x64,dontstarve_dedicated_server_nullrenderer_x64 -ErrorAction SilentlyContinue); foreach($p in $running){if($p.Threads.Count -gt 0){throw 'Save and fully exit the game and dedicated server first'}}";
  execFileSync('powershell.exe',['-NoProfile','-Command',script],{windowsHide:true,stdio:['ignore','pipe','pipe']});
}
export function install({root,gamePath,port,codexPath,model,checkRunning=ensureGameStopped}){
  root=path.resolve(root);gamePath=path.resolve(gamePath);
  if(!fs.existsSync(path.join(gamePath,'data'))||!fs.existsSync(path.join(gamePath,'bin64/dontstarve_steam_x64.exe')))
    throw Error('Choose the Windows game directory containing data and bin64, not its mods folder');
  checkRunning();
  const configFile=path.join(root,'bridge/config.json');
  const previous=fs.existsSync(configFile)?validateConfig(JSON.parse(fs.readFileSync(configFile,'utf8'))):null;
  const config=validateConfig({port:port??previous?.port??3131,token:previous?.token??randomBytes(32).toString('hex'),
    codexPath:codexPath??previous?.codexPath??'',model:model??previous?.model??''});
  const mods=path.join(gamePath,'mods');const destination=path.join(mods,'wendy_ai_companion');
  const relative=path.relative(gamePath,destination);
  if(relative.startsWith('..')||path.isAbsolute(relative))throw Error('Unexpected mod destination');
  if(fs.existsSync(mods)&&fs.lstatSync(mods).isSymbolicLink())throw Error('Install manually if the mods folder is a symbolic link');
  if(fs.existsSync(destination)&&fs.lstatSync(destination).isSymbolicLink())throw Error('Refusing to replace a linked mod directory');
  let backup=null;
  if(fs.existsSync(destination)){
    backup=path.join(root,'backups',new Date().toISOString().replaceAll(':','-'),'wendy_ai_companion');
    fs.cpSync(destination,backup,{recursive:true});
  }
  fs.mkdirSync(mods,{recursive:true});fs.cpSync(path.join(root,'mod'),destination,{recursive:true});
  fs.mkdirSync(path.dirname(configFile),{recursive:true});
  fs.writeFileSync(configFile,JSON.stringify(config,null,2)+'\n');
  fs.writeFileSync(path.join(destination,'scripts/ai_private.lua'),`return {url="http://127.0.0.1:${config.port}",token="${config.token}"}\n`);
  if(!fs.existsSync(path.join(root,'role.md')))fs.copyFileSync(path.join(root,'role.example.md'),path.join(root,'role.md'));
  return {destination,backup,config};
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  try{
    const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
    const args=process.argv.slice(2),get=name=>{const i=args.indexOf(name);return i<0?undefined:args[i+1];};
    let gamePath=get('--game');
    if(!gamePath&&process.stdin.isTTY){
      const {createInterface}=await import('node:readline/promises');const input=createInterface({input:process.stdin,output:process.stdout});
      gamePath=(await input.question('Game directory (data and bin64): ')).trim().replace(/^"|"$/g,'');input.close();
    }
    if(!gamePath)throw Error('Usage: node tools/setup.mjs --game <game directory> [--codex <codex.exe or codex.js>] [--port 3131]');
    const result=install({root,gamePath,port:get('--port')?Number(get('--port')):undefined,codexPath:get('--codex'),model:get('--model')});
    console.log('Installed mod:',result.destination);if(result.backup)console.log('Backup:',result.backup);
    console.log('Local secret generated/preserved. Do not upload bridge/config.json, role.md or the installed ai_private.lua.');
    try{resolveCodex(result.config);console.log('Codex executable found. Use your own local Codex login.');}
    catch(error){console.log(error.message);}
  }catch(error){console.error(error.message);process.exitCode=1;}
}
