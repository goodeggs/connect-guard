{EventEmitter} = require('events')
fresh = require 'fresh'

CACHE = {};

# Next steps:
#   etag
#   respect expires in response
#   cache only needed headers
#   CACHE as external dependency - memory, mongo
module.exports = guard = (invalidator) ->
  return (req, res, next) ->
    if fresh(req.headers, CACHE[req.url] or {})
      guard.emit 'hit', req.url, CACHE[req.url]
      return res.send 304

    guard.emit('miss', req.url, CACHE[req.url]);

    res.cache = ({lastModified} = {}) ->
      @set 'Last-Modified', new Date(lastModified).toUTCString() if lastModified?
      CACHE[req.url] = @_headers;
      if invalidator?
        invalidator.once 'invalidate', ->
          guard.invalidate req.url

    next()

guard.invalidate = (path) ->
  cached = CACHE[path]
  delete CACHE[path];
  @emit 'miss', path, cached

guard.__proto__ = EventEmitter.prototype

guard.on 'hit',         (path, cached) -> console.log("Cache hit", path, cached)
guard.on 'miss',        (path, cached) -> console.log("Cache miss", path, cached);
guard.on 'invalidate',  (path, cached) -> console.log("Cache invalidate", path, cached and 'found' or 'not found');
