$(function () {
	var route = function (mode) {
		return function (ctf, challenge) {
			if (ctf === undefined) ctf = null;
			if (challenge === undefined) challenge = null;
			if (mode === undefined) mode = null;
			model.currentCtf(ctf);
			model.currentChallenge(challenge);
			model.mode(mode);
		}
	};

	var routes = {
		'/global': route('pad'),
		'/new': route('new'),
		'/:ctf': {
			on: route('pad'),
			'/files': route('files'),
			'/edit': route('edit'),
			'/:challenge': {
				on: route('pad'),
				'/files': route('files')
			}
		}
	};

	var router = Router(routes);
	router.configure({strict: false});
	window.dataReady = function () {
		router.init();
	};
});
