(function () {
  'use strict';

  var AUTHELIA = '/authelia';
  var PWD_API = '/home/api/account/password';

  function $(sel, root) {
    return (root || document).querySelector(sel);
  }

  function msg(text, kind) {
    var el = $('#acc-msg');
    if (!el) return;
    el.textContent = text || '';
    el.className = 'acc-msg' + (kind ? (' ' + kind) : '');
  }

  function parseJsonRes(res) {
    return res.text().then(function (t) {
      try {
        return t ? JSON.parse(t) : null;
      } catch (e) {
        return null;
      }
    });
  }

  function autheliaFetch(method, path, body) {
    return fetch(AUTHELIA + path, {
      method: method,
      credentials: 'same-origin',
      cache: 'no-store',
      headers: body ? { 'Content-Type': 'application/json' } : {},
      body: body ? JSON.stringify(body) : undefined
    }).then(function (res) {
      return parseJsonRes(res).then(function (data) {
        return { ok: res.ok, status: res.status, data: data };
      });
    });
  }

  function apiData(res) {
    var d = res && res.data;
    if (!d) return null;
    if (d.status === 'OK' && d.data !== undefined) return d.data;
    if (d.ok && d.data !== undefined) return d.data;
    return null;
  }

  function showOtc(on) {
    var block = $('#acc-otc-block');
    if (block) block.hidden = !on;
    window._accNeedOtc = !!on;
  }

  function loadAccountPanel() {
    msg('');
    showOtc(false);
    window._accNeedOtc = false;
    var form = $('#acc-password-form');
    if (form) form.reset();

    var meReq = fetch('/home/api/account/me', {
      credentials: 'same-origin',
      cache: 'no-store'
    }).then(function (r) {
      return parseJsonRes(r).then(function (b) {
        return { status: r.status, body: b || {} };
      });
    });

    return Promise.all([
      meReq,
      autheliaFetch('GET', '/api/configuration')
    ]).then(function (arr) {
      var meRes = arr[0];
      var cfgRes = arr[1];
      if (meRes.status === 401 || meRes.status === 403) {
        throw new Error('未登录或会话已过期，请重新打开门户并登录 Authelia');
      }
      if (meRes.status !== 200 || !meRes.body || !meRes.body.ok) {
        throw new Error(
          (meRes.body && meRes.body.error) || '无法读取当前账户'
        );
      }
      var me = meRes.body;
      var cfg = apiData(cfgRes) || cfgRes.data || {};
      window._accCfg = cfg;

      var userEl = $('#acc-username');
      var nameEl = $('#acc-display-name');
      if (userEl) userEl.textContent = me.username || '—';
      if (nameEl) {
        nameEl.textContent = me.display_name || me.username || '—';
      }

      var disabled = me.password_change_disabled ||
        (cfg && cfg.password_change_disabled);
      var formEl = $('#acc-password-form');
      var hint = $('#acc-disabled-hint');
      if (formEl) formEl.hidden = !!disabled;
      if (hint) hint.hidden = !disabled;
    }).catch(function (e) {
      msg(e.message || '无法加载当前账户', 'bad');
    });
  }

  function submitPassword(oldPw, newPw, otc) {
    var body = { old_password: oldPw, new_password: newPw };
    if (otc) body.otc = otc;
    return fetch(PWD_API, {
      method: 'POST',
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    }).then(function (r) {
      return parseJsonRes(r).then(function (b) {
        return { status: r.status, body: b || {} };
      });
    });
  }

  function otcDeliveryHint(body) {
    if (body && body.otc_delivery === 'filesystem') {
      return '未配置 SMTP：验证码在中心机 /var/lib/authelia/notification.txt（SSH：tail -20 该文件），填入后再次点击「更新密码」。';
    }
    return '已向您的邮箱发送验证码，填写后再次点击「更新密码」。';
  }

  function onSubmit(e) {
    e.preventDefault();
    var oldPw = ($('#acc-old') && $('#acc-old').value) || '';
    var newPw = ($('#acc-new') && $('#acc-new').value) || '';
    var new2 = ($('#acc-new2') && $('#acc-new2').value) || '';
    var otc = ($('#acc-otc') && $('#acc-otc').value) || '';

    if (!oldPw || !newPw || !new2) {
      msg('请填写所有密码字段', 'bad');
      return;
    }
    if (newPw !== new2) {
      msg('两次新密码不一致', 'bad');
      return;
    }
    if (newPw.length < 8) {
      msg('新密码至少 8 位', 'bad');
      return;
    }
    if (window._accNeedOtc && !otc) {
      msg('请输入验证码', 'bad');
      return;
    }

    msg('正在提交…', '');

    submitPassword(oldPw, newPw, otc).then(function (res) {
      if (res.status === 202 && res.body && res.body.need_otc) {
        showOtc(true);
        msg(otcDeliveryHint(res.body), 'warn');
        return;
      }
      if (res.body && res.body.ok) {
        showOtc(false);
        if ($('#acc-password-form')) $('#acc-password-form').reset();
        msg('密码已更新', 'ok');
        return;
      }
      if (res.status === 401) {
        msg((res.body && res.body.error) || '当前密码不正确', 'bad');
        return;
      }
      msg((res.body && res.body.error) || '修改失败', 'bad');
    }).catch(function () {
      msg('请求失败', 'bad');
    });
  }

  function wireGotoTab() {
    document.querySelectorAll('[data-goto-tab]').forEach(function (el) {
      el.addEventListener('click', function (ev) {
        ev.preventDefault();
        var id = el.getAttribute('data-goto-tab');
        var btn = document.querySelector('.tabs button[data-tab="' + id + '"]');
        if (btn) btn.click();
      });
    });
  }

  function initPortalAccount() {
    wireGotoTab();
    var form = $('#acc-password-form');
    if (form) form.addEventListener('submit', onSubmit);
    document.querySelectorAll('.tabs button').forEach(function (btn) {
      btn.addEventListener('click', function () {
        if (btn.getAttribute('data-tab') === 'account') loadAccountPanel();
      });
    });
  }

  window.initPortalAccount = initPortalAccount;
})();
