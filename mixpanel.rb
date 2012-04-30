# This is a class definition from https://mixpanel.com/docs/integration-libraries/ruby

require 'rubygems'
require 'base64'
require 'json'
require 'active_support'

class MixPanel

# A simple function for asynchronously logging to the mixpanel.com API.
# This function requires `curl`.
#
# event: The overall event/category you would like to log this data under
# properties: A hash of key-value pairs that describe the event. Must include 
# the Mixpanel API token as 'token'
#
# See http://mixpanel.com/api/ for further detail.
  def self.track(event, properties={})
    if !properties.has_key?("token")
      raise "Token is required"
    end

    params = {"event" => event, "properties" => properties}
    data = ActiveSupport::Base64.encode64s(JSON.generate(params))
    request = "http://api.mixpanel.com/track/?data=#{data}"

    `curl -s '#{request}' &`
  end
end
