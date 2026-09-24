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
    const note = d.lastBar.intradayExcluded ? ' Kursen øverst er live. Analysen bygger på lukkekursen.' : '';
    $('updated').textContent = 'Opdateret ' + dtf.format(gen) + '. Analysen bygger på lukkekursen ' + bar + '.' + note;

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






  // ---------- Previous setups (fase 6) ----------
  const ST_LABEL = { green: 'INTERESSANT', yellow: 'AFVENT', red: 'UINTERESSANT' };
  const RES_LABEL = { t1: 'Target 1', stop: 'Stop', none: 'Ingen (20d)', open: 'Åben' };

  function renderPerformance(p) {
    if (!p || p.status !== 'ok') {
      $('perf-sub').textContent = p && p.reason ? 'Fejl: ' + p.reason : 'Ingen setups logget endnu.';
      return;
    }
    const from = p.firstDate ? df.format(new Date(p.firstDate + 'T12:00:00')) : '-';
    $('perf-sub').innerHTML = '<b>' + p.total + ' setups</b> siden ' + esc(from) + ' (' + p.live + ' live, ' + p.backfilled + ' beregnet bagud).';

    const num = (v, f) => (v == null ? '-' : f(v));
    const pp = (v) => num(v, (x) => nf0.format(x) + '%');
    $('perf-groups').querySelector('tbody').innerHTML = ['green', 'yellow', 'red', 'all'].map((k) => {
      const g = p.groups[k];
      const name = k === 'all' ? 'Alle' : '<span class="st st-' + k + '">' + ST_LABEL[k] + '</span>';
      return '<tr><td>' + name + '</td><td>' + g.n + '</td><td>' + g.closed + '</td><td>' + pp(g.t1Pct) + '</td><td>' + pp(g.stopPct) + '</td>' +
        '<td class="' + pctCls(g.avgR) + '">' + num(g.avgR, (x) => nf2.format(x) + 'R') + '</td>' +
        '<td>' + pp(g.d5 && g.d5.pctPositive) + '</td><td>' + pp(g.d10 && g.d10.pctPositive) + '</td>' +
        (g.d20 ? pctCell(g.d20.mean) : '<td>-</td>') + '</tr>';
    }).join('');

    $('perf-calib').querySelector('tbody').innerHTML = p.calibration.d5.map((b, i) => {
      const c = p.calibration.d10[i];
      return '<tr><td>' + esc(b.bucket) + '</td><td>' + b.n + '</td><td>' + pp(b.predicted) + '</td><td>' + pp(b.actual) + '</td>' +
        '<td>' + c.n + '</td><td>' + pp(c.predicted) + '</td><td>' + pp(c.actual) + '</td></tr>';
    }).join('');

    $('perf-recent').querySelector('tbody').innerHTML = p.recent.map((e) => {
      const o = e.outcome || { returns: {}, result: 'open' };
      const r = (v) => (v == null ? '<td class="muted">-</td>' : pctCell(v));
      const exp5 = e.expected && e.expected.d5 ? nf0.format(e.expected.d5.matches) + '%' : '-';
      const res = RES_LABEL[o.result] + (o.r != null ? ' (' + nf2.format(o.r) + 'R)' : '');
      return '<tr><td>' + esc(e.date) + (e.backfill ? '<span class="bf" title="Beregnet bagud">*</span>' : '') + '</td><td>' + usd(e.close) + '</td>' +
        '<td><span class="st st-' + e.status + '">' + esc(e.label) + '</span></td><td>' + usd(e.stop) + ' / ' + usd(e.target1) + '</td>' +
        '<td>' + exp5 + '</td>' + r(o.returns.d2) + r(o.returns.d5) + r(o.returns.d10) + r(o.returns.d20) +
        '<td class="' + (o.result === 't1' ? 'up' : o.result === 'stop' ? 'down' : '') + '">' + res + '</td></tr>';
    }).join('');

    $('perf-note').textContent = p.note + ' * = beregnet bagud. Udfald: entry på setup-dagens lukkekurs. Target 1 eller stop inden for 20 dage, ellers lukket på dag 20. R = resultat i forhold til risikoen.';
  }

  // ---------- Events (fase 5) ----------
  function renderEvents(e) {
    if (!e || e.status !== 'ok') {
      $('event-risk-label').textContent = e && e.reason ? 'Fejl: ' + e.reason : 'Ikke beregnet endnu';
      return;
    }
    $('event-risk').className = 'status status-' + e.risk.status;
    $('event-risk-label').textContent = e.risk.label;
    $('event-reasons').innerHTML = e.risk.reasons.map((r) => '<li>' + esc(r) + '</li>').join('');
    const when = (td) => (td === 0 ? 'I dag' : td === 1 ? 'I morgen' : td + ' handelsdage');
    $('events-table').querySelector('tbody').innerHTML = e.items.map((i) => {
      const url = /^https?:\/\//.test(i.url || '') ? i.url : null;
      const soon = (i.group === 'tesla' && i.tradingDays <= 5) || (i.group === 'macro' && i.tradingDays <= 1);
      return '<tr class="' + (soon ? 'ev-soon' : '') + '"><td>' + esc(df.format(new Date(i.date + 'T12:00:00'))) + (i.time ? ' ' + esc(i.time) : '') + '</td>' +
        '<td>' + when(i.tradingDays) + '</td><td>' + esc(i.typeLabel) + '</td><td>' + esc(i.title) + '</td>' +
        '<td class="' + (i.confirmed ? 'ev-conf' : 'ev-est') + '">' + (i.confirmed ? 'Bekræftet' : 'Estimat') + '</td>' +
        '<td>' + (url ? '<a href="' + esc(url) + '" target="_blank" rel="noopener noreferrer" title="' + esc(i.source) + '">Kilde</a>' : esc(i.source || '')) + '</td></tr>';
    }).join('');
    $('events-method').textContent = e.risk.rule + ' Estimater er markeret. Datoerne vedligeholdes i Events.json.' +
      (e.warnings.length ? ' Advarsel: ' + e.warnings.join(' ') : '');
  }

  // ---------- Tema ----------
  function initTheme() {
    const btn = $('theme-btn');
    const cur = () => document.documentElement.getAttribute('data-theme') || 'dark';
    const label = () => { btn.textContent = cur() === 'dark' ? 'Lyst tema' : 'Mørkt tema'; };
    label();
    btn.addEventListener('click', () => {
      const next = cur() === 'dark' ? 'light' : 'dark';
      try { localStorage.setItem('theme', next); } catch (e) { /* ignorer */ }
      document.documentElement.setAttribute('data-theme', next);
      location.reload();   // Graferne tegnes med temaets farver ved indlæsning
    });
  }

  // ---------- Nyheder (fase 4) ----------
  const TONE = { positive: 'green', neutral: 'na', negative: 'red' };
  const TONE_TXT = { positive: 'Positiv', neutral: 'Neutral', negative: 'Negativ' };

  function renderNews(n) {
    if (!n || n.status !== 'ok') {
      $('news-risk-label').textContent = n && n.reason ? 'Fejl: ' + n.reason : 'Ikke beregnet endnu';
      return;
    }
    $('news-risk').className = 'status status-' + n.risk.status;
    $('news-risk-label').textContent = n.risk.label;
    $('news-reasons').innerHTML = n.risk.reasons.map((r) => '<li>' + esc(r) + '</li>').join('');
    $('news-cats').innerHTML = Object.entries(n.categories).map(([k, v]) => '<span class="chip">' + esc(k) + ' ' + v + '</span>').join('') +
      '<span class="chip">' + n.counts.positive + ' positive / ' + n.counts.neutral + ' neutrale / ' + n.counts.negative + ' negative</span>';

    const list = (tone) => {
      const items = n.items.filter((i) => tone === 'all' || i.tone === tone);
      $('news-list').innerHTML = items.length ? items.map((i) => {
        const safe = /^https?:\/\//.test(i.link) ? i.link : '#';
        return '<li><span class="sig-dot s-' + TONE[i.tone] + '" title="' + TONE_TXT[i.tone] + '"></span><div>' +
          '<a href="' + esc(safe) + '" target="_blank" rel="noopener noreferrer">' + esc(i.title) + '</a>' +
          '<div class="news-meta">' + esc(dtf.format(new Date(i.time))) + ' · ' + esc(i.source) +
          (i.categoryLabels.length ? ' · ' + esc(i.categoryLabels.join(', ')) : '') +
          (i.highImpact ? ' · <span class="tag-high">Høj betydning</span>' : '') + '</div>' +
          '<div class="news-why">' + TONE_TXT[i.tone] + '. ' + esc(i.why) + '</div></div></li>';
      }).join('') : '<li><span></span><span class="muted">Ingen nyheder i dette filter.</span></li>';
    };
    list('all');
    $('news-filter').querySelectorAll('button').forEach((b) => b.addEventListener('click', () => {
      $('news-filter').querySelectorAll('button').forEach((x) => x.classList.toggle('active', x === b));
      list(b.dataset.tone);
    }));

    const src = n.sources.map((x) => x.name + (x.ok ? ' (' + x.items + ')' : ' (fejlede)')).join(', ');
    $('news-method').textContent = 'Kilder: ' + src + '. Seneste ' + n.days + ' dage. ' + n.method + ' ' + n.risk.rule;
  }



  // ---------- Dynamisk forklaring ----------
  function renderNarrative(n) {
    if (!n) return;
    $('narrative').hidden = false;
    $('narrative-parts').innerHTML = n.parts.map((p) => '<p class="np"><b>' + esc(p.topic) + '</b>' + esc(p.text) + '</p>').join('');
    $('narrative-need-title').textContent = n.needTitle;
    $('narrative-need').innerHTML = n.need.map((x) => '<li>' + esc(x) + '</li>').join('');
    $('narrative-note').textContent = n.note;
  }

  // ---------- Handlingsboks: hvad betyder status lige nu? ----------
  function renderAction(d) {
    const s = d.setup;
    if (!s || !s.entryLow) return;
    const p = d.quote.price, L = s.entryLow, H = s.entryHigh, S = s.stop, T1 = s.target1;
    const rrAt = (x) => (x > S ? (T1 - x) / (x - S) : null);
    const minRR = s.minRR || 1.5;
    const pGood = (T1 + minRR * S) / (1 + minRR);  // Købskurs hvor risk/reward til T1 er minRR
    const notMet = s.criteria.filter((c) => !c.pass).map((c) => c.label.toLowerCase());
    const hard = s.criteria.filter((c) => c.hardFail).map((c) => c.label.toLowerCase());
    let cls, title, text;

    if (p <= S) { cls = 'red'; title = 'Setup ugyldigt'; text = 'Kursen er under stop. Niveauerne beregnes igen efter lukketid.'; }
    else if (s.status === 'green') {
      if (p > H) { cls = 'yellow'; title = 'Over entry-zonen'; text = 'Alle krav er opfyldt, men kursen er over zonen. Efter reglerne købes der kun i zonen.'; }
      else if (p < L) { cls = 'yellow'; title = 'Under entry-zonen'; text = 'Kursen er faldet under zonen. Niveauerne beregnes igen efter lukketid.'; }
      else if (rrAt(p) >= minRR) { cls = 'green'; title = 'Muligt køb efter reglerne'; text = (s.setupType === 'vending' ? 'Vending-setup efter fald. ' : '') + 'Alle krav er opfyldt, og kursen ligger i entry-zonen med risk/reward på mindst ' + nf1.format(minRR) + '. Målet er +10% inden for 20 handelsdage.'; }
      else { cls = 'yellow'; title = 'I zonen, men dyrt'; text = 'Alle krav er opfyldt, men risk/reward ved den aktuelle kurs er under ' + nf1.format(minRR) + '. Under ' + usd(pGood) + ' er den mindst ' + nf1.format(minRR) + '.'; }
    } else if (s.status === 'yellow') {
      cls = 'yellow'; title = 'Afvent. Ikke et køb endnu';
      text = 'Ikke opfyldt: ' + notMet.join(', ') + '. Status skifter først når alle krav er opfyldt.';
    } else {
      cls = 'red'; title = 'Ikke et køb efter reglerne';
      text = 'Langt fra kravet: ' + hard.join(', ') + '.' + (notMet.length > hard.length ? ' Heller ikke opfyldt: ' + notMet.filter((x) => !hard.includes(x)).join(', ') + '.' : '');
    }

    const box = $('action');
    box.hidden = false;
    box.className = 'action a-' + cls;
    $('action-title').textContent = title;
    $('action-text').textContent = text;
    const pb = $('action-pullback');
    if (pb) {
      const show = s.pullback && s.pullback.active && s.status !== 'green';
      pb.hidden = !show;
      if (show) pb.innerHTML = '<b>Muligt pullback der vender (kun hint).</b> ' + esc(s.pullback.detail);
    }
    const f = (x) => (x == null ? '-' : nf1.format(x));
    $('action-rr').textContent = 'Risk/reward til Target 1 ved ' + usd(p) + ': ' + f(rrAt(p)) +
      '. I bunden af zonen (' + usd(L) + '): ' + f(rrAt(L)) + '. I toppen (' + usd(H) + '): ' + f(rrAt(H)) +
      '. Regelbaseret vurdering, ikke rådgivning. Har du en position, så se "Min position".';
  }

  // ---------- Tips-popup ----------
  function initTips() {
    const dlg = $('tips-dialog');
    $('tips-btn').addEventListener('click', () => { if (dlg.showModal) dlg.showModal(); else dlg.setAttribute('open', ''); });
    $('tips-close').addEventListener('click', () => dlg.close ? dlg.close() : dlg.removeAttribute('open'));
    dlg.addEventListener('click', (e) => { if (e.target === dlg) dlg.close(); });   // Klik udenfor lukker
  }

  // ---------- Min position (kun i browseren) ----------
  const POS_KEY = 'tsla-position';
  let setupLogCache = null;

  async function initPosition(d, hist) {
    let pos = null;
    try { pos = JSON.parse(localStorage.getItem(POS_KEY) || 'null'); } catch (e) { pos = null; }
    if (pos) { $('pos-date').value = pos.date; $('pos-price').value = pos.price; $('pos-qty').value = pos.qty || ''; }
    const run = async () => { if (pos) await evalPosition(pos, d, hist); else $('pos-result').innerHTML = '<p class="muted small">Indtast købsdato og købskurs. Så vises stop og targets fra den dag du købte, og hvor du er i planen nu.</p>'; };
    $('pos-form').addEventListener('submit', async (e) => {
      e.preventDefault();
      pos = { date: $('pos-date').value, price: Number($('pos-price').value), qty: Number($('pos-qty').value) || 0 };
      try { localStorage.setItem(POS_KEY, JSON.stringify(pos)); } catch (err) { /* ignorer */ }
      await run();
    });
    $('pos-clear').addEventListener('click', async () => {
      pos = null;
      try { localStorage.removeItem(POS_KEY); } catch (err) { /* ignorer */ }
      $('pos-form').reset();
      await run();
    });
    await run();
  }

  async function evalPosition(pos, d, hist) {
    const out = $('pos-result');
    try {
      if (!setupLogCache) setupLogCache = await getJson('data/setups-log.json');
    } catch (e) { setupLogCache = { entries: [] }; }
    const logE = setupLogCache.entries.filter((e) => e.date <= pos.date).pop();
    const lv = logE || d.setup;
    const src = logE ? 'setup fra ' + logE.date + (logE.date !== pos.date ? ' (seneste før købsdagen)' : '') + ', status dengang: ' + logE.label
      : 'dagens setup, fordi der ikke er logget et setup for købsdagen';
    const S = lv.stop, T1 = lv.target1, T2 = lv.target2;
    const hHigh = logE && logE.horizon ? Number(String(logE.horizon).split('-')[1]) : (d.setup.horizon ? d.setup.horizon.high : 20);

    const col = hist.columns, ix = Object.fromEntries(col.map((c, i) => [c, i]));
    const after = hist.rows.filter((r) => r[0] > pos.date);
    const last = hist.rows[hist.rows.length - 1];
    const c = last[ix.close];
    const maxH = after.length ? Math.max(...after.map((r) => r[ix.high])) : null;
    const minL = after.length ? Math.min(...after.map((r) => r[ix.low])) : null;
    const days = after.length;
    const plPct = (c / pos.price - 1) * 100;
    const risk = pos.price - S;
    const r = risk > 0 ? (c - pos.price) / risk : null;

    let cls, title, text;
    if (c < S) { cls = 'red'; title = 'Stop brudt'; text = 'Lukkekursen ' + usd(c) + ' er under stop ' + usd(S) + '. Efter planen er du ude.'; }
    else if (maxH != null && maxH >= T2) { cls = 'green'; title = 'Target 2 nået'; text = 'Kursen har været på ' + usd(maxH) + '. Planen er opfyldt.'; }
    else if (maxH != null && maxH >= T1) { cls = 'green'; title = 'Target 1 nået'; text = 'Kursen har været på ' + usd(maxH) + '. En almindelig metode er at sælge en del og flytte stop op til købskursen ' + usd(pos.price) + '.'; }
    else if (days > hHigh) { cls = 'yellow'; title = 'Horisonten er passeret'; text = days + ' handelsdage uden Target 1. Forventet horisont var højst ' + hHigh + ' dage. Forløbet passer ikke med mønsteret.'; }
    else { cls = 'neutral'; title = 'Inden for planen'; text = 'Hverken stop eller Target 1 er ramt. ' + days + ' af højst ' + hHigh + ' handelsdage er gået.'; }
    if (c >= S && minL != null && minL <= S) text += ' Bemærk: kursen har intradag været nede på ' + usd(minL) + ', under stop. En stop-ordre i banken ville have solgt dig.';
    if (pos.price > S && logE && (pos.price < logE.entryLow || pos.price > logE.entryHigh)) text += ' Købskursen lå uden for den dags entry-zone (' + usd(logE.entryLow) + ' - ' + usd(logE.entryHigh) + ').';
    if (pos.price <= S) { cls = 'yellow'; title = 'Købskurs under stop'; text = 'Købskursen er under stop fra planen, så stop og targets passer ikke til din handel.'; }

    const pl = pos.qty ? ' (' + (c >= pos.price ? '+' : '-') + usd(Math.abs(pos.qty * (c - pos.price))) + ')' : '';
    out.innerHTML =
      '<div class="action a-' + (cls === 'neutral' ? 'none' : cls) + '"><div class="action-title">' + esc(title) + '</div><div class="action-text">' + esc(text) + '</div></div>' +
      '<dl class="levels">' +
      '<div><dt>Købskurs</dt><dd>' + usd(pos.price) + '</dd></div>' +
      '<div><dt>Seneste lukkekurs</dt><dd>' + usd(c) + '<span class="pc">' + pct(plPct) + pl + '</span></dd></div>' +
      '<div><dt>Resultat i R</dt><dd>' + (r == null ? '-' : nf2.format(r) + 'R') + '</dd></div>' +
      '<div><dt>Stop</dt><dd>' + usd(S) + '</dd></div>' +
      '<div><dt>Target 1</dt><dd>' + usd(T1) + '</dd></div>' +
      '<div><dt>Target 2</dt><dd>' + usd(T2) + '</dd></div></dl>' +
      '<p class="muted small">Niveauer fra ' + esc(src) + '. Planen følger niveauerne fra købsdagen, ikke dagens nye niveauer. Beregnet på lukkekurser og dagens high/low. Regelbaseret, ikke rådgivning.</p>';
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

    $('setup-event').textContent = 'Status: grøn kræver et vending-setup efter et fald og at alle krav er opfyldt. Rød hvis et krav er langt fra. Ellers gul. News risk indgår ikke i status, se nyhedssektionen.';

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
    initTheme();
    initTips();
    try {
      const [d, hist] = await Promise.all([getJson('data/tsla.json'), getJson('data/tsla-history.json')]);
      renderHeader(d);
      renderTrend(d);
      renderNarrative(d.narrative);
      renderKeyFigures(d);
      renderHistorical(d.historical);
      renderSetup(d.setup);
      renderAction(d);
      renderNews(d.news);
      renderEvents(d.events);
      renderPerformance(d.performance);
      showWarnings(d.dataWarnings);
      $('source').textContent = 'Datakilde: ' + d.source + '. Historik: ' + d.history.bars + ' handelsdage fra ' + d.history.firstDate + '.';
      renderCharts(hist, d.setup);
      initPosition(d, hist);
    } catch (e) {
      const box = $('error');
      box.hidden = false;
      box.textContent = 'Kunne ikke indlæse data: ' + e.message;
      console.error(e);
    }
  }

  main();
})();
