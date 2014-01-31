normalizeKey = (key) ->
  if typeof key is 'string'
    key = url: key
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
      key = normalizeKey key
      cached = @paths[key]
      delete @paths[key]
      callback(null, cached) if callback?

  # Extension to store interface for test convenience
  syncGet: (key) ->
    @paths[normalizeKey key]