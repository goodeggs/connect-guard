{EventEmitter} = require('events')
fresh = require 'fresh'
{parseCacheControl} = require 'connect/lib/utils'
MemoryStore = require './memory_store'

# Next steps:
#   Invalidate cached response based on
#     expires in response
class Guard extends EventEmitter

  constructor: ({store}={}) ->
    @configure store: store or new MemoryStore()
    @setMaxListeners 0

  configure: ({store}={}) ->
    @store = store if store?
    @

  invalidate: (path, callback) ->
    @store.delete path, (err, cached) =>
      @emit 'invalidate', path, cached
      callback(err, cached) if callback?

  expired: (res) ->
    return false unless res?.headers['cache-control']?
    cacheControl = parseCacheControl res?.headers['cache-control']
    return false unless (maxAge = cacheControl['max-age'])?
    expiresAt = res.createdAt.valueOf() + maxAge * 1000
    expiresAt < Date.now()

  middleware: (options={}) =>
    options.expireMaxAge ?= true # Expire our header cache based on max-age

    guard = @
    return (req, res, next) ->
      return next() unless req.method is 'GET'

      # Check response cache
      guard.store.get req.url, (err, cached) ->
        return next(err) if err?

        # Invalidate if checking maxAge and expired
        if cached? and options.expireMaxAge and guard.expired(cached)
          delete req.headers[name] for name in ['if-modified', 'if-none-match']
          guard.invalidate req.url, (err) ->
            guard.emit('error', "Error expiring headers for path '#{req.url}'", err) if err?
        # 304 if last response is still fresh
        else if fresh(req.headers, cached?.headers or {})
          guard.emit 'hit', req.url, cached
          res.set cached.headers
          res.set 'X-Connect-Guard', 'hit'
          return res.send 304

        guard.emit 'miss', req.url, cached
        res.set 'X-Connect-Guard', 'miss'

        res.cacheable = ({lastModified, etag, maxAge} = {}) ->
          @set 'Last-Modified', new Date(lastModified).toUTCString() if lastModified?
          @set 'Etag', etag if etag?
          @set 'Cache-Control', "public, max-age=#{maxAge}, must-revalidate" if maxAge?
          delete @_headers['set-cookie']

        res.cacheable {maxAge: options.maxAge} if options.maxAge?

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

        next()

module.exports = guard = new Guard(store: new MemoryStore())
guard.Guard = Guard
guard.MemoryStore = MemoryStore