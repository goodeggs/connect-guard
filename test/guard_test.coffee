expect = require 'expect.js'
require 'coffee-errors'
express = require 'express'
request = require 'supertest'
{EventEmitter} = require 'events'
{Guard, MemoryStore} = connectGuard = require '../'

describe 'guard', ->
  describe 'exported function', ->
    it 'is a function', ->
      expect(connectGuard).to.be.a Function

    it 'exposes instance and constructors', ->
      expect(connectGuard.instance).to.be.ok()
      expect(connectGuard.MemoryStore).to.be.ok()
      expect(connectGuard.Guard).to.be.ok()

  describe 'Guard object', ->
    {app, instance, guard, store, expressResponse} = {}
    beforeEach ->
      app = express()
      store = new MemoryStore()
      instance = new Guard(store: store)
      guard = instance.middleware

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
          .expect('X-Connect-Guard', 'miss')
          .end (err, res) ->
            expect(res.header['x-connect-guard']).to.be 'miss'
            expect(store.paths).to.be.empty()
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
            expect(res.header['x-connect-guard']).to.be undefined
            expect(store.paths).to.be.empty()
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
            expect(store.paths).to.have.key '/users'
            expect(store.paths['/users']).to.have.key 'createdAt'
            expect(store.paths['/users'].headers).to.have.key 'last-modified'
            done(err)

    describe 'with Etag response header', ->
      {etag} = {}
      beforeEach ->
        etag = 'abc'
        app.use guard()
        app.get '/users', (req, res) ->
          res.set 'Etag', etag
          res.send 'Users'

      it 'adds response headers to the cache', (done) ->
        request(app)
          .get('/users')
          .expect(200, 'Users')
          .expect('Etag', etag)
          .end (err, res) ->
            expect(store.paths).to.have.key '/users'
            expect(store.paths['/users'].headers).to.have.key 'etag'
            done(err)

    describe 'with cached response', ->

      describe 'with If-Modified-Since request', ->
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
            .end (err, res) ->
              expect(res.header['x-connect-guard']).to.be 'hit'
              done(err)

      describe 'with If-None-Match request', ->
        {etag} = {}
        beforeEach (done) ->
          etag = 'abc'
          app.use guard()
          app.get '/users', (req, res) ->
            res.cacheable {etag}
            res.send 'Users'
          request(app).get('/users').end(done)

        it 'sends 304', (done) ->
          request(app)
            .get('/users')
            .set('If-None-Match', etag)
            .expect(304)
            .expect('Etag', etag)
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
            expect(store.paths).to.be.empty()
            done(err)

    describe 'res.cacheable', ->
      {requested} = {}
      beforeEach ->
        app.use guard()

      describe 'lastModified', ->
        {lastModified} = {}
        beforeEach ->
          lastModified = new Date()
          app.get '/users', (req, res) ->
            res.cacheable {lastModified}
            res.send 'Users'
          requested = request(app).get('/users')

        it 'caches response', (done) ->
          requested
            .expect(200, 'Users')
            .expect('Last-Modified', lastModified.toUTCString())
            .end (err, res) ->
              expect(store.paths).to.have.key '/users'
              expect(store.paths['/users'].headers).to.have.key 'last-modified'
              expect(store.paths['/users'].headers['last-modified']).to.be lastModified.toUTCString()
              done(err)

      describe 'etag', ->
        {etag} = {}
        beforeEach ->
          etag = '123'
          app.get '/users', (req, res) ->
            res.cacheable {etag}
            res.send 'Users'
          requested = request(app).get('/users')

        it 'caches response', (done) ->
          requested
            .expect(200, 'Users')
            .expect('Etag', etag)
            .end (err, res) ->
              expect(store.paths).to.have.key '/users'
              expect(store.paths['/users'].headers).to.have.key 'etag'
              expect(store.paths['/users'].headers['etag']).to.be etag
              done(err)

      describe 'maxAge', ->
        beforeEach ->
          app.get '/users', (req, res) ->
            res.cacheable {maxAge: 10}
            res.send 'Users'
          requested = request(app).get('/users')

        it 'sets Cache-Control header', (done) ->
          requested
            .expect(200)
            .expect('Cache-Control', 'public, max-age=10, must-revalidate', done)

      describe 'cookie purging', ->
        beforeEach ->
          app.get '/users', (req, res) ->
            res.cookie('sessionID', 'abc')
            res.cacheable(etag: '123')
            res.send 'Users'
          requested = request(app).get('/users')

        it 'deletes cookie from response', (done) ->
          requested
            .expect(200)
            .end (err, res) ->
              expect(res.headers['set-cookie']).to.be undefined
              done(err)

    describe 'expiration', ->

      describe 'with maxAge param', ->
        {etag} = {}
        beforeEach (done) ->
          etag = '123'
          app.use guard(maxAge: 10)
          app.get '/users', (req, res) ->
            res.set 'Etag', etag
            res.send 'Users'
          request(app).get('/users').end(done)

        it 'hits cache', (done) ->
          request(app)
            .get('/users')
            .set('If-None-Match', etag)
            .expect(304, done)

        describe 'after 10 seconds', ->
          beforeEach ->
            oneMinuteEarlier = new Date(store.paths['/users'].createdAt.valueOf() - 60 * 1000)
            store.paths['/users'].createdAt = oneMinuteEarlier

          it 'misses cache', (done) ->
            request(app)
              .get('/users')
              .set('If-None-Match', etag)
              .expect(200)
              .end (err, res) ->
                expect(res.header['x-connect-guard']).to.be 'miss'
                done(err)

      describe 'with max-age header', ->
        {etag} = {}
        beforeEach (done) ->
          etag = '123'
          app.use guard()
          app.get '/users', (req, res) ->
            res.set 'Etag', etag
            res.set 'Cache-Control', 'public, max-age=10'
            res.send 'Users'
          request(app).get('/users').end(done)

        it 'hits cache', (done) ->
          request(app)
            .get('/users')
            .set('If-None-Match', etag)
            .expect(304, done)

        describe 'after 10 seconds', ->
          beforeEach ->
            oneMinuteEarlier = new Date(store.paths['/users'].createdAt.valueOf() - 60 * 1000)
            store.paths['/users'].createdAt = oneMinuteEarlier

          it 'misses cache', (done) ->
            request(app)
              .get('/users')
              .set('If-None-Match', etag)
              .expect(200)
              .end (err, res) ->
                expect(res.header['x-connect-guard']).to.be 'miss'
                done(err)