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

	function init() {
		var menu = document.getElementById('topmenu');
		if (!menu || menu.dataset.awAccordion === '1') return;
		menu.dataset.awAccordion = '1';

		for (var i = 0; i < menu.children.length; i++)
			menu.children[i].classList.remove('aw-expanded');

		menu.addEventListener('click', function(ev) {
			var anchor = ev.target.closest ? ev.target.closest('a') : null;
			if (!anchor || !menu.contains(anchor)) return;

			/* Only intercept the direct top-level group link. Submenu links must
			 * retain their normal LuCI navigation behaviour. */
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
