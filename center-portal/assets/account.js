(function () {
  'use strict';

  var ME_API = '/home/api/account/me';
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

  function loadAccountPanel() {
    msg('');
    showOtc(false);
    window._accNeedOtc = false;
    var form = $('#acc-password-form');
    if (form) form.reset();

    return fetch(ME_API, { credentials: 'same-origin', cache: 'no-store' })
      .then(function (r) { return r.json().then(function (b) { return { r: r, b: b }; }); })
      .then(function (x) {
        if (!x.r.ok || !x.b.ok) {
          throw new Error((x.b && x.b.error) || '未登录');
        }
        var nameEl = $('#acc-display-name');
        var userEl = $('#acc-username');
        if (nameEl) nameEl.textContent = x.b.display_name || x.b.username || '—';
        if (userEl) userEl.textContent = x.b.username || '—';
        var formEl = $('#acc-password-form');
        var hint = $('#acc-disabled-hint');
        if (formEl) formEl.hidden = !!x.b.password_change_disabled;
        if (hint) hint.hidden = !x.b.password_change_disabled;
      })
      .catch(function (e) {
        msg(e.message || '无法加载当前账户', 'bad');
      });
  }

  function showOtc(on) {
    var block = $('#acc-otc-block');
    if (block) block.hidden = !on;
    window._accNeedOtc = !!on;
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
      return r.json().then(function (b) { return { status: r.status, body: b }; });
    });
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
      msg('请输入邮箱验证码', 'bad');
      return;
    }

    msg('正在提交…', '');

    submitPassword(oldPw, newPw, otc).then(function (res) {
      if (res.status === 202 && res.body && res.body.need_otc) {
        showOtc(true);
        msg('已向您的邮箱发送验证码，填写后再次点击「更新密码」。', 'warn');
        return;
      }
      if (res.body && res.body.ok) {
        showOtc(false);
        if ($('#acc-password-form')) $('#acc-password-form').reset();
        msg('密码已更新', 'ok');
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
