#database.coffee
bcrypt = require 'bcrypt-nodejs'
sqlite3 = require 'sqlite3'
fs = require 'fs'

# SQLITE DB
stmts = {}
sql = new sqlite3.Database 'ctfpad.sqlite', ->
  stmts.getUser = sql.prepare 'SELECT name,scope,apikey FROM user WHERE sessid = ?'
  stmts.getUserByApiKey = sql.prepare 'SELECT name,scope FROM user WHERE apikey = ? AND apikey NOT NULL'
  stmts.addUser = sql.prepare 'INSERT INTO user (name,pwhash) VALUES (?,?)'
  stmts.getUserPW = sql.prepare 'SELECT pwhash FROM user WHERE name = ?'
  stmts.insertSession = sql.prepare 'UPDATE user SET sessid = ? WHERE name = ?'
  stmts.voidSession = sql.prepare 'UPDATE user SET sessid = NULL WHERE sessid = ?'
  stmts.getChallenges = sql.prepare 'SELECT id,title,category,points,done FROM challenge WHERE ctf = ? ORDER BY category,points,id'
  stmts.getChallenge = sql.prepare 'SELECT * FROM challenge WHERE id = ?' 
  stmts.addChallenge = sql.prepare 'INSERT INTO challenge (ctf, title, category, points) VALUES (?,?,?,?)'
  stmts.modifyChallenge = sql.prepare 'UPDATE challenge SET title = ?, category = ?, points = ? WHERE id = ?'
  stmts.setDone = sql.prepare 'UPDATE challenge SET done = ? WHERE id = ?'
  stmts.getCTFs = sql.prepare 'SELECT id,name FROM ctf ORDER BY id DESC'
  stmts.addCTF = sql.prepare 'INSERT INTO ctf (name) VALUES (?)'
  stmts.changeScope = sql.prepare 'UPDATE user SET scope = ? WHERE name = ?'
  stmts.isAssigned = sql.prepare 'SELECT COUNT(*) AS assigned FROM assigned WHERE user = ? AND challenge = ?'
  stmts.assign = sql.prepare 'INSERT INTO assigned VALUES (?,?)'
  stmts.unassign = sql.prepare 'DELETE FROM assigned WHERE user = ? AND challenge = ?'
  stmts.changePassword = sql.prepare 'UPDATE user SET pwhash = ? WHERE sessid = ?'
  stmts.getApiKeyFor = sql.prepare 'SELECT apikey FROM user WHERE sessid = ?'
  stmts.setApiKeyFor = sql.prepare 'UPDATE user SET apikey = ? WHERE sessid = ?'
  stmts.listAssignments = sql.prepare 'SELECT assigned.challenge,assigned.user FROM assigned JOIN challenge ON assigned.challenge = challenge.id JOIN user ON assigned.user = user.name WHERE challenge.ctf = ?'
  stmts.listAssignmentsForChallenge = sql.prepare 'SELECT user FROM assigned WHERE challenge = ?'
  stmts.getFiles = sql.prepare 'SELECT id,name,user,uploaded,mimetype FROM file WHERE CASE ? WHEN 1 THEN ctf WHEN 2 THEN challenge END = ?'
  stmts.addFile = sql.prepare 'INSERT INTO file (id, name, user, ctf, challenge, uploaded, mimetype) VALUES (?,?,?,?,?,?,?)'
  stmts.findFile = sql.prepare 'SELECT ctf,challenge FROM file WHERE id = ?'
  stmts.fileMimetype = sql.prepare 'SELECT mimetype FROM file WHERE id = ?'
  stmts.deleteFile = sql.prepare 'DELETE FROM file WHERE id = ?'
  stmts.getLatestCtfId = sql.prepare 'SELECT id FROM ctf ORDER BY id DESC LIMIT 1'

#
# EXPORTS
#
exports.validateSession = (sess, cb = ->) ->
  stmts.getUser.get [sess], H cb

exports.checkPassword = (name, pw, cb = ->) ->
  stmts.getUserPW.get [name], H (row) ->
    unless row then cb false
    else bcrypt.compare pw, row.pwhash, (err, res) ->
      if err or not res then cb false
      else
        sess = newRandomId()
        cb sess
        stmts.insertSession.run [sess, name]

exports.validateApiKey = (apikey, cb) ->
  stmts.getUserByApiKey.get [apikey], H cb
  stmts.getUserByApiKey.reset()

exports.voidSession = (sessionId) -> stmts.voidSession.run [sessionId]

exports.setChallengeDone = (chalId, done) ->
  stmts.setDone.run [(if done then 1 else 0), chalId]

exports.getChallenges = (ctfId, cb = ->) ->
  stmts.getChallenges.all [ctfId], H cb

exports.getChallenge = (challengeId, cb = ->) ->
  stmts.getChallenge.get [challengeId], H cb
  stmts.getChallenge.reset()

exports.addChallenge = (ctfId, title, category, points, cb = ->) ->
  stmts.addChallenge.run [ctfId, title, category, points], (err) ->
    cb(this.lastID)

exports.modifyChallenge = (chalId, title, category, points) ->
  stmts.modifyChallenge.run [title, category, points, chalId]

exports.getCTFs = (cb = ->) ->
  stmts.getCTFs.all [], H cb

exports.addCTF = (title, cb = ->) ->
  stmts.addCTF.run [title], (err) ->
    cb(this.lastID)

exports.changeScope = (user, ctfid) ->
  stmts.changeScope.run [ctfid, user]

exports.toggleAssign = (user, chalid, cb = ->) ->
  stmts.isAssigned.get [user, chalid], H (ans) ->
    if ans.assigned
      exports.unassign user, chalid
      cb false
    else
      exports.assign user, chalid
      cb true
  stmts.isAssigned.reset()

exports.assign = (user, chalid, cb = ->) ->
  stmts.assign.run [user,chalid], cb

exports.unassign = (user, chalid, cb = ->) ->
  stmts.unassign.run [user,chalid], cb

exports.listAssignments = (ctfid, cb = ->) ->
  stmts.listAssignments.all [ctfid], H cb
  stmts.listAssignments.reset()

exports.listAssignmentsForChallenge = (chalId, cb = ->) ->
  stmts.listAssignmentsForChallenge.all [chalId], H cb
  stmts.listAssignmentsForChallenge.reset()

exports.changePassword = (sessid, newpw, cb = ->) ->
  bcrypt.hash newpw, bcrypt.genSaltSync(), null, (err, hash) ->
    if err then cb err
    else
      stmts.changePassword.run [hash, sessid]
      cb false

exports.getApiKeyFor = (sessid, cb = ->) ->
  stmts.getApiKeyFor.get [sessid], H (row) ->
    cb if row then row.apikey else ''
  stmts.getApiKeyFor.reset()

exports.newApiKeyFor = (sessid, cb = ->) ->
  apikey = newRandomId 32
  stmts.setApiKeyFor.run [apikey, sessid]
  setImmediate cb, apikey

exports.addUser = (name, pw, cb = ->) ->
  bcrypt.hash pw, bcrypt.genSaltSync(), null, (err, hash) ->
    if err then cb err
    else
      stmts.addUser.run [name, hash], (err, ans) ->
        if err
          cb err
        else
          cb false

exports.getCTFFiles = (id, cb = ->) ->
  stmts.getFiles.all [1, id], H cb
  stmts.getFiles.reset()

exports.getChallengeFiles = (id, cb = ->) ->
  stmts.getFiles.all [2, id], H cb
  stmts.getFiles.reset()

exports.addChallengeFile = (chal, name, user, mimetype, cb = ->) ->
  id = newRandomId(32)
  stmts.addFile.run [id, name, user, null, chal, new Date().getTime()/1000, mimetype], (err, ans) ->
    cb err, id

exports.addCTFFile = (ctf, name, user, mimetype, cb = ->) ->
  id = newRandomId(32)
  stmts.addFile.run [id, name, user, ctf, null, new Date().getTime()/1000, mimetype], (err, ans) ->
    cb err, id

exports.mimetypeForFile = (id, cb = ->) ->
  stmts.fileMimetype.get [id], H ({mimetype: mimetype}) -> cb(mimetype)

exports.deleteFile = (fileid, cb = ->) ->
  stmts.findFile.get [fileid], H ({ctf:ctf, challenge:challenge}) ->
    stmts.deleteFile.run [fileid], (err) ->
      cb err, (if ctf then 0 else 1), (if ctf then ctf else challenge)

exports.getLatestCtfId = (cb = ->) ->
  stmts.getLatestCtfId.get H (row) ->
    stmts.getLatestCtfId.reset ->
      cb(if row isnt undefined then row.id else -1)

#
# UTIL
#
H = (cb=->) ->
  return (err, ans) ->
    if err then console.log err
    else cb ans

newRandomId = (length = 16) ->
    buf = new Buffer length
    fd = fs.openSync '/dev/urandom', 'r'
    fs.readSync fd, buf, 0, length, null
    buf.toString 'hex'

