expect = require 'expect.js'
express = require 'express'
request = require 'supertest'
{EventEmitter} = require 'events'
{MemoryStore} = guard = require '../'

describe 'guard', ->
  {app, expressResponse} = {}
  beforeEach ->
    app = express()
    guard.store = new MemoryStore()

  describe 'with no cache headers in response', ->
    beforeEach ->
      app.use guard()
      app.get '/users', (req, res) ->
        expressResponse = res
        res.send 'Users'

    it 'passes request through middleware chain', (done) ->
      request(app)
        .get('/users')
        .expect(200, 'Users')
        .end (err, res) ->
          expect(guard.store.paths).to.be.empty()
          done(err)

    it 'mixes cacheable into response', (done) ->
      request(app)
        .get('/users')
        .end (err, res) ->
          expect(expressResponse.cacheable).to.be.a Function
          done(err)

  describe 'non-GET requests', ->
    beforeEach ->
      app.use guard()
      app.put '/users', (req, res) ->
        expressResponse = res
        res.send 'Users'

    it 'ignores requests', (done) ->
      request(app)
        .put('/users')
        .expect(200, 'Users')
        .end (err, res) ->
          expect(guard.store.paths).to.be.empty()
          expect(expressResponse.cacheable).to.be undefined
          done(err)

  describe 'with Last-Modified response header', ->
    {lastModified} = {}
    beforeEach ->
      lastModified = new Date().toUTCString()
      app.use guard()
      app.get '/users', (req, res) ->
        res.set 'Last-Modified', lastModified
        res.send 'Users'

    it 'adds response headers to the cache', (done) ->
      request(app)
        .get('/users')
        .expect(200, 'Users')
        .expect('Last-Modified', lastModified)
        .end (err, res) ->
          expect(guard.store.paths).to.have.key '/users'
          expect(guard.store.paths['/users']).to.have.key 'last-modified'
          done(err)

  describe 'with cached response', ->
    {lastModified} = {}

    beforeEach (done) ->
      lastModified = new Date().toUTCString()
      app.use guard()
      app.get '/users', (req, res) ->
        res.cacheable {lastModified}
        res.send 'Users'
      request(app).get('/users').end(done)

    it 'sends 304', (done) ->
      request(app)
        .get('/users')
        .set('If-Modified-Since', lastModified)
        .expect(304)
        .expect('Last-Modified', lastModified)
        .expect('X-Connect-Guard', 'hit')
        .end(done)

  describe 'with non-2xx response', ->
    beforeEach ->
      app.use guard()
      app.get '/users', (req, res) ->
        res.set 'Last-Modified', new Date().toUTCString()
        res.send 404

    it 'does not cache response', (done) ->
      request(app)
        .get('/users')
        .expect(404)
        .end (err, res) ->
          expect(guard.store.paths).to.be.empty()
          done(err)

  describe 'res.cacheable', ->
    {lastModified} = {}
    beforeEach ->
      lastModified = new Date()
      app.use guard()
      app.get '/users', (req, res) ->
        res.cacheable {lastModified}
        res.send 'Users'

    it 'adds response headers to the cache', (done) ->
      request(app)
        .get('/users')
        .expect(200, 'Users')
        .expect('Last-Modified', lastModified.toUTCString())
        .end (err, res) ->
          expect(guard.store.paths).to.have.key '/users'
          expect(guard.store.paths['/users']).to.have.key 'last-modified'
          expect(guard.store.paths['/users']['last-modified']).to.be lastModified.toUTCString()
          done(err)

  describe 'invalidation', ->
    {invalidator} = {}

    beforeEach (done) ->
      invalidator = new EventEmitter()
      app.use guard(invalidator)
      app.get '/users', (req, res) ->
        res.cacheable lastModified: new Date()
        res.send 'Users'
      request(app).get('/users').end (err, res) ->
        expect(guard.store.paths).to.have.key '/users'
        done(err)

    it 'removes entry from response store', (done) ->
      guard.on 'invalidate', ->
        expect(guard.store.paths).to.not.have.key '/users'
        done()
      invalidator.emit 'stale'
