Guard
---------------

Guard is connect middleware that short circuits request handling if it can send a 304 Not Modified response.
Intended to be used with reverse proxies like Varnish.

Contributing
-------------

```
$ git clone https://github.com/goodeggs/connect-guard && cd connect-guard
$ npm install
$ npm test
```