$(function () {
	model = {values: {}};

	var getCtf = function (data) {
		for (i in model.values.ctfs) {
			if (""+model.values.ctfs[i].id == data) {
				var ctf = model.values.ctfs[i];
				if (ctf.chals === undefined) {
					ctf.chals = {};
					for (j in model.values.challenges) {
						var chal = model.values.challenges[j];
						if (ctf.challenges.indexOf(chal.id) > -1) {
							if (ctf.chals[chal.category] === undefined) {
								ctf.chals[chal.category] = [chal];
							} else {
								ctf.chals[chal.category].push(chal);
							}
						}
					}
				}
				return ctf;
			}
		}
		return {name: 'no CTF chosen'};
	}
	var getChallenge = function (data) {
		var res = model.challenges.search({id: data});
		if (res.length > 0) {
			return res[0];
		} else {
			return null
		}
	}


	var ctfname = H.view('ctfname', 'ctfname', getCtf);
	ctfname.postReplaceHook = function (ctf) {
		$(this).attr('href', '#/'+ctf.id+'/edit');
	};
	model.currentCtf = H.savedValue('currentCtf', [
			H.view('ctf', 'root', getCtf),
			ctfname
	]);
	model.currentChallenge = H.savedValue('currentChallenge', H.view('challenge', 'challenge', getChallenge));

	model.mode = H.savedValue('mode', H.view('mode', 'mode'));
	model.user = H.savedValue('user', H.inlineView('{{.}}', 'user'));

	model.ctfs = H.savedArray('ctfs', H.view('ctflist', 'ctflist'));
	model.challenges = H.savedArray('challenges', function () {});
});
