exports.init = (app, db, upload, config, prefix) ->
  # UTIL
  validateApiKey = (req, res, cb = ->) ->
    db.validateApiKey req.header('X-Apikey'), (user) ->
      if user
        cb user
      else
        res.send 401

  recursiveTypeCheck = (proto, obj) ->
    unless obj
      return false
    for k,v of proto
      if typeof(v) is 'string'
        unless typeof(obj[k]) is v
          return false
      else if typeof(v) is 'object'
        unless recursiveTypeCheck(v, obj[k])
          return false
    return true

  validateArguments = (req, res, args) ->
    if recursiveTypeCheck args, req.body
      return true
    else
      res.send 400
      return false

  # direct etherpad interaction
  getEtherpadHTML = (pad, resp) ->
      request.get("http://localhost:#{config.etherpad_internal_port}/api/1/getHTML?apikey=#{config.etherpadAPIKey}&padID=#{pad}")
        .pipe(resp)

  # USER Endpoints
  app.get "#{prefix}/user/whoami", (req, res) ->
    validateApiKey req, res, (user) ->
      res.json {username: user.name}

  app.get "#{prefix}/user/scope", (req, res) ->
    validateApiKey req, res, (user) ->
      res.json {scope: user.scope}

  app.put "#{prefix}/user/scope", (req, res) ->
    validateApiKey req, res, (user) ->
      if validateArguments req, res, {scope: 'number'}
        db.changeScope user.name, req.body.scope
        res.json {scope: req.body.scope}
        #TODO change ws.authenticated.scope

  app.put "#{prefix}/user/scope/latest", (req, res) ->
    validateApiKey req, res, (user) ->
      db.getLatestCtfId (id) ->
        db.changeScope user.name, id
        res.json {scope: id}
        #TODO change ws.authenticated.scope

  # CTF Endpoints

  app.get "#{prefix}/ctfs", (req, res) ->
    validateApiKey req, res, (user) ->
      db.getCTFs (ctfs) ->
        res.json {ctfs: ctfs}

  app.post "#{prefix}/ctfs", (req, res) ->
    validateApiKey req, res, (user) ->
      if validateArguments req, res, {name: 'string'}
        db.addCTF req.body.name, (id) ->
          res.json {ctf: {id: id, name: req.body.name}}

  app.get "#{prefix}/ctfs/:ctf", (req, res) ->
    try
      req.params.ctf = parseInt req.params.ctf
    catch e
      res.send 400
      return
    validateApiKey req, res, (user) ->
      db.getCTFs (ctfs) ->
        candidates = (ctf for ctf in ctfs when ctf.id is req.params.ctf)
        if candidates.length > 0
          res.json {ctf: candidates[0]}
        else
          res.send 404

  app.get "#{prefix}/ctfs/:ctf/challenges", (req, res) ->
    try
      req.params.ctf = parseInt req.params.ctf
    catch e
      res.send 400
      return
    validateApiKey req, res, (user) ->
      db.getChallenges req.params.ctf, (challenges) ->
        challenge.done = new Boolean(challenge.done) for challenge in challenges
        res.json {challenges: challenges}

  app.post "#{prefix}/ctfs/:ctf/challenges", (req, res) ->
    try
      req.params.ctf = parseInt req.params.ctf
    catch e
      res.send 400
      return
    validateApiKey req, res, (user) ->
      validArg = {challenge: {title: 'string', category: 'string', points: 'number'}}
      if validateArguments req, res, validArg
        db.addChallenge req.params.ctf, req.body.challenge.title,
            req.body.challenge.category, req.body.challenge.points, (id) ->
              res.json {challenge:
                id: id
                title: req.body.challenge.title
                category: req.body.challenge.category
                points: req.body.challenge.points
                done: false
              }
              exports.broadcast {type: 'ctfmodification'}, req.params.ctf

  app.get "#{prefix}/ctfs/:ctf/files", (req, res) ->
    try
      req.params.ctf = parseInt req.params.ctf
    catch e
      res.send 400
      return
    validateApiKey req, res, (user) ->
      db.getCTFFiles req.params.ctf, (files) ->
        file.path = "/file/#{file.id}/#{file.name}" for file in files
        res.json {files: files}

  app.post "#{prefix}/ctfs/:ctf/files", (req, res) ->
    validateApiKey req, res, (user) ->
      upload user, 'ctf', req.params.ctf, req, res

  #CHALLENGE Endpoints
  app.get "#{prefix}/challenges/:challenge", (req, res) ->
    try
      req.params.challenge = parseInt req.params.challenge
    catch e
      res.send 400
      return
    validateApiKey req, res, (user) ->
      db.getChallenge req.params.challenge, (challenge) ->
        unless challenge
          res.send 404
          return
        challenge.done = new Boolean challenge.done
        done = ->
          if challenge.filecount isnt undefined and challenge.assigned isnt undefined
            res.json {challenge: challenge}
        db.getChallengeFiles challenge.id, (files) ->
          challenge.filecount = files.length
          done()
        db.listAssignmentsForChallenge challenge.id, (assignments) ->
          challenge.assigned = (a.user for a in assignments)
          done()

  app.put "#{prefix}/challenges/:challenge/assign", (req, res) ->
    try
      req.params.challenge = parseInt req.params.challenge
    catch e
      res.send 400
      return
    validateApiKey req, res, (user) ->
      db.assign user.name, req.params.challenge, ->
        db.listAssignmentsForChallenge req.params.challenge, (assignments) ->
          res.json {assigned: (a.user for a in assignments)}
          exports.broadcast {type: 'assign', subject: req.params.challenge, data: [{name: user.name}, true]}

  app.delete "#{prefix}/challenges/:challenge/assign", (req, res) ->
    try
      req.params.challenge = parseInt req.params.challenge
    catch e
      res.send 400
      return
    validateApiKey req, res, (user) ->
      db.unassign user.name, req.params.challenge, ->
        db.listAssignmentsForChallenge req.params.challenge, (assignments) ->
          res.json {assigned: (a.user for a in assignments)}
          exports.broadcast {type: 'assign', subject: req.params.challenge, data: [{name: user.name}, false]}

  app.put "#{prefix}/challenges/:challenge/done", (req, res) ->
    try
      req.params.challenge = parseInt req.params.challenge
    catch e
      res.send 400
      return
    validateApiKey req, res, (user) ->
      db.setChallengeDone req.params.challenge, true
      exports.broadcast {type: 'done', subject: req.params.challenge, data: true}
      res.send 204

  app.delete "#{prefix}/challenges/:challenge/done", (req, res) ->
    try
      req.params.challenge = parseInt req.params.challenge
    catch e
      res.send 400
      return
    validateApiKey req, res, (user) ->
      db.setChallengeDone req.params.challenge, false
      exports.broadcast {type: 'done', subject: req.params.challenge, data: false}
      res.send 204

  app.get "#{prefix}/challenges/:challenge/files", (req, res) ->
    try
      req.params.challenge = parseInt req.params.challenge
    catch e
      res.send 400
      return
    validateApiKey req, res, (user) ->
      db.getChallengeFiles req.params.challenge, (files) ->
        file.path = "/file/#{file.id}/#{file.name}" for file in files
        res.json {files: files}

  app.post "#{prefix}/challenges/:challenge/files", (req, res) ->
    validateApiKey req, res, (user) ->
      upload user, 'challenge', req.params.challenge, req, res


  app.get "#{prefix}/challenges/:challenge/html", (req, res) ->
    try
      req.params.challenge = parseInt req.params.challenge
    catch e
      res.send 400
      return
    validateApiKey req, res, (user) ->
      getEtherpadHTML "challenge#{req.params.challenge}" res
