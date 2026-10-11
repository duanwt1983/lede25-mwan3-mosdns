(function () {
  'use strict';

  var base = document.querySelector('meta[name="portal-base"]');
  var PORTAL_BASE = (base && base.content) ? base.content.replace(/\/?$/, '/') : '/home/';
  var API = PORTAL_BASE + 'api/admin/sites';
  var BOOTSTRAP_API = PORTAL_BASE + 'api/admin/bootstrap';
  var STATUS_API = PORTAL_BASE + 'api/status.json';

  var registry = { version: 1, sites: [] };
  var frpStatus = null;
  function readCenterHost() {
    var m = document.querySelector('meta[name="portal-center-host"]');
    return (m && m.content) ? m.content.trim() : 'center.123.gd.cn';
  }

  /** 内网隧道 / 登记页访问链接（业务域名，勿与 bootstrap 混用） */
  var tunnelHost = readCenterHost();
  /** 复制到网关 frpc 的中心地址 */
  var frpcServer = readCenterHost();
  var tunnelPortMin = 19100;
  var tunnelPortMax = 19999;
  var reservedCenterPorts = [8000, 80, 443, 9091, 8765, 18443, 18007];

  /** @type {null|string} */
  var editingId = null;
  /** @type {null|'site'|'tunnels'|'new'} */
  var panelMode = null;
  var tunnelDirty = false;

  function $(id) { return document.getElementById(id); }

  function msg(text, isErr) {
    var el = $('admin-msg');
    if (!el) return;
    el.textContent = text || '';
    el.className = 'admin-msg' + (isErr ? ' err' : text ? ' ok' : '');
  }

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }
  function escAttr(s) { return esc(s).replace(/"/g, '&quot;'); }

  function allUsedPorts() {
    var used = [];
    registry.sites.forEach(function (s) {
      if (s.luci_port) used.push(s.luci_port);
      if (s.ssh_port) used.push(s.ssh_port);
      (s.tunnels || []).forEach(function (t) {
        if (t.port) used.push(t.port);
      });
    });
    return used;
  }

  function nextLuciPort() {
    var used = allUsedPorts();
    for (var p = 19001; p <= 19999; p++) {
      if (used.indexOf(p) === -1) return p;
    }
    return 19001;
  }

  function nextSshPort(luci) {
    var used = allUsedPorts();
    var basePort = luci + 100;
    if (used.indexOf(basePort) === -1) return basePort;
    for (var p = 19101; p <= 19999; p++) {
      if (used.indexOf(p) === -1) return p;
    }
    return 0;
  }

  function nextTunnelPort() {
    var used = allUsedPorts();
    for (var p = tunnelPortMin; p <= tunnelPortMax; p++) {
      if (used.indexOf(p) === -1) return p;
    }
    return tunnelPortMin;
  }

  function tunnelPortConflict(port) {
    if (port < tunnelPortMin || port > tunnelPortMax) return '建议改用 ' + tunnelPortMin + '–' + tunnelPortMax;
    if (reservedCenterPorts.indexOf(port) >= 0) return '该端口被中心机 Nginx/面板占用，frp 无法监听';
    return '';
  }

  function tunnelLinkMode(local) {
    var s = String(local || '');
    if (/:(443|8443)\s*$/.test(s)) return 'https';
    if (/:(80|8080)\s*$/.test(s)) return 'http';
    return 'both';
  }

  function statusProxies(st) {
    var s = st || frpStatus;
    if (!s) return [];
    if (s.proxies_tcp && s.proxies_tcp.length) return s.proxies_tcp;
    if (s.tcp && s.tcp.proxies) return s.tcp.proxies;
    return [];
  }

  function proxyNamedOnline(proxyName) {
    return statusProxies().some(function (p) {
      return p.name === proxyName && p.status === 'online';
    });
  }

  function tunnelAccessUrl(port, https) {
    return (https ? 'https' : 'http') + '://' + tunnelHost + ':' + port + '/';
  }

  function copyText(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text).then(function () { msg('已复制到剪贴板'); });
    }
    msg('请手动复制：' + text, true);
    return Promise.resolve();
  }

  function readTunnelsFromForm(strict) {
    var tbody = $('adm-tunnels-body');
    if (!tbody) return [];
    var rows = tbody.querySelectorAll('tr');
    var out = [];
    for (var idx = 0; idx < rows.length; idx++) {
      var tr = rows[idx];
      var name = (tr.querySelector('[data-f="name"]').value || '').trim();
      var portRaw = (tr.querySelector('[data-f="port"]').value || '').trim();
      var remark = (tr.querySelector('[data-f="remark"]').value || '').trim();
      var local = (tr.querySelector('[data-f="local"]').value || '').trim();
      if (!name && !portRaw && !remark && !local) continue;
      var port = parseInt(portRaw, 10);
      if (!name || !/^[a-zA-Z0-9_-]{2,32}$/.test(name)) {
        if (strict) throw new Error('第 ' + (idx + 1) + ' 行：代理名须 2–32 位字母数字 _ -');
        continue;
      }
      if (isNaN(port) || port < 1024 || port > 65535) {
        if (strict) throw new Error('第 ' + (idx + 1) + ' 行「' + name + '」：中心端口无效');
        continue;
      }
      var conflict = tunnelPortConflict(port);
      if (conflict && strict) throw new Error('第 ' + (idx + 1) + ' 行「' + name + '」：' + conflict);
      var t = { name: name, port: port };
      if (remark) t.remark = remark;
      if (local) t.local = local;
      out.push(t);
    }
    return out;
  }

  function renderTunnelRows(tunnels) {
    var tbody = $('adm-tunnels-body');
    if (!tbody) return;
    tbody.innerHTML = '';
    (tunnels || []).forEach(function (t) { addTunnelRow(t); });
    tunnelDirty = false;
  }

  function addTunnelRow(data) {
    var tbody = $('adm-tunnels-body');
    if (!tbody) return;
    var tr = document.createElement('tr');
    tr.innerHTML =
      '<td><input class="tunnel-inp" data-f="name" placeholder="nvr"></td>' +
      '<td><input class="tunnel-inp" data-f="port" type="number" min="1024" max="65535"></td>' +
      '<td><input class="tunnel-inp" data-f="remark" placeholder="说明"></td>' +
        '<td><input class="tunnel-inp" data-f="local" placeholder="备忘，如 192.168.9.x:80"></td>' +
      '<td><button type="button" class="btn-sm danger tunnel-del">删</button></td>';
    tr.querySelector('[data-f="name"]').value = (data && data.name) || '';
    tr.querySelector('[data-f="port"]').value = (data && data.port) || nextTunnelPort();
    tr.querySelector('[data-f="remark"]').value = (data && data.remark) || '';
    tr.querySelector('[data-f="local"]').value = (data && data.local) || '';
    tr.querySelector('.tunnel-del').addEventListener('click', function () {
      tr.remove();
      tunnelDirty = true;
    });
    tr.querySelectorAll('.tunnel-inp').forEach(function (inp) {
      inp.addEventListener('input', function () { tunnelDirty = true; });
    });
    tbody.appendChild(tr);
    tunnelDirty = true;
  }

  function readSiteBasicsFromDom(prefix) {
    prefix = prefix || '';
    var ssh = parseInt($(prefix + 'adm-ssh').value, 10);
    if (isNaN(ssh)) ssh = 0;
    return {
      id: $(prefix + 'adm-id').value.trim(),
      name: $(prefix + 'adm-name').value.trim(),
      region: $(prefix + 'adm-region').value.trim(),
      luci_port: parseInt($(prefix + 'adm-luci').value, 10),
      ssh_port: ssh,
      tags: $(prefix + 'adm-tags').value.split(',').map(function (t) { return t.trim(); }).filter(Boolean),
      note: $(prefix + 'adm-note').value.trim()
    };
  }

  function fillSiteBasicsDom(site, prefix) {
    prefix = prefix || '';
    var s = site || {};
    $(prefix + 'adm-id').value = s.id || '';
    $(prefix + 'adm-id').disabled = !!(s.id && registry.sites.some(function (x) { return x.id === s.id; }));
    $(prefix + 'adm-name').value = s.name || '';
    $(prefix + 'adm-region').value = s.region || '';
    $(prefix + 'adm-luci').value = s.luci_port != null ? s.luci_port : nextLuciPort();
    $(prefix + 'adm-ssh').value = s.ssh_port != null ? s.ssh_port : nextSshPort(nextLuciPort());
    $(prefix + 'adm-tags').value = s.tags && s.tags.length ? s.tags.join(', ') : '';
    $(prefix + 'adm-note').value = s.note || '';
  }

  function tunnelCheckFor(siteId, name) {
    if (!frpStatus || !frpStatus.tunnel_checks) return null;
    for (var i = 0; i < frpStatus.tunnel_checks.length; i++) {
      var c = frpStatus.tunnel_checks[i];
      if (c.site_id === siteId && c.name === name) return c;
    }
    return null;
  }

  function frpTunnelTarget(siteId, name) {
    var chk = tunnelCheckFor(siteId, name);
    var raw = '';
    if (chk && chk.frp_target) raw = chk.frp_target;
    if (!raw) {
      var pname = siteId + '-' + name;
      var plist = statusProxies();
      for (var i = 0; i < plist.length; i++) {
        var p = plist[i];
        if (p.name !== pname || !p.conf) continue;
        var ip = p.conf.localIP || '';
        var port = p.conf.localPort;
        if (!ip) break;
        raw = port != null && port !== '' ? (ip + ':' + port) : ip;
        break;
      }
    }
    if (!raw || raw === '127.0.0.1' || raw.indexOf('127.0.0.1:') === 0) return '';
    return raw;
  }

  function renderTunnelReadonlyTable(site) {
    var tunnels = site.tunnels || [];
    if (!tunnels.length) {
      return '<p class="sub tunnel-empty">暂无内网隧道。点「编辑内网隧道」添加。</p>';
    }
    var rows = tunnels.map(function (t) {
      var pname = site.id + '-' + t.name;
      var on = proxyNamedOnline(pname);
      var conflict = tunnelPortConflict(t.port);
      var localStr = String(t.local || '');
      if (!conflict && (localStr.indexOf('6.251') >= 0 || localStr.indexOf('192.168.6.251') >= 0)) {
        conflict = '内网目标误填为中心机 6.251，请改为门店 LAN 内 IP';
      }
      var httpUrl = tunnelAccessUrl(t.port, false);
      var httpsUrl = tunnelAccessUrl(t.port, true);
      var mode = tunnelLinkMode(t.local);
      var links = '';
      if (conflict) {
        links = '<span class="tunnel-warn">' + esc(conflict) + '</span>';
      } else if (!on) {
        links = '<span class="sub">隧道离线，请检查网关 frpc</span>';
      } else {
        if (mode === 'http' || mode === 'both') {
          links += '<a class="btn-sm link-btn" href="' + escAttr(httpUrl) + '" target="_blank" rel="noopener">HTTP</a> ';
        }
        if (mode === 'https' || mode === 'both') {
          links += '<a class="btn-sm link-btn" href="' + escAttr(httpsUrl) + '" target="_blank" rel="noopener">HTTPS</a> ';
        }
        links += '<button type="button" class="btn-sm" data-copy-url="' + escAttr(mode === 'https' ? httpsUrl : httpUrl) + '">复制链接</button>';
      }
      var live = frpTunnelTarget(site.id, t.name);
      var memo = t.local || '—';
      var liveCell = live
        ? ('<code>' + esc(live) + '</code>' +
          (memo !== '—' && memo !== live ? ' <span class="tunnel-warn">与备忘不一致</span>' : ''))
        : '—';
      var chk = tunnelCheckFor(site.id, t.name);
      if (chk && chk.hint && chk.level === 'bad') {
        links += '<div class="tunnel-warn" style="margin-top:6px;max-width:22em">' + esc(chk.hint) + '</div>';
      }
      return '<tr>' +
        '<td><code>' + esc(t.name) + '</code></td>' +
        '<td>' + esc(t.remark || '—') + '</td>' +
        '<td>' + esc(memo) + '</td>' +
        '<td>' + liveCell + '</td>' +
        '<td><code>' + esc(pname) + '</code></td>' +
        '<td>' + t.port + (conflict ? ' ⚠' : '') + '</td>' +
        '<td><span class="tunnel-pill ' + (on ? 'on' : 'off') + '">' + (on ? '在线' : '离线') + '</span></td>' +
        '<td class="tunnel-link-cell">' + links + '</td></tr>';
    }).join('');
    return '<table class="data tunnel-readonly">' +
      '<thead><tr><th>代理名</th><th>说明</th><th>内网备忘</th><th>frps 参考</th><th>frp 名</th><th>中心端口</th><th>状态</th><th>访问</th></tr></thead>' +
      '<tbody>' + rows + '</tbody></table>';
  }

  function siteFormHtml(site, isNew) {
    var title = isNew ? '新建站点' : ('编辑站点 · ' + esc(site.id));
    return (
      '<div class="admin-card-panel">' +
        '<h4>' + title + '</h4>' +
        '<div class="admin-grid">' +
          '<label>站点 ID <input id="adm-id" pattern="[a-zA-Z0-9_-]{2,32}"></label>' +
          '<label>显示名称 <input id="adm-name"></label>' +
          '<label>区域 <input id="adm-region" placeholder="如：晋城、广州"></label>' +
          '<label>LuCI 中心端口 <input id="adm-luci" type="number" min="1024" max="65535"></label>' +
          '<label>SSH 中心端口（0=不映射） <input id="adm-ssh" type="number" min="0" max="65535" value="0"></label>' +
          '<label>标签 <input id="adm-tags" placeholder="逗号分隔"></label>' +
        '</div>' +
        '<label class="admin-note">备注 <textarea id="adm-note" rows="2"></textarea></label>' +
        '<div class="admin-actions">' +
          '<button type="button" class="btn-secondary" id="adm-suggest">建议端口</button>' +
          '<button type="button" class="btn-secondary" id="adm-cancel-panel">取消</button>' +
          '<button type="button" class="btn-primary" id="adm-save-site">保存站点信息</button>' +
        '</div>' +
      '</div>'
    );
  }

  function tunnelFormHtml(site) {
    return (
      '<div class="admin-card-panel">' +
        '<h4>编辑内网隧道 · 站点 <code>' + esc(site.id) + '</code>' +
          (site.region ? (' · 区域 ' + esc(site.region)) : '') +
          ' · ' + esc(site.name) + '</h4>' +
        '<p class="sub">中心端口请用 <strong>' + tunnelPortMin + '–' + tunnelPortMax + '</strong>（勿用 8000/80/443 等中心已占用端口）。</p>' +
        '<table class="data tunnel-table"><thead><tr><th>代理名</th><th>中心端口</th><th>说明</th><th>内网备忘</th><th></th></tr></thead>' +
        '<tbody id="adm-tunnels-body"></tbody></table>' +
        '<div class="tunnel-editor-actions">' +
          '<button type="button" class="btn-secondary" id="adm-tunnel-add">添加内网隧道</button>' +
          '<button type="button" class="btn-primary" id="adm-save-tunnels">保存内网隧道</button>' +
        '</div>' +
      '</div>'
    );
  }

  function renderSiteCard(site) {
    var isOpenSite = panelMode === 'site' && editingId === site.id;
    var isOpenTunnels = panelMode === 'tunnels' && editingId === site.id;
    var gwUrl = PORTAL_BASE + 'gw/' + encodeURIComponent(site.id) + '/cgi-bin/luci/';
    var luciOn = proxyNamedOnline(site.id + '-luci');
    var region = site.region ? ('<span class="region-badge">' + esc(site.region) + '</span>') : '';

    var panel = '';
    if (isOpenSite) panel = siteFormHtml(site, false);
    if (isOpenTunnels) panel = tunnelFormHtml(site);

    return (
      '<article class="admin-site-card" id="card-' + escAttr(site.id) + '">' +
        '<header class="admin-site-card-head">' +
          region +
          '<h3>' + esc(site.name) + ' <code class="site-id">' + esc(site.id) + '</code></h3>' +
          '<div class="admin-site-card-actions">' +
            '<button type="button" class="btn-sm" data-act="edit-site" data-id="' + escAttr(site.id) + '">编辑站点</button>' +
            '<button type="button" class="btn-sm" data-act="edit-tunnels" data-id="' + escAttr(site.id) + '">编辑内网隧道</button>' +
            '<button type="button" class="btn-sm danger" data-act="del" data-id="' + escAttr(site.id) + '">删除</button>' +
          '</div>' +
        '</header>' +
        '<div class="admin-site-meta">' +
          '<div>LuCI 中心端口 <strong>' + site.luci_port + '</strong> ' +
            '<span class="tunnel-pill ' + (luciOn ? 'on' : 'off') + '">' + (luciOn ? '在线' : '离线') + '</span> ' +
            '<a class="btn-sm link-btn" href="' + escAttr(gwUrl) + '" target="_blank" rel="noopener">打开 LuCI（门户）</a></div>' +
          (site.ssh_port ? ('<div>SSH 中心端口 <strong>' + site.ssh_port + '</strong></div>') : '') +
          (site.note ? ('<div class="sub">' + esc(site.note) + '</div>') : '') +
        '</div>' +
        '<div class="admin-site-tunnels">' +
          '<h4>内网隧道 <span class="count">' + (site.tunnels || []).length + '</span></h4>' +
          renderTunnelReadonlyTable(site) +
        '</div>' +
        panel +
      '</article>'
    );
  }

  function renderSiteCards() {
    var root = $('admin-site-cards');
    var newSlot = $('admin-new-site-slot');
    if (!root) return;

    if (!registry.sites.length && panelMode !== 'new') {
      root.innerHTML = '<div class="empty">暂无站点，请点击右上角「＋ 新建站点」。</div>';
    } else {
      root.innerHTML = registry.sites.map(renderSiteCard).join('');
    }

    if (newSlot) {
      if (panelMode === 'new') {
        newSlot.innerHTML = '<article class="admin-site-card admin-site-card--new">' + siteFormHtml(null, true) + '</article>';
        fillSiteBasicsDom(null);
      } else {
        newSlot.innerHTML = '';
      }
    }

    if (panelMode === 'tunnels' && editingId) {
      var site = registry.sites.find(function (s) { return s.id === editingId; });
      if (site) renderTunnelRows(site.tunnels || []);
    }
    if (panelMode === 'site' && editingId) {
      var site2 = registry.sites.find(function (s) { return s.id === editingId; });
      if (site2) fillSiteBasicsDom(site2);
    }
  }

  function openSitePanel(id) {
    if (tunnelDirty && !confirm('内网隧道有未保存修改，确定切换？')) return;
    editingId = id;
    panelMode = 'site';
    tunnelDirty = false;
    renderSiteCards();
    var el = $('card-' + id);
    if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  function openTunnelsPanel(id) {
    if (tunnelDirty && editingId !== id && !confirm('内网隧道有未保存修改，确定切换？')) return;
    editingId = id;
    panelMode = 'tunnels';
    tunnelDirty = false;
    renderSiteCards();
    var el = $('card-' + id);
    if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  function closePanel() {
    editingId = null;
    panelMode = null;
    tunnelDirty = false;
    renderSiteCards();
    msg('');
  }

  function deleteSite(id) {
    if (!confirm('确定删除站点「' + id + '」及其登记的全部隧道？')) return;
    registry.sites = registry.sites.filter(function (s) { return s.id !== id; });
    closePanel();
    saveRegistry('正在删除…', null, '已删除站点「' + id + '」。');
  }

  function saveRegistry(hint, keepEditingId, successMsg) {
    msg(hint || '正在保存…', false);
    return fetch(API, {
      method: 'PUT',
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(registry)
    }).then(function (r) {
      return r.json().then(function (body) {
        if (!r.ok || !body.ok) {
          var err = body.error || ('HTTP ' + r.status);
          if (body.detail) err += '：' + body.detail;
          throw new Error(err);
        }
        registry = body.registry || registry;
        if (keepEditingId && panelMode === 'tunnels' && tunnelDirty) {
          var saved = registry.sites.find(function (s) { return s.id === keepEditingId; });
          var sent = readTunnelsFromForm(false);
          if (sent.length && (!saved || !(saved.tunnels || []).length)) {
            throw new Error('内网隧道未写入服务器，请执行 systemctl restart center-portal-admin');
          }
        }
        tunnelDirty = false;
        if (panelMode === 'new' && keepEditingId) {
          editingId = keepEditingId;
          panelMode = 'tunnels';
        }
        renderSiteCards();
        msg(successMsg || '已保存。');
        if (window.portalReload) window.portalReload();
      });
    }).catch(function (e) {
      msg(e.message || String(e), true);
    });
  }

  function saveSiteHandler() {
    var basics = readSiteBasicsFromDom('');
    if (!basics.id || !basics.name || isNaN(basics.luci_port)) {
      msg('请填写站点 ID、名称、LuCI 端口', true);
      return;
    }
    var idx = registry.sites.findIndex(function (s) { return s.id === basics.id; });
    if (idx >= 0) {
      var prev = registry.sites[idx];
      var merged = Object.assign({}, prev, basics);
      if (prev.tunnels && prev.tunnels.length) merged.tunnels = prev.tunnels;
      if (prev.luci_host && !basics.luci_host) merged.luci_host = prev.luci_host;
      registry.sites[idx] = merged;
      if (!basics.note) delete registry.sites[idx].note;
      if (!basics.region) delete registry.sites[idx].region;
    } else {
      registry.sites.push(Object.assign({}, basics));
    }
    var wasNew = panelMode === 'new';
    return saveRegistry('正在保存站点…', basics.id,
      wasNew ? ('站点「' + basics.id + '」已创建，请在下方面板添加内网隧道。') : ('站点「' + basics.id + '」已更新。'))
      .then(function () {
        if (wasNew) {
          editingId = basics.id;
          panelMode = 'tunnels';
          renderSiteCards();
        }
      });
  }

  function validateTunnelList(tunnels) {
    var names = {};
    for (var i = 0; i < tunnels.length; i++) {
      if (names[tunnels[i].name]) throw new Error('代理名重复：' + tunnels[i].name);
      names[tunnels[i].name] = true;
    }
  }

  function saveTunnelsHandler() {
    if (!editingId) {
      msg('请先选择站点', true);
      return;
    }
    var badLocal = readTunnelsFromForm(false).filter(function (t) {
      var L = (t.local || '').toLowerCase();
      return L.indexOf('6.251') >= 0 || L.indexOf('192.168.6.251') >= 0;
    });
    if (badLocal.length && !window.confirm(
      '内网备忘中含有中心机 6.251：隧道会从门店网关转回中心服务器，通常不是你要的内网设备。确定仍要保存？')) {
      return;
    }
    var idx = registry.sites.findIndex(function (s) { return s.id === editingId; });
    if (idx < 0) {
      msg('站点不存在', true);
      return;
    }
    var tunnels;
    try {
      tunnels = readTunnelsFromForm(true);
      validateTunnelList(tunnels);
    } catch (e) {
      msg(e.message || String(e), true);
      return;
    }
    var next = Object.assign({}, registry.sites[idx]);
    if (tunnels.length) next.tunnels = tunnels;
    else delete next.tunnels;
    registry.sites[idx] = next;
    saveRegistry('正在保存内网隧道…', editingId,
      '站点「' + editingId + '」已保存 ' + tunnels.length + ' 条隧道，可在上方列表点击「打开 HTTP/HTTPS」。');
    panelMode = 'tunnels';
  }

  function loadBootstrap() {
    return fetch(BOOTSTRAP_API, { credentials: 'same-origin' })
      .then(function (r) { return r.json(); })
      .then(function (data) {
        if (!data.ok) throw new Error(data.error || '无法加载 Token');
        frpcServer = data.server || readCenterHost();
        if (data.tunnel_port_min) tunnelPortMin = data.tunnel_port_min;
        if (data.tunnel_port_max) tunnelPortMax = data.tunnel_port_max;
        if (data.reserved_center_ports) reservedCenterPorts = data.reserved_center_ports;
        $('bp-server').textContent = frpcServer;
        $('bp-port').textContent = String(data.port || 18007);
        $('bp-token').textContent = data.token || '';
        $('bp-token').classList.add('token-blur');
        $('bp-reveal').textContent = '显示';
        $('bp-err').textContent = '';
        var caLink = $('bp-ca-link');
        var caSha = $('bp-ca-sha');
        if (data.ca_available && data.ca_cert_url && caLink) {
          caLink.href = data.ca_cert_url;
          caLink.textContent = '下载根 CA';
          if (caSha && data.ca_cert_sha256) {
            caSha.textContent = ' SHA256 ' + data.ca_cert_sha256.slice(0, 16) + '…';
          }
        } else if (caLink) {
          caLink.removeAttribute('href');
          caLink.textContent = '未签发（请在中心执行 center-portal-ca-init）';
        }
        var caCopy = $('bp-ca-copy-url');
        if (caCopy) {
          caCopy.onclick = function () {
            if (data.ca_cert_url) copyText(data.ca_cert_url);
          };
        }
      })
      .catch(function (e) {
        $('bp-err').textContent = e.message || String(e);
      });
  }

  function loadStatus() {
    return fetch(STATUS_API, { credentials: 'same-origin' })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (s) { frpStatus = s; })
      .catch(function () { frpStatus = null; });
  }

  function loadRegistry() {
    return Promise.all([
      fetch(API, { credentials: 'same-origin', cache: 'no-store' }).then(function (r) {
        if (!r.ok) throw new Error('加载失败 HTTP ' + r.status);
        return r.json();
      }),
      loadStatus()
    ]).then(function (res) {
      registry = res[0];
      if (!registry.sites) registry.sites = [];
      renderSiteCards();
    });
  }

  function setupCopyButtons() {
    document.querySelectorAll('.copy[data-copy]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var id = btn.getAttribute('data-copy');
        var el = $(id);
        var text = el.textContent || '';
        if (id === 'bp-token') el.classList.remove('token-blur');
        copyText(text);
      });
    });
    var rev = $('bp-reveal');
    if (rev) {
      rev.addEventListener('click', function () {
        var t = $('bp-token');
        var on = t.classList.toggle('token-blur');
        rev.textContent = on ? '显示' : '隐藏';
      });
    }
  }

  function initAdmin() {
    var panel = $('panel-admin');
    if (!$('admin-site-cards') || !panel) return;
    setupCopyButtons();
    loadBootstrap();
    panel.addEventListener('click', function (ev) {
      var t = ev.target;
      if (!(t instanceof Element)) return;
      var actBtn = t.closest('[data-act]');
      if (actBtn) {
        var id = actBtn.getAttribute('data-id');
        var act = actBtn.getAttribute('data-act');
        if (act === 'edit-site') openSitePanel(id);
        else if (act === 'edit-tunnels') openTunnelsPanel(id);
        else if (act === 'del') deleteSite(id);
        return;
      }
      var copyBtn = t.closest('[data-copy-url]');
      if (copyBtn) {
        copyText(copyBtn.getAttribute('data-copy-url') || '');
        return;
      }
      if (t.id === 'adm-save-site') saveSiteHandler();
      else if (t.id === 'adm-save-tunnels') saveTunnelsHandler();
      else if (t.id === 'adm-tunnel-add') addTunnelRow(null);
      else if (t.id === 'adm-cancel-panel') closePanel();
      else if (t.id === 'adm-suggest') {
        if ($('adm-id') && !$('adm-id').disabled) {
          $('adm-luci').value = nextLuciPort();
          $('adm-ssh').value = nextSshPort(parseInt($('adm-luci').value, 10));
        }
      }
    });
    $('adm-new-site').addEventListener('click', function () {
      if (tunnelDirty && !confirm('有未保存的内网隧道修改，继续新建？')) return;
      editingId = null;
      panelMode = 'new';
      tunnelDirty = false;
      renderSiteCards();
      $('admin-new-site-slot').scrollIntoView({ behavior: 'smooth' });
    });
    window.addEventListener('beforeunload', function (ev) {
      if (!tunnelDirty) return;
      ev.preventDefault();
      ev.returnValue = '';
    });
    loadRegistry().catch(function (e) { msg(e.message, true); });
  }

  window.initPortalAdmin = initAdmin;
})();
