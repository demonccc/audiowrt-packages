(function() {
	'use strict';

	function directSubmenu(li) {
		for (var i = 0; i < li.children.length; i++)
			if (li.children[i].tagName === 'UL') return li.children[i];
		return null;
	}

	function directAnchor(li) {
		for (var i = 0; i < li.children.length; i++)
			if (li.children[i].tagName === 'A') return li.children[i];
		return null;
	}

	function normalizePath(url) {
		try { return new URL(url, window.location.href).pathname.replace(/\/+$/, ''); }
		catch (e) { return ''; }
	}

	function syncCurrent(menu) {
		var current = window.location.pathname.replace(/\/+$/, '');
		var links = menu.querySelectorAll('li > ul a[href]');
		var best = null, bestLen = -1;

		for (var i = 0; i < links.length; i++) {
			var path = normalizePath(links[i].href);
			links[i].parentNode.classList.remove('aw-current');
			if (!path) continue;
			if ((current === path || current.indexOf(path + '/') === 0) && path.length > bestLen) {
				best = links[i];
				bestLen = path.length;
			}
		}

		if (!best) return;
		var subitem = best.parentNode;
		subitem.classList.add('aw-current');
		var submenu = subitem.parentNode;
		var top = submenu && submenu.parentNode;
		if (top && top.parentNode === menu) {
			for (var j = 0; j < menu.children.length; j++)
				menu.children[j].classList.remove('aw-expanded');
			top.classList.add('aw-expanded');
		}
	}

	function enableAccordion(menu) {
		if (!menu || menu.dataset.awAccordion === '1') return;
		menu.dataset.awAccordion = '1';

		menu.addEventListener('click', function(ev) {
			var anchor = ev.target.closest ? ev.target.closest('a') : null;
			if (!anchor || !menu.contains(anchor)) return;

			var item = anchor.parentNode;
			if (!item || item.parentNode !== menu || directAnchor(item) !== anchor)
				return;

			var submenu = directSubmenu(item);
			if (!submenu) return;
			ev.preventDefault();

			if (item.classList.contains('aw-expanded')) return;
			for (var j = 0; j < menu.children.length; j++)
				menu.children[j].classList.remove('aw-expanded');
			item.classList.add('aw-expanded');
		});

		syncCurrent(menu);
	}

	function renderTabMenu(ui, tree, url, level) {
		var container = document.querySelector('#tabmenu');
		if (!container) return;

		var ul = E('ul', { 'class': 'tabs' });
		var children = ui.menu.getChildren(tree);
		var activeNode = null;

		children.forEach(function(child) {
			var isActive = (L.env.dispatchpath[3 + (level || 0)] == child.name);
			ul.appendChild(E('li', { 'class': 'tabmenu-item-' + child.name + (isActive ? ' active' : '') }, [
				E('a', { 'href': L.url(url, child.name) }, [ _(child.title) ])
			]));
			if (isActive) activeNode = child;
		});

		if (!ul.children.length) return;
		container.appendChild(ul);
		container.style.display = '';
		if (activeNode)
			renderTabMenu(ui, activeNode, url + '/' + activeNode.name, (level || 0) + 1);
	}

	function renderMainMenu(ui, tree, url, level) {
		var ul = level ? E('ul', { 'class': 'dropdown-menu' }) : document.querySelector('#topmenu');
		var children = ui.menu.getChildren(tree);
		if (!ul || children.length === 0 || level > 1) return E([]);

		children.forEach(function(child) {
			var submenu = renderMainMenu(ui, child, url + '/' + child.name, (level || 0) + 1);
			var hasSubmenu = !!submenu.firstElementChild;
			var li = E('li', { 'class': (!level && hasSubmenu) ? 'dropdown' : '' }, [
				E('a', {
					'class': (!level && hasSubmenu) ? 'menu' : '',
					'href': hasSubmenu ? '#' : L.url(url, child.name)
				}, [ _(child.title) ]),
				submenu
			]);
			ul.appendChild(li);
		});

		ul.style.display = '';
		return ul;
	}

	function renderModeMenu(ui, tree) {
		var ul = document.querySelector('#modemenu');
		if (!ul) return;
		var children = ui.menu.getChildren(tree);

		children.forEach(function(child, index) {
			var isActive = L.env.requestpath.length ? child.name === L.env.requestpath[0] : index === 0;
			ul.appendChild(E('li', { 'class': isActive ? 'active' : '' }, [
				E('a', { 'href': L.url(child.name) }, [ _(child.title) ])
			]));
			if (isActive) renderMainMenu(ui, child, child.name, 0);
		});

		if (ul.children.length > 1) ul.style.display = '';
	}

	function renderMenu(ui, tree) {
		renderModeMenu(ui, tree);

		var node = tree;
		var url = '';
		if (L.env.dispatchpath.length >= 3) {
			for (var i = 0; i < 3 && node; i++) {
				node = node.children[L.env.dispatchpath[i]];
				url += (url ? '/' : '') + L.env.dispatchpath[i];
			}
			if (node) renderTabMenu(ui, node, url, 0);
		}

		enableAccordion(document.getElementById('topmenu'));
	}

	function init() {
		if (!window.L || !L.require) return;
		L.require('ui').then(function(ui) {
			return ui.menu.load().then(function(tree) { renderMenu(ui, tree); });
		}).catch(function(err) {
			console.error('AudioWRT menu initialization failed', err);
		});
	}

	if (document.readyState === 'loading')
		document.addEventListener('DOMContentLoaded', init);
	else
		init();
})();
