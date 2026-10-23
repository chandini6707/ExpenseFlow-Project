import { readdir, readFile, access } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const root=fileURLToPath(new URL('../',import.meta.url));
const js=await readdir(path.join(root,'dist/js'));
for(const file of js.filter(f=>f.endsWith('.js'))){const r=spawnSync(process.execPath,['--check',path.join(root,'dist/js',file)],{encoding:'utf8'});if(r.status!==0)throw new Error(r.stderr);}
const pages=(await readdir(path.join(root,'dist'))).filter(f=>f.endsWith('.html'));
for(const page of pages){const text=await readFile(path.join(root,'dist',page),'utf8');for(const match of text.matchAll(/(?:src|href)="([^"#?]+)(?:[?#][^"]*)?"/g)){if(/^(https?:|data:)/.test(match[1]))continue;await access(path.join(root,'dist',match[1]));}}
for(const file of js){const text=await readFile(path.join(root,'dist/js',file),'utf8');for(const match of text.matchAll(/from ['"]([^'"]+)['"]/g)){if(match[1].startsWith('.'))await access(path.join(root,'dist/js',match[1]));}}
const config=await readFile(path.join(root,'dist/config.js'),'utf8');if(/sb_secret_|eyJ[A-Za-z0-9_-]{20,}/.test(config))throw new Error('A credential was unexpectedly committed in config.js.');
console.log(`Checked ${js.length} frontend modules and ${pages.length} HTML pages: valid syntax and local references.`);
