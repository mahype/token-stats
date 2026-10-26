.pragma library

function fmtTokens(n) {
    if (n >= 1e6) return (n / 1e6).toFixed(1) + " M"
    if (n >= 1e3) return Math.round(n / 1e3) + " k"
    return String(n)
}

function fmtMoney(v) {
    return v.toLocaleString(Qt.locale(), "f", 2) + " $"
}

function duration(secs) {
    secs = Math.floor(secs)
    var d = Math.floor(secs / 86400), h = Math.floor(secs % 86400 / 3600), m = Math.floor(secs % 3600 / 60)
    if (d) return h ? d + " d " + h + " h" : d + " d"
    return h ? h + " h " + m + " min" : m + " min"
}

function limitState(l) {
    // elapsed share of the window, and the gap between used share and elapsed share in seconds
    var left = l.reset ? (Date.parse(l.reset) - Date.now()) / 1000 : -1
    if (left < 0) return { elapsed: -1, gap: 0, left: 0 }
    var elapsed = 1 - left / l.window
    return { elapsed: elapsed, gap: (l.pct / 100 - elapsed) * l.window, left: left }
}

// usage: [{date, models:[{model,in,out,cache,value}]}] (oldest first, last = today); n = number of days
function aggregate(usage, n, locale) {
    var days = usage.slice(Math.max(0, usage.length - n))
    var perModel = {}, series = [], total = 0, cache = 0, value = 0, unpriced = false
    for (var i = 0; i < days.length; i++) {
        var d = days[i], dayTokens = 0
        for (var j = 0; j < d.models.length; j++) {
            var m = d.models[j]
            var acc = perModel[m.model] || (perModel[m.model] = { model: m.model, in: 0, out: 0, cache: 0, value: 0, priced: true })
            acc.in += m.in; acc.out += m.out; acc.cache += m.cache
            if (m.value === null) { acc.priced = false; unpriced = true } else { acc.value += m.value; value += m.value }
            dayTokens += m.in + m.out + m.cache
            total += m.in + m.out + m.cache
            cache += m.cache
        }
        var dt = new Date(d.date + "T12:00:00")
        series.push({ label: n <= 7 ? locale.dayName(dt.getDay(), 1).substring(0, 2) : String(dt.getDate()),
                      tokens: dayTokens, last: i === days.length - 1 })
    }
    var models = Object.keys(perModel).map(function (k) { return perModel[k] })
    models.sort(function (a, b) { return (b.in + b.out + b.cache) - (a.in + a.out + a.cache) })
    return { total: total, cache: cache, value: value, unpriced: unpriced, models: models, series: series }
}
