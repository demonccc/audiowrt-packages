'use strict';
'require view';
'require fs';

function parseRows(text) {
	return (text || '').trim().split(/\n/).filter(Boolean).map(function(line) {
		var f = line.split('\t');
		return {
			pid: f[0] || '-',
			owner: f[1] || '-',
			command: f[2] || '-',
			cpu: f[3] || '0',
			memory: f[4] || '0'
		};
	});
}

return view.extend({
	load: function() {
		return L.resolveDefault(fs.exec('/usr/libexec/audiowrt-process-list', []), { stdout: '' });
	},

	render: function(data) {
		var rows = parseRows(data.stdout || '');
		var table = E('table', { 'class': 'table' }, [
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, _('PID')),
				E('th', { 'class': 'th' }, _('Owner')),
				E('th', { 'class': 'th' }, _('Command')),
				E('th', { 'class': 'th right' }, _('CPU usage (%)')),
				E('th', { 'class': 'th right' }, _('Memory usage (%)'))
			])
		]);

		if (!rows.length) {
			table.appendChild(E('tr', { 'class': 'tr placeholder' }, [
				E('td', { 'class': 'td', 'colspan': '5' }, E('em', {}, _('No process information available')))
			]));
		} else {
			rows.forEach(function(row) {
				table.appendChild(E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td' }, row.pid),
					E('td', { 'class': 'td' }, row.owner),
					E('td', { 'class': 'td', 'style': 'word-break:break-word' }, row.command),
					E('td', { 'class': 'td right' }, row.cpu),
					E('td', { 'class': 'td right' }, row.memory)
				]));
			});
		}

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Processes')),
			E('div', { 'class': 'cbi-section' }, [ table ])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
