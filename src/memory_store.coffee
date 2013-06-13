module.exports = class MemoryStore
  constructor: ->
    @paths = {}

  set: (path, headers, callback) ->
    process.nextTick =>
      @paths[path] = headers
      callback() if callback?

  get: (path, callback) ->
    process.nextTick =>
      callback(null, @paths[path])

  delete: (path, callback) ->
    process.nextTick =>
      cached = @paths[path]
      delete @paths[path]
      callback(null, cached) if callback?