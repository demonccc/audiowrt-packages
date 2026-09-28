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

		if (!best) {
			for (var j = 0; j < links.length; j++) {
				if (links[j].classList.contains('active') || links[j].parentNode.classList.contains('active')) {
					best = links[j];
					break;
				}
			}
		}

		if (!best) return;
		var subitem = best.parentNode;
		subitem.classList.add('aw-current');
		var submenu = subitem.parentNode;
		var top = submenu && submenu.parentNode;
		if (top && top.parentNode === menu) {
			for (var k = 0; k < menu.children.length; k++)
				menu.children[k].classList.remove('aw-expanded');
			top.classList.add('aw-expanded');
		}
	}

	function init() {
		var menu = document.getElementById('topmenu');
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

		/* LuCI builds the menu after the theme script is loaded. Keep syncing
		 * until the generated active entry is present, and after any rebuild. */
		var queued = false;
		function queueSync() {
			if (queued) return;
			queued = true;
			setTimeout(function() { queued = false; syncCurrent(menu); }, 0);
		}
		new MutationObserver(queueSync).observe(menu, { childList:true, subtree:true });
		queueSync();
		setTimeout(queueSync, 100);
		setTimeout(queueSync, 500);
	}

	if (document.readyState === 'loading')
		document.addEventListener('DOMContentLoaded', init);
	else
		init();
})();
