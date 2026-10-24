import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {workshop,showme,replay,disableOrigin,enabledMods} from '../tools/probe-showme-conflict.mjs';

test('Show Me repair only disables Origin when both versions are enabled',()=>{
 const input='return { ["workshop-666155465"]={configuration_options={x=true},enabled=true}, ["workshop-3436020204"]={enabled=true}, wendy_ai_companion={enabled=true} }';
 const fixed=disableOrigin(input);
 assert.equal(fixed,input.replace('x=true},enabled=true','x=true},enabled=false'));
 assert.equal(disableOrigin(fixed),fixed);
 assert.equal(disableOrigin('return {["workshop-666155465"]={enabled=true}}'),'return {["workshop-666155465"]={enabled=true}}');
 assert.ok(enabledMods(fixed).has('wendy_ai_companion'));
});

test('real Show Me callbacks collide only when both versions are active',{
 skip:!showme.every(id=>fs.existsSync(`${workshop}/${id}/modmain.lua`)),
},()=>{
 for(const id of showme)assert.equal(replay([id]).ok,true,id);
 const result=replay(showme);
 assert.equal(result.ok,false);
 assert.match(result.error,/Registering duplicate lua network variable showme_hintbua/);
});
