import {test} from 'node:test';
import assert from 'node:assert/strict';
import {validateProfilePhoto,renderProfilePicture} from '../dist/js/account.js';

test('Profile pictures accept only non-empty JPG/PNG files up to 2 MB',()=>{
  for(const type of ['image/jpeg','image/png'])for(const size of [1,2097152])assert.doesNotThrow(()=>validateProfilePhoto({type,size}));
  for(const file of [{type:'image/png',size:2097153},{type:'image/png',size:0},{type:'image/gif',size:10},{type:'image/svg+xml',size:10},{type:'application/pdf',size:10},{type:'image/png',size:NaN}])assert.throws(()=>validateProfilePhoto(file),/JPG or PNG/);
});
test('Profile images have fixed dimensions, removal restores initials, and stale load errors cannot replace a new photo',()=>{
  global.Image=class{constructor(width,height){this.width=width;this.height=height;this.parentElement=null;}};
  const target={children:[],textContent:'',replaceChildren(){this.children.forEach(c=>c.parentElement=null);this.children=[];this.textContent='';},append(child){this.children.push(child);child.parentElement=this;}};
  renderProfilePicture(target,'blob:large-image','Example Person',86);
  const first=target.children[0];assert.equal(first.width,86);assert.equal(first.height,86);assert.equal(first.className,'profile-photo');
  renderProfilePicture(target,'https://example.com/private-signed-photo','Example Person',75);
  const second=target.children[0];assert.equal(second.width,75);assert.equal(second.height,75);
  first.onerror();assert.equal(target.children[0],second);assert.equal(target.textContent,'');
  renderProfilePicture(target,null,'Example Person',86);assert.equal(target.children.length,0);assert.equal(target.textContent,'EP');
  second.onerror();assert.equal(target.textContent,'EP');
  delete global.Image;
});
