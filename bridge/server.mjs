import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import {timingSafeEqual} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {DecisionEngine} from './engine.mjs';
import {generate} from './model.mjs';
import {LocalDiary} from './diary.mjs';
import {loadConfig,instanceId} from './config.mjs';

export function createServer({token,engine,port=3131}) {
  const json=(res,code,value)=>{res.writeHead(code,{'content-type':'application/json; charset=utf-8','cache-control':'no-store'});res.end(JSON.stringify(value));};
  const same=s=>typeof s==='string' && Buffer.byteLength(s)===Buffer.byteLength(token) && timingSafeEqual(Buffer.from(s),Buffer.from(token));
  const server=http.createServer(async(req,res)=>{
    if(req.headers.host!==`127.0.0.1:${server.address().port}` || req.headers.origin) return json(res,403,{error:'Local game requests only'});
    if(req.method==='GET' && req.url==='/health')return json(res,200,{service:'wendy-ai',version:'0.8.0',ready:true,instanceId:instanceId(token)});
    if(req.method!=='POST' || !['/v1/tick','/v1/status','/v1/qq/chat','/v1/qq/result','/v1/qq/cancel'].includes(req.url))return json(res,404,{error:'Not found'});
    try {
      let body='';for await(const b of req){body+=b;if(Buffer.byteLength(body)>250000)throw Error('Request too large');}
      const data=JSON.parse(body);
      if(!same(data.token))return json(res,403,{error:'Unauthorized'});
      if(req.url==='/v1/qq/chat'){
        try{const r=engine.remoteChat(data.text,data.id,data.expected);return json(res,200,{id:r.id,status:r.status});}
        catch(e){return json(res,409,{error:e.message});}
      }
      if(req.url==='/v1/qq/result')return json(res,200,engine.remote.result(data.id));
      if(req.url==='/v1/qq/cancel')return json(res,200,engine.remote.cancel(data.id));
      return json(res,200,req.url==='/v1/tick'?engine.tick(data.snapshot):{sessions:engine.status()});
    }catch{return json(res,400,{error:'Invalid request'});}
  });
  server.requestTimeout=15000;server.headersTimeout=10000;
  return server;
}

export function startServer(root){
  const config=loadConfig(root);
  const engine=new DecisionEngine({root,generate:(input,signal)=>generate(root,config,input,signal),diary:new LocalDiary(root)});
  const server=createServer({token:config.token,engine,port:config.port});
  server.listen(config.port,'127.0.0.1',()=>console.log(`Companion bridge on 127.0.0.1:${config.port}`));
  const stop=()=>{engine.close();server.close(()=>process.exit(0));};
  process.once('SIGTERM',stop);process.once('SIGINT',stop);
  return server;
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
  try{startServer(root);}catch(error){console.error(error.message);process.exitCode=1;}
}
