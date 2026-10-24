import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
export const instanceId=token=>createHash('sha256').update(token).digest('hex').slice(0,16);
export function validateConfig(config){
  if(!config||!Number.isInteger(config.port)||config.port<1024||config.port>65535
    ||typeof config.token!=='string'||!/^[a-f0-9]{64}$/.test(config.token))throw Error('Invalid local config. Run npm run setup first.');
  for(const key of ['codexPath','model'])if(config[key]!=null&&(typeof config[key]!=='string'||config[key].length>2000))throw Error('Invalid model configuration');
  return config;
}
export function loadConfig(root){
  const file=path.join(root,'bridge/config.json');
  if(!fs.existsSync(file))throw Error('Local config missing. Run npm run setup -- --game <game directory>');
  return validateConfig(JSON.parse(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,'')));
}
