'use strict';
'require baseclass';

const W = 800, H = 200;
const PAD = { l: 10, r: 90, t: 12, b: 28 };
const PAD_LAT = 52;
const COL_LAT = '#ea580c';

function svgEl(name, attrs) {
	const n = document.createElementNS('http://www.w3.org/2000/svg', name);
	if (attrs) {
		for (const k in attrs)
			n.setAttribute(k, attrs[k]);
	}
	return n;
}

function fmtBit(bps) {
	bps = Number(bps) || 0;
	if (bps < 1000)
		return bps.toFixed(0) + ' b';
	if (bps < 1e6)
		return (bps / 1e3).toFixed(bps >= 1e4 ? 0 : 1) + ' K';
	if (bps < 1e9)
		return (bps / 1e6).toFixed(bps >= 1e7 ? 0 : 1) + ' M';
	return (bps / 1e9).toFixed(2) + ' G';
}

function fmtBitFull(bps) {
	bps = Number(bps) || 0;
	if (!isFinite(bps) || bps < 0)
		bps = 0;
	if (bps < 1000)
		return bps.toFixed(0) + ' bps';
	if (bps < 1e6)
		return (bps / 1e3).toFixed(1) + ' Kbps';
	if (bps < 1e9)
		return (bps / 1e6).toFixed(2) + ' Mbps';
	return (bps / 1e9).toFixed(2) + ' Gbps';
}

function fmtWhen(ts) {
	ts = Number(ts) || 0;
	if (ts <= 0)
		return '--:--';
	const d = new Date(ts * 1000);
	const p = n => (n < 10 ? '0' : '') + n;
	return p(d.getHours()) + ':' + p(d.getMinutes()) + ':' + p(d.getSeconds());
}

function fmtWhenLong(ts) {
	ts = Number(ts) || 0;
	if (ts <= 0)
		return '--';
	const d = new Date(ts * 1000);
	const p = n => (n < 10 ? '0' : '') + n;
	return p(d.getMonth() + 1) + '-' + p(d.getDate()) + ' ' +
		p(d.getHours()) + ':' + p(d.getMinutes());
}

function niceMax(v) {
	v = Math.max(1, Number(v) || 1);
	const exp = Math.pow(10, Math.floor(Math.log10(v)));
	const n = v / exp;
	let m = 1;
	if (n > 5)
		m = 10;
	else if (n > 2)
		m = 5;
	else if (n > 1)
		m = 2;
	return m * exp;
}

function fmtMs(v) {
	v = Number(v) || 0;
	if (!isFinite(v) || v < 0)
		v = 0;
	if (v >= 100)
		return v.toFixed(0) + ' ms';
	if (v >= 10)
		return v.toFixed(1) + ' ms';
	return v.toFixed(1) + ' ms';
}

function seriesHasLat(series) {
	return (series || []).some(s => Array.isArray(s.lat) && s.lat.length);
}

function inner(hasLat) {
	const l = hasLat ? PAD_LAT : PAD.l;
	return {
		x: l,
		y: PAD.t,
		w: W - l - PAD.r,
		h: H - PAD.t - PAD.b
	};
}

function yOf(v, max, box) {
	return box.y + box.h - (Math.max(0, Number(v) || 0) / max) * box.h;
}

function xOf(i, n, box) {
	if (n <= 1)
		return box.x;
	return box.x + (i / (n - 1)) * box.w;
}

function polyPoints(arr, max, box) {
	const n = arr.length;
	return arr.map((v, i) => xOf(i, n, box).toFixed(1) + ',' + yOf(v, max, box).toFixed(1)).join(' ');
}

function bindHover(wrap, svg, box) {
	const tip = wrap.querySelector('.ratechart-tip');
	const cursor = wrap.querySelector('.ratechart-cursor');
	const hit = wrap.querySelector('.ratechart-hit');
	if (!tip || !cursor || !hit)
		return;
	const hide = function() {
		tip.style.display = 'none';
		cursor.setAttribute('opacity', '0');
		wrap._hovering = false;
	};
	hit.addEventListener('mouseleave', hide);
	hit.addEventListener('mousemove', function(ev) {
		const spec = wrap._spec;
		if (!spec || !spec.t || spec.t.length < 1)
			return;
		const rec = svg.getBoundingClientRect();
		if (rec.width <= 0)
			return;
		const sx = (ev.clientX - rec.left) * (W / rec.width);
		const box = inner(seriesHasLat(spec.series));
		const n = spec.t.length;
		let i = Math.round(((sx - box.x) / box.w) * (n - 1));
		if (i < 0)
			i = 0;
		if (i > n - 1)
			i = n - 1;
		wrap._hovering = true;
		cursor.setAttribute('x1', xOf(i, n, box).toFixed(1));
		cursor.setAttribute('x2', xOf(i, n, box).toFixed(1));
		cursor.setAttribute('opacity', '1');
		const span = spec.t[n - 1] - spec.t[0];
		const when = span >= 12 * 3600 ? fmtWhenLong(spec.t[i]) : fmtWhen(spec.t[i]);
		const lines = [when];
		(spec.series || []).forEach(s => {
			const lab = s.label ? s.label + ' ' : '';
			lines.push(lab + '下行 ' + fmtBitFull(s.rx && s.rx[i]));
			lines.push(lab + '上行 ' + fmtBitFull(s.tx && s.tx[i]));
			if (Array.isArray(s.lat) && s.lat.length)
				lines.push(lab + '延时 ' + fmtMs(s.lat[i]));
		});
		tip.textContent = lines.join('\n');
		tip.style.display = 'block';
		const left = ev.clientX - rec.left + 12;
		const top = ev.clientY - rec.top + 8;
		tip.style.left = Math.min(left, rec.width - 180) + 'px';
		tip.style.top = Math.min(top, rec.height - 88) + 'px';
	});
}

function ensure(wrap) {
	if (wrap._ready)
		return wrap;
	wrap.classList.add('ratechart-wrap');
	const svg = svgEl('svg', {
		viewBox: '0 0 ' + W + ' ' + H,
		class: 'ratechart',
		preserveAspectRatio: 'none'
	});
	svg.style.width = '100%';
	svg.style.height = H + 'px';
	svg.style.display = 'block';
	const gGrid = svgEl('g', { class: 'rc-grid' });
	const gPlot = svgEl('g', { class: 'rc-plot' });
	const gAxis = svgEl('g', { class: 'rc-axis' });
	const cursor = svgEl('line', {
		class: 'ratechart-cursor',
		y1: String(PAD.t),
		y2: String(H - PAD.b),
		stroke: 'rgba(30,41,59,.55)',
		'stroke-width': '1',
		opacity: '0'
	});
	const box = inner();
	const hit = svgEl('rect', {
		class: 'ratechart-hit',
		x: String(box.x),
		y: String(box.y),
		width: String(box.w),
		height: String(box.h),
		fill: 'transparent'
	});
	svg.appendChild(gGrid);
	svg.appendChild(gPlot);
	svg.appendChild(gAxis);
	svg.appendChild(cursor);
	svg.appendChild(hit);
	const tip = document.createElement('div');
	tip.className = 'ratechart-tip';
	wrap.appendChild(svg);
	wrap.appendChild(tip);
	wrap._svg = svg;
	wrap._grid = gGrid;
	wrap._plot = gPlot;
	wrap._axis = gAxis;
	bindHover(wrap, svg, box);
	wrap._ready = true;
	return wrap;
}

function draw(wrap, spec) {
	ensure(wrap);
	wrap._spec = spec || { t: [], series: [] };
	const t = wrap._spec.t || [];
	const series = wrap._spec.series || [];
	const hasLat = seriesHasLat(series);
	const box = inner(hasLat);
	const n = t.length;
	let rawMax = 1;
	let latRaw = 1;
	series.forEach(s => {
		(s.rx || []).forEach(v => { if (v > rawMax) rawMax = v; });
		(s.tx || []).forEach(v => { if (v > rawMax) rawMax = v; });
		(s.lat || []).forEach(v => { if (v > latRaw) latRaw = v; });
	});
	const max = niceMax(rawMax);
	const latMax = hasLat ? niceMax(Math.max(10, latRaw)) : 1;
	const grid = wrap._grid;
	const plot = wrap._plot;
	const axis = wrap._axis;
	while (grid.firstChild)
		grid.removeChild(grid.firstChild);
	while (plot.firstChild)
		plot.removeChild(plot.firstChild);
	while (axis.firstChild)
		axis.removeChild(axis.firstChild);

	const hit = wrap.querySelector('.ratechart-hit');
	if (hit) {
		hit.setAttribute('x', String(box.x));
		hit.setAttribute('y', String(box.y));
		hit.setAttribute('width', String(box.w));
		hit.setAttribute('height', String(box.h));
	}
	const cursor = wrap.querySelector('.ratechart-cursor');
	if (cursor) {
		cursor.setAttribute('y1', String(box.y));
		cursor.setAttribute('y2', String(box.y + box.h));
	}

	const bg = svgEl('rect', {
		x: String(box.x), y: String(box.y),
		width: String(box.w), height: String(box.h),
		fill: 'rgba(127,127,127,.06)', rx: '4'
	});
	grid.appendChild(bg);

	for (let k = 0; k <= 4; k++) {
		const frac = k / 4;
		const y = box.y + box.h * (1 - frac);
		const line = svgEl('line', {
			x1: String(box.x), x2: String(box.x + box.w),
			y1: y.toFixed(1), y2: y.toFixed(1),
			stroke: 'rgba(127,127,127,.22)',
			'stroke-width': '1'
		});
		grid.appendChild(line);
		const lab = svgEl('text', {
			x: String(box.x + box.w + 8),
			y: String(y + 3),
			'text-anchor': 'start',
			'font-size': '11',
			fill: 'currentColor',
			opacity: '.72'
		});
		lab.textContent = fmtBit(max * frac);
		axis.appendChild(lab);
		if (hasLat) {
			const ll = svgEl('text', {
				x: String(box.x - 6),
				y: String(y + 3),
				'text-anchor': 'end',
				'font-size': '11',
				fill: COL_LAT,
				opacity: '.85'
			});
			ll.textContent = fmtMs(latMax * frac);
			axis.appendChild(ll);
		}
	}

	const span = n >= 2 ? (t[n - 1] - t[0]) : 0;
	const tickN = 5;
	for (let k = 0; k < tickN; k++) {
		const frac = tickN === 1 ? 0 : k / (tickN - 1);
		const i = n <= 1 ? 0 : Math.round(frac * (n - 1));
		const x = n <= 1 ? box.x : xOf(i, n, box);
		const lab = svgEl('text', {
			x: x.toFixed(1),
			y: String(H - 8),
			'text-anchor': k === 0 ? 'start' : (k === tickN - 1 ? 'end' : 'middle'),
			'font-size': '11',
			fill: 'currentColor',
			opacity: '.72'
		});
		lab.textContent = n ? (span >= 12 * 3600 ? fmtWhenLong(t[i]) : fmtWhen(t[i])) : '';
		axis.appendChild(lab);
	}

	if (n >= 2) {
		series.forEach(s => {
			const rx = (s.rx && s.rx.length) ? s.rx : [0, 0];
			const tx = (s.tx && s.tx.length) ? s.tx : [0, 0];
			const down = svgEl('polyline', {
				fill: 'none',
				stroke: s.color || '#16a34a',
				'stroke-width': '2.1',
				points: polyPoints(rx, max, box)
			});
			const up = svgEl('polyline', {
				fill: 'none',
				stroke: s.colorTx || s.color || '#2563eb',
				'stroke-width': '2.1',
				'stroke-dasharray': '6 4',
				points: polyPoints(tx, max, box)
			});
			plot.appendChild(down);
			plot.appendChild(up);
			if (Array.isArray(s.lat) && s.lat.length >= 2) {
				const latLine = svgEl('polyline', {
					fill: 'none',
					stroke: s.colorLat || COL_LAT,
					'stroke-width': '1.7',
					'stroke-dasharray': '2 3',
					points: polyPoints(s.lat, latMax, box)
				});
				plot.appendChild(latLine);
			}
			if (series.length !== 1)
				return;
			const lastRx = Number(rx[rx.length - 1]) || 0;
			const lastTx = Number(tx[tx.length - 1]) || 0;
			let yRx = yOf(lastRx, max, box);
			let yTx = yOf(lastTx, max, box);
			if (Math.abs(yRx - yTx) < 14) {
				if (lastRx >= lastTx)
					yTx = Math.min(box.y + box.h, yRx + 14);
				else
					yRx = Math.min(box.y + box.h, yTx + 14);
			}
			const lx = box.x + box.w + 8;
			const downLab = svgEl('text', {
				x: String(lx), y: String(yRx + 3),
				'text-anchor': 'start',
				'font-size': '11',
				'font-weight': '700',
				fill: s.color || '#16a34a',
				stroke: 'var(--background-color-high, #fff)',
				'stroke-width': '3',
				'paint-order': 'stroke'
			});
			downLab.textContent = fmtBitFull(lastRx);
			const upLab = svgEl('text', {
				x: String(lx), y: String(yTx + 3),
				'text-anchor': 'start',
				'font-size': '11',
				'font-weight': '700',
				fill: s.colorTx || s.color || '#2563eb',
				stroke: 'var(--background-color-high, #fff)',
				'stroke-width': '3',
				'paint-order': 'stroke'
			});
			upLab.textContent = fmtBitFull(lastTx);
			axis.appendChild(downLab);
			axis.appendChild(upLab);
			if (Array.isArray(s.lat) && s.lat.length) {
				const lastLat = Number(s.lat[s.lat.length - 1]) || 0;
				const latLab = svgEl('text', {
					x: String(box.x - 6),
					y: String(yOf(lastLat, latMax, box) + 3),
					'text-anchor': 'end',
					'font-size': '11',
					'font-weight': '700',
					fill: s.colorLat || COL_LAT,
					stroke: 'var(--background-color-high, #fff)',
					'stroke-width': '3',
					'paint-order': 'stroke'
				});
				latLab.textContent = fmtMs(lastLat);
				axis.appendChild(latLab);
			}
		});
	}
}

return baseclass.extend({
	COLORS: ['#16a34a', '#2563eb', '#ea580c', '#7c3aed', '#db2777', '#0891b2'],

	renderInto(el, spec) {
		if (!el)
			return el;
		draw(el, spec);
		return el;
	},

	spark(rxHist, txHist, times) {
		const wrap = document.createElement('div');
		draw(wrap, {
			t: times && times.length ? times : [],
			series: [{
				rx: rxHist && rxHist.length ? rxHist : [0, 0],
				tx: txHist && txHist.length ? txHist : [0, 0],
				color: '#16a34a',
				colorTx: '#2563eb'
			}]
		});
		return wrap;
	},

	combo(series, times) {
		const wrap = document.createElement('div');
		draw(wrap, { t: times && times.length ? times : [], series: series || [] });
		return wrap;
	}
});
