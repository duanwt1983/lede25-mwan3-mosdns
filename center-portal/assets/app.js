(function () {
  'use strict';

  var base = document.querySelector('meta[name="portal-base"]');
  var PORTAL_BASE = (base && base.content) ? base.content.replace(/\/?$/, '/') : '/home/';
  function readCenterHost() {
    var m = document.querySelector('meta[name="portal-center-host"]');
    return (m && m.content) ? m.content.trim() : 'center.123.gd.cn';
  }

  var PORTAL_HOST = readCenterHost();
  var PORTAL_HTTPS_PORT = '18443';

  function tunnelPublicUrl(port, https) {
    return (https ? 'https' : 'http') + '://' + PORTAL_HOST + ':' + port + '/';
  }

  function portalEntryUrl() {
    return 'https://' + PORTAL_HOST + ':' + PORTAL_HTTPS_PORT + '/home/';
  }

  function $(sel, root) {
    return (root || document).querySelector(sel);
  }

  function tabSetup() {
    var tabs = document.querySelectorAll('.tabs button');
    tabs.forEach(function (btn) {
      btn.addEventListener('click', function () {
        var id = btn.getAttribute('data-tab');
        tabs.forEach(function (b) { b.classList.toggle('active', b === btn); });
        document.querySelectorAll('.panel').forEach(function (p) {
          p.classList.toggle('active', p.id === 'panel-' + id);
        });
      });
    });
  }

  function proxyNamedOnline(status, proxyName) {
    if (!status || !status.tcp || !status.tcp.proxies)
      return false;
    return status.tcp.proxies.some(function (p) {
      return p.name === proxyName && p.status === 'online';
    });
  }

  function proxyOnline(status, siteId) {
    return proxyNamedOnline(status, siteId + '-luci');
  }

  function formatTime(iso) {
    if (!iso) return '—';
    try {
      return new Date(iso).toLocaleString('zh-CN', { hour12: false });
    } catch (e) {
      return iso;
    }
  }

  function renderKpi(sites, status) {
    var total = sites.length;
    var online = sites.filter(function (s) { return proxyOnline(status, s.id); }).length;
    var ver = (status && status.server && status.server.version) ? status.server.version : '—';
    var clients = (status && status.server && status.server.clientCounts != null)
      ? status.server.clientCounts : '—';

    $('#kpi-total').textContent = String(total);
    $('#kpi-online').textContent = String(online);
    $('#kpi-frps').textContent = ver;
    $('#kpi-clients').textContent = String(clients);
    $('#status-updated').textContent = formatTime(status && status.updated);
  }

  function renderSites(sites, status) {
    var grid = $('#site-grid');
    if (!sites.length) {
      grid.innerHTML = '<div class="empty">尚未登记站点。请编辑服务器上的 <code>sites.json</code> 后执行 <code>center-portal-sync</code>。</div>';
      return;
    }

    grid.innerHTML = sites.map(function (site) {
      var on = proxyOnline(status, site.id);
      var tags = (site.tags || []).map(function (t) {
        return '<span class="tag">' + escapeHtml(t) + '</span>';
      }).join('');
      var gwUrl = PORTAL_BASE + 'gw/' + encodeURIComponent(site.id) + '/cgi-bin/luci/';
      var sshHint = site.ssh_port ? ('SSH ' + site.ssh_port) : '无 SSH';
      var tunnelHtml = (site.tunnels || []).map(function (t) {
        var pname = site.id + '-' + t.name;
        var ton = proxyNamedOnline(status, pname);
        var label = escapeHtml(t.remark || t.name) + ' · ' + t.port;
        var local = String(t.local || '');
        var useHttps = /:443\b/.test(local) || local.endsWith(':443');
        var href = tunnelPublicUrl(t.port, useHttps);
        return '<span class="tunnel-chip ' + (ton ? 'on' : 'off') + '">' +
          (ton ? '<a href="' + href + '" target="_blank" rel="noopener">' + label + '</a>' : label) +
          '</span>';
      }).join('');

      return (
        '<article class="site-card">' +
          '<h3><span class="status-dot ' + (on ? 'on' : 'off') + '"></span>' + escapeHtml(site.name) + '</h3>' +
          '<div class="meta">' + escapeHtml(site.region || '') +
            ' · ID: <code>' + escapeHtml(site.id) + '</code></div>' +
          '<div class="tags">' + tags + '</div>' +
          '<div class="meta">' + (on ? 'LuCI 在线' : 'LuCI 离线') + ' · 端口 ' + (site.luci_port || '—') + ' · ' + sshHint + '</div>' +
          (tunnelHtml ? '<div class="tunnel-chips">' + tunnelHtml + '</div>' : '') +
          (site.note ? '<div class="meta">' + escapeHtml(site.note) + '</div>' : '') +
          '<div class="card-actions">' +
            '<a class="' + (on ? '' : 'disabled') + '" href="' + (on ? gwUrl : '#') + '" target="_blank" rel="noopener">打开 LuCI</a>' +
            '<a class="secondary" href="#panel-docs" data-goto-docs="1">接入说明</a>' +
          '</div>' +
        '</article>'
      );
    }).join('');

    grid.querySelectorAll('[data-goto-docs]').forEach(function (a) {
      a.addEventListener('click', function (ev) {
        ev.preventDefault();
        document.querySelector('.tabs button[data-tab="docs"]').click();
      });
    });
  }

  function renderPortTable(sites, status) {
    var tbody = $('#port-table-body');
    if (!sites.length) {
      tbody.innerHTML = '<tr><td colspan="6">暂无</td></tr>';
      return;
    }
    var tmap = tunnelCheckMap(status);
    var rows = [];
    sites.forEach(function (s) {
      rows.push({
        id: s.id, name: s.name, kind: 'LuCI', proxy: 'luci', port: s.luci_port, note: s.luci_host || ''
      });
      if (s.ssh_port) {
        rows.push({
          id: s.id, name: s.name, kind: 'SSH', proxy: 'ssh', port: s.ssh_port, note: ''
        });
      }
      (s.tunnels || []).forEach(function (t) {
        var chk = tmap[s.id + '/' + t.name];
        var live = (chk && chk.frp_target) ? chk.frp_target : '';
        var noteParts = [t.remark, t.local ? ('备忘:' + t.local) : ''];
        if (live) noteParts.push('frp:' + live);
        rows.push({
          id: s.id, name: s.name, kind: '内网 TCP', proxy: t.name, port: t.port,
          note: noteParts.filter(Boolean).join(' · ')
        });
      });
    });
    tbody.innerHTML = rows.map(function (r) {
      return '<tr>' +
        '<td><code>' + escapeHtml(r.id) + '</code></td>' +
        '<td>' + escapeHtml(r.name) + '</td>' +
        '<td>' + escapeHtml(r.kind) + '</td>' +
        '<td><code>' + escapeHtml(r.id + '-' + r.proxy) + '</code></td>' +
        '<td>' + (r.port || '—') + '</td>' +
        '<td>' + escapeHtml(r.note || '') + '</td>' +
      '</tr>';
    }).join('');
  }

  function escapeHtml(s) {
    if (s == null) return '';
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function loadRegistry() {
    return fetch(PORTAL_BASE + 'api/admin/sites', {
      credentials: 'same-origin',
      cache: 'no-store'
    }).then(function (r) {
      if (!r.ok) throw new Error('加载站点登记失败 HTTP ' + r.status);
      return r.json();
    });
  }

  function tunnelCheckMap(status) {
    var map = {};
    (status && status.tunnel_checks || []).forEach(function (c) {
      map[c.site_id + '/' + c.name] = c;
    });
    return map;
  }

  function loadAll() {
    return Promise.all([
      loadRegistry(),
      fetch(PORTAL_BASE + 'api/status.json', { credentials: 'same-origin', cache: 'no-store' })
        .then(function (r) { return r.json(); }).catch(function () { return {}; })
    ]).then(function (arr) {
      var registry = arr[0];
      var status = arr[1];
      var sites = (registry && registry.sites) ? registry.sites : [];
      window._portalStatus = status;
      renderKpi(sites, status);
      renderSites(sites, status);
      renderPortTable(sites, status);
    }).catch(function (err) {
      console.error(err);
      $('#site-grid').innerHTML = '<div class="empty">加载失败，请检查登录状态或联系管理员。</div>';
    });
  }

  window.portalReload = loadAll;

  tabSetup();
  loadAll();
  setInterval(loadAll, 60000);
})();
