expect = require 'expect.js'
require 'coffee-errors'
express = require 'express'
request = require 'supertest'
{EventEmitter} = require 'events'
{Guard, MemoryStore} = connectGuard = require '../'

describe 'guard', ->
  describe 'exported value', ->
    it 'is a Guard instance', ->
      expect(connectGuard).to.be.a Guard

    it 'exposes instance and constructors', ->
      expect(connectGuard.MemoryStore).to.be.ok()
      expect(connectGuard.Guard).to.be.ok()

  describe 'Guard', ->
    {app, instance, guard, store, expressResponse} = {}
    beforeEach ->
      app = express()
      store = new MemoryStore()
      instance = new Guard(store: store)
      guard = instance.middleware

    describe '::middleware', ->

      describe 'cacheable response helper', ->
        beforeEach ->
          app.use guard()
          app.get '/users', (req, res) ->
            expressResponse = res
            res.send 'Users'

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
              cached = store.syncGet '/users'
              expect(cached).to.be.ok()
              expect(cached).to.have.key 'createdAt'
              expect(cached.headers).to.have.key 'Last-Modified'
              done(err)

      describe 'with cookie in response', ->
        beforeEach ->
          app.use guard(maxAge: 60)
          app.get '/users', (req, res) ->
            res.set 'Set-Cookie', 'foo'
            res.send 'Users'

        it 'clears cookie headers', (done) ->
          request(app)
            .get('/users')
            .expect(200, 'Users')
            .end (err, res) ->
              expect(res.headers['set-cookie']).to.be undefined
              expect(res.headers['last-modified']).to.be.ok()
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
              cached = store.syncGet '/users'
              expect(cached).to.be.ok()
              expect(cached.headers).to.have.key 'Etag'
              done(err)

      describe 'with cached response with Vary header', ->
        lastModified =
          chrome: new Date(new Date().valueOf() - 1000 * 60 * 60).toUTCString()
          iOS:    new Date().toUTCString()

        beforeEach (done) ->
          # vary before guard
          app.get '/users', (req, res, next) ->
            res.set 'Vary', 'User-Agent'
            next()
          app.get '/users', guard()
          app.get '/users', (req, res) ->
            userAgent = req.header 'User-Agent'
            res.cacheable lastModified: lastModified[userAgent]
            res.send "Users for #{userAgent}"

          request(app)
            .get('/users')
            .set('User-Agent', 'chrome')
            .expect(200, 'Users for chrome')
            .expect('X-Connect-Guard', 'miss', done)

        describe 'a request with the same values for varied headers', ->
          {requested} = {}
          beforeEach ->
            requested = request(app)
              .get('/users')
              .set('If-Modified-Since', lastModified.chrome)
              .set('User-Agent', 'chrome')

          it 'hits the cache', (done) ->
            requested
              .expect('X-Connect-Guard', 'hit')
              .expect(304, done)

        describe 'a request with different values for varied headers', ->
          {requested} = {}
          beforeEach ->
            requested = request(app)
              .get('/users')
              .set('If-Modified-Since', lastModified.chrome)
              .set('User-Agent', 'iOS')

          it 'warms the cache for the new header values', (done) ->
            requested
              .expect('X-Connect-Guard', 'miss')
              .expect(200, 'Users for iOS', done)

      describe 'with no cache headers in response', ->
        {requested, longBody} = {}
        beforeEach ->
          longBody = 'Users' + (i for i in [0..1000])
          app.use guard()
          app.get '/users', (req, res) ->
            res.send longBody
          requested = request(app).get('/users').expect(200, longBody)

        it 'has etag added by express (for responses over 1024 bytes)', (done) ->
          requested.end (err, res) ->
            expect(res.headers['etag']).to.be.ok()
            done(err)

        it 'adds last-modified header to the response', (done) ->
          requested.end (err, res) ->
            expect(res.headers['last-modified']).to.be.ok()
            done(err)

        it 'sends 304 for next request', (done) ->
          requested.end (err, res) ->
            lastModified = res.headers['last-modified']
            expressEtag = res.headers['etag']
            request(app)
              .get('/users')
              .set('If-Modified-Since', lastModified)
              .set('If-None-Match', expressEtag)
              .expect 304, (err, res) ->
                done(err)

        it 'sends same last-modified value for next stale request 1 minute later', (done) ->
          requested.end (err, res) ->
            lastModified = new Date(new Date(res.headers['last-modified'].valueOf() - 60*1000)).toUTCString()
            cached = store.syncGet '/users'
            cached.headers['Last-Modified'] = lastModified
            store.set '/users', cached, (err) ->
              request(app)
                .get('/users')
                .expect(200, longBody)
                .expect('Last-Modified', lastModified, done)

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
                cached = store.syncGet '/users'
                expect(cached).to.be.ok()
                expect(cached.headers).to.have.key 'Last-Modified'
                expect(cached.headers['Last-Modified']).to.be lastModified.toUTCString()
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
                cached = store.syncGet '/users'
                expect(cached).to.be.ok()
                expect(cached.headers).to.have.key 'Etag'
                expect(cached.headers['Etag']).to.be etag
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

          describe 'after 1 minute', ->
            beforeEach (done) ->
              cached = store.syncGet '/users'
              oneMinuteEarlier = new Date(cached.createdAt.valueOf() - 60 * 1000)
              cached.createdAt = oneMinuteEarlier
              store.set '/users', cached, done

            it 'misses cache', (done) ->
              request(app)
                .get('/users')
                .set('If-None-Match', etag)
                .expect(200)
                .end (err, res) ->
                  expect(res.header['x-connect-guard']).to.be 'miss'
                  done(err)

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

          describe 'after 1 minute', ->
            beforeEach (done) ->
              cached = store.syncGet '/users'
              oneMinuteEarlier = new Date(cached.createdAt.valueOf() - 60 * 1000)
              cached.createdAt = oneMinuteEarlier
              store.set '/users', cached, done

            it 'misses cache', (done) ->
              request(app)
                .get('/users')
                .set('If-None-Match', etag)
                .expect(200)
                .end (err, res) ->
                  expect(res.header['x-connect-guard']).to.be 'miss'
                  done(err)


        describe 'with ttl', ->
          {etag} = {}
          beforeEach (done) ->
            etag = '123'
            app.use guard(maxAge: 10, ttl: 60)
            app.get '/users', (req, res) ->
              res.set 'Etag', etag
              res.send 'Users'
            request(app).get('/users').end(done)

          it 'hits cache', (done) ->
            request(app)
              .get('/users')
              .set('If-None-Match', etag)
              .expect(304, done)

          describe 'after 20 seconds', ->
            beforeEach (done) ->
              cached = store.syncGet '/users'
              twentySecEarlier = new Date(cached.createdAt.valueOf() - 20 * 1000)
              cached.createdAt = twentySecEarlier
              store.set '/users', cached, done

            it 'hits cache', (done) ->
              request(app)
                .get('/users')
                .set('If-None-Match', etag)
                .expect(304, done)

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

          describe 'after 1 minute', ->
            beforeEach (done) ->
              cached = store.syncGet '/users'
              oneMinuteEarlier = new Date(cached.createdAt.valueOf() - 60 * 1000)
              cached.createdAt = oneMinuteEarlier
              store.set '/users', cached, done

            it 'misses cache', (done) ->
              request(app)
                .get('/users')
                .set('If-None-Match', etag)
                .expect(200)
                .end (err, res) ->
                  expect(res.header['x-connect-guard']).to.be 'miss'
                  done(err)

    describe '::invalidate', ->
      beforeEach (done) ->
        app.use guard()
        app.get '/users', (req, res) ->
          res.cacheable {etag: 'abc'}
          res.send 'Users'
        request(app).get('/users').end(done)

      it 'invalidates cache whether something there or not', (done) ->
        instance.invalidate '/users', (err, cached) ->
          expect(cached).to.be.ok()
          instance.invalidate '/users', (err, cached) ->
            expect(cached).to.be undefined
            done(err)

      it 'emits "invalidate" event', (done) ->
        instance.on 'invalidate', (cached) ->
          expect(cached).to.be.ok()
          done()
        instance.invalidate '/users'

