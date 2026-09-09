'use strict';
'require baseclass';
'require uci';

return baseclass.extend({
	title: _('AudioWRT'),

	load: function() {
		return Promise.all([
			uci.load('audiowrt-audio'),
			uci.load('system')
		]);
	},

	render: function() {
		var hostname = uci.get('system', '@system[0]', 'hostname') || 'OpenWrt';
		var outputType = uci.get('audiowrt-audio', 'main', 'output_type') || 'auto';
		var ready = uci.get('audiowrt-audio', 'main', 'ready') === '1';
		var device = uci.get('audiowrt-audio', 'main', 'device') || '-';
		var btName = uci.get('audiowrt-audio', 'main', 'bluetooth_name') || '-';
		var error = uci.get('audiowrt-audio', 'main', 'last_error') || '';
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
