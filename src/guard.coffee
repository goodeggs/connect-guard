{EventEmitter} = require('events')
fresh = require 'fresh'
MemoryStore = require './memory_store'

# Next steps:
#   Invalidate cached response based on
#     expires in response
#     Cache-Control: max-age in response
#   cacheable strips cookies to enable proxy caching
class Guard extends EventEmitter

  constructor: ({@store}) ->
    @store ?= new MemoryStore()
    @setMaxListeners 0

  invalidate: (path, callback) ->
    @store.delete path, (err, cached) =>
      @emit 'invalidate', path, cached
      callback(err, cached) if callback?

  middleware: (invalidators...) =>
    guard = @
    return (req, res, next) ->
      return next() unless req.method is 'GET'

      # Check response cache
      guard.store.get req.url, (err, cached) ->
        return next(err) if err?

        # 304 if last response is still fresh
        if fresh(req.headers, cached?.headers or {})
          guard.emit 'hit', req.url, cached
          res.set cached.headers
          res.set 'X-Connect-Guard', 'hit'
          return res.send 304

        guard.emit 'miss', req.url, cached
        res.set 'X-Connect-Guard', 'miss'

        res.cacheable = ({lastModified, etag} = {}) ->
          @set 'Last-Modified', new Date(lastModified).toUTCString() if lastModified?
          @set 'Etag', etag if etag?

        # Don't cache headers if not a 2xx response
        end = res.end
        res.end = ->
          end.apply res, arguments
          # 2xx or 304 as per rfc2616 14.26
          return unless (@statusCode >= 200 and @statusCode < 300) or 304 == @statusCode

          # Cache headers
          headers = {}
          for name in ['expires', 'last-modified', 'etag', 'cache-control']
            headers[name] = @_headers[name] if @_headers[name]?
          if Object.keys(headers).length
            guard.store.set req.url, {createdAt: new Date(), headers}, (err) ->
              return guard.emit('error', "Error storing headers for path '#{req.url}'", err) if err?
              guard.emit('add', req.url, headers)
              # Register invalidators
              for invalidator in invalidators
                invalidator.once 'stale', ->
                  guard.invalidate req.url

        next()

instance = new Guard(store: new MemoryStore())
module.exports = guard = instance.middleware
guard.instance = instance
guard.store = instance.store
guard.Guard = Guard
guard.MemoryStore = MemoryStore