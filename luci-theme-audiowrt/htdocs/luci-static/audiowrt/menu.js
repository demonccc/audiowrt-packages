(function() {
	'use strict';

	function topItemFromTarget(menu, target) {
		var node = target;
		while (node && node !== menu) {
			if (node.tagName === 'LI' && node.parentNode === menu)
				return node;
			node = node.parentNode;
		}
		return null;
	}

	function directSubmenu(li) {
		for (var i = 0; i < li.children.length; i++) {
			var el = li.children[i];
			if (el.tagName === 'UL') return el;
		}
		return null;
	}

	function init() {
		var menu = document.getElementById('topmenu');
		if (!menu || menu.dataset.awAccordion === '1') return;
		menu.dataset.awAccordion = '1';

		/* Start collapsed regardless of whichever item LuCI marked active. */
		for (var i = 0; i < menu.children.length; i++)
			menu.children[i].classList.remove('aw-expanded');

		/* Delegate clicks because LuCI builds/rebuilds menu entries dynamically. */
		menu.addEventListener('click', function(ev) {
			var anchor = ev.target.closest ? ev.target.closest('a') : null;
			if (!anchor || !menu.contains(anchor)) return;

			var item = topItemFromTarget(menu, anchor);
			if (!item) return;
			var submenu = directSubmenu(item);
			if (!submenu) return;

			ev.preventDefault();

			/* Clicking an already expanded group keeps it expanded. */
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
