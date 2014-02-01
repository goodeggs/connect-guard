Guard [![NPM version](https://badge.fury.io/js/connect-guard.png)](http://badge.fury.io/js/connect-guard) [![Build Status](https://travis-ci.org/goodeggs/connect-guard.png)](https://travis-ci.org/goodeggs/connect-guard)
============

Guard is connect middleware that short circuits request handling if it can send a 304 Not Modified response.
Intended to be used with reverse proxies like Varnish.

Status
------------

Work in-progress. Hold off for a bit.

Stores
------
Guard can store request and response information wherever you like.  In memory is the default.  If your site hosts lots of unique URLs, a DB is probably a better choice.  Choose one of the following stores, or [write your own](docs/writing_a_store.md).

- [MemoryStore](src/memory_store.coffee) - the default
- [MongoGuardStore](https://github.com/goodeggs/mongo-guard-store) - backed by MongoDB

Contributing
-------------

```
$ git clone https://github.com/goodeggs/connect-guard && cd connect-guard
$ npm install
$ npm test
```

