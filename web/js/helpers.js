$(function () {
	H = {hooks: {}};
	H.savedValue = function (parameter, listener) {
		var notify = function(value) {
			if (typeof listener === 'function') {
				listener.call(model.values[parameter], parameter, value);
			} else if (Array.isArray(listener)) {
				for (var i = 0; i < listener.length; i++) {
					listener[i].call(model.values[parameter], parameter, value);
				}
			}
		}
		var val = function(value) {
			if (value === undefined) {
				return model.values[parameter];
			} else if (model.values[parameter] !== value) {
				model.values[parameter] = value;
				console.log(parameter+' has been changed to '+value);
				notify(value);
			}
		}
		val.rerender = function () { notify(model.values[parameter]); };
		val.listener = listener;
		return val
	};

	H.savedArray = function (parameter, listener) {
		var array = H.savedValue(parameter, listener);
		array.push = function () {
			model.values[parameter].push.apply(model.values[parameter], arguments);
		}
		array.search = function (obj) {
			return model.values[parameter].filter(function (e) {
				for (key in obj) {
					if (e[key] != obj[key]) {
						return false;
					}
				}
				return true;
			});
		}
		return array;
	};
	
	H.inlineView = function (template, outletName, acquireData) {
		var fun = function () {
			"use strict"; // null context has to be null, not window
			if (acquireData === undefined) {
				acquireData = function (value) { return value; }
			}
			var outlet = $('[data-outlet="'+outletName+'"]');
			if (outlet.length === 0) {
				console.log("ERROR: outlet "+outletName+" not found");
				return;
			} else if (outlet.length > 1) {
				console.log("WARNING: multiple outlets for "+outletName+" found");
			}
			// detect old outlets to copy
			var innerOutlets = outlet.find('[data-outlet]');
			// fill current outlet with new content
			var data = acquireData(this);
			fun.lastData = data;
			var content = Handlebars.compile(template)(data);
			if (fun.postRenderHook.call(outlet, content) === false) return
			outlet.html(content);
			fun.postReplaceHook.call(outlet, data);
			// detect newly inserted outlets that are already rendered outside
			outlet.find('[data-outlet]').each(function () {
				// if not one of the old outlets
				if (!innerOutlets.is($(this))) {
					var self = $(this);
					var name = self.attr('data-outlet');
					$('[data-outlet="'+name+'"]').each(function () {
						// outlet must not be inside the current outlet
						if ($(this).parent().closest('[data-outlet]').get(0) != outlet.get(0)) {
							// copy content of these outlets
							self.html($(this).html());
						}
					});
				}
			});
			// copy content of old inner outlets into newly created outlets
			innerOutlets.each(function () {
				var parentOutlet = $(this).parent().closest('[data-outlet]');
				if (parentOutlet.length === 0) {
					var innerOutletName = $(this).attr('data-outlet');
					var newOutlet = outlet.find('[data-outlet="'+innerOutletName+'"]');
					newOutlet.html($(this).html());
				}
			});
		}
		fun.postRenderHook = function () {};
		fun.postReplaceHook = function () {};
		return fun;
	};
	H.view = function (templateName, outletName, acquireData) {
		var template = $('script[data-template="'+templateName+'"]').html();
		if (template === undefined) {
			console.log("ERROR: template "+templateName+" not found!");
			return;
		}
		return H.inlineView(template, outletName, acquireData);
	};
});
