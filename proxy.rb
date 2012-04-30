 
require 'socket'
require 'thread'
require 'rubygems'
require 'mixpanel'


$MAX_LOAD        = 10000000 # maximum total cache memory
$MAX_OBJECT_SIZE = 1000000  # maximum memory per cache object
$CACHE                      # global variable to store pages
$MIXPANEL_API_TOKEN = "6f0649a0962f2c92d1e491fbba9169fa"

# This class stores basic webpage responses, as well as the
# most recent request time for the page
class CacheEntry
  attr_accessor :url, :response, :timestamp
  def initialize *args
    @url, @response, @timestamp = *args
  end
end

# Caches web page responses and evicts the least recently used 
# pages to avoid exceeding maximum load.
# Implemented using a Hash table that stores responses via url keys
# The Cache makes use of a single semaphor which locks the cache
# on all cache accesses, including both read and write.
class Cache
  attr_accessor :max_load, :max_object_size, :current_load
  @cache
  @semaphor

  # initializes the Cache object with default values
  def initialize *args
    @max_load        = $MAX_LOAD
    @max_object_size = $MAX_OBJECT_SIZE
    @current_load    = 0
    @cache = Hash.new()
    @semaphor = Mutex.new()
  end

  # retrieves the Cache object if it is in the cache 
  # and updates the corresponding timestamp
  # otherwise, returns nil.
  def retrieve (url)
    @semaphor.lock()
    if(@cache.has_key?(url))
      response = @cache[url].response
      @semaphor.unlock()
      update(url, response, Time.now())
      return response
    else
      @semaphor.unlock()
      return nil
    end
    
  end

  # adds this url/response pair to the cache, 
  # or updates the corresponding timestamp if it is already in the cache
  # if page size exceeds the max object size, it is not added to the cache.
  def update (url, response, timestamp)
    
    @semaphor.synchronize(){||
      if @cache.has_key?(url)
        # then this url is already in the cache and we simply update the timestamp
        new_entry = CacheEntry.new(url, response, timestamp)
        @cache[url] = new_entry
      else
        new_entry = CacheEntry.new(url, response, timestamp)
        # ensure that this object is not too large
        return if new_entry.response.bytesize() > max_object_size 
        # remove items from the cache until this new entry fits.
        while @current_load + new_entry.response.bytesize() > max_load do
          evict()
        end
        @current_load = @current_load + new_entry.response.bytesize()
        @cache[url] = new_entry
      end
    }
  end

  # evicts the least recently accessed item.
  def evict
    return if @cache.empty?
    @semaphor.synchronize(){|| 
      keys = @cache.keys
      least_recently_used = keys.first
      @cache.each_pair do |url, response|
        least_recently_used = url if @cache[least_recently_used].timestamp > @cache[url].timestamp
      end
      @current_load = @current_load - @cache[least_recently_used].response.bytesize()
      @cache.delete(least_recently_used)
    }
  end
end

# This class models an HTTP request, along with its
# associated metadata.
# All attributes should be populated upon initialization
# except for the request string, which is constructed upon instantiation.
class Request
  attr_accessor :host, :port, :filename, :url, :headers, :request_type, :request_string
  
  def initialize *args
    @host, @port, @filename, @url, @headers, @request_type = *args
    @request_string = "#{@request_type} #{@filename} HTTP/1.0\r\nHost:#{@headers["Host"]}\r\n"
    
    # first, we must ensure that the Keep-Alive and Proxy-Connection headers
    # do not keep our socket from closing
    @headers.delete("Keep-Alive")
    @headers["Proxy-Connection"] = " Connection: close\r\n"

    @headers.each_pair do |header, value|
      unless header.eql?("Host")
        @request_string << "#{header}:#{value}\r\n"
      end
    end
    @request_string.concat("\r\n")
  end
end

# Starts the web proxy by initializing global variables
# and listening for clients on the given port.
def proxy (port)
  $CACHE = Cache.new()

  # open the server connection so that we can listen
  # in on the given port
  server = TCPServer.open("localhost", port)

  # start listening for requests
  loop do
    Thread.start(server.accept) do |client|
      MixPanel.track("Client Connection Accepted", properties = {
        "token"=>$MIXPANEL_API_TOKEN,
        "Event Time"=>Time.now
      })

      process_transaction(client)
      client.close
    end
  end
end

# given an open connection to a client, this method 
# handles a single incoming request
def process_transaction(client)
  
  # for data analysis, we track the start time of this transaction
  start_time = Time.now()

  request = form_request(client)
  if request.nil?
    MixPanel.track("Request Unsupported", properties = {
      "token"=>$MIXPANEL_API_TOKEN,
      "Event Time"=>Time.now
    })
    client.print("I'm sorry, this proxy does not support that request type.\n") 
    return 0
  end

  # make the request and store response
  # If the request is a GET request, we will search and update the cache.
  if request.request_type.eql?("GET") && cached_entry = $CACHE.retrieve(request.url)
    response = cached_entry
    client.print(response)

    end_time = Time.now()
    MixPanel.track("Cached Request Processed", properties = {
      "token"=>$MIXPANEL_API_TOKEN, 
      "Event Time"=>Time.now, 
      "Url"=>request.url, 
      "Process Time"=>start_time - end_time, 
      "Request Type"=>request.request_type
    })
  else
    response = make_request_and_respond(request, client)
    $CACHE.update(request.url, response, Time.now()) if request.request_type.eql?("GET")
    
    end_time = Time.now()
    MixPanel.track("Uncached Request Processed", properties = {
      "token"=>$MIXPANEL_API_TOKEN, 
      "Event Time"=>Time.now, 
      "Url"=>request.url, 
      "Process Time"=>start_time - end_time, 
      "Request Type"=>request.request_type
    })
  end
end

# given an open connection to a client,
# listens for a request and parses relevent information
# returns nil if the request is malformed, or is not a GET or POST request.
# otherwise, returns a populated Request object.
def form_request(client)
  # read and tokenize the first line
  # we want to parse this line to retrieve the port, hostname, version, and filename
  first_line_tokens = client.gets.split

  # read the headers and store them in a hash
  header_hash = Hash.new()
  
  while next_line = client.gets do
    break if next_line.eql?("\r\n")  
    # we expect this line to be of the form (header): (header value)
    first_colon_index = next_line.index(":")
    unless first_colon_index.nil?
      header_hash[next_line[0..first_colon_index-1]] = next_line[first_colon_index+1..next_line.length - 1]
    end
  end

  #populate our metadata with temporary values
  port     = 80
  version  = ""
  filename = "/"
  request_type = first_line_tokens[0]
  
  if (!first_line_tokens[0].eql?("GET") && !first_line_tokens[0].eql?("POST"))
    # then this is not a GET or POST request, and we return nil
    return nil
 else
    # then this is a GET or POST request, and we will parse out the
    # port, hostname, version, and filename associated with this request

    # the rest of our attributes can be parsed from the second token, and
    # the token should be of the form: http://(hostname)(:port)/(filename)
    #                  or of the form: /(filename)
    url = first_line_tokens[1]
    # ignore the prefix
    url = url.split("//")[1]

    # now, extract the hostname and port
    first_slash_index = url.index("/")
    first_colon_index = url.index(":")
    if first_colon_index.nil? || first_colon_index>first_slash_index
      # then the port was not specified. Default to 80
      port = 80
      # then the hostname is the substring up to the first slash, or it
      # is instead specified in a header
      if first_slash_index > 0
        header_hash["Host"] = url[0..first_slash_index-1]
      end
    else first_colon_index<first_slash_index
      # then the port is specified
      port     = url[first_colon_index+1..first_slash_index-1]
      header_hash["Host"] = url[0..first_colon_index-1]
    end
    
    # extract the filename from the url
    filename = url[first_slash_index..url.length-1]
  end
  return Request.new(header_hash["Host"], port, filename, url, header_hash, request_type)
end

# Given a valid request object and an open client socket,
# opens a connection to the desired host, makes a request,
# and serves that request to the client.
# This method does not cache the response, but returns the
# response string so that it may be cached.
def make_request_and_respond(request, client)
  socket = TCPSocket.open(request.host, request.port)

  socket.print(request.request_string)
  response = ""
 
  while next_kilobyte = socket.read(1000) do
    unless next_kilobyte.nil?
      response << next_kilobyte
      client.print(next_kilobyte)
    end
  end
  socket.close()
  return response
end


##########################
# Run the proxy!         #
##########################
if(ARGV.empty?)
  puts("Proper usage: ruby proxy.rb port_number")
else
  proxy(ARGV[0])
end
