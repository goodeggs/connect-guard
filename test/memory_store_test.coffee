expect = require 'expect.js'
require 'coffee-errors'
{MemoryStore} = require '../'

describe 'MemoryStore', ->
  {store} = {}
  beforeEach ->
    store = new MemoryStore()

  describe '::set', ->
    describe 'given a url and response headers', ->
      beforeEach (done) ->
        store.set '/users',
          createdAt: new Date()
          headers:
            Etag: '123'
          , done

      it 'saves the response headers for future requests for this url', (done) ->
        store.get '/users', (err, cached) ->
          expect(cached.headers).to.be.ok()
          done(err)

    describe 'given a request url, varied request headers, and response headers', ->
      beforeEach (done) ->
        store.set {
          url: '/users'
          'user-agent': 'chrome'
        }, {
          createdAt: new Date()
          headers:
            Etag: '123'
        }, done

      it 'saves the response headers for future requests for this url and header combination', (done) ->
        store.get url: '/users', 'user-agent': 'chrome', (err, cached) ->
          expect(cached.headers).to.be.ok()
          done(err)

      it 'is stored separetly from other header permuatations for the same url', (done) ->
        store.set {
          url: '/users'
          'user-agent': 'iOS'
        }, {
          createdAt: new Date()
          headers:
            Etag: '456'
        }, (err) ->
          store.get url: '/users', 'user-agent': 'chrome', (err, cached) ->
            expect(cached.headers.Etag).to.be '123'
            done(err)

  describe '::get', ->
    describe 'given the url of a previously cached response', ->
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

    describe 'given a url with no cached response', ->
      it 'returns undefined', (done) ->
        store.get '/users', (err, cached) ->
          expect(cached).to.be undefined
          done(err)

  describe '::delete', ->
    describe 'given the url of a previously cached response', ->
      beforeEach (done) ->
        store.set '/users',
          createdAt: new Date()
          headers:
            Etag: '123'
          , done

      it 'dumps the cached response for that url', (done) ->
        store.delete '/users', (err, cached) ->
          store.get '/users', (err, cached) ->
            expect(cached).to.be undefined
            done(err)



