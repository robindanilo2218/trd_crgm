// ==========================================
        // 1. REGISTRO SERVICE WORKER (Para Producción)
        // ==========================================
        if ('serviceWorker' in navigator) {
            // El navegador buscará sw.js en la misma carpeta del html.
            // Si el archivo no existe (como aquí en el Canvas), lanzará un 404 seguro, 
            // pero la app seguirá funcionando normalmente con IndexedDB.
            navigator.serviceWorker.register('./sw.js')
                .then(reg => console.log('SW Registrado', reg.scope))
                .catch(err => console.warn('SW no encontrado, ejecutando en modo online regular.'));
        }

        // ==========================================
        // 2. BASE DE DATOS LOCAL (IndexedDB Vanilla)
        // ==========================================
        const DB = {
            name: 'TradeStatsVanillaDB',
            version: 1,
            store: 'datasets',
            open() {
                return new Promise((resolve, reject) => {
                    const req = indexedDB.open(this.name, this.version);
                    req.onupgradeneeded = e => {
                        const db = e.target.result;
                        if (!db.objectStoreNames.contains(this.store)) db.createObjectStore(this.store, { keyPath: 'id' });
                    };
                    req.onsuccess = () => resolve(req.result);
                    req.onerror = () => reject(req.error);
                });
            },
            async save(dataset) {
                const db = await this.open();
                return new Promise((resolve, reject) => {
                    const tx = db.transaction(this.store, 'readwrite');
                    tx.objectStore(this.store).put(dataset);
                    tx.oncomplete = resolve;
                    tx.onerror = reject;
                });
            },
            async getAll() {
                const db = await this.open();
                return new Promise((resolve, reject) => {
                    const tx = db.transaction(this.store, 'readonly');
                    const req = tx.objectStore(this.store).getAll();
                    req.onsuccess = () => resolve(req.result);
                    req.onerror = reject;
                });
            },
            async delete(id) {
                const db = await this.open();
                return new Promise((resolve, reject) => {
                    const tx = db.transaction(this.store, 'readwrite');
                    tx.objectStore(this.store).delete(id);
                    tx.oncomplete = resolve;
                    tx.onerror = reject;
                });
            }
        };

        // ==========================================
        // 3. ESTADO DE LA APP Y MATEMÁTICAS
        // ==========================================
        const State = {
            datasets: [],
            activeId: null,
            timeFilter: 'M1', // M1, H1, H4, D1
            dateStart: null,
            dateEnd: null,
            processedData: [],
            stats: null,
            // Columnas personalizadas
            customColumns: []
        };

        const MathUtils = {
            quartiles(arr) {
                if (!arr || arr.length === 0) return { min: 0, q1: 0, q2: 0, q3: 0, max: 0, count: 0 };
                const s = [...arr].sort((a, b) => a - b);
                return {
                    min: s[0],
                    q1: s[Math.floor(s.length * 0.25)],
                    q2: s[Math.floor(s.length * 0.50)], // Mediana
                    q3: s[Math.floor(s.length * 0.75)],
                    max: s[s.length - 1],
                    count: s.length
                };
            },
            mode(arr) {
                if (!arr || arr.length === 0) return 0;
                let freq = {}, maxFreq = 0, mode = arr[0];
                for (let v of arr) {
                    let r = Math.round(v * 10) / 10;
                    freq[r] = (freq[r] || 0) + 1;
                    if (freq[r] > maxFreq) { maxFreq = freq[r]; mode = r; }
                }
                return mode;
            }
        };

        // ==========================================
        // 4. LÓGICA PRINCIPAL (PARSER Y CÁLCULOS)
        // ==========================================
        function showLoader(text) {
            document.getElementById('loader-text').innerText = text;
            document.getElementById('loader').classList.add('active');
        }
        function hideLoader() { document.getElementById('loader').classList.remove('active'); }

        async function parseCSV(file) {
            showLoader("Leyendo archivo...");
            try {
                const text = await file.text();
                const delimiter = text.includes('\t') ? '\t' : ',';
                const lines = text.split('\n').map(l => l.trim()).filter(l => l);

                if (lines.length < 2) throw new Error("Archivo muy corto.");

                const headers = lines[0].split(delimiter).map(h => h.replace(/<|>/g, '').toLowerCase());

                // Buscar indices estandar
                const iD = headers.findIndex(h => h === 'date' || h.includes('date') || h === 'd');
                const iT = headers.findIndex(h => h === 'time' || h.includes('time') || h === 't');
                const iO = headers.findIndex(h => h === 'open' || h.includes('open') || h === 'o');
                const iH = headers.findIndex(h => h === 'high' || h.includes('high') || h === 'h');
                const iL = headers.findIndex(h => h === 'low' || h.includes('low') || h === 'l');
                const iC = headers.findIndex(h => h === 'close' || h.includes('close') || h === 'c');
                const iTV = headers.findIndex(h => h === 'tickvol' || h.includes('tickvol') || h === 'tv');
                const iV = headers.findIndex(h => h === 'vol' || h === 'volume' || h === 'v');
                const iS = headers.findIndex(h => h === 'spread' || h.includes('spread') || h === 'sp');

                if (iO === -1 || iC === -1) throw new Error("Faltan columnas Open/Close");

                const data = [];
                for (let i = 1; i < lines.length; i++) {
                    const cols = lines[i].split(delimiter);
                    if (cols.length < 4) continue;

                    let dtStr = '';
                    if (iD !== -1 && iT !== -1) {
                        dtStr = `${cols[iD].replace(/\./g, '-')}T${cols[iT]}`;
                    } else if (iD !== -1) {
                        dtStr = cols[iD].replace(/\./g, '-');
                    } else {
                        dtStr = new Date().toISOString();
                    }

                    const timestamp = new Date(dtStr).getTime();
                    if (isNaN(timestamp)) continue;

                    let row = {
                        datetime: timestamp,
                        open: parseFloat(cols[iO]),
                        high: parseFloat(cols[iH]),
                        low: parseFloat(cols[iL]),
                        close: parseFloat(cols[iC]),
                        tickvol: iTV !== -1 ? parseFloat(cols[iTV]) : 0,
                        vol: iV !== -1 ? parseFloat(cols[iV]) : 0,
                        spread: iS !== -1 ? parseFloat(cols[iS]) : 0
                    };

                    // Agregar columnas extra que no sean las básicas
                    headers.forEach((h, idx) => {
                        if (![iD, iT, iO, iH, iL, iC, iTV, iV, iS].includes(idx)) {
                            row[h] = isNaN(cols[idx]) ? cols[idx] : parseFloat(cols[idx]);
                        }
                    });

                    data.push(row);
                }

                const ds = {
                    id: Date.now().toString(),
                    name: file.name,
                    data: data,
                    customColumns: [] // Para guardar las fórmulas agregadas por el usuario
                };

                await DB.save(ds);
                await loadDatasets();
                setActiveDataset(ds.id);
            } catch (e) {
                alert("Error: " + e.message);
            }
            hideLoader();
        }

        function processTimeframe() {
            const ds = State.datasets.find(d => d.id === State.activeId);
            if (!ds) return [];

            let raw = ds.data;
            
            if (State.dateStart) {
                const sTime = new Date(State.dateStart + "T00:00:00").getTime();
                raw = raw.filter(r => r.datetime >= sTime);
            }
            if (State.dateEnd) {
                const eTime = new Date(State.dateEnd + "T23:59:59.999").getTime();
                raw = raw.filter(r => r.datetime <= eTime);
            }

            if (State.timeFilter === 'M1') return [...raw];

            const grouped = {};
            for (let r of raw) {
                const dateObj = new Date(r.datetime);
                let key = 0;

                const m = dateObj.getMinutes();
                const h = dateObj.getHours();

                switch (State.timeFilter) {
                    case 'M5':
                        dateObj.setMinutes(m - (m % 5), 0, 0);
                        break;
                    case 'M15':
                        dateObj.setMinutes(m - (m % 15), 0, 0);
                        break;
                    case 'M30':
                        dateObj.setMinutes(m - (m % 30), 0, 0);
                        break;
                    case 'H1':
                        dateObj.setMinutes(0, 0, 0);
                        break;
                    case 'H4':
                        dateObj.setHours(h - (h % 4), 0, 0, 0);
                        break;
                    case 'H6':
                        dateObj.setHours(h - (h % 6), 0, 0, 0);
                        break;
                    case 'H12':
                        dateObj.setHours(h - (h % 12), 0, 0, 0);
                        break;
                    case 'D1':
                        dateObj.setHours(0, 0, 0, 0);
                        break;
                    case 'W1':
                        const day = dateObj.getDay();
                        dateObj.setDate(dateObj.getDate() - day);
                        dateObj.setHours(0, 0, 0, 0);
                        break;
                    case 'MN':
                        dateObj.setDate(1);
                        dateObj.setHours(0, 0, 0, 0);
                        break;
                    case 'Y1':
                        dateObj.setMonth(0, 1);
                        dateObj.setHours(0, 0, 0, 0);
                        break;
                    case 'ALL':
                        dateObj.setTime(0);
                        break;
                }

                key = dateObj.getTime();

                if (!grouped[key]) {
                    grouped[key] = { ...r, datetime: key, close: r.close };
                } else {
                    grouped[key].high = Math.max(grouped[key].high, r.high);
                    grouped[key].low = Math.min(grouped[key].low, r.low);
                    grouped[key].close = r.close;
                    if (r.vol !== undefined) grouped[key].vol += r.vol;
                    if (r.tickvol !== undefined) grouped[key].tickvol += r.tickvol;
                    if (r.spread !== undefined) grouped[key].spread = Math.max(grouped[key].spread, r.spread);
                }
            }
            return Object.values(grouped).sort((a, b) => a.datetime - b.datetime);
        }

        function calculateIndicators() {
            let data = processTimeframe();
            if (data.length === 0) return [];

            const rsiP = parseInt(document.getElementById('input-rsi').value) || 14;
            const atrP = parseInt(document.getElementById('input-atr').value) || 14;

            // Calcular columnas calculadas personalizadas (Eval seguro)
            const ds = State.datasets.find(d => d.id === State.activeId);
            const formulas = ds?.customColumns || [];

            let gains = 0, losses = 0, trSum = 0;

            for (let i = 0; i < data.length; i++) {
                // Fórmulas personalizadas
                formulas.forEach(f => {
                    try {
                        const func = new Function(...Object.keys(data[i]), `return ${f.formula};`);
                        data[i][f.name] = func(...Object.values(data[i]));
                    } catch (e) { data[i][f.name] = null; }
                });

                // RSI
                if (i > 0) {
                    const chg = data[i].close - data[i - 1].close;
                    if (i <= rsiP) {
                        if (chg > 0) gains += chg; else losses -= chg;
                    }
                    if (i === rsiP) {
                        data[i].avgGain = gains / rsiP;
                        data[i].avgLoss = losses / rsiP;
                        let rs = data[i].avgLoss === 0 ? 100 : data[i].avgGain / data[i].avgLoss;
                        data[i].rsi = 100 - (100 / (1 + rs));
                    } else if (i > rsiP) {
                        let cG = chg > 0 ? chg : 0;
                        let cL = chg < 0 ? -chg : 0;
                        data[i].avgGain = ((data[i - 1].avgGain * (rsiP - 1)) + cG) / rsiP;
                        data[i].avgLoss = ((data[i - 1].avgLoss * (rsiP - 1)) + cL) / rsiP;
                        let rs = data[i].avgLoss === 0 ? 100 : data[i].avgGain / data[i].avgLoss;
                        data[i].rsi = 100 - (100 / (1 + rs));
                    }
                }

                // ATR
                if (i === 0) data[i].tr = data[i].high - data[i].low;
                else {
                    const hl = data[i].high - data[i].low;
                    const hc = Math.abs(data[i].high - data[i - 1].close);
                    const lc = Math.abs(data[i].low - data[i - 1].close);
                    data[i].tr = Math.max(hl, hc, lc);
                }

                if (i < atrP) trSum += data[i].tr;
                else if (i === atrP) data[i].atr = trSum / atrP;
                else data[i].atr = ((data[i - 1].atr * (atrP - 1)) + data[i].tr) / atrP;
            }

            return data;
        }

        function computeStats(data) {
            if (!data || data.length === 0) return null;

            let pos = [], neg = [], rsi = [], atr = [], vol = [], hours = {};
            const avgP = data[0].close;
            const pipMult = (avgP < 200 && avgP > 10) ? 100 : 10000; // JPY o normal

            for (let c of data) {
                const dateObj = new Date(c.datetime);
                const h = dateObj.getHours();

                const openCloseDist = (c.close - c.open) * pipMult;
                const highLowDist = (c.high - c.low) * pipMult;

                if (c.close >= c.open) pos.push(openCloseDist);
                else neg.push(Math.abs(openCloseDist));

                if (c.rsi !== undefined) rsi.push(c.rsi);
                if (c.atr !== undefined) atr.push(c.atr * pipMult);
                vol.push(c.tickvol || c.vol || 0);

                if (!hours[h]) hours[h] = { ranges: [], moves: [] };
                hours[h].ranges.push(highLowDist);
                hours[h].moves.push(Math.abs(openCloseDist));
            }

            const procHours = Object.keys(hours).map(k => ({
                hour: parseInt(k),
                avgRange: hours[k].ranges.reduce((a, b) => a + b, 0) / hours[k].ranges.length,
                quartiles: MathUtils.quartiles(hours[k].moves),
                mode: MathUtils.mode(hours[k].moves)
            })).sort((a, b) => a.hour - b.hour);

            return {
                pipMult,
                pos: MathUtils.quartiles(pos), modePos: MathUtils.mode(pos),
                neg: MathUtils.quartiles(neg), modeNeg: MathUtils.mode(neg),
                rsi: MathUtils.quartiles(rsi),
                atr: MathUtils.quartiles(atr),
                vol: MathUtils.quartiles(vol),
                hours: procHours
            };
        }

        // ==========================================
        // 5. RENDERIZADO DE VISTAS
        // ==========================================
        function renderAll() {
            showLoader("Actualizando Vistas...");
            setTimeout(() => {
                const data = calculateIndicators();
                State.processedData = data;
                State.stats = computeStats(data);

                renderSidebar();
                renderTable(data);
                renderStatsTabs();
                updateRiskMax();

                hideLoader();
            }, 50);
        }

        function renderSidebar() {
            const list = document.getElementById('saved-files-list');
            list.innerHTML = '';

            if (State.datasets.length === 0) {
                list.innerHTML = '<li class="text-slate-500 italic text-xs">Ningún archivo cargado</li>';
                document.getElementById('active-dataset-name').innerText = 'Ninguno';
                document.getElementById('btn-add-calc').classList.add('hidden');
                return;
            }

            State.datasets.forEach(d => {
                const li = document.createElement('li');
                const isAct = d.id === State.activeId;
                li.className = `flex justify-between p-2 rounded cursor-pointer transition ${isAct ? 'bg-blue-600 text-white' : 'hover:bg-slate-800'}`;
                li.innerHTML = `
                    <div class="truncate pr-2" onclick="setActiveDataset('${d.id}')">
                        <div class="font-medium truncate">${d.name}</div>
                        <div class="text-[10px] opacity-70">${d.data.length} filas</div>
                    </div>
                    <button class="text-red-400 hover:text-red-300" onclick="deleteDataset('${d.id}')">✕</button>
                `;
                list.appendChild(li);
                if (isAct) {
                    document.getElementById('active-dataset-name').innerText = d.name;
                    document.getElementById('btn-add-calc').classList.remove('hidden');
                    document.getElementById('data-status').innerText = `${State.processedData.length} registros (${State.timeFilter})`;
                }
            });
        }

        function renderTable(data) {
            const thead = document.getElementById('table-head');
            const tbody = document.getElementById('table-body');
            thead.innerHTML = ''; tbody.innerHTML = '';

            if (data.length === 0) {
                thead.innerHTML = '<tr><th class="p-4">Sube un archivo para ver los datos</th></tr>';
                return;
            }

            // Renderizar encabezados dinámicamente
            const sample = data[0];
            const keys = Object.keys(sample).filter(k => !['avgGain', 'avgLoss', 'tr'].includes(k)); // Ocultar auxiliares

            let headRow = '<tr>';
            keys.forEach(k => { headRow += `<th class="px-4 py-3">${k.toUpperCase()}</th>`; });
            thead.innerHTML = headRow + '</tr>';

            // Paginación (Mostrar solo las primeras 1000 para no trabar el navegador)
            const limit = Math.min(data.length, 1000);
            document.getElementById('pagination-info').innerText = `Mostrando ${limit} de ${data.length} filas. Usa los filtros y estadísticas para analizar la totalidad.`;

            let bodyHtml = '';
            for (let i = 0; i < limit; i++) {
                let rowHtml = `<tr class="hover:bg-slate-700/30 transition-colors">`;
                keys.forEach(k => {
                    let val = data[i][k];
                    if (k === 'datetime') val = new Date(val).toLocaleString();
                    else if (typeof val === 'number') val = val.toFixed(4);
                    rowHtml += `<td class="px-4 py-2 font-mono">${val !== undefined && val !== null ? val : '-'}</td>`;
                });
                bodyHtml += rowHtml + '</tr>';
            }
            tbody.innerHTML = bodyHtml;
        }

        function createQuartileHTML(title, data, suffix = "") {
            if (!data) return '';
            return `
                <div class="bg-slate-800 rounded-xl border border-slate-700 shadow-lg p-5">
                    <h3 class="text-slate-300 font-semibold mb-4 border-b border-slate-700 pb-2">${title} <span class="text-xs text-slate-500 ml-2">(n=${data.count})</span></h3>
                    <div class="space-y-2 text-sm">
                        <div class="flex justify-between"><span class="text-slate-500">Mínimo:</span> <span class="font-mono">${data.min.toFixed(4)}${suffix}</span></div>
                        <div class="flex justify-between"><span class="text-slate-500">Q1 (25%):</span> <span class="font-mono text-blue-400">${data.q1.toFixed(4)}${suffix}</span></div>
                        <div class="flex justify-between"><span class="text-slate-500">Mediana (Q2):</span> <span class="font-mono text-green-400">${data.q2.toFixed(4)}${suffix}</span></div>
                        <div class="flex justify-between"><span class="text-slate-500">Q3 (75%):</span> <span class="font-mono text-purple-400">${data.q3.toFixed(4)}${suffix}</span></div>
                        <div class="flex justify-between"><span class="text-slate-500">Máximo:</span> <span class="font-mono">${data.max.toFixed(4)}${suffix}</span></div>
                    </div>
                </div>
            `;
        }

        function renderStatsTabs() {
            const stats = State.stats;
            if (!stats) return;

            // Velas
            const cVelas = document.getElementById('velas-container');
            cVelas.innerHTML = `
                ${createQuartileHTML('▲ Velas Alcistas (Positivas)', stats.pos, ' pips')}
                ${createQuartileHTML('▼ Velas Bajistas (Negativas)', stats.neg, ' pips')}
                <div class="col-span-1 lg:col-span-2 grid grid-cols-2 gap-6 mt-4">
                    <div class="bg-slate-900 border border-slate-700 p-4 rounded-lg flex flex-col items-center justify-center">
                        <span class="text-slate-500 text-sm mb-1">Moda Alcista (Mov. Frecuente)</span>
                        <span class="text-2xl font-bold text-green-400">${stats.modePos.toFixed(1)} pips</span>
                    </div>
                    <div class="bg-slate-900 border border-slate-700 p-4 rounded-lg flex flex-col items-center justify-center">
                        <span class="text-slate-500 text-sm mb-1">Moda Bajista (Mov. Frecuente)</span>
                        <span class="text-2xl font-bold text-red-400">${stats.modeNeg.toFixed(1)} pips</span>
                    </div>
                </div>
            `;

            // Horarios
            const tBodyHours = document.getElementById('hours-body');
            let hHtml = '';
            stats.hours.forEach(h => {
                hHtml += `
                <tr class="hover:bg-slate-700/50">
                    <td class="px-4 py-3 font-bold text-white">${h.hour.toString().padStart(2, '0')}:00</td>
                    <td class="px-4 py-3 font-mono text-blue-400">${h.avgRange.toFixed(1)}</td>
                    <td class="px-4 py-3 font-mono text-yellow-400">${h.mode.toFixed(1)}</td>
                    <td class="px-4 py-3 font-mono text-slate-400">${h.quartiles.min.toFixed(1)}</td>
                    <td class="px-4 py-3 font-mono">${h.quartiles.q1.toFixed(1)}</td>
                    <td class="px-4 py-3 font-mono text-green-400">${h.quartiles.q2.toFixed(1)}</td>
                    <td class="px-4 py-3 font-mono text-purple-400">${h.quartiles.q3.toFixed(1)}</td>
                    <td class="px-4 py-3 font-mono text-slate-400">${h.quartiles.max.toFixed(1)}</td>
                </tr>`;
            });
            tBodyHours.innerHTML = hHtml;

            // Indicadores
            const rsiP = document.getElementById('input-rsi').value;
            const atrP = document.getElementById('input-atr').value;
            const cInd = document.getElementById('indicadores-container');
            cInd.innerHTML = `
                ${createQuartileHTML(`RSI (${rsiP})`, stats.rsi)}
                ${createQuartileHTML(`ATR (${atrP}) Volatilidad`, stats.atr, ' pips')}
                ${createQuartileHTML(`Volumen (Ticks)`, stats.vol)}
            `;
        }

        // ==========================================
        // 6. CALCULADORA DE RIESGO
        // ==========================================
        function updateRiskMax() {
            const el = document.getElementById('risk-candle-idx');
            el.max = Math.max(0, State.processedData.length - 1);
            if (el.value > el.max) el.value = el.max;
            calcRisk();
        }

        function calcRisk() {
            if (!State.stats || State.processedData.length === 0) return;

            const bal = parseFloat(document.getElementById('risk-balance').value) || 0;
            const pct = parseFloat(document.getElementById('risk-percent').value) || 0;
            const idx = parseInt(document.getElementById('risk-candle-idx').value) || 0;
            const strategy = document.getElementById('risk-strategy').value;

            document.getElementById('risk-candle-label').innerText = `Vela #${idx}`;

            let slPips = parseFloat(document.getElementById('risk-sl').value) || 1;

            if (strategy !== 'manual') {
                if (strategy === 'vela') {
                    const c = State.processedData[idx];
                    const isBull = c.close >= c.open;
                    const dist = isBull ? (c.close - c.low) : (c.high - c.close);
                    slPips = Math.max(1, dist * State.stats.pipMult);
                    document.getElementById('slider-container').classList.remove('hidden');
                } else {
                    document.getElementById('slider-container').classList.add('hidden');

                    if (strategy === 'pos_q1') slPips = State.stats.pos.q1;
                    else if (strategy === 'pos_q2') slPips = State.stats.pos.q2;
                    else if (strategy === 'pos_q3') slPips = State.stats.pos.q3;
                    else if (strategy === 'neg_q1') slPips = State.stats.neg.q1;
                    else if (strategy === 'neg_q2') slPips = State.stats.neg.q2;
                    else if (strategy === 'neg_q3') slPips = State.stats.neg.q3;
                    else if (strategy === 'atr') {
                        const lastCandle = State.processedData[State.processedData.length - 1];
                        slPips = lastCandle && lastCandle.atr ? (lastCandle.atr * State.stats.pipMult) : 1;
                    }
                    slPips = Math.max(1, slPips); // Asegurar que sea mayor a cero
                }
                document.getElementById('risk-sl').value = slPips.toFixed(1);
            } else {
                document.getElementById('slider-container').classList.add('hidden');
            }

            const riskMoney = bal * (pct / 100);
            const lotSize = riskMoney / (slPips * 10); // $10 por pip lote std

            document.getElementById('risk-money').innerText = `$${riskMoney.toFixed(2)}`;
            document.getElementById('risk-lots').innerText = isFinite(lotSize) && lotSize > 0 ? lotSize.toFixed(2) : '0.00';
        }

        // ==========================================
        // 7. EVENTOS Y CONTROLADORES
        // ==========================================
        async function loadDatasets() {
            State.datasets = await DB.getAll();
            if (State.datasets.length > 0 && !State.activeId) {
                State.activeId = State.datasets[0].id;
            } else if (State.datasets.length === 0) {
                State.activeId = null;
            }
            renderAll();
        }

        async function setActiveDataset(id) {
            State.activeId = id;
            renderAll();
        }

        async function deleteDataset(id) {
            await DB.delete(id);
            if (State.activeId === id) State.activeId = null;
            loadDatasets();
        }

        // UI Tabs
        document.querySelectorAll('.nav-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                // Estilos
                document.querySelectorAll('.nav-btn').forEach(b => {
                    b.className = 'nav-btn w-full flex items-center gap-3 px-4 py-3 rounded-lg text-sm font-medium transition-all text-slate-400 hover:bg-slate-800 hover:text-slate-200';
                });
                btn.className = 'nav-btn w-full flex items-center gap-3 px-4 py-3 rounded-lg text-sm font-medium transition-all bg-blue-600 text-white shadow-md';

                // Mostrar/Ocultar
                document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
                document.getElementById(btn.dataset.target).classList.add('active');
            });
        });

        // Time Filters
        document.querySelectorAll('.time-filter-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                document.querySelectorAll('.time-filter-btn').forEach(b => {
                    b.className = 'time-filter-btn px-3 py-1.5 rounded text-xs font-medium text-slate-400 hover:text-white hover:bg-slate-800 shrink-0';
                });
                btn.className = 'time-filter-btn px-3 py-1.5 rounded text-xs font-medium bg-blue-600 text-white shrink-0';
                State.timeFilter = btn.dataset.tf;
                renderAll();
            });
        });

        // Date Filters
        document.getElementById('date-start').addEventListener('change', (e) => {
            State.dateStart = e.target.value;
            renderAll();
        });
        document.getElementById('date-end').addEventListener('change', (e) => {
            State.dateEnd = e.target.value;
            renderAll();
        });
        document.getElementById('btn-date-clear').addEventListener('click', () => {
            document.getElementById('date-start').value = '';
            document.getElementById('date-end').value = '';
            State.dateStart = null;
            State.dateEnd = null;
            renderAll();
        });

        // Eventos Generales
        document.getElementById('file-input').addEventListener('change', e => {
            if (e.target.files[0]) parseCSV(e.target.files[0]);
        });

        document.getElementById('btn-recalc-ind').addEventListener('click', renderAll);

        // Eventos de Calculadora de Riesgo
        ['risk-balance', 'risk-percent', 'risk-candle-idx', 'risk-strategy'].forEach(id => {
            document.getElementById(id).addEventListener('input', calcRisk);
        });

        // Si el usuario edita el SL manualmente, cambiar estrategia a 'manual'
        document.getElementById('risk-sl').addEventListener('input', () => {
            document.getElementById('risk-strategy').value = 'manual';
            calcRisk();
        });

        // Evento: Columna Calculada (Críticidad mode)
        document.getElementById('btn-add-calc').addEventListener('click', async () => {
            if (!State.activeId) return;
            const name = prompt("Nombre de la nueva columna calculada:");
            if (!name) return;
            const formula = prompt(`Fórmula en JavaScript usando los nombres de columna (ej. open, high, low, close, vol).\n\nEjemplo para rango de vela:\nhigh - low`);
            if (!formula) return;

            const ds = State.datasets.find(d => d.id === State.activeId);
            if (!ds.customColumns) ds.customColumns = [];
            ds.customColumns.push({ name: name.toLowerCase().replace(/ /g, '_'), formula });

            showLoader("Aplicando Fórmula...");
            await DB.save(ds);
            await loadDatasets();
        });

        // INICIALIZACIÓN
        window.onload = loadDatasets;
