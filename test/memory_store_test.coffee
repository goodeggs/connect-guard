expect = require 'expect.js'
require 'coffee-errors'
{MemoryStore} = require '../'

describe 'MemoryStore', ->
  {store} = {}
  beforeEach ->
    store = new MemoryStore()

  describe '::set', ->
    describe 'given request and response info', ->
      beforeEach (done) ->
        store.set {
          url: '/users',
          headers: {}
        }, {
          createdAt: new Date()
          headers:
            Etag: '123'
        }, done

      it 'saves the response info for future matching requests', (done) ->
        store.get {
          url: '/users'
          headers: {}
        }, (err, cached) ->
          expect(cached.headers).to.be.ok()
          done(err)

    describe 'given request info containing varied headers', ->
      beforeEach (done) ->
        store.set {
          url: '/users'
          headers:
            'user-agent': 'chrome'
        }, {
          createdAt: new Date()
          headers:
            Etag: '123'
        }, done

      it 'matches future requests for the same url and header combination', (done) ->
        store.get {
          url: '/users'
          headers:
            'user-agent': 'chrome'
        }, (err, cached) ->
          expect(cached.headers).to.be.ok()
          done(err)

      it 'doesnt match requests from other header permuatations for the same url', (done) ->
        store.set {
          url: '/users'
          headers:
            'user-agent': 'iOS'
        }, {
          createdAt: new Date()
          headers:
            Etag: '456'
        }, (err) ->
          store.get {
            url: '/users'
            headers:
             'user-agent': 'chrome'
          }, (err, cached) ->
            expect(cached.headers.Etag).to.be '123'
            done(err)

  describe '::get', ->
    describe 'given the url of a previously cached response', ->
      headers = Etag: '123'
      beforeEach (done) ->
        store.set {
          url: '/users',
          headers: {}
        }, {
          createdAt: new Date()
          headers: headers
        }, done

      it 'returns the headers of the previous response', (done) ->
        store.get {
          url: '/users'
          headers: {}
        }, (err, cached) ->
          expect(cached.headers).to.eql headers
          done(err)

    describe 'given a url with no cached response', ->
      it 'returns undefined', (done) ->
        store.get {
          url: '/users'
          headers: {}
        }, (err, cached) ->
          expect(cached).to.be undefined
          done(err)

  describe '::delete', ->
    describe 'given the url of a previously cached response', ->
      beforeEach (done) ->
        store.set {
          url: '/users',
          headers: {}
        }, {
          createdAt: new Date()
          headers:
            Etag: '123'
        }, done

      it 'dumps the cached response for that url', (done) ->
        store.delete {
          url: '/users',
          headers: {}
        }, (err, cached) ->
          store.get {
            url: '/users'
            headers: {}
          }, (err, cached) ->
            expect(cached).to.be undefined
            done(err)

      it 'accepts a regexp to match a url', (done) ->
        store.delete {
          url: new RegExp('^/us'),
          headers: {}
        }, (err, cached) ->
          store.get {
            url: '/users',
            headers: {}
          }, (err, cached) ->
            expect(cached).to.be undefined
            done(err)
