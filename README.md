Ruby Proxy Server
==============
This is a caching proxy server with threading.
The server takes advantage of the TCPSocket class in Ruby's standard library, handling GET and POST requests only.
Responses to GET requests are cached using a least-recently-used eviction policy.
The cache holds objects up to 1MB in size, and holds a maximum of 10MB total.