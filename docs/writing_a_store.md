Writing a Store
===============

Check out [MemoryStore](../src/memory_store.coffee) for a reference implementation.

Stores remember just enough information about requests and responses to decide if a 304 response is appropriate.

Most methods operate on these simplified representations of requests:
``` js
requestInfo = {
  url: '/beep?q=boop',
  headers: {
    requestHeader1: '...',
    requestHeader2: '...',
    ...
  }
}
```
and responses:
```js
responseInfo = {
  createdAt: 1391198819652, // milliseconds since epoch
  headers: {
    responseHeader1: '...',
    responseHeader2: '...',
    ...
  }
}
```
Stores can assume the `headers` key in reqeust and response info will always map to an object, but that object may be empty.

Stores must implement at least the following methods:

`set(requestInfo, responseInfo, callback(err))`

`get(requestInfo, callback(err, responseInfo))`

`delete(requestInfo, callback(err, count))`
Delete should support a regular expression as the `requestInfo.url` to clear many urls at once.
