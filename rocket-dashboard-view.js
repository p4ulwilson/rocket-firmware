'use strict';
'require view';

// Rocket Routers Dashboard — LuCI view entry point
// Immediately redirects to the CGI dashboard which has full system data
// Deployed to: /www/luci-static/resources/view/rocket/overview.js

return view.extend({
	title: _('Rocket Dashboard'),

	render: function() {
		window.location.replace('/cgi-bin/rocket');
		return E('div', { style: 'text-align:center;padding:60px;color:#8b949e' }, [
			E('div', { style: 'font-size:2em;margin-bottom:16px' }, '🚀'),
			E('div', {}, 'Loading Rocket Dashboard...')
		]);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
