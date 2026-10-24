import fs from 'node:fs';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {execFileSync} from 'node:child_process';
import {schema} from './schema.mjs';

export function resolveCodex(config={}) {
  if(config.codexPath){
    const file=path.resolve(config.codexPath);
    if(!fs.existsSync(file)||!fs.statSync(file).isFile())throw Error('Configured Codex executable does not exist');
    if(/\.(cmd|bat)$/i.test(file))throw Error('Use codex.exe or the official npm package bin/codex.js, not a shell wrapper');
    return /\.m?js$/i.test(file)?{command:process.execPath,prefix:[file]}:{command:file,prefix:[]};
  }
  if(process.platform==='win32'){
    try{
      const file=execFileSync('where.exe',['codex.exe'],{encoding:'utf8',windowsHide:true,stdio:['ignore','pipe','ignore']}).trim().split(/\r?\n/)[0];
      if(file&&fs.existsSync(file))return {command:file,prefix:[]};
    }catch{}
    const candidates=[process.env.APPDATA&&path.join(process.env.APPDATA,'npm/node_modules/@openai/codex/bin/codex.js'),
      process.env.npm_config_prefix&&path.join(process.env.npm_config_prefix,'node_modules/@openai/codex/bin/codex.js')].filter(Boolean);
    for(const file of candidates)if(fs.existsSync(file))return {command:process.execPath,prefix:[file]};
    throw Error('Codex CLI not found. Install it yourself, then set codexPath with npm run setup -- --codex <path>');
  }
  return {command:'codex',prefix:[]};
}

export async function generate(root, config, input, signal) {
  const executable=resolveCodex(config);
  const dir=path.join(root,'state','model'); fs.mkdirSync(dir,{recursive:true});
  const schemaFile=path.join(dir,'decision-schema.json'); fs.writeFileSync(schemaFile,JSON.stringify(schema));
  const roleFile=fs.existsSync(path.join(root,'role.md'))?'role.md':'role.example.md';
  const commonRole=fs.readFileSync(path.join(root,roleFile),'utf8').slice(0,24000);
  const args=['exec','--ignore-user-config','--ephemeral','--skip-git-repo-check','--sandbox','read-only','--color','never','--json','--output-schema',schemaFile,'-C',dir];
  const settings={'features.shell_tool':false,'features.plugins':false,'features.multi_agent':false,
    'features.memories':false,'tools.view_image':false,'web_search':'disabled',
    'approval_policy':'never','project_doc_max_bytes':0,'model_reasoning_effort':'medium',
    'model_instructions_file':path.join(root,'bridge/instructions.txt'),'developer_instructions':commonRole};
  for(const [key,value] of Object.entries(settings)) args.push('-c',`${key}=${JSON.stringify(value)}`);
  if(config.model)args.push('--model',config.model);
  args.push('-');
  const env={...process.env};
  return await new Promise((resolve,reject)=>{
    const child=spawn(executable.command,[...executable.prefix,...args],{cwd:dir,env,windowsHide:true,shell:false,stdio:['pipe','pipe','pipe']});
    let out='',err='',done=false;
    const finish=(error,value)=>{if(done)return;done=true;clearTimeout(timer);signal?.removeEventListener('abort',abort);error?reject(error):resolve(value);};
    const abort=()=>{child.kill();finish(Error('Cancelled'));};
    const timer=setTimeout(()=>{child.kill();finish(Error('Model timed out'));},165000);
    signal?.addEventListener('abort',abort,{once:true});
    child.stdout.on('data',b=>{out+=b;if(out.length>1500000){child.kill();finish(Error('Output too large'));}});
    child.stderr.on('data',b=>{err=(err+b).slice(-2000);});
    child.once('error',finish);
    child.once('close',code=>{
      if(done)return;
      const events=out.split(/\r?\n/).flatMap(s=>{try{return[JSON.parse(s)];}catch{return[];}});
      const denied=events.some(e=>['command_execution','file_change','mcp_tool_call'].includes(e.item?.type));
      const response=events.filter(e=>e.type==='item.completed' && e.item?.type==='agent_message').map(e=>e.item.text).join('\n');
      if(code || denied || !events.some(e=>e.type==='turn.completed') || events.some(e=>['error','turn.failed'].includes(e.type))) return finish(Error(`Codex failed: ${events.find(e=>e.type==='error')?.message || err.slice(-800) || code}`));
      try{finish(null,JSON.parse(response));}catch{finish(Error('Invalid structured output'));}
    });
    child.stdin.on('error',()=>{});
    if(signal?.aborted)abort();else child.stdin.end(JSON.stringify(input));
  });
}
