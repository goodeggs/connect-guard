expect = require 'expect.js'
require 'coffee-errors'
{MemoryStore} = require '../'

describe 'MemoryStore', ->
  {store} = {}
  beforeEach ->
    store = new MemoryStore()

  describe '::set', ->
    describe 'given a path and response headers', ->
      beforeEach (done) ->
        store.set '/users',
          createdAt: new Date()
          headers:
            Etag: '123'
          , done

      it 'saves the response headers for future requests for this path', (done) ->
        store.get '/users', (err, cached) ->
          expect(cached.headers).to.be.ok()
          done(err)

    describe 'given a request path, varied request headers, and response headers', ->
      beforeEach (done) ->
        store.set {
          path: '/users'
          'user-agent': 'chrome'
        }, {
          createdAt: new Date()
          headers:
            Etag: '123'
        }, done

      it 'saves the response headers for future requests for this path and header combination', (done) ->
        store.get path: '/users', 'user-agent': 'chrome', (err, cached) ->
          expect(cached.headers).to.be.ok()
          done(err)

      it 'is stored separetly from other header permuatations for the same path', (done) ->
        store.set {
          path: '/users'
          'user-agent': 'iOS'
        }, {
          createdAt: new Date()
          headers:
            Etag: '456'
        }, (err) ->
          store.get path: '/users', 'user-agent': 'chrome', (err, cached) ->
            expect(cached.headers.Etag).to.be '123'
            done(err)

  describe '::get', ->
    describe 'given the path of a previously cached response', ->
      headers = Etag: '123'
      beforeEach (done) ->
        store.set '/users',
          createdAt: new Date()
          headers: headers
          , done

      it 'returns the headers of the previous response', (done) ->
        store.get '/users', (err, cached) ->
          expect(cached.headers).to.eql headers
          done(err)

    describe 'given a path with no cached response', ->
      it 'returns undefined', (done) ->
        store.get '/users', (err, cached) ->
          expect(cached).to.be undefined
          done(err)

  describe '::delete', ->
    describe 'given the path of a previously cached response', ->
      beforeEach (done) ->
        store.set '/users',
          createdAt: new Date()
          headers:
            Etag: '123'
          , done

      it 'dumps the cached response for that path', (done) ->
        store.delete '/users', (err, cached) ->
          store.get '/users', (err, cached) ->
            expect(cached).to.be undefined
            done(err)



