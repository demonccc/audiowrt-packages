'use strict';
'require baseclass';
'require uci';
'require fs';

function parseState(text) {
	var state = {};
	(text || '').split(/\n/).forEach(function(line) {
		var p = line.indexOf('=');
		if (p > 0) state[line.substring(0, p)] = line.substring(p + 1);
	});
	return state;
}

return baseclass.extend({
	title: _('AudioWRT'),

	load: function() {
		return Promise.all([
			uci.load('system'),
			L.resolveDefault(fs.exec('/usr/sbin/audiowrt-audio', [ 'status' ]), { stdout: '' })
		]);
	},

	render: function(data) {
		var hostname = uci.get('system', '@system[0]', 'hostname') || 'OpenWrt';
		var state = parseState(data[1].stdout || '');
		var outputType = state.output_type || 'auto';
		var ready = state.ready === '1';
		var device = state.device || '-';
		var btName = state.bluetooth_name || '-';
		var error = state.last_error || '';
		var fields = [
			_('Audio name'), hostname,
			_('Output type'), outputType,
			_('Output status'), ready ? _('Ready') : _('Not ready'),
			_('ALSA device'), device,
			_('Bluetooth device'), btName
		];
		var table = E('table', { 'class': 'table' });
		for (var i = 0; i < fields.length; i += 2) {
			table.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '33%' }, fields[i]),
				E('td', { 'class': 'td left' }, fields[i + 1])
			]));
		}
		if (error)
			table.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left' }, _('Last error')),
				E('td', { 'class': 'td left' }, error)
			]));
		return table;
	}
});
