import fs from 'node:fs';
import path from 'node:path';
export class LocalDiary{
  constructor(root){this.file=path.join(root,'state/diary.json');}
  read(){try{
    if(fs.statSync(this.file).size>2000000)return [];
    const value=JSON.parse(fs.readFileSync(this.file,'utf8'));
    return Array.isArray(value)?value.slice(-200):[];
  }catch{return [];}}
  context(query=''){
    const entries=this.read();const terms=query.toLowerCase().split(/[\s，。！？]+/).filter(v=>v.length>1).slice(0,12);
    const related=entries.filter(e=>terms.some(t=>(e.title+' '+e.text+' '+(e.tags||[]).join(' ')).toLowerCase().includes(t)));
    return (related.length?related:entries).slice(-5);
  }
  add(entry){
    if(!entry||typeof entry.text!=='string'||!entry.text.trim())return false;
    const clean={title:String(entry.title||'').slice(0,100),mood:String(entry.mood||'').slice(0,100),
      text:entry.text.slice(0,600),tags:(Array.isArray(entry.tags)?entry.tags:[]).slice(0,8).map(v=>String(v).slice(0,40)),at:new Date().toISOString()};
    const entries=this.read();if(entries.some(e=>e.text===clean.text))return false;
    entries.push(clean);fs.mkdirSync(path.dirname(this.file),{recursive:true});
    fs.writeFileSync(this.file+'.tmp',JSON.stringify(entries.slice(-200),null,2));fs.renameSync(this.file+'.tmp',this.file);return true;
  }
}
