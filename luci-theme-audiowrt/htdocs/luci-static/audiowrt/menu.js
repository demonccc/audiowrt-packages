(function() {
	'use strict';

	function directSubmenu(li) {
		for (var i = 0; i < li.children.length; i++) {
			var el = li.children[i];
			if (el.tagName === 'UL') return el;
		}
		return null;
	}

	function setupAccordion() {
		var menu = document.getElementById('topmenu');
		if (!menu) return false;

		var items = menu.children;
		for (var i = 0; i < items.length; i++) {
			var li = items[i];
			if (li.tagName !== 'LI' || li.dataset.awAccordion === '1') continue;
			var submenu = directSubmenu(li);
			if (!submenu) continue;

			li.dataset.awAccordion = '1';
			li.classList.remove('open', 'active');
			var trigger = li.querySelector(':scope > a');
			if (!trigger) continue;

			trigger.addEventListener('click', function(ev) {
				var current = this.parentNode;
				var parent = current.parentNode;
				var siblings = parent.children;

				if (current.classList.contains('aw-expanded')) {
					ev.preventDefault();
					return;
				}

				ev.preventDefault();
				for (var j = 0; j < siblings.length; j++)
					siblings[j].classList.remove('aw-expanded');
				current.classList.add('aw-expanded');
			});
		}
		return true;
	}

	function init() {
		if (setupAccordion()) return;
		var tries = 0;
		var timer = setInterval(function() {
			tries++;
			if (setupAccordion() || tries > 40) clearInterval(timer);
		}, 100);
	}

	if (document.readyState === 'loading')
		document.addEventListener('DOMContentLoaded', init);
	else
		init();
})();
