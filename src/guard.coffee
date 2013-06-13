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
    return next() unless req.method is 'GET'

    guard.store.get req.url, (err, cached) ->
      return next(err) if err?

      if fresh(req.headers, cached or {})
        guard.emit 'hit', req.url, cached
        return res.send 304

      guard.emit 'miss', req.url, cached

      res.cacheable = ({lastModified} = {}) ->
        @set 'Last-Modified', new Date(lastModified).toUTCString() if lastModified?

      end = res.end
      res.end = ->
        end.apply res, arguments
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

module.exports = guard