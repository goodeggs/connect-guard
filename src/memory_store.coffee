normalizeKey = (key) ->
  JSON.stringify key

module.exports = class MemoryStore
  constructor: ->
    @paths = {}

  set: (key, responseHeaders, callback) ->
    process.nextTick =>

      @paths[normalizeKey key] = responseHeaders
      callback() if callback?

  get: (key, callback) ->
    process.nextTick =>
      callback(null, @paths[normalizeKey key])

  delete: (key, callback) ->
    process.nextTick =>
      if key.url? and key.url instanceof RegExp
        cached = []
        for pathString, contents of @paths
          path = JSON.parse(pathString)
          if key.url.test(path.url)
            delete @paths[pathString]
            cached.push contents
      else
        key = normalizeKey key
        cached = @paths[key]
        delete @paths[key]

      callback(null, cached) if callback?

  # Extension to store interface for test convenience
  syncGet: (key) ->
    @paths[normalizeKey key]
