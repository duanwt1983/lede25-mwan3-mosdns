#!/usr/bin/env python3
"""Replace sysupgrade section in flash.js with LEDE component pack upgrade."""
import sys
from pathlib import Path

src = Path(sys.argv[1]).read_text(encoding="utf-8")
out = Path(sys.argv[2])

RPC = (
    "const callLedeApplyUrl=rpc.declare({object:'lede-component',method:'apply_url',params:['url']});"
    "const callLedeApplyFile=rpc.declare({object:'lede-component',method:'apply_file',params:['path']});"
    "const callLedeCompStatus=rpc.declare({object:'lede-component',method:'status',expect:{}});"
    "const ledeCompModalUi={pre:null,status:null,closeBtn:null,foot:null};function ledeCompReadState(){return callLedeCompStatus().catch(function(){return L.resolveDefault(fs.read('/etc/lede-component-state.json'),'{}');}).then(function(raw){if(typeof raw==='object'&&raw!==null)return raw;try{return JSON.parse(raw);}catch(e){return{};}});}function ledeCompSetLog(text){const pre=ledeCompModalUi.pre||document.getElementById('lede-comp-log-pre');if(!pre)return;const t=String(text||'');pre.textContent=t?t.split('\n').slice(-60).join('\n'):'';pre.scrollTop=pre.scrollHeight;}function ledeCompRefreshLog(){return L.resolveDefault(fs.read('/tmp/lede-component-apply.log'),'').then(ledeCompSetLog);}function ledeCompOpenInstallModal(){ledeCompModalUi.pre=E('pre',{'id':'lede-comp-log-pre','style':'max-height:12em;overflow:auto;font-size:11px;line-height:1.35;white-space:pre-wrap;margin:6px 0 0;padding:6px;background:var(--background-color-low,#f4f4f4);border-radius:4px;'},'');ledeCompModalUi.status=E('p',{'id':'lede-comp-log-status','class':'spinning','style':'margin:0;font-size:13px;'},_('安装中…'));ledeCompModalUi.closeBtn=E('button',{'class':'btn cbi-button-action important','disabled':true,'click':function(){ui.hideModal();location.reload();}},_('关闭'));ledeCompModalUi.foot=E('div',{'class':'right','style':'margin-top:8px;'},[ledeCompModalUi.closeBtn]);const panel=E('div',{'style':'width:28rem;max-width:90vw;box-sizing:border-box;'},[ledeCompModalUi.status,ledeCompModalUi.pre,ledeCompModalUi.foot]);ui.showModal(_('组件安装'),[panel],'cbi-modal');ledeCompSetLog(_('安装已开始…\n'));}function ledeCompInstallDone(res){return ledeCompRefreshLog().then(function(){if(ledeCompModalUi.status){ledeCompModalUi.status.className='';ledeCompModalUi.status.textContent=res&&res.pack_id?(_('安装成功：%s %s').format(res.pack_id||'',res.version||'')):_('安装成功');}if(ledeCompModalUi.closeBtn)ledeCompModalUi.closeBtn.disabled=false;});}function ledeCompInstallFail(msg){return ledeCompRefreshLog().then(function(){if(ledeCompModalUi.status){ledeCompModalUi.status.className='alert-message danger';ledeCompModalUi.status.textContent=String(msg||_('安装失败'));}if(ledeCompModalUi.closeBtn)ledeCompModalUi.closeBtn.disabled=false;});}function ledeCompPollApply(deadline){return ledeCompRefreshLog().then(function(){return ledeCompReadState().then(function(st){st=st||{};if(st.running){if(Date.now()>deadline)throw new Error(_('安装超时'));return new Promise(function(r){setTimeout(r,1000);}).then(function(){return ledeCompPollApply(deadline);});}return ledeCompRefreshLog().then(function(){if(st.ok)return{ok:true,pack_id:st.pack_id,version:st.version};throw new Error(st.error||_('安装失败'));});});});}function ledeCompRunApply(path){return callLedeApplyFile(path).then(function(res){if(res&&res.started)return ledeCompPollApply(Date.now()+180000);if(res&&res.ok===false)throw new Error(res.error||_('安装失败'));return res;});}function ledeCompRunApplyUrl(url){return callLedeApplyUrl(url).then(function(res){if(res&&res.started)return ledeCompPollApply(Date.now()+180000);if(res&&res.ok===false)throw new Error(res.error||_('安装失败'));return res;});}const LEDE_COMP_UPLOAD='/tmp/lede-component-upload.tar.gz';function ledeCompExtOk(name){const n=(name||'').toLowerCase();return n.endsWith('.tar.gz')||n.endsWith('.tgz')||n.endsWith('.tar');}function ledeCompIsGzip(u8){return u8&&u8.length>=2&&u8[0]===0x1f&&u8[1]===0x8b;}function ledeCompIsTar(u8){if(!u8||u8.length<262)return false;let m='';for(let i=257;i<262;i++)m+=String.fromCharCode(u8[i]);return m==='ustar';}function ledeCompValidateFile(file){return new Promise(function(resolve){if(!file||!ledeCompExtOk(file.name)){resolve({ok:false,err:_('仅支持 .tar.gz、.tgz、.tar 组件包')});return;}const reader=new FileReader();reader.onload=function(){const u8=new Uint8Array(reader.result||[]);const n=file.name.toLowerCase();if(n.endsWith('.tar.gz')||n.endsWith('.tgz')){resolve(ledeCompIsGzip(u8)?{ok:true}:{ok:false,err:_('不是有效的 gzip 压缩包')});return;}if(ledeCompIsGzip(u8)){resolve({ok:false,err:_('请使用 .tar.gz 或 .tgz 扩展名')});return;}resolve(ledeCompIsTar(u8)?{ok:true}:{ok:false,err:_('不是有效的 tar 包')});};reader.onerror=function(){resolve({ok:false,err:_('无法读取文件')});};reader.readAsArrayBuffer(file.slice(0,512));});}function ledeCompPickFile(){return new Promise(function(resolve){const input=E('input',{type:'file',accept:'.tar,.tgz,.tar.gz,application/gzip,application/x-tar',style:'display:none'});const done=function(f){input.remove();resolve(f||null);};input.addEventListener('change',function(){done(input.files&&input.files[0]);});document.body.appendChild(input);input.click();});}function ledeCompPostUpload(path,file){const fd=new FormData();fd.append('sessionid',rpc.getSessionID());fd.append('filename',path);fd.append('filedata',file,file.name);return fetch(L.env.cgi_base+'/cgi-upload',{method:'POST',body:fd,credentials:'same-origin'}).then(function(res){return res.json();}).then(function(reply){if(reply&&reply.failure&&reply.failure[0])throw new Error(reply.failure[0]);return reply;});}"
)

if "callLedeApplyUrl" not in src:
    src = src.replace(
        "const callSystemValidateFirmwareImage=rpc.declare",
        RPC + "const callSystemValidateFirmwareImage=rpc.declare",
        1,
    )

old_load = (
    "load(){const tasks=[L.resolveDefault(fs.stat('/lib/upgrade/platform.sh'),{}),"
    "fs.trimmed('/proc/sys/kernel/hostname'),fs.trimmed('/proc/mtd'),"
    "fs.trimmed('/proc/partitions'),fs.trimmed('/proc/mounts')];return Promise.all(tasks);}"
)
new_load = (
    "load(){const tasks=[L.resolveDefault(fs.stat('/lib/upgrade/platform.sh'),{}),"
    "fs.trimmed('/proc/sys/kernel/hostname'),L.resolveDefault(fs.trimmed('/proc/mtd'),''),"
    "fs.trimmed('/proc/partitions'),fs.trimmed('/proc/mounts'),"
    "];return Promise.all(tasks);}"
)
if old_load in src:
    src = src.replace(old_load, new_load, 1)

HANDLERS = """,handleLedeComponentUrl(ev){const btn=ev.target;const row=dom.findParent(btn,'.cbi-section');const urlEl=row&&(row.querySelector('[data-name="comp_url"] input')||row.querySelector('input[data-name="comp_url"]'));const url=urlEl?(urlEl.value||'').trim():'';if(!url){ui.addNotification(null,E('p',{},_('请填写 URL')),'danger');return Promise.resolve();}if(btn.firstChild)btn.firstChild.data=_('安装中…');ledeCompOpenInstallModal();return ledeCompRunApplyUrl(url).then(function(res){if(res&&res.ok)return ledeCompInstallDone(res);}).catch(function(e){return ledeCompInstallFail(e.message||String(e));}).finally(function(){if(btn.firstChild)btn.firstChild.data=_('安装');});},handleLedeComponentUpload(ev){const btn=ev.target;const path=LEDE_COMP_UPLOAD;const setPackInfo=function(info){const el=document.getElementById('lede-comp-pack-info');if(!el)return;if(!info){el.textContent='';return;}const name=info.name||'';const kb=info.size?(' ('+Math.round(info.size/1024)+' KB)'):'';el.textContent=_('%s%s → %s').format(name,kb,path);};return ledeCompPickFile().then(function(file){if(!file)return null;if(btn.firstChild)btn.firstChild.data=_('校验中…');return ledeCompValidateFile(file).then(function(v){if(!v.ok){ui.addNotification(null,E('p',{},v.err),'danger');return null;}if(btn.firstChild)btn.firstChild.data=_('上传中…');return ledeCompPostUpload(path,file).then(function(reply){return{name:file.name,size:(reply&&reply.size)||file.size};});});}).then(function(info){if(!info)return;setPackInfo(info);if(btn.firstChild)btn.firstChild.data=_('安装中…');ledeCompOpenInstallModal();return ledeCompRunApply(path);}).then(function(res){if(res&&res.ok)return ledeCompInstallDone(res);else if(res)ui.addNotification(null,E('p',{},res.error||_('失败')),'danger');}).catch(function(e){setPackInfo(null);return ledeCompInstallFail(e.message||String(e));}).finally(function(){if(btn.firstChild)btn.firstChild.data=_('上传组件包');});}"""

if "handleLedeComponentUrl" not in src:
    src = src.replace(",render([p_fstat,hostname", HANDLERS + ",render([p_fstat,hostname", 1)

for old_render_sig, new_render_sig in (
    ("render([p_fstat,hostname,procmtd,procpart,procmounts,compSt,compPacks,compLog])", "render([p_fstat,hostname,procmtd,procpart,procmounts])"),
    ("render([p_fstat,hostname,procmtd,procpart,procmounts,compSt,compLog])", "render([p_fstat,hostname,procmtd,procpart,procmounts])"),
    ("render([p_fstat,hostname,procmtd,procpart,procmounts,compLog])", "render([p_fstat,hostname,procmtd,procpart,procmounts])"),
):
    if old_render_sig in src and old_render_sig != new_render_sig:
        src = src.replace(old_render_sig, new_render_sig, 1)
        break

OLD_FLASH = (
    "o=s.option(form.SectionValue,'actions',form.NamedSection,'actions','actions',"
    "_('Flash new firmware image'),has_sysupgrade?"
    "_('Upload a sysupgrade-compatible image here to replace the running firmware.'):"
    "_('Sorry, there is no sysupgrade support present; a new firmware image must be flashed manually. Please refer to the wiki for device specific install instructions.'));"
    "ss=o.subsection;if(has_sysupgrade){o=ss.option(form.Button,'sysupgrade',_('Image'));"
    "o.inputstyle='action important';o.inputtitle=_('Flash image...');"
    "o.onclick=L.bind(this.handleSysupgrade,this,storage_size,has_rootfs_data);}"
)

NEW_FLASH = (
    "o=s.option(form.SectionValue,'actions',form.NamedSection,'actions','actions',"
    "_('组件升级'));"
    "ss=o.subsection;"
    "o=ss.option(form.DummyValue,'comp_local',_('本地升级'));"
    "o.rawhtml=true;"
    "o.cfgvalue=L.bind(function(){return E('div',{'style':'display:flex;align-items:center;gap:0.5rem;flex-wrap:wrap;'},[E('button',{'class':'btn cbi-button-action important','click':L.bind(this.handleLedeComponentUpload,this)},[_('上传组件包')]),E('span',{'id':'lede-comp-pack-info'})]);},this);"
    "o=ss.option(form.DummyValue,'comp_online',_('在线升级'));"
    "o.rawhtml=true;"
    "o.cfgvalue=L.bind(function(){return E('div',{'style':'display:flex;align-items:center;gap:0.5rem;flex-wrap:wrap;'},[E('input',{'type':'text','data-name':'comp_url','class':'cbi-input-text','style':'flex:1;min-width:12em;max-width:28em','placeholder':'https://example.com/lede-overlay.tar.gz'}),E('button',{'class':'btn cbi-button-apply','click':L.bind(this.handleLedeComponentUrl,this)},[_('安装')])]);},this);"
    "o=s.option(form.SectionValue,'actions',form.NamedSection,'actions','actions',"
    "_('固件升级'),has_sysupgrade?"
    "_('上传 sysupgrade 镜像（如 ext4-combined-efi.img.gz），校验后刷写并重启；会替换整盘固件，不同于组件热更新。'):"
    "_('无 sysupgrade 支持，需线下刷机。'));"
    "ss=o.subsection;"
    "if(has_sysupgrade){"
    "o=ss.option(form.Button,'sysupgrade',_('镜像'));"
    "o.inputstyle='action important';"
    "o.inputtitle=_('刷写固件…');"
    "o.onclick=L.bind(this.handleSysupgrade,this,storage_size,has_rootfs_data);"
    "}"
)

if OLD_FLASH not in src:
    print("WARN: flash.js sysupgrade block not found; skipping replace", file=sys.stderr)
else:
    src = src.replace(OLD_FLASH, NEW_FLASH, 1)

src = src.replace(
    "m=new form.JSONMap(mapdata,_('Flash operations'));",
    "m=new form.JSONMap(mapdata,_('备份与更新'));",
    1,
)
src = src.replace("s=m.section(form.NamedSection,'actions',_('Actions'));", "s=m.section(form.NamedSection,'actions',_('操作'));", 1)

out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(src, encoding="utf-8")
print("wrote", out)
