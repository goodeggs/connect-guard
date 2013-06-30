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

  expired: (cacheEntry, ttl) ->
    # Explicitly set, expire on ttl
    if ttl >=0
      expiresAt = cacheEntry.createdAt.valueOf() + ttl * 1000
      return expiresAt < Date.now()
    # Otherwise use max-age
    return false unless cacheEntry.headers['Cache-Control']?
    cacheControl = parseCacheControl cacheEntry.headers['Cache-Control']
    return false unless (maxAge = cacheControl['max-age'])?
    expiresAt = cacheEntry.createdAt.valueOf() + maxAge * 1000
    expiresAt < Date.now()

  fresh: (requestHeaders, cachedHeaders) ->
    cached = {}
    for key, value of cachedHeaders
      cached[key.toLowerCase()] = value
    fresh(requestHeaders, cached)

  middleware: (options={}) =>
    ttl = options.ttl or options.maxAge or -1 # When to expire our header cache, or based on cached max-age (-1)

    guard = @
    return (req, res, next) ->
      return next() unless req.method is 'GET'

      # Define cacheable response helper
      res.cacheable = ({lastModified, etag, maxAge} = {}) ->
        @set 'Last-Modified', new Date(lastModified).toUTCString() if lastModified?
        @set 'Etag', etag if etag?
        @set 'Cache-Control', "public, max-age=#{maxAge}, must-revalidate" if maxAge?
        delete @_headers['set-cookie'] # Clear cookies so response is cacheable downstream

      # Check response cache
      guard.store.get req.url, (err, cached) ->
        return next(err) if err?

        # Invalidate if checking maxAge and expired
        if cached? and guard.expired(cached, ttl)
          delete req.headers[name] for name in ['if-modified', 'if-none-match']
          guard.invalidate req.url, (err) ->
            guard.emit('error', "Error expiring headers for path '#{req.url}'", err) if err?
        # 304 if last response is still fresh
        else if cached? and guard.fresh(req.headers, cached.headers)
          guard.emit 'hit', req.url, cached
          res.set cached.headers
          res.set 'X-Connect-Guard', 'hit'
          return res.send 304

        guard.emit 'miss', req.url, cached
        res.set 'X-Connect-Guard', 'miss'

        res.cacheable {maxAge: options.maxAge} if options.maxAge?

        # Monkey patch res.send to remove Express-added Etag as it interferes with default Last-Modified behavior
        expressAddedEtag = false
        send = res.send
        res.send = ->
          etagBeforeSend = @get('Etag')
          send.apply res, arguments
          expressAddedEtag = @get('Etag') isnt etagBeforeSend

        # Monkey patch res.end to store cache headers
        end = res.end
        res.end = ->
          # Don't cache headers if not a 2xx response
          # 2xx or 304 as per rfc2616 14.26
          unless (@statusCode >= 200 and @statusCode < 300) or 304 == @statusCode
            return end.apply res, arguments

          # Set Last-Modified if no Etag/Last-Modified header present
          unless @get('Last-Modified')? or (@get('Etag')? and expressAddedEtag)
            @cacheable lastModified: cached?.headers['Last-Modified'] or Date.now()

          # Send response
          end.apply res, arguments

          # Cache response headers
          headers = {}
          for name in ['Last-Modified', 'Etag', 'Cache-Control']
            headers[name] = @get(name) if @get(name)?
          if Object.keys(headers).length
            guard.store.set req.url, {createdAt: new Date(), headers}, (err) ->
              return guard.emit('error', "Error storing headers for path '#{req.url}'", err) if err?
              guard.emit('add', req.url, headers)

        next()

module.exports = guard = new Guard(store: new MemoryStore())
guard.Guard = Guard
guard.MemoryStore = MemoryStore