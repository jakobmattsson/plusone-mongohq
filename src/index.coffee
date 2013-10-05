request = require 'request'
async = require 'async'

propagate = (onErr, onSucc) -> (err, rest...) -> if err? then onErr(err) else onSucc(rest...)

query = ({ apikey, json, path, method }, callback) ->
  request {
    method: method || 'GET'
    url: 'https://api.mongohq.com/' + path
    json: json || {}
    headers:
      'MongoHQ-API-Token': apikey
  }, (err, res, body) ->
    return callback(err) if err?
    callback(null, body)

hasFreePlanCalledSandbox = (apikey, callback) ->
  query {
    apikey
    path: 'plans'
  }, (err, body) ->
    return callback(err) if err?
    callback(null, body.filter((x) -> x.price == 0 && x.slug == 'sandbox').length == 1)

listDatabases = (apikey, callback) ->
  query {
    apikey
    path: 'databases'
  }, callback

createDatabase = (apikey, name, slug, callback) ->
  query {
    apikey
    path: 'databases'
    method: 'POST'
    json:
      name: name
      slug: slug
  }, callback

deleteDatabase = (apikey, name, callback) ->
  query {
    apikey
    path: 'databases/' + name
    method: 'DELETE'
  }, callback



exports.create = ({ apikey, username, password }) ->

  create: (conf, callback) ->
    minutesToLive = conf.minutesToLive ? 20
    prefix = conf.tag ? 'default'

    if prefix.indexOf('-') != -1
      throw new Error("The tag cannot contain a dash")

    nowTime = new Date()
    now = nowTime.getTime() + 1000 * 60 * minutesToLive
    readableName = nowTime.getMinutes()
    name = prefix + '-' + now + '-' + readableName

    createDatabase apikey, name, 'sandbox', propagate callback, (res) ->
      listDatabases apikey, propagate callback, (dbs) ->

        toPurge = dbs.filter (db) ->
          [pre, timestamp] = db.name.split('-')
          pre == prefix && parseInt(timestamp) < nowTime.getTime()

        async.forEach toPurge, (db, callback) ->
          deleteDatabase(apikey, db.name, callback)
        , propagate callback, ->

          theOne = dbs.filter (x) -> x.name == name

          if theOne.length == 0
            return callback(new Error("Could not find a database with the given name"))
          if theOne.length > 1
            return callback(new Error("Multiple databases found with the same name"))

          callback(null, {
            host: theOne[0].hostname
            port: theOne[0].port
            username: username
            password: password
          })

  destroyAll: (tag, callback) ->
    listDatabases apikey, propagate callback, (dbs) ->
      matches = dbs.filter (db) ->
        parts = db.name.split('-')
        parts.length == 3 && parts[0] == tag

      async.forEach matches, (db, callback) ->
        deleteDatabase(apikey, db.name, callback)
      , callback

  destroy: (connData, callback) ->
    listDatabases apikey, propagate callback, (dbs) ->
      matches = dbs.filter (db) -> db.port == connData.port && db.hostname == connData.host

      if matches.length > 1
        return callback(new Error("Too many matches"))
      if matches.length == 0
        return callback()

      deleteDatabase apikey, matches[0].name, (err, res) ->
        # ta hand om err och res här?
        callback()
