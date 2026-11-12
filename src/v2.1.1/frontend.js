/* TGEEK OAF TIME SYNC V2.1.1 BEGIN */
(function () {
    'use strict';

    var originalSubmit = submitHandle;
    var originalGetTimeFormData = getTimeFormData;
    var originalRenderTimeData = renderTimeData;
    var busy = false;
    var dayOrder = [1, 2, 3, 4, 5, 6, 0];

    function getBody() {
        return document.getElementById('timeTableBody');
    }

    function getRows() {
        var body = getBody();
        return body ? Array.prototype.slice.call(body.rows).filter(function (row) {
            return row.querySelector('.start-time') && row.querySelector('.end-time');
        }) : [];
    }

    /*
     * V2.1.1: reuse the original OAF weekday controls in the first table cell.
     * Do not append a new TH/TD and do not create a second weekday column.
     * The original labels, order, CSS and horizontal layout remain untouched.
     */
    function legacyWeekdayInputs(row) {
        if (!row || !row.cells || !row.cells.length) return [];
        var cell = row.cells[0];
        var inputs = cell.querySelectorAll('input[name="weekday"]');
        if (!inputs || inputs.length !== 7) {
            inputs = cell.querySelectorAll('input[type="checkbox"]');
        }

        var byDay = {};
        Array.prototype.forEach.call(inputs, function (input) {
            var value = Number(input.value);
            if (value >= 0 && value <= 6 && Math.floor(value) === value && !byDay[value]) {
                byDay[value] = input;
            }
        });

        return dayOrder.map(function (day) { return byDay[day]; }).filter(Boolean);
    }

    function rowHasLegacyWeekdays(row) {
        var inputs = legacyWeekdayInputs(row);
        return inputs.length === 7;
    }

    function selectedDays(row) {
        return legacyWeekdayInputs(row).filter(function (input) {
            return input.checked;
        }).map(function (input) {
            return Number(input.value);
        }).sort(function (a, b) { return a - b; });
    }

    function ensureAllRows() {
        var rows = getRows();
        var valid = true;
        rows.forEach(function (row) {
            var inputs = legacyWeekdayInputs(row);
            row.setAttribute('data-oaf-v211-weekday-ready', inputs.length === 7 ? '1' : '0');
            if (inputs.length !== 7) valid = false;
        });
        return valid;
    }

    function applyStoredWeekdays() {
        ensureAllRows();
        var rows = getRows();
        var list = (time_data && time_data.time_list) || [];
        var globalDays = (time_data && Array.isArray(time_data.weekday_list)) ?
            time_data.weekday_list.map(Number) : [];

        rows.forEach(function (row, index) {
            var inputs = legacyWeekdayInputs(row);
            if (inputs.length !== 7) return;
            var item = list[index] || {};
            var stored = Array.isArray(item.weekday_list) ? item.weekday_list.map(Number) : globalDays;
            inputs.forEach(function (input) {
                input.checked = stored.indexOf(Number(input.value)) !== -1;
            });
        });
    }

    /* Fixed-time mode reads each row's original weekday controls independently. */
    getTimeFormData = function () {
        var mode = document.getElementById('timeMode').value;
        if (mode !== '0') return originalGetTimeFormData.apply(this, arguments);

        var rows = getRows();
        var list = rows.map(function (row) {
            return {
                start: row.querySelector('.start-time').value,
                end: row.querySelector('.end-time').value,
                weekday_list: selectedDays(row)
            };
        });
        var union = {};
        list.forEach(function (item) {
            item.weekday_list.forEach(function (day) { union[day] = true; });
        });

        return {
            mode: 0,
            weekday_list: Object.keys(union).map(Number).sort(function (a, b) { return a - b; }),
            time_list: list
        };
    };

    function canonical(list) {
        return JSON.stringify((list || []).map(function (item) {
            return [String(item.start), String(item.end), (item.weekday_list || []).map(Number).sort(function (a, b) { return a - b; }).join(',')];
        }).sort(function (a, b) {
            return JSON.stringify(a).localeCompare(JSON.stringify(b));
        }));
    }

    submitHandle = function () {
        if (document.getElementById('timeMode').value !== '0') {
            return originalSubmit.apply(this, arguments);
        }
        if (busy) return;

        var error = document.getElementById('errorContainer');
        var rows = getRows();
        if (!rows.length || !ensureAllRows()) {
            error.textContent = '未找到原版星期控件，请勿保存。请确认使用原生 OAF 时间页面后重试。';
            return;
        }

        var payload = getTimeFormData();
        var list = payload.time_list || [];
        error.textContent = '';

        if (!list.length || list.length > 64) {
            error.textContent = '请添加 1–64 个时间段。';
            return;
        }
        for (var i = 0; i < list.length; i++) {
            var item = list[i];
            if (!item.weekday_list.length || !item.start || !item.end || item.start >= item.end) {
                error.textContent = '每段至少选择一个星期，结束时间须晚于开始时间；跨午夜请拆成两段。';
                return;
            }
        }

        busy = true;
        error.textContent = '正在保存并核对独立星期规则……';
        var timer = setTimeout(function () {
            busy = false;
            error.textContent = '请求超时，请刷新页面核对保存结果。';
        }, 15000);

        function finish(message) {
            clearTimeout(timer);
            busy = false;
            error.textContent = message;
        }

        new XHR().post("<%=url('admin/network/set_app_filter_time')%>",
            { data: JSON.stringify(payload) }, function (x, result) {
                if (!busy) return;
                if (!x || x.status !== 200 || !result || Number(result.code) !== 0) {
                    finish((result && result.message) || '保存失败，请检查后台日志。');
                    return;
                }
                new XHR().get("<%=url('admin/network/get_app_filter_time')%>", null,
                    function (rx, readback) {
                        if (!busy) return;
                        if (!rx || rx.status !== 200 || !readback || !readback.data ||
                            !readback.data.time_sync_compat || Number(readback.data.mode) !== 0 ||
                            canonical(readback.data.time_list) !== canonical(list)) {
                            finish((readback && readback.message) || '读回配置不一致，尚未确认保存成功。');
                            return;
                        }
                        time_data = readback.data;
                        originalRenderTimeData.apply(this, arguments);
                        applyStoredWeekdays();
                        finish('已保存并核对：已沿用原版星期排版，各时间段独立星期已保留。');
                    });
            });
    };

    renderTimeData = function () {
        var result = originalRenderTimeData.apply(this, arguments);
        setTimeout(applyStoredWeekdays, 0);
        return result;
    };

    function init() {
        ensureAllRows();
        applyStoredWeekdays();
        var body = getBody();
        if (body && typeof MutationObserver !== 'undefined') {
            var observer = new MutationObserver(function () {
                ensureAllRows();
            });
            observer.observe(body, { childList: true, subtree: true });
        }
    }

    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
    else init();
})();
/* TGEEK OAF TIME SYNC V2.1.1 END */
