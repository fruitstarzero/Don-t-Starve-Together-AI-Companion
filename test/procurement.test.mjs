import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
import {validateDecision} from '../bridge/schema.mjs';
const src=f=>fs.readFileSync(new URL('../mod/scripts/'+f,import.meta.url),'utf8');
function run(body){const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
 const status=lauxlib.luaL_dostring(L,to_luastring(`local now=100;GetTime=function()return now end
 Vector3=function(x,y,z)return{x=x,z=z}end
 TheWorld={state={isday=true,cycles=1},Map={GetTileAtPoint=function()return 7 end}}
 WORLD_TILES={ROCKY=7,FOREST=8}
 local Q=(function()${src('ai_procurement.lua')}end)()
 local function entity(prefab,x,z)
  return{prefab=prefab,components={},GetPosition=function()return{x=x,z=z}end,HasTag=function()return false end}
 end
 ${body}`));const e=status?to_jsstring(lua.lua_tostring(L,-1)):null;lua.lua_close(L);assert.equal(status,lua.LUA_OK,e);}
test('mining chooses real product sources rather than arbitrary rocks',()=>run(`
 local rocks=entity('rock1',0,0);rocks.components.workable={CanBeWorked=function()return true end}
 assert(Q.Yields(rocks,'rocks') and Q.Yields(rocks,'flint') and not Q.Yields(rocks,'goldnugget'))
 rocks.prefab='rock2';assert(Q.Yields(rocks,'goldnugget'))
 rocks.prefab='rock_ice';assert(Q.Yields(rocks,'ice') and not Q.Yields(rocks,'flint'))
 rocks.prefab='rock_flintless';assert(not Q.Yields(rocks,'flint'))
 `));
test('observed nodes and visited terrain guide travel; depleted close records are invalidated',()=>run(`
 local x=0;local rock=entity('rock2',10,0);rock.components.workable={CanBeWorked=function()return true end}
 local entities={rock};local dest
 local c={inst={GetPosition=function()return{x=x,z=0}end,GetDistanceSqToPoint=function(_,p)return(p.x-x)^2+p.z^2 end},
  Scan=function()return entities end,MoveTo=function(_,p)dest=p;return true end}
 Q.Observe(c);assert(next(c.resource_memory) and next(c.terrain_memory))
 x=50;assert(Q.Search(c,'goldnugget') and dest.x==10,'return to the observed gold vein first')
 local saved=c.resource_memory;c.material_searches=nil;c.resource_memory=saved
 x=10;entities={};now=106;Q.Observe(c);assert(not next(c.resource_memory),'empty node must not be trusted forever')
 c.terrain_memory={visited={x=90,z=0,tile=7,day=1}};c.material_searches=nil
 assert(Q.Search(c,'goldnugget') and dest.x==90,'only a visited rocky area is a legitimate terrain lead')
 TheWorld.state.isday=false;assert(not Q.Search(c,'goldnugget'),'do not expand exploration at night')
 `));
test('unknown routes are bounded per material/day and do not start fires for charcoal',()=>run(`
 local c={inst={GetPosition=function()return{x=0,z=0}end,GetDistanceSqToPoint=function()return 10000 end},MoveTo=function()return true end}
 assert(Q.Search(c,'flint'))
 for i=1,10 do now=now+21;Q.Search(c,'flint')end
 assert(not Q.Search(c,'flint') and c.material_searches.flint.index>8)
 assert(not Q.Search(c,'charcoal') and not Q.Search(c,'silk'))
 TheWorld.state.cycles=2;assert(Q.Search(c,'flint'),'a new day can revisit resource search')
 `));
test('refinement aliases and actual ingredient modifiers preserve production requirements',()=>run(`
 AllRecipes={custom_boards={name='custom_boards',product='boards',ingredients={{type='log',amount=4}},character_ingredients={}},
   other={name='other',product='boards',builder_tag='other_character'}}
 assert(Q.RecipeFor('boards').name=='custom_boards')
 local c={inst={components={builder={ingredientmod=.5}}}}
 assert(Q.Requirements(c,AllRecipes.custom_boards)[1].required==2)
 `));
test('observed basic-science recipes can be prepared without inventing unknown character recipes',()=>{
 const d={reply:'准备制作',command:null,plan:{activity:'craft',recipe:'icebox',prefab:null,count:1,reason:'准备冰箱'},tripSeconds:240,taskStatus:'ongoing',experiences:[]};
 assert.equal(validateDecision(d,{source:'chat',snapshot:{recipeDetails:[{id:'icebox',canPrepare:true}]}}),d);
 assert.throws(()=>validateDecision(d,{source:'chat',snapshot:{recipeDetails:[{id:'icebox',canPrepare:false}]}}));
});
