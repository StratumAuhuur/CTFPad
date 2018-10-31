express = require 'express'
http = require 'http'
https = require 'https'
httpProxy = require 'http-proxy'
process = require 'child_process'
fs = require 'fs'
mv = require 'mv'
cons = require 'consolidate'
request = require 'request'
querystring = require('querystring')
escape = querystring.escape
WebSocketServer = require('ws').Server
db = require './database.coffee'

# parse config file
config = null
console.log 'checking for config file'
if fs.existsSync 'config.json'
  console.log 'config file found, parsing...'
  try
    config = JSON.parse fs.readFileSync 'config.json'
  catch err
    console.log "error parsing config file: #{err}"
    return
  console.log "config loaded"
else
  console.log "config file not found"
  return

# read oauth configuration file
config.oauth = null
fs.readFile './oauth-config.json', "utf8", (err, data) ->
  if err
    console.log "failed to read OAuth config from file ", err
    return
  else
    config.oauth = JSON.parse(data)
    config.oauth.states = {}

if config.useHTTPS or config.proxyUseHTTPS
  # nodejs' http cannot deal with a chain in one file ->
  # quickfix according to http://stackoverflow.com/a/31629223/1518225
  cert = []
  ca = []
  chain = fs.readFileSync(config.fullchain).toString()
  chain.split('\n').forEach (line) ->
    cert.push line
    if line.match(/-END CERTIFICATE-/)
      ca.push cert.join('\n')
      cert = []
    return

  options =
    key: fs.readFileSync config.keyfile
    cert: fs.readFileSync config.certfile
    ca: ca


app = express()
app.engine 'html', cons.mustache
app.set 'view engine', 'html'
app.set 'views', 'web'
app.use express.bodyParser()
app.use express.cookieParser()

app.use '/js/', express.static 'web/js/'
app.use '/css/', express.static 'web/css/'
app.use '/img/', express.static 'web/img/'
app.use '/doc/', express.static 'web/doc/'


scoreboards = {2: ['test','test2']}

if config.useHTTPS
  server = https.createServer options, app
else 
  server = http.createServer app


validateLogin = (user, pass, cb) ->
  if user and pass then db.checkPassword user, pass, cb
  else setImmediate cb, false

validateSession = (session, cb=->) ->
  if session is undefined then setImmediate cb, false
  else db.validateSession session, cb

app.get '/', (req, res) ->
  validateSession req.cookies.ctfpad, (user) ->
    unless user
        if config.oauth
            res.redirect 302, '/githublogin'
        else
            res.sendfile 'web/login.html'
    else
      user.etherpad_port = config.etherpad_port
      db.getCTFs (ctfs) ->
        user.all_ctfs = ctfs
        n = 0
        user.ctfs = []
        for i in ctfs
          if i.id is user.scope then user.current = i
          if n < 5 or i.id is user.scope
            user.ctfs.push(i)
          n++
        if user.current
          done = -> #have it prepared
          db.getChallenges user.current.id, (challenges) ->
            buf = {}
            for challenge in challenges
              do (challenge) ->
                db.getChallengeFiles challenge.id, (files) ->
                  challenge.filecount = files.length
                  done()
              if buf[challenge.category] is undefined then buf[challenge.category] = []
              buf[challenge.category].push challenge
            user.categories = []
            for k,v of buf
              user.categories.push {name:k, challenges:v}
            doneCount = 0
            done = ->
              doneCount++
              if doneCount is challenges.length+1 # +1 for ctf filecount
                res.render 'index.html', user
          db.getCTFFiles user.current.id, (files) ->
            user.current.filecount = files.length
            done()
        else res.render 'index.html', user

app.post '/login', (req, res) ->
  validateSession req.cookies.ctfpad, (ans) ->
    validateLogin req.body.name, req.body.password, (session) ->
      if session then res.cookie 'ctfpad', session
      res.redirect 303, '/'

app.get '/login', (req, res) -> res.redirect 303, '/'

app.post '/register', (req, res) ->
  if req.body.name and req.body.password1 and req.body.password2 and req.body.authkey
    if req.body.password1 == req.body.password2
      if req.body.authkey == config.authkey
        db.addUser req.body.name, req.body.password1, (err) ->
          if err then res.json {success: false, error: "#{err}"}
          else res.json {success: true}
      else res.json {success: false, error: 'incorrect authkey'}
    else res.json {success: false, error: 'passwords do not match'}
  else res.json {success: false, error: 'incomplete request'}

app.get '/logout', (req, res) ->
    res.clearCookie 'ctfpad'
    if config.oauth
      res.sendfile 'web/login.html'
    else
      res.redirect 303, '/'

app.post '/changepassword', (req, res) ->
  validateSession req.header('x-session-id'), (ans) ->
    if ans
      if req.body.newpw and req.body.newpw2
        if req.body.newpw == req.body.newpw2
          db.changePassword req.header('x-session-id'), req.body.newpw, (err) ->
            if err then res.json {success: false, error: "#{err}"}
            else res.json {success: true}
        else res.json {success: false, error: 'inputs do not match'}
      else res.json {success: false, error: 'incomplete request'}
    else res.json {success: false, error: 'invalid session'}


# read the oauth stuff
# https://developer.github.com/v3/oauth/
# https://developer.github.com/v3/#current-version

newRandomState = (length = 64) ->
    buf = new Buffer length
    fd = fs.openSync '/dev/urandom', 'r'
    fs.readSync fd, buf, 0, length, null
    return buf.toString 'hex'

setOAuthState = (req, res) ->
  #client = req.headers['x-forwarded-for'] || req.connection.remoteAddress
  client = newRandomState(32)
  res.cookie 'ctfpad-oauth-state-id', client
  config.oauth.states[client] = newRandomState()
  # FIXME: if this log is removed then somehow the states object becomes empty
  # sometimes o_O
  console.log "current oauth states", config.oauth.states
  return config.oauth.states[client]

app.get '/githublogin', (req, res) ->
  unless config.oauth
    res.send 500, "Github Login is disabled"
    return
  state = setOAuthState req, res
  url = "https://github.com/login/oauth/authorize?client_id="
  url += escape config.oauth.id
  url += "&redirect_uri="
  url += escape config.oauth.redirecturl
  url += "&scope="
  url += escape config.oauth.scope
  url += "&state="
  url += escape state
  #console.log "redirecting to #{url}"
  res.redirect 302, url

# get json data from github api access
githubApiAccess = (resource, acces_token, cb) ->
  acces_token = escape acces_token
  unless resource[0] == '/'
    resource = "/#{resource}"
  url = "https://api.github.com#{resource}?access_token=#{acces_token}"
  #console.log "performing github api request to #{url}"
  headers = {'User-Agent': 'request', 'Accept': 'application/json'}
  request.get url, headers: headers, (err, eresp, body) ->
    #console.log "result: #{eresp.statusCode} - #{body}"
    if not err and eresp.statusCode == 200
      data = JSON.parse(body)
      cb data, null
    else
      code = -1
      if eresp
        code = eresp.statusCode
      cb {}, {errortype: "request", error: "#{err}", code: code}

checkOAuthState = (req, res) ->
  #console.log "current oauth states", config.oauth.states
  stateIdCookie = 'ctfpad-oauth-state-id'
  clientStateKey = req.cookies[stateIdCookie]
  unless req.query.state
    console.log "checkOAuthState - No state passed for #{clientStateKey} -", req.query
    res.send 500, "No state passed for #{clientStateKey}"
    return
  unless config.oauth.states and config.oauth.states[clientStateKey]
    console.log "checkOAuthState - No state configured for #{clientStateKey} in ", config.oauth.states
    res.send 500, "No state exists for #{clientStateKey}"
    return
  unless req.query.state == config.oauth.states[clientStateKey]
    console.log "checkOAuthState - possible CSRF attempt at #{clientStateKey} - ", req.query, config.oauth.states
    res.send 500, "Github Login failed (state mismatch)"
    return

  delete config.oauth.states[clientStateKey]
  res.clearCookie stateIdCookie

app.get '/oauthcb', (req, res) ->
  unless config.oauth
    res.send 500, "Github Login is disabled"
    return
  unless checkOAuthState req, res
    return
  # get the code from github
  unless req.query.code
    res.send 500, "Github Login failed (missing code)"
    return
  code = req.query.code
  #state = req.params.state
  url = 'https://github.com/login/oauth/access_token'
  data = {client_id: config.oauth.id, \
          client_secret: config.oauth.secret, \
          code: code}
  request.post url, form: data, headers: {Accept: 'application/json'}, (err, eresp, body) ->
    #console.log err, eresp, body
    if not err and eresp.statusCode == 200
      body = JSON.parse(body)
      if body.error
        console.log "Github error: #{body.error} - #{body.error_description}"
        res.send 500, "Github Login failed (no access_token)"
        return
      githubApiAccess "/user", body.access_token, (userdata, err) ->
        user = userdata.login
        #console.log "current github user is #{user} with token #{body.access_token}"
        if not err
          orgs = githubApiAccess "/user/orgs", body.access_token, (orgdata, err) ->
            if not err
              orgs = (o.login for o in orgdata)
              #console.log "user #{user} authenticated with github. orgs: #{orgs}"
              if config.oauth.required_org in orgs
                console.log "logging in user #{user} with github"
                db.userExists user, (result) ->
                  if result
                    db.newSessionFor user, (session) ->
                      if session then res.cookie 'ctfpad', session
                      res.redirect 303, '/'
                  else
                    # create new special github user
                    db.addUserOauth user, (err) ->
                      if err
                        console.log "failed to create new user #{user} (no pw, oauth-only)", err
                        res.send 500, 'Github login failed (new user)'
                      else
                        db.newSessionFor user, (session) ->
                          if session then res.cookie 'ctfpad', session
                          res.redirect 303, '/'
              else
                console.log "oauthcb - #{user} triedto login but is not part of #{config.oauth.required_org}"
                res.send 403, 'Github login failed (not part of org)'
            else
              console.log "oauthcb - failed to get github orgs", err
              res.send 500, 'Github login failed (failed to get orgs)'
        else
          console.log "oauthcb - failed to get current github user", err
          res.send 500, 'Github login failed (couldn\'t get current user)'
    else
      console.log "oauthcb - github unreachable", err
      res.send 500, "Github login failed (unreachable)"

app.post '/newapikey', (req, res) ->
  validateSession req.header('x-session-id'), (ans) ->
    if ans
      db.newApiKeyFor req.header('x-session-id'), (apikey) ->
        res.send apikey
    else res.send 403

app.get '/scope/latest', (req, res) ->
  validateSession req.cookies.ctfpad, (ans) ->
    if ans
      db.getLatestCtfId (id) ->
        db.changeScope ans.name, id
        res.redirect 303, '/'

app.get '/scope/:ctfid', (req, res) ->
  validateSession req.cookies.ctfpad, (ans) ->
    if ans then db.changeScope ans.name, req.params.ctfid
    res.redirect 303, '/'

app.get '/scoreboard', (req, res) ->
  validateSession req.cookies.ctfpad, (ans) ->
    if ans and scoreboards[ans.scope]
      res.render 'scoreboard', scoreboards[ans.scope]
    else res.send ''

app.get '/files/:objtype/:objid', (req, res) ->
  validateSession req.cookies.ctfpad, (ans) ->
    if ans
      objtype = ["ctf", "challenge"].indexOf(req.params.objtype)
      if objtype != -1
        objid = parseInt(req.params.objid)
        if isNaN objid
          res.send 400
          return
        files = db[["getCTFFiles", "getChallengeFiles"][objtype]] objid, (files) ->
          for file in files
            file.uploaded = new Date(file.uploaded*1000).toISOString()
            if file.mimetype
              file.mimetype = file.mimetype.substr 0, file.mimetype.indexOf ';'
          res.render 'files.html', {files: files, objtype: req.params.objtype, objid: req.params.objid}
      else res.send 404
    else res.send 403

app.get '/file/:fileid/:filename', (req, res) ->
  file = "#{__dirname}/uploads/#{req.params.fileid}"
  if /^[a-f0-9A-F]+$/.test(req.params.fileid) and fs.existsSync(file)
    db.mimetypeForFile req.params.fileid, (mimetype) ->
      res.setHeader 'Content-disposition', "attachment; filename=#{req.params.filename}"
      if /html/i.test mimetype
        res.set 'Content-Type', 'application/octet-stream;'
      else
        res.set 'Content-Type', mimetype.trim()
      res.sendfile file
  else res.send 404

app.get '/delete_file/:fileid', (req, res) ->
  validateSession req.cookies.ctfpad, (ans) ->
    if ans
      file = "#{__dirname}/uploads/#{req.params.fileid}"
      if /^[a-f0-9A-F]+$/.test(req.params.fileid) and fs.existsSync(file)
        db.deleteFile req.params.fileid, (err, type, typeId) ->
          unless err
            fs.unlink file, (fserr) ->
              unless fserr
                res.json {success: true}
                fun = db[["getCTFFiles", "getChallengeFiles"][type]]
                fun typeId, (files) ->
                  wss.broadcast JSON.stringify {type: 'filedeletion', data: "#{["ctf", "challenge"][type]}#{typeId}", filecount: files.length}
              else res.json {success: false, error: fserr}
          else res.json {success: false, error: err}
      else res.json {success: false, error: "file not found"}
    else res.send 403

upload = (user, objtype, objid, req, res) ->
  type = ["ctf", "challenge"].indexOf(objtype)
  if type != -1 and req.files.files
    mimetype = null
    process.execFile '/usr/bin/file', ['-bi', req.files.files.path], (err, stdout) ->
      mimetype = unless err then stdout.toString().trim()
      db[["addCTFFile", "addChallengeFile"][type]] objid, req.files.files.name, user.name, mimetype, (err, id) ->
        if err then res.json {success: false, error: err}
        else
          mv req.files.files.path, "#{__dirname}/uploads/#{id}", (err) ->
            if err then res.json {success: false, error: err}
            else
              res.json {success: true, id: id}
              fun = db[["getCTFFiles", "getChallengeFiles"][type]]
              fun parseInt(objid), (files) ->
                wss.broadcast JSON.stringify {type: 'fileupload', data: "#{objtype}#{objid}", filecount: files.length}
  else res.send 400

app.post '/upload/:objtype/:objid', (req, res) ->
  validateSession req.cookies.ctfpad, (user) ->
    if user
      upload user, req.params.objtype, req.params.objid, req, res
    else res.send 403

api = require './api.coffee'
api.init app, db, upload, config, ''

## PROXY INIT
proxyTarget = {host: 'localhost', port: config.etherpad_internal_port}
proxy = httpProxy.createProxyServer {target: proxyTarget}
proxy.on 'error', (err, req, res) ->
  if err then console.log err
  try
    res.send 500
  catch e then return

proxyServer = null
if config.proxyUseHTTPS
  proxyServer = https.createServer options, (req, res) ->
    if req.headers.cookie
      sessid = req.headers.cookie.substr req.headers.cookie.indexOf('ctfpad=')+7, 32
      validateSession sessid, (ans) ->
        if ans
          proxy.web req, res
        else
          res.writeHead 403
          res.end()
    else
      res.writeHead 403
      res.end()
else
  proxyServer = http.createServer (req, res) ->
    if req.headers.cookie
      sessid = req.headers.cookie.substr req.headers.cookie.indexOf('ctfpad=')+7, 32
      validateSession sessid, (ans) ->
        if ans
          proxy.web req, res
        else
          res.writeHead 403
          res.end()
    else
      res.writeHead 403
      res.end()

###proxyServer.on 'upgrade', (req, socket, head) -> ## USELESS SOMEHOW???
  console.log "UPGRADE UPGRADE UPGRADE"
  sessid = req.headers.cookie.substr req.headers.cookie.indexOf('ctfpad=')+7, 32
  validateSession sessid, (ans) ->
    if ans then proxy.ws req, socket, head else res.send 403###

## START ETHERPAD
etherpad = process.spawn 'etherpad-lite/bin/run.sh'
etherpad.stdout.on 'data', (line) ->
  console.log "[etherpad] #{line.toString 'utf8', 0, line.length-1}"
etherpad.stderr.on 'data', (line) ->
  console.log "[etherpad] #{line.toString 'utf8', 0, line.length-1}"

# read etherpad API key and store in config object
fs.readFile 'etherpad-lite/APIKEY.txt', "utf8", (err, data) ->
  if err
    console.log "failed to read etherpad apikey: " + err
  else
    config.etherpadAPIKey = data

wss = new WebSocketServer {server:server}
wss.broadcast = (msg, exclude, scope=null) ->
  this.clients.forEach (c) ->
    unless c.authenticated then return
    if c isnt exclude and (scope is null or scope is c.authenticated.scope)
      try
        c.send msg
      catch e
        console.log e
api.broadcast = (obj, scope) -> wss.broadcast JSON.stringify(obj), null, scope
wss.getClients = -> this.clients
wss.on 'connection', (sock) ->
  sock.on 'close', ->
    if sock.authenticated
      wss.broadcast JSON.stringify {type: 'logout', data: sock.authenticated.name}
  sock.on 'message', (message) ->
    msg = null
    try msg = JSON.parse(message) catch e then return
    unless sock.authenticated 
      if typeof msg is 'string'
        validateSession msg, (ans) ->
          if ans
            sock.authenticated = ans
            # send assignments on auth
            if ans.scope then db.listAssignments ans.scope, (list) ->
              for i in list
                sock.send JSON.stringify {type: 'assign', subject: i.challenge, data: [{name: i.user}, true]}
            # notify all users about new authentication and notify new socket about other users
            wss.broadcast JSON.stringify {type: 'login', data: ans.name}
            wss.getClients().forEach (s) ->
              if s.authenticated and s.authenticated.name isnt ans.name
                sock.send JSON.stringify {type: 'login', data: s.authenticated.name}
    else
      if msg.type and msg.type is 'done'
        clean = {data: Boolean(msg.data), subject: msg.subject, type: 'done'}
        wss.broadcast JSON.stringify(clean), null
        db.setChallengeDone clean.subject, clean.data
      else if msg.type and msg.type is 'assign'
        db.toggleAssign sock.authenticated.name, msg.subject, (hasBeenAssigned) ->
          data = [{name:sock.authenticated.name},hasBeenAssigned]
          wss.broadcast JSON.stringify({type: 'assign', data: data, subject: msg.subject}), null
      else if msg.type and msg.type is 'newctf'
        db.addCTF msg.data.title, (ctfid) ->
          for c in msg.data.challenges
            db.addChallenge ctfid, c.title, c.category, c.points
      else if msg.type and msg.type is 'modifyctf'
        for c in msg.data.challenges
          if c.id
            db.modifyChallenge c.id, c.title, c.category, c.points
          else
            db.addChallenge msg.data.ctf, c.title, c.category, c.points
        wss.clients.forEach (s) ->
          if s.authenticated and s.authenticated.scope is msg.data.ctf
            s.send JSON.stringify {type: 'ctfmodification'}
      else console.log msg

server.listen config.port
proxyServer.listen config.etherpad_port
console.log "listening on port #{config.port} and #{config.etherpad_port}"

filetype = (path,cb = ->) ->
  p = process.spawn 'file', ['-b', path]
  p.stdout.on 'data', (output) ->
    cb output.toString().substr 0,output.length-1
