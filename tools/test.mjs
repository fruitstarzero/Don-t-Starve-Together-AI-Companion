import fs from 'node:fs';import {spawnSync} from 'node:child_process';
// Only these two suites need copyrighted scripts imported from the user's game.
const native=new Set(['reliability.test.mjs','ui-history.test.mjs']);
const files=fs.readdirSync('test').filter(f=>f.endsWith('.test.mjs')&&!native.has(f)).sort().map(f=>'test/'+f);
const result=spawnSync(process.execPath,['--test',...files],{stdio:'inherit',windowsHide:true});
if(result.error)throw result.error;process.exitCode=result.status??1;
