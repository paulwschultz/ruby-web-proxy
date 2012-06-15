Ruby Proxy Server
==============
This is a caching proxy server with threading.
The server takes advantage of the TCPSocket class in Ruby's standard library and caches tesponses to GET requests are cached using a least-recently-used eviction policy.
The cache holds objects up to 1MB in size, and holds a maximum of 10MB total.

The server also tracks some events using MixPanel, including cache hits and misses, and their corresponding transaction processing times.
To track this data on your own MixPanel account, modify the token constant at the beginning of proxy.rb

The Server handles GET and POST requests only. Also, the proxy does not support the default Keep-Alive feature of HTTP/1.1 and instead modifies the request to HTTP/1.0 and removes Keep-Alive headers.


Usage
==============
To run the proxy, you must run the following command and specify a port number:

    ruby proxy.rb <portnumber>

The proxy will start running and will listen for requests on that port.

About This Proxy
==============
This proxy was written for a programming challenge in fewer than 24 hours.