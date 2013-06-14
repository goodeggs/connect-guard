expect = require 'expect.js'
express = require 'express'
request = require 'supertest'
{MemoryStore} = guard = require '../'

describe 'guard', ->
  {app, middleware, expressResponse} = {}
  beforeEach ->
    app = express()
    guard.store = new MemoryStore()
    middleware = guard()

  describe 'with no cache headers in response', ->
    beforeEach ->
      app.use middleware
      app.get '/users', (req, res) ->
        expressResponse = res
        res.send 'Users'

    it 'passes request through middleware chain', (done) ->
      request(app)
        .get('/users')
        .expect(200, 'Users')
        .end (err, res) ->
          expect(guard.store.paths).to.not.have.key '/users'
          done(err)

    it 'mixes cacheable into response', (done) ->
      request(app)
        .get('/users')
        .end (err, res) ->
          expect(expressResponse.cacheable).to.be.a Function
          done(err)

  describe 'non-GET requests', ->
    beforeEach ->
      app.use middleware
      app.put '/users', (req, res) ->
        expressResponse = res
        res.send 'Users'

    it 'ignores requests', (done) ->
      request(app)
        .put('/users')
        .expect(200, 'Users')
        .end (err, res) ->
          expect(expressResponse.cacheable).to.be undefined
          done(err)

  describe 'with Last-Modified response header', ->
    {lastModified} = {}
    beforeEach ->
      lastModified = new Date().toUTCString()
      app.use middleware
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

  describe 'res.cacheable', ->
    {lastModified} = {}
    beforeEach ->
      lastModified = new Date()
      app.use middleware
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