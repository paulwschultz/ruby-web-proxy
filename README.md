Ruby Proxy Server
==============
This is a caching proxy server with threading.
The server takes advantage of the TCPSocket class in Ruby's standard library, handling GET and POST requests only.
Responses to GET requests are cached using a least-recently-used eviction policy.
The cache holds objects up to 1MB in size, and holds a maximum of 10MB total. 
This server does not support the default Keep-Alive feature of HTTP/1.1, and instead modifies the request to HTTP/1.0 and removes Keep-Alive headers


Usage
==============
To run the proxy, you must run the following command and specify a port number:

    ruby proxy.rb <portnumber>

The proxy will start running and will listen for requests on that port.