{EventEmitter} = require('events')
fresh = require 'fresh'
MemoryStore = require './memory_store'

# Next steps:
#   etag
#   respect expires in response
#   respect and pass through Cache-Control: max-age in response
#   cacheable strips cookies
#   set X-Connect-Guard: hit/miss
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
        # 2xx or 304 as per rfc2616 14.26
        return unless (@statusCode >= 200 and @statusCode < 300) or 304 == @statusCode

        headers = {}
        for name in ['expires', 'last-modified', 'etag', 'cache-control']
          headers[name] = @_headers[name] if @_headers[name]?
        if Object.keys(headers).length
          guard.store.set req.url, headers, (err) ->
            return guard.emit('error', "Error storing headers for path '#{req.url}'", err) if err?
            guard.emit('add', req.url, headers)
            for invalidator in invalidators
              invalidator.once 'stale', ->
                guard.invalidate req.url

      next()

guard.invalidate = (path, callback) ->
  @store.delete path, (err, cached) =>
    @emit 'invalidate', path, cached
    callback(err, cached) if callback?

guard.MemoryStore = MemoryStore
guard.store = new MemoryStore()

guard.__proto__ = EventEmitter.prototype

module.exports = guard