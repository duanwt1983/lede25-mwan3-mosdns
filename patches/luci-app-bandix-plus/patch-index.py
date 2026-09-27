#!/usr/bin/env python3
"""Patch luci-app-bandix-plus index.js: device search, pagination, topo embed."""

import re
import sys
from pathlib import Path


def patch(src: str) -> str:
    # --- initState: pagination / search defaults ---
    src = src.replace(
        "\t\tthis.devicesFilterIface = '';\n",
        "\t\tthis.devicesFilterIface = '';\n"
        "\t\tthis.devicesSearchQuery = '';\n"
        "\t\tthis.devicesFilterLimit = 'all';\n"
        "\t\tthis.devicesPage = 1;\n"
        "\t\tvar _dps = localStorage.getItem('bplus_devices_page_size');\n"
        "\t\tthis.devicesPageSize = _dps ? Math.max(5, Math.min(200, parseInt(_dps, 10) || 20)) : 20;\n",
        1,
    )

    # --- helpers before getSortedDevices ---
    insert_before = "\tgetSortedDevices: function () {"
    helpers = """
\tdeviceMatchesSearch: function (d, q) {
\t\tif (!q) return true;
\t\tvar mac = String(d.mac || '').toLowerCase();
\t\tvar host = String(d.hostname || '').toLowerCase();
\t\tvar ips = ((d.ipv4 || []).concat(d.ipv6 || [])).join(' ').toLowerCase();
\t\treturn mac.indexOf(q) >= 0 || host.indexOf(q) >= 0 || ips.indexOf(q) >= 0;
\t},

\tgetFilteredDevices: function () {
\t\tvar self = this;
\t\tvar list = this.devices.slice();
\t\tvar iface = this.devicesFilterIface || '';
\t\tif (iface) {
\t\t\tlist = list.filter(function (d) {
\t\t\t\treturn deviceIfaceName(d) === iface;
\t\t\t});
\t\t}
\t\tvar q = String(this.devicesSearchQuery || '').trim().toLowerCase();
\t\tif (q) {
\t\t\tlist = list.filter(function (d) {
\t\t\t\treturn self.deviceMatchesSearch(d, q);
\t\t\t});
\t\t}
\t\tvar lim = this.devicesFilterLimit || 'all';
\t\tif (lim !== 'all') {
\t\t\tlist = list.filter(function (d) {
\t\t\t\tvar st = self.deviceScheduleRuleStatus(d);
\t\t\t\tvar limited = st.count > 0;
\t\t\t\treturn lim === 'limited' ? limited : !limited;
\t\t\t});
\t\t}
\t\treturn list;
\t},

\trenderDevicesPagination: function (total, totalPages, pageSize) {
\t\tif (!this.el.devicesPagination) return;
\t\tvar page = Math.max(1, asNum(this.devicesPage) || 1);
\t\tvar start = total ? ((page - 1) * pageSize + 1) : 0;
\t\tvar end = total ? Math.min(total, page * pageSize) : 0;
\t\tif (this.el.devicesPageInfo)
\t\t\tthis.el.devicesPageInfo.textContent = total
\t\t\t\t? (_('Showing %d–%d of %d').format(start, end, total))
\t\t\t\t: _('No devices');
\t\tif (this.el.devicesPagePrev)
\t\t\tthis.el.devicesPagePrev.disabled = page <= 1;
\t\tif (this.el.devicesPageNext)
\t\t\tthis.el.devicesPageNext.disabled = page >= totalPages;
\t\tif (this.el.devicesPageNum)
\t\t\tthis.el.devicesPageNum.textContent = String(page) + ' / ' + String(totalPages);
\t},

"""
    if insert_before not in src:
        raise SystemExit("getSortedDevices anchor missing")
    src = src.replace(insert_before, helpers + insert_before, 1)

    # --- getSortedDevices uses filtered list ---
    src = src.replace(
        "\t\tvar list = this.devices.slice();\n\t\tvar key = this.deviceSortKey;",
        "\t\tvar list = this.getFilteredDevices();\n\t\tvar key = this.deviceSortKey;",
        1,
    )

    # --- renderDevicesTable: pagination slice + count ---
    old_count_block = """\t\tif (this.el.devicesCount) {
\t\t\tthis.el.devicesCount.textContent = _('Online devices') + ': ' + String(online) + ' / ' + String(list.length);
\t\t}

\t\tif (!list.length) {
\t\t\tbody.appendChild(E('tr', {}, [ E('td', { 'colspan': '11', 'class': 'bplus-empty' }, [ _('No devices') ]) ]));
\t\t\treturn;
\t\t}

\t\tvar det = this.deviceDisplayMode === 'detailed';
\t\tfor (var i = 0; i < list.length; i++) {"""

    new_count_block = """\t\tvar total = list.length;
\t\tvar pageSize = Math.max(5, asNum(this.devicesPageSize) || 20);
\t\tvar totalPages = Math.max(1, Math.ceil(total / pageSize));
\t\tif (this.devicesPage > totalPages) this.devicesPage = totalPages;
\t\tif (this.devicesPage < 1) this.devicesPage = 1;
\t\tvar pageStart = (this.devicesPage - 1) * pageSize;
\t\tvar pageList = list.slice(pageStart, pageStart + pageSize);
\t\tthis.renderDevicesPagination(total, totalPages, pageSize);

\t\tif (this.el.devicesCount) {
\t\t\tthis.el.devicesCount.textContent = _('Online devices') + ': ' + String(online) + ' / ' + String(total);
\t\t}

\t\tif (!pageList.length) {
\t\t\tbody.appendChild(E('tr', {}, [ E('td', { 'colspan': '11', 'class': 'bplus-empty' }, [ _('No devices') ]) ]));
\t\t\treturn;
\t\t}

\t\tvar det = this.deviceDisplayMode === 'detailed';
\t\tfor (var i = 0; i < pageList.length; i++) {"""

    if old_count_block not in src:
        raise SystemExit("renderDevicesTable count block missing")
    src = src.replace(old_count_block, new_count_block, 1)

    src = src.replace(
        "\t\tfor (var i = 0; i < pageList.length; i++) {\n\t\t\tvar d = list[i];",
        "\t\tfor (var i = 0; i < pageList.length; i++) {\n\t\t\tvar d = pageList[i];",
        1,
    )

    # --- buildView: device toolbar elements ---
    src = src.replace(
        "\t\tthis.el.devicesCount = E('span', { 'class': 'meta-pill', 'id': 'bplus-devices-count' }, [ _('Online devices') + ': 0 / 0' ]);\n",
        "\t\tthis.el.devicesCount = E('span', { 'class': 'meta-pill', 'id': 'bplus-devices-count' }, [ _('Online devices') + ': 0 / 0' ]);\n"
        "\t\tthis.el.devicesSearchInput = E('input', {\n"
        "\t\t\t'class': 'cbi-input-text bplus-devices-search',\n"
        "\t\t\t'type': 'search',\n"
        "\t\t\t'placeholder': _('Search IP / MAC / hostname')\n"
        "\t\t});\n"
        "\t\tthis.el.devicesLimitSelect = E('select', { 'class': 'cbi-input-select' }, [\n"
        "\t\t\tE('option', { 'value': 'all' }, [ _('All limit states') ]),\n"
        "\t\t\tE('option', { 'value': 'limited' }, [ _('Limited') ]),\n"
        "\t\t\tE('option', { 'value': 'unlimited' }, [ _('Unlimited') ])\n"
        "\t\t]);\n"
        "\t\tthis.el.devicesPageSizeSelect = E('select', { 'class': 'cbi-input-select' }, [\n"
        "\t\t\tE('option', { 'value': '10' }, [ '10 / ' + _('page') ]),\n"
        "\t\t\tE('option', { 'value': '20' }, [ '20 / ' + _('page') ]),\n"
        "\t\t\tE('option', { 'value': '50' }, [ '50 / ' + _('page') ]),\n"
        "\t\t\tE('option', { 'value': '100' }, [ '100 / ' + _('page') ])\n"
        "\t\t]);\n"
        "\t\tthis.el.devicesPageSizeSelect.value = String(this.devicesPageSize || 20);\n"
        "\t\tthis.el.devicesPagePrev = E('button', { 'type': 'button', 'class': 'btn cbi-button cbi-button-neutral' }, [ '‹' ]);\n"
        "\t\tthis.el.devicesPageNext = E('button', { 'type': 'button', 'class': 'btn cbi-button cbi-button-neutral' }, [ '›' ]);\n"
        "\t\tthis.el.devicesPageNum = E('span', { 'class': 'bplus-page-num' }, [ '1 / 1' ]);\n"
        "\t\tthis.el.devicesPageInfo = E('span', { 'class': 'bplus-page-info meta-pill' }, [ '' ]);\n"
        "\t\tthis.el.devicesPagination = E('div', { 'class': 'bplus-devices-pagination' }, [\n"
        "\t\t\tthis.el.devicesPageInfo,\n"
        "\t\t\tthis.el.devicesPagePrev,\n"
        "\t\t\tthis.el.devicesPageNum,\n"
        "\t\t\tthis.el.devicesPageNext\n"
        "\t\t]);\n",
        1,
    )

    old_device_section = """\t\t\t\tE('section', { 'class': 'bplus-panel' }, [
\t\t\t\t\tE('div', { 'class': 'bplus-panel-head' }, [
\t\t\t\t\t\tE('h2', {}, [ _('Device List') ]),
\t\t\t\t\t\tthis.el.devicesCount
\t\t\t\t\t]),
\t\t\t\t\tE('div', { 'class': 'bplus-inline-form' }, [
\t\t\t\t\t\tE('label', {}, [ _('Iface'), this.el.devicesIfaceSelect ]),
\t\t\t\t\t\tE('label', {}, [ _('Period'), this.el.periodSelect ]),
\t\t\t\t\t\tE('label', {}, [ _('Display mode'), this.el.deviceModeSelect ])
\t\t\t\t\t]),
\t\t\t\t\tE('div', { 'class': 'table-wrapper' }, [ E('table', { 'class': 'table bplus-table bplus-table--devices' }, [ this.el.deviceHead, this.el.deviceBody ]) ])
\t\t\t\t]),"""

    new_device_section = """\t\t\t\tthis.el.deviceListSection = E('section', { 'class': 'bplus-panel' }, [
\t\t\t\t\tE('div', { 'class': 'bplus-panel-head' }, [
\t\t\t\t\t\tE('h2', {}, [ _('Device List') ]),
\t\t\t\t\t\tthis.el.devicesCount
\t\t\t\t\t]),
\t\t\t\t\tE('div', { 'class': 'bplus-inline-form bplus-device-toolbar' }, [
\t\t\t\t\t\tE('label', {}, [ _('Search'), this.el.devicesSearchInput ]),
\t\t\t\t\t\tE('label', {}, [ _('Limit'), this.el.devicesLimitSelect ]),
\t\t\t\t\t\tE('label', {}, [ _('Iface'), this.el.devicesIfaceSelect ]),
\t\t\t\t\t\tE('label', {}, [ _('Period'), this.el.periodSelect ]),
\t\t\t\t\t\tE('label', {}, [ _('Display mode'), this.el.deviceModeSelect ]),
\t\t\t\t\t\tE('label', {}, [ _('Per page'), this.el.devicesPageSizeSelect ])
\t\t\t\t\t]),
\t\t\t\t\tthis.el.devicesPagination,
\t\t\t\t\tE('div', { 'class': 'table-wrapper' }, [ E('table', { 'class': 'table bplus-table bplus-table--devices' }, [ this.el.deviceHead, this.el.deviceBody ]) ])
\t\t\t\t]),"""

    if old_device_section not in src:
        raise SystemExit("device list section missing")
    src = src.replace(old_device_section, new_device_section, 1)

    # reference deviceListSection in mainSection
    src = src.replace(
        "\t\t\t\t]),\n\n\t\t\t\tE('section', { 'class': 'bplus-panel bplus-usage-ranking-section' }",
        "\t\t\t\t]),\n\n\t\t\t\tthis.el.deviceListSection,\n\n\t\t\t\tE('section', { 'class': 'bplus-panel bplus-usage-ranking-section' }",
        1,
    )
    # remove duplicate - we replaced inline section with el.deviceListSection variable but left duplicate
    # The mainSection now has this.el.deviceListSection as separate statement - need to fix structure
    # Actually new_device_section assigns to this.el.deviceListSection but doesn't include in array - we add via second replace

    # --- bindEvents: search / pagination ---
    bind_anchor = "\t\tif (this.el.deviceModeSelect) {\n\t\t\tthis.el.deviceModeSelect.addEventListener('change', L.bind(function () {"
    bind_extra = """\t\tif (this.el.devicesSearchInput) {
\t\t\tthis.el.devicesSearchInput.addEventListener('input', L.bind(function () {
\t\t\t\tthis.devicesSearchQuery = this.el.devicesSearchInput.value || '';
\t\t\t\tthis.devicesPage = 1;
\t\t\t\tthis.renderDevicesTable();
\t\t\t}, this));
\t\t}

\t\tif (this.el.devicesLimitSelect) {
\t\t\tthis.el.devicesLimitSelect.addEventListener('change', L.bind(function () {
\t\t\t\tthis.devicesFilterLimit = this.el.devicesLimitSelect.value || 'all';
\t\t\t\tthis.devicesPage = 1;
\t\t\t\tthis.renderDevicesTable();
\t\t\t}, this));
\t\t}

\t\tif (this.el.devicesPageSizeSelect) {
\t\t\tthis.el.devicesPageSizeSelect.addEventListener('change', L.bind(function () {
\t\t\t\tthis.devicesPageSize = Math.max(5, asNum(this.el.devicesPageSizeSelect.value) || 20);
\t\t\t\tlocalStorage.setItem('bplus_devices_page_size', String(this.devicesPageSize));
\t\t\t\tthis.devicesPage = 1;
\t\t\t\tthis.renderDevicesTable();
\t\t\t}, this));
\t\t}

\t\tif (this.el.devicesPagePrev) {
\t\t\tthis.el.devicesPagePrev.addEventListener('click', L.bind(function (ev) {
\t\t\t\tev.preventDefault();
\t\t\t\tif (this.devicesPage > 1) {
\t\t\t\t\tthis.devicesPage--;
\t\t\t\t\tthis.renderDevicesTable();
\t\t\t\t}
\t\t\t}, this));
\t\t}

\t\tif (this.el.devicesPageNext) {
\t\t\tthis.el.devicesPageNext.addEventListener('click', L.bind(function (ev) {
\t\t\t\tev.preventDefault();
\t\t\t\tthis.devicesPage++;
\t\t\t\tthis.renderDevicesTable();
\t\t\t}, this));
\t\t}

"""
    if bind_anchor not in src:
        raise SystemExit("bindEvents anchor missing")
    src = src.replace(bind_anchor, bind_extra + bind_anchor, 1)

    # --- inline CSS for pagination toolbar ---
    css_anchor = "\t\t'.bplus-page .bplus-status-down-notice{padding:18px 16px;border-radius:12px;border:1px dashed var(--bplus-border,#d1d5db);background:var(--bplus-bg,#fff);text-align:center;color:#6b7280;}'"
    css_extra = (
        "\n\t\t'.bplus-device-toolbar .bplus-devices-search{min-width:12em;}'"
        "\n\t\t'.bplus-devices-pagination{display:flex;flex-wrap:wrap;align-items:center;gap:8px 12px;margin:0 0 10px;}'"
        "\n\t\t'.bplus-devices-pagination .bplus-page-num{font-variant-numeric:tabular-nums;min-width:4.5em;text-align:center;}'"
        "\n\t\t'.topo-bandix-devlist .bplus-panel{margin-top:12px;}'"
        "\n\t\t'.topo-bandix-devlist .bplus-page{max-width:100%;}'"
    )
    src = src.replace(css_anchor, css_anchor + css_extra, 1)

    # --- embed API before final return ---
    src = re.sub(
        r"\nreturn view\.extend\(\{",
        "\n\nvar __bplusEmbedPolls = [];\n\nvar BandixView = view.extend({",
        src,
        count=1,
    )

    embed_methods = """
\tbuildDeviceListElements: function (titleText) {
\t\tif (!this.el) this.el = {};
\t\tif (!this.el.devicesIfaceSelect) {
\t\t\tthis.el.devicesIfaceSelect = E('select', { 'class': 'cbi-input-select' }, [ E('option', { 'value': '' }, [ _('All interfaces') ]) ]);
\t\t\tthis.el.periodSelect = E('select', { 'class': 'cbi-input-select' }, [
\t\t\t\tE('option', { 'value': 'all' }, [ _('All') ]),
\t\t\t\tE('option', { 'value': 'today' }, [ _('Today') ]),
\t\t\t\tE('option', { 'value': 'week' }, [ _('This Week') ]),
\t\t\t\tE('option', { 'value': 'month' }, [ _('This Month') ]),
\t\t\t\tE('option', { 'value': 'year' }, [ _('This Year') ])
\t\t\t]);
\t\t\tthis.el.periodSelect.value = this.period || 'all';
\t\t\tthis.el.deviceModeSelect = E('select', { 'class': 'cbi-input-select' }, [
\t\t\t\tE('option', { 'value': 'simple' }, [ _('Simple Mode') ]),
\t\t\t\tE('option', { 'value': 'detailed' }, [ _('Detailed Mode') ])
\t\t\t]);
\t\t\tthis.el.deviceModeSelect.value = this.deviceDisplayMode;
\t\t\tthis.el.devicesCount = E('span', { 'class': 'meta-pill' }, [ _('Online devices') + ': 0 / 0' ]);
\t\t\tthis.el.devicesSearchInput = E('input', { 'class': 'cbi-input-text bplus-devices-search', 'type': 'search', 'placeholder': _('Search IP / MAC / hostname') });
\t\t\tthis.el.devicesLimitSelect = E('select', { 'class': 'cbi-input-select' }, [
\t\t\t\tE('option', { 'value': 'all' }, [ _('All limit states') ]),
\t\t\t\tE('option', { 'value': 'limited' }, [ _('Limited') ]),
\t\t\t\tE('option', { 'value': 'unlimited' }, [ _('Unlimited') ])
\t\t\t]);
\t\t\tthis.el.devicesPageSizeSelect = E('select', { 'class': 'cbi-input-select' }, [
\t\t\t\tE('option', { 'value': '10' }, [ '10 / ' + _('page') ]),
\t\t\t\tE('option', { 'value': '20' }, [ '20 / ' + _('page') ]),
\t\t\t\tE('option', { 'value': '50' }, [ '50 / ' + _('page') ]),
\t\t\t\tE('option', { 'value': '100' }, [ '100 / ' + _('page') ])
\t\t\t]);
\t\t\tthis.el.devicesPageSizeSelect.value = String(this.devicesPageSize || 20);
\t\t\tthis.el.devicesPagePrev = E('button', { 'type': 'button', 'class': 'btn cbi-button cbi-button-neutral' }, [ '‹' ]);
\t\t\tthis.el.devicesPageNext = E('button', { 'type': 'button', 'class': 'btn cbi-button cbi-button-neutral' }, [ '›' ]);
\t\t\tthis.el.devicesPageNum = E('span', { 'class': 'bplus-page-num' }, [ '1 / 1' ]);
\t\t\tthis.el.devicesPageInfo = E('span', { 'class': 'bplus-page-info meta-pill' }, [ '' ]);
\t\t\tthis.el.devicesPagination = E('div', { 'class': 'bplus-devices-pagination' }, [
\t\t\t\tthis.el.devicesPageInfo, this.el.devicesPagePrev, this.el.devicesPageNum, this.el.devicesPageNext
\t\t\t]);
\t\t\tthis.el.deviceHead = E('thead');
\t\t\tthis.el.deviceBody = E('tbody');
\t\t}
\t\tthis.el.deviceListSection = E('section', { 'class': 'bplus-panel bplus-panel--embed' }, [
\t\t\tE('div', { 'class': 'bplus-panel-head' }, [
\t\t\t\tE('h2', {}, [ titleText || _('Device List') ]),
\t\t\t\tthis.el.devicesCount
\t\t\t]),
\t\t\tE('div', { 'class': 'bplus-inline-form bplus-device-toolbar' }, [
\t\t\t\tE('label', {}, [ _('Search'), this.el.devicesSearchInput ]),
\t\t\t\tE('label', {}, [ _('Limit'), this.el.devicesLimitSelect ]),
\t\t\t\tE('label', {}, [ _('Iface'), this.el.devicesIfaceSelect ]),
\t\t\t\tE('label', {}, [ _('Period'), this.el.periodSelect ]),
\t\t\t\tE('label', {}, [ _('Display mode'), this.el.deviceModeSelect ]),
\t\t\t\tE('label', {}, [ _('Per page'), this.el.devicesPageSizeSelect ])
\t\t\t]),
\t\t\tthis.el.devicesPagination,
\t\t\tE('div', { 'class': 'table-wrapper' }, [
\t\t\t\tE('table', { 'class': 'table bplus-table bplus-table--devices' }, [ this.el.deviceHead, this.el.deviceBody ])
\t\t\t])
\t\t]);
\t\treturn this.el.deviceListSection;
\t},

\tensureEmbedModals: function (root) {
\t\tif (!this.el) this.el = {};
\t\tvar host = root || document.body;
\t\tif (!this.el.scheduleHubOverlay) {
\t\t\tthis.buildView();
\t\t\tthis.setRateUnitMode(this.rateUnitMode, false);
\t\t}
\t\tvar modals = [
\t\t\tthis.el.scheduleHubOverlay,
\t\t\tthis.el.scheduleRuleOverlay,
\t\t\tthis.el.scheduleDeleteConfirmOverlay,
\t\t\tthis.el.deviceDeleteConfirmOverlay
\t\t];
\t\tfor (var mi = 0; mi < modals.length; mi++) {
\t\t\tvar node = modals[mi];
\t\t\tif (node && node.parentNode !== host)
\t\t\t\thost.appendChild(node);
\t\t}
\t},

\tbindDeviceListControls: function () {
\t\tif (this._deviceListControlsBound) return;
\t\tthis._deviceListControlsBound = true;
\t\tthis.bindEvents();
\t},

\tmountDeviceListEmbed: function (container, opts) {
\t\topts = opts || {};
\t\tensureCss();
\t\tthis._embedMode = true;
\t\tthis._embedContainer = container;
\t\tif (!this.period) this.period = localStorage.getItem('bplus_period') || 'all';
\t\tif (!this.rateUnitMode) this.rateUnitMode = localStorage.getItem('bplus_rate_unit') === 'bit' ? 'bit' : 'byte';
\t\tsetRateUnitMode(this.rateUnitMode);
\t\tvar bdm = localStorage.getItem('bplus_device_display_mode');
\t\tthis.deviceDisplayMode = bdm === 'detailed' ? 'detailed' : 'simple';
\t\tthis.deviceSortKey = this.deviceSortKey || 'ipv4';
\t\tthis.deviceSortAsc = this.deviceSortAsc !== false;
\t\tthis.devices = this.devices || [];
\t\tthis.rate = this.rate || { schedules: [], ifaceLimits: [], guestDefaults: [], guestWhitelist: [] };
\t\tvar section = this.buildDeviceListElements(opts.title || _('Device List'));
\t\tdom.content(container, [ E('div', { 'class': 'bplus-page bplus-page--embed' }, [ section ]) ]);
\t\tthis.ensureEmbedModals(container);
\t\tthis.bindDeviceListControls();
\t\tvar self = this;
\t\treturn Promise.all([
\t\t\tthis.refreshRateData(false),
\t\t\tthis.refreshLive(false)
\t\t]).then(function () {
\t\t\tvar fn = L.bind(function () {
\t\t\t\treturn Promise.all([ self.refreshLive(false), self.refreshRateData(false) ]);
\t\t\t}, self);
\t\t\tpoll.add(fn, 2);
\t\t\tself._embedPollFn = fn;
\t\t\t__bplusEmbedPolls.push(self);
\t\t\treturn self;
\t\t});
\t},

\tunmountDeviceListEmbed: function () {
\t\tif (this._embedPollFn) {
\t\t\tpoll.remove(this._embedPollFn);
\t\t\tthis._embedPollFn = null;
\t\t}
\t\tvar idx = __bplusEmbedPolls.indexOf(this);
\t\tif (idx >= 0) __bplusEmbedPolls.splice(idx, 1);
\t\tif (this._embedContainer)
\t\t\tdom.content(this._embedContainer, []);
\t\tthis._embedContainer = null;
\t\tthis._embedMode = false;
\t},

"""

    src = src.replace(
        "\n\trender: function (load) {\n\t\tensureCss();",
        embed_methods + "\n\trender: function (load) {\n\t\tensureCss();",
        1,
    )

    # --- factory on returned view ---
    src = src.replace(
        "\t\treturn viewNode;\n\t}\n});\n",
        "\t\treturn viewNode;\n\t}\n});\n\n"
        "BandixView.createDeviceListEmbed = function (container, opts) {\n"
        "\tvar inst = Object.create(BandixView.prototype);\n"
        "\tinst.initState([]);\n"
        "\treturn inst.mountDeviceListEmbed(container, opts || {});\n"
        "};\n\n"
        "return BandixView;\n",
        1,
    )

    return src


def main() -> None:
    src_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("tmp-bandix-index.js")
    out_path = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(
        "files/www/luci-static/resources/view/bandix_plus/index.js"
    )
    text = src_path.read_text(encoding="utf-8")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(patch(text), encoding="utf-8")
    print(f"patched -> {out_path}")


if __name__ == "__main__":
    main()
