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



