/* TSLA Swing Trader - frontend (fase 1)
   Læser data/tsla.json og data/tsla-history.json og tegner dashboardet. */
(function () {
  'use strict';

  const nf2 = new Intl.NumberFormat('da-DK', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const nf1 = new Intl.NumberFormat('da-DK', { minimumFractionDigits: 1, maximumFractionDigits: 1 });
  const nf0 = new Intl.NumberFormat('da-DK', { maximumFractionDigits: 0 });
  const dtf = new Intl.DateTimeFormat('da-DK', { dateStyle: 'medium', timeStyle: 'short' });
  const df = new Intl.DateTimeFormat('da-DK', { dateStyle: 'medium' });

  const $ = (id) => document.getElementById(id);
  const usd = (v) => (v == null ? '-' : '$' + nf2.format(v));
  const pct = (v) => (v == null ? '-' : (v > 0 ? '+' : '') + nf1.format(v) + '%');
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const cssVar = (name) => getComputedStyle(document.documentElement).getPropertyValue(name).trim();

  const TREND_TXT = { positive: 'Positiv', neutral: 'Neutral', negative: 'Negativ', unknown: 'Ukendt' };
  const TREND_CLS = { positive: 'up', negative: 'down' };

  async function getJson(path) {
    // Cache-busting: GitHub Pages cacher filer i op til 10 minutter
    const res = await fetch(path + '?v=' + Date.now(), { cache: 'no-store' });
    if (!res.ok) throw new Error(path + ': HTTP ' + res.status);
    return res.json();
  }

  function renderHeader(d) {
    const q = d.quote;
    $('price').textContent = usd(q.price);
    const ch = $('change');
    ch.textContent = (q.change > 0 ? '+' : '') + nf2.format(q.change) + ' (' + pct(q.changePct) + ')';
    ch.className = 'chg ' + (q.change >= 0 ? 'up' : 'down');

    const gen = new Date(d.generatedAt);
    const bar = df.format(new Date(d.lastBar.date + 'T12:00:00'));
    const state = d.lastBar.complete ? 'afsluttet' : 'intradag, ikke afsluttet';
    $('updated').textContent = 'Opdateret ' + dtf.format(gen) + '. Seneste handelsdag ' + bar + ' (' + state + ').';

    const ageH = (Date.now() - gen.getTime()) / 36e5;
    if (ageH > 72) showWarnings(['Data er mere end 3 døgn gamle. Tjek at opdateringsjobbet på serveren kører.']);
  }

  function renderTrend(d) {
    const t = d.trend;
    const items = [['Kort trend', t.short, '20 EMA'], ['Mellem trend', t.medium, '50 SMA'], ['Lang trend', t.long, '200 SMA']];
    $('trend').innerHTML = items.map(([label, v, basis]) =>
      '<div><div class="t-label">' + label + ' <span class="muted">(' + basis + ')</span></div>' +
      '<div class="t-val ' + (TREND_CLS[v] || '') + '">' + (TREND_TXT[v] || v) + '</div></div>').join('');

    const fmtVal = (s) => {
      if (s.value == null) return '';
      if (s.key === 'rsi') return nf1.format(s.value);
      if (s.key === 'volume') return nf2.format(s.value) + 'x';
      if (s.key === 'volatility') return nf2.format(s.value) + '%';
      if (s.key === 'macd') return nf2.format(s.value);
      return usd(s.value);
    };
    $('signals').innerHTML = d.signals.map((s) =>
      '<li><button class="sig-row" type="button" aria-expanded="false">' +
      '<span class="sig-dot s-' + esc(s.status) + '" title="' + esc(s.status) + '"></span>' +
      '<span class="sig-label">' + esc(s.label) + '</span>' +
      '<span class="sig-reason">' + esc(s.reason) + '</span>' +
      '<span class="sig-val">' + esc(fmtVal(s)) + '</span></button>' +
      '<div class="sig-rule">Regel: ' + esc(s.rule) + '</div></li>').join('');

    $('signals').querySelectorAll('.sig-row').forEach((btn) => {
      btn.addEventListener('click', () => {
        const li = btn.parentElement;
        li.classList.toggle('open');
        btn.setAttribute('aria-expanded', li.classList.contains('open'));
      });
    });
  }

  function renderKeyFigures(d) {
    const i = d.indicators;
    const rows = [
      ['20 EMA', usd(i.ema20), pct(i.distEma20) + ' fra kurs'],
      ['50 SMA', usd(i.sma50), pct(i.distSma50) + ' fra kurs'],
      ['200 SMA', usd(i.sma200), pct(i.distSma200) + ' fra kurs'],
      ['RSI 14', nf1.format(i.rsi14), ''],
      ['MACD / signal', nf2.format(i.macd) + ' / ' + nf2.format(i.macdSignal), 'Histogram ' + nf2.format(i.macdHist)],
      ['ATR 14', usd(i.atr14), nf2.format(i.atrPct) + '% af kurs'],
      ['Volumen i dag', nf0.format(d.lastBar.volume), nf2.format(i.volumeRatio) + 'x 20d gns.'],
      ['Gns. volumen 20d', nf0.format(i.avgVolume20), 'Forrige 20 dage'],
      ['20d high / low', usd(i.high20) + ' / ' + usd(i.low20), ''],
      ['52u high', usd(i.high52w), pct(i.distHigh52w) + ' fra kurs'],
      ['52u low', usd(i.low52w), pct(i.distLow52w) + ' fra kurs'],
      ['ATR percentil 1 år', nf0.format(i.atrPctRank), '0 = laveste, 100 = højeste'],
    ];
    $('keyfigures').innerHTML = rows.map(([k, v, note]) =>
      '<div><div class="k">' + esc(k) + '</div><div class="v">' + esc(v) + '</div>' +
      (note ? '<div class="k">' + esc(note) + '</div>' : '') + '</div>').join('');
  }

  function showWarnings(list) {
    if (!list || !list.length) return;
    const box = $('warnings');
    box.hidden = false;
    box.innerHTML += list.map((w) => '<div>' + esc(w) + '</div>').join('');
  }



  // ---------- Setup (fase 3) ----------
  function renderSetup(s) {
    const box = $('setup-status');
    if (!s || s.status === 'na' || s.status === 'pending') {
      $('setup-label').textContent = s && s.reason ? 'Ikke beregnet: ' + s.reason : 'Ikke beregnet endnu';
      return;
    }
    box.className = 'status status-' + s.status;
    $('setup-label').textContent = s.label;

    const lv = (label, val, pc) => '<div><dt>' + label + '</dt><dd>' + val + (pc != null ? '<span class="pc">' + pct(pc) + '</span>' : '') + '</dd></div>';
    $('setup-levels').innerHTML =
      lv('Entry', usd(s.entryLow) + ' - ' + usd(s.entryHigh)) +
      lv('Stop', usd(s.stop), s.riskPct) +
      lv('Target 1', usd(s.target1), s.target1Pct) +
      lv('Target 2', usd(s.target2), s.target2Pct) +
      lv('Risk/reward', nf1.format(s.riskReward1) + ' / ' + nf1.format(s.riskReward2)) +
      lv('Horisont', s.horizon.low + '-' + s.horizon.high + ' dage');

    $('setup-criteria').innerHTML = s.criteria.map((c) => {
      const cls = c.pass ? 'ok' : c.hardFail ? 'hard' : 'no';
      const ic = c.pass ? '✓' : '✗';
      return '<li><span class="ic ' + cls + '">' + ic + '</span><span>' + esc(c.label) + '<span class="d">' + esc(c.detail) + '</span></span></li>';
    }).join('');

    $('setup-event').textContent = 'Event risk: ' + s.eventRisk.note +
      ' Status: grøn kræver at alle krav er opfyldt. Rød hvis et krav er langt fra. Ellers gul.';

    const w = s.why;
    $('setup-why').innerHTML = [['Entry', w.entry], ['Stop', w.stop], ['Target 1', w.target1], ['Target 2', w.target2],
      ['Horisont', s.horizon.source + '.']].map(([k, v]) => '<li><b>' + k + '</b> ' + esc(v) + '</li>').join('');
    $('setup-invalid').innerHTML = s.invalidation.map((v) => '<li>' + esc(v) + '</li>').join('');

    const t = s.historicalTest;
    if (t) {
      $('setup-test').textContent = 'Historisk test på ' + t.matches + ' lignende setups: Target 1 først i ' + t.target1First +
        ', stop først i ' + t.stopFirst + ', ingen af dem i ' + t.neither + '. Target 2 nået i ' + t.target2 +
        '. Gennemsnit ' + nf2.format(t.avgR) + 'R pr. trade. ' + t.rule;
    }
  }

  // ---------- Historiske matches (fase 2) ----------
  const pctCls = (v) => (v > 0 ? 'up' : v < 0 ? 'down' : '');
  const pctCell = (v) => '<td class="' + pctCls(v) + '">' + pct(v) + '</td>';
  const ppCell = (v) => '<td class="' + pctCls(v) + '">' + (v > 0 ? '+' : '') + nf1.format(v) + ' pp</td>';

  function renderHistorical(h) {
    if (!h || h.status !== 'ok') {
      $('hist-sub').textContent = h && h.reason ? 'Ikke beregnet: ' + h.reason : 'Ikke beregnet endnu.';
      return;
    }
    const from = df.format(new Date(h.searchFrom + 'T12:00:00'));
    $('hist-sub').innerHTML = '<b>' + h.similarSetups + ' lignende dage</b> fundet blandt ' + nf0.format(h.candidates) +
      ' handelsdage siden ' + esc(from) + '. Match-kvalitet: <b>' + esc(h.quality) + '</b> (median afstand ' + nf2.format(h.medianDistance) + ').';

    $('hist-table').querySelector('tbody').innerHTML = h.horizons.map((x) =>
      '<tr><td>' + x.days + ' dage</td>' +
      '<td>' + nf0.format(x.matches.pctPositive) + '%</td>' +
      '<td class="muted">' + nf0.format(x.baseline.pctPositive) + '%</td>' +
      ppCell(x.edgePositive) +
      pctCell(x.matches.median) +
      '<td class="muted">' + pct(x.matches.p25) + ' til ' + pct(x.matches.p75) + '</td></tr>').join('');

    $('hist-exc').innerHTML = h.excursions.map((e) =>
      '<div><div class="k">Inden for ' + e.days + ' dage (median)</div>' +
      '<div class="v"><span class="up">' + pct(e.maxUpMedian) + '</span> / <span class="down">' + pct(e.maxDownMedian) + '</span></div>' +
      '<div class="k">Max op / max ned. Værste 25%: ' + pct(e.maxDownP25) + '</div></div>').join('');

    const fmtF = (f, v) => (f.unit === '%' ? pct(v) : f.unit === 'x' ? nf2.format(v) + 'x' : nf1.format(v));
    $('hist-features').querySelector('tbody').innerHTML = h.features.map((f) =>
      '<tr><td>' + esc(f.label) + '</td><td>' + fmtF(f, f.current) + '</td><td>' + fmtF(f, f.matchMedian) + '</td><td>' + nf0.format(f.percentile) + '</td></tr>').join('');

    $('hist-matches').querySelector('tbody').innerHTML = h.matches.slice().reverse().map((m) =>
      '<tr><td>' + esc(m.date) + '</td><td>' + usd(m.close) + '</td><td>' + nf2.format(m.distance) + '</td>' +
      pctCell(m.returns.d2) + pctCell(m.returns.d5) + pctCell(m.returns.d10) + pctCell(m.returns.d20) +
      pctCell(m.maxUp.d20) + pctCell(m.maxDown.d20) + '</tr>').join('');

    $('hist-method').textContent = 'Metode: ' + h.method + '. Afstand måles i standardafvigelser. ' + h.qualityRule +
      ' Matches ligger mindst ' + h.minGapDays + ' handelsdage fra hinanden. "Alle dage" er udviklingen efter samtlige dage i søgevinduet. ' +
      'Matchenes perioder overlapper og er ikke uafhængige, så små forskelle fra "Alle dage" kan være tilfældige.';

    renderFan(h);
  }

  function renderFan(h) {
    const W = 560, H = 260, L = 40, R = 12, T = 10, B = 26;
    const b = h.bands, t0 = b[0].t, t1 = b[b.length - 1].t;
    const ys = b.flatMap((x) => [x.p25, x.p75]).concat(h.currentPath);
    let yMin = Math.min(...ys), yMax = Math.max(...ys);
    const pad = (yMax - yMin) * 0.08; yMin -= pad; yMax += pad;
    const X = (t) => L + (t - t0) / (t1 - t0) * (W - L - R);
    const Y = (v) => T + (yMax - v) / (yMax - yMin) * (H - T - B);
    const line = (pts) => pts.map((p, i) => (i ? 'L' : 'M') + X(p[0]).toFixed(1) + ',' + Y(p[1]).toFixed(1)).join('');

    const band = line(b.map((x) => [x.t, x.p75])) + b.slice().reverse().map((x) => 'L' + X(x.t).toFixed(1) + ',' + Y(x.p25).toFixed(1)).join('') + 'Z';
    const med = line(b.map((x) => [x.t, x.p50]));
    const cur = line(h.currentPath.map((v, i) => [i - h.pathBack, v]));

    const step = (yMax - yMin) > 30 ? 10 : 5;
    let grid = '';
    for (let v = Math.ceil(yMin / step) * step; v <= yMax; v += step) {
      grid += '<line x1="' + L + '" x2="' + (W - R) + '" y1="' + Y(v) + '" y2="' + Y(v) + '" stroke="var(--border)" stroke-width="1"/>' +
        '<text x="' + (L - 6) + '" y="' + (Y(v) + 4) + '" text-anchor="end">' + v + '</text>';
    }
    let xt = '';
    [-10, -5, 0, 5, 10, 15, 20].filter((t) => t >= t0 && t <= t1).forEach((t) => {
      xt += '<text x="' + X(t) + '" y="' + (H - 8) + '" text-anchor="middle">' + (t > 0 ? '+' + t : t) + '</text>';
    });

    $('hist-fan').innerHTML = '<svg viewBox="0 0 ' + W + ' ' + H + '" role="img" aria-label="Kursforløb for historiske matches">' + grid +
      '<line x1="' + X(0) + '" x2="' + X(0) + '" y1="' + T + '" y2="' + (H - B) + '" stroke="var(--muted)" stroke-dasharray="3 3"/>' +
      '<path d="' + band + '" fill="var(--band)" stroke="none"/>' +
      '<path d="' + med + '" fill="none" stroke="var(--accent)" stroke-width="2"/>' +
      '<path d="' + cur + '" fill="none" stroke="var(--ema20)" stroke-width="2.5"/>' + xt +
      '<text x="' + (W - R) + '" y="' + (H - 8) + '" text-anchor="end" opacity="0">.</text></svg>';
  }

  // ---------- Grafer ----------
  function renderCharts(hist, setup) {
    const LC = window.LightweightCharts;
    if (!LC) throw new Error('Graf-biblioteket kunne ikke indlæses');

    const col = hist.columns;
    const idx = Object.fromEntries(col.map((c, i) => [c, i]));
    const rows = hist.rows;
    const n = rows.length;

    const text = cssVar('--muted'), border = cssVar('--border'), surface = cssVar('--surface');
    const green = cssVar('--green'), red = cssVar('--red');
    const base = {
      autoSize: true,
      layout: { background: { type: 'solid', color: surface }, textColor: text, attributionLogo: true },
      grid: { vertLines: { color: border }, horzLines: { color: border } },
      rightPriceScale: { borderColor: border, minimumWidth: 70 },
      timeScale: { borderColor: border },
      crosshair: { mode: 0 },
      localization: { locale: 'da-DK' },
    };

    // Linjeserie med whitespace for manglende værdier, så alle grafer har samme antal punkter
    const line = (key) => rows.map((r) => (r[idx[key]] == null ? { time: r[0] } : { time: r[0], value: r[idx[key]] }));

    const main = LC.createChart($('chart-price'), base);
    const candles = main.addCandlestickSeries({ upColor: green, downColor: red, wickUpColor: green, wickDownColor: red, borderVisible: false });
    candles.setData(rows.map((r) => ({ time: r[0], open: r[idx.open], high: r[idx.high], low: r[idx.low], close: r[idx.close] })));
    if (setup && setup.entryLow) {
      const pl = (price, color, title, style) => candles.createPriceLine({ price, color, lineWidth: 1, lineStyle: style, axisLabelVisible: true, title });
      const accent = cssVar('--accent');
      pl(setup.entryHigh, accent, 'Entry', 2);
      pl(setup.entryLow, accent, 'Entry', 2);
      pl(setup.stop, red, 'Stop', 0);
      pl(setup.target1, green, 'T1', 0);
      pl(setup.target2, green, 'T2', 2);
    }
    const lineOpts = (c) => ({ color: c, lineWidth: 1.5, priceLineVisible: false, lastValueVisible: false, crosshairMarkerVisible: false });
    main.addLineSeries(lineOpts(cssVar('--ema20'))).setData(line('ema20'));
    main.addLineSeries(lineOpts(cssVar('--sma50'))).setData(line('sma50'));
    main.addLineSeries(lineOpts(cssVar('--sma200'))).setData(line('sma200'));
    const vol = main.addHistogramSeries({ priceFormat: { type: 'volume' }, priceScaleId: 'vol', lastValueVisible: false, priceLineVisible: false });
    vol.priceScale().applyOptions({ scaleMargins: { top: 0.82, bottom: 0 } });
    vol.setData(rows.map((r, i) => ({
      time: r[0], value: r[idx.volume],
      color: (i > 0 && r[idx.close] < rows[i - 1][idx.close] ? red : green) + '66',
    })));

    const sub = Object.assign({}, base, { layout: Object.assign({}, base.layout, { attributionLogo: false }) });
    const rsiChart = LC.createChart($('chart-rsi'), sub);
    const rsi = rsiChart.addLineSeries({ color: cssVar('--accent'), lineWidth: 1.5, priceLineVisible: false });
    rsi.setData(line('rsi14'));
    [70, 50, 30].forEach((p) => rsi.createPriceLine({ price: p, color: border, lineWidth: 1, lineStyle: 2, axisLabelVisible: false }));

    const macdChart = LC.createChart($('chart-macd'), sub);
    macdChart.addHistogramSeries({ priceLineVisible: false, lastValueVisible: false })
      .setData(rows.map((r) => (r[idx.macdHist] == null ? { time: r[0] }
        : { time: r[0], value: r[idx.macdHist], color: (r[idx.macdHist] >= 0 ? green : red) + '99' })));
    macdChart.addLineSeries({ color: cssVar('--accent'), lineWidth: 1.5, priceLineVisible: false }).setData(line('macd'));
    macdChart.addLineSeries({ color: cssVar('--ema20'), lineWidth: 1, priceLineVisible: false }).setData(line('macdSignal'));

    // Synkroniser tidsakser
    const charts = [main, rsiChart, macdChart];
    let syncing = false;
    charts.forEach((c) => c.timeScale().subscribeVisibleLogicalRangeChange((range) => {
      if (syncing || !range) return;
      syncing = true;
      charts.forEach((o) => { if (o !== c) o.timeScale().setVisibleLogicalRange(range); });
      syncing = false;
    }));

    const setRange = (days) => main.timeScale().setVisibleLogicalRange({ from: Math.max(0, n - days), to: n - 1 + 3 });
    $('ranges').querySelectorAll('button').forEach((b) => b.addEventListener('click', () => {
      $('ranges').querySelectorAll('button').forEach((x) => x.classList.toggle('active', x === b));
      setRange(Number(b.dataset.days));
    }));
    setRange(Number($('ranges').querySelector('.active').dataset.days));
  }

  async function main() {
    try {
      const [d, hist] = await Promise.all([getJson('data/tsla.json'), getJson('data/tsla-history.json')]);
      renderHeader(d);
      renderTrend(d);
      renderKeyFigures(d);
      renderHistorical(d.historical);
      renderSetup(d.setup);
      showWarnings(d.dataWarnings);
      $('source').textContent = 'Datakilde: ' + d.source + '. Historik: ' + d.history.bars + ' handelsdage fra ' + d.history.firstDate + '.';
      renderCharts(hist, d.setup);
    } catch (e) {
      const box = $('error');
      box.hidden = false;
      box.textContent = 'Kunne ikke indlæse data: ' + e.message;
      console.error(e);
    }
  }

  main();
})();
