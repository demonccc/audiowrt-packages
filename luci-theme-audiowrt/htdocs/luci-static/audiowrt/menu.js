(function() {
	'use strict';

	function directSubmenu(li) {
		for (var i = 0; i < li.children.length; i++) {
			if (li.children[i].tagName === 'UL') return li.children[i];
		}
		return null;
	}

	function directAnchor(li) {
		for (var i = 0; i < li.children.length; i++) {
			if (li.children[i].tagName === 'A') return li.children[i];
		}
		return null;
	}

	function normalizePath(url) {
		try {
			return new URL(url, window.location.href).pathname.replace(/\/+$/, '');
		}
		catch (e) {
			return '';
		}
	}

	function markCurrent(menu) {
		var current = window.location.pathname.replace(/\/+$/, '');
		var links = menu.querySelectorAll('li > ul a[href]');
		var best = null;
		var bestLen = -1;

		for (var i = 0; i < links.length; i++) {
			var path = normalizePath(links[i].href);
			if (!path) continue;
			if (current === path || current.indexOf(path + '/') === 0) {
				if (path.length > bestLen) {
					best = links[i];
					bestLen = path.length;
				}
			}
		}

		if (!best) return;
		var subitem = best.parentNode;
		if (subitem) subitem.classList.add('aw-current');
		var submenu = subitem && subitem.parentNode;
		var top = submenu && submenu.parentNode;
		if (top && top.parentNode === menu)
			top.classList.add('aw-expanded');
	}

	function init() {
		var menu = document.getElementById('topmenu');
		if (!menu || menu.dataset.awAccordion === '1') return;
		menu.dataset.awAccordion = '1';

		for (var i = 0; i < menu.children.length; i++)
			menu.children[i].classList.remove('aw-expanded');

		markCurrent(menu);

		menu.addEventListener('click', function(ev) {
			var anchor = ev.target.closest ? ev.target.closest('a') : null;
			if (!anchor || !menu.contains(anchor)) return;

			/* Submenu links keep normal LuCI navigation. */
			var item = anchor.parentNode;
			if (!item || item.parentNode !== menu || directAnchor(item) !== anchor)
				return;

			var submenu = directSubmenu(item);
			if (!submenu) return;
			ev.preventDefault();

			/* Clicking the already-open group keeps it open. */
			if (item.classList.contains('aw-expanded')) return;

			for (var j = 0; j < menu.children.length; j++)
				menu.children[j].classList.remove('aw-expanded');
			item.classList.add('aw-expanded');
		});
	}

	if (document.readyState === 'loading')
		document.addEventListener('DOMContentLoaded', init);
	else
		init();
})();
