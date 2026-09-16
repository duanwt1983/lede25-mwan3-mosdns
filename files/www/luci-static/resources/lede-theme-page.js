'use strict';
'require baseclass';

const CARD_BG = 'var(--cbi-section-bg, var(--background-color-high, #fff))';
const TEXT = 'var(--text-color-high, inherit)';
const BORDER = 'var(--border-color-medium, rgba(127,127,127,.18))';
const MUTED = 'var(--muted-color, rgba(127,127,127,.75))';

const BASE_LIGHT = [
	'.lede-themed-page { width: 100%; min-width: 0; box-sizing: border-box; color: inherit; }',
	'.lede-themed-page .lede-page-card {',
	'  background: ' + CARD_BG + ';',
	'  border: 1px solid rgba(0,0,0,0.08);',
	'  border-radius: 8px;',
	'  box-shadow: 0 2px 6px rgba(0,0,0,0.03);',
	'  color: inherit;',
	'}',
	'.lede-themed-page .lede-page-panel {',
	'  background: ' + CARD_BG + ';',
	'  border: 1px solid rgba(0,0,0,0.08);',
	'  border-radius: 8px;',
	'  padding: 1rem 1.1rem;',
	'  box-shadow: 0 2px 6px rgba(0,0,0,0.03);',
	'  color: inherit;',
	'}',
	'.lede-themed-page .cbi-section {',
	'  background: transparent;',
	'  border: none;',
	'  box-shadow: none;',
	'  padding: 0;',
	'  margin: 0 0 1rem;',
	'}'
].join('\n');

const BASE_DARK = [
	'.lede-themed-page .lede-page-card,',
	'.lede-themed-page .lede-page-panel {',
	'  background: rgba(255,255,255,0.03);',
	'  border-color: rgba(255,255,255,0.08);',
	'  box-shadow: none;',
	'}'
].join('\n');

function injectStyles(id, lightRules, darkRules) {
	if (document.getElementById(id))
		return;
	let css = lightRules || '';
	if (darkRules)
		css += '\n@media (prefers-color-scheme: dark) {\n' + darkRules + '\n}';
	document.head.appendChild(E('style', { id: id, 'data-lede-theme-page': '1' }, css));
}

function injectBase() {
	injectStyles('lede-theme-page-base', BASE_LIGHT, BASE_DARK);
}

function wrapCbiMap(children, extraClass) {
	injectBase();
	const kids = [];
	if (Array.isArray(children))
		kids.push.apply(kids, children);
	else if (children)
		kids.push(children);
	const cls = 'cbi-map lede-themed-page' + (extraClass ? (' ' + extraClass) : '');
	return E('div', { 'class': cls }, kids);
}

function wrapSection(children, extraClass) {
	const cls = 'cbi-section' + (extraClass ? (' ' + extraClass) : '');
	return E('div', { 'class': cls }, children);
}

function enhanceMapNode(mapNode, extraClass) {
	injectBase();
	if (!mapNode)
		return mapNode;
	if (mapNode.classList) {
		mapNode.classList.add('lede-themed-page');
		if (extraClass)
			extraClass.split(/\s+/).filter(Boolean).forEach(c => mapNode.classList.add(c));
		return mapNode;
	}
	return wrapCbiMap(mapNode, extraClass);
}

return baseclass.extend({
	CARD_BG: CARD_BG,
	TEXT: TEXT,
	BORDER: BORDER,
	MUTED: MUTED,
	injectStyles: injectStyles,
	injectBase: injectBase,
	wrapCbiMap: wrapCbiMap,
	wrapSection: wrapSection,
	enhanceMapNode: enhanceMapNode
});
