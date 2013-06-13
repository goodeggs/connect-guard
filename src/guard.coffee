{EventEmitter} = require('events')
fresh = require 'fresh'
MemoryStore = require './memory_store'

# Next steps:
#   only GET requests
#   only cache 200-300 responses
#   etag
#   respect expires in response
#   cache only needed headers
#   CACHE as external dependency - memory, mongo
guard = (invalidators...) ->
  return (req, res, next) ->
    guard.store.get req.url, (err, cached) ->
      return next(err) if err?

      if fresh(req.headers, cached or {})
        guard.emit 'hit', req.url, cached
        return res.send 304

      guard.emit 'miss', req.url, cached

      res.cache = ({lastModified} = {}) ->
        @set 'Last-Modified', new Date(lastModified).toUTCString() if lastModified?
        # Do this on res.end so we can check response code
        guard.store.set req.url, @_headers, (err) ->
          return console.log("Error storing headers for path '#{req.url}'", err) if err?
          for invalidator in invalidators
            invalidator.once 'stale', ->
              guard.invalidate req.url

      next()

guard.invalidate = (path, callback) ->
  @store.delete path, (err, cached) =>
    @emit 'invalidate', path, cached
    callback(err, cached) if callback?

guard.store = new MemoryStore()

guard.__proto__ = EventEmitter.prototype

guard.on 'hit',         (path, cached) -> console.log("Cache hit", path, cached)
guard.on 'miss',        (path, cached) -> console.log("Cache miss", path, cached);
guard.on 'invalidate',  (path, cached) -> console.log("Cache invalidate", path, cached and 'found' or 'not found');

module.exports = guard