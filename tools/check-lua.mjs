import fs from 'node:fs';
import path from 'node:path';
import luaparse from 'luaparse';
import {fileURLToPath} from 'node:url';
let n=0;
function walk(dir){for(const e of fs.readdirSync(dir,{withFileTypes:true})){
 const f=path.join(dir,e.name);if(e.isDirectory())walk(f);else if(f.endsWith('.lua')){luaparse.parse(fs.readFileSync(f,'utf8'),{luaVersion:'5.1'});n++;}
}}
walk(fileURLToPath(new URL('../mod',import.meta.url)));console.log(`Lua 5.1 syntax: ${n} files passed`);
